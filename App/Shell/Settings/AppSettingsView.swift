import SwiftUI
import KeyboardShortcuts

struct AppSettingsView: View {
    @Bindable var clipboardHistory: ClipboardHistoryStore
    @Bindable var screenshotHistory: ScreenshotHistoryStore
    @Bindable var translationController: TranslationController
    @Bindable var dockIconPreference: DockIconPreference
    @Bindable var updateManager: AppUpdateManager
    let openOnboardingAction: () -> Void
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
            GeneralSettingsSection(
                preference: dockIconPreference,
                openOnboardingAction: openOnboardingAction
            )
        case .shortcuts:
            ShortcutsSettingsSection()
        case .clip:
            ClipSettingsSection(history: clipboardHistory)
        case .pix:
            PixSettingsSection(history: screenshotHistory)
        case .tran:
            TranSettingsSection(controller: translationController)
        case .about:
            AboutSettingsSection(updateManager: updateManager)
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
    let openOnboardingAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsGroup(title: "Dock") {
                VStack(spacing: 0) {
                    toggleRow(
                        "关闭主窗口后隐藏 Dock 图标",
                        isOn: hidesDockIconWhenMainWindowClosed
                    )
                }
                .settingsRowGroup()
            }

            SettingsGroup(title: "引导") {
                VStack(spacing: 0) {
                    SettingsFormRow(title: "首次启动引导") {
                        Button {
                            openOnboardingAction()
                        } label: {
                            Label("重新打开", systemImage: "sparkles.rectangle.stack")
                        }
                    }
                }
                .settingsRowGroup()
            }

            SettingsFootnote("开启 Dock 隐藏后，关闭主窗口时应用会留在菜单栏；首次引导可随时重新打开。")
        }
    }

    private var hidesDockIconWhenMainWindowClosed: Binding<Bool> {
        Binding {
            preference.hidesDockIconWhenMainWindowClosed
        } set: { newValue in
            preference.updateHidesDockIconWhenMainWindowClosed(newValue)
        }
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

    var body: some View {
        SettingsGroup(title: "历史") {
            VStack(spacing: 0) {
                toggleRow("重启后保留剪贴板历史", isOn: persistsHistory)
                historyLimitRow(
                    title: "普通历史上限",
                    value: maximumNormalItems,
                    range: 10...200,
                    step: 10
                )
            }
            .settingsRowGroup()
        }

        SettingsFootnote("关闭保留历史后，已保存的剪贴板历史文件会被删除。")
    }

    private var maximumNormalItems: Binding<Double> {
        Binding {
            Double(history.limit)
        } set: { newValue in
            history.updateLimit(Int(newValue))
        }
    }

    private var persistsHistory: Binding<Bool> {
        Binding {
            history.persistsHistory
        } set: { newValue in
            history.updatePersistsHistory(newValue)
        }
    }
}

private struct PixSettingsSection: View {
    @Bindable var history: ScreenshotHistoryStore

    var body: some View {
        SettingsGroup(title: "历史") {
            VStack(spacing: 0) {
                toggleRow("重启后保留截图历史", isOn: persistsHistory)
                historyLimitRow(
                    title: "截图历史上限",
                    value: maximumItems,
                    range: 5...200,
                    step: 5
                )
            }
            .settingsRowGroup()
        }

        SettingsFootnote("截图可能包含敏感信息；开启保留历史后，会把最近截图保存到本机应用支持目录。")
    }

    private var maximumItems: Binding<Double> {
        Binding {
            Double(history.limit)
        } set: { newValue in
            history.updateLimit(Int(newValue))
        }
    }

    private var persistsHistory: Binding<Bool> {
        Binding {
            history.persistsHistory
        } set: { newValue in
            history.updatePersistsHistory(newValue)
        }
    }
}

