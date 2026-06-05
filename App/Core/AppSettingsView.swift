import SwiftUI
import KeyboardShortcuts

struct AppSettingsView: View {
    @Bindable var clipboardHistory: ClipboardHistoryStore
    @Bindable var screenshotHistory: ScreenshotHistoryStore
    @Bindable var translationController: TranslationController
    @Bindable var dockIconPreference: DockIconPreference
    @State private var selectedPane: SettingsPane = .general

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("设置")
                        .font(.headline)
                }

                Spacer()

                SettingsPaneToolbar(selectedPane: $selectedPane)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            SettingsContentPanel {
                selectedPaneView
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .frame(width: ControlPanelDesign.Layout.Settings.windowWidth)
        .frame(height: ControlPanelDesign.Layout.Settings.windowHeight)
        .background(ControlPanelBackground())
    }

    @ViewBuilder
    private var selectedPaneView: some View {
        switch selectedPane {
        case .general:
            GeneralSettingsSection(preference: dockIconPreference)
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
    case general
    case shortcuts
    case clip
    case pix
    case tran
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general:
            "通用"
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
        case .general:
            "slider.horizontal.3"
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

private struct GeneralSettingsSection: View {
    @Bindable var preference: DockIconPreference
    @State private var hidesDockIconWhenMainWindowClosed: Bool

    init(preference: DockIconPreference) {
        self.preference = preference
        self._hidesDockIconWhenMainWindowClosed = State(
            initialValue: preference.hidesDockIconWhenMainWindowClosed
        )
    }

    var body: some View {
        SettingsGroup(title: "Dock") {
            VStack(spacing: 0) {
                toggleRow(
                    "关闭主窗口后隐藏 Dock 图标",
                    isOn: $hidesDockIconWhenMainWindowClosed
                ) { newValue in
                    preference.updateHidesDockIconWhenMainWindowClosed(newValue)
                }
            }
            .settingsRowGroup()
        }

        SettingsFootnote("开启后，关闭主窗口时应用会留在菜单栏；从菜单栏打开主窗口时会临时恢复 Dock 图标。")
    }
}

private struct SettingsPaneToolbar: View {
    @Binding var selectedPane: SettingsPane

    var body: some View {
        HStack(spacing: 3) {
            ForEach(SettingsPane.allCases) { pane in
                Button {
                    selectedPane = pane
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: pane.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: 16, height: 16)

                        Text(pane.title)
                            .font(.caption)
                    }
                    .foregroundStyle(selectedPane == pane ? Color.accentColor : Color.secondary)
                    .frame(width: 62, height: 30)
                    .controlPanelRoundedSurface(
                        background: ControlPanelDesign.selectedFill(
                            tint: Color.accentColor,
                            isSelected: selectedPane == pane,
                            opacity: 0.11
                        ),
                        cornerRadius: ControlPanelDesign.compactRadius
                    )
                    .contentShape(RoundedRectangle(cornerRadius: ControlPanelDesign.compactRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(pane.title)
            }
        }
        .controlPanelSegmentedSurface()
    }
}

private struct SettingsContentPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(minHeight: ControlPanelDesign.Layout.Settings.contentMinHeight, alignment: .topLeading)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ShortcutsSettingsSection: View {
    var body: some View {
        SettingsGroup(title: "全局快捷键") {
            VStack(spacing: 0) {
                ForEach(AppKeyboardShortcut.all) { shortcut in
                    shortcutRow(shortcut)
                }
            }
            .settingsRowGroup()
        }
    }

    private func shortcutRow(_ shortcut: AppKeyboardShortcut) -> some View {
        SettingsFormRow(title: shortcut.title) {
            KeyboardShortcuts.Recorder("", name: shortcut.name)
                .labelsHidden()
        }
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
        SettingsGroup(title: "历史") {
            VStack(spacing: 0) {
                toggleRow("重启后保留剪贴板历史", isOn: $persistsHistory) { newValue in
                    history.updatePersistsHistory(newValue)
                }
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
        }

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
        SettingsGroup(title: "历史") {
            VStack(spacing: 0) {
                toggleRow("重启后保留截图历史", isOn: $persistsHistory) { newValue in
                    history.updatePersistsHistory(newValue)
                }
                historyLimitRow(
                    title: "截图历史上限",
                    value: $maximumItems,
                    range: 5...200,
                    step: 5
                ) { newValue in
                    history.updateLimit(Int(newValue))
                }
            }
            .settingsRowGroup()
        }

        SettingsFootnote("截图可能包含敏感信息；开启保留历史后，会把最近截图保存到本机应用支持目录。")
    }
}

private struct TranSettingsSection: View {
    @Bindable var controller: TranslationController
    @State private var maximumItems: Double
    @State private var persistsHistory: Bool
    @State private var openAIBaseURL: String
    @State private var openAIAPIKey: String
    @State private var openAIModel: String
    @State private var openAITTSModel: String
    @State private var openAITTSVoice: String

    init(controller: TranslationController) {
        self.controller = controller
        self._maximumItems = State(initialValue: Double(controller.history.limit))
        self._persistsHistory = State(initialValue: controller.history.persistsHistory)
        let configuration = controller.preferences.openAICompatibleConfiguration
        self._openAIBaseURL = State(initialValue: configuration.baseURL)
        self._openAIAPIKey = State(initialValue: configuration.apiKey)
        self._openAIModel = State(initialValue: configuration.model)
        let ttsConfiguration = controller.preferences.openAITextToSpeechConfiguration
        self._openAITTSModel = State(initialValue: ttsConfiguration.model)
        self._openAITTSVoice = State(initialValue: ttsConfiguration.voice)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsGroup(title: "默认语言") {
                VStack(spacing: 0) {
                    SettingsFormRow(title: "默认原文语言") {
                        Picker("", selection: sourceLanguageSelection) {
                            Text(TranslationLanguage.automaticSourceName)
                                .tag(TranslationLanguage.automaticSourceCode)
                            Divider()
                            ForEach(TranslationLanguage.supportedSources) { language in
                                Text(language.name).tag(language.code)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity)
                    }
                    SettingsFormRow(title: "默认目标语言") {
                        Picker("", selection: targetLanguageSelection) {
                            ForEach(TranslationLanguage.supported) { language in
                                Text(language.name).tag(language.code)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity)
                    }
                }
                .settingsRowGroup()
            }

            SettingsGroup(title: "翻译服务") {
                VStack(spacing: 0) {
                    ForEach(TranslationProviderDescriptor.builtIn) { provider in
                        providerToggleRow(provider)
                    }
                }
                .settingsRowGroup()
            }

            SettingsGroup(title: "发音服务") {
                VStack(spacing: 0) {
                    SettingsFormRow(title: "默认发音") {
                        Picker("", selection: speechProviderSelection) {
                            ForEach(TranslationSpeechProviderDescriptor.builtIn) { provider in
                                Label(provider.name, systemImage: provider.systemImage)
                                    .tag(provider.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity)
                    }
                }
                .settingsRowGroup()
            }

            SettingsGroup(title: "OpenAI Compatible") {
                VStack(spacing: 0) {
                    SettingsFormRow(title: "Base URL") {
                        TextField("https://api.openai.com/v1", text: $openAIBaseURL)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(saveOpenAICompatibleConfiguration)
                    }

                    SettingsFormRow(title: "API Key") {
                        SecureField("sk-...", text: $openAIAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(saveOpenAICompatibleConfiguration)
                    }

                    SettingsFormRow(title: "Translation Model") {
                        TextField("gpt-4o-mini", text: $openAIModel)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(saveOpenAICompatibleConfiguration)
                    }

                    SettingsFormRow(title: "TTS Model") {
                        TextField(OpenAITextToSpeechConfiguration.defaultModel, text: $openAITTSModel)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(saveOpenAITextToSpeechConfiguration)
                    }

                    SettingsFormRow(title: "TTS Voice") {
                        TextField(OpenAITextToSpeechConfiguration.defaultVoice, text: $openAITTSVoice)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(saveOpenAITextToSpeechConfiguration)
                    }
                }
                .settingsRowGroup()

                SettingsFootnote("MiMo 发音：Base URL 可填到 host 或 /v1；TTS Voice 使用 mimo_default、Chloe 等，alloy 会自动按 mimo_default 处理。")
            }
            .onChange(of: openAIBaseURL) { _, _ in saveOpenAICompatibleConfiguration() }
            .onChange(of: openAIAPIKey) { _, _ in saveOpenAICompatibleConfiguration() }
            .onChange(of: openAIModel) { _, _ in saveOpenAICompatibleConfiguration() }
            .onChange(of: openAITTSModel) { _, _ in saveOpenAITextToSpeechConfiguration() }
            .onChange(of: openAITTSVoice) { _, _ in saveOpenAITextToSpeechConfiguration() }

            SettingsGroup(title: "历史") {
                VStack(spacing: 0) {
                    toggleRow("重启后保留翻译历史", isOn: $persistsHistory) { newValue in
                        controller.history.updatePersistsHistory(newValue)
                    }
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
            }
        }

        SettingsFootnote("目标语言默认跟随系统；发音默认使用系统语音；翻译历史会保存到本机。")
    }

    private var targetLanguageSelection: Binding<String> {
        Binding {
            controller.preferences.defaultTargetLanguageCode
        } set: { newValue in
            controller.selectTargetLanguage(newValue, persistsDefault: true)
        }
    }

    private var sourceLanguageSelection: Binding<String> {
        Binding {
            controller.preferences.defaultSourceLanguageCode ?? TranslationLanguage.automaticSourceCode
        } set: { newValue in
            controller.selectSourceLanguage(
                newValue == TranslationLanguage.automaticSourceCode ? nil : newValue,
                persistsDefault: true
            )
        }
    }

    private var speechProviderSelection: Binding<String> {
        Binding {
            controller.preferences.speechProviderID
        } set: { newValue in
            controller.selectSpeechProvider(newValue)
        }
    }

    private func providerToggleRow(_ provider: TranslationProviderDescriptor) -> some View {
        SettingsFormRow {
            VStack(alignment: .leading, spacing: 2) {
                Label(provider.name, systemImage: provider.systemImage)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.primary)

                if provider.requiresConfiguration {
                    Text("需要配置")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } control: {
            Toggle("", isOn: providerEnabledBinding(provider.id))
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    private func providerEnabledBinding(_ providerID: String) -> Binding<Bool> {
        Binding {
            controller.preferences.enabledProviderIDs.contains(providerID)
        } set: { newValue in
            controller.setProvider(providerID, isEnabled: newValue)
        }
    }

    private func saveOpenAICompatibleConfiguration() {
        controller.preferences.updateOpenAICompatibleConfiguration(
            OpenAICompatibleTranslationConfiguration(
                baseURL: openAIBaseURL,
                apiKey: openAIAPIKey,
                model: openAIModel
            )
        )
    }

    private func saveOpenAITextToSpeechConfiguration() {
        controller.preferences.updateOpenAITextToSpeechConfiguration(
            OpenAITextToSpeechConfiguration(
                baseURL: openAIBaseURL,
                apiKey: openAIAPIKey,
                model: openAITTSModel,
                voice: openAITTSVoice
            )
        )
        let configuration = controller.preferences.openAITextToSpeechConfiguration
        if openAITTSModel != configuration.model {
            openAITTSModel = configuration.model
        }
        if openAITTSVoice != configuration.voice {
            openAITTSVoice = configuration.voice
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            content
        }
    }
}

private struct AboutSettingsSection: View {
    var body: some View {
        VStack(spacing: 14) {
            ControlPanelIconTile(
                systemImage: "sparkles.rectangle.stack",
                tint: Color.accentColor,
                size: 58
            )

            Text("ClipPixTran")
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

private struct SettingsFormRow<Control: View>: View {
    let titleContent: AnyView
    @ViewBuilder var control: Control

    init(title: String, @ViewBuilder control: () -> Control) {
        self.titleContent = AnyView(Text(title))
        self.control = control()
    }

    init<Title: View>(
        @ViewBuilder title: () -> Title,
        @ViewBuilder control: () -> Control
    ) {
        self.titleContent = AnyView(title())
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            titleContent
                .font(.callout)
                .lineLimit(2)
                .frame(width: ControlPanelDesign.Layout.Settings.labelWidth, alignment: .leading)

            Spacer(minLength: 16)

            control
                .controlSize(.regular)
                .frame(width: ControlPanelDesign.Layout.Settings.controlWidth, alignment: .trailing)
        }
        .frame(minHeight: ControlPanelDesign.Layout.Settings.rowHeight)
        .padding(.horizontal, 16)
    }
}

private struct SettingsFootnote: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Label(text, systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .controlPanelRoundedSurface(
                background: ControlPanelDesign.quietFill,
                cornerRadius: ControlPanelDesign.compactRadius
            )
    }
}

private extension View {
    func settingsRowGroup() -> some View {
        controlPanelSettingsRowGroup()
    }
}

private func toggleRow(
    _ title: String,
    isOn: Binding<Bool>,
    onChange: @escaping (Bool) -> Void
) -> some View {
    SettingsFormRow(title: title) {
        Toggle("", isOn: isOn)
            .labelsHidden()
            .toggleStyle(.switch)
    }
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
    SettingsFormRow(title: title) {
        HStack(spacing: 10) {
            Slider(value: value, in: range, step: step)
                .frame(width: ControlPanelDesign.Layout.Settings.sliderWidth)
                .onChange(of: value.wrappedValue) { _, newValue in
                    onChange(newValue)
                }

            Text("\(Int(value.wrappedValue))")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: ControlPanelDesign.Layout.Settings.valueWidth, alignment: .trailing)
        }
    }
}

#Preview {
    AppSettingsView(
        clipboardHistory: .preview,
        screenshotHistory: .preview,
        translationController: TranslationController(
            history: .preview,
            translationService: FallbackTranslationService(),
            pasteboard: PreviewClipboardService()
        ),
        dockIconPreference: DockIconPreference()
    )
}
