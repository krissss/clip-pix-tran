import Foundation
import Observation
import ServiceManagement

enum LaunchAtLoginRegistrationStatus: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

protocol LaunchAtLoginServicing {
    var status: LaunchAtLoginRegistrationStatus { get }
    func register() throws
    func unregister() throws
}

struct SystemLaunchAtLoginService: LaunchAtLoginServicing {
    var status: LaunchAtLoginRegistrationStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered:
            .disabled
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .unavailable
        @unknown default:
            .unavailable
        }
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

@MainActor
@Observable
final class LaunchAtLoginPreference {
    private let service: any LaunchAtLoginServicing
    private(set) var status: LaunchAtLoginRegistrationStatus
    private(set) var launchesAtLogin: Bool
    private var errorMessage: String?

    convenience init() {
        self.init(service: SystemLaunchAtLoginService())
    }

    init(service: any LaunchAtLoginServicing) {
        self.service = service
        let status = service.status
        self.status = status
        self.launchesAtLogin = Self.launchesAtLogin(for: status)
    }

    var isToggleDisabled: Bool {
        status == .unavailable
    }

    var statusMessage: String {
        if let errorMessage {
            return errorMessage
        }

        switch status {
        case .disabled:
            return L10n.launchAtLoginDisabledMessage
        case .enabled:
            return L10n.launchAtLoginEnabledMessage
        case .requiresApproval:
            return L10n.launchAtLoginRequiresApprovalMessage
        case .unavailable:
            return L10n.launchAtLoginUnavailableMessage
        }
    }

    func refresh() {
        errorMessage = nil
        updateState(from: service.status)
    }

    func setLaunchesAtLogin(_ newValue: Bool) {
        do {
            if newValue {
                try service.register()
            } else {
                try service.unregister()
            }

            errorMessage = nil
            updateState(from: service.status)
        } catch {
            updateState(from: service.status)
            errorMessage = L10n.launchAtLoginUpdateFailed(error.localizedDescription)
        }
    }

    private func updateState(from status: LaunchAtLoginRegistrationStatus) {
        self.status = status
        launchesAtLogin = Self.launchesAtLogin(for: status)
    }

    private static func launchesAtLogin(for status: LaunchAtLoginRegistrationStatus) -> Bool {
        status == .enabled || status == .requiresApproval
    }
}
