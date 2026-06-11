import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let showMainWindow = Self("showClip")
    static let showClipboardQuickPanel = Self("showClipboardQuickPanel")
    static let captureSelectedRegion = Self("captureSelectedRegion")
    static let translateSelectedText = Self("translateSelectedText")
}

struct AppKeyboardShortcut: Identifiable {
    let titleKey: String
    let name: KeyboardShortcuts.Name

    var id: String {
        name.rawValue
    }

    var title: String {
        L10n.tr(titleKey, titleFallback)
    }

    private var titleFallback: String {
        switch name {
        case .showMainWindow:
            "Open Main Window"
        case .showClipboardQuickPanel:
            "Clipboard Quick Panel"
        case .captureSelectedRegion:
            "Pix Capture"
        case .translateSelectedText:
            "Translate Selected Text"
        default:
            titleKey
        }
    }
}

extension AppKeyboardShortcut {
    static let showMainWindow = Self(titleKey: "shortcut.mainWindow", name: .showMainWindow)
    static let showClipboardQuickPanel = Self(titleKey: "shortcut.clipboardPanel", name: .showClipboardQuickPanel)
    static let captureSelectedRegion = Self(titleKey: "shortcut.pixCapture", name: .captureSelectedRegion)
    static let translateSelectedText = Self(titleKey: "shortcut.translateSelection", name: .translateSelectedText)

    static let all: [Self] = [
        .showMainWindow,
        .showClipboardQuickPanel,
        .captureSelectedRegion,
        .translateSelectedText
    ]
}
