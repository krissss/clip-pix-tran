//
//  Application.swift
//
//  Created by kriss k on 2026/5/25.
//

import AppKit
import SwiftUI

@main
struct Application: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    @State private var clipboardMonitor: ClipboardMonitor
    @State private var screenshotController: ScreenshotController
    @State private var translationController: TranslationController
    @State private var shortcutController: AppShortcutController
    @State private var dockIconPreference: DockIconPreference
    @State private var selectedSection: AppSection = .clip

    init() {
        let clipboardMonitor = ClipboardMonitor(
            pasteboard: SystemClipboardService(),
            history: ClipboardHistoryStore(
                persistence: FileClipboardHistoryPersistence(),
                persistsHistoryDefaultsKey: HistoryPersistencePreferenceKey.clipboard
            )
        )
        let screenshotController = ScreenshotController(
            history: ScreenshotHistoryStore(
                persistence: FileScreenshotHistoryPersistence(),
                persistsHistoryDefaultsKey: HistoryPersistencePreferenceKey.screenshot
            ),
            screenshotService: SystemScreenshotService(),
            pasteboard: SystemScreenshotPasteboardService(),
            fileSaver: SystemScreenshotFileSaver(),
            pinning: ScreenshotPinToScreenPresenter()
        )
        let translationController = TranslationController(
            history: TranslationHistoryStore(
                persistence: FileTranslationHistoryPersistence(),
                persistsHistoryDefaultsKey: HistoryPersistencePreferenceKey.translation
            ),
            pasteboard: SystemClipboardService()
        )

        self._clipboardMonitor = State(initialValue: clipboardMonitor)
        self._screenshotController = State(initialValue: screenshotController)
        self._translationController = State(initialValue: translationController)
        self._shortcutController = State(
            initialValue: AppShortcutController(
                clipboardMonitor: clipboardMonitor,
                screenshotController: screenshotController,
                translationController: translationController
            )
        )
        self._dockIconPreference = State(initialValue: DockIconPreference())
    }

    var body: some Scene {
        let _ = configureAppRuntime()

        WindowGroup("ClipPixTran", id: "main") {
            ContentView(
                clipboardMonitor: clipboardMonitor,
                screenshotController: screenshotController,
                translationController: translationController,
                shortcutController: shortcutController,
                selectedSection: $selectedSection
            )
                .frame(minWidth: 760, minHeight: 520)
                .onAppear {
                    AppDockIconController.shared.updateActivationPolicy()
                }
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 1040, height: 680)

        Settings {
            AppSettingsView(
                clipboardHistory: clipboardMonitor.history,
                screenshotHistory: screenshotController.history,
                translationController: translationController,
                dockIconPreference: dockIconPreference
            )
        }
    }

    private func configureAppRuntime() {
        AppDockIconController.shared.configure(preference: dockIconPreference)
        clipboardMonitor.start()
        shortcutController.start()
        shortcutController.openSection = { section in
            selectedSection = section
            openMainWindow()
        }
        AppStatusMenuController.shared.configure(
            clipboardMonitor: clipboardMonitor,
            screenshotController: screenshotController,
            translationController: translationController,
            shortcutController: shortcutController,
            openMainWindowAction: openMainWindow,
            openSettingsAction: openSettings.callAsFunction
        )
    }

    private func openMainWindow() {
        if !AppWindowPresenter.bringMainWindowForward() {
            openWindow(id: "main")
            DispatchQueue.main.async {
                AppWindowPresenter.bringMainWindowForward()
            }
        }
    }
}

final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        DispatchQueue.main.async {
            AppWindowPresenter.bringMainWindowForward()
        }
        return true
    }
}
