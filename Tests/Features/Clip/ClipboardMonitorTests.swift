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

    @Test func changedPasteboardRecordsImage() throws {
        let pasteboard = FakeClipboardService()
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            history: ClipboardHistoryStore()
        )
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])

        pasteboard.simulateExternalChange(item: ClipboardItem(imageData: imageData))
        monitor.refreshIfNeeded()

        let item = try #require(monitor.history.items.first)
        #expect(item.kind == .image)
        #expect(item.imageData == imageData)
    }

    @Test func changedPasteboardRecordsFiles() throws {
        let pasteboard = FakeClipboardService()
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            history: ClipboardHistoryStore()
        )
        let fileItem = ClipboardItem(filePaths: ["/tmp/report.pdf", "/tmp/image.png"])

        pasteboard.simulateExternalChange(item: fileItem)
        monitor.refreshIfNeeded()

        let item = try #require(monitor.history.items.first)
        #expect(item.kind == .file)
        #expect(item.filePaths == ["/tmp/report.pdf", "/tmp/image.png"])
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

    @Test func copyingPlainTextWritesOnlyTextFallback() throws {
        let pasteboard = FakeClipboardService()
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard,
            history: ClipboardHistoryStore()
        )
        let htmlData = try #require("<b>saved clip</b>".data(using: .utf8))
        let item = ClipboardItem(
            text: "saved clip",
            payloads: [
                ClipboardPayload(type: "public.html", data: htmlData)
            ]
        )

        monitor.copyPlainTextToPasteboard(item)

        #expect(pasteboard.text == "saved clip")
        #expect(pasteboard.item?.payloads.isEmpty == true)
        #expect(monitor.history.items.first?.payloads == item.payloads)
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
    private(set) var item: ClipboardItem?
    private(set) var text: String?
    private(set) var changeCount: Int
    private let writeError: Error?

    init(
        text: String? = nil,
        changeCount: Int = 0,
        writeError: Error? = nil
    ) {
        self.text = text
        self.item = text.map { ClipboardItem(text: $0) }
        self.changeCount = changeCount
        self.writeError = writeError
    }

    func readItem() -> ClipboardItem? {
        item
    }

    func writeItem(_ item: ClipboardItem) throws {
        if let writeError {
            throw writeError
        }

        self.item = item
        text = item.text
        changeCount += 1
    }

    func readPlainText() -> String? {
        text
    }

    func writePlainText(_ text: String) throws {
        if let writeError {
            throw writeError
        }

        self.text = text
        item = ClipboardItem(text: text)
        changeCount += 1
    }

    func simulateExternalChange(text: String?) {
        self.text = text
        item = text.map { ClipboardItem(text: $0) }
        changeCount += 1
    }

    func simulateExternalChange(item: ClipboardItem?) {
        self.item = item
        text = item?.text
        changeCount += 1
    }

    func replaceTextWithoutChangingCount(_ text: String?) {
        self.text = text
        item = text.map { ClipboardItem(text: $0) }
    }
}
