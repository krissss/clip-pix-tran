import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ClipPixTran

struct ScreenshotAnnotationRendererTests {
    @Test func rendersEachAnnotationKindToPNGData() throws {
        let baseData = try #require(makePNGData())
        let style = ScreenshotAnnotationStyle(
            colorComponents: .red,
            lineWidth: 3,
            fontSize: 18
        )
        let annotations = [
            ScreenshotAnnotation(
                kind: .rectangle,
                points: [CGPoint(x: 8, y: 8), CGPoint(x: 42, y: 38)],
                style: style
            ),
            ScreenshotAnnotation(
                kind: .ellipse,
                points: [CGPoint(x: 50, y: 10), CGPoint(x: 84, y: 42)],
                style: style
            ),
            ScreenshotAnnotation(
                kind: .arrow,
                points: [CGPoint(x: 12, y: 70), CGPoint(x: 60, y: 84)],
                style: style
            ),
            ScreenshotAnnotation(
                kind: .pen,
                points: [CGPoint(x: 70, y: 70), CGPoint(x: 78, y: 78), CGPoint(x: 88, y: 74)],
                style: style
            ),
            ScreenshotAnnotation(
                kind: .text,
                points: [CGPoint(x: 10, y: 96)],
                style: style,
                text: "Pix"
            ),
            ScreenshotAnnotation(
                kind: .step,
                points: [CGPoint(x: 32, y: 104)],
                style: ScreenshotAnnotationStyle(
                    colorComponents: .blue,
                    fontSize: 18,
                    fontWeight: .bold
                ),
                text: "Click"
            ),
            ScreenshotAnnotation(
                kind: .mosaic,
                points: [CGPoint(x: 60, y: 92), CGPoint(x: 110, y: 116)],
                style: style
            ),
            ScreenshotAnnotation(
                kind: .mosaic,
                points: [CGPoint(x: 92, y: 50), CGPoint(x: 98, y: 56), CGPoint(x: 110, y: 58)],
                style: ScreenshotAnnotationStyle(
                    colorComponents: .red,
                    lineWidth: 3,
                    fontSize: 18,
                    mosaicMode: .brush,
                    mosaicBlockSize: 10,
                    mosaicBrushSize: 22
                )
            )
        ]

        let renderedData = try ScreenshotAnnotationRenderer.renderPNGData(
            basePNGData: baseData,
            annotations: annotations,
            canvasSize: CGSize(width: 120, height: 120)
        )

        #expect(renderedData != baseData)
        #expect(CGImageSourceCreateWithData(renderedData as CFData, nil) != nil)
    }

    @Test func noAnnotationsReturnsOriginalData() throws {
        let baseData = try #require(makePNGData())

        let renderedData = try ScreenshotAnnotationRenderer.renderPNGData(
            basePNGData: baseData,
            annotations: [],
            canvasSize: CGSize(width: 120, height: 120)
        )

        #expect(renderedData == baseData)
    }

    @Test func previewMosaicRenderingMatchesPNGRendering() throws {
        let baseData = try makeGradientPNGData()
        let baseImage = try #require(makeCGImage(from: baseData))
        let canvasSize = CGSize(width: 40, height: 40)
        let annotations = [
            ScreenshotAnnotation(
                kind: .mosaic,
                points: [CGPoint(x: 4, y: 4), CGPoint(x: 34, y: 30)],
                style: ScreenshotAnnotationStyle(
                    mosaicMode: .rectangle,
                    mosaicBlockSize: 8
                )
            ),
            ScreenshotAnnotation(
                kind: .mosaic,
                points: [CGPoint(x: 8, y: 34), CGPoint(x: 16, y: 28), CGPoint(x: 28, y: 34)],
                style: ScreenshotAnnotationStyle(
                    mosaicMode: .brush,
                    mosaicBlockSize: 6,
                    mosaicBrushSize: 12
                )
            )
        ]

        let pngData = try ScreenshotAnnotationRenderer.renderPNGData(
            basePNGData: baseData,
            annotations: annotations,
            canvasSize: canvasSize
        )
        let pngImage = try #require(makeCGImage(from: pngData))
        let previewImage = try renderPreviewImage(
            baseImage: baseImage,
            annotations: annotations,
            canvasSize: canvasSize
        )

        #expect(try rgbaBytes(from: previewImage) == rgbaBytes(from: pngImage))
    }
}

private func makePNGData() -> Data? {
    let image = NSImage(size: CGSize(width: 120, height: 120))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 120, height: 120).fill()
    image.unlockFocus()

    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData) else {
        return nil
    }

    return bitmap.representation(using: .png, properties: [:])
}

private func makeGradientPNGData() throws -> Data {
    let width = 40
    let height = 40
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
            context.setFillColor(
                CGColor(
                    red: CGFloat(x) / CGFloat(width),
                    green: CGFloat(y) / CGFloat(height),
                    blue: CGFloat((x + y) % width) / CGFloat(width),
                    alpha: 1
                )
            )
            context.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }
    }

    guard let image = context.makeImage() else {
        throw TestImageError.imageCreationFailed
    }

    return try pngData(from: image)
}

private func renderPreviewImage(
    baseImage: CGImage,
    annotations: [ScreenshotAnnotation],
    canvasSize: CGSize
) throws -> CGImage {
    guard let context = CGContext(
        data: nil,
        width: baseImage.width,
        height: baseImage.height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw TestImageError.contextCreationFailed
    }

    context.draw(
        baseImage,
        in: CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height)
    )
    ScreenshotAnnotationRenderer.drawAnnotations(
        annotations,
        in: context,
        baseImage: baseImage,
        canvasSize: canvasSize
    )

    guard let image = context.makeImage() else {
        throw TestImageError.imageCreationFailed
    }

    return image
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

private func rgbaBytes(from image: CGImage) throws -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try pixels.withUnsafeMutableBytes { rawBuffer in
        guard let context = CGContext(
            data: rawBuffer.baseAddress,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestImageError.contextCreationFailed
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }

    return pixels
}

private enum TestImageError: Error {
    case contextCreationFailed
    case imageCreationFailed
    case pngEncodingFailed
}
