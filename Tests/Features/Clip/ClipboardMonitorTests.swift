import Foundation
import Testing
@testable import ClipPixTran

@MainActor
struct ClipboardMonitorTests {
    @Test func unchangedPasteboardDoesNotRecordText() {
        let pasteboard = FakeClipboardService(text: "existing")
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            history: ClipboardHistoryStore()
        )

        monitor.refreshIfNeeded()

        #expect(monitor.history.items.isEmpty)
    }

    @Test func changedPasteboardRecordsPlainText() {
        let pasteboard = FakeClipboardService()
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            history: ClipboardHistoryStore()
        )

        pasteboard.simulateExternalChange(text: "copied text")
        monitor.refreshIfNeeded()

        #expect(monitor.history.items.map(\.text) == ["copied text"])
        #expect(monitor.lastErrorMessage == nil)
    }

    @Test func changedPasteboardWithoutTextDoesNotRecord() {
        let pasteboard = FakeClipboardService()
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            history: ClipboardHistoryStore()
        )

        pasteboard.simulateExternalChange(text: nil)
        monitor.refreshIfNeeded()

        #expect(monitor.history.items.isEmpty)
    }

    @Test func copyingHistoryItemWritesPasteboardAndRecordsHistory() {
        let pasteboard = FakeClipboardService()
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            history: ClipboardHistoryStore()
        )
        let item = ClipboardItem(text: "saved clip")
        monitor.lastErrorMessage = "旧错误"

        monitor.copyToPasteboard(item)
        pasteboard.replaceTextWithoutChangingCount("external")
        monitor.refreshIfNeeded()

        #expect(pasteboard.text == "external")
        #expect(monitor.history.items.map(\.text) == ["saved clip"])
        #expect(monitor.lastErrorMessage == nil)
    }

    @Test func copyFailureSetsErrorAndDoesNotRecordHistory() {
        let pasteboard = FakeClipboardService(writeError: ClipboardWriteError.rejected)
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            history: ClipboardHistoryStore()
        )
        let item = ClipboardItem(text: "saved clip")

        monitor.copyToPasteboard(item)

        #expect(pasteboard.text == nil)
        #expect(monitor.history.items.isEmpty)
        #expect(monitor.lastErrorMessage == ClipboardWriteError.rejected.localizedDescription)
    }

    @Test func clearHistoryRemovesRecordedItems() {
        let pasteboard = FakeClipboardService()
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            history: ClipboardHistoryStore()
        )
        monitor.history.record("one")
        monitor.history.record("two")

        monitor.clearHistory()

        #expect(monitor.history.items.isEmpty)
    }
}

private final class FakeClipboardService: ClipboardService {
    private(set) var text: String?
    private(set) var changeCount: Int
    private let writeError: Error?

    init(
        text: String? = nil,
        changeCount: Int = 0,
        writeError: Error? = nil
    ) {
        self.text = text
        self.changeCount = changeCount
        self.writeError = writeError
    }

    func readPlainText() -> String? {
        text
    }

    func writePlainText(_ text: String) throws {
        if let writeError {
            throw writeError
        }

        self.text = text
        changeCount += 1
    }

    func simulateExternalChange(text: String?) {
        self.text = text
        changeCount += 1
    }

    func replaceTextWithoutChangingCount(_ text: String?) {
        self.text = text
    }
}
