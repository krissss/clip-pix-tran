import Foundation
import Testing
@testable import ClipPixTran

@MainActor
struct OnboardingPermissionServiceTests {
    @Test func reportsAuthorizedScreenRecordingStatus() {
        let service = SystemOnboardingPermissionService(
            preflightScreenRecordingAccess: { true }
        )

        #expect(service.screenRecordingStatus() == .authorized)
    }

    @Test func reportsUnauthorizedAccessibilityStatus() {
        let service = SystemOnboardingPermissionService(
            accessibilityTrusted: { false }
        )

        #expect(service.accessibilityStatus() == .notAuthorized)
    }

    @Test func requestScreenRecordingSkipsPromptWhenAlreadyAuthorized() async {
        let service = SystemOnboardingPermissionService(
            preflightScreenRecordingAccess: { true },
            requestScreenRecordingAccessHandler: {
                Issue.record("Already authorized requests should not prompt again.")
                return false
            }
        )

        let status = await service.requestScreenRecordingAccess()

        #expect(status == .authorized)
    }

    @Test func requestScreenRecordingUsesPromptResult() async {
        let service = SystemOnboardingPermissionService(
            preflightScreenRecordingAccess: { false },
            requestScreenRecordingAccessHandler: { true }
        )

        let status = await service.requestScreenRecordingAccess()

        #expect(status == .authorized)
    }

    @Test func opensScreenRecordingSettingsURL() {
        var openedURL: URL?
        let service = SystemOnboardingPermissionService(
            openURL: { url in
                openedURL = url
                return true
            }
        )

        #expect(service.openScreenRecordingSettings())
        #expect(openedURL?.absoluteString.contains("Privacy_ScreenCapture") == true)
    }

    @Test func opensAccessibilitySettingsURL() {
        var openedURL: URL?
        let service = SystemOnboardingPermissionService(
            openURL: { url in
                openedURL = url
                return true
            }
        )

        #expect(service.openAccessibilitySettings())
        #expect(openedURL?.absoluteString.contains("Privacy_Accessibility") == true)
    }
}
