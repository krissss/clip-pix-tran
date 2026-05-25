import Foundation
import Testing
@testable import ClipPixTran

@MainActor
struct TranslationHistoryStoreTests {
    @Test func recordsTranslationAtTop() {
        let store = TranslationHistoryStore()
        let firstRequest = TranslationRequest(
            sourceText: "hello",
            targetLanguageCode: "zh-Hans",
            sourceLanguageCode: "en"
        )
        let secondRequest = TranslationRequest(
            sourceText: "world",
            targetLanguageCode: "ja",
            sourceLanguageCode: "en"
        )

        store.record(
            request: firstRequest,
            result: TranslationResult(
                translatedText: "你好",
                sourceLanguageCode: "en",
                targetLanguageCode: "zh-Hans"
            ),
            at: Date(timeIntervalSince1970: 10)
        )
        store.record(
            request: secondRequest,
            result: TranslationResult(
                translatedText: "世界",
                sourceLanguageCode: "en",
                targetLanguageCode: "ja"
            ),
            at: Date(timeIntervalSince1970: 20)
        )

        #expect(store.items.map(\.sourceText) == ["world", "hello"])
        #expect(store.items.first?.targetLanguageCode == "ja")
    }

    @Test func deduplicatesSameSourceAndTarget() {
        let store = TranslationHistoryStore()
        let request = TranslationRequest(
            sourceText: "hello",
            targetLanguageCode: "zh-Hans",
            sourceLanguageCode: "en"
        )

        store.record(
            request: request,
            result: TranslationResult(
                translatedText: "你好",
                sourceLanguageCode: "en",
                targetLanguageCode: "zh-Hans"
            )
        )
        store.record(
            request: request,
            result: TranslationResult(
                translatedText: "您好",
                sourceLanguageCode: "en",
                targetLanguageCode: "zh-Hans"
            )
        )

        #expect(store.items.count == 1)
        #expect(store.items.first?.translatedText == "您好")
    }

    @Test func trimsToLimit() {
        let store = TranslationHistoryStore(limit: 2)

        store.record(
            request: TranslationRequest(sourceText: "one", targetLanguageCode: "zh-Hans", sourceLanguageCode: nil),
            result: TranslationResult(translatedText: "一", sourceLanguageCode: nil, targetLanguageCode: "zh-Hans")
        )
        store.record(
            request: TranslationRequest(sourceText: "two", targetLanguageCode: "zh-Hans", sourceLanguageCode: nil),
            result: TranslationResult(translatedText: "二", sourceLanguageCode: nil, targetLanguageCode: "zh-Hans")
        )
        store.record(
            request: TranslationRequest(sourceText: "three", targetLanguageCode: "zh-Hans", sourceLanguageCode: nil),
            result: TranslationResult(translatedText: "三", sourceLanguageCode: nil, targetLanguageCode: "zh-Hans")
        )

        #expect(store.items.map(\.sourceText) == ["three", "two"])
    }

    @Test func defaultsToPersistingHistory() {
        let store = TranslationHistoryStore()

        #expect(store.persistsHistory == true)
    }

    @Test func persistsHistorySnapshot() async throws {
        let fileURL = temporaryFileURL()
        let store = TranslationHistoryStore(
            limit: 20,
            persistsHistory: true,
            persistence: FileTranslationHistoryPersistence(fileURL: fileURL)
        )

        store.record(
            request: TranslationRequest(sourceText: "hello", targetLanguageCode: "zh-Hans", sourceLanguageCode: "en"),
            result: TranslationResult(translatedText: "你好", sourceLanguageCode: "en", targetLanguageCode: "zh-Hans"),
            at: Date(timeIntervalSince1970: 10)
        )
        store.record(
            request: TranslationRequest(sourceText: "world", targetLanguageCode: "ja", sourceLanguageCode: "en"),
            result: TranslationResult(translatedText: "世界", sourceLanguageCode: "en", targetLanguageCode: "ja"),
            at: Date(timeIntervalSince1970: 20)
        )
        store.updateLimit(10)
        await store.waitForPendingPersistence()

        let reloadedStore = TranslationHistoryStore(
            persistence: FileTranslationHistoryPersistence(fileURL: fileURL)
        )

        #expect(reloadedStore.items.map(\.sourceText) == ["world", "hello"])
        #expect(reloadedStore.limit == 10)
        #expect(reloadedStore.persistsHistory == true)
    }

    @Test func explicitPersistencePreferenceOverridesSnapshot() async throws {
        let fileURL = temporaryFileURL()
        let defaults = makeDefaults()
        let persistence = FileTranslationHistoryPersistence(fileURL: fileURL)
        let store = TranslationHistoryStore(
            persistsHistory: true,
            persistence: persistence,
            persistsHistoryDefaultsKey: "tran.persistsHistory",
            defaults: defaults
        )

        store.record(
            request: TranslationRequest(sourceText: "temporary", targetLanguageCode: "zh-Hans", sourceLanguageCode: "en"),
            result: TranslationResult(translatedText: "临时", sourceLanguageCode: "en", targetLanguageCode: "zh-Hans")
        )
        store.updatePersistsHistory(false)
        await store.waitForPendingPersistence()

        let reloadedStore = TranslationHistoryStore(
            persistence: persistence,
            persistsHistoryDefaultsKey: "tran.persistsHistory",
            defaults: defaults
        )

        #expect(reloadedStore.persistsHistory == false)
        #expect(reloadedStore.items.isEmpty)
    }

    @Test func disablingPersistenceDeletesSnapshot() async throws {
        let fileURL = temporaryFileURL()
        let store = TranslationHistoryStore(
            persistsHistory: true,
            persistence: FileTranslationHistoryPersistence(fileURL: fileURL)
        )

        store.record(
            request: TranslationRequest(sourceText: "temporary", targetLanguageCode: "zh-Hans", sourceLanguageCode: "en"),
            result: TranslationResult(translatedText: "临时", sourceLanguageCode: "en", targetLanguageCode: "zh-Hans")
        )
        await store.waitForPendingPersistence()
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        store.updatePersistsHistory(false)
        await store.waitForPendingPersistence()

        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        #expect(store.items.map(\.sourceText) == ["temporary"])
    }

    @Test func updatesLimitAndTrimsItems() {
        let store = TranslationHistoryStore(limit: 5)

        store.record(
            request: TranslationRequest(sourceText: "one", targetLanguageCode: "zh-Hans", sourceLanguageCode: nil),
            result: TranslationResult(translatedText: "一", sourceLanguageCode: nil, targetLanguageCode: "zh-Hans")
        )
        store.record(
            request: TranslationRequest(sourceText: "two", targetLanguageCode: "zh-Hans", sourceLanguageCode: nil),
            result: TranslationResult(translatedText: "二", sourceLanguageCode: nil, targetLanguageCode: "zh-Hans")
        )
        store.record(
            request: TranslationRequest(sourceText: "three", targetLanguageCode: "zh-Hans", sourceLanguageCode: nil),
            result: TranslationResult(translatedText: "三", sourceLanguageCode: nil, targetLanguageCode: "zh-Hans")
        )
        store.updateLimit(2)

        #expect(store.items.map(\.sourceText) == ["three", "two"])
        #expect(store.limit == 2)
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .appending(path: "translation-history.json")
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "TranslationHistoryStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
