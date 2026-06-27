import AppKit
import AVFoundation
import CoreMedia
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

struct ScreenRecordingOutput: Equatable, Sendable {
    let fileURL: URL
    let createdAt: Date
    let duration: TimeInterval
    let pixelSize: CGSize
    let fileSize: Int64?
}

nonisolated struct ScreenRecordingGIFExportOptions: Equatable, Sendable {
    var frameRate: Double
    var playbackSpeed: Double
    var maximumPixelSize: CGFloat
    var maximumFrameCount: Int

    init(
        frameRate: Double = 10,
        playbackSpeed: Double = 1,
        maximumPixelSize: CGFloat = 960,
        maximumFrameCount: Int = 600
    ) {
        self.frameRate = frameRate
        self.playbackSpeed = playbackSpeed
        self.maximumPixelSize = maximumPixelSize
        self.maximumFrameCount = maximumFrameCount
    }

    var sanitized: ScreenRecordingGIFExportOptions {
        ScreenRecordingGIFExportOptions(
            frameRate: frameRate.finiteValue(defaultValue: 10).lowerBounded(to: 1),
            playbackSpeed: playbackSpeed.clamped(to: 0.25...4),
            maximumPixelSize: maximumPixelSize.clamped(to: 320...1920),
            maximumFrameCount: maximumFrameCount.lowerBounded(to: 1)
        )
    }
}

nonisolated struct ScreenRecordingGIFFramePlan: Equatable, Sendable {
    let outputDuration: TimeInterval
    let requestedFrameCount: Int
    let exportFrameCount: Int
    let frameCount: Int
    let frameDelay: TimeInterval
    let previewedDuration: TimeInterval
    let isTruncated: Bool

    init?(
        sourceDuration: TimeInterval,
        options: ScreenRecordingGIFExportOptions,
        maximumFrameCount: Int? = nil
    ) {
        let options = options.sanitized
        guard sourceDuration.isFinite,
              sourceDuration > 0 else {
            return nil
        }

        let outputDuration = sourceDuration / options.playbackSpeed
        guard outputDuration.isFinite,
              outputDuration > 0 else {
            return nil
        }

        let requestedFrameCount = Self.requestedFrameCount(
            outputDuration: outputDuration,
            frameRate: options.frameRate
        )
        let exportFrameCount = max(
            1,
            min(requestedFrameCount, options.maximumFrameCount)
        )
        let additionalFrameCap = maximumFrameCount?.lowerBounded(to: 1) ?? exportFrameCount
        let frameCount = max(1, min(exportFrameCount, additionalFrameCap))
        let frameDelay = outputDuration / Double(exportFrameCount)

        self.outputDuration = outputDuration
        self.requestedFrameCount = requestedFrameCount
        self.exportFrameCount = exportFrameCount
        self.frameCount = frameCount
        self.frameDelay = frameDelay
        self.previewedDuration = min(outputDuration, Double(frameCount) * frameDelay)
        self.isTruncated = frameCount < exportFrameCount
    }

    private static func requestedFrameCount(
        outputDuration: TimeInterval,
        frameRate: Double
    ) -> Int {
        let requestedFrameCount = (outputDuration * frameRate).rounded(.up)
        guard requestedFrameCount.isFinite,
              requestedFrameCount > 0 else {
            return 1
        }

        guard requestedFrameCount < Double(Int.max) else {
            return Int.max
        }

        return max(Int(requestedFrameCount), 1)
    }
}

struct ScreenRecordingGIFPreview: Identifiable, @unchecked Sendable {
    let id = UUID()
    let frames: [CGImage]
    let frameDelay: TimeInterval
    let previewedDuration: TimeInterval
    let isTruncated: Bool
}

protocol ScreenRecordingSession: AnyObject, Sendable {
    nonisolated var startedAt: Date { get }
    nonisolated func stop() async throws -> ScreenRecordingOutput
    nonisolated func cancel() async
}