private struct TranSettingsSection: View {
    @Bindable var controller: TranslationController

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
                        TextField("https://api.openai.com/v1", text: openAIBaseURL)
                            .textFieldStyle(.roundedBorder)
                    }

                    SettingsFormRow(title: "API Key") {
                        SecureField("sk-...", text: openAIAPIKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    SettingsFormRow(title: "Translation Model") {
                        TextField("gpt-4o-mini", text: openAIModel)
                            .textFieldStyle(.roundedBorder)
                    }

                    SettingsFormRow(title: "TTS Model") {
                        TextField(OpenAITextToSpeechConfiguration.defaultModel, text: openAITTSModel)
                            .textFieldStyle(.roundedBorder)
                    }

                    SettingsFormRow(title: "TTS Voice") {
                        TextField(OpenAITextToSpeechConfiguration.defaultVoice, text: openAITTSVoice)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .settingsRowGroup()

                SettingsFootnote("MiMo 发音：Base URL 可填到 host 或 /v1；TTS Voice 使用 mimo_default、Chloe 等，alloy 会自动按 mimo_default 处理。")
            }

            SettingsGroup(title: "历史") {
                VStack(spacing: 0) {
                    toggleRow("重启后保留翻译历史", isOn: persistsHistory)
                    historyLimitRow(
                        title: "翻译历史上限",
                        value: maximumItems,
                        range: 10...200,
                        step: 10
                    )
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

    private var maximumItems: Binding<Double> {
        Binding {
            Double(controller.history.limit)
        } set: { newValue in
            controller.history.updateLimit(Int(newValue))
        }
    }

    private var persistsHistory: Binding<Bool> {
        Binding {
            controller.history.persistsHistory
        } set: { newValue in
            controller.history.updatePersistsHistory(newValue)
        }
    }

    private var openAIBaseURL: Binding<String> {
        Binding {
            controller.preferences.openAICompatibleConfiguration.baseURL
        } set: { newValue in
            updateOpenAICompatibleConfiguration(baseURL: newValue)
        }
    }

    private var openAIAPIKey: Binding<String> {
        Binding {
            controller.preferences.openAICompatibleConfiguration.apiKey
        } set: { newValue in
            updateOpenAICompatibleConfiguration(apiKey: newValue)
        }
    }

    private var openAIModel: Binding<String> {
        Binding {
            controller.preferences.openAICompatibleConfiguration.model
        } set: { newValue in
            updateOpenAICompatibleConfiguration(model: newValue)
        }
    }

    private var openAITTSModel: Binding<String> {
        Binding {
            controller.preferences.openAITextToSpeechConfiguration.model
        } set: { newValue in
            updateOpenAITextToSpeechConfiguration(model: newValue)
        }
    }

    private var openAITTSVoice: Binding<String> {
        Binding {
            controller.preferences.openAITextToSpeechConfiguration.voice
        } set: { newValue in
            updateOpenAITextToSpeechConfiguration(voice: newValue)
        }
    }

    private func updateOpenAICompatibleConfiguration(
        baseURL: String? = nil,
        apiKey: String? = nil,
        model: String? = nil
    ) {
        let configuration = controller.preferences.openAICompatibleConfiguration
        controller.preferences.updateOpenAICompatibleConfiguration(
            OpenAICompatibleTranslationConfiguration(
                baseURL: baseURL ?? configuration.baseURL,
                apiKey: apiKey ?? configuration.apiKey,
                model: model ?? configuration.model
            )
        )
    }

    private func updateOpenAITextToSpeechConfiguration(
        model: String? = nil,
        voice: String? = nil
    ) {
        let configuration = controller.preferences.openAITextToSpeechConfiguration
        let openAIConfiguration = controller.preferences.openAICompatibleConfiguration
        controller.preferences.updateOpenAITextToSpeechConfiguration(
            OpenAITextToSpeechConfiguration(
                baseURL: openAIConfiguration.baseURL,
                apiKey: openAIConfiguration.apiKey,
                model: model ?? configuration.model,
                voice: voice ?? configuration.voice
            )
        )
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
    @Bindable var updateManager: AppUpdateManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup(title: "更新") {
                VStack(spacing: 0) {
                    SettingsFormRow(title: "当前版本") {
                        HStack(spacing: 8) {
                            Text(appVersionText)
                                .font(.callout.monospacedDigit())

                            #if DEBUG
                            DebugSettingsBadge()
                            #endif
                        }
                    }

                    toggleRow("自动检查更新", isOn: automaticallyChecksForUpdates)
                    toggleRow("自动下载更新", isOn: automaticallyDownloadsUpdates)

                    SettingsFormRow(title: "检查频率") {
                        Picker("", selection: updateCheckInterval) {
                            ForEach(UpdateCheckInterval.allCases) { interval in
                                Text(interval.displayName).tag(interval)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity)
                    }

                    SettingsFormRow(title: "上次检查") {
                        HStack(spacing: 10) {
                            Text(lastUpdateCheckText)
                                .font(.callout)

                            Spacer(minLength: 0)

                            Button {
                                updateManager.checkForUpdates()
                            } label: {
                                Label("检查更新", systemImage: "arrow.clockwise")
                            }
                            .controlSize(.small)
                            .disabled(!updateManager.canCheckForUpdates)
                        }
                    }
                }
                .settingsRowGroup()
            }

            SettingsFootnote(updateManager.isConfigured ? "自动更新通过 GitHub Release 和 Sparkle appcast 提供。" : "当前构建未配置 Sparkle appcast 或公钥。")
        }
    }

    private var appVersionText: String {
        let version = bundleInfoValue("CFBundleShortVersionString") ?? "未知"
        guard let build = bundleInfoValue("CFBundleVersion"),
              build != version else {
            return version
        }

        return "\(version) (\(build))"
    }

    private var lastUpdateCheckText: String {
        guard let date = updateManager.lastUpdateCheckDate else {
            return "从未检查"
        }

        return date.formatted(date: .numeric, time: .shortened)
    }

    private var automaticallyChecksForUpdates: Binding<Bool> {
        Binding {
            updateManager.automaticallyChecksForUpdates
        } set: { newValue in
            updateManager.setAutomaticallyChecksForUpdates(newValue)
        }
    }

    private var automaticallyDownloadsUpdates: Binding<Bool> {
        Binding {
            updateManager.automaticallyDownloadsUpdates
        } set: { newValue in
            updateManager.setAutomaticallyDownloadsUpdates(newValue)
        }
    }

    private var updateCheckInterval: Binding<UpdateCheckInterval> {
        Binding {
            UpdateCheckInterval.from(seconds: updateManager.updateCheckInterval)
        } set: { newValue in
            updateManager.setUpdateCheckInterval(newValue)
        }
    }

    private func bundleInfoValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              !value.contains("$(") else {
            return nil
        }

        return value
    }
}

#if DEBUG
private struct DebugSettingsBadge: View {
    var body: some View {
        Text("Debug")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color(nsColor: .systemRed))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: ControlPanelDesign.compactRadius, style: .continuous)
                    .fill(Color(nsColor: .systemRed).opacity(0.12))
            }
            .accessibilityLabel("Debug 构建")
    }
}
#endif

private struct SettingsFormRow<Title: View, Control: View>: View {
    let title: Title
    let control: Control

    init(title: String, @ViewBuilder control: () -> Control) where Title == Text {
        self.title = Text(title)
        self.control = control()
    }

    init(
        @ViewBuilder title: () -> Title,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title()
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            title
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
    isOn: Binding<Bool>
) -> some View {
    SettingsFormRow(title: title) {
        Toggle("", isOn: isOn)
            .labelsHidden()
            .toggleStyle(.switch)
    }
}

private func historyLimitRow(
    title: String,
    value: Binding<Double>,
    range: ClosedRange<Double>,
    step: Double
) -> some View {
    SettingsFormRow(title: title) {
        HStack(spacing: 10) {
            Slider(value: value, in: range, step: step)
                .frame(width: ControlPanelDesign.Layout.Settings.sliderWidth)

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
        dockIconPreference: DockIconPreference(),
        updateManager: AppUpdateManager(),
        openOnboardingAction: {}
    )
}
