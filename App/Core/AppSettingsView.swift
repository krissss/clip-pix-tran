import SwiftUI
import KeyboardShortcuts

struct AppSettingsView: View {
    @Bindable var clipboardHistory: ClipboardHistoryStore
    @Bindable var screenshotHistory: ScreenshotHistoryStore
    @Bindable var translationController: TranslationController
    @State private var selectedPane: SettingsPane = .shortcuts

    var body: some View {
        VStack(spacing: 0) {
            Text(selectedPane.title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 2)

            SettingsPaneToolbar(selectedPane: $selectedPane)
                .padding(.horizontal, 18)
                .padding(.bottom, 16)

            Divider()

            SettingsContentPanel {
                selectedPaneView
            }
            .padding(18)
        }
        .frame(width: 620)
        .frame(minHeight: 420)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var selectedPaneView: some View {
        switch selectedPane {
        case .shortcuts:
            ShortcutsSettingsSection()
        case .clip:
            ClipSettingsSection(history: clipboardHistory)
        case .pix:
            PixSettingsSection(history: screenshotHistory)
        case .tran:
            TranSettingsSection(controller: translationController)
        case .about:
            AboutSettingsSection()
        }
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case shortcuts
    case clip
    case pix
    case tran
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .shortcuts:
            "快捷键"
        case .clip:
            "Clip"
        case .pix:
            "Pix"
        case .tran:
            "Tran"
        case .about:
            "关于"
        }
    }

    var systemImage: String {
        switch self {
        case .shortcuts:
            "keyboard"
        case .clip:
            "doc.on.clipboard"
        case .pix:
            "camera.viewfinder"
        case .tran:
            "character.book.closed"
        case .about:
            "info.circle"
        }
    }
}

private struct SettingsPaneToolbar: View {
    @Binding var selectedPane: SettingsPane

    var body: some View {
        HStack(spacing: 6) {
            ForEach(SettingsPane.allCases) { pane in
                Button {
                    selectedPane = pane
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: pane.systemImage)
                            .font(.system(size: 20, weight: .regular))
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: 28, height: 24)

                        Text(pane.title)
                            .font(.caption)
                    }
                    .foregroundStyle(selectedPane == pane ? Color.accentColor : Color.secondary)
                    .frame(width: 74, height: 54)
                    .background {
                        if selectedPane == pane {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.accentColor.opacity(0.1))
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(pane.title)
            }
        }
    }
}

private struct SettingsContentPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.64))
        }
    }
}

private struct ShortcutsSettingsSection: View {
    var body: some View {
        SettingsSectionHeader(
            icon: "keyboard",
            title: "快捷键",
            subtitle: "配置常用操作的全局快捷键。"
        )

        VStack(spacing: 0) {
            shortcutRow(title: "打开 Clip", name: .showClip)
            SettingsRowDivider()
            shortcutRow(title: "区域截图", name: .captureSelectedRegion)
            SettingsRowDivider()
            shortcutRow(title: "翻译剪贴板文本", name: .translateClipboardText)
        }
        .settingsRowGroup()
    }

    private func shortcutRow(title: String, name: KeyboardShortcuts.Name) -> some View {
        HStack {
            Text(title)
            Spacer()
            KeyboardShortcuts.Recorder("", name: name)
                .labelsHidden()
        }
        .settingsRow()
    }
}

private struct ClipSettingsSection: View {
    @Bindable var history: ClipboardHistoryStore
    @State private var maximumNormalItems: Double
    @State private var persistsHistory: Bool

    init(history: ClipboardHistoryStore) {
        self.history = history
        self._maximumNormalItems = State(initialValue: Double(history.limit))
        self._persistsHistory = State(initialValue: history.persistsHistory)
    }

    var body: some View {
        SettingsSectionHeader(
            icon: "doc.on.clipboard",
            title: "Clip",
            subtitle: "管理剪贴板历史的保存方式和容量。"
        )

        VStack(spacing: 0) {
            toggleRow("重启后保留剪贴板历史", isOn: $persistsHistory) { newValue in
                history.updatePersistsHistory(newValue)
            }
            SettingsRowDivider()
            historyLimitRow(
                title: "普通历史上限",
                value: $maximumNormalItems,
                range: 10...200,
                step: 10
            ) { newValue in
                history.updateLimit(Int(newValue))
            }
        }
        .settingsRowGroup()

        SettingsFootnote("关闭保留历史后，已保存的剪贴板历史文件会被删除。")
    }
}