protocol ScreenRecordingService: Sendable {
    nonisolated func startSelectedRegionRecording() async throws -> ScreenRecordingSession
    nonisolated func startRecording(
        in selectedRect: CGRect,
        excludingWindowIDs: Set<CGWindowID>
    ) async throws -> ScreenRecordingSession
}

protocol ScreenRecordingFileManaging: Sendable {
    nonisolated func makeRecordingURL(createdAt: Date) throws -> URL
    nonisolated func deleteRecording(named fileName: String)
}

nonisolated struct ScreenRecordingFileStore: ScreenRecordingFileManaging {
    func makeRecordingURL(createdAt: Date = Date()) throws -> URL {
        try FileManager.default.createDirectory(
            at: Self.defaultDirectoryURL,
            withIntermediateDirectories: true
        )

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let timestamp = formatter.string(from: createdAt)
        let fileName = "Pix-\(timestamp)-\(UUID().uuidString.prefix(8)).mp4"
        return Self.defaultDirectoryURL.appending(path: fileName)
    }

    func deleteRecording(named fileName: String) {
        let url = Self.defaultDirectoryURL.appending(path: fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        try? FileManager.default.removeItem(at: url)
    }

    static var defaultDirectoryURL: URL {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        return applicationSupportURL
            .appending(path: "ClipPixTran", directoryHint: .isDirectory)
            .appending(path: "PixRecordings", directoryHint: .isDirectory)
    }
}

enum ScreenRecordingError: LocalizedError, Equatable {
    case missingRecordingFile
    case recordingOutputRejected
    case recordingDidNotFinish
    case gifDestinationFailed
    case gifFrameGenerationFailed

    var errorDescription: String? {
        switch self {
        case .missingRecordingFile:
            L10n.recordingMissingFile
        case .recordingOutputRejected:
            L10n.recordingOutputRejected
        case .recordingDidNotFinish:
            L10n.recordingDidNotFinish
        case .gifDestinationFailed:
            L10n.recordingGIFDestinationFailed
        case .gifFrameGenerationFailed:
            L10n.recordingGIFFrameGenerationFailed
        }
    }
}

nonisolated struct SystemScreenRecordingService: ScreenRecordingService {
    private let fileStore: ScreenRecordingFileManaging
    private let screenshotService = SystemScreenshotService()

    init(fileStore: ScreenRecordingFileManaging = ScreenRecordingFileStore()) {
        self.fileStore = fileStore
    }

    nonisolated func startSelectedRegionRecording() async throws -> ScreenRecordingSession {
        let snapshots = await screenshotService.captureDisplaySnapshotsBestEffort()
        let selectedRect = try await RegionSelectionOverlay.selectRegion(initialSnapshots: snapshots)

        return try await startRecording(in: selectedRect, excludingWindowIDs: [])
    }

    nonisolated func startRecording(
        in selectedRect: CGRect,
        excludingWindowIDs: Set<CGWindowID> = []
    ) async throws -> ScreenRecordingSession {
        try await screenshotService.ensureScreenCaptureAccess()
        let shareableContent = try await screenshotService.loadShareableContent()
        let screenRegion = try await screenshotService.screenRegion(for: selectedRect)
        let targetDisplay = try screenshotService.display(
            matching: screenRegion.displayID,
            in: shareableContent.displays
        )
        let sourceRect = screenshotService.sourceRect(for: screenRegion)
        guard !sourceRect.isNull,
              sourceRect.width > 0,
              sourceRect.height > 0 else {
            throw ScreenshotCaptureError.unavailable
        }

        let filter: SCContentFilter
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            let excludedApplications = shareableContent.applications.filter { application in
                application.bundleIdentifier == bundleIdentifier
            }
            let includedApplicationWindows = shareableContent.windows.filter { window in
                window.owningApplication?.bundleIdentifier == bundleIdentifier
                    && !excludingWindowIDs.contains(window.windowID)
            }
            filter = SCContentFilter(
                display: targetDisplay,
                excludingApplications: excludedApplications,
                exceptingWindows: includedApplicationWindows
            )
        } else {
            let excludedWindows = shareableContent.windows.filter { window in
                excludingWindowIDs.contains(window.windowID)
            }
            filter = SCContentFilter(display: targetDisplay, excludingWindows: excludedWindows)
        }
        filter.includeMenuBar = true

        let pixelScale = CGFloat(filter.pointPixelScale)
        let pixelSize = CGSize(
            width: CGFloat(Self.evenPixelDimension(Int(sourceRect.width * pixelScale))),
            height: CGFloat(Self.evenPixelDimension(Int(sourceRect.height * pixelScale)))
        )

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = sourceRect
        configuration.width = Int(pixelSize.width)
        configuration.height = Int(pixelSize.height)
        configuration.showsCursor = true
        configuration.showMouseClicks = true
        configuration.queueDepth = 8
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.capturesAudio = false
        configuration.captureMicrophone = false
        configuration.streamName = "Pix Recording"

        let createdAt = Date()
        let outputURL = try fileStore.makeRecordingURL(createdAt: createdAt)
        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = outputURL
        recordingConfiguration.outputFileType = .mp4
        recordingConfiguration.videoCodecType = .h264

        let delegate = ScreenRecordingOutputDelegateBox()
        let recordingOutput = SCRecordingOutput(
            configuration: recordingConfiguration,
            delegate: delegate
        )
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)

        try stream.addRecordingOutput(recordingOutput)

        try await stream.startCapture()

        return SystemScreenRecordingSession(
            stream: stream,
            recordingOutput: recordingOutput,
            delegate: delegate,
            outputURL: outputURL,
            startedAt: createdAt,
            pixelSize: pixelSize,
            fileStore: fileStore
        )
    }

    nonisolated private static func evenPixelDimension(_ value: Int) -> Int {
        max(((max(value, 1) + 1) / 2) * 2, 2)
    }
}

