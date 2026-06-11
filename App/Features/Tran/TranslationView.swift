import SwiftUI

struct TranslationView: View {
    @Bindable var controller: TranslationController
    @State private var historySearchText = ""
    @State private var showsClearHistoryConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            editor

            history
        }
        .navigationTitle("Tran")
        .background(ControlPanelBackground())
        .confirmationDialog(
            L10n.tranClearTitle,
            isPresented: $showsClearHistoryConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.commonClearHistory, role: .destructive) {
                controller.clearHistory()
            }

            Button(L10n.commonCancel, role: .cancel) {}
        } message: {
            Text(L10n.tranClearMessage)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            translateToolbar

            HStack(alignment: .top, spacing: 14) {
                sourcePane
                    .frame(minWidth: 280, maxWidth: .infinity)

                ControlPanelHairline(.vertical)
                    .padding(.vertical, 14)

                resultPane
                    .frame(minWidth: 300, maxWidth: .infinity)
            }
            .frame(minHeight: 260)

            if let speechErrorMessage = controller.speechErrorMessage {
                speechErrorBanner(speechErrorMessage)
            }
        }
        .padding(ControlPanelDesign.Layout.pagePadding)
        .overlay(alignment: .bottom) {
            ControlPanelHairline(.horizontal)
        }
    }

    private var translateToolbar: some View {
        HStack(spacing: 12) {
            ControlPanelSidebarHeader(
                title: L10n.tranTextTranslation,
                systemImage: "text.bubble",
                tint: ControlPanelDesign.tint(for: .tran)
            )

            languageBar

            Spacer()

            Button {
                Task {
                    await controller.translate()
                }
            } label: {
                if controller.isTranslating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label(L10n.tranTranslate, systemImage: "arrow.right.circle")
                }
            }
            .buttonStyle(ControlPanelButtonStyle(tint: ControlPanelDesign.tint(for: .tran), prominence: .primary))
            .disabled(controller.isTranslating)
        }
        .frame(maxWidth: .infinity)
    }

    private var sourcePane: some View {
        VStack(alignment: .leading, spacing: 8) {
            sourcePaneHeader

            ShortcutTextEditor(text: $controller.sourceText) {
                translate()
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            .padding(1)
            .controlPanelTextSurface()
        }
        .controlPanelDetailSection()
    }

    private var sourcePaneHeader: some View {
        HStack(spacing: 8) {
            Label(L10n.tranSourceText, systemImage: "text.alignleft")
                .font(.headline)

            Spacer()

            Text(sourceLanguageName)
                .font(.callout)
                .foregroundStyle(.secondary)

            TranslationSpeechButton(
                isPreparing: controller.preparingSpeechTarget == .source,
                isSpeaking: controller.speakingTarget == .source,
                canSpeak: canSpeakSourceText,
                idleHelp: L10n.tranSpeakSource,
                speechProviderName: controller.currentSpeechProviderName,
                action: controller.speakSourceText
            )
        }
        .frame(height: 26)
    }

    private var resultPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            paneHeader(
                title: L10n.tranResult,
                systemImage: "rectangle.stack",
                accessory: L10n.tranProviderCount(visibleProviders.count)
            )

            providerDeck
        }
        .controlPanelDetailSection()
    }

    private func paneHeader(
        title: String,
        systemImage: String,
        accessory: String
    ) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            Spacer()

            Text(accessory)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(height: 26)
    }

    private func speechErrorBanner(_ message: String) -> some View {
        Label(message, systemImage: "speaker.slash")
            .font(.caption)
            .foregroundStyle(.red)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .controlPanelRoundedSurface(
                background: ControlPanelDesign.quietFill,
                cornerRadius: ControlPanelDesign.compactRadius
            )
    }

    private var languageBar: some View {
        HStack(spacing: 10) {
            Picker(L10n.tranSourceLanguage, selection: sourceLanguageSelection) {
                Text(TranslationLanguage.automaticSourceName)
                    .tag(TranslationLanguage.automaticSourceCode)
                ForEach(TranslationLanguage.supportedSources) { language in
                    Text(language.name).tag(language.code)
                }
            }
            .labelsHidden()
            .frame(width: 142)

            Button(action: swapLanguages) {
                Image(systemName: "arrow.left.arrow.right")
            }
            .buttonStyle(ControlPanelIconButtonStyle())
            .disabled(!canSwapLanguages)
            .help(L10n.tranSwapLanguages)

            Picker(L10n.tranTargetLanguage, selection: targetLanguageSelection) {
                ForEach(TranslationLanguage.supported) { language in
                    Text(language.name).tag(language.code)
                }
            }
            .labelsHidden()
            .frame(width: 142)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .controlPanelRoundedSurface(
            background: ControlPanelDesign.embeddedPanelBackground,
            cornerRadius: ControlPanelDesign.compactRadius
        )
        .disabled(controller.isTranslating)
    }

    private var providerDeck: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                providerCards
            }
            .padding(.vertical, 1)
        }
        .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 300)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var providerCards: some View {
        ForEach(visibleProviders) { provider in
            TranslationProviderCard(
                provider: provider.provider,
                status: provider.status,
                translatedText: provider.translatedText,
                canCopy: hasTranslatedText(for: provider),
                canSpeak: hasTranslatedText(for: provider),
                isPreparingSpeech: controller.isPreparingSpeechResult(providerID: provider.provider.id),
                isSpeaking: controller.isSpeakingResult(providerID: provider.provider.id),
                speechProviderName: controller.currentSpeechProviderName,
                onCopy: {
                    controller.copyResultToPasteboard(providerID: provider.provider.id)
                },
                onSpeak: {
                    controller.speakResult(providerID: provider.provider.id)
                },
                onRetry: translate,
                contentMinHeight: 34
            )
        }
    }

    private var visibleProviders: [TranslationProviderState] {
        controller.activeProviderStates
    }

    private var sourceLanguageName: String {
        guard let sourceLanguageCode = controller.effectiveSourceLanguageCode else {
            return controller.sourceLanguageCode == nil
                ? TranslationLanguage.automaticSourceName
                : TranslationLanguage.name(for: controller.sourceLanguageCode ?? "")
        }

        if controller.sourceLanguageCode == nil {
            return L10n.tranAutoDetectedLanguage(TranslationLanguage.name(for: sourceLanguageCode))
        }

        return TranslationLanguage.name(for: sourceLanguageCode)
    }

    private func translate() {
        Task {
            await controller.translate()
        }
    }

    private var canSpeakSourceText: Bool {
        !controller.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSwapLanguages: Bool {
        guard let sourceLanguageCode = controller.effectiveSourceLanguageCode else {
            return false
        }

        return TranslationLanguage.isSupported(sourceLanguageCode)
            && TranslationLanguage.isSupportedSource(controller.targetLanguageCode)
    }

    private func swapLanguages() {
        guard canSwapLanguages, let sourceLanguageCode = controller.effectiveSourceLanguageCode else {
            return
        }

        let targetLanguageCode = controller.targetLanguageCode
        controller.selectSourceLanguage(targetLanguageCode, persistsDefault: false)
        controller.selectTargetLanguage(sourceLanguageCode, persistsDefault: false)
    }

    @ViewBuilder
    private var history: some View {
        let visibleItems = controller.history.filteredItems(matching: historySearchText)
        if controller.history.items.isEmpty {
            ControlPanelEmptyState(
                title: L10n.tranEmptyHistory,
                systemImage: "text.bubble",
                tint: ControlPanelDesign.tint(for: .tran)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 5) {
                    historyActions

                    ControlPanelSearchField(text: $historySearchText, prompt: L10n.tranSearchHistory)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 6)

                    if let errorMessage = controller.history.persistenceErrorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }

                    if visibleItems.isEmpty {
                        ControlPanelNoResultsState(
                            title: L10n.tranNoResults,
                            systemImage: "text.bubble.fill"
                        )
                            .padding(.vertical, 36)
                    }

                    ForEach(visibleItems) { item in
                        TranslationHistoryRow(
                            item: item,
                            onUse: {
                                controller.useHistoryItem(item)
                            },
                            onSelectProvider: { providerID in
                                controller.history.selectProviderResult(providerID, for: item)
                            },
                            onDelete: {
                                controller.deleteHistoryItem(item)
                            }
                        )
                    }
                }
                .padding(.bottom, 8)
            }
            .controlPanelSidebarSurface(.history, showsTrailingBoundary: false)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var historyActions: some View {
        HStack {
            ControlPanelSectionLabel(title: L10n.tranHistory, systemImage: "clock")

            Text(historyCountText)
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            Button(role: .destructive) {
                showsClearHistoryConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(ControlPanelIconButtonStyle(role: .destructive))
            .disabled(controller.history.items.isEmpty)
            .help(L10n.tranClearHelp)
        }
        .font(.callout)
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var historyCountText: String {
        let totalCount = controller.history.items.count
        let visibleCount = controller.history.filteredItems(matching: historySearchText).count
        if historySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.commonRecordsCount(totalCount)
        }

        return L10n.commonFilteredRecordsCount(visible: visibleCount, total: totalCount)
    }

    private var targetLanguageSelection: Binding<String> {
        Binding {
            controller.targetLanguageCode
        } set: { newValue in
            controller.selectTargetLanguage(newValue, persistsDefault: false)
        }
    }

    private var sourceLanguageSelection: Binding<String> {
        Binding {
            controller.sourceLanguageCode ?? TranslationLanguage.automaticSourceCode
        } set: { newValue in
            controller.selectSourceLanguage(
                newValue == TranslationLanguage.automaticSourceCode ? nil : newValue,
                persistsDefault: false
            )
        }
    }

    private func hasTranslatedText(for provider: TranslationProviderState) -> Bool {
        !provider.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct ShortcutTextEditor: NSViewRepresentable {
    @Binding var text: String
    let onCommandReturn: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommandReturn: onCommandReturn)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true

        let textView = CommandReturnTextView()
        textView.delegate = context.coordinator
        textView.onCommandReturn = context.coordinator.handleCommandReturn
        textView.string = text
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onCommandReturn = onCommandReturn

        guard let textView = scrollView.documentView as? CommandReturnTextView else {
            return
        }

        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onCommandReturn: () -> Void

        init(text: Binding<String>, onCommandReturn: @escaping () -> Void) {
            self.text = text
            self.onCommandReturn = onCommandReturn
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            text.wrappedValue = textView.string
        }

        func handleCommandReturn() {
            onCommandReturn()
        }
    }
}

