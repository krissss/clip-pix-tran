import Foundation

@MainActor
@Observable
final class TranslationHistoryStore {
    private(set) var items: [TranslationHistoryItem] = []
    private(set) var persistenceErrorMessage: String?

    private let persistence: TranslationHistoryPersistence?
    private let persistencePreference: HistoryPersistencePreference
    private let shouldRestorePersistsHistoryFromSnapshot: Bool
    private var isLoading = false
    private var maximumItems: Int
    private var persistTask: Task<Void, Never>?
    private var persistenceGeneration = 0
    var persistsHistory: Bool

    var limit: Int {
        maximumItems
    }

    init(
        limit: Int = 50,
        persistsHistory: Bool? = nil,
        persistence: TranslationHistoryPersistence? = nil,
        persistsHistoryDefaultsKey: String? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.maximumItems = max(1, limit)
        self.persistence = persistence
        self.persistencePreference = HistoryPersistencePreference(
            defaults: defaults,
            key: persistsHistoryDefaultsKey
        )

        if let storedPersistsHistory = persistencePreference.storedValue {
            self.persistsHistory = storedPersistsHistory
            self.shouldRestorePersistsHistoryFromSnapshot = false
        } else if let persistsHistory {
            self.persistsHistory = persistsHistory
            self.shouldRestorePersistsHistoryFromSnapshot = false
        } else {
            self.persistsHistory = true
            self.shouldRestorePersistsHistoryFromSnapshot = true
        }

        loadPersistedSnapshot()
    }

    func updateLimit(_ newLimit: Int) {
        maximumItems = max(1, newLimit)
        trimToLimit()
        persistIfNeeded()
    }

    func updatePersistsHistory(_ shouldPersist: Bool) {
        persistsHistory = shouldPersist
        persistencePreference.save(shouldPersist)

        if shouldPersist {
            persistIfNeeded()
        } else {
            deletePersistedSnapshot()
        }
    }

    func record(
        request: TranslationRequest,
        providerResults: [TranslationProviderResult],
        at date: Date = Date()
    ) {
        let sourceText = request.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanProviderResults = providerResults.compactMap { providerResult -> TranslationProviderResult? in
            let translatedText = providerResult.result.translatedText
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !translatedText.isEmpty else {
                return nil
            }

            return TranslationProviderResult(
                provider: providerResult.provider,
                result: TranslationResult(
                    translatedText: translatedText,
                    sourceLanguageCode: providerResult.result.sourceLanguageCode,
                    targetLanguageCode: providerResult.result.targetLanguageCode
                )
            )
        }
        guard let primaryResult = cleanProviderResults.first else {
            return
        }
        let translatedText = primaryResult.result.translatedText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty, !translatedText.isEmpty else {
            return
        }

        var nextItems = items
        if let existingIndex = nextItems.firstIndex(where: {
            $0.sourceText == sourceText
                && $0.targetLanguageCode == primaryResult.result.targetLanguageCode
        }) {
            nextItems.remove(at: existingIndex)
        }

        nextItems.insert(
            TranslationHistoryItem(
                sourceText: sourceText,
                translatedText: translatedText,
                sourceLanguageCode: request.sourceLanguageCode,
                detectedSourceLanguageCode: primaryResult.result.sourceLanguageCode,
                targetLanguageCode: primaryResult.result.targetLanguageCode,
                providerID: primaryResult.provider.id,
                providerName: primaryResult.provider.name,
                providerResults: cleanProviderResults.map { providerResult in
                    TranslationHistoryProviderResult(
                        providerID: providerResult.provider.id,
                        providerName: providerResult.provider.name,
                        translatedText: providerResult.result.translatedText,
                        detectedSourceLanguageCode: providerResult.result.sourceLanguageCode,
                        targetLanguageCode: providerResult.result.targetLanguageCode
                    )
                },
                createdAt: date
            ),
            at: 0
        )
        items = nextItems
        trimToLimit()
        persistIfNeeded()
    }

    func record(
        request: TranslationRequest,
        providerResult: TranslationProviderResult,
        at date: Date = Date()
    ) {
        record(request: request, providerResults: [providerResult], at: date)
    }

    func record(
        request: TranslationRequest,
        result: TranslationResult,
        at date: Date = Date()
    ) {
        record(
            request: request,
            providerResult: TranslationProviderResult(
                provider: .systemTranslation,
                result: result
            ),
            at: date
        )
    }

    func filteredItems(matching searchText: String) -> [TranslationHistoryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return items
        }

