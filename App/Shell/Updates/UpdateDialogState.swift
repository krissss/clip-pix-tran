import Foundation

@MainActor
@Observable
final class UpdateDialogState {
    enum Phase: Equatable {
        case checking
        case updateFound
        case downloading(progress: Double?)
        case extracting(progress: Double?)
        case readyToInstall
        case installing
        case installed
        case notFound
        case error
    }

    var phase: Phase = .checking
    var currentVersion = ""
    var latestVersion = ""
    var changelogEntries: [UpdateChangelogEntry] = []
    var fallbackNotes: String?
    var message: String?

    var expectedDownloadBytes: UInt64 = 0
    var receivedDownloadBytes: UInt64 = 0

    var installAction: (() -> Void)?
    var dismissAction: (() -> Void)?
    var skipAction: (() -> Void)?
    var cancelAction: (() -> Void)?
    var acknowledgeAction: (() -> Void)?

    var progressFraction: Double? {
        switch phase {
        case let .downloading(progress), let .extracting(progress):
            progress
        default:
            nil
        }
    }

    var isTerminal: Bool {
        switch phase {
        case .notFound, .error, .installed:
            true
        default:
            false
        }
    }

    func resetActions() {
        installAction = nil
        dismissAction = nil
        skipAction = nil
        cancelAction = nil
        acknowledgeAction = nil
    }
}
