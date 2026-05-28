import Foundation
import KeyboardShortcuts

@MainActor
final class AppShortcutController {
    private let clipboardMonitor: ClipboardMonitor
    private let screenshotController: ScreenshotController
    private let translationController: TranslationController
    private let clipboardQuickPanelPresenter = ClipboardQuickPanelPresenter()
    private var tasks: [Task<Void, Never>] = []
    var selectSection: ((AppSection) -> Void)?
    var openSection: ((AppSection) -> Void)?

    init(
        clipboardMonitor: ClipboardMonitor,
        screenshotController: ScreenshotController,
        translationController: TranslationController
    ) {
        self.clipboardMonitor = clipboardMonitor
        self.screenshotController = screenshotController
        self.translationController = translationController
        clipboardQuickPanelPresenter.openFullClipboardAction = { [weak self] in
            self?.openSection?(.clip)
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
            Task { await observeTranslateClipboardShortcut() }
        ]
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    private func observeShowClipShortcut() async {
        for await event in KeyboardShortcuts.events(for: .showClip) where event == .keyUp {
            openSection?(.clip)
        }
    }

    private func observeClipboardQuickPanelShortcut() async {
        for await event in KeyboardShortcuts.events(for: .showClipboardQuickPanel) where event == .keyUp {
            clipboardQuickPanelPresenter.toggle(monitor: clipboardMonitor)
        }
    }

    private func observeCaptureSelectedRegionShortcut() async {
        for await event in KeyboardShortcuts.events(for: .captureSelectedRegion) where event == .keyUp {
            openSection?(.pix)
            await screenshotController.captureSelectedRegion()
        }
    }

    private func observeTranslateClipboardShortcut() async {
        for await event in KeyboardShortcuts.events(for: .translateClipboardText) where event == .keyUp {
            guard let text = SystemClipboardService().readPlainText() else {
                continue
            }

            translationController.prefillSourceText(text)
            openSection?(.tran)
            await translationController.translate()
        }
    }
}
