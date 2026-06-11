import Testing
@testable import ClipPixTran

@MainActor
struct FirstLaunchOnboardingViewTests {
    @Test func screenRecordingFallbackMessageMentionsOpenedSettings() {
        let message = FirstLaunchOnboardingView.screenRecordingRequestFallbackMessage(
            didOpenSettings: true
        )

        #expect(message == .warning(L10n.onboardingScreenRecordingPromptFallbackOpenedSettings))
    }

    @Test func screenRecordingFallbackMessageMentionsManualSettingsWhenOpenFails() {
        let message = FirstLaunchOnboardingView.screenRecordingRequestFallbackMessage(
            didOpenSettings: false
        )

        #expect(message == .warning(L10n.onboardingScreenRecordingPromptFallbackManual))
    }
}
