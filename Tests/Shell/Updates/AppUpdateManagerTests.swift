import Testing
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
}
