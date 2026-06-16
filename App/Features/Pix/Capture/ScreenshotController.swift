import AppKit

enum PixCaptureMode: String, CaseIterable, Identifiable {
    case screenshot
    case recording

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .screenshot:
            L10n.pixScreenshot
        case .recording:
            L10n.pixRecording
        }
    }
}

enum ScreenshotCaptureResult: Equatable {
    case completed
    case ignored
    case needsScreenRecordingPermission
}

@MainActor
@Observable
final class ScreenshotController {
    let history: ScreenshotHistoryStore

    private let screenshotService: ScreenshotService
    private let recordingService: ScreenRecordingService
    private let pasteboard: ScreenshotPasteboardService
    private let fileSaver: ScreenshotFileSaving
    private let recordingExporter: ScreenRecordingFileExporting
    private let pinning: ScreenshotPinning
    private let recordingRegionOverlayFactory: (CGRect) -> ScreenRecordingRegionOverlayPresenting
    private let captureTimeoutNanoseconds: UInt64
    private let ocrService: OCRService?

    var captureMode: PixCaptureMode = .screenshot
    var isCapturing = false
    var isRecording = false
    var isStoppingRecording = false
    var recordingStartedAt: Date?
    var lastErrorMessage: String?
    var lastCaptureError: ScreenshotCaptureError?
    var recordingDidFinish: (() -> Void)?
    /// OCR 截图入历史后的回调，由 App Shell 注入（切到 Pix + 打开主窗口）。
    var ocrCaptureDidRecord: (() -> Void)?
    /// OCR 文本送入翻译的回调，由 App Shell 注入（切到 Tran + 预填文本）。
    var translateText: ((String) -> Void)?
    var needsScreenRecordingPermission: Bool {
        lastCaptureError == .permissionDenied
    }

    private var activeCaptureID: UUID?
    private var activeCaptureTask: Task<ScreenshotCaptureOutput, Error>?
    private var captureKeyMonitor: Any?
    private var activeRecordingSession: ScreenRecordingSession?
    private var recordingControlWindow: ScreenRecordingControlWindow?
    private var recordingRegionOverlay: ScreenRecordingRegionOverlayPresenting?
    private var recordingKeyMonitor: Any?

    init(
        history: ScreenshotHistoryStore? = nil,
        screenshotService: ScreenshotService,
        recordingService: ScreenRecordingService = SystemScreenRecordingService(),
        pasteboard: ScreenshotPasteboardService,
        fileSaver: ScreenshotFileSaving,
        recordingExporter: ScreenRecordingFileExporting = SystemScreenRecordingFileExporter(),
        pinning: ScreenshotPinning? = nil,
        recordingRegionOverlayFactory: @escaping (CGRect) -> ScreenRecordingRegionOverlayPresenting = {
            ScreenRecordingRegionOverlay(recordingRect: $0)
        },
        captureTimeoutNanoseconds: UInt64 = 5_000_000_000,
        ocrService: OCRService? = nil
    ) {
        self.history = history ?? ScreenshotHistoryStore()
        self.screenshotService = screenshotService
        self.recordingService = recordingService
        self.pasteboard = pasteboard
        self.fileSaver = fileSaver
        self.recordingExporter = recordingExporter
        self.pinning = pinning ?? ScreenshotPinToScreenPresenter()
        self.recordingRegionOverlayFactory = recordingRegionOverlayFactory
        self.captureTimeoutNanoseconds = captureTimeoutNanoseconds
        self.ocrService = ocrService
    }

    @discardableResult
    func performPrimaryCapture() async -> ScreenshotCaptureResult {
        switch captureMode {
        case .screenshot:
            await captureSelectedRegion(initialMode: .screenshot)
        case .recording:
            await captureSelectedRegion(initialMode: .recording)
        }
    }

    @discardableResult
    func captureMainDisplay() async -> ScreenshotCaptureResult {
        let screenshotService = screenshotService
        return await capture(usesTimeout: true, captureSource: .fullScreen) {
            ScreenshotCaptureOutput(data: try await screenshotService.captureMainDisplay())
        }
    }

