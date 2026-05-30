import AppKit
import SwiftUI

@MainActor
final class TranslationQuickPanelPresenter {
    private var panel: TranslationQuickPanelWindow?
    private var localMouseDownMonitor: Any?
    private var globalMouseDownMonitor: Any?
    private var resignKeyObserver: Any?
    private weak var translationController: TranslationController?
    private var currentSourceText: String?
    private var currentErrorMessage: String?
    private var isPinned = false
    var openFullTranslationAction: (() -> Void)?

    func show(
        controller: TranslationController,
        sourceText: String?,
        errorMessage: String? = nil
    ) {
        translationController = controller
        currentSourceText = sourceText
        currentErrorMessage = errorMessage

        if panel == nil {
            panel = makePanel()
        }

        guard let panel else {
            return
        }

        let rootView = TranslationQuickPanelView(
            controller: controller,
            sourceText: sourceText,
            errorMessage: errorMessage,
            isPinned: isPinned,
            onCopySource: { [weak self] in
                self?.translationController?.copySourceToPasteboard()
            },
            onCopyBestTranslation: { [weak self] in
                self?.translationController?.copyResultToPasteboard()
            },
            onCopyProviderTranslation: { [weak self] providerID in
                self?.translationController?.copyResultToPasteboard(providerID: providerID)
            },
            onTogglePinned: { [weak self] in
                self?.togglePinned()
            },
            onOpenFullTranslation: { [weak self] in
                self?.openFullTranslation()
            },
            onClose: { [weak self] in
                self?.dismiss()
            }
        )

        panel.contentView = NSHostingView(rootView: rootView)
        panel.setFrameOrigin(panelOrigin(for: panel.frame.size))
        panel.deminiaturize(nil)
        panel.orderFrontRegardless()
        panel.makeKey()
        installAutoDismissObservers(for: panel)
    }

    func dismiss() {
        removeAutoDismissObservers()
        panel?.orderOut(nil)
    }

    private func openFullTranslation() {
        dismiss()
        openFullTranslationAction?()
    }

    private func togglePinned() {
        isPinned.toggle()
        if isPinned {
            removeAutoDismissObservers()
        }

        if let controller = translationController {
            show(
                controller: controller,
                sourceText: currentSourceText,
                errorMessage: currentErrorMessage
            )
        }
    }

    private func makePanel() -> TranslationQuickPanelWindow {
        let panel = TranslationQuickPanelWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: ControlPanelDesign.Layout.QuickPanel.translationWidth,
                height: ControlPanelDesign.Layout.QuickPanel.translationHeight
            ),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        return panel
    }

    private func installAutoDismissObservers(for panel: NSPanel) {
        guard !isPinned else {
            return
        }

        removeAutoDismissObservers()

        localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else {
                return event
            }

            if self.shouldDismissForCurrentMouseLocation() {
                self.dismiss()
            }

            return event
        }

        globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismiss()
            }
        }

        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismiss()
            }
        }
    }

    private func removeAutoDismissObservers() {
        if let localMouseDownMonitor {
            NSEvent.removeMonitor(localMouseDownMonitor)
            self.localMouseDownMonitor = nil
        }

        if let globalMouseDownMonitor {
            NSEvent.removeMonitor(globalMouseDownMonitor)
            self.globalMouseDownMonitor = nil
        }

        if let resignKeyObserver {
            NotificationCenter.default.removeObserver(resignKeyObserver)
            self.resignKeyObserver = nil
        }
    }

    private func shouldDismissForCurrentMouseLocation() -> Bool {
        guard let panel, panel.isVisible else {
            return false
        }

        return !panel.frame.contains(NSEvent.mouseLocation)
    }

    private func panelOrigin(for size: CGSize) -> CGPoint {
        let anchor = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) })
            ?? NSScreen.main else {
            return anchor
        }

        return ClipboardQuickPanelPositioning.panelOrigin(
            near: anchor,
            panelSize: size,
            visibleFrame: screen.visibleFrame
        )
    }
}

private final class TranslationQuickPanelWindow: NSPanel {
    var keyDownHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyDownHandler?(event) == true {
            return
        }

        super.sendEvent(event)
    }
}

private struct TranslationQuickPanelView: View {
    @Bindable var controller: TranslationController
    let sourceText: String?
    let errorMessage: String?
    let isPinned: Bool
    let onCopySource: () -> Void
    let onCopyBestTranslation: () -> Void
    let onCopyProviderTranslation: (String) -> Void
    let onTogglePinned: () -> Void
    let onOpenFullTranslation: () -> Void
    let onClose: () -> Void

    private var visibleErrorMessage: String? {
        if !controller.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return controller.lastErrorMessage
        }

