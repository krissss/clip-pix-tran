import Testing
@testable import ClipPixTran

@MainActor
struct OnboardingStepTests {
    @Test func stepsAreInExpectedOrder() {
        #expect(OnboardingStep.allCases == [
            .screenRecording,
            .accessibility,
            .shortcuts
        ])
    }

    @Test func previousAndNextFollowStepOrder() {
        #expect(OnboardingStep.screenRecording.previous == nil)
        #expect(OnboardingStep.screenRecording.next == .accessibility)
        #expect(OnboardingStep.accessibility.previous == .screenRecording)
        #expect(OnboardingStep.accessibility.next == .shortcuts)
        #expect(OnboardingStep.shortcuts.previous == .accessibility)
        #expect(OnboardingStep.shortcuts.next == nil)
    }
}