    @discardableResult
    func captureSelectedRegion() async -> ScreenshotCaptureResult {
        await captureSelectedRegion(initialMode: .screenshot)
    }

    private func captureSelectedRegion(initialMode: ScreenshotRegionCaptureMode) async -> ScreenshotCaptureResult {
        guard !isCapturing else {
            return .ignored
        }

        let screenshotService = screenshotService
        do {
            try await screenshotService.ensureScreenCaptureAccess()
        } catch let error as ScreenshotCaptureError {
            setCaptureError(error)
            return captureResult(for: error)
        } catch {
            setOperationError(error)
            return .completed
        }

        return await capture(usesTimeout: false) {
            try await screenshotService.captureSelectedRegion(initialMode: initialMode)
        }
    }

    private func capture(
        usesTimeout: Bool,
        captureSource: ScreenshotItem.CaptureSource = .selectedRegion,
        _ action: @Sendable @escaping () async throws -> ScreenshotCaptureOutput
    ) async -> ScreenshotCaptureResult {
        guard !isCapturing else {
            return .ignored
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
                return .ignored
            }

            switch output.completion {
            case .recordOnly:
                captureMode = .screenshot
                history.record(output.data, captureSource: captureSource)
            case .copy:
                captureMode = .screenshot
                history.record(output.data, captureSource: captureSource)
                try pasteboard.writePNGData(output.data)
            case .save:
                captureMode = .screenshot
                history.record(output.data, captureSource: captureSource)
                try fileSaver.savePNGData(
                    output.data,
                    suggestedFileName: suggestedFileName(createdAt: Date())
                )
            case .pinToScreen:
                captureMode = .screenshot
                history.record(output.data, captureSource: captureSource)
                try pinning.pinPNGData(output.data, sourceRect: output.sourceRect)
            case .recognizeText:
                captureMode = .screenshot
                history.record(output.data, captureSource: captureSource)
                ocrCaptureDidRecord?()
                await recognizeAndCopyImageData(output.data)
            case .startRecording:
                guard let sourceRect = output.sourceRect else {
                    throw ScreenshotCaptureError.unavailable
                }

                captureMode = .recording
                try await startRecording(in: sourceRect)
            }
            clearLastError()
            return .completed
        } catch is CancellationError {
            if activeCaptureID == captureID {
                clearLastError()
            }
            return .completed
        } catch ScreenshotCaptureError.cancelled {
            if activeCaptureID == captureID {
                clearLastError()
            }
            return .completed
        } catch ScreenshotSaveError.cancelled {
            if activeCaptureID == captureID {
                clearLastError()
            }
            return .completed
        } catch let error as ScreenshotCaptureError {
            if activeCaptureID == captureID {
                setCaptureError(error)
            }
            return captureResult(for: error)
        } catch {
            if activeCaptureID == captureID {
                setOperationError(error)
            }
            return .completed
        }
    }

    @discardableResult
    func startSelectedRegionRecording() async -> ScreenshotCaptureResult {
        await captureSelectedRegion(initialMode: .recording)
    }

    private func startRecording(in selectedRect: CGRect) async throws {
        guard !isRecording else {
            return
        }

        showRecordingRegionOverlay(selectedRect: selectedRect)
        showRecordingControlWindow(startedAt: Date())
        let excludedWindowIDs = recordingHintWindowIDs()

        do {
            let session = try await recordingService.startRecording(
                in: selectedRect,
                excludingWindowIDs: excludedWindowIDs
            )
            beginRecordingSession(session)
        } catch {
            closeRecordingHints()
            throw error
        }
    }

    private func beginRecordingSession(_ session: ScreenRecordingSession) {
        activeRecordingSession = session
        isRecording = true
        recordingStartedAt = session.startedAt
        installRecordingKeyMonitor()
        recordingControlWindow?.updateStartedAt(session.startedAt)
    }

    func stopCapture() {
        if isRecording {
            stopRecording()
            return
        }

        guard let activeCaptureID else {
            return
        }

        cancelCapture(activeCaptureID)
    }

    func stopRecording() {
        guard let session = activeRecordingSession else {
            return
        }

        guard !isStoppingRecording else {
            return
        }

        isStoppingRecording = true
        recordingControlWindow?.close()
        Task { @MainActor [weak self, session] in
            var didFinishRecording = false

            do {
                let output = try await session.stop()
                guard self?.activeRecordingSession === session else {
                    return
                }

                self?.history.record(output)
                self?.clearLastError()
                didFinishRecording = true
            } catch is CancellationError {
                self?.clearLastError()
            } catch ScreenshotSaveError.cancelled {
                self?.clearLastError()
            } catch {
                self?.setOperationError(error)
            }

            self?.releaseRecording(session)
            if didFinishRecording {
                self?.recordingDidFinish?()
            }
        }
    }

    func cancelRecording() {
        guard let session = activeRecordingSession else {
            return
        }

        guard !isStoppingRecording else {
            return
        }

        isStoppingRecording = true
        recordingControlWindow?.close()
        Task { @MainActor [weak self, session] in
            await session.cancel()
            self?.clearLastError()
            self?.releaseRecording(session)
        }
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

    private func installRecordingKeyMonitor() {
        removeRecordingKeyMonitor()
        recordingKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .rightMouseDown]) { [weak self] event in
            if event.type == .rightMouseDown {
                Task { @MainActor [weak self] in
                    self?.cancelRecording()
                }
                return nil
            }

            guard event.keyCode == 53 else {
                return event
            }

            Task { @MainActor [weak self] in
                self?.stopRecording()
            }
            return nil
        }
    }

    private func removeRecordingKeyMonitor() {
        if let recordingKeyMonitor {
            NSEvent.removeMonitor(recordingKeyMonitor)
            self.recordingKeyMonitor = nil
        }
    }

    private func showRecordingControlWindow(startedAt: Date) {
        recordingControlWindow?.close()
        let controlWindow = ScreenRecordingControlWindow(
            startedAt: startedAt,
            stopAction: { [weak self] in
                self?.stopRecording()
            },
            cancelAction: { [weak self] in
                self?.cancelRecording()
            }
        )
        recordingControlWindow = controlWindow
        controlWindow.show()
    }

    private func showRecordingRegionOverlay(selectedRect: CGRect) {
        recordingRegionOverlay?.close()
        let regionOverlay = recordingRegionOverlayFactory(selectedRect)
        recordingRegionOverlay = regionOverlay
        regionOverlay.show()
    }

    private func recordingHintWindowIDs() -> Set<CGWindowID> {
        (recordingRegionOverlay?.excludedWindowIDs ?? [])
            .union(recordingControlWindow?.excludedWindowIDs ?? [])
    }

    private func closeRecordingHints() {
        recordingControlWindow?.close()
        recordingControlWindow = nil
        recordingRegionOverlay?.close()
        recordingRegionOverlay = nil
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

    private func releaseRecording(_ session: ScreenRecordingSession) {
        guard activeRecordingSession === session else {
            return
        }

        activeRecordingSession = nil
        isRecording = false
        isStoppingRecording = false
        recordingStartedAt = nil
        closeRecordingHints()
        removeRecordingKeyMonitor()
    }

    func copyToPasteboard(_ item: ScreenshotItem) {
        guard item.isImage else {
            return
        }

        do {
            try pasteboard.writePNGData(item.data)
            clearLastError()
        } catch {
            setOperationError(error)
        }
    }

    func save(_ item: ScreenshotItem) {
        guard item.isImage else {
            return
        }

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

    func pinToScreen(_ item: ScreenshotItem) {
        guard item.isImage else {
            return
        }

        do {
            try pinning.pinPNGData(item.data, sourceRect: nil)
            clearLastError()
        } catch {
            setOperationError(error)
        }
    }

    func exportMP4(_ item: ScreenshotItem) {
        guard let url = item.recordingURL else {
            setOperationError(ScreenRecordingError.missingRecordingFile)
            return
        }

        do {
            try recordingExporter.saveMP4File(
                at: url,
                suggestedFileName: suggestedFileName(forRecording: item, extension: "mp4")
            )
            clearLastError()
        } catch ScreenshotSaveError.cancelled {
            clearLastError()
        } catch {
            setOperationError(error)
        }
    }

    func exportGIF(_ item: ScreenshotItem, options: ScreenRecordingGIFExportOptions) {
        guard let url = item.recordingURL else {
            setOperationError(ScreenRecordingError.missingRecordingFile)
            return
        }

        Task { @MainActor [weak self] in
            do {
                try await self?.recordingExporter.saveGIFFile(
                    from: url,
                    suggestedFileName: self?.suggestedFileName(forRecording: item, extension: "gif") ?? "Pix.gif",
                    options: options
                )
                self?.clearLastError()
            } catch ScreenshotSaveError.cancelled {
                self?.clearLastError()
            } catch {
                self?.setOperationError(error)
            }
        }
    }

    func delete(_ item: ScreenshotItem) {
        history.delete(item)
    }

    func clearHistory() {
        history.clear()
    }

    // MARK: - OCR

    /// OCR 服务，供视图观察识别进度。可能为 nil（无 OCR 能力）。
    var ocr: OCRService? {
        ocrService
    }

    /// 对历史中的某张截图触发 OCR，成功后把文本写回历史。
    func recognizeText(_ item: ScreenshotItem) async {
        guard let ocrService else {
            return
        }

        do {
            let result = try await ocrService.recognize(imageData: item.data, itemID: item.id)
            history.updateRecognizedText(result.text, for: item.id)
            clearLastError()
        } catch let error as OCRError {
            setOperationError(error)
        } catch {
            setOperationError(error)
        }
    }

    /// 用编辑后的文本回写某张截图的识别结果。
    func updateRecognizedText(_ item: ScreenshotItem, text: String?) {
        history.updateRecognizedText(text, for: item.id)
    }

    /// 把某张截图的识别文本送入翻译。
    func translateRecognizedText(_ item: ScreenshotItem) {
        let text = item.recognizedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            return
        }
        translateText?(text)
    }

    /// 复制识别文本到剪贴板。
    func copyRecognizedText(_ item: ScreenshotItem) {
        let text = item.recognizedText ?? ""
        guard !text.isEmpty else {
            return
        }
        pasteboard.writeString(text)
        clearLastError()
    }

    /// 对刚捕获的图片数据跑 OCR，把结果写入最新的历史项并复制到剪贴板。
    private func recognizeAndCopyImageData(_ data: Data) async {
        guard let ocrService else {
            return
        }

        let itemID = history.items.first?.id
        guard let itemID else {
            return
        }

        do {
            let result = try await ocrService.recognize(imageData: data, itemID: itemID)
            history.updateRecognizedText(result.text, for: itemID)
            if !result.text.isEmpty {
                pasteboard.writeString(result.text)
            }
            clearLastError()
        } catch let error as OCRError {
            setOperationError(error)
        } catch {
            setOperationError(error)
        }
    }

    private func suggestedFileName(for item: ScreenshotItem) -> String {
        suggestedFileName(createdAt: item.createdAt)
    }

    private func suggestedFileName(forRecording item: ScreenshotItem, extension fileExtension: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return "Pix-\(formatter.string(from: item.createdAt)).\(fileExtension)"
    }

    private func suggestedFileName(createdAt: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return "Pix-\(formatter.string(from: createdAt)).png"
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

    private func captureResult(for error: ScreenshotCaptureError) -> ScreenshotCaptureResult {
        error == .permissionDenied ? .needsScreenRecordingPermission : .completed
    }
}
