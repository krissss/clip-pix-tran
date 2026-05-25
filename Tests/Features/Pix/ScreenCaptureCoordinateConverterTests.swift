import CoreGraphics
import Testing
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
}
