import Foundation

@MainActor
@Observable
final class FirstLaunchOnboardingPreference {
    private enum Key {
        static let hasCompleted = "app.firstLaunchOnboardingCompleted"
    }

    private let defaults: UserDefaults
    private(set) var hasCompleted: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasCompleted = defaults.bool(forKey: Key.hasCompleted)
    }

    func markCompleted() {
        hasCompleted = true
        defaults.set(true, forKey: Key.hasCompleted)
    }

    func reset() {
        hasCompleted = false
        defaults.set(false, forKey: Key.hasCompleted)
    }
}
