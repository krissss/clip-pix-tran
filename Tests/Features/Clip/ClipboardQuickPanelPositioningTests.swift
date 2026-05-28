import CoreGraphics
import Testing
@testable import ClipPixTran

struct ClipboardQuickPanelPositioningTests {
    @Test func placesPanelAtLowerRightOfMouseWhenThereIsRoom() {
        let origin = ClipboardQuickPanelPositioning.panelOrigin(
            near: CGPoint(x: 320, y: 700),
            panelSize: CGSize(width: 420, height: 430),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )

        #expect(origin == CGPoint(x: 328, y: 262))
    }

    @Test func placesPanelAboveMouseWhenBelowWouldOverflow() {
        let origin = ClipboardQuickPanelPositioning.panelOrigin(
            near: CGPoint(x: 320, y: 220),
            panelSize: CGSize(width: 420, height: 430),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )

        #expect(origin == CGPoint(x: 328, y: 228))
    }

    @Test func placesPanelLeftOfMouseWhenRightWouldOverflow() {
        let origin = ClipboardQuickPanelPositioning.panelOrigin(
            near: CGPoint(x: 1260, y: 700),
            panelSize: CGSize(width: 420, height: 430),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )

        #expect(origin == CGPoint(x: 832, y: 262))
    }

    @Test func clampsPanelInsideVisibleFrame() {
        let origin = ClipboardQuickPanelPositioning.panelOrigin(
            near: CGPoint(x: 1410, y: 40),
            panelSize: CGSize(width: 420, height: 430),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )

        #expect(origin == CGPoint(x: 982, y: 48))
    }
}
