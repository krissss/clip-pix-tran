import Foundation
import ServiceManagement
import Testing
@testable import ClipPixTran

@MainActor
struct LaunchAtLoginPreferenceTests {
    @Test func treatsMissingRegistrationAsDisabled() {
        #expect(
            SystemLaunchAtLoginService.registrationStatus(for: .notFound) == .disabled
        )
    }

    @Test func reflectsEnabledStatus() {
        let preference = LaunchAtLoginPreference(
            service: FakeLaunchAtLoginService(status: .enabled)
        )

        #expect(preference.launchesAtLogin)
        #expect(preference.status == .enabled)
        #expect(!preference.isToggleDisabled)
    }

    @Test func keepsToggleOnWhenApprovalIsRequired() {
        let preference = LaunchAtLoginPreference(
            service: FakeLaunchAtLoginService(status: .requiresApproval)
        )

        #expect(preference.launchesAtLogin)
        #expect(preference.statusMessage == L10n.launchAtLoginRequiresApprovalMessage)
    }

    @Test func registersLaunchAtLogin() {
        let service = FakeLaunchAtLoginService(status: .disabled)
        let preference = LaunchAtLoginPreference(service: service)

        preference.setLaunchesAtLogin(true)

        #expect(service.registerCallCount == 1)
        #expect(preference.launchesAtLogin)
        #expect(preference.status == .enabled)
    }

    @Test func unregistersLaunchAtLogin() {
        let service = FakeLaunchAtLoginService(status: .enabled)
        let preference = LaunchAtLoginPreference(service: service)

        preference.setLaunchesAtLogin(false)

        #expect(service.unregisterCallCount == 1)
        #expect(!preference.launchesAtLogin)
        #expect(preference.status == .disabled)
    }

    @Test func reportsRegistrationErrors() {
        let service = FakeLaunchAtLoginService(status: .disabled)
        service.registerError = NSError(
            domain: "LaunchAtLoginPreferenceTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "registration denied"]
        )
        let preference = LaunchAtLoginPreference(service: service)

        preference.setLaunchesAtLogin(true)

        #expect(!preference.launchesAtLogin)
        #expect(preference.statusMessage.contains("registration denied"))
    }
}

private final class FakeLaunchAtLoginService: LaunchAtLoginServicing {
    var status: LaunchAtLoginRegistrationStatus
    var registerCallCount = 0
    var unregisterCallCount = 0
    var registerError: Error?
    var unregisterError: Error?

    init(status: LaunchAtLoginRegistrationStatus) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        if let registerError {
            throw registerError
        }

        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError {
            throw unregisterError
        }

        status = .disabled
    }
}
