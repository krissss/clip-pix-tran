import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let showClip = Self("showClip")
    static let showClipboardQuickPanel = Self("showClipboardQuickPanel")
    static let captureSelectedRegion = Self("captureSelectedRegion")
    static let translateSelectedText = Self("translateSelectedText")
    static let translateClipboardText = Self("translateClipboardText")
}

struct AppKeyboardShortcut: Identifiable {
    let title: String
    let name: KeyboardShortcuts.Name

    var id: String {
        name.rawValue
    }
}

extension AppKeyboardShortcut {
    static let showClip = Self(title: "打开 Clip", name: .showClip)
    static let showClipboardQuickPanel = Self(title: "剪贴板快速面板", name: .showClipboardQuickPanel)
    static let captureSelectedRegion = Self(title: "Pix 捕获", name: .captureSelectedRegion)
    static let translateSelectedText = Self(title: "翻译选中文本", name: .translateSelectedText)
    static let translateClipboardText = Self(title: "翻译剪贴板文本", name: .translateClipboardText)

    static let all: [Self] = [
        .showClip,
        .showClipboardQuickPanel,
        .captureSelectedRegion,
        .translateSelectedText,
        .translateClipboardText
    ]
}
