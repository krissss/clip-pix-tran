import Foundation
import Testing
@testable import ClipPixTran

@MainActor
struct ClipboardHistoryStoreTests {
    @Test func recordsNewTextAtTop() {
        let store = ClipboardHistoryStore()
        let firstDate = Date(timeIntervalSince1970: 10)
        let secondDate = Date(timeIntervalSince1970: 20)

        store.record("first", at: firstDate)
        store.record("second", at: secondDate)

        #expect(store.items.map(\.text) == ["second", "first"])
        #expect(store.items.first?.createdAt == secondDate)
        #expect(store.items.first?.lastCopiedAt == secondDate)
    }

    @Test func ignoresEmptyText() {
        let store = ClipboardHistoryStore()

        store.record("")
        store.record("   \n\t   ")

        #expect(store.items.isEmpty)
    }

    @Test func preservesWhitespaceForRecordedText() {
        let store = ClipboardHistoryStore()

        store.record("  useful text\n")

        #expect(store.items.map(\.text) == ["  useful text\n"])
    }

    @Test func deduplicatesRepeatedText() {
        let store = ClipboardHistoryStore()

        store.record("same")
        store.record("same")

        #expect(store.items.count == 1)
        #expect(store.items.first?.text == "same")
    }

    @Test func repeatedTextKeepsLatestPayloads() throws {
        let store = ClipboardHistoryStore()
        let richTextPayload = ClipboardPayload(
            type: "public.html",
            data: try #require("<b>same</b>".data(using: .utf8))
        )

        store.record("same")
        store.record(ClipboardItem(text: "same", payloads: [richTextPayload]))

        let item = try #require(store.items.first)
        #expect(store.items.count == 1)
        #expect(item.text == "same")
        #expect(item.payloads == [richTextPayload])
    }

