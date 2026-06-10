import AppKit
import Combine
import Foundation
import Observation
import Sparkle

@MainActor
@Observable
final class AppUpdateManager: NSObject, SPUUpdaterDelegate {
    var canCheckForUpdates = false
    var lastUpdateCheckDate: Date?
    var automaticallyChecksForUpdates = false
    var automaticallyDownloadsUpdates = false
    var updateCheckInterval: TimeInterval = UpdateCheckInterval.weekly.seconds

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var updaterStarted = false
    @ObservationIgnored private static let isRunningTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        ProcessInfo.processInfo.processName == "xctest"
    @ObservationIgnored private static let runsDebugBuild =
        isDebugBuildChannel(Bundle.main.object(forInfoDictionaryKey: "ClipPixTranBuildChannel") as? String)
    @ObservationIgnored private static let sparkleConfigurationIsValid: Bool = {
        guard let bundleID = Bundle.main.bundleIdentifier,
              !bundleID.isEmpty,
              let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              !feedURL.isEmpty,
              !feedURL.contains("$("),
              let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !publicKey.isEmpty,
              !publicKey.contains("$(") else {
            return false
        }

        return true
    }()
    @ObservationIgnored private static let canUseSparkleUpdater =
        !isRunningTests && !runsDebugBuild && sparkleConfigurationIsValid

    @ObservationIgnored private lazy var userDriver = SparkleUpdateUserDriver()
    @ObservationIgnored private(set) lazy var updater = SPUUpdater(
        hostBundle: Bundle.main,
        applicationBundle: Bundle.main,
        userDriver: userDriver,
        delegate: self
    )

    var updateCheckingIsAvailable: Bool {
        Self.canUseSparkleUpdater
    }

    var statusMessage: String {
        if Self.runsDebugBuild {
            return "Debug 构建不会检查更新；请使用 Release 构建测试 Sparkle 更新。"
        }

        if Self.sparkleConfigurationIsValid {
            return "自动更新通过 GitHub Release 和 Sparkle appcast 提供。"
        }

        return "当前构建未配置 Sparkle appcast 或公钥。"
    }

    override init() {
        super.init()
        guard Self.canUseSparkleUpdater else {
            canCheckForUpdates = !Self.isRunningTests && !Self.runsDebugBuild
            return
        }

        _ = updater
        configureCancellables()
        startUpdaterIfNeeded()
        if updater.automaticallyChecksForUpdates {
            updater.checkForUpdatesInBackground()
        }
        syncFromSparkle()
    }

    func checkForUpdates() {
        guard !Self.isRunningTests, !Self.runsDebugBuild else {
            return
        }

        guard Self.sparkleConfigurationIsValid else {
            let alert = NSAlert()
            alert.messageText = "自动更新未配置"
            alert.informativeText = "Release 构建需要在发布流程中使用 SPARKLE_PRIVATE_KEY 签名更新包。"
            alert.runModal()
            return
        }

        startUpdaterIfNeeded()
        updater.checkForUpdates()
    }

    func setAutomaticallyChecksForUpdates(_ newValue: Bool) {
        guard Self.canUseSparkleUpdater else {
            return
        }

        automaticallyChecksForUpdates = newValue
        startUpdaterIfNeeded()
        updater.automaticallyChecksForUpdates = newValue
    }

    func setAutomaticallyDownloadsUpdates(_ newValue: Bool) {
        guard Self.canUseSparkleUpdater else {
            return
        }

        automaticallyDownloadsUpdates = newValue
        startUpdaterIfNeeded()
        updater.automaticallyDownloadsUpdates = newValue
    }

    func setUpdateCheckInterval(_ interval: UpdateCheckInterval) {
        guard Self.canUseSparkleUpdater else {
            return
        }

        updateCheckInterval = interval.seconds
        startUpdaterIfNeeded()
        updater.updateCheckInterval = interval.seconds
    }

    nonisolated static func isDebugBuildChannel(_ buildChannel: String?) -> Bool {
        buildChannel?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("Debug") == .orderedSame
    }

    private func configureCancellables() {
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.canCheckForUpdates = value }
            .store(in: &cancellables)

        updater.publisher(for: \.lastUpdateCheckDate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.lastUpdateCheckDate = value }
            .store(in: &cancellables)

        updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.automaticallyChecksForUpdates = value }
            .store(in: &cancellables)

        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.automaticallyDownloadsUpdates = value }
            .store(in: &cancellables)

        updater.publisher(for: \.updateCheckInterval)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.updateCheckInterval = value }
            .store(in: &cancellables)
    }

    private func startUpdaterIfNeeded() {
        guard !updaterStarted else {
            return
        }

        do {
            try updater.start()
            updaterStarted = true
        } catch {
            print("[Sparkle] failed to start updater: \(error)")
        }
    }

    private func syncFromSparkle() {
        canCheckForUpdates = updater.canCheckForUpdates
        lastUpdateCheckDate = updater.lastUpdateCheckDate
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        updateCheckInterval = updater.updateCheckInterval
    }

    nonisolated func updaterShouldPromptForPermissionToCheck(forUpdates _: SPUUpdater) -> Bool {
        false
    }

    nonisolated func updater(_: SPUUpdater, didFindValidUpdate _: SUAppcastItem) {
        DispatchQueue.main.async {
            NSApp.activate()
        }
    }

    nonisolated func updater(_: SPUUpdater, didAbortWithError error: Error) {
        print("[Sparkle] didAbortWithError: \(error)")
    }

    nonisolated var supportsGentleScheduledUpdateReminders: Bool {
        false
    }
}

enum UpdateCheckInterval: String, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly

    var id: Self { self }

    var displayName: String {
        switch self {
        case .daily:
            "每天"
        case .weekly:
            "每周"
        case .monthly:
            "每月"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .daily:
            86_400
        case .weekly:
            604_800
        case .monthly:
            2_592_000
        }
    }

    static func from(seconds: TimeInterval) -> UpdateCheckInterval {
        if seconds <= daily.seconds {
            return .daily
        }

        if seconds <= weekly.seconds {
            return .weekly
        }

        return .monthly
    }
}
