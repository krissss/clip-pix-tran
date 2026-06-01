import Foundation
import Testing
@testable import ClipPixTran

@MainActor
struct DockIconPreferenceTests {
    @Test func defaultsToHidingDockIconWhenMainWindowClosed() {
        let preference = DockIconPreference(defaults: makeDefaults())

        #expect(preference.hidesDockIconWhenMainWindowClosed)
    }

    @Test func persistsHidingDockIconPreference() {
        let defaults = makeDefaults()
        let preference = DockIconPreference(defaults: defaults)

        preference.updateHidesDockIconWhenMainWindowClosed(false)

        let restoredPreference = DockIconPreference(defaults: defaults)
        #expect(!restoredPreference.hidesDockIconWhenMainWindowClosed)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "DockIconPreferenceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
