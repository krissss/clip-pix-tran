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
            return "关闭后，ClipPixTran 不会随系统登录自动启动。"
        case .enabled:
            return "已开启，系统登录后会自动启动 ClipPixTran。"
        case .requiresApproval:
            return "已请求开机启动，请在系统设置的登录项中允许 ClipPixTran。"
        case .unavailable:
            return "当前构建无法注册为登录项。"
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
            errorMessage = "无法更新开机启动设置：\(error.localizedDescription)"
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
