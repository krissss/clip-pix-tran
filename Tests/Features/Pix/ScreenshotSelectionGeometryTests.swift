import CoreGraphics
import Testing
@testable import ClipPixTran

struct ScreenshotSelectionGeometryTests {
    @Test func createsStandardizedRectClampedToBounds() {
        let rect = ScreenshotSelectionGeometry.rect(
            from: CGPoint(x: 180, y: 160),
            to: CGPoint(x: -20, y: 40),
            clampedTo: CGRect(x: 0, y: 0, width: 200, height: 180)
        )

        #expect(rect == CGRect(x: 0, y: 40, width: 180, height: 120))
    }

    @Test func ignoresTinySelection() {
        let rect = ScreenshotSelectionGeometry.rect(
            from: CGPoint(x: 10, y: 10),
            to: CGPoint(x: 18, y: 18),
            clampedTo: CGRect(x: 0, y: 0, width: 200, height: 180)
        )

        #expect(rect == nil)
    }

    @Test func movingSelectionClampsInsideBounds() {
        let rect = ScreenshotSelectionGeometry.moved(
            CGRect(x: 40, y: 50, width: 80, height: 70),
            by: CGSize(width: 200, height: -100),
            clampedTo: CGRect(x: 0, y: 0, width: 220, height: 180)
        )

        #expect(rect == CGRect(x: 140, y: 0, width: 80, height: 70))
    }

    @Test func resizeKeepsMinimumSize() {
        let rect = ScreenshotSelectionGeometry.resized(
            CGRect(x: 20, y: 30, width: 80, height: 70),
            handle: .right,
            to: CGPoint(x: 24, y: 40),
            clampedTo: CGRect(x: 0, y: 0, width: 200, height: 180)
        )

        #expect(rect == CGRect(x: 20, y: 30, width: 16, height: 70))
    }

    @Test func detectsMoveAndCornerHandles() {
        let rect = CGRect(x: 20, y: 30, width: 80, height: 70)

        #expect(ScreenshotSelectionGeometry.handle(at: CGPoint(x: 20, y: 30), in: rect) == .topLeft)
        #expect(ScreenshotSelectionGeometry.handle(at: CGPoint(x: 50, y: 50), in: rect) == .move)
        #expect(ScreenshotSelectionGeometry.handle(at: CGPoint(x: 1, y: 1), in: rect) == nil)
    }
}
