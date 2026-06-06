import Testing
@testable import ClipPixTran

@MainActor
struct TextSelectionServiceTests {
    @Test func returnsTrimmedAccessibilitySelection() async {
        let service = SystemTextSelectionService(
            accessibilityGrabber: { "  hello  " },
            clipboardGrabber: { "fallback" }
        )

        let text = await service.selectedText()

        #expect(text == "hello")
    }

    @Test func fallsBackToClipboardWhenAccessibilityIsEmpty() async {
        let service = SystemTextSelectionService(
            accessibilityGrabber: { "   " },
            clipboardGrabber: { "  clipboard text\n" }
        )

        let text = await service.selectedText()

        #expect(text == "clipboard text")
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