nonisolated private final class SystemScreenRecordingSession: ScreenRecordingSession, @unchecked Sendable {
    let startedAt: Date

    private let stream: SCStream
    private let recordingOutput: SCRecordingOutput
    private let delegate: ScreenRecordingOutputDelegateBox
    private let outputURL: URL
    private let pixelSize: CGSize
    private let fileStore: ScreenRecordingFileManaging
    private let lock = NSLock()
    private var didStop = false

    init(
        stream: SCStream,
        recordingOutput: SCRecordingOutput,
        delegate: ScreenRecordingOutputDelegateBox,
        outputURL: URL,
        startedAt: Date,
        pixelSize: CGSize,
        fileStore: ScreenRecordingFileManaging
    ) {
        self.stream = stream
        self.recordingOutput = recordingOutput
        self.delegate = delegate
        self.outputURL = outputURL
        self.startedAt = startedAt
        self.pixelSize = pixelSize
        self.fileStore = fileStore
    }

    func stop() async throws -> ScreenRecordingOutput {
        guard markStoppedIfNeeded() else {
            return try output()
        }

        try await stream.stopCapture()
        try await waitForRecordingToFinish()
        return try output()
    }

    func cancel() async {
        guard markStoppedIfNeeded() else {
            return
        }

        try? await stream.stopCapture()
        if let fileName = outputURL.lastPathComponent.nilIfEmpty {
            fileStore.deleteRecording(named: fileName)
        }
    }

    private func markStoppedIfNeeded() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !didStop else {
            return false
        }

        didStop = true
        return true
    }

    private func waitForRecordingToFinish() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [delegate] in
                try await delegate.waitForFinish()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                throw ScreenRecordingError.recordingDidNotFinish
            }

            _ = try await group.next()
            group.cancelAll()
        }
    }

    private func output() throws -> ScreenRecordingOutput {
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw ScreenRecordingError.missingRecordingFile
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.int64Value
        let recordedDuration = recordingOutput.recordedDuration.seconds
        let elapsedDuration = Date().timeIntervalSince(startedAt)

        return ScreenRecordingOutput(
            fileURL: outputURL,
            createdAt: startedAt,
            duration: max(recordedDuration.isFinite ? recordedDuration : 0, elapsedDuration),
            pixelSize: pixelSize,
            fileSize: fileSize
        )
    }
}