private struct PixSettingsSection: View {
    @Bindable var history: ScreenshotHistoryStore
    @State private var maximumItems: Double
    @State private var persistsHistory: Bool

    init(history: ScreenshotHistoryStore) {
        self.history = history
        self._maximumItems = State(initialValue: Double(history.limit))
        self._persistsHistory = State(initialValue: history.persistsHistory)
    }

    var body: some View {
        SettingsSectionHeader(
            icon: "camera.viewfinder",
            title: "Pix",
            subtitle: "管理截图历史的保存方式和容量。"
        )

        VStack(spacing: 0) {
            toggleRow("重启后保留截图历史", isOn: $persistsHistory) { newValue in
                history.updatePersistsHistory(newValue)
            }
            SettingsRowDivider()
            historyLimitRow(
                title: "截图历史上限",
                value: $maximumItems,
                range: 5...50,
                step: 5
            ) { newValue in
                history.updateLimit(Int(newValue))
            }
        }
        .settingsRowGroup()

        SettingsFootnote("截图可能包含敏感信息；开启保留历史后，会把最近截图保存到本机应用支持目录。")
    }
}

private struct TranSettingsSection: View {
    @Bindable var controller: TranslationController
    @State private var maximumItems: Double
    @State private var persistsHistory: Bool

    init(controller: TranslationController) {
        self.controller = controller
        self._maximumItems = State(initialValue: Double(controller.history.limit))
        self._persistsHistory = State(initialValue: controller.history.persistsHistory)
    }

    var body: some View {
        SettingsSectionHeader(
            icon: "character.book.closed",
            title: "Tran",
            subtitle: "配置翻译默认语言和历史记录。"
        )

        VStack(spacing: 0) {
            HStack {
                Text("默认目标语言")
                Spacer()
                Picker("", selection: targetLanguageSelection) {
                    ForEach(TranslationLanguage.supported) { language in
                        Text(language.name).tag(language.code)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
            }
            .settingsRow()
            SettingsRowDivider()
            toggleRow("重启后保留翻译历史", isOn: $persistsHistory) { newValue in
                controller.history.updatePersistsHistory(newValue)
            }
            SettingsRowDivider()
            historyLimitRow(
                title: "翻译历史上限",
                value: $maximumItems,
                range: 10...200,
                step: 10
            ) { newValue in
                controller.history.updateLimit(Int(newValue))
            }
        }
        .settingsRowGroup()

        SettingsFootnote("未手动选择时，默认目标语言会跟随系统首选语言；开启保留历史后，翻译记录会保存到本机应用支持目录。")
    }

    private var targetLanguageSelection: Binding<String> {
        Binding {
            controller.targetLanguageCode
        } set: { newValue in
            controller.selectTargetLanguage(newValue)
        }
    }
}

private struct AboutSettingsSection: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 42, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(width: 70, height: 70)
                .background {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                }

            Text("ClipPixTran")
                .font(.title3.weight(.semibold))

            Text("剪贴板、截图与翻译的轻量工具集。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

private struct SettingsSectionHeader: View {
    var icon: String
    var title: String
    var subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SettingsFootnote: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SettingsRowDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 16)
    }
}

private extension View {
    func settingsRowGroup() -> some View {
        background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    func settingsRow() -> some View {
        frame(minHeight: 46)
            .padding(.horizontal, 16)
    }
}

private func toggleRow(
    _ title: String,
    isOn: Binding<Bool>,
    onChange: @escaping (Bool) -> Void
) -> some View {
    Toggle(title, isOn: isOn)
        .toggleStyle(.switch)
        .settingsRow()
        .onChange(of: isOn.wrappedValue) { _, newValue in
            onChange(newValue)
        }
}

private func historyLimitRow(
    title: String,
    value: Binding<Double>,
    range: ClosedRange<Double>,
    step: Double,
    onChange: @escaping (Double) -> Void
) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        HStack {
            Text(title)
            Spacer()
            Text("\(Int(value.wrappedValue))")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }

        Slider(value: value, in: range, step: step)
            .onChange(of: value.wrappedValue) { _, newValue in
                onChange(newValue)
            }
    }
    .padding(.vertical, 10)
    .settingsRow()
}

#Preview {
    AppSettingsView(
        clipboardHistory: .preview,
        screenshotHistory: .preview,
        translationController: TranslationController(
            history: .preview,
            translationService: FallbackTranslationService(),
            pasteboard: PreviewClipboardService()
        )
    )
}
