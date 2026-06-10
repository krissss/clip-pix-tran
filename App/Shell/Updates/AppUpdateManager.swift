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
    @ObservationIgnored private static let sparkleIsConfigured: Bool = {
        guard !isRunningTests,
              let bundleID = Bundle.main.bundleIdentifier,
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

    @ObservationIgnored private lazy var userDriver = SparkleUpdateUserDriver()
    @ObservationIgnored private(set) lazy var updater = SPUUpdater(
        hostBundle: Bundle.main,
        applicationBundle: Bundle.main,
        userDriver: userDriver,
        delegate: self
    )

    var isConfigured: Bool {
        Self.sparkleIsConfigured
    }

    override init() {
        super.init()
        guard Self.sparkleIsConfigured else {
            canCheckForUpdates = !Self.isRunningTests
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
        guard Self.sparkleIsConfigured else {
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
        automaticallyChecksForUpdates = newValue
        guard Self.sparkleIsConfigured else {
            return
        }

        startUpdaterIfNeeded()
        updater.automaticallyChecksForUpdates = newValue
    }

    func setAutomaticallyDownloadsUpdates(_ newValue: Bool) {
        automaticallyDownloadsUpdates = newValue
        guard Self.sparkleIsConfigured else {
            return
        }

        startUpdaterIfNeeded()
        updater.automaticallyDownloadsUpdates = newValue
    }

    func setUpdateCheckInterval(_ interval: UpdateCheckInterval) {
        updateCheckInterval = interval.seconds
        guard Self.sparkleIsConfigured else {
            return
        }

        startUpdaterIfNeeded()
        updater.updateCheckInterval = interval.seconds
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
