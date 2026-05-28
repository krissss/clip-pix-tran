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

    @State private var clipboardMonitor = ClipboardMonitor(
        pasteboard: SystemClipboardService(),
        history: ClipboardHistoryStore(
            persistence: FileClipboardHistoryPersistence(),
            persistsHistoryDefaultsKey: HistoryPersistencePreferenceKey.clipboard
        )
    )
    @State private var screenshotController = ScreenshotController(
        history: ScreenshotHistoryStore(
            persistence: FileScreenshotHistoryPersistence(),
            persistsHistoryDefaultsKey: HistoryPersistencePreferenceKey.screenshot
        ),
        screenshotService: SystemScreenshotService(),
        pasteboard: SystemScreenshotPasteboardService(),
        fileSaver: SystemScreenshotFileSaver()
    )
    @State private var translationController = TranslationController(
        history: TranslationHistoryStore(
            persistence: FileTranslationHistoryPersistence(),
            persistsHistoryDefaultsKey: HistoryPersistencePreferenceKey.translation
        ),
        translationService: HybridTranslationService(),
        pasteboard: SystemClipboardService()
    )
    @State private var shortcutController: AppShortcutController

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
            fileSaver: SystemScreenshotFileSaver()
        )
        let translationController = TranslationController(
            history: TranslationHistoryStore(
                persistence: FileTranslationHistoryPersistence(),
                persistsHistoryDefaultsKey: HistoryPersistencePreferenceKey.translation
            ),
            translationService: HybridTranslationService(),
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
    }

    var body: some Scene {
        WindowGroup("ClipPixTran", id: "main") {
            ContentView(
                clipboardMonitor: clipboardMonitor,
                screenshotController: screenshotController,
                translationController: translationController,
                shortcutController: shortcutController
            )
                .frame(minWidth: 760, minHeight: 520)
                .onAppear {
                    clipboardMonitor.start()
                    shortcutController.start()
                }
        }
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: 1040, height: 680)

        Settings {
            AppSettingsView(
                clipboardHistory: clipboardMonitor.history,
                screenshotHistory: screenshotController.history,
                translationController: translationController
            )
        }
    }
}

final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        bringMainWindowForward()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        bringMainWindowForward()
        return true
    }

    private func bringMainWindowForward() {
        DispatchQueue.main.async {
            AppWindowPresenter.bringMainWindowForward()
        }
    }
}
