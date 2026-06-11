import AppKit
import Sparkle
import SwiftUI

@MainActor
final class SparkleUpdateUserDriver: NSObject, SPUUserDriver, NSWindowDelegate {
    private static let windowContentSize = NSSize(width: 560, height: 520)

    private let changelogURL: URL
    private let currentVersionProvider: () -> String
    private var state = UpdateDialogState()
    private var windowController: NSWindowController?
    private var changelogTask: Task<Void, Never>?
    private var isClosingProgrammatically = false

    init(
        changelogURL: URL = UpdateChangelog.defaultRemoteURL,
        currentVersionProvider: @escaping () -> String = {
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        }
    ) {
        self.changelogURL = changelogURL
        self.currentVersionProvider = currentVersionProvider
        super.init()
    }

    func show(
        _ updatePermissionRequest: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        reply(SUUpdatePermissionResponse(
            automaticUpdateChecks: true,
            sendSystemProfile: false
        ))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        state.resetActions()
        state.phase = .checking
        state.currentVersion = currentVersionProvider()
        state.latestVersion = ""
        state.changelogEntries = []
        state.fallbackNotes = nil
        state.message = nil
        state.cancelAction = { [weak self] in
            self?.state.resetActions()
            cancellation()
            self?.closeWindow()
        }
        showWindow()
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state updateState: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        state.resetActions()
        state.phase = .updateFound
        state.currentVersion = currentVersionProvider()
        state.latestVersion = appcastItem.displayVersionString
        state.changelogEntries = []
        state.fallbackNotes = Self.plainText(fromHTML: appcastItem.itemDescription)
        state.message = message(for: updateState)

        if appcastItem.isInformationOnlyUpdate {
            state.installAction = nil
        } else {
            state.installAction = { [weak self] in
                self?.state.resetActions()
                reply(.install)
            }
        }

        state.dismissAction = { [weak self] in
            self?.state.resetActions()
            reply(.dismiss)
            self?.closeWindow()
        }
        state.skipAction = { [weak self] in
            self?.state.resetActions()
            reply(.skip)
            self?.closeWindow()
        }

        showWindow()
        loadChangelog(for: appcastItem)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        guard state.changelogEntries.isEmpty,
              let notes = String(data: downloadData.data, encoding: .utf8)
        else {
            return
        }

        state.fallbackNotes = Self.plainText(fromHTML: notes)
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        guard state.fallbackNotes == nil else {
            return
        }

        state.fallbackNotes = error.localizedDescription
    }

    func showUpdateNotFoundWithError(
        _ error: Error,
        acknowledgement: @escaping () -> Void
    ) {
        state.resetActions()
        state.phase = .notFound
        state.currentVersion = currentVersionProvider()
        state.latestVersion = ""
        state.changelogEntries = []
        state.fallbackNotes = nil
        state.message = error.localizedDescription
        state.acknowledgeAction = { [weak self] in
            self?.state.resetActions()
            acknowledgement()
            self?.closeWindow()
        }
        showWindow()
    }

    func showUpdaterError(
        _ error: Error,
        acknowledgement: @escaping () -> Void
    ) {
        state.resetActions()
        state.phase = .error
        state.message = error.localizedDescription
        state.acknowledgeAction = { [weak self] in
            self?.state.resetActions()
            acknowledgement()
            self?.closeWindow()
        }
        showWindow()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        state.phase = .downloading(progress: nil)
        state.expectedDownloadBytes = 0
        state.receivedDownloadBytes = 0
        state.cancelAction = { [weak self] in
            self?.state.resetActions()
            cancellation()
            self?.closeWindow()
        }
        showWindow()
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        state.expectedDownloadBytes = expectedContentLength
        state.receivedDownloadBytes = 0
        state.phase = .downloading(progress: expectedContentLength > 0 ? 0 : nil)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        state.receivedDownloadBytes += length
        if state.expectedDownloadBytes > 0 {
            state.phase = .downloading(
                progress: Double(state.receivedDownloadBytes) / Double(state.expectedDownloadBytes)
            )
        } else {
            state.phase = .downloading(progress: nil)
        }
    }

