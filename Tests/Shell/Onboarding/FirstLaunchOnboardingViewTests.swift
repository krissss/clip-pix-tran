import Testing
@testable import ClipPixTran

@MainActor
struct FirstLaunchOnboardingViewTests {
    @Test func screenRecordingFallbackMessageMentionsOpenedSettings() {
        let message = FirstLaunchOnboardingView.screenRecordingRequestFallbackMessage(
            didOpenSettings: true
        )

        #expect(message == .warning("系统没有弹出授权提示。已为你打开系统设置，请允许 ClipPixTran 录制屏幕后重新检测。"))
    }

    @Test func screenRecordingFallbackMessageMentionsManualSettingsWhenOpenFails() {
        let message = FirstLaunchOnboardingView.screenRecordingRequestFallbackMessage(
            didOpenSettings: false
        )

        #expect(message == .warning("系统没有弹出授权提示。请手动前往隐私与安全性中的屏幕录制，允许 ClipPixTran 后重新检测。"))
    }
}
