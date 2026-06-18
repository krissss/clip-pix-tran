import SwiftUI
import KeyboardShortcuts

struct AppSettingsView: View {
    @Bindable var clipboardHistory: ClipboardHistoryStore
    @Bindable var screenshotHistory: ScreenshotHistoryStore
    @Bindable var translationController: TranslationController
    @Bindable var dockIconPreference: DockIconPreference
    @Bindable var launchAtLoginPreference: LaunchAtLoginPreference
    @Bindable var localizationPreference: LocalizationPreference
    @Bindable var updateManager: AppUpdateManager
    let openOnboardingAction: () -> Void
    @State private var selectedPane: SettingsPane = .general

    var body: some View {
        VStack(spacing: 0) {
            SettingsPaneToolbar(selectedPane: $selectedPane)
                .layoutPriority(1)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                launchAtLoginPreference: launchAtLoginPreference,
                localizationPreference: localizationPreference,
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
            L10n.settingsGeneral
        case .shortcuts:
            L10n.settingsShortcuts
        case .clip:
            "Clip"
        case .pix:
            "Pix"
        case .tran:
            "Tran"
        case .about:
            L10n.settingsAbout
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
    @Bindable var launchAtLoginPreference: LaunchAtLoginPreference
    @Bindable var localizationPreference: LocalizationPreference
    let openOnboardingAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsGroup(title: L10n.settingsStartup) {
                VStack(spacing: 0) {
                    toggleRow(
                        L10n.settingsLaunchAtLogin,
                        isOn: launchesAtLogin
                    )
                    .disabled(launchAtLoginPreference.isToggleDisabled)
                }
                .settingsRowGroup()
            }

            SettingsFootnote(launchAtLoginPreference.statusMessage)

            SettingsGroup(title: L10n.settingsDock) {
                VStack(spacing: 0) {
                    toggleRow(
                        L10n.settingsHideDockIcon,
                        isOn: hidesDockIconWhenMainWindowClosed
                    )
                }
                .settingsRowGroup()
            }

            SettingsGroup(title: L10n.languageHeader) {
                VStack(spacing: 0) {
                    SettingsFormRow(title: L10n.settingsInterfaceLanguage) {
                        Picker("", selection: appLanguage) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
                .settingsRowGroup()
            }

            SettingsGroup(title: L10n.settingsOnboarding) {
                VStack(spacing: 0) {
                    SettingsFormRow(title: L10n.settingsFirstLaunchOnboarding) {
                        Button {
                            openOnboardingAction()
                        } label: {
                            Label(L10n.settingsReopen, systemImage: "sparkles.rectangle.stack")
                        }
                    }
                }
                .settingsRowGroup()
            }

            SettingsFootnote(L10n.settingsGeneralFootnote)
        }
        .onAppear {
            launchAtLoginPreference.refresh()
        }
    }

    private var launchesAtLogin: Binding<Bool> {
        Binding {
            launchAtLoginPreference.launchesAtLogin
        } set: { newValue in
            launchAtLoginPreference.setLaunchesAtLogin(newValue)
        }
    }

    private var hidesDockIconWhenMainWindowClosed: Binding<Bool> {
        Binding {
            preference.hidesDockIconWhenMainWindowClosed
        } set: { newValue in
            preference.updateHidesDockIconWhenMainWindowClosed(newValue)
        }
    }

    private var appLanguage: Binding<AppLanguage> {
        Binding {
            localizationPreference.language
        } set: { newValue in
            localizationPreference.updateLanguage(newValue)
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
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .foregroundStyle(selectedPane == pane ? Color.accentColor : Color.secondary)
                    .padding(.horizontal, 8)
                    .frame(minWidth: ControlPanelDesign.Layout.Settings.paneTabMinWidth, minHeight: 30)
                    .fixedSize(horizontal: true, vertical: false)
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
        SettingsGroup(title: L10n.settingsGlobalShortcuts) {
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
            LocalizedShortcutRecorder(name: shortcut.name)
        }
    }
}

private struct ClipSettingsSection: View {
    @Bindable var history: ClipboardHistoryStore

    var body: some View {
        SettingsGroup(title: L10n.settingsHistory) {
            VStack(spacing: 0) {
                toggleRow(L10n.settingsPersistClipboardHistory, isOn: persistsHistory)
                historyLimitRow(
                    title: L10n.settingsNormalHistoryLimit,
                    value: maximumNormalItems,
                    range: 10...200,
                    step: 10
                )
            }
            .settingsRowGroup()
        }

        SettingsFootnote(L10n.settingsClipHistoryFootnote)
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
        SettingsGroup(title: L10n.settingsHistory) {
            VStack(spacing: 0) {
                toggleRow(L10n.settingsPersistScreenshotHistory, isOn: persistsHistory)
                historyLimitRow(
                    title: L10n.settingsScreenshotHistoryLimit,
                    value: maximumItems,
                    range: 5...200,
                    step: 5
                )
            }
            .settingsRowGroup()
        }

        SettingsFootnote(L10n.settingsPixHistoryFootnote)
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
            SettingsGroup(title: L10n.settingsDefaultLanguages) {
                VStack(spacing: 0) {
                    SettingsFormRow(title: L10n.settingsDefaultSourceLanguage) {
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
                    }
                    SettingsFormRow(title: L10n.settingsDefaultTargetLanguage) {
                        Picker("", selection: targetLanguageSelection) {
                            ForEach(TranslationLanguage.supported) { language in
                                Text(language.name).tag(language.code)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
                .settingsRowGroup()
            }

            SettingsGroup(title: L10n.settingsTranslationServices) {
                VStack(spacing: 0) {
                    ForEach(TranslationProviderDescriptor.builtIn) { provider in
                        providerToggleRow(provider)
                    }
                }
                .settingsRowGroup()
            }

            SettingsGroup(title: L10n.settingsSpeechServices) {
                VStack(spacing: 0) {
                    SettingsFormRow(title: L10n.settingsDefaultSpeech) {
                        Picker("", selection: speechProviderSelection) {
                            ForEach(TranslationSpeechProviderDescriptor.builtIn) { provider in
                                Label(provider.name, systemImage: provider.systemImage)
                                    .tag(provider.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
                .settingsRowGroup()
            }

            SettingsGroup(title: L10n.settingsHistory) {
                VStack(spacing: 0) {
                    toggleRow(L10n.settingsPersistTranslationHistory, isOn: persistsHistory)
                    historyLimitRow(
                        title: L10n.settingsTranslationHistoryLimit,
                        value: maximumItems,
                        range: 10...200,
                        step: 10
                    )
                }
                .settingsRowGroup()
            }
        }

        SettingsFootnote(L10n.settingsTranFootnote)
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
        .frame(maxWidth: ControlPanelDesign.Layout.Settings.formMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct AboutSettingsSection: View {
    @Bindable var updateManager: AppUpdateManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup(title: L10n.settingsUpdates) {
                VStack(spacing: 0) {
                    SettingsFormRow(title: L10n.settingsCurrentVersion) {
                        HStack(spacing: 8) {
                            Text(appVersionText)
                                .font(.callout.monospacedDigit())

                            #if DEBUG
                            DebugSettingsBadge()
                            #endif
                        }
                    }

                    toggleRow(L10n.settingsAutoCheckUpdates, isOn: automaticallyChecksForUpdates)
                        .disabled(!updateManager.updateCheckingIsAvailable)
                    toggleRow(L10n.settingsAutoDownloadUpdates, isOn: automaticallyDownloadsUpdates)
                        .disabled(!updateManager.updateCheckingIsAvailable)

                    SettingsFormRow(title: L10n.settingsCheckFrequency) {
                        Picker("", selection: updateCheckInterval) {
                            ForEach(UpdateCheckInterval.allCases) { interval in
                                Text(interval.displayName).tag(interval)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .disabled(!updateManager.updateCheckingIsAvailable)
                    }

                    SettingsFormRow(title: L10n.settingsLastChecked) {
                        HStack(spacing: 10) {
                            Text(lastUpdateCheckText)
                                .font(.callout)

                            Spacer(minLength: 0)

                            Button {
                                updateManager.checkForUpdates()
                            } label: {
                                Label(L10n.settingsCheckUpdates, systemImage: "arrow.clockwise")
                            }
                            .controlSize(.small)
                            .disabled(!updateManager.canCheckForUpdates)
                        }
                    }
                }
                .settingsRowGroup()
            }

            SettingsFootnote(updateManager.statusMessage)
        }
    }

    private var appVersionText: String {
        let version = bundleInfoValue("CFBundleShortVersionString") ?? L10n.settingsUnknown
        guard let build = bundleInfoValue("CFBundleVersion"),
              build != version else {
            return version
        }

        return "\(version) (\(build))"
    }

    private var lastUpdateCheckText: String {
        guard let date = updateManager.lastUpdateCheckDate else {
            return L10n.settingsNeverChecked
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
            .accessibilityLabel(L10n.appDebugBuild)
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

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
            .frame(maxWidth: ControlPanelDesign.Layout.Settings.formMaxWidth, alignment: .leading)
            .controlPanelRoundedSurface(
                background: ControlPanelDesign.quietFill,
                cornerRadius: ControlPanelDesign.compactRadius
            )
            .frame(maxWidth: .infinity, alignment: .center)
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
        launchAtLoginPreference: LaunchAtLoginPreference(),
        localizationPreference: LocalizationPreference(),
        updateManager: AppUpdateManager(),
        openOnboardingAction: {}
    )
}
