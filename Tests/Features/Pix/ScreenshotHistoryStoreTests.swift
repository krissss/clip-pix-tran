import Foundation
import Testing
@testable import ClipPixTran

@MainActor
struct ScreenshotHistoryStoreTests {
    @Test func recordsScreenshotAtTop() throws {
        let store = ScreenshotHistoryStore()
        let firstData = try #require("first".data(using: .utf8))
        let secondData = try #require("second".data(using: .utf8))
        let firstDate = Date(timeIntervalSince1970: 10)
        let secondDate = Date(timeIntervalSince1970: 20)

        store.record(firstData, at: firstDate)
        store.record(secondData, at: secondDate)

        #expect(store.items.map(\.data) == [secondData, firstData])
        #expect(store.items.first?.createdAt == secondDate)
    }

    @Test func recordsRecordingAtTop() throws {
        let fileStore = FakeRecordingFileStore()
        let store = ScreenshotHistoryStore(recordingFileStore: fileStore)
        let fileURL = ScreenRecordingFileStore.defaultDirectoryURL
            .appending(path: "clip.mp4")
        let createdAt = Date(timeIntervalSince1970: 30)

        store.record(
            ScreenRecordingOutput(
                fileURL: fileURL,
                createdAt: createdAt,
                duration: 3.2,
                pixelSize: CGSize(width: 640, height: 360),
                fileSize: 1024
            )
        )

        let item = try #require(store.items.first)
        #expect(item.kind == .recording)
        #expect(item.recordingFileName == "clip.mp4")
        #expect(item.createdAt == createdAt)
        #expect(item.duration == 3.2)
        #expect(item.pixelSize == CGSize(width: 640, height: 360))
        #expect(item.byteCount == 1024)
        #expect(fileStore.deletedFileNames.isEmpty)
    }

    @Test func ignoresEmptyData() {
        let store = ScreenshotHistoryStore()

        store.record(Data())

        #expect(store.items.isEmpty)
    }

    @Test func trimsToLimit() throws {
        let store = ScreenshotHistoryStore(limit: 2)
        let firstData = try #require("first".data(using: .utf8))
        let secondData = try #require("second".data(using: .utf8))
        let thirdData = try #require("third".data(using: .utf8))

        store.record(firstData)
        store.record(secondData)
        store.record(thirdData)

        #expect(store.items.map(\.data) == [thirdData, secondData])
    }

    @Test func deletesSingleItem() throws {
        let store = ScreenshotHistoryStore()
        let keepData = try #require("keep".data(using: .utf8))
        let deleteData = try #require("delete".data(using: .utf8))

        store.record(keepData)
        store.record(deleteData)
        let item = try #require(store.items.first)

        store.delete(item)

        #expect(store.items.map(\.data) == [keepData])
    }

    @Test func clearsHistory() throws {
        let store = ScreenshotHistoryStore()
        let data = try #require("shot".data(using: .utf8))

        store.record(data)
        store.clear()

        #expect(store.items.isEmpty)
    }

    @Test func deletingRecordingRemovesStoredFile() throws {
        let fileStore = FakeRecordingFileStore()
        let store = ScreenshotHistoryStore(recordingFileStore: fileStore)
        let fileURL = ScreenRecordingFileStore.defaultDirectoryURL
            .appending(path: "delete-me.mp4")
        store.record(
            ScreenRecordingOutput(
                fileURL: fileURL,
                createdAt: Date(),
                duration: 1,
                pixelSize: CGSize(width: 100, height: 100),
                fileSize: 10
            )
        )
        let item = try #require(store.items.first)

        store.delete(item)

        #expect(store.items.isEmpty)
        #expect(fileStore.deletedFileNames == ["delete-me.mp4"])
    }

    @Test func clearingHistoryRemovesRecordingFiles() throws {
        let fileStore = FakeRecordingFileStore()
        let store = ScreenshotHistoryStore(recordingFileStore: fileStore)
        let firstURL = ScreenRecordingFileStore.defaultDirectoryURL.appending(path: "first.mp4")
        let secondURL = ScreenRecordingFileStore.defaultDirectoryURL.appending(path: "second.mp4")
        store.record(
            ScreenRecordingOutput(
                fileURL: firstURL,
                createdAt: Date(),
                duration: 1,
                pixelSize: CGSize(width: 100, height: 100),
                fileSize: 10
            )
        )
        store.record(
            ScreenRecordingOutput(
                fileURL: secondURL,
                createdAt: Date(),
                duration: 1,
                pixelSize: CGSize(width: 100, height: 100),
                fileSize: 10
            )
        )

        store.clear()

        #expect(store.items.isEmpty)
        #expect(Set(fileStore.deletedFileNames) == Set(["first.mp4", "second.mp4"]))
    }

