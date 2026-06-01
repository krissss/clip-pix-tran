import Foundation
import KeyboardShortcuts

@MainActor
final class AppShortcutController {
    private let clipboardMonitor: ClipboardMonitor
    private let screenshotController: ScreenshotController
    private let translationController: TranslationController
    private let textSelectionService: TextSelectionService
    private let clipboardQuickPanelPresenter = ClipboardQuickPanelPresenter()
    private let translationQuickPanelPresenter = TranslationQuickPanelPresenter()
    private var tasks: [Task<Void, Never>] = []
    var openSection: ((AppSection) -> Void)?

    init(
        clipboardMonitor: ClipboardMonitor,
        screenshotController: ScreenshotController,
        translationController: TranslationController,
        textSelectionService: TextSelectionService? = nil
    ) {
        self.clipboardMonitor = clipboardMonitor
        self.screenshotController = screenshotController
        self.translationController = translationController
        self.textSelectionService = textSelectionService ?? SystemTextSelectionService()
        clipboardQuickPanelPresenter.openFullClipboardAction = { [weak self] in
            self?.openSection?(.clip)
        }
        translationQuickPanelPresenter.openFullTranslationAction = { [weak self] in
            self?.openSection?(.tran)
        }
    }

    func start() {
        guard tasks.isEmpty else {
            return
        }

        tasks = [
            Task { await observeShowClipShortcut() },
            Task { await observeClipboardQuickPanelShortcut() },
            Task { await observeCaptureSelectedRegionShortcut() },
            Task { await observeTranslateSelectedTextShortcut() },
            Task { await observeTranslateClipboardShortcut() }
        ]
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    func showClip() {
        openSection?(.clip)
    }

    func showClipboardQuickPanel() {
        clipboardQuickPanelPresenter.toggle(monitor: clipboardMonitor)
    }

    func captureSelectedRegion() {
        Task {
            await screenshotController.captureSelectedRegion()
        }
    }

    func translateSelectedText() {
        Task {
            await performTranslateSelectedText()
        }
    }

    func translateClipboardText() {
        Task {
            await performTranslateClipboardText()
        }
    }

    private func observeShowClipShortcut() async {
        for await event in KeyboardShortcuts.events(for: .showClip) where event == .keyUp {
            showClip()
        }
    }

    private func observeClipboardQuickPanelShortcut() async {
        for await event in KeyboardShortcuts.events(for: .showClipboardQuickPanel) where event == .keyUp {
            showClipboardQuickPanel()
        }
    }

    private func observeCaptureSelectedRegionShortcut() async {
        for await event in KeyboardShortcuts.events(for: .captureSelectedRegion) where event == .keyUp {
            await screenshotController.captureSelectedRegion()
        }
    }

    private func observeTranslateSelectedTextShortcut() async {
        for await event in KeyboardShortcuts.events(for: .translateSelectedText) where event == .keyUp {
            await performTranslateSelectedText()
        }
    }

    private func observeTranslateClipboardShortcut() async {
        for await event in KeyboardShortcuts.events(for: .translateClipboardText) where event == .keyUp {
            await performTranslateClipboardText()
        }
    }

    private func performTranslateSelectedText() async {
        translationController.prefillSourceText("")

        guard let text = await textSelectionService.selectedText() else {
            translationQuickPanelPresenter.show(
                controller: translationController,
                sourceText: nil,
                errorMessage: TextSelectionError.noSelection.localizedDescription
            )
            return
        }

        translationController.prefillSourceText(text)
        translationQuickPanelPresenter.show(
            controller: translationController,
            sourceText: text
        )
        await translationController.translate()
    }

    private func performTranslateClipboardText() async {
        guard let text = SystemClipboardService().readPlainText() else {
            return
        }

        translationController.prefillSourceText(text)
        openSection?(.tran)
        await translationController.translate()
    }
}