nonisolated private final class ScreenRecordingOutputDelegateBox: NSObject, SCRecordingOutputDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var didFinish = false
    private var failure: Error?
    private var finishContinuation: CheckedContinuation<Void, Error>?

    func waitForFinish() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            if let failure {
                lock.unlock()
                continuation.resume(throwing: failure)
                return
            }

            if didFinish {
                lock.unlock()
                continuation.resume()
                return
            }

            finishContinuation = continuation
            lock.unlock()
        }
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        finish(.failure(error))
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        finish(.success(()))
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        guard !didFinish, failure == nil else {
            lock.unlock()
            return
        }

        switch result {
        case .success:
            didFinish = true
        case .failure(let error):
            failure = error
        }

        let continuation = finishContinuation
        finishContinuation = nil
        lock.unlock()

        switch result {
        case .success:
            continuation?.resume()
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }
}

protocol ScreenRecordingFileExporting: Sendable {
    @MainActor func saveMP4File(at sourceURL: URL, suggestedFileName: String) throws
    @MainActor func saveGIFFile(
        from sourceURL: URL,
        suggestedFileName: String,
        options: ScreenRecordingGIFExportOptions
    ) async throws
}

nonisolated struct SystemScreenRecordingFileExporter: ScreenRecordingFileExporting {
    @MainActor
    func saveMP4File(at sourceURL: URL, suggestedFileName: String) throws {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw ScreenRecordingError.missingRecordingFile
        }

        let destinationURL = try destinationURL(
            suggestedFileName: suggestedFileName,
            allowedContentTypes: [.mpeg4Movie]
        )
        guard sourceURL != destinationURL else {
            return
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    @MainActor
    func saveGIFFile(
        from sourceURL: URL,
        suggestedFileName: String,
        options: ScreenRecordingGIFExportOptions
    ) async throws {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw ScreenRecordingError.missingRecordingFile
        }

        let destinationURL = try destinationURL(
            suggestedFileName: suggestedFileName,
            allowedContentTypes: [.gif]
        )
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try await ScreenRecordingGIFExporter.writeGIF(
            from: sourceURL,
            to: destinationURL,
            options: options
        )
    }

    @MainActor
    private func destinationURL(
        suggestedFileName: String,
        allowedContentTypes: [UTType]
    ) throws -> URL {
        let panel = NSSavePanel()
        panel.allowedContentTypes = allowedContentTypes
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFileName

        guard panel.runModal() == .OK else {
            throw ScreenshotSaveError.cancelled
        }

        guard let url = panel.url else {
            throw ScreenshotSaveError.missingDestination
        }

        return url
    }
}

nonisolated enum ScreenRecordingGIFExporter {
    static func writeGIF(
        from sourceURL: URL,
        to destinationURL: URL,
        options: ScreenRecordingGIFExportOptions = ScreenRecordingGIFExportOptions()
    ) async throws {
        try await Task.detached(priority: .utility) {
            let options = options.sanitized
            let asset = AVURLAsset(url: sourceURL)
            let duration = try await asset.load(.duration)
            let durationSeconds = max(duration.seconds, 0)
            guard durationSeconds.isFinite,
                  durationSeconds > 0 else {
                throw ScreenRecordingError.gifFrameGenerationFailed
            }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(
                width: options.maximumPixelSize,
                height: options.maximumPixelSize
            )

            guard let framePlan = ScreenRecordingGIFFramePlan(
                sourceDuration: durationSeconds,
                options: options
            ) else {
                throw ScreenRecordingError.gifFrameGenerationFailed
            }

            guard let destination = CGImageDestinationCreateWithURL(
                destinationURL as CFURL,
                UTType.gif.identifier as CFString,
                framePlan.frameCount,
                nil
            ) else {
                throw ScreenRecordingError.gifDestinationFailed
            }

            let gifProperties: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFLoopCount: 0
                ]
            ]
            let frameProperties: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: framePlan.frameDelay,
                    kCGImagePropertyGIFUnclampedDelayTime: framePlan.frameDelay
                ]
            ]
            CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

            for index in 0..<framePlan.frameCount {
                let outputSeconds = Double(index) * framePlan.frameDelay
                let seconds = min(outputSeconds * options.playbackSpeed, durationSeconds)
                let time = CMTime(seconds: seconds, preferredTimescale: 600)
                let image = try generator.copyCGImage(at: time, actualTime: nil)
                CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
            }

            guard CGImageDestinationFinalize(destination) else {
                throw ScreenRecordingError.gifDestinationFailed
            }
        }.value
    }
}

