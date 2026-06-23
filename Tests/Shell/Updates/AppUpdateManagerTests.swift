import Testing
import Foundation
@testable import ClipPixTran

@Suite("AppUpdateManager")
struct AppUpdateManagerTests {
    @Test("isDebugBuildChannel treats Debug channel as update-disabled")
    func isDebugBuildChannelDetectsDebugChannel() {
        #expect(AppUpdateManager.isDebugBuildChannel("Debug"))
        #expect(AppUpdateManager.isDebugBuildChannel(" debug "))
        #expect(AppUpdateManager.isDebugBuildChannel("DEBUG"))
        #expect(!AppUpdateManager.isDebugBuildChannel("Release"))
        #expect(!AppUpdateManager.isDebugBuildChannel(nil))
    }

    @Test("delayUntilUpdateCheckIsDue is immediately due without a previous check")
    func delayUntilUpdateCheckIsDueWithoutPreviousCheck() {
        #expect(AppUpdateManager.delayUntilUpdateCheckIsDue(
            lastUpdateCheckDate: nil,
            updateCheckInterval: UpdateCheckInterval.daily.seconds
        ) == 0)
    }

    @Test("delayUntilUpdateCheckIsDue returns zero after the interval has elapsed")
    func delayUntilUpdateCheckIsDueAfterIntervalElapsed() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let lastCheck = now.addingTimeInterval(-UpdateCheckInterval.daily.seconds - 1)

        #expect(AppUpdateManager.delayUntilUpdateCheckIsDue(
            lastUpdateCheckDate: lastCheck,
            updateCheckInterval: UpdateCheckInterval.daily.seconds,
            now: now
        ) == 0)
    }

    @Test("delayUntilUpdateCheckIsDue returns remaining interval before the check is due")
    func delayUntilUpdateCheckIsDueBeforeIntervalElapsed() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let lastCheck = now.addingTimeInterval(-3_600)

        #expect(AppUpdateManager.delayUntilUpdateCheckIsDue(
            lastUpdateCheckDate: lastCheck,
            updateCheckInterval: UpdateCheckInterval.daily.seconds,
            now: now
        ) == UpdateCheckInterval.daily.seconds - 3_600)
    }

    @Test("delayUntilUpdateCheckIsDue ignores disabled intervals")
    func delayUntilUpdateCheckIsDueWithDisabledInterval() {
        #expect(AppUpdateManager.delayUntilUpdateCheckIsDue(
            lastUpdateCheckDate: nil,
            updateCheckInterval: 0
        ).isInfinite)
    }
}
