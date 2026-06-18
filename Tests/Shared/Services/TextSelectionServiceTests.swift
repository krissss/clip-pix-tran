import Testing
@testable import ClipPixTran

@MainActor
struct TextSelectionServiceTests {
    @Test func prefersClipboardSelectionToPreserveFormatting() async {
        let service = SystemTextSelectionService(
            accessibilityGrabber: { "Providers: System Google Apple" },
            clipboardGrabber: {
                "\n  Providers\n\n- System\n- Google\n- Apple\n\n"
            }
        )

        let text = await service.selectedText()

        #expect(
            text ==
                """
                Providers

                - System
                - Google
                - Apple
                """
        )
    }

    @Test func fallsBackToAccessibilityWhenClipboardIsEmpty() async {
        let service = SystemTextSelectionService(
            accessibilityGrabber: { "  accessibility text\n" },
            clipboardGrabber: { "   " }
        )

        let text = await service.selectedText()

        #expect(text == "accessibility text")
    }

    @Test func returnsNilWhenNoGrabberFindsText() async {
        let service = SystemTextSelectionService(
            accessibilityGrabber: { nil },
            clipboardGrabber: { "\n\t  " }
        )

        let text = await service.selectedText()

        #expect(text == nil)
    }

}