        return items.filter { item in
            item.sourceText.localizedCaseInsensitiveContains(query)
                || item.translatedText.localizedCaseInsensitiveContains(query)
                || item.providerName.localizedCaseInsensitiveContains(query)
                || item.providerResults.contains { providerResult in
                    providerResult.providerName.localizedCaseInsensitiveContains(query)
                        || providerResult.translatedText.localizedCaseInsensitiveContains(query)
                }
                || TranslationLanguage.name(for: item.targetLanguageCode)
                    .localizedCaseInsensitiveContains(query)
        }
    }

    func selectProviderResult(_ providerID: String, for item: TranslationHistoryItem) {
        guard let itemIndex = items.firstIndex(where: { $0.id == item.id }),
              let providerResult = items[itemIndex].providerResults.first(where: { $0.providerID == providerID })
        else {
            return
        }

        let currentItem = items[itemIndex]
        guard currentItem.providerID != providerResult.providerID else {
            return
        }

        items[itemIndex] = TranslationHistoryItem(
            id: currentItem.id,
            sourceText: currentItem.sourceText,
            translatedText: providerResult.translatedText,
            sourceLanguageCode: currentItem.sourceLanguageCode,
            detectedSourceLanguageCode: providerResult.detectedSourceLanguageCode,
            targetLanguageCode: providerResult.targetLanguageCode,
            providerID: providerResult.providerID,
            providerName: providerResult.providerName,
            providerResults: currentItem.providerResults,
            createdAt: currentItem.createdAt
        )
        persistIfNeeded()
    }

    func delete(_ item: TranslationHistoryItem) {
        items = items.filter { $0.id != item.id }
        persistIfNeeded()
    }

    func clear() {
        items = []
        persistIfNeeded()
    }

    func waitForPendingPersistence() async {
        await persistTask?.value
    }

    private func trimToLimit() {
        if items.count > maximumItems {
            items = Array(items.prefix(maximumItems))
        }
    }

    private func loadPersistedSnapshot() {
        guard let persistence, persistsHistory else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            guard let snapshot = try persistence.loadSnapshot() else {
                return
            }

            items = snapshot.items.sorted { first, second in
                first.createdAt > second.createdAt
            }
            maximumItems = max(1, snapshot.maximumItems)
            if shouldRestorePersistsHistoryFromSnapshot {
                persistsHistory = snapshot.persistsHistory
            }
            trimToLimit()
            persistenceErrorMessage = nil
        } catch {
            persistenceErrorMessage = error.localizedDescription
        }
    }

    private func persistIfNeeded() {
        guard !isLoading, persistsHistory, let persistence else {
            return
        }

        persistenceGeneration += 1
        let generation = persistenceGeneration
        let snapshot = TranslationHistorySnapshot(
            items: items,
            maximumItems: maximumItems,
            persistsHistory: persistsHistory
        )
        let previousTask = persistTask
        persistTask = Task { [weak self, persistence, snapshot, previousTask, generation] in
            await previousTask?.value

            let result = await Task.detached(priority: .utility) {
                do {
                    try persistence.saveSnapshot(snapshot)
                    return Result<Void, Error>.success(())
                } catch {
                    return .failure(error)
                }
            }.value

            guard !Task.isCancelled else {
                return
            }

            guard generation == self?.persistenceGeneration else {
                return
            }

            switch result {
            case .success:
                self?.persistenceErrorMessage = nil
            case .failure(let error):
                self?.persistenceErrorMessage = error.localizedDescription
            }
        }
    }

    private func deletePersistedSnapshot() {
        guard let persistence else {
            return
        }

        persistenceGeneration += 1
        let generation = persistenceGeneration
        let previousTask = persistTask
        persistTask = Task { [weak self, persistence, previousTask, generation] in
            await previousTask?.value

            let result = await Task.detached(priority: .utility) {
                do {
                    try persistence.deleteSnapshot()
                    return Result<Void, Error>.success(())
                } catch {
                    return .failure(error)
                }
            }.value

            guard !Task.isCancelled else {
                return
            }

            guard generation == self?.persistenceGeneration else {
                return
            }

            switch result {
            case .success:
                self?.persistenceErrorMessage = nil
            case .failure(let error):
                self?.persistenceErrorMessage = error.localizedDescription
            }
        }
    }
}

extension TranslationHistoryStore {
    static var preview: TranslationHistoryStore {
        let store = TranslationHistoryStore()
        store.record(
            request: TranslationRequest(
                sourceText: "Hello",
                targetLanguageCode: "zh-Hans",
                sourceLanguageCode: "en"
            ),
            result: TranslationResult(
                translatedText: "【简体中文】你好",
                sourceLanguageCode: "en",
                targetLanguageCode: "zh-Hans"
            )
        )
        return store
    }
}
