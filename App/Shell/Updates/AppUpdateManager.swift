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
    @ObservationIgnored private var updateCheckWakeUpTimer: Timer?
    @ObservationIgnored private static let updateCheckWakeUpGraceInterval: TimeInterval = 60
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
            return L10n.updateUnavailableDebugBuild
        }

        if Self.sparkleConfigurationIsValid {
            return L10n.updateAvailableStatus
        }

        return L10n.updateUnavailableConfiguration
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
        syncFromSparkle()
        scheduleUpdateCheckWakeUp()
    }

    func checkForUpdates() {
        guard !Self.isRunningTests, !Self.runsDebugBuild else {
            return
        }

        guard Self.sparkleConfigurationIsValid else {
            let alert = NSAlert()
            alert.messageText = L10n.updateUnavailableAlertTitle
            alert.informativeText = L10n.updateUnavailableAlertMessage
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
        scheduleUpdateCheckWakeUp()
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
        scheduleUpdateCheckWakeUp()
    }

    nonisolated static func isDebugBuildChannel(_ buildChannel: String?) -> Bool {
        buildChannel?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("Debug") == .orderedSame
    }

    nonisolated static func delayUntilUpdateCheckIsDue(
        lastUpdateCheckDate: Date?,
        updateCheckInterval: TimeInterval,
        now: Date = Date()
    ) -> TimeInterval {
        guard updateCheckInterval > 0 else {
            return .infinity
        }

        guard let lastUpdateCheckDate else {
            return 0
        }

        let elapsed = max(0, now.timeIntervalSince(lastUpdateCheckDate))
        return max(0, updateCheckInterval - elapsed)
    }

    private func configureCancellables() {
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.canCheckForUpdates = value }
            .store(in: &cancellables)

        updater.publisher(for: \.lastUpdateCheckDate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.lastUpdateCheckDate = value
                self?.scheduleUpdateCheckWakeUp()
            }
            .store(in: &cancellables)

        updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.automaticallyChecksForUpdates = value
                self?.scheduleUpdateCheckWakeUp()
            }
            .store(in: &cancellables)

        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.automaticallyDownloadsUpdates = value }
            .store(in: &cancellables)

        updater.publisher(for: \.updateCheckInterval)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.updateCheckInterval = value
                self?.scheduleUpdateCheckWakeUp()
            }
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

    private func scheduleUpdateCheckWakeUp() {
        updateCheckWakeUpTimer?.invalidate()
        updateCheckWakeUpTimer = nil

        guard updaterStarted,
              updater.automaticallyChecksForUpdates else {
            return
        }

        let delayUntilDue = Self.delayUntilUpdateCheckIsDue(
            lastUpdateCheckDate: updater.lastUpdateCheckDate,
            updateCheckInterval: updater.updateCheckInterval
        )
        guard delayUntilDue.isFinite else {
            return
        }

        let wakeUpDelay = max(
            Self.updateCheckWakeUpGraceInterval,
            delayUntilDue + Self.updateCheckWakeUpGraceInterval
        )
        let timer = Timer(timeInterval: wakeUpDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.wakeUpOverdueUpdateCheck()
            }
        }

        updateCheckWakeUpTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func wakeUpOverdueUpdateCheck() {
        updateCheckWakeUpTimer?.invalidate()
        updateCheckWakeUpTimer = nil
        syncFromSparkle()

        guard updaterStarted,
              updater.automaticallyChecksForUpdates else {
            return
        }

        guard !updater.sessionInProgress else {
            scheduleUpdateCheckWakeUp()
            return
        }

        let delayUntilDue = Self.delayUntilUpdateCheckIsDue(
            lastUpdateCheckDate: updater.lastUpdateCheckDate,
            updateCheckInterval: updater.updateCheckInterval
        )

        if delayUntilDue > 0 {
            scheduleUpdateCheckWakeUp()
        } else {
            updater.resetUpdateCycle()
        }
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
            L10n.updateFrequencyDaily
        case .weekly:
            L10n.updateFrequencyWeekly
        case .monthly:
            L10n.updateFrequencyMonthly
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
