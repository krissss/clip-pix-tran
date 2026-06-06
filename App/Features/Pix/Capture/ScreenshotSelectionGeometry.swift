import CoreGraphics

enum ScreenshotSelectionHandle: Sendable {
    case move
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
}

extension ScreenshotSelectionHandle: Equatable {
    nonisolated static func == (
        lhs: ScreenshotSelectionHandle,
        rhs: ScreenshotSelectionHandle
    ) -> Bool {
        switch (lhs, rhs) {
        case (.move, .move),
            (.topLeft, .topLeft),
            (.top, .top),
            (.topRight, .topRight),
            (.right, .right),
            (.bottomRight, .bottomRight),
            (.bottom, .bottom),
            (.bottomLeft, .bottomLeft),
            (.left, .left):
            true
        default:
            false
        }
    }
}

enum ScreenshotSelectionGeometry {
    static let minimumSize = CGSize(width: 16, height: 16)
    static let handleHitSize: CGFloat = 12

    static func rect(from start: CGPoint, to end: CGPoint, clampedTo bounds: CGRect) -> CGRect? {
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(start.x - end.x),
            height: abs(start.y - end.y)
        ).intersection(bounds).standardized

        guard rect.width >= minimumSize.width,
              rect.height >= minimumSize.height else {
            return nil
        }

        return rect
    }

    static func moved(
        _ rect: CGRect,
        by translation: CGSize,
        clampedTo bounds: CGRect
    ) -> CGRect {
        var movedRect = rect.offsetBy(dx: translation.width, dy: translation.height)

        if movedRect.minX < bounds.minX {
            movedRect.origin.x = bounds.minX
        }
        if movedRect.maxX > bounds.maxX {
            movedRect.origin.x = bounds.maxX - movedRect.width
        }
        if movedRect.minY < bounds.minY {
            movedRect.origin.y = bounds.minY
        }
        if movedRect.maxY > bounds.maxY {
            movedRect.origin.y = bounds.maxY - movedRect.height
        }

        return movedRect.standardized
    }

    static func resized(
        _ rect: CGRect,
        handle: ScreenshotSelectionHandle,
        to point: CGPoint,
        clampedTo bounds: CGRect
    ) -> CGRect {
        guard handle != .move else {
            return rect
        }

        let clampedPoint = CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY

        switch handle {
        case .topLeft:
            minX = min(clampedPoint.x, maxX - minimumSize.width)
            minY = min(clampedPoint.y, maxY - minimumSize.height)
        case .top:
            minY = min(clampedPoint.y, maxY - minimumSize.height)
        case .topRight:
            maxX = max(clampedPoint.x, minX + minimumSize.width)
            minY = min(clampedPoint.y, maxY - minimumSize.height)
        case .right:
            maxX = max(clampedPoint.x, minX + minimumSize.width)
        case .bottomRight:
            maxX = max(clampedPoint.x, minX + minimumSize.width)
            maxY = max(clampedPoint.y, minY + minimumSize.height)
        case .bottom:
            maxY = max(clampedPoint.y, minY + minimumSize.height)
        case .bottomLeft:
            minX = min(clampedPoint.x, maxX - minimumSize.width)
            maxY = max(clampedPoint.y, minY + minimumSize.height)
        case .left:
            minX = min(clampedPoint.x, maxX - minimumSize.width)
        case .move:
            break
        }

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        ).intersection(bounds).standardized
    }

    static func handle(at point: CGPoint, in rect: CGRect) -> ScreenshotSelectionHandle? {
        for (handle, handleRect) in handleRects(for: rect) {
            if handleRect.contains(point) {
                return handle
            }
        }

        if rect.contains(point) {
            return .move
        }

        return nil
    }

    static func handleRects(for rect: CGRect) -> [(ScreenshotSelectionHandle, CGRect)] {
        let size = handleHitSize
        let half = size / 2
        let points: [(ScreenshotSelectionHandle, CGPoint)] = [
            (.topLeft, CGPoint(x: rect.minX, y: rect.minY)),
            (.top, CGPoint(x: rect.midX, y: rect.minY)),
            (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
            (.right, CGPoint(x: rect.maxX, y: rect.midY)),
            (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY)),
            (.bottom, CGPoint(x: rect.midX, y: rect.maxY)),
            (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)),
            (.left, CGPoint(x: rect.minX, y: rect.midY))
        ]

        return points.map { handle, point in
            (
                handle,
                CGRect(
                    x: point.x - half,
                    y: point.y - half,
                    width: size,
                    height: size
                )
            )
        }
    }
}
