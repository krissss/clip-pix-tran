import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ClipPixTran

struct ScrollingScreenshotServiceTests {
    @Test func stitchesManuallyCapturedOverlappingFrames() async throws {
        let content = try makeStripedImage(width: 24, height: 180)
        let viewportHeight = 60
        let service = ScrollingScreenshotService(
            configuration: ScrollingScreenshotConfiguration(
                maxCaptures: 3,
                sampleIntervalNanoseconds: 0,
                minimumOverlapRatio: 0.1,
                minimumAppendRatio: 0.02,
                maximumOutputPixelHeight: 400
            )
        )
        let frames = try [0, 42, 84].map { offset in
            try pngData(from: try crop(content, y: offset, height: viewportHeight))
        }

        let output = try service.stitch(pngDataFrames: frames)

        let stitched = try #require(makeCGImage(from: output))
        #expect(stitched.width == 24)
        #expect(stitched.height == 144)
    }

    @Test func sessionSamplesUntilFinished() async throws {
        let content = try makeStripedImage(width: 20, height: 120)
        let viewportHeight = 50
        let offsets = [0, 35, 70]
        let captureCounter = ManualCaptureCounter()
        let service = ScrollingScreenshotService(
            configuration: ScrollingScreenshotConfiguration(
                maxCaptures: offsets.count,
                sampleIntervalNanoseconds: 1_000_000,
                minimumOverlapRatio: 0.1,
                minimumAppendRatio: 0.02,
                maximumOutputPixelHeight: 300
            )
        )

        let session = try service.startManualCapture(
            in: CGRect(x: 0, y: 0, width: 20, height: viewportHeight),
            excludingWindowIDs: []
        ) { _, _ in
            let index = await captureCounter.nextIndex(limit: offsets.count)
            return try pngData(from: try crop(content, y: offsets[index], height: viewportHeight))
        }

        try await captureCounter.waitUntilCount(atLeast: offsets.count)
        let output = try await session.finish()

        let stitched = try #require(makeCGImage(from: output))
        #expect(stitched.width == 20)
        #expect(stitched.height == 120)
        #expect(await captureCounter.count >= offsets.count)
    }

    @Test func ignoresDuplicateManualFrames() throws {
        let frame = try pngData(from: makeSolidImage(width: 18, height: 50))
        let service = ScrollingScreenshotService(
            configuration: ScrollingScreenshotConfiguration(
                maxCaptures: 4,
                sampleIntervalNanoseconds: 0,
                minimumOverlapRatio: 0.1,
                minimumAppendRatio: 0.02,
                maximumOutputPixelHeight: 300
            )
        )

        let output = try service.stitch(pngDataFrames: [frame, frame, frame])

        let stitched = try #require(makeCGImage(from: output))
        #expect(stitched.width == 18)
        #expect(stitched.height == 50)
    }
}

private func makeStripedImage(width: Int, height: Int) throws -> CGImage {
    try makeImage(width: width, height: height) { x, y in
        let band = y / 3
        return CGColor(
            red: CGFloat((band * 17 + x * 3) % 255) / 255,
            green: CGFloat((band * 29 + x * 5) % 255) / 255,
            blue: CGFloat((band * 43 + x * 7) % 255) / 255,
            alpha: 1
        )
    }
}

private func makeSolidImage(width: Int, height: Int) throws -> CGImage {
    try makeImage(width: width, height: height) { _, _ in
        CGColor(red: 0.3, green: 0.4, blue: 0.5, alpha: 1)
    }
}

private func makeImage(
    width: Int,
    height: Int,
    color: (Int, Int) -> CGColor
) throws -> CGImage {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw TestImageError.contextCreationFailed
    }

    for y in 0..<height {
        for x in 0..<width {
            context.setFillColor(color(x, y))
            context.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }
    }

    guard let image = context.makeImage() else {
        throw TestImageError.imageCreationFailed
    }

    return image
}

private func crop(_ image: CGImage, y: Int, height: Int) throws -> CGImage {
    guard let cropped = image.cropping(
        to: CGRect(x: 0, y: y, width: image.width, height: height)
    ) else {
        throw TestImageError.imageCreationFailed
    }

    return cropped
}

private func pngData(from image: CGImage) throws -> Data {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw TestImageError.pngEncodingFailed
    }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw TestImageError.pngEncodingFailed
    }

    return data as Data
}

private func makeCGImage(from data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
        return nil
    }

    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

private enum TestImageError: Error {
    case contextCreationFailed
    case imageCreationFailed
    case pngEncodingFailed
}

private actor ManualCaptureCounter {
    private var value = 0

    var count: Int {
        value
    }

    func nextIndex(limit: Int) -> Int {
        let index = min(value, limit - 1)
        value += 1
        return index
    }

    func waitUntilCount(
        atLeast minimumCount: Int,
        timeoutNanoseconds: UInt64 = 500_000_000
    ) async throws {
        let deadline = ContinuousClock.now + .nanoseconds(Int64(timeoutNanoseconds))
        while value < minimumCount {
            if ContinuousClock.now >= deadline {
                return
            }

            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}
