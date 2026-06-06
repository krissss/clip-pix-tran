import AppKit

@MainActor
final class AppDockIconController {
    static let shared = AppDockIconController()

    private weak var preference: DockIconPreference?

    func configure(preference: DockIconPreference) {
        self.preference = preference
        updateActivationPolicy()
    }

    func updateActivationPolicy() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        let hidesWhenClosed = preference?.hidesDockIconWhenMainWindowClosed ?? true
        let shouldShowDockIcon = !hidesWhenClosed || AppWindowPresenter.hasVisibleMainWindow
        NSApplication.shared.setActivationPolicy(shouldShowDockIcon ? .regular : .accessory)
    }
}
