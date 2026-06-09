import AppKit
import ApplicationServices
import Foundation

enum OnboardingPermissionStatus: Equatable {
    case authorized
    case notAuthorized
}

protocol OnboardingPermissionStatusProviding {
    func screenRecordingStatus() -> OnboardingPermissionStatus
    func accessibilityStatus() -> OnboardingPermissionStatus
    func requestScreenRecordingAccess() async -> OnboardingPermissionStatus
    func openScreenRecordingSettings() -> Bool
    func openAccessibilitySettings() -> Bool
}

struct SystemOnboardingPermissionService: OnboardingPermissionStatusProviding {
    var preflightScreenRecordingAccess: @Sendable () -> Bool = {
        CGPreflightScreenCaptureAccess()
    }
    var requestScreenRecordingAccessHandler: @MainActor @Sendable () -> Bool = {
        CGRequestScreenCaptureAccess()
    }
    var accessibilityTrusted: @Sendable () -> Bool = {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    var openURL: @MainActor @Sendable (URL) -> Bool = { url in
        NSWorkspace.shared.open(url)
    }

    func screenRecordingStatus() -> OnboardingPermissionStatus {
        preflightScreenRecordingAccess() ? .authorized : .notAuthorized
    }

    func accessibilityStatus() -> OnboardingPermissionStatus {
        accessibilityTrusted() ? .authorized : .notAuthorized
    }

    func requestScreenRecordingAccess() async -> OnboardingPermissionStatus {
        if preflightScreenRecordingAccess() {
            return .authorized
        }

        let didGrantAccess = await MainActor.run {
            requestScreenRecordingAccessHandler()
        }
        return didGrantAccess || preflightScreenRecordingAccess() ? .authorized : .notAuthorized
    }

    @MainActor
    func openScreenRecordingSettings() -> Bool {
        openSystemSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    @MainActor
    func openAccessibilitySettings() -> Bool {
        openSystemSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    @MainActor
    private func openSystemSettingsPane(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else {
            return false
        }

        return openURL(url)
    }
}
