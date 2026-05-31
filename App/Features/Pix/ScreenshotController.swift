import AppKit

@MainActor
@Observable
final class ScreenshotController {
    let history: ScreenshotHistoryStore

    private let screenshotService: ScreenshotService
    private let pasteboard: ScreenshotPasteboardService
    private let fileSaver: ScreenshotFileSaving
    private let captureTimeoutNanoseconds: UInt64

    var isCapturing = false
    var lastErrorMessage: String?
    var lastCaptureError: ScreenshotCaptureError?
    var needsScreenRecordingPermission: Bool {
        lastCaptureError == .permissionDenied
    }

    private var activeCaptureID: UUID?
    private var activeCaptureTask: Task<ScreenshotCaptureOutput, Error>?
    private var captureKeyMonitor: Any?

    init(
        history: ScreenshotHistoryStore? = nil,
        screenshotService: ScreenshotService,
        pasteboard: ScreenshotPasteboardService,
        fileSaver: ScreenshotFileSaving,
        captureTimeoutNanoseconds: UInt64 = 5_000_000_000
    ) {
        self.history = history ?? ScreenshotHistoryStore()
        self.screenshotService = screenshotService
        self.pasteboard = pasteboard
        self.fileSaver = fileSaver
        self.captureTimeoutNanoseconds = captureTimeoutNanoseconds
    }

    func captureMainDisplay() async {
        let screenshotService = screenshotService
        await capture(usesTimeout: true) {
            ScreenshotCaptureOutput(data: try await screenshotService.captureMainDisplay())
        }
    }

    func captureSelectedRegion() async {
        let screenshotService = screenshotService
        await capture(usesTimeout: false) {
            try await screenshotService.captureSelectedRegion()
        }
    }

    private func capture(
        usesTimeout: Bool,
        _ action: @Sendable @escaping () async throws -> ScreenshotCaptureOutput
    ) async {
        guard !isCapturing else {
            return
        }

        let captureID = UUID()
        activeCaptureID = captureID
        isCapturing = true
        clearLastError()
        installCaptureKeyMonitor()

        let captureTask = Task.detached(priority: .userInitiated) {
            try await action()
        }
        activeCaptureTask = captureTask

        let watchdog: Task<Void, Never>?
        if usesTimeout {
            let captureTimeoutNanoseconds = captureTimeoutNanoseconds
            watchdog = Task(priority: .userInitiated) { [weak self] in
                do {
                    try await Task.sleep(nanoseconds: captureTimeoutNanoseconds)
                } catch {
                    return
                }

                self?.cancelCapture(
                    captureID,
                    captureError: .timedOut
                )
            }
        } else {
            watchdog = nil
        }
        defer {
            watchdog?.cancel()
            releaseCapture(captureID)
        }

        do {
            let output = try await captureTask.value
            guard activeCaptureID == captureID else {
                return
            }

            history.record(output.data)
            switch output.completion {
            case .recordOnly:
                break
            case .copy:
                try pasteboard.writePNGData(output.data)
            case .save:
                try fileSaver.savePNGData(
                    output.data,
                    suggestedFileName: suggestedFileName(createdAt: Date())
                )
            }
            clearLastError()
        } catch is CancellationError {
            if activeCaptureID == captureID {
                clearLastError()
            }
        } catch ScreenshotCaptureError.cancelled {
            if activeCaptureID == captureID {
                clearLastError()
            }
        } catch ScreenshotSaveError.cancelled {
            if activeCaptureID == captureID {
                clearLastError()
            }
        } catch let error as ScreenshotCaptureError {
            if activeCaptureID == captureID {
                setCaptureError(error)
            }
        } catch {
            if activeCaptureID == captureID {
                setOperationError(error)
            }
        }
    }

    func stopCapture() {
        guard let activeCaptureID else {
            return
        }

        cancelCapture(activeCaptureID)
    }

    private func cancelCapture(_ captureID: UUID, captureError: ScreenshotCaptureError? = nil) {
        guard activeCaptureID == captureID else {
            return
        }

        activeCaptureTask?.cancel()
        NSCursor.arrow.set()
        releaseCapture(captureID, captureError: captureError)
    }

    private func installCaptureKeyMonitor() {
        removeCaptureKeyMonitor()
        captureKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else {
                return event
            }

            Task { @MainActor [weak self] in
                self?.stopCapture()
            }
            return nil
        }
    }

    private func removeCaptureKeyMonitor() {
        if let captureKeyMonitor {
            NSEvent.removeMonitor(captureKeyMonitor)
            self.captureKeyMonitor = nil
        }
    }

    private func releaseCapture(_ captureID: UUID, captureError: ScreenshotCaptureError? = nil) {
        guard activeCaptureID == captureID else {
            return
        }

        activeCaptureID = nil
        activeCaptureTask = nil
        isCapturing = false
        removeCaptureKeyMonitor()
        if let captureError {
            setCaptureError(captureError)
        }
    }

    func copyToPasteboard(_ item: ScreenshotItem) {
        do {
            try pasteboard.writePNGData(item.data)
            clearLastError()
        } catch {
            setOperationError(error)
        }
    }

    func save(_ item: ScreenshotItem) {
        do {
            try fileSaver.savePNGData(
                item.data,
                suggestedFileName: suggestedFileName(for: item)
            )
            clearLastError()
        } catch ScreenshotSaveError.cancelled {
            clearLastError()
        } catch {
            setOperationError(error)
        }
    }

    func delete(_ item: ScreenshotItem) {
        history.delete(item)
    }

    func clearHistory() {
        history.clear()
    }

    private func suggestedFileName(for item: ScreenshotItem) -> String {
        suggestedFileName(createdAt: item.createdAt)
    }

    private func suggestedFileName(createdAt: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return "ClipPixTran-\(formatter.string(from: createdAt)).png"
    }

    private func clearLastError() {
        lastErrorMessage = nil
        lastCaptureError = nil
    }

    private func setCaptureError(_ error: ScreenshotCaptureError) {
        lastErrorMessage = error.localizedDescription
        lastCaptureError = error
    }

    private func setOperationError(_ error: Error) {
        lastErrorMessage = error.localizedDescription
        lastCaptureError = nil
    }
}