nonisolated enum ScreenRecordingThumbnailRenderer {
    static func image(from sourceURL: URL, maxPixelSize: CGFloat = 480) async -> NSImage? {
        guard let cgImage = await cgImage(from: sourceURL, maxPixelSize: maxPixelSize) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
    }

    static func pngData(from sourceURL: URL, maxPixelSize: CGFloat = 480) async -> Data? {
        guard let image = await cgImage(from: sourceURL, maxPixelSize: maxPixelSize) else {
            return nil
        }

        return autoreleasepool {
            let bitmap = NSBitmapImageRep(cgImage: image)
            return bitmap.representation(using: .png, properties: [:])
        }
    }

    private static func cgImage(from sourceURL: URL, maxPixelSize: CGFloat) async -> CGImage? {
        await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                return nil
            }

            let asset = AVURLAsset(url: sourceURL)
            let duration = try? await asset.load(.duration).seconds
            let durationSeconds = max(duration ?? 0, 0)
            let sampleSeconds: TimeInterval
            if durationSeconds.isFinite, durationSeconds > 0 {
                sampleSeconds = min(max(durationSeconds * 0.08, 0.08), 0.5)
            } else {
                sampleSeconds = 0
            }

            return autoreleasepool {
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)

                return try? generator.copyCGImage(
                    at: CMTime(seconds: sampleSeconds, preferredTimescale: 600),
                    actualTime: nil
                )
            }
        }.value
    }
}

nonisolated enum ScreenRecordingGIFPreviewRenderer {
    static func preview(
        from sourceURL: URL,
        options: ScreenRecordingGIFExportOptions,
        maximumFrameCount: Int = .max,
        maximumPixelSize: CGFloat = 480
    ) async -> ScreenRecordingGIFPreview? {
        let task = Task.detached(priority: .utility) { () async -> ScreenRecordingGIFPreview? in
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                return nil
            }

            let options = options.sanitized
            let asset = AVURLAsset(url: sourceURL)
            guard let duration = try? await asset.load(.duration),
                  duration.seconds.isFinite,
                  duration.seconds > 0 else {
                return nil
            }

            let durationSeconds = duration.seconds
            guard let framePlan = ScreenRecordingGIFFramePlan(
                sourceDuration: durationSeconds,
                options: options,
                maximumFrameCount: maximumFrameCount
            ) else {
                return nil
            }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(
                width: maximumPixelSize,
                height: maximumPixelSize
            )

            var frames: [CGImage] = []
            frames.reserveCapacity(framePlan.frameCount)

            for index in 0..<framePlan.frameCount {
                if Task.isCancelled {
                    return nil
                }

                let outputSeconds = Double(index) * framePlan.frameDelay
                let seconds = min(outputSeconds * options.playbackSpeed, durationSeconds)
                let time = CMTime(seconds: seconds, preferredTimescale: 600)
                guard let image = try? generator.copyCGImage(at: time, actualTime: nil) else {
                    continue
                }

                frames.append(image)
            }

            guard !frames.isEmpty else {
                return nil
            }

            return ScreenRecordingGIFPreview(
                frames: frames,
                frameDelay: framePlan.frameDelay,
                previewedDuration: framePlan.previewedDuration,
                isTruncated: framePlan.isTruncated
            )
        }

        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

nonisolated private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

nonisolated private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }

    func lowerBounded(to lowerBound: Self) -> Self {
        max(self, lowerBound)
    }
}

nonisolated private extension Double {
    func finiteValue(defaultValue: Double) -> Double {
        isFinite ? self : defaultValue
    }
}
