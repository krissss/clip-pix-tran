import AppKit
import KeyboardShortcuts

@MainActor
final class AppStatusMenuController: NSObject, NSMenuDelegate {
    static let shared = AppStatusMenuController()

    private var statusItem: NSStatusItem?
    private var menu = NSMenu()
    private weak var clipboardMonitor: ClipboardMonitor?
    private weak var screenshotController: ScreenshotController?
    private weak var translationController: TranslationController?
    private weak var shortcutController: AppShortcutController?
    private var openMainWindowAction: (() -> Void)?
    private var openSettingsAction: (() -> Void)?

    func configure(
        clipboardMonitor: ClipboardMonitor,
        screenshotController: ScreenshotController,
        translationController: TranslationController,
        shortcutController: AppShortcutController,
        openMainWindowAction: @escaping () -> Void,
        openSettingsAction: @escaping () -> Void
    ) {
        self.clipboardMonitor = clipboardMonitor
        self.screenshotController = screenshotController
        self.translationController = translationController
        self.shortcutController = shortcutController
        self.openMainWindowAction = openMainWindowAction
        self.openSettingsAction = openSettingsAction

        installStatusItemIfNeeded()
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    func openMainWindow() {
        openMainWindowAction?()
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else {
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = statusBarImage
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = "ClipPixTran"
        item.menu = menu
        statusItem = item
    }

    private var statusBarImage: NSImage? {
        let image = NSImage(systemSymbolName: "sparkles.rectangle.stack", accessibilityDescription: "ClipPixTran")
        image?.isTemplate = true
        return image
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        menu.delegate = self
        menu.autoenablesItems = false

        addHeader()
        menu.addItem(.separator())

        addPlainItem(
            title: "打开主窗口",
            systemImage: "macwindow",
            action: #selector(openMainWindowMenuItem)
        )
        addShortcutItem(
            shortcut: .showClip,
            systemImage: "doc.on.clipboard",
            action: #selector(showClip)
        )
        addShortcutItem(
            shortcut: .showClipboardQuickPanel,
            systemImage: "rectangle.stack",
            action: #selector(showClipboardQuickPanel)
        )
        addShortcutItem(
            shortcut: .captureSelectedRegion,
            systemImage: "camera.viewfinder",
            action: #selector(captureSelectedRegion)
        )
        addShortcutItem(
            shortcut: .translateSelectedText,
            systemImage: "text.viewfinder",
            action: #selector(translateSelectedText)
        )
        addShortcutItem(
            shortcut: .translateClipboardText,
            systemImage: "text.bubble",
            action: #selector(translateClipboardText)
        )

        menu.addItem(.separator())
        addPlainItem(
            title: "设置...",
            systemImage: "gearshape",
            keyEquivalent: ",",
            action: #selector(openSettings)
        )

        menu.addItem(.separator())
        addPlainItem(
            title: "退出 ClipPixTran",
            keyEquivalent: "q",
            action: #selector(quit)
        )
    }

    private func addHeader() {
        let title = [
            "Clip \(clipboardMonitor?.history.items.count ?? 0)",
            "Pix \(screenshotController?.history.items.count ?? 0)",
            "Tran \(translationController?.history.items.count ?? 0)"
        ].joined(separator: "    ")
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = menuImage(systemName: "sparkles.rectangle.stack")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func addShortcutItem(
        shortcut: AppKeyboardShortcut,
        systemImage: String,
        action: Selector
    ) {
        let item = NSMenuItem(title: shortcut.title, action: action, keyEquivalent: "")
        item.target = self
        item.image = menuImage(systemName: systemImage)
        item.setShortcut(for: shortcut.name)
        menu.addItem(item)
    }

    private func addPlainItem(
        title: String,
        systemImage: String? = nil,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = .command,
        action: Selector
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.keyEquivalentModifierMask = keyEquivalent.isEmpty ? [] : modifiers
        if let systemImage {
            item.image = menuImage(systemName: systemImage)
        }
        menu.addItem(item)
    }

    private func menuImage(systemName: String) -> NSImage? {
        let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    @objc private func showClip() {
        shortcutController?.showClip()
    }

    @objc private func showClipboardQuickPanel() {
        shortcutController?.showClipboardQuickPanel()
    }

    @objc private func captureSelectedRegion() {
        shortcutController?.captureSelectedRegion()
    }

    @objc private func translateSelectedText() {
        shortcutController?.translateSelectedText()
    }

    @objc private func translateClipboardText() {
        shortcutController?.translateClipboardText()
    }

    @objc private func openMainWindowMenuItem() {
        openMainWindow()
    }

    @objc private func openSettings() {
        openSettingsAction?()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
