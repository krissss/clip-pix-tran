import AppKit
import ImageIO
import UniformTypeIdentifiers

nonisolated struct ScrollingScreenshotConfiguration: Equatable, Sendable {
    var maxCaptures: Int = 120
    var sampleIntervalNanoseconds: UInt64 = 280_000_000
    var minimumOverlapRatio: CGFloat = 0.12
    var minimumAppendRatio: CGFloat = 0.04
    var maximumOutputPixelHeight: Int = 32_000

    static let `default` = Self()
}

nonisolated struct ScrollingScreenshotService: Sendable {
    typealias CaptureProvider = @Sendable (CGRect, Set<CGWindowID>) async throws -> Data

    private let configuration: ScrollingScreenshotConfiguration

    init(
        configuration: ScrollingScreenshotConfiguration = .default
    ) {
        self.configuration = configuration
    }

    func startManualCapture(
        in rect: CGRect,
        excludingWindowIDs: Set<CGWindowID>,
        captureProvider: @escaping CaptureProvider
    ) throws -> ScrollingScreenshotCaptureSession {
        let normalizedRect = rect.standardized
        guard normalizedRect.width > 0,
              normalizedRect.height > 0 else {
            throw ScreenshotCaptureError.unavailable
        }

        let session = ScrollingScreenshotCaptureSession(
            rect: normalizedRect,
            excludingWindowIDs: excludingWindowIDs,
            configuration: configuration,
            captureProvider: captureProvider
        )
        Task {
            await session.start()
        }
        return session
    }

    func stitch(pngDataFrames: [Data]) throws -> Data {
        let frames = try pngDataFrames.map(ScrollingScreenshotFrame.init(pngData:))
        return try stitch(frames: frames)
    }

    private func stitch(frames capturedFrames: [ScrollingScreenshotFrame]) throws -> Data {
        guard let firstFrame = capturedFrames.first else {
            throw ScreenshotCaptureError.unavailable
        }

        var frames = [ScrollingScreenshotFrameSegment(frame: firstFrame, startY: 0, height: firstFrame.height)]
        var previousFrame = firstFrame
        var outputHeight = firstFrame.height

        guard capturedFrames.count > 1 else {
            return try renderPNGData(from: frames, outputHeight: outputHeight)
        }

        let minimumAppendHeight = max(
            Int(CGFloat(firstFrame.height) * configuration.minimumAppendRatio),
            12
        )

        for nextFrame in capturedFrames.dropFirst() {
            guard nextFrame.width == firstFrame.width else {
                continue
            }

            let overlap = previousFrame.bestVerticalOverlap(
                with: nextFrame,
                minimumOverlapRatio: configuration.minimumOverlapRatio
            ) ?? 0
            let appendHeight = nextFrame.height - overlap
            guard appendHeight >= minimumAppendHeight else {
                continue
            }

            let remainingHeight = configuration.maximumOutputPixelHeight - outputHeight
            guard remainingHeight >= minimumAppendHeight else {
                break
            }

            let segmentHeight = min(appendHeight, remainingHeight)
            frames.append(
                ScrollingScreenshotFrameSegment(
                    frame: nextFrame,
                    startY: overlap,
                    height: segmentHeight
                )
            )
            outputHeight += segmentHeight
            previousFrame = nextFrame

            if segmentHeight < appendHeight {
                break
            }
        }

        return try renderPNGData(from: frames, outputHeight: outputHeight)
    }

    private func renderPNGData(
        from segments: [ScrollingScreenshotFrameSegment],
        outputHeight: Int
    ) throws -> Data {
        guard let first = segments.first,
              outputHeight > 0 else {
            throw ScreenshotCaptureError.unavailable
        }

        let width = first.frame.width
        var outputBytes = [UInt8](repeating: 0, count: width * outputHeight * 4)
        var destinationY = 0

        for segment in segments {
            guard segment.frame.width == width,
                  segment.height > 0,
                  segment.startY >= 0,
                  segment.startY + segment.height <= segment.frame.height else {
                continue
            }

            for row in 0..<segment.height {
                let sourceOffset = ((segment.startY + row) * width) * 4
                let destinationOffset = ((destinationY + row) * width) * 4
                outputBytes[destinationOffset..<(destinationOffset + width * 4)] =
                    segment.frame.rgbaBytes[sourceOffset..<(sourceOffset + width * 4)]
            }
            destinationY += segment.height
        }

        return try pngData(
            rgbaBytes: outputBytes,
            width: width,
            height: outputHeight
        )
    }
}

