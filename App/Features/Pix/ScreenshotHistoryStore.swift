import Foundation

@MainActor
@Observable
final class ScreenshotHistoryStore {
    private(set) var items: [ScreenshotItem] = []
    private(set) var persistenceErrorMessage: String?

    private let persistence: ScreenshotHistoryPersistence?
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
        limit: Int = 20,
        persistsHistory: Bool? = nil,
        persistence: ScreenshotHistoryPersistence? = nil,
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

    func record(_ data: Data, at date: Date = Date()) {
        guard !data.isEmpty else {
            return
        }

        items.insert(
            ScreenshotItem(data: data, createdAt: date),
            at: 0
        )
        trimToLimit()
        persistIfNeeded()
    }

    func delete(_ item: ScreenshotItem) {
        items.removeAll { $0.id == item.id }
        persistIfNeeded()
    }

    func clear() {
        items.removeAll()
        persistIfNeeded()
    }

    func waitForPendingPersistence() async {
        await persistTask?.value
    }

    private func trimToLimit() {
        if items.count > maximumItems {
            items.removeSubrange(maximumItems...)
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
        let snapshot = ScreenshotHistorySnapshot(
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

extension ScreenshotHistoryStore {
    static var preview: ScreenshotHistoryStore {
        let store = ScreenshotHistoryStore()
        store.record(Data([0x89, 0x50, 0x4E, 0x47]))
        return store
    }
}
