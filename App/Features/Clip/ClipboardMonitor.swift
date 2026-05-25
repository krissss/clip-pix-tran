import Foundation

@MainActor
@Observable
final class ClipboardMonitor {
    let history: ClipboardHistoryStore

    private let pasteboard: ClipboardService
    private let pollInterval: TimeInterval
    private var observedChangeCount: Int
    private var pollTask: Task<Void, Never>?

    var lastErrorMessage: String?

    init(
        pasteboard: ClipboardService,
        history: ClipboardHistoryStore? = nil,
        pollInterval: TimeInterval = 0.75
    ) {
        self.pasteboard = pasteboard
        self.history = history ?? ClipboardHistoryStore()
        self.pollInterval = pollInterval
        self.observedChangeCount = pasteboard.changeCount
    }

    func start() {
        guard pollTask == nil else {
            return
        }

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let pollInterval = self?.pollInterval else {
                    return
                }

                try? await Task.sleep(
                    for: .seconds(pollInterval)
                )
                guard !Task.isCancelled else {
                    return
                }

                self?.refreshIfNeeded()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refreshIfNeeded() {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != observedChangeCount else {
            return
        }

        observedChangeCount = currentChangeCount

        if let text = pasteboard.readPlainText() {
            history.record(text)
        }
    }

    func copyToPasteboard(_ item: ClipboardItem) {
        do {
            try pasteboard.writePlainText(item.text)
            observedChangeCount = pasteboard.changeCount
            history.record(item.text)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func clearHistory() {
        history.clear()
    }
}
