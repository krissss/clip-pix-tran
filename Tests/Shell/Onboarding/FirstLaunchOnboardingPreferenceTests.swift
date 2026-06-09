import Foundation
import Testing
@testable import ClipPixTran

@MainActor
struct FirstLaunchOnboardingPreferenceTests {
    @Test func defaultsToNotCompleted() {
        let preference = FirstLaunchOnboardingPreference(defaults: makeDefaults())

        #expect(!preference.hasCompleted)
    }

    @Test func persistsCompletion() {
        let defaults = makeDefaults()
        let preference = FirstLaunchOnboardingPreference(defaults: defaults)

        preference.markCompleted()

        let restoredPreference = FirstLaunchOnboardingPreference(defaults: defaults)
        #expect(restoredPreference.hasCompleted)
    }

    @Test func resetClearsCompletion() {
        let defaults = makeDefaults()
        let preference = FirstLaunchOnboardingPreference(defaults: defaults)
        preference.markCompleted()

        preference.reset()

        let restoredPreference = FirstLaunchOnboardingPreference(defaults: defaults)
        #expect(!restoredPreference.hasCompleted)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "FirstLaunchOnboardingPreferenceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
