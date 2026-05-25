import Foundation

enum HistoryPersistencePreferenceKey {
    static let clipboard = "clip.persistsHistory"
    static let screenshot = "pix.persistsHistory"
    static let translation = "tran.persistsHistory"
}

struct HistoryPersistencePreference {
    private let defaults: UserDefaults
    private let key: String?

    init(defaults: UserDefaults = .standard, key: String?) {
        self.defaults = defaults
        self.key = key
    }

    var storedValue: Bool? {
        guard let key, defaults.object(forKey: key) != nil else {
            return nil
        }

        return defaults.bool(forKey: key)
    }

    func save(_ value: Bool) {
        guard let key else {
            return
        }

        defaults.set(value, forKey: key)
    }
}