    func showDownloadDidStartExtractingUpdate() {
        state.phase = .extracting(progress: nil)
        state.cancelAction = nil
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        state.phase = .extracting(progress: progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        state.resetActions()
        state.phase = .readyToInstall
        state.installAction = { [weak self] in
            self?.state.resetActions()
            reply(.install)
        }
        state.dismissAction = { [weak self] in
            self?.state.resetActions()
            reply(.dismiss)
            self?.closeWindow()
        }
        showWindow()
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        state.phase = .installing
        state.resetActions()
        showWindow()
    }

    func showUpdateInstalledAndRelaunched(
        _ relaunched: Bool,
        acknowledgement: @escaping () -> Void
    ) {
        state.resetActions()
        state.phase = .installed
        state.message = relaunched ? nil : L10n.updateInstalledMessage
        state.acknowledgeAction = { [weak self] in
            self?.state.resetActions()
            acknowledgement()
            self?.closeWindow()
        }
        showWindow()
    }

    func dismissUpdateInstallation() {
        closeWindow()
    }

    func showUpdateInFocus() {
        showWindow()
    }

    func windowWillClose(_ notification: Notification) {
        guard !isClosingProgrammatically else {
            return
        }

        changelogTask?.cancel()
        changelogTask = nil

        let dismissAction = state.dismissAction
        let cancelAction = state.cancelAction
        let acknowledgeAction = state.acknowledgeAction
        state.resetActions()
        windowController = nil

        if let dismissAction {
            dismissAction()
        } else if let cancelAction {
            cancelAction()
        } else if let acknowledgeAction {
            acknowledgeAction()
        }
    }

    private func showWindow() {
        let controller: NSWindowController
        let shouldCenterWindow: Bool

        if let windowController {
            controller = windowController
            controller.window?.title = L10n.updateWindowTitle
            shouldCenterWindow = false
        } else {
            let hostingController = NSHostingController(rootView: UpdateDialogView(state: state))
            let window = NSWindow(contentViewController: hostingController)
            window.title = L10n.updateWindowTitle
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(Self.windowContentSize)
            window.isReleasedWhenClosed = false
            window.delegate = self
            controller = NSWindowController(window: window)
            windowController = controller
            shouldCenterWindow = true
        }

        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        if shouldCenterWindow, let window = controller.window {
            window.contentView?.layoutSubtreeIfNeeded()
            centerWindow(window)
        }
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private func centerWindow(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else {
            window.center()
            return
        }

        let screenFrame = screen.visibleFrame
        let windowFrame = window.frame
        window.setFrameOrigin(NSPoint(
            x: screenFrame.midX - windowFrame.width / 2,
            y: screenFrame.midY - windowFrame.height / 2
        ))
    }

    private func closeWindow() {
        changelogTask?.cancel()
        changelogTask = nil
        isClosingProgrammatically = true
        windowController?.close()
        isClosingProgrammatically = false
        windowController = nil
    }

    private func loadChangelog(for appcastItem: SUAppcastItem) {
        changelogTask?.cancel()

        let currentVersion = state.currentVersion
        let latestVersion = appcastItem.displayVersionString
        let url = appcastItem.fullReleaseNotesURL ?? changelogURL

        changelogTask = Task { [weak self] in
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled else {
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode)
                else {
                    return
                }
                guard let markdown = String(data: data, encoding: .utf8) else {
                    return
                }

                let entries = UpdateChangelog.entries(
                    in: markdown,
                    from: currentVersion,
                    through: latestVersion
                )
                guard !Task.isCancelled else {
                    return
                }

                self?.state.changelogEntries = entries
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                if self?.state.fallbackNotes == nil {
                    self?.state.fallbackNotes = error.localizedDescription
                }
            }
        }
    }

    private func message(for updateState: SPUUserUpdateState) -> String? {
        switch updateState.stage {
        case .downloaded:
            return L10n.updateDownloadedMessage
        case .installing:
            return L10n.updateInstallingProgress
        default:
            return nil
        }
    }

    private static func plainText(fromHTML text: String?) -> String? {
        guard let text, !text.isEmpty else {
            return nil
        }

        let replacements: [(String, String)] = [
            ("<br>", "\n"),
            ("<br/>", "\n"),
            ("<br />", "\n"),
            ("</p>", "\n"),
            ("</li>", "\n"),
            ("<li>", "- "),
            ("</ul>", "\n"),
            ("</b>", "\n")
        ]
        var result = text
        for (target, replacement) in replacements {
            result = result.replacingOccurrences(
                of: target,
                with: replacement,
                options: .caseInsensitive
            )
        }
        result = result.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        return result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
