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

    var body: some Scene {
        WindowGroup("ClipPixTran", id: "main") {
            ContentView(
                clipboardMonitor: clipboardMonitor,
                screenshotController: screenshotController,
                translationController: translationController
            )
                .frame(minWidth: 760, minHeight: 520)
        }
        .defaultLaunchBehavior(.presented)

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
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
            NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
}
