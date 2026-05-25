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

    nonisolated func captureSelectedRegion() async throws -> Data {
        let rect = try await RegionSelectionOverlay.selectRegion()
        try Task.checkCancellation()
        try await Task.sleep(nanoseconds: 120_000_000)

        return try await capturePNGData(in: rect)
    }

    nonisolated private func capturePNGData(in rect: CGRect) async throws -> Data {
        let cgImage = try await captureDisplayImage(in: rect)
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw ScreenshotCaptureError.pngEncodingFailed
        }

        return data
    }

    nonisolated private func captureDisplayImage(in rect: CGRect) async throws -> CGImage {
        try await ensureScreenCaptureAccess()

        let shareableContent = try await loadShareableContent()
        let screenRegion = try await screenRegion(for: rect)
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

        let filter = SCContentFilter(display: targetDisplay, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = sourceRect
        configuration.width = Int(sourceRect.width * CGFloat(filter.pointPixelScale))
        configuration.height = Int(sourceRect.height * CGFloat(filter.pointPixelScale))
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

    nonisolated private func ensureScreenCaptureAccess() async throws {
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

    nonisolated private func loadShareableContent() async throws -> SCShareableContent {
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

    nonisolated private func screenRegion(for rect: CGRect) async throws -> ScreenCaptureRegion {
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

    nonisolated private func sourceRect(for region: ScreenCaptureRegion) -> CGRect {
        ScreenCaptureCoordinateConverter.sourceRect(for: region)
    }

    nonisolated private func display(
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
