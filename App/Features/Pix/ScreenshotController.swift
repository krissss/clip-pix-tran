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
    private var activeCaptureTask: Task<Data, Error>?
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
        await capture {
            try await screenshotService.captureMainDisplay()
        }
    }

    func captureSelectedRegion() async {
        let screenshotService = screenshotService
        await capture {
            try await screenshotService.captureSelectedRegion()
        }
    }

    private func capture(_ action: @Sendable @escaping () async throws -> Data) async {
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

        let captureTimeoutNanoseconds = captureTimeoutNanoseconds
        let watchdog = Task(priority: .userInitiated) { [weak self] in
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
        defer {
            watchdog.cancel()
            releaseCapture(captureID)
        }

        do {
            let data = try await captureTask.value
            guard activeCaptureID == captureID else {
                return
            }

            history.record(data)
            clearLastError()
        } catch is CancellationError {
            if activeCaptureID == captureID {
                clearLastError()
            }
        } catch ScreenshotCaptureError.cancelled {
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
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return "ClipPixTran-\(formatter.string(from: item.createdAt)).png"
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