actor ScrollingScreenshotCaptureSession {
    private let rect: CGRect
    private let excludingWindowIDs: Set<CGWindowID>
    private let configuration: ScrollingScreenshotConfiguration
    private let captureProvider: ScrollingScreenshotService.CaptureProvider
    private var frames: [Data] = []
    private var captureTask: Task<Void, Never>?
    private var firstError: Error?

    init(
        rect: CGRect,
        excludingWindowIDs: Set<CGWindowID>,
        configuration: ScrollingScreenshotConfiguration,
        captureProvider: @escaping ScrollingScreenshotService.CaptureProvider
    ) {
        self.rect = rect
        self.excludingWindowIDs = excludingWindowIDs
        self.configuration = configuration
        self.captureProvider = captureProvider
    }

    func start() {
        guard captureTask == nil else {
            return
        }

        captureTask = Task(priority: .userInitiated) { [weak self] in
            await self?.captureLoop()
        }
    }

    func finish() async throws -> Data {
        let task = captureTask
        captureTask = nil
        task?.cancel()
        await task?.value

        if frames.count < max(configuration.maxCaptures, 1) {
            do {
                try await captureOneFrame()
            } catch {
                if frames.isEmpty {
                    throw error
                }
            }
        }

        if frames.isEmpty,
           let firstError {
            throw firstError
        }

        return try ScrollingScreenshotService(configuration: configuration)
            .stitch(pngDataFrames: frames)
    }

    func cancel() {
        captureTask?.cancel()
        captureTask = nil
        frames.removeAll()
    }

    private func captureLoop() async {
        while !Task.isCancelled,
              frames.count < max(configuration.maxCaptures, 1) {
            do {
                try await captureOneFrame()
            } catch is CancellationError {
                return
            } catch {
                firstError = error
                return
            }

            do {
                try await Task.sleep(nanoseconds: configuration.sampleIntervalNanoseconds)
            } catch {
                return
            }
        }
    }

    private func captureOneFrame() async throws {
        try Task.checkCancellation()
        let data = try await captureProvider(rect, excludingWindowIDs)
        frames.append(data)
    }
}

nonisolated private struct ScrollingScreenshotFrameSegment {
    let frame: ScrollingScreenshotFrame
    let startY: Int
    let height: Int
}

nonisolated struct ScrollingScreenshotFrame {
    let width: Int
    let height: Int
    let rgbaBytes: [UInt8]

    init(pngData: Data) throws {
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ScreenshotCaptureError.unavailable
        }

        try self.init(image: image)
    }

    init(image: CGImage) throws {
        let width = image.width
        let height = image.height
        guard width > 0,
              height > 0 else {
            throw ScreenshotCaptureError.unavailable
        }

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { rawBuffer in
            guard let context = CGContext(
                data: rawBuffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                throw ScreenshotCaptureError.pngEncodingFailed
            }

            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        self.width = width
        self.height = height
        self.rgbaBytes = bytes
    }

    func bestVerticalOverlap(
        with next: ScrollingScreenshotFrame,
        minimumOverlapRatio: CGFloat
    ) -> Int? {
        guard width == next.width,
              height > 1,
              next.height > 1 else {
            return nil
        }

        let minimumOverlap = max(Int(CGFloat(min(height, next.height)) * minimumOverlapRatio), 8)
        let maximumOverlap = min(height, next.height)
        guard minimumOverlap <= maximumOverlap else {
            return nil
        }

        var bestOverlap: Int?
        var bestDifference = Double.greatestFiniteMagnitude

        for overlap in stride(from: maximumOverlap, through: minimumOverlap, by: -1) {
            let difference = averageRowDifference(
                next: next,
                overlap: overlap
            )
            if difference < bestDifference {
                bestDifference = difference
                bestOverlap = overlap
            }
            if difference <= 1.2 {
                return overlap
            }
        }

        guard bestDifference <= 6 else {
            return nil
        }

        return bestOverlap
    }

    private func averageRowDifference(
        next: ScrollingScreenshotFrame,
        overlap: Int
    ) -> Double {
        let rowStride = max(overlap / 24, 1)
        let columnStride = max(width / 80, 1)
        var totalDifference = 0
        var sampleCount = 0

        for row in stride(from: 0, to: overlap, by: rowStride) {
            let previousRow = height - overlap + row
            let nextRow = row
            for column in stride(from: 0, to: width, by: columnStride) {
                let previousOffset = (previousRow * width + column) * 4
                let nextOffset = (nextRow * next.width + column) * 4

                totalDifference += abs(Int(rgbaBytes[previousOffset]) - Int(next.rgbaBytes[nextOffset]))
                totalDifference += abs(Int(rgbaBytes[previousOffset + 1]) - Int(next.rgbaBytes[nextOffset + 1]))
                totalDifference += abs(Int(rgbaBytes[previousOffset + 2]) - Int(next.rgbaBytes[nextOffset + 2]))
                sampleCount += 3
            }
        }

        guard sampleCount > 0 else {
            return Double.greatestFiniteMagnitude
        }

        return Double(totalDifference) / Double(sampleCount)
    }
}

nonisolated private func pngData(
    rgbaBytes: [UInt8],
    width: Int,
    height: Int
) throws -> Data {
    guard width > 0,
          height > 0 else {
        throw ScreenshotCaptureError.pngEncodingFailed
    }

    let data = Data(rgbaBytes) as CFData
    guard let provider = CGDataProvider(data: data),
          let image = CGImage(
              width: width,
              height: height,
              bitsPerComponent: 8,
              bitsPerPixel: 32,
              bytesPerRow: width * 4,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
              provider: provider,
              decode: nil,
              shouldInterpolate: false,
              intent: .defaultIntent
          ) else {
        throw ScreenshotCaptureError.pngEncodingFailed
    }

    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        output,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw ScreenshotCaptureError.pngEncodingFailed
    }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw ScreenshotCaptureError.pngEncodingFailed
    }

    return output as Data
}
