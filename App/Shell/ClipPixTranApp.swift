//
//  ClipPixTranApp.swift
//
//  Created by kriss k on 2026/5/25.
//

import AppKit
import SwiftUI

@main
struct ClipPixTranApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase

    @State private var clipboardMonitor: ClipboardMonitor
    @State private var screenshotController: ScreenshotController
    @State private var translationController: TranslationController
    @State private var shortcutController: AppShortcutController
    @State private var dockIconPreference: DockIconPreference
    @State private var launchAtLoginPreference: LaunchAtLoginPreference
    @State private var onboardingPreference: FirstLaunchOnboardingPreference
    @State private var updateManager: AppUpdateManager
    @State private var localizationPreference: LocalizationPreference
    @State private var selectedSection: AppSection = .clip
    @State private var hasConfiguredRuntime = false

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
        self._launchAtLoginPreference = State(initialValue: LaunchAtLoginPreference())
        self._onboardingPreference = State(initialValue: FirstLaunchOnboardingPreference())
        self._updateManager = State(initialValue: AppUpdateManager())
        self._localizationPreference = State(initialValue: LocalizationPreference())
    }

    var body: some Scene {
        WindowGroup(mainWindowTitle, id: "main") {
            AppShellView(
                clipboardMonitor: clipboardMonitor,
                screenshotController: screenshotController,
                translationController: translationController,
                shortcutController: shortcutController,
                localizationPreference: localizationPreference,
                openSettingsAction: openSettingsWindow,
                selectedSection: $selectedSection
            )
                .id(localizationPreference.version)
                .frame(minWidth: 760, minHeight: 520)
                .onAppear {
                    AppDockIconController.shared.updateActivationPolicy()
                }
                .onChange(of: localizationPreference.version) {
                    translationController.refreshLocalizedMessages()
                }
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 1040, height: 680)
        .onChange(of: scenePhase, initial: true) {
            configureAppRuntime()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(L10n.appSettings) {
                    openSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    private func configureAppRuntime() {
        shortcutController.openMainWindow = openMainWindow
        shortcutController.openSection = { section in
            selectedSection = section
            openMainWindow()
        }
        screenshotController.recordingDidFinish = {
            selectedSection = .pix
            openMainWindow()
        }
        AppStatusMenuController.shared.configure(
            clipboardMonitor: clipboardMonitor,
            screenshotController: screenshotController,
            translationController: translationController,
            shortcutController: shortcutController,
            openMainWindowAction: openMainWindow,
            openSettingsAction: openSettingsWindow,
            openOnboardingAction: openOnboardingWindow
        )

        guard !hasConfiguredRuntime else {
            return
        }

        hasConfiguredRuntime = true
        AppDockIconController.shared.configure(preference: dockIconPreference)
        clipboardMonitor.start()
        shortcutController.start()
        FirstLaunchOnboardingPresenter.shared.configure(preference: onboardingPreference)
        DispatchQueue.main.async {
            FirstLaunchOnboardingPresenter.shared.showIfNeeded()
        }
    }

    private func openMainWindow() {
        if !AppWindowPresenter.bringMainWindowForward() {
            openWindow(id: "main")
            DispatchQueue.main.async {
                AppWindowPresenter.bringMainWindowForward()
            }
        }
    }

    private func openSettingsWindow() {
        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.regular)
            AppSettingsWindowController.shared.show(content: AnyView(appSettingsView))

            DispatchQueue.main.async {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
    }

    private func openOnboardingWindow() {
        DispatchQueue.main.async {
            FirstLaunchOnboardingPresenter.shared.configure(preference: onboardingPreference)
            FirstLaunchOnboardingPresenter.shared.show()
        }
    }

    private var appSettingsView: some View {
        AppSettingsView(
            clipboardHistory: clipboardMonitor.history,
            screenshotHistory: screenshotController.history,
            translationController: translationController,
            dockIconPreference: dockIconPreference,
            launchAtLoginPreference: launchAtLoginPreference,
            localizationPreference: localizationPreference,
            updateManager: updateManager,
            openOnboardingAction: openOnboardingWindow
        )
        .id(localizationPreference.version)
        .onChange(of: localizationPreference.version) {
            AppSettingsWindowController.shared.updateTitle()
            translationController.refreshLocalizedMessages()
        }
        .onDisappear {
            AppDockIconController.shared.updateActivationPolicy()
        }
    }

    private var mainWindowTitle: String {
        #if DEBUG
        L10n.appDebugBuildTitle
        #else
        L10n.appName
        #endif
    }
}

@MainActor
private final class FirstLaunchOnboardingPresenter {
    static let shared = FirstLaunchOnboardingPresenter()

    private var controller: FirstLaunchOnboardingWindowController?

    func configure(preference: FirstLaunchOnboardingPreference) {
        guard controller == nil else {
            return
        }

        controller = FirstLaunchOnboardingWindowController(preference: preference)
    }

    func showIfNeeded() {
        controller?.showIfNeeded()
    }

    func show() {
        controller?.show()
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

@MainActor
private final class AppSettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = AppSettingsWindowController()

    func show(content: AnyView) {
        if let hostingController = window?.contentViewController as? NSHostingController<AnyView> {
            hostingController.rootView = content
        } else {
            window = makeWindow(content: content)
        }

        updateTitle()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func updateTitle() {
        window?.title = L10n.appSettings
    }

    private func makeWindow(content: AnyView) -> NSWindow {
        let hostingController = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hostingController)
        window.title = L10n.appSettings
        window.identifier = NSUserInterfaceItemIdentifier("ClipPixTran.SettingsWindow")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(
            NSSize(
                width: ControlPanelDesign.Layout.Settings.windowWidth,
                height: ControlPanelDesign.Layout.Settings.windowHeight
            )
        )
        return window
    }

    func windowWillClose(_ notification: Notification) {
        AppDockIconController.shared.updateActivationPolicy()
    }
}
