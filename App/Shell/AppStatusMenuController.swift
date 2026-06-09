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
    private var openOnboardingAction: (() -> Void)?

    func configure(
        clipboardMonitor: ClipboardMonitor,
        screenshotController: ScreenshotController,
        translationController: TranslationController,
        shortcutController: AppShortcutController,
        openMainWindowAction: @escaping () -> Void,
        openSettingsAction: @escaping () -> Void,
        openOnboardingAction: @escaping () -> Void
    ) {
        self.clipboardMonitor = clipboardMonitor
        self.screenshotController = screenshotController
        self.translationController = translationController
        self.shortcutController = shortcutController
        self.openMainWindowAction = openMainWindowAction
        self.openSettingsAction = openSettingsAction
        self.openOnboardingAction = openOnboardingAction

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
        item.button?.toolTip = statusItemToolTip
        item.menu = menu
        statusItem = item
    }

    private var statusItemToolTip: String {
        #if DEBUG
        "ClipPixTran Debug"
        #else
        "ClipPixTran"
        #endif
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

        #if DEBUG
        addDebugBuildItem()
        menu.addItem(.separator())
        #endif

        addShortcutItem(
            shortcut: .showMainWindow,
            systemImage: "macwindow",
            action: #selector(openMainWindowMenuItem)
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

        menu.addItem(.separator())
        addPlainItem(
            title: "设置...",
            systemImage: "gearshape",
            keyEquivalent: ",",
            action: #selector(openSettings)
        )
        addPlainItem(
            title: "重新打开引导",
            systemImage: "sparkles.rectangle.stack",
            action: #selector(openOnboarding)
        )

        menu.addItem(.separator())
        addPlainItem(
            title: "退出 ClipPixTran",
            keyEquivalent: "q",
            action: #selector(quit)
        )
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

    #if DEBUG
    private func addDebugBuildItem() {
        let item = NSMenuItem(title: "Debug 构建 · ClipPixTran", action: nil, keyEquivalent: "")
        item.image = menuImage(systemName: "hammer")
        item.isEnabled = true
        item.attributedTitle = NSAttributedString(
            string: "Debug 构建 · ClipPixTran",
            attributes: [
                .foregroundColor: NSColor.systemRed,
                .font: NSFont.menuFont(ofSize: 0)
            ]
        )
        menu.addItem(item)
    }
    #endif

    private func menuImage(systemName: String) -> NSImage? {
        let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
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

    @objc private func openMainWindowMenuItem() {
        shortcutController?.showMainWindow()
    }

    @objc private func openSettings() {
        openSettingsAction?()
    }

    @objc private func openOnboarding() {
        openOnboardingAction?()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
