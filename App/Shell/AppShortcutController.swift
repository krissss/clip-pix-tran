import AppKit
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
    private var captureShortcutEventTap: CaptureShortcutEventTap?
    var openSection: ((AppSection) -> Void)?
    var openMainWindow: (() -> Void)?

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
            Task { await observeShowMainWindowShortcut() },
            Task { await observeClipboardQuickPanelShortcut() },
            Task { await observeCaptureSelectedRegionShortcut() },
            Task { await observeTranslateSelectedTextShortcut() }
        ]
        installCaptureShortcutEventTap()
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        captureShortcutEventTap = nil
    }

    func showMainWindow() {
        openMainWindow?()
    }

    func showClipboardQuickPanel() {
        clipboardQuickPanelPresenter.toggle(monitor: clipboardMonitor)
    }

    func captureSelectedRegion() {
        Task {
            await performCaptureSelectedRegion()
        }
    }

    func translateSelectedText() {
        Task {
            await performTranslateSelectedText()
        }
    }

    private func observeShowMainWindowShortcut() async {
        for await event in KeyboardShortcuts.events(for: .showMainWindow) where event == .keyUp {
            showMainWindow()
        }
    }

    private func observeClipboardQuickPanelShortcut() async {
        for await event in KeyboardShortcuts.events(for: .showClipboardQuickPanel) where event == .keyUp {
            showClipboardQuickPanel()
        }
    }

    private func observeCaptureSelectedRegionShortcut() async {
        for await _ in KeyboardShortcuts.events(.keyDown, for: .captureSelectedRegion) {
            await performCaptureSelectedRegion()
        }
    }

    private func installCaptureShortcutEventTap() {
        captureShortcutEventTap = CaptureShortcutEventTap(shortcutName: .captureSelectedRegion) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.performCaptureSelectedRegion()
            }
        }
    }

    private func performCaptureSelectedRegion() async {
        let result = await screenshotController.performPrimaryCapture()
        if result == .needsScreenRecordingPermission {
            openSection?(.pix)
        }
    }

    private func observeTranslateSelectedTextShortcut() async {
        for await event in KeyboardShortcuts.events(for: .translateSelectedText) where event == .keyUp {
            await performTranslateSelectedText()
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
}

private final class CaptureShortcutEventTap {
    private let shortcutName: KeyboardShortcuts.Name
    private let action: @MainActor () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var shortcutChangeObserver: NSObjectProtocol?
    private var handledKeyDown = false

    init(
        shortcutName: KeyboardShortcuts.Name,
        action: @escaping @MainActor () -> Void
    ) {
        self.shortcutName = shortcutName
        self.action = action
        install()
        shortcutChangeObserver = NotificationCenter.default.addObserver(
            forName: Self.shortcutChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  notification.userInfo?["name"] as? KeyboardShortcuts.Name == shortcutName else {
                return
            }

            self.install()
        }
    }

    deinit {
        if let shortcutChangeObserver {
            NotificationCenter.default.removeObserver(shortcutChangeObserver)
        }
        uninstall()
    }

    private func install() {
        uninstall()

        guard KeyboardShortcuts.getShortcut(for: shortcutName) != nil else {
            return
        }

        guard CGPreflightListenEventAccess() else {
            return
        }

        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: Self.handleEvent,
            userInfo: userInfo
        ) else {
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
    }

    private static let shortcutChangedNotification = Notification.Name(
        "KeyboardShortcuts_shortcutByNameDidChange"
    )

    private func uninstall() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        handledKeyDown = false
    }

    private static let handleEvent: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let monitor = Unmanaged<CaptureShortcutEventTap>
            .fromOpaque(userInfo)
            .takeUnretainedValue()

        return monitor.handle(type: type, event: event)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        guard matchesCaptureShortcut(event) else {
            if type == .keyUp {
                handledKeyDown = false
            }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            guard !handledKeyDown else {
                return nil
            }

            handledKeyDown = true
            Task { @MainActor [action] in
                action()
            }
            return nil
        case .keyUp:
            handledKeyDown = false
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func matchesCaptureShortcut(_ event: CGEvent) -> Bool {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: shortcutName),
              event.getIntegerValueField(.keyboardEventKeycode) == shortcut.carbonKeyCode else {
            return false
        }

        return event.flags.normalizedShortcutFlags == shortcut.modifiers.normalizedShortcutFlags
    }
}

private extension CGEventFlags {
    var normalizedShortcutFlags: NSEvent.ModifierFlags {
        var flags = NSEvent.ModifierFlags()
        if contains(.maskControl) {
            flags.insert(.control)
        }
        if contains(.maskAlternate) {
            flags.insert(.option)
        }
        if contains(.maskShift) {
            flags.insert(.shift)
        }
        if contains(.maskCommand) {
            flags.insert(.command)
        }
        return flags
    }
}

private extension NSEvent.ModifierFlags {
    var normalizedShortcutFlags: NSEvent.ModifierFlags {
        intersection([.control, .option, .shift, .command])
    }
}
