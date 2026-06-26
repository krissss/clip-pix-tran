import AppKit
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ScreenshotAnnotationRenderError: Error {
    case invalidImageData
    case contextCreationFailed
    case imageCreationFailed
    case pngEncodingFailed
}

enum ScreenshotAnnotationRenderer {
    nonisolated static func renderPNGData(
        basePNGData: Data,
        annotations: [ScreenshotAnnotation],
        canvasSize: CGSize
    ) throws -> Data {
        guard !annotations.isEmpty else {
            return basePNGData
        }

        guard let source = CGImageSourceCreateWithData(basePNGData as CFData, nil),
              let baseImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ScreenshotAnnotationRenderError.invalidImageData
        }

        let width = baseImage.width
        let height = baseImage.height
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ScreenshotAnnotationRenderError.contextCreationFailed
        }

        let scaleX = CGFloat(width) / max(canvasSize.width, 1)
        let scaleY = CGFloat(height) / max(canvasSize.height, 1)

        context.draw(
            baseImage,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )
        context.saveGState()
        context.scaleBy(x: scaleX, y: scaleY)

        drawAnnotations(
            annotations,
            in: context,
            baseImage: baseImage,
            scale: CGSize(width: scaleX, height: scaleY)
        )

        context.restoreGState()

        guard let outputImage = context.makeImage() else {
            throw ScreenshotAnnotationRenderError.imageCreationFailed
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ScreenshotAnnotationRenderError.pngEncodingFailed
        }

        CGImageDestinationAddImage(destination, outputImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenshotAnnotationRenderError.pngEncodingFailed
        }

        return data as Data
    }

    nonisolated static func drawAnnotations(
        _ annotations: [ScreenshotAnnotation],
        in context: CGContext
    ) {
        drawAnnotations(annotations, in: context, baseImage: nil, scale: .zero)
    }

    nonisolated static func drawAnnotations(
        _ annotations: [ScreenshotAnnotation],
        in context: CGContext,
        baseImage: CGImage?,
        canvasSize: CGSize
    ) {
        let scale: CGSize
        if let baseImage {
            scale = CGSize(
                width: CGFloat(baseImage.width) / max(canvasSize.width, 1),
                height: CGFloat(baseImage.height) / max(canvasSize.height, 1)
            )
        } else {
            scale = .zero
        }

        drawAnnotations(annotations, in: context, baseImage: baseImage, scale: scale)
    }

    nonisolated private static func drawAnnotations(
        _ annotations: [ScreenshotAnnotation],
        in context: CGContext,
        baseImage: CGImage?,
        scale: CGSize
    ) {
        var stepNumber = 0
        for annotation in annotations {
            if annotation.kind == .step {
                stepNumber += 1
                draw(annotation, stepNumber: stepNumber, in: context)
            } else {
                draw(annotation, in: context, baseImage: baseImage, scale: scale)
            }
        }
    }

    nonisolated private static func draw(
        _ annotation: ScreenshotAnnotation,
        in context: CGContext,
        baseImage: CGImage?,
        scale: CGSize
    ) {
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(annotation.style.lineWidth)
        context.setStrokeColor(annotation.style.colorComponents.cgColor)
        context.setFillColor(annotation.style.colorComponents.cgColor)

        switch annotation.kind {
        case .rectangle:
            drawRectangle(annotation, in: context)
        case .ellipse:
            drawEllipse(annotation, in: context)
        case .arrow:
            drawArrow(annotation, in: context)
        case .pen:
            drawPen(annotation, in: context)
        case .text:
            drawText(annotation, in: context)
        case .mosaic:
            drawMosaic(annotation, in: context, baseImage: baseImage, scale: scale)
        case .step:
            break
        }

        context.restoreGState()
    }

    nonisolated private static func draw(
        _ annotation: ScreenshotAnnotation,
        stepNumber: Int,
        in context: CGContext
    ) {
        guard annotation.points.first != nil else {
            return
        }

        context.saveGState()
        drawStepBubble(annotation, stepNumber: stepNumber, in: context)
        drawStepDescription(annotation, in: context)
        context.restoreGState()
    }

    nonisolated private static func drawRectangle(
        _ annotation: ScreenshotAnnotation,
        in context: CGContext
    ) {
        let rect = annotation.rect
        guard !rect.isNull, rect.width > 0, rect.height > 0 else {
            return
        }

        context.stroke(rect)
    }

    nonisolated private static func drawEllipse(
        _ annotation: ScreenshotAnnotation,
        in context: CGContext
    ) {
        let rect = annotation.rect
        guard !rect.isNull, rect.width > 0, rect.height > 0 else {
            return
        }

        context.strokeEllipse(in: rect)
    }

    nonisolated private static func drawArrow(
        _ annotation: ScreenshotAnnotation,
        in context: CGContext
    ) {
        guard let start = annotation.points.first,
              let end = annotation.points.last,
              start != end else {
            return
        }

        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(annotation.style.lineWidth * 5, 14)
        let spread = CGFloat.pi / 7
        let first = CGPoint(
            x: end.x - cos(angle - spread) * headLength,
            y: end.y - sin(angle - spread) * headLength
        )
        let second = CGPoint(
            x: end.x - cos(angle + spread) * headLength,
            y: end.y - sin(angle + spread) * headLength
        )

        context.move(to: end)
        context.addLine(to: first)
        context.move(to: end)
        context.addLine(to: second)
        context.strokePath()
    }

    nonisolated private static func drawPen(
        _ annotation: ScreenshotAnnotation,
        in context: CGContext
    ) {
        guard let first = annotation.points.first else {
            return
        }

        context.move(to: first)
        annotation.points.dropFirst().forEach { point in
            context.addLine(to: point)
        }
        context.strokePath()
    }

    nonisolated private static func drawText(
        _ annotation: ScreenshotAnnotation,
        in context: CGContext
    ) {
        guard let origin = annotation.points.first,
              let text = annotation.text,
              !text.isEmpty else {
            return
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: annotation.style.ctFont,
            .foregroundColor: annotation.style.colorComponents.cgColor
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributedText)

        context.textMatrix = .identity
        context.textPosition = origin
        CTLineDraw(line, context)
    }

    nonisolated private static func drawStepBubble(
        _ annotation: ScreenshotAnnotation,
        stepNumber: Int,
        in context: CGContext
    ) {
        guard let center = annotation.points.first else {
            return
        }

        let diameter = stepBubbleDiameter(for: annotation.style)
        let bubbleRect = CGRect(
            x: center.x - diameter / 2,
            y: center.y - diameter / 2,
            width: diameter,
            height: diameter
        )

        context.setFillColor(annotation.style.colorComponents.cgColor)
        context.fillEllipse(in: bubbleRect)
        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.92))
        context.setLineWidth(max(2, diameter * 0.08))
        context.strokeEllipse(in: bubbleRect.insetBy(dx: 1, dy: 1))

        let text = "\(stepNumber)"
        let fontSize = min(max(annotation.style.fontSize * 0.78, 12), diameter * 0.52)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: CTFontCreateWithName("HelveticaNeue-Bold" as CFString, fontSize, nil),
            .foregroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributedText)
        let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        let textOrigin = CGPoint(
            x: center.x - bounds.width / 2 - bounds.minX,
            y: center.y - bounds.height / 2 - bounds.minY
        )

        context.textMatrix = .identity
        context.textPosition = textOrigin
        CTLineDraw(line, context)
    }

    nonisolated private static func drawStepDescription(
        _ annotation: ScreenshotAnnotation,
        in context: CGContext
    ) {
        guard let center = annotation.points.first,
              let text = annotation.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return
        }

        let diameter = stepBubbleDiameter(for: annotation.style)
        let origin = CGPoint(
            x: center.x + diameter / 2 + 8,
            y: center.y - annotation.style.fontSize * 0.38
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: annotation.style.ctFont,
            .foregroundColor: annotation.style.colorComponents.cgColor
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributedText)

        context.textMatrix = .identity
        context.textPosition = origin
        CTLineDraw(line, context)
    }

    nonisolated static func stepBubbleDiameter(for style: ScreenshotAnnotationStyle) -> CGFloat {
        max(style.fontSize + 14, 30)
    }

    nonisolated private static func drawMosaic(
        _ annotation: ScreenshotAnnotation,
        in context: CGContext,
        baseImage: CGImage?,
        scale: CGSize
    ) {
        switch annotation.style.mosaicMode {
        case .rectangle:
            drawMosaic(
                in: annotation.rect,
                blockSize: annotation.style.mosaicBlockSize,
                context: context,
                baseImage: baseImage,
                scale: scale
            )
        case .brush:
            drawMosaicBrush(
                annotation,
                in: context,
                baseImage: baseImage,
                scale: scale
            )
        }
    }

    nonisolated private static func drawMosaicBrush(
        _ annotation: ScreenshotAnnotation,
        in context: CGContext,
        baseImage: CGImage?,
        scale: CGSize
    ) {
        guard !annotation.points.isEmpty else {
            return
        }

        let brushSize = max(annotation.style.mosaicBrushSize, 8)
        annotation.points.forEach { point in
            drawMosaic(
                in: CGRect(
                    x: point.x - brushSize / 2,
                    y: point.y - brushSize / 2,
                    width: brushSize,
                    height: brushSize
                ),
                blockSize: annotation.style.mosaicBlockSize,
                context: context,
                baseImage: baseImage,
                scale: scale
            )
        }
    }

    nonisolated private static func drawMosaic(
        in rect: CGRect,
        blockSize requestedBlockSize: CGFloat,
        context: CGContext,
        baseImage: CGImage?,
        scale: CGSize
    ) {
        guard !rect.isNull, rect.width > 0, rect.height > 0 else {
            return
        }

        guard let baseImage,
              scale.width > 0,
              scale.height > 0 else {
            drawMosaicPlaceholder(in: rect, blockSize: requestedBlockSize, context: context)
            return
        }

        let blockSize = max(requestedBlockSize, 6)
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX
            while x < rect.maxX {
                let blockRect = CGRect(
                    x: x,
                    y: y,
                    width: min(blockSize, rect.maxX - x),
                    height: min(blockSize, rect.maxY - y)
                )
                fillMosaicBlock(blockRect, baseImage: baseImage, scale: scale, context: context)
                x += blockSize
            }
            y += blockSize
        }
    }

    nonisolated private static func drawMosaicPlaceholder(
        in rect: CGRect,
        blockSize requestedBlockSize: CGFloat,
        context: CGContext
    ) {
        let blockSize = max(requestedBlockSize, 6)
        var y = rect.minY
        var row = 0
        while y < rect.maxY {
            var x = rect.minX
            var column = 0
            while x < rect.maxX {
                let alpha: CGFloat = (row + column).isMultiple(of: 2) ? 0.88 : 0.74
                context.setFillColor(CGColor(gray: 0.72, alpha: alpha))
                context.fill(CGRect(
                    x: x,
                    y: y,
                    width: min(blockSize, rect.maxX - x),
                    height: min(blockSize, rect.maxY - y)
                ))
                x += blockSize
                column += 1
            }
            y += blockSize
            row += 1
        }
    }

    nonisolated private static func fillMosaicBlock(
        _ blockRect: CGRect,
        baseImage: CGImage,
        scale: CGSize,
        context: CGContext
    ) {
        let samplePoint = CGPoint(
            x: blockRect.midX * scale.width,
            y: blockRect.midY * scale.height
        )
        let sourceRect = CGRect(
            x: min(max(floor(samplePoint.x), 0), CGFloat(baseImage.width - 1)),
            y: min(max(floor(samplePoint.y), 0), CGFloat(baseImage.height - 1)),
            width: 1,
            height: 1
        )

        guard let sample = baseImage.cropping(to: sourceRect) else {
            return
        }

        context.interpolationQuality = .none
        context.draw(sample, in: blockRect)
    }
}

private extension ScreenshotColorComponents {
    nonisolated var cgColor: CGColor {
        CGColor(
            red: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    }
}

private extension ScreenshotAnnotationStyle {
    nonisolated var ctFont: CTFont {
        CTFontCreateWithName(fontWeight.postScriptName as CFString, fontSize, nil)
    }
}

private extension ScreenshotTextWeight {
    nonisolated var postScriptName: String {
        switch self {
        case .regular:
            "HelveticaNeue"
        case .medium:
            "HelveticaNeue-Medium"
        case .bold:
            "HelveticaNeue-Bold"
        }
    }
}