        return errorMessage ?? controller.lastErrorMessage
    }

    private var isReadingSelection: Bool {
        sourceText == nil
            && controller.sourceText.isEmpty
            && visibleErrorMessage == nil
            && !controller.isTranslating
    }

    private var canEditSource: Bool {
        !isReadingSelection && !controller.isTranslating
    }

    private var canSelectTargetLanguage: Bool {
        canTranslateSource
    }

    private var canTranslateSource: Bool {
        !isReadingSelection
            && !controller.isTranslating
            && !controller.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSpeakSource: Bool {
        !controller.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sourceTextBinding: Binding<String> {
        Binding {
            controller.sourceText
        } set: { newValue in
            controller.editSourceText(newValue)
        }
    }

    private var visibleProviders: [TranslationProviderState] {
        controller.activeProviderStates
    }

    private var tint: Color {
        ControlPanelDesign.tint(for: .tran)
    }

    private var sourcePreviewText: String {
        if visibleErrorMessage != nil {
            return "输入原文"
        }

        return "正在读取选中文本..."
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ControlPanelHairline(.horizontal)

            content
        }
        .frame(
            width: ControlPanelDesign.Layout.QuickPanel.translationWidth,
            height: ControlPanelDesign.Layout.QuickPanel.translationHeight
        )
        .controlPanelPanelChrome(cornerRadius: ControlPanelDesign.Layout.QuickPanel.cornerRadius)
        .background(TranslationQuickPanelKeyboardBridge { event in
            handleKeyDown(event)
        })
    }

    private var header: some View {
        ControlPanelSidebarHeader(
            title: "划词翻译",
            systemImage: "text.bubble",
            tint: tint
        ) {
            headerActions
        }
        .padding(.horizontal, ControlPanelDesign.Layout.QuickPanel.headerHorizontalPadding)
        .padding(.vertical, ControlPanelDesign.Layout.QuickPanel.headerVerticalPadding)
    }

    private var headerActions: some View {
        HStack(spacing: 6) {
            Button(action: onCopySource) {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(ControlPanelIconButtonStyle())
            .disabled(controller.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("复制原文")

            Button(action: onTogglePinned) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
            }
            .buttonStyle(ControlPanelIconButtonStyle(role: isPinned ? .selected : .normal, tint: tint))
            .help(isPinned ? "取消固定" : "固定小窗")

            Button(action: onOpenFullTranslation) {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(ControlPanelIconButtonStyle())
            .help("打开完整翻译")

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(ControlPanelIconButtonStyle())
            .help("关闭")
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: ControlPanelDesign.Layout.QuickPanel.sectionSpacing) {
            sourceSection

            languageBar

            resultsSection
        }
        .padding(ControlPanelDesign.Layout.QuickPanel.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var languageBar: some View {
        HStack(spacing: 8) {
            Label("语言", systemImage: "globe")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .frame(width: 56, alignment: .leading)

            Picker("原文语言", selection: sourceLanguageSelection) {
                Text(TranslationLanguage.automaticSourceName)
                    .tag(TranslationLanguage.automaticSourceCode)
                Divider()
                ForEach(TranslationLanguage.supportedSources) { language in
                    Text(language.name).tag(language.code)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: ControlPanelDesign.Layout.QuickPanel.languagePickerWidth)
            .help("切换原文语言")

            Button(action: swapLanguages) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption)
            }
            .buttonStyle(ControlPanelIconButtonStyle())
            .disabled(!canSwapLanguages)
            .help("交换语言")

            Picker("目标语言", selection: targetLanguageSelection) {
                ForEach(TranslationLanguage.supported) { language in
                    Text(language.name).tag(language.code)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: ControlPanelDesign.Layout.QuickPanel.languagePickerWidth)
            .help("切换目标语言")
        }
        .padding(.horizontal, ControlPanelDesign.Layout.QuickPanel.groupPadding)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(!canSelectTargetLanguage)
        .controlPanelRoundedSurface(
            background: ControlPanelDesign.embeddedPanelBackground,
            cornerRadius: ControlPanelDesign.cardRadius
        )
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: "text.alignleft")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("原文")
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: 8)

                if !controller.sourceText.isEmpty {
                    Text("\(controller.sourceText.count) 字")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                TranslationSpeechButton(
                    isSpeaking: controller.speakingTarget == .source,
                    canSpeak: canSpeakSource,
                    idleHelp: "朗读原文",
                    action: controller.speakSourceText
                )

                Button(action: translateCurrentSelection) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(ControlPanelIconButtonStyle())
                .disabled(!canTranslateSource)
                .help("用当前原文重新翻译")
            }
            .frame(height: 22)

            ZStack(alignment: .topLeading) {
                TranslationQuickPanelSourceEditor(
                    text: sourceTextBinding,
                    isEditable: canEditSource
                )
                .padding(1)

                if controller.sourceText.isEmpty {
                    Text(sourcePreviewText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .allowsHitTesting(false)
                }
            }
                .frame(
                    maxWidth: .infinity,
                    minHeight: ControlPanelDesign.Layout.QuickPanel.sourceMinHeight,
                    maxHeight: ControlPanelDesign.Layout.QuickPanel.sourceMinHeight,
                    alignment: .topLeading
                )
                .controlPanelTextSurface(cornerRadius: ControlPanelDesign.compactRadius)
        }
        .controlPanelQuickPanelGroup()
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ControlPanelCompactSectionHeader(title: "翻译结果", systemImage: "rectangle.stack") {
                Text("\(visibleProviders.count) 个服务")
            }

            if visibleProviders.isEmpty {
                ControlPanelNoResultsState(
                    title: "暂无翻译服务",
                    systemImage: "text.badge.xmark"
                )
                .frame(maxWidth: .infinity, minHeight: 112)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        providerCards
                    }
                    .padding(.vertical, 1)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .controlPanelQuickPanelGroup()
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var providerCards: some View {
        ForEach(visibleProviders) { provider in
            TranslationProviderCard(
                provider: provider.provider,
                status: providerStatus(for: provider),
                translatedText: providerTranslatedText(for: provider),
                detectedSourceLanguageCode: provider.detectedSourceLanguageCode,
                canCopy: providerCanCopy(for: provider),
                canSpeak: providerCanCopy(for: provider),
                isSpeaking: controller.isSpeakingResult(providerID: provider.provider.id),
                onCopy: {
                    onCopyProviderTranslation(provider.provider.id)
                },
                onSpeak: {
                    controller.speakResult(providerID: provider.provider.id)
                },
                onRetry: translateCurrentSelection,
                contentMinHeight: ControlPanelDesign.Layout.QuickPanel.providerMinHeight,
                isCompact: true
            )
        }
    }

    private func providerStatus(for provider: TranslationProviderState) -> TranslationProviderStatus {
        if isReadingSelection {
            return .loading("正在读取选中文本...")
        }

        if controller.isTranslating {
            return provider.status
        }

        if let visibleErrorMessage {
            return .failed(visibleErrorMessage)
        }

        return provider.status
    }

    private func providerTranslatedText(for provider: TranslationProviderState) -> String {
        switch providerStatus(for: provider) {
        case .success:
            provider.translatedText
        case .idle, .loading, .failed:
            ""
        }
    }

    private func providerCanCopy(for provider: TranslationProviderState) -> Bool {
        switch providerStatus(for: provider) {
        case .success:
            !provider.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .idle, .loading, .failed:
            false
        }
    }

    private var targetLanguageSelection: Binding<String> {
        Binding {
            controller.targetLanguageCode
        } set: { newValue in
            guard newValue != controller.targetLanguageCode else {
                return
            }

            controller.selectTargetLanguage(newValue, persistsDefault: false)
            translateCurrentSelection()
        }
    }

    private var sourceLanguageSelection: Binding<String> {
        Binding {
            controller.sourceLanguageCode ?? TranslationLanguage.automaticSourceCode
        } set: { newValue in
            let selectedCode = newValue == TranslationLanguage.automaticSourceCode ? nil : newValue
            guard selectedCode != controller.sourceLanguageCode else {
                return
            }

            controller.selectSourceLanguage(selectedCode, persistsDefault: false)
            translateCurrentSelection()
        }
    }

    private func translateCurrentSelection() {
        guard canTranslateSource else {
            return
        }

        Task {
            await controller.translate()
        }
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
        translateCurrentSelection()
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isTextEditorActive = event.window?.firstResponder is NSTextView

        switch event.keyCode {
        case 53:
            onClose()
            return true
        case 36, 76:
            guard modifierFlags.contains(.command) else {
                return false
            }

            translateCurrentSelection()
            return true
        case 8 where modifierFlags.contains(.command) && !isTextEditorActive:
            onCopyBestTranslation()
            return true
        default:
            return false
        }
    }
}

private struct TranslationQuickPanelSourceEditor: NSViewRepresentable {
    @Binding var text: String
    let isEditable: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
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

        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        textView.isEditable = isEditable

        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            text.wrappedValue = textView.string
        }
    }
}

private struct TranslationQuickPanelKeyboardBridge: NSViewRepresentable {
    let handler: (NSEvent) -> Bool

    func makeNSView(context: Context) -> NSView {
        TranslationQuickPanelKeyboardBridgeView(handler: handler)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? TranslationQuickPanelKeyboardBridgeView)?.handler = handler
    }
}

private final class TranslationQuickPanelKeyboardBridgeView: NSView {
    var handler: (NSEvent) -> Bool

    init(handler: @escaping (NSEvent) -> Bool) {
        self.handler = handler
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        (window as? TranslationQuickPanelWindow)?.keyDownHandler = { [weak self] event in
            self?.handler(event) ?? false
        }
    }

    deinit {
        (window as? TranslationQuickPanelWindow)?.keyDownHandler = nil
    }
}
