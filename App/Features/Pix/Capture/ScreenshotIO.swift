import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers

protocol ScreenshotPasteboardService {
    func writePNGData(_ data: Data) throws
}

protocol ScreenshotFileSaving {
    func savePNGData(_ data: Data, suggestedFileName: String) throws
}

enum ScreenshotCaptureError: LocalizedError, Equatable {
    case cancelled
    case permissionDenied
    case missingEntitlements
    case displayNotFound
    case timedOut
    case unavailable
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .cancelled:
            nil
        case .permissionDenied:
            "无法读取屏幕内容。请在系统设置中允许 ClipPixTran 录制屏幕，授权后重启应用再试。"
        case .missingEntitlements:
            "当前构建缺少屏幕录制所需权限配置。请检查 Xcode 的签名和沙盒设置。"
        case .displayNotFound:
            "无法定位要截图的显示器。"
        case .timedOut:
            "截图响应超时，请重试。"
        case .unavailable:
            "无法获取当前屏幕截图。"
        case .pngEncodingFailed:
            "截图已生成，但无法转换为 PNG。"
        }
    }
}

enum ScreenshotPasteboardError: LocalizedError, Equatable {
    case invalidImageData
    case rejected

    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            "无法识别这张截图。"
        case .rejected:
            "无法写入剪贴板。"
        }
    }
}

enum ScreenshotSaveError: LocalizedError, Equatable {
    case cancelled
    case missingDestination

    var errorDescription: String? {
        switch self {
        case .cancelled:
            nil
        case .missingDestination:
            "未选择保存位置。"
        }
    }
}

struct SystemScreenshotService: ScreenshotService {
    nonisolated func captureMainDisplay() async throws -> Data {
        guard let screenFrame = await MainActor.run(body: { NSScreen.main?.frame }) else {
            throw ScreenshotCaptureError.unavailable
        }

        return try await capturePNGData(in: screenFrame)
    }

    nonisolated func captureSelectedRegion(initialMode: ScreenshotRegionCaptureMode) async throws -> ScreenshotCaptureOutput {
        let snapshots = await captureDisplaySnapshotsBestEffort()
        return try await RegionSelectionOverlay.capture(
            initialMode: initialMode,
            initialSnapshots: snapshots
        ) { rect, excludedWindowIDs in
            try Task.checkCancellation()
            return try await capturePNGData(
                in: rect,
                excludingWindowIDs: excludedWindowIDs
            )
        }
    }

    nonisolated func captureDisplaySnapshotsBestEffort() async -> [ScreenCaptureSnapshot] {
        do {
            return try await captureDisplaySnapshots()
        } catch {
            return []
        }
    }

    nonisolated private func capturePNGData(
        in rect: CGRect,
        excludingWindowIDs: Set<CGWindowID> = []
    ) async throws -> Data {
        let cgImage = try await captureDisplayImage(
            in: rect,
            excludingWindowIDs: excludingWindowIDs
        )
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw ScreenshotCaptureError.pngEncodingFailed
        }