    @Test func defaultsToPersistingHistory() {
        let store = ScreenshotHistoryStore()

        #expect(store.persistsHistory == true)
    }

    @Test func persistsHistorySnapshot() async throws {
        let fileURL = temporaryFileURL()
        let firstData = try #require("first".data(using: .utf8))
        let secondData = try #require("second".data(using: .utf8))
        let store = ScreenshotHistoryStore(
            limit: 10,
            persistsHistory: true,
            persistence: FileScreenshotHistoryPersistence(fileURL: fileURL)
        )

        store.record(firstData, at: Date(timeIntervalSince1970: 10))
        store.record(secondData, at: Date(timeIntervalSince1970: 20))
        store.updateLimit(5)
        await store.waitForPendingPersistence()

        let reloadedStore = ScreenshotHistoryStore(
            persistence: FileScreenshotHistoryPersistence(fileURL: fileURL)
        )

        #expect(reloadedStore.items.map(\.data) == [secondData, firstData])
        #expect(reloadedStore.limit == 5)
        #expect(reloadedStore.persistsHistory == true)
    }

    @Test func decodesLegacyImageItemsWithoutKind() throws {
        let data = try #require("legacy".data(using: .utf8))
        let itemID = UUID()
        let createdAt = Date(timeIntervalSince1970: 42)
        let encodedData = data.base64EncodedString()
        let json = """
        {
          "items": [
            {
              "id": "\(itemID.uuidString)",
              "data": "\(encodedData)",
              "createdAt": \(createdAt.timeIntervalSinceReferenceDate)
            }
          ],
          "maximumItems": 20,
          "persistsHistory": true
        }
        """
        let snapshot = try JSONDecoder().decode(
            ScreenshotHistorySnapshot.self,
            from: try #require(json.data(using: .utf8))
        )

        let item = try #require(snapshot.items.first)
        #expect(item.id == itemID)
        #expect(item.kind == .image)
        #expect(item.data == data)
        #expect(item.createdAt == createdAt)
    }

    @Test func explicitPersistencePreferenceOverridesSnapshot() async throws {
        let fileURL = temporaryFileURL()
        let data = try #require("shot".data(using: .utf8))
        let defaults = makeDefaults()
        let persistence = FileScreenshotHistoryPersistence(fileURL: fileURL)
        let store = ScreenshotHistoryStore(
            persistsHistory: true,
            persistence: persistence,
            persistsHistoryDefaultsKey: "pix.persistsHistory",
            defaults: defaults
        )

        store.record(data)
        await store.waitForPendingPersistence()
        store.updatePersistsHistory(false)
        await store.waitForPendingPersistence()

        let reloadedStore = ScreenshotHistoryStore(
            persistence: persistence,
            persistsHistoryDefaultsKey: "pix.persistsHistory",
            defaults: defaults
        )

        #expect(reloadedStore.persistsHistory == false)
        #expect(reloadedStore.items.isEmpty)
    }

    @Test func disablingPersistenceDeletesSnapshot() async throws {
        let fileURL = temporaryFileURL()
        let data = try #require("shot".data(using: .utf8))
        let store = ScreenshotHistoryStore(
            persistsHistory: true,
            persistence: FileScreenshotHistoryPersistence(fileURL: fileURL)
        )

        store.record(data)
        await store.waitForPendingPersistence()
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        store.updatePersistsHistory(false)
        await store.waitForPendingPersistence()

        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        #expect(store.items.map(\.data) == [data])
    }

    @Test func updatesLimitAndTrimsItems() throws {
        let store = ScreenshotHistoryStore(limit: 5)
        let firstData = try #require("first".data(using: .utf8))
        let secondData = try #require("second".data(using: .utf8))
        let thirdData = try #require("third".data(using: .utf8))

        store.record(firstData)
        store.record(secondData)
        store.record(thirdData)
        store.updateLimit(2)

        #expect(store.items.map(\.data) == [thirdData, secondData])
        #expect(store.limit == 2)
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .appending(path: "screenshot-history.json")
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "ScreenshotHistoryStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class FakeRecordingFileStore: ScreenRecordingFileManaging, @unchecked Sendable {
    private(set) var deletedFileNames: [String] = []

    func makeRecordingURL(createdAt: Date) throws -> URL {
        ScreenRecordingFileStore.defaultDirectoryURL.appending(path: "fake.mp4")
    }

    func deleteRecording(named fileName: String) {
        deletedFileNames.append(fileName)
    }
}
