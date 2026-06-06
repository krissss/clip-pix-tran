import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let showMainWindow = Self("showClip")
    static let showClipboardQuickPanel = Self("showClipboardQuickPanel")
    static let captureSelectedRegion = Self("captureSelectedRegion")
    static let translateSelectedText = Self("translateSelectedText")
}

struct AppKeyboardShortcut: Identifiable {
    let title: String
    let name: KeyboardShortcuts.Name

    var id: String {
        name.rawValue
    }
}

extension AppKeyboardShortcut {
    static let showMainWindow = Self(title: "打开主窗口", name: .showMainWindow)
    static let showClipboardQuickPanel = Self(title: "剪贴板快速面板", name: .showClipboardQuickPanel)
    static let captureSelectedRegion = Self(title: "Pix 捕获", name: .captureSelectedRegion)
    static let translateSelectedText = Self(title: "翻译选中文本", name: .translateSelectedText)

    static let all: [Self] = [
        .showMainWindow,
        .showClipboardQuickPanel,
        .captureSelectedRegion,
        .translateSelectedText
    ]
}