        return data
    }

    nonisolated private func captureDisplayImage(
        in rect: CGRect,
        excludingWindowIDs: Set<CGWindowID>
    ) async throws -> CGImage {
        try await ensureScreenCaptureAccess()

        let shareableContent = try await loadShareableContent()
        let screenRegion = try await screenRegion(for: rect)
        return try await captureDisplayImage(
            in: screenRegion,
            excludingWindowIDs: excludingWindowIDs,
            shareableContent: shareableContent
        )
    }

    nonisolated private func captureDisplaySnapshots() async throws -> [ScreenCaptureSnapshot] {
        try await ensureScreenCaptureAccess()

        if let snapshots = try await captureDisplaySnapshotsWithScreenRectCapture(),
           !snapshots.isEmpty {
            return snapshots
        }

        let shareableContent = try await loadShareableContent()
        let regions = try await screenRegionsForAllScreens()
        var snapshots: [ScreenCaptureSnapshot] = []
        snapshots.reserveCapacity(regions.count)

        for region in regions {
            do {
                let image = try await captureDisplayImage(
                    in: region,
                    excludingWindowIDs: [],
                    shareableContent: shareableContent
                )
                snapshots.append(
                    ScreenCaptureSnapshot(
                        screenFrame: region.screenFrame,
                        displayID: region.displayID,
                        image: image
                    )
                )
            } catch {
                continue
            }
        }

        return snapshots
    }

    nonisolated private func captureDisplaySnapshotsWithScreenRectCapture() async throws -> [ScreenCaptureSnapshot]? {
        let regions = try await screenRegionsForAllScreens()
        guard !regions.isEmpty else {
            return nil
        }

        var snapshots: [ScreenCaptureSnapshot] = []
        snapshots.reserveCapacity(regions.count)

        for region in regions {
            do {
                let image = try await captureScreenRectImage(in: region.rect)
                snapshots.append(
                    ScreenCaptureSnapshot(
                        screenFrame: region.screenFrame,
                        displayID: region.displayID,
                        image: image
                    )
                )
            } catch {
                return nil
            }
        }

        return snapshots
    }

    nonisolated private func captureScreenRectImage(in rect: CGRect) async throws -> CGImage {
        let configuration = SCScreenshotConfiguration()
        configuration.showsCursor = false
        configuration.dynamicRange = .sdr

        return try await withCheckedThrowingContinuation { continuation in
            let continuationBox = ScreenshotContinuationBox(continuation)
            let timeoutTask = Task.detached(priority: .userInitiated) {
                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                } catch {
                    return
                }

                continuationBox.resume(.failure(ScreenshotCaptureError.timedOut))
            }

            SCScreenshotManager.captureScreenshot(
                rect: rect.standardized,
                configuration: configuration
            ) { output, error in
                timeoutTask.cancel()

                if let image = output?.sdrImage {
                    continuationBox.resume(.success(image))
                } else if let error {
                    continuationBox.resume(.failure(mapCaptureError(error)))
                } else {
                    continuationBox.resume(.failure(ScreenshotCaptureError.unavailable))
                }
            }
        }
    }

    nonisolated private func captureDisplayImage(
        in screenRegion: ScreenCaptureRegion,
        excludingWindowIDs: Set<CGWindowID>,
        shareableContent: SCShareableContent
    ) async throws -> CGImage {
        let targetDisplay = try display(
            matching: screenRegion.displayID,
            in: shareableContent.displays
        )
        let sourceRect = sourceRect(for: screenRegion)

        guard !sourceRect.isNull,
              sourceRect.width > 0,
              sourceRect.height > 0 else {
            throw ScreenshotCaptureError.unavailable
        }

        let excludedWindows = shareableContent.windows.filter { window in
            excludingWindowIDs.contains(window.windowID)
        }
        let filter = SCContentFilter(display: targetDisplay, excludingWindows: excludedWindows)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = sourceRect
        configuration.width = max(Int(sourceRect.width * CGFloat(filter.pointPixelScale)), 1)
        configuration.height = max(Int(sourceRect.height * CGFloat(filter.pointPixelScale)), 1)
        configuration.showsCursor = false
        configuration.queueDepth = 1

        return try await withCheckedThrowingContinuation { continuation in
            let continuationBox = ScreenshotContinuationBox(continuation)
            let timeoutTask = Task.detached(priority: .userInitiated) {
                do {
                    try await Task.sleep(nanoseconds: 4_000_000_000)
                } catch {
                    return
                }

                continuationBox.resume(.failure(ScreenshotCaptureError.timedOut))
            }

            SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            ) { image, error in
                timeoutTask.cancel()

                if let image {
                    continuationBox.resume(.success(image))
                } else if let error {
                    continuationBox.resume(.failure(mapCaptureError(error)))
                } else {
                    continuationBox.resume(.failure(ScreenshotCaptureError.unavailable))
                }
            }
        }
    }

    nonisolated private func screenRegionsForAllScreens() async throws -> [ScreenCaptureRegion] {
        try await MainActor.run {
            try NSScreen.screens.map { screen in
                guard let displayID = screen.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")
                ] as? CGDirectDisplayID else {
                    throw ScreenshotCaptureError.displayNotFound
                }

                return ScreenCaptureRegion(
                    rect: screen.frame.standardized,
                    screenFrame: screen.frame,
                    displayID: displayID
                )
            }
        }
    }

    nonisolated func ensureScreenCaptureAccess() async throws {
        if CGPreflightScreenCaptureAccess() {
            return
        }

        let didGrantAccess = await MainActor.run {
            CGRequestScreenCaptureAccess()
        }

        guard didGrantAccess || CGPreflightScreenCaptureAccess() else {
            throw ScreenshotCaptureError.permissionDenied
        }
    }

    nonisolated func loadShareableContent() async throws -> SCShareableContent {
        try await withCheckedThrowingContinuation { continuation in
            SCShareableContent.getExcludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            ) { content, error in
                if let content {
                    continuation.resume(returning: content)
                } else if let error {
                    continuation.resume(throwing: mapCaptureError(error))
                } else {
                    continuation.resume(throwing: ScreenshotCaptureError.unavailable)
                }
            }
        }
    }

    nonisolated func screenRegion(for rect: CGRect) async throws -> ScreenCaptureRegion {
        try await MainActor.run {
            let normalizedRect = rect.standardized
            guard let screen = NSScreen.screens.max(by: { first, second in
                first.frame.intersection(normalizedRect).area < second.frame.intersection(normalizedRect).area
            }),
            screen.frame.intersects(normalizedRect) else {
                throw ScreenshotCaptureError.displayNotFound
            }

            guard let displayID = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? CGDirectDisplayID else {
                throw ScreenshotCaptureError.displayNotFound
            }

            return ScreenCaptureRegion(
                rect: normalizedRect.intersection(screen.frame),
                screenFrame: screen.frame,
                displayID: displayID
            )
        }
    }

    nonisolated func sourceRect(for region: ScreenCaptureRegion) -> CGRect {
        ScreenCaptureCoordinateConverter.sourceRect(for: region)
    }

    nonisolated func display(
        matching displayID: CGDirectDisplayID,
        in displays: [SCDisplay]
    ) throws -> SCDisplay {
        guard let display = displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenshotCaptureError.displayNotFound
        }

        return display
    }

    nonisolated private func mapCaptureError(_ error: Error) -> Error {
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain {
            switch nsError.code {
            case SCStreamError.userDeclined.rawValue:
                return ScreenshotCaptureError.permissionDenied
            case SCStreamError.missingEntitlements.rawValue:
                return ScreenshotCaptureError.missingEntitlements
            default:
                break
            }
        }

        if !CGPreflightScreenCaptureAccess() {
            return ScreenshotCaptureError.permissionDenied
        }

        return ScreenshotCaptureError.unavailable
    }
}