    @Test func recordsImageItems() throws {
        let store = ClipboardHistoryStore()
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])

        store.record(ClipboardItem(imageData: imageData))

        let item = try #require(store.items.first)
        #expect(item.kind == .image)
        #expect(item.imageData == imageData)
    }

    @Test func recordsFileItems() throws {
        let store = ClipboardHistoryStore()

        store.record(ClipboardItem(filePaths: ["/tmp/report.pdf", "/tmp/photo.png"]))

        let item = try #require(store.items.first)
        #expect(item.kind == .file)
        #expect(item.filePaths == ["/tmp/report.pdf", "/tmp/photo.png"])
    }

    @Test func deduplicatesRepeatedFiles() {
        let store = ClipboardHistoryStore()
        let firstDate = Date(timeIntervalSince1970: 10)
        let secondDate = Date(timeIntervalSince1970: 20)
        let item = ClipboardItem(filePaths: ["/tmp/report.pdf"])

        store.record(item, at: firstDate)
        store.record(item, at: secondDate)

        #expect(store.items.count == 1)
        #expect(store.items.first?.lastCopiedAt == secondDate)
    }

    @Test func movesRepeatedTextToTop() {
        let store = ClipboardHistoryStore()
        let firstDate = Date(timeIntervalSince1970: 10)
        let secondDate = Date(timeIntervalSince1970: 20)
        let repeatedDate = Date(timeIntervalSince1970: 30)

        store.record("first", at: firstDate)
        store.record("second", at: secondDate)
        store.record("first", at: repeatedDate)

        #expect(store.items.map(\.text) == ["first", "second"])
        #expect(store.items.first?.createdAt == firstDate)
        #expect(store.items.first?.lastCopiedAt == repeatedDate)
    }

    @Test func trimsHistoryToLimit() {
        let store = ClipboardHistoryStore(limit: 3)

        store.record("one")
        store.record("two")
        store.record("three")
        store.record("four")

        #expect(store.items.map(\.text) == ["four", "three", "two"])
    }

    @Test func filtersItemsWithoutChangingOrder() {
        let store = ClipboardHistoryStore()

        store.record("Design note")
        store.record("Release checklist")
        store.record("daily note")

        let filteredItems = store.filteredItems(matching: "NOTE")

        #expect(filteredItems.map(\.text) == ["daily note", "Design note"])
        #expect(store.items.map(\.text) == ["daily note", "Release checklist", "Design note"])
    }

    @Test func filtersFileItemsByFilename() {
        let store = ClipboardHistoryStore()

        store.record("plain text")
        store.record(ClipboardItem(filePaths: ["/tmp/design-brief.pdf"]))

        let filteredItems = store.filteredItems(matching: "brief")

        #expect(filteredItems.map(\.kind) == [.file])
    }

    @Test func emptySearchReturnsAllItems() {
        let store = ClipboardHistoryStore()

        store.record("one")
        store.record("two")

        #expect(store.filteredItems(matching: "   ").map(\.text) == ["two", "one"])
    }

    @Test func deletesSingleItem() throws {
        let store = ClipboardHistoryStore()

        store.record("keep")
        store.record("delete")
        let item = try #require(store.items.first)

        store.delete(item)

        #expect(store.items.map(\.text) == ["keep"])
    }

    @Test func togglesPinnedItemToTop() throws {
        let store = ClipboardHistoryStore()
        let firstDate = Date(timeIntervalSince1970: 10)
        let secondDate = Date(timeIntervalSince1970: 20)

        store.record("first", at: firstDate)
        store.record("second", at: secondDate)
        let firstItem = try #require(store.items.last)

        store.togglePinned(firstItem)

        #expect(store.items.map(\.text) == ["first", "second"])
        #expect(store.items.first?.isPinned == true)
    }

    @Test func pinnedItemsDoNotGetTrimmed() throws {
        let store = ClipboardHistoryStore(limit: 2)

        store.record("one")
        let pinnedItem = try #require(store.items.first)
        store.togglePinned(pinnedItem)
        store.record("two")
        store.record("three")
        store.record("four")

        #expect(store.items.map(\.text) == ["one", "four", "three"])
        #expect(store.items.first?.isPinned == true)
    }

    @Test func clearsOnlyUnpinnedItems() throws {
        let store = ClipboardHistoryStore()

        store.record("keep")
        let pinnedItem = try #require(store.items.first)
        store.togglePinned(pinnedItem)
        store.record("remove")

        store.clearUnpinned()

        #expect(store.items.map(\.text) == ["keep"])
        #expect(store.items.first?.isPinned == true)
    }

    @Test func defaultsToPersistingHistory() {
        let store = ClipboardHistoryStore()

        #expect(store.persistsHistory == true)
    }

    @Test func persistsHistorySnapshot() async throws {
        let fileURL = temporaryFileURL()
        let persistence = FileClipboardHistoryPersistence(fileURL: fileURL)
        let store = ClipboardHistoryStore(
            limit: 20,
            persistsHistory: true,
            persistence: persistence
        )

        store.record("persisted")
        let item = try #require(store.items.first)
        store.togglePinned(item)
        store.updateLimit(10)
        await store.waitForPendingPersistence()

        let reloadedStore = ClipboardHistoryStore(
            persistence: FileClipboardHistoryPersistence(fileURL: fileURL)
        )

        #expect(reloadedStore.items.map(\.text) == ["persisted"])
        #expect(reloadedStore.items.first?.isPinned == true)
        #expect(reloadedStore.limit == 10)
        #expect(reloadedStore.persistsHistory == true)
    }

    @Test func explicitPersistencePreferenceOverridesSnapshot() async throws {
        let fileURL = temporaryFileURL()
        let defaults = makeDefaults()
        let persistence = FileClipboardHistoryPersistence(fileURL: fileURL)
        let store = ClipboardHistoryStore(
            persistsHistory: true,
            persistence: persistence,
            persistsHistoryDefaultsKey: "clip.persistsHistory",
            defaults: defaults
        )

        store.record("temporary")
        store.updatePersistsHistory(false)
        await store.waitForPendingPersistence()

        let reloadedStore = ClipboardHistoryStore(
            persistence: persistence,
            persistsHistoryDefaultsKey: "clip.persistsHistory",
            defaults: defaults
        )

        #expect(reloadedStore.persistsHistory == false)
        #expect(reloadedStore.items.isEmpty)
    }

    @Test func legacySnapshotCanRestorePersistencePreference() async throws {
        let fileURL = temporaryFileURL()
        let persistence = FileClipboardHistoryPersistence(fileURL: fileURL)
        let store = ClipboardHistoryStore(
            persistsHistory: false,
            persistence: persistence
        )

        store.updatePersistsHistory(true)
        store.record("legacy")
        store.updatePersistsHistory(false)
        await store.waitForPendingPersistence()
        try persistence.saveSnapshot(
            ClipboardHistorySnapshot(
                items: store.items,
                maximumNormalItems: store.limit,
                persistsHistory: false
            )
        )

        let reloadedStore = ClipboardHistoryStore(persistence: persistence)

        #expect(reloadedStore.persistsHistory == false)
    }

    @Test func disablingPersistenceDeletesSnapshot() async throws {
        let fileURL = temporaryFileURL()
        let persistence = FileClipboardHistoryPersistence(fileURL: fileURL)
        let store = ClipboardHistoryStore(persistence: persistence)

        store.record("temporary")
        await store.waitForPendingPersistence()
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        store.updatePersistsHistory(false)
        await store.waitForPendingPersistence()

        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        #expect(store.items.map(\.text) == ["temporary"])
    }

    @Test func persistsImageAndFileItems() async throws {
        let fileURL = temporaryFileURL()
        let persistence = FileClipboardHistoryPersistence(fileURL: fileURL)
        let store = ClipboardHistoryStore(persistence: persistence)
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])

        store.record(ClipboardItem(imageData: imageData))
        store.record(ClipboardItem(filePaths: ["/tmp/report.pdf"]))
        await store.waitForPendingPersistence()

        let reloadedStore = ClipboardHistoryStore(
            persistence: FileClipboardHistoryPersistence(fileURL: fileURL)
        )

        #expect(reloadedStore.items.map(\.kind) == [.file, .image])
        #expect(reloadedStore.items.first?.filePaths == ["/tmp/report.pdf"])
        #expect(reloadedStore.items.last?.imageData == imageData)
    }

    @Test func persistsRichTextPayloads() async throws {
        let fileURL = temporaryFileURL()
        let persistence = FileClipboardHistoryPersistence(fileURL: fileURL)
        let store = ClipboardHistoryStore(persistence: persistence)
        let payload = ClipboardPayload(
            type: "public.rtf",
            data: try #require("{\\rtf1 rich}".data(using: .utf8))
        )

        store.record(ClipboardItem(text: "rich", payloads: [payload]))
        await store.waitForPendingPersistence()

        let reloadedStore = ClipboardHistoryStore(
            persistence: FileClipboardHistoryPersistence(fileURL: fileURL)
        )

        let item = try #require(reloadedStore.items.first)
        #expect(item.text == "rich")
        #expect(item.payloads == [payload])
    }

    @Test func updatesLimitAndTrimsNormalItems() {
        let store = ClipboardHistoryStore(limit: 5)

        store.record("one")
        store.record("two")
        store.record("three")
        store.updateLimit(2)

        #expect(store.items.map(\.text) == ["three", "two"])
        #expect(store.limit == 2)
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .appending(path: "clipboard-history.json")
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "ClipboardHistoryStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
