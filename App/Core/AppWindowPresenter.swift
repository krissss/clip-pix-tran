import AppKit
import SwiftUI

private let mainWindowIdentifier = NSUserInterfaceItemIdentifier("ClipPixTran.MainWindow")

@MainActor
enum AppWindowPresenter {
    private static weak var mainWindow: NSWindow?

    static var hasVisibleMainWindow: Bool {
        guard let window = mainWindowIfAvailable() else {
            return false
        }

        return window.isVisible && !window.isMiniaturized
    }

    static func registerMainWindow(_ window: NSWindow) {
        mainWindow = window
        window.identifier = mainWindowIdentifier
        AppDockIconController.shared.updateActivationPolicy()
    }

    @discardableResult
    static func bringMainWindowForward() -> Bool {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return false
        }

        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        let window = mainWindowIfAvailable()

        guard let window else {
            AppDockIconController.shared.updateActivationPolicy()
            return false
        }

        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        AppDockIconController.shared.updateActivationPolicy()
        return true
    }

    private static func mainWindowIfAvailable() -> NSWindow? {
        if let mainWindow, isUsableMainWindow(mainWindow) {
            return mainWindow
        }

        return NSApplication.shared.windows.first { window in
            window.identifier == mainWindowIdentifier
                && isUsableMainWindow(window)
        }
    }

    private static func isUsableMainWindow(_ window: NSWindow) -> Bool {
        window.canBecomeKey
            && (window.isVisible || window.isMiniaturized)
    }
}

struct MainWindowRegistrationView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        MainWindowRegistrationNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else {
            return
        }

        AppWindowPresenter.registerMainWindow(window)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        NotificationCenter.default.removeObserver(nsView)
    }
}

private final class MainWindowRegistrationNSView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard let window else {
            return
        }

        AppWindowPresenter.registerMainWindow(window)
        observeWindowLifecycle(window)
    }

    private func observeWindowLifecycle(_ window: NSWindow) {
        NotificationCenter.default.removeObserver(self)

        let notifications: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.willCloseNotification
        ]
        for notification in notifications {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowVisibilityChanged),
                name: notification,
                object: window
            )
        }
    }

    @objc private func windowVisibilityChanged() {
        DispatchQueue.main.async {
            AppDockIconController.shared.updateActivationPolicy()
        }
    }
}
