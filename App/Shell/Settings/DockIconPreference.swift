import Foundation

@MainActor
@Observable
final class DockIconPreference {
    private enum Key {
        static let hidesDockIconWhenMainWindowClosed = "app.hidesDockIconWhenMainWindowClosed"
    }

    private let defaults: UserDefaults
    private(set) var hidesDockIconWhenMainWindowClosed: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Key.hidesDockIconWhenMainWindowClosed) == nil {
            self.hidesDockIconWhenMainWindowClosed = true
            defaults.set(true, forKey: Key.hidesDockIconWhenMainWindowClosed)
        } else {
            self.hidesDockIconWhenMainWindowClosed = defaults.bool(
                forKey: Key.hidesDockIconWhenMainWindowClosed
            )
        }
    }

    func updateHidesDockIconWhenMainWindowClosed(_ value: Bool) {
        hidesDockIconWhenMainWindowClosed = value
        defaults.set(value, forKey: Key.hidesDockIconWhenMainWindowClosed)
        AppDockIconController.shared.updateActivationPolicy()
    }
}
