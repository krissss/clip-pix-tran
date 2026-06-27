import Foundation

@MainActor
@Observable
final class ClipboardHistoryStore {
    private(set) var items: [ClipboardItem] = []
    private(set) var persistenceErrorMessage: String?

    private let persistence: ClipboardHistoryPersistence?
    private let persistencePreference: HistoryPersistencePreference
    private let shouldRestorePersistsHistoryFromSnapshot: Bool
    private var isLoading = false
    private var maximumNormalItems: Int
    private var persistTask: Task<Void, Never>?
    private var persistenceGeneration = 0
    var persistsHistory: Bool

    var limit: Int {
        maximumNormalItems
    }

    init(
        limit: Int = 50,
        persistsHistory: Bool? = nil,
        persistence: ClipboardHistoryPersistence? = nil,
        persistsHistoryDefaultsKey: String? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.maximumNormalItems = max(1, limit)
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
        maximumNormalItems = max(1, newLimit)
        trimToLimit()
        persistIfNeeded()
    }

    func updatePersistsHistory(_ shouldPersist: Bool) {
        if !shouldPersist {
            hydrateImageDataForCurrentSession()
        }

        persistsHistory = shouldPersist
        persistencePreference.save(shouldPersist)

        if shouldPersist {
            persistIfNeeded()
        } else {
            deletePersistedSnapshot()
        }
    }

    func record(_ text: String, at date: Date = Date()) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }

        record(ClipboardItem(text: text, createdAt: date, lastCopiedAt: date), at: date)
    }

    func record(_ item: ClipboardItem, at date: Date = Date()) {
        guard shouldRecord(item) else {
            return
        }

        if let existingIndex = items.firstIndex(where: { $0.contentMatches(item) }) {
            let existingItem = items.remove(at: existingIndex)
            items.insert(existingItem, at: 0)
            items[0] = existingItem.mergingMetadata(
                from: item,
                lastCopiedAt: date
            )
        } else {
            items.insert(
                item.replacingDates(
                    createdAt: date,
                    lastCopiedAt: date
                ),
                at: 0
            )
        }

        sortItems()
        trimToLimit()
        persistIfNeeded()
    }

    func filteredItems(matching query: String) -> [ClipboardItem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return items
        }

        return items.filter {
            $0.searchableText.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    func delete(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        deleteImageFiles(for: [item])
        persistIfNeeded()
    }

    func togglePinned(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        items[index].isPinned.toggle()
        sortItems()
        persistIfNeeded()
    }

    func clear() {
        deleteImageFiles(for: items)
        items.removeAll()
        persistIfNeeded()
    }

    func clearUnpinned() {
        let removedItems = items.filter { !$0.isPinned }
        items.removeAll { !$0.isPinned }
        deleteImageFiles(for: removedItems)
        persistIfNeeded()
    }

    func waitForPendingPersistence() async {
        await persistTask?.value
    }

    private func trimToLimit() {
        var normalItemCount = items.filter { !$0.isPinned }.count

        while normalItemCount > limit,
              let oldestNormalIndex = items.lastIndex(where: { !$0.isPinned }) {
            let removedItem = items.remove(at: oldestNormalIndex)
            deleteImageFiles(for: [removedItem])
            normalItemCount -= 1
        }
    }

    private func deleteImageFiles(for items: [ClipboardItem]) {
        items.compactMap(\.imageDataURL).forEach { url in
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func hydrateImageDataForCurrentSession() {
        items = items.map { item in
            guard item.kind == .image,
                  item.imageDataFileName != nil,
                  let imageData = item.imageData else {
                return item
            }

            return item.replacingImageStorage(
                inlineImageData: imageData,
                imageDataFileName: nil,
                imageDataFilePath: nil
            )
        }
    }

    private func sortItems() {
        items.sort { first, second in
            if first.isPinned != second.isPinned {
                return first.isPinned
            }

            return first.lastCopiedAt > second.lastCopiedAt
        }
    }

    private func shouldRecord(_ item: ClipboardItem) -> Bool {
        switch item.kind {
        case .text:
            return !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .image:
            return item.hasImageData || !item.filePaths.isEmpty
        case .file:
            return !item.filePaths.isEmpty
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

            items = snapshot.items
            maximumNormalItems = max(1, snapshot.maximumNormalItems)
            if shouldRestorePersistsHistoryFromSnapshot {
                persistsHistory = snapshot.persistsHistory
            }
            sortItems()
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
        let snapshot = ClipboardHistorySnapshot(
            items: items,
            maximumNormalItems: maximumNormalItems,
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