private final class CommandReturnTextView: NSTextView {
    var onCommandReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isReturnKey = event.keyCode == 36 || event.keyCode == 76

        if isReturnKey, modifierFlags.contains(.command) {
            onCommandReturn?()
            return
        }

        super.keyDown(with: event)
    }
}

private struct TranslationHistoryRow: View {
    let item: TranslationHistoryItem
    let onUse: () -> Void
    let onSelectProvider: (String) -> Void
    let onDelete: () -> Void

    private var languageText: String {
        let targetLanguage = TranslationLanguage.name(for: item.targetLanguageCode)
        let sourceLanguage = item.detectedSourceLanguageCode
            .map { TranslationLanguage.name(for: $0) }
            ?? item.sourceLanguageCode.map { TranslationLanguage.name(for: $0) }
            ?? TranslationLanguage.automaticSourceName
        return "\(sourceLanguage) → \(targetLanguage)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ControlPanelIconTile(
                systemImage: "text.bubble",
                tint: ControlPanelDesign.tint(for: .tran),
                size: 34
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(languageText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(item.providerResults.prefix(3)) { providerResult in
                        providerChip(providerResult)
                    }

                    if item.providerResults.count > 3 {
                        Text("+\(item.providerResults.count - 3)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                CompactTranslationText(
                    text: item.sourceText,
                    font: .subheadline,
                    foregroundColor: .secondary,
                    maxDisplayLines: 2,
                    lineLimitPerDisplayLine: 1,
                    lineSpacing: 1
                )

                CompactTranslationText(
                    text: item.translatedText,
                    font: .body,
                    maxDisplayLines: 3,
                    lineLimitPerDisplayLine: 1,
                    lineSpacing: 1
                )
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: onUse) {
                    Image(systemName: "arrow.up.left")
                }
                .buttonStyle(ControlPanelIconButtonStyle())
                .help(L10n.tranLoadHistory)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(ControlPanelIconButtonStyle(role: .destructive))
                .help(L10n.tranDeleteHistory)
            }
        }
        .controlPanelHistoryRow(isSelected: false, tint: ControlPanelDesign.tint(for: .tran))
        .padding(.horizontal, 12)
    }

    private func providerChip(_ providerResult: TranslationHistoryProviderResult) -> some View {
        let isSelected = providerResult.providerID == item.providerID
        return Button {
            onSelectProvider(providerResult.providerID)
        } label: {
            Text(providerResult.providerName)
                .font(.caption2.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .controlPanelRoundedSurface(
                    background: isSelected
                        ? ControlPanelDesign.tint(for: .tran).opacity(0.12)
                        : ControlPanelDesign.quietFill,
                    cornerRadius: ControlPanelDesign.compactRadius
                )
        }
        .buttonStyle(.plain)
        .help(L10n.tranSwitchProvider(providerResult.providerName))
        .disabled(isSelected)
    }
}

#Preview {
    TranslationView(
        controller: TranslationController(
            history: .preview,
            translationService: FallbackTranslationService(),
            pasteboard: PreviewClipboardService()
        )
    )
}
