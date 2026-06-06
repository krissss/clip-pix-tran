import CoreGraphics
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ClipPixTran

struct ScreenCaptureCoordinateConverterTests {
    @Test func convertsAppKitScreenRectToDisplaySourceRect() {
        let region = ScreenCaptureRegion(
            rect: CGRect(x: 100, y: 200, width: 300, height: 400),
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            displayID: 1
        )

        let sourceRect = ScreenCaptureCoordinateConverter.sourceRect(for: region)

        #expect(sourceRect == CGRect(x: 100, y: 300, width: 300, height: 400))
    }

    @Test func convertsOffsetScreenRectToDisplaySourceRect() {
        let region = ScreenCaptureRegion(
            rect: CGRect(x: 1540, y: 500, width: 320, height: 180),
            screenFrame: CGRect(x: 1440, y: 100, width: 1280, height: 720),
            displayID: 2
        )

        let sourceRect = ScreenCaptureCoordinateConverter.sourceRect(for: region)

        #expect(sourceRect == CGRect(x: 100, y: 140, width: 320, height: 180))
    }

    @Test func snapshotCropUsesAppKitScreenCoordinates() throws {
        let image = try makeTestImage(width: 2880, height: 1800)
        let snapshot = ScreenCaptureSnapshot(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            displayID: 1,
            image: image
        )

        let cropRect = try #require(
            snapshot.cropPixelRect(
                in: CGRect(x: 100, y: 200, width: 300, height: 400)
            )
        )

        #expect(cropRect == CGRect(x: 200, y: 600, width: 600, height: 800))
    }

    @Test func snapshotPNGDataCropsRequestedRegion() throws {
        let image = try makeTestImage(width: 2880, height: 1800)
        let snapshot = ScreenCaptureSnapshot(
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            displayID: 1,
            image: image
        )

        let pngData = try snapshot.pngData(
            in: CGRect(x: 100, y: 200, width: 300, height: 400)
        )
        let source = try #require(CGImageSourceCreateWithData(pngData as CFData, nil))
        let croppedImage = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))

        #expect(croppedImage.width == 600)
        #expect(croppedImage.height == 800)
    }
}

private func makeTestImage(width: Int, height: Int) throws -> CGImage {
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

    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    guard let image = context.makeImage() else {
        throw TestImageError.imageCreationFailed
    }

    return image
}

private enum TestImageError: Error {
    case contextCreationFailed
    case imageCreationFailed
}
