import AppKit
import SwiftUI

private let mainWindowIdentifier = NSUserInterfaceItemIdentifier("ClipPixTran.MainWindow")

@MainActor
enum AppWindowPresenter {
    private static weak var mainWindow: NSWindow?

    static func registerMainWindow(_ window: NSWindow) {
        mainWindow = window
        window.identifier = mainWindowIdentifier
    }

    @discardableResult
    static func bringMainWindowForward() -> Bool {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return false
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        let window = mainWindowIfAvailable()

        guard let window else {
            return false
        }

        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
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
}

private final class MainWindowRegistrationNSView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard let window else {
            return
        }

        AppWindowPresenter.registerMainWindow(window)
    }
}