struct ScreenCaptureRegion: Sendable {
    let rect: CGRect
    let screenFrame: CGRect
    let displayID: CGDirectDisplayID
}

struct ScreenCaptureSnapshot: @unchecked Sendable {
    let screenFrame: CGRect
    let displayID: CGDirectDisplayID
    let image: CGImage

    nonisolated func croppedImage(in rect: CGRect) -> CGImage? {
        guard let pixelRect = cropPixelRect(in: rect) else {
            return nil
        }

        return image.cropping(to: pixelRect)
    }

    nonisolated func pngData(in rect: CGRect) throws -> Data {
        guard let croppedImage = croppedImage(in: rect) else {
            throw ScreenshotCaptureError.unavailable
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ScreenshotCaptureError.pngEncodingFailed
        }

        CGImageDestinationAddImage(destination, croppedImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenshotCaptureError.pngEncodingFailed
        }

        return data as Data
    }

    nonisolated func cropPixelRect(in rect: CGRect) -> CGRect? {
        let screenRect = rect.standardized.intersection(screenFrame)
        guard !screenRect.isNull,
              screenRect.width > 0,
              screenRect.height > 0,
              screenFrame.width > 0,
              screenFrame.height > 0 else {
            return nil
        }

        let sourceRect = ScreenCaptureCoordinateConverter.sourceRect(
            for: ScreenCaptureRegion(
                rect: screenRect,
                screenFrame: screenFrame,
                displayID: displayID
            )
        )
        let scaleX = CGFloat(image.width) / screenFrame.width
        let scaleY = CGFloat(image.height) / screenFrame.height
        let minX = floor(sourceRect.minX * scaleX)
        let minY = floor(sourceRect.minY * scaleY)
        let maxX = ceil(sourceRect.maxX * scaleX)
        let maxY = ceil(sourceRect.maxY * scaleY)
        let pixelRect = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
        .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))

        guard !pixelRect.isNull,
              pixelRect.width > 0,
              pixelRect.height > 0 else {
            return nil
        }

        return pixelRect
    }
}

enum ScreenCaptureCoordinateConverter {
    nonisolated static func sourceRect(for region: ScreenCaptureRegion) -> CGRect {
        CGRect(
            x: region.rect.minX - region.screenFrame.minX,
            y: region.screenFrame.maxY - region.rect.maxY,
            width: region.rect.width,
            height: region.rect.height
        )
    }
}

private extension CGRect {
    nonisolated var area: CGFloat {
        guard !isNull else {
            return 0
        }

        return width * height
    }
}

nonisolated private final class ScreenshotContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<CGImage, Error>?

    init(_ continuation: CheckedContinuation<CGImage, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<CGImage, Error>) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()

        guard let continuation else {
            return
        }

        switch result {
        case .success(let image):
            continuation.resume(returning: image)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

struct SystemScreenshotPasteboardService: ScreenshotPasteboardService {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func writePNGData(_ data: Data) throws {
        guard let image = NSImage(data: data) else {
            throw ScreenshotPasteboardError.invalidImageData
        }

        pasteboard.clearContents()
        let didWrite = pasteboard.writeObjects([image])
        if !didWrite {
            throw ScreenshotPasteboardError.rejected
        }
    }
}

struct SystemScreenshotFileSaver: ScreenshotFileSaving {
    func savePNGData(_ data: Data, suggestedFileName: String) throws {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFileName

        guard panel.runModal() == .OK else {
            throw ScreenshotSaveError.cancelled
        }

        guard let url = panel.url else {
            throw ScreenshotSaveError.missingDestination
        }

        try data.write(to: url, options: [.atomic])
    }
}
