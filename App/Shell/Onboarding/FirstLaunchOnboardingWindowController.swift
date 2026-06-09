import AppKit
import SwiftUI

@MainActor
final class FirstLaunchOnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let preference: FirstLaunchOnboardingPreference
    private let permissionService: OnboardingPermissionStatusProviding
    private var didCompleteFromView = false

    convenience init(preference: FirstLaunchOnboardingPreference) {
        self.init(
            preference: preference,
            permissionService: SystemOnboardingPermissionService()
        )
    }

    init(
        preference: FirstLaunchOnboardingPreference,
        permissionService: OnboardingPermissionStatusProviding
    ) {
        self.preference = preference
        self.permissionService = permissionService
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func showIfNeeded() {
        guard !preference.hasCompleted else {
            return
        }

        show()
    }

    func show() {
        didCompleteFromView = false
        if window == nil {
            window = makeWindow()
        } else {
            updateRootView()
        }

        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: makeHostingController())
        window.title = "ClipPixTran 准备使用"
        window.identifier = NSUserInterfaceItemIdentifier("ClipPixTran.FirstLaunchOnboardingWindow")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 720, height: 460))
        return window
    }

    private func makeHostingController() -> NSHostingController<AnyView> {
        NSHostingController(rootView: AnyView(onboardingView))
    }

    private func updateRootView() {
        if let hostingController = window?.contentViewController as? NSHostingController<AnyView> {
            hostingController.rootView = AnyView(onboardingView)
        }
    }

    private var onboardingView: some View {
        FirstLaunchOnboardingView(
            permissionService: permissionService,
            completeAction: { [weak self] in
                self?.completeAndClose()
            },
            skipAction: { [weak self] in
                self?.completeAndClose()
            }
        )
    }

    private func completeAndClose() {
        didCompleteFromView = true
        preference.markCompleted()
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        if !didCompleteFromView {
            preference.markCompleted()
        }
    }
}
