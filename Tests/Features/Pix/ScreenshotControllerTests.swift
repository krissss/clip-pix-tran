import Foundation
import CoreGraphics
import Testing
@testable import ClipPixTran

@MainActor
struct ScreenshotControllerTests {
    @Test func captureRecordsScreenshot() async throws {
        let data = try #require("shot".data(using: .utf8))
        let controller = ScreenshotController(
            screenshotService: FakeScreenshotService(
                mainDisplayResult: .success(data),
                selectedRegionResult: .success(ScreenshotCaptureOutput(data: Data()))
            ),
            pasteboard: FakeScreenshotPasteboardService(),
            fileSaver: FakeScreenshotFileSaver()
        )

        await controller.captureMainDisplay()

        #expect(controller.history.items.map(\.data) == [data])
        #expect(controller.lastErrorMessage == nil)
        #expect(controller.lastCaptureError == nil)
    }

    @Test func selectedRegionCaptureRecordsScreenshot() async throws {
        let data = try #require("region".data(using: .utf8))
        let pasteboard = FakeScreenshotPasteboardService()
        let controller = ScreenshotController(
            screenshotService: FakeScreenshotService(
                mainDisplayResult: .success(Data()),
                selectedRegionResult: .success(ScreenshotCaptureOutput(data: data, completion: .copy))
            ),
            pasteboard: pasteboard,
            fileSaver: FakeScreenshotFileSaver()
        )

        await controller.captureSelectedRegion()

        #expect(controller.history.items.map(\.data) == [data])
        #expect(pasteboard.copiedData == data)
        #expect(controller.lastErrorMessage == nil)
        #expect(controller.lastCaptureError == nil)
    }

    @Test func selectedRegionSaveCompletionRecordsAndSavesScreenshot() async throws {
        let data = try #require("saved-region".data(using: .utf8))
        let fileSaver = FakeScreenshotFileSaver()
        let controller = ScreenshotController(
            screenshotService: FakeScreenshotService(
                mainDisplayResult: .success(Data()),
                selectedRegionResult: .success(ScreenshotCaptureOutput(data: data, completion: .save))
            ),
            pasteboard: FakeScreenshotPasteboardService(),
            fileSaver: fileSaver
        )

        await controller.captureSelectedRegion()

        #expect(controller.history.items.map(\.data) == [data])
        #expect(fileSaver.savedData == data)
        #expect(fileSaver.suggestedFileName?.hasSuffix(".png") == true)
        #expect(controller.lastErrorMessage == nil)
        #expect(controller.lastCaptureError == nil)
    }

    @Test func selectedRegionPinCompletionRecordsAndPinsScreenshot() async throws {
        let data = try #require("pinned-region".data(using: .utf8))
        let sourceRect = CGRect(x: 12, y: 34, width: 120, height: 80)
        let pinning = FakeScreenshotPinning()
        let controller = ScreenshotController(
            screenshotService: FakeScreenshotService(
                mainDisplayResult: .success(Data()),
                selectedRegionResult: .success(
                    ScreenshotCaptureOutput(
                        data: data,
                        completion: .pinToScreen,
                        sourceRect: sourceRect
                    )
                )
            ),
            pasteboard: FakeScreenshotPasteboardService(),
            fileSaver: FakeScreenshotFileSaver(),
            pinning: pinning
        )

        await controller.captureSelectedRegion()

        #expect(controller.history.items.map(\.data) == [data])
        #expect(pinning.pinnedData == data)
        #expect(pinning.sourceRect == sourceRect)
        #expect(controller.lastErrorMessage == nil)
        #expect(controller.lastCaptureError == nil)
    }

    @Test func selectedRegionSaveCancellationDoesNotSetErrorMessage() async throws {
        let data = try #require("cancelled-save-region".data(using: .utf8))
        let controller = ScreenshotController(
            screenshotService: FakeScreenshotService(
                mainDisplayResult: .success(Data()),
                selectedRegionResult: .success(ScreenshotCaptureOutput(data: data, completion: .save))
            ),
            pasteboard: FakeScreenshotPasteboardService(),
            fileSaver: FakeScreenshotFileSaver(error: ScreenshotSaveError.cancelled)
        )

        await controller.captureSelectedRegion()

        #expect(controller.history.items.map(\.data) == [data])
        #expect(controller.lastErrorMessage == nil)
        #expect(controller.lastCaptureError == nil)
    }

    @Test func captureFailureSetsErrorMessage() async {
        let controller = ScreenshotController(
            screenshotService: FakeScreenshotService(
                mainDisplayResult: .failure(ScreenshotCaptureError.permissionDenied),
                selectedRegionResult: .success(ScreenshotCaptureOutput(data: Data()))
            ),
            pasteboard: FakeScreenshotPasteboardService(),
            fileSaver: FakeScreenshotFileSaver()
        )

        await controller.captureMainDisplay()

        #expect(controller.history.items.isEmpty)
        #expect(controller.lastErrorMessage == ScreenshotCaptureError.permissionDenied.localizedDescription)
        #expect(controller.lastCaptureError == .permissionDenied)
        #expect(controller.needsScreenRecordingPermission)
    }

    @Test func selectedRegionCancellationDoesNotSetErrorMessage() async {
        let controller = ScreenshotController(
            screenshotService: FakeScreenshotService(
                mainDisplayResult: .success(Data()),
                selectedRegionResult: .failure(ScreenshotCaptureError.cancelled)
            ),
            pasteboard: FakeScreenshotPasteboardService(),
            fileSaver: FakeScreenshotFileSaver()
        )

        await controller.captureSelectedRegion()

        #expect(controller.history.items.isEmpty)
        #expect(controller.lastErrorMessage == nil)
        #expect(controller.lastCaptureError == nil)
    }

    @Test func mainDisplayCaptureTimeoutReleasesCapturingStateBeforeServiceReturns() async throws {
        let data = try #require("late-shot".data(using: .utf8))
        let controller = ScreenshotController(
            screenshotService: DelayedScreenshotService(
                delayNanoseconds: 200_000_000,
                data: data
            ),
            pasteboard: FakeScreenshotPasteboardService(),
            fileSaver: FakeScreenshotFileSaver(),
            captureTimeoutNanoseconds: 20_000_000
        )

        let captureTask = Task {
            await controller.captureMainDisplay()
        }

        try await waitUntil {
            controller.isCapturing == false
                && controller.lastCaptureError == .timedOut
        }

        #expect(controller.isCapturing == false)
        #expect(controller.lastErrorMessage == ScreenshotCaptureError.timedOut.localizedDescription)
        #expect(controller.lastCaptureError == .timedOut)
        #expect(!controller.needsScreenRecordingPermission)
        #expect(controller.history.items.isEmpty)

        await captureTask.value

        #expect(controller.history.items.isEmpty)
    }

    @Test func selectedRegionCaptureDoesNotTimeoutWhileUserIsEditing() async throws {
        let data = try #require("late-region".data(using: .utf8))
        let controller = ScreenshotController(
            screenshotService: DelayedScreenshotService(
                delayNanoseconds: 80_000_000,
                data: data
            ),
            pasteboard: FakeScreenshotPasteboardService(),
            fileSaver: FakeScreenshotFileSaver(),
            captureTimeoutNanoseconds: 20_000_000
        )

        await controller.captureSelectedRegion()

        #expect(controller.history.items.map(\.data) == [data])
        #expect(controller.lastErrorMessage == nil)
        #expect(controller.lastCaptureError == nil)
    }

    @Test func stopCaptureReleasesCapturingStateBeforeServiceReturns() async throws {
        let data = try #require("late-shot".data(using: .utf8))
        let controller = ScreenshotController(
            screenshotService: DelayedScreenshotService(
                delayNanoseconds: 200_000_000,
                data: data
            ),
            pasteboard: FakeScreenshotPasteboardService(),
            fileSaver: FakeScreenshotFileSaver(),
            captureTimeoutNanoseconds: 1_000_000_000
        )

        let captureTask = Task {
            await controller.captureSelectedRegion()
        }

        try await Task.sleep(nanoseconds: 20_000_000)
        controller.stopCapture()

        #expect(controller.isCapturing == false)
        #expect(controller.lastErrorMessage == nil)
        #expect(controller.lastCaptureError == nil)

        await captureTask.value

        #expect(controller.history.items.isEmpty)
    }

    @Test func copyFailureSetsErrorMessage() throws {
        let data = try #require("shot".data(using: .utf8))
        let pasteboard = FakeScreenshotPasteboardService(
            error: ScreenshotPasteboardError.rejected
        )
        let controller = ScreenshotController(
            screenshotService: FakeScreenshotService(
                mainDisplayResult: .success(data),
                selectedRegionResult: .success(ScreenshotCaptureOutput(data: Data()))
            ),
            pasteboard: pasteboard,
            fileSaver: FakeScreenshotFileSaver()
        )
        let item = ScreenshotItem(data: data)

        controller.copyToPasteboard(item)

        #expect(controller.lastErrorMessage == ScreenshotPasteboardError.rejected.localizedDescription)
        #expect(controller.lastCaptureError == nil)
        #expect(!controller.needsScreenRecordingPermission)
    }

    @Test func copySuccessWritesPasteboardAndClearsPreviousError() throws {
        let data = try #require("shot".data(using: .utf8))
        let pasteboard = FakeScreenshotPasteboardService()
        let controller = ScreenshotController(
            screenshotService: FakeScreenshotService(
                mainDisplayResult: .success(data),
                selectedRegionResult: .success(ScreenshotCaptureOutput(data: Data()))
            ),
            pasteboard: pasteboard,
            fileSaver: FakeScreenshotFileSaver()
        )
        let item = ScreenshotItem(data: data)
        controller.lastErrorMessage = "旧错误"
        controller.lastCaptureError = .permissionDenied

        controller.copyToPasteboard(item)

        #expect(pasteboard.copiedData == data)
        #expect(controller.lastErrorMessage == nil)
        #expect(controller.lastCaptureError == nil)
    }

    @Test func savingCancelledDoesNotSetErrorMessage() throws {
        let data = try #require("shot".data(using: .utf8))
        let controller = ScreenshotController(
            screenshotService: FakeScreenshotService(
                mainDisplayResult: .success(data),
                selectedRegionResult: .success(ScreenshotCaptureOutput(data: Data()))
            ),
            pasteboard: FakeScreenshotPasteboardService(),
            fileSaver: FakeScreenshotFileSaver(error: ScreenshotSaveError.cancelled)
        )
        let item = ScreenshotItem(data: data)

        controller.save(item)

        #expect(controller.lastErrorMessage == nil)
        #expect(controller.lastCaptureError == nil)
    }

    @Test func saveSuccessWritesFileAndClearsPreviousError() throws {
        let data = try #require("shot".data(using: .utf8))
        let fileSaver = FakeScreenshotFileSaver()
        let controller = ScreenshotController(
            screenshotService: FakeScreenshotService(
                mainDisplayResult: .success(data),
                selectedRegionResult: .success(ScreenshotCaptureOutput(data: Data()))
            ),
            pasteboard: FakeScreenshotPasteboardService(),
            fileSaver: fileSaver
        )
        let item = ScreenshotItem(data: data, createdAt: Date(timeIntervalSince1970: 0))
        controller.lastErrorMessage = "旧错误"
        controller.lastCaptureError = .permissionDenied

        controller.save(item)

        #expect(fileSaver.savedData == data)
        #expect(fileSaver.suggestedFileName?.hasPrefix("ClipPixTran-") == true)
        #expect(fileSaver.suggestedFileName?.hasSuffix(".png") == true)
        #expect(controller.lastErrorMessage == nil)
        #expect(controller.lastCaptureError == nil)
    }

    @Test func saveFailureSetsOperationError() throws {
        let data = try #require("shot".data(using: .utf8))
        let controller = ScreenshotController(
            screenshotService: FakeScreenshotService(
                mainDisplayResult: .success(data),
                selectedRegionResult: .success(ScreenshotCaptureOutput(data: Data()))
            ),
            pasteboard: FakeScreenshotPasteboardService(),
            fileSaver: FakeScreenshotFileSaver(error: FakeScreenshotSaveError.failed)
        )
        let item = ScreenshotItem(data: data)

        controller.save(item)

        #expect(controller.lastErrorMessage == FakeScreenshotSaveError.failed.localizedDescription)
        #expect(controller.lastCaptureError == nil)
    }

    @Test func pinToScreenPinsExistingScreenshotAndClearsPreviousError() throws {
        let data = try #require("shot".data(using: .utf8))
        let pinning = FakeScreenshotPinning()
        let controller = ScreenshotController(
            screenshotService: FakeScreenshotService(
                mainDisplayResult: .success(data),
                selectedRegionResult: .success(ScreenshotCaptureOutput(data: Data()))
            ),
            pasteboard: FakeScreenshotPasteboardService(),
            fileSaver: FakeScreenshotFileSaver(),
            pinning: pinning
        )
        let item = ScreenshotItem(data: data)
        controller.lastErrorMessage = "旧错误"
        controller.lastCaptureError = .permissionDenied

        controller.pinToScreen(item)

        #expect(pinning.pinnedData == data)
        #expect(pinning.sourceRect == nil)
        #expect(controller.lastErrorMessage == nil)
        #expect(controller.lastCaptureError == nil)
    }

    @Test func pinToScreenFailureSetsOperationError() throws {
        let data = try #require("shot".data(using: .utf8))
        let controller = ScreenshotController(
            screenshotService: FakeScreenshotService(
                mainDisplayResult: .success(data),
                selectedRegionResult: .success(ScreenshotCaptureOutput(data: Data()))
            ),
            pasteboard: FakeScreenshotPasteboardService(),
            fileSaver: FakeScreenshotFileSaver(),
            pinning: FakeScreenshotPinning(error: FakeScreenshotPinError.failed)
        )
        let item = ScreenshotItem(data: data)

        controller.pinToScreen(item)

        #expect(controller.lastErrorMessage == FakeScreenshotPinError.failed.localizedDescription)
        #expect(controller.lastCaptureError == nil)
    }

    @Test func deleteAndClearHistoryDelegateToStore() throws {
        let firstData = try #require("first".data(using: .utf8))
        let secondData = try #require("second".data(using: .utf8))
        let history = ScreenshotHistoryStore()
        let controller = ScreenshotController(
            history: history,
            screenshotService: FakeScreenshotService(
                mainDisplayResult: .success(firstData),
                selectedRegionResult: .success(ScreenshotCaptureOutput(data: Data()))
            ),
            pasteboard: FakeScreenshotPasteboardService(),
            fileSaver: FakeScreenshotFileSaver()
        )
        history.record(firstData)
        history.record(secondData)
        let item = try #require(history.items.first)

        controller.delete(item)
        #expect(history.items.map(\.data) == [firstData])

        controller.clearHistory()
        #expect(history.items.isEmpty)
    }
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 3_000_000_000,
    pollIntervalNanoseconds: UInt64 = 10_000_000,
    condition: () -> Bool
) async throws {
    let deadline = ContinuousClock.now + .nanoseconds(Int64(timeoutNanoseconds))

    while ContinuousClock.now < deadline {
        if condition() {
            return
        }

        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }
}

private struct DelayedScreenshotService: ScreenshotService {
    let delayNanoseconds: UInt64
    let data: Data

    func captureMainDisplay() async throws -> Data {
        try await delayedData()
    }

    func captureSelectedRegion() async throws -> ScreenshotCaptureOutput {
        ScreenshotCaptureOutput(data: try await delayedData(), completion: .copy)
    }

    private func delayedData() async throws -> Data {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return data
    }
}

private struct FakeScreenshotService: ScreenshotService {
    let mainDisplayResult: Result<Data, Error>
    let selectedRegionResult: Result<ScreenshotCaptureOutput, Error>

    func captureMainDisplay() async throws -> Data {
        try mainDisplayResult.get()
    }

    func captureSelectedRegion() async throws -> ScreenshotCaptureOutput {
        try selectedRegionResult.get()
    }
}

private final class FakeScreenshotPasteboardService: ScreenshotPasteboardService {
    private(set) var copiedData: Data?
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func writePNGData(_ data: Data) throws {
        if let error {
            throw error
        }

        copiedData = data
    }
}

private final class FakeScreenshotFileSaver: ScreenshotFileSaving {
    private(set) var savedData: Data?
    private(set) var suggestedFileName: String?
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func savePNGData(_ data: Data, suggestedFileName: String) throws {
        if let error {
            throw error
        }

        savedData = data
        self.suggestedFileName = suggestedFileName
    }
}

@MainActor
private final class FakeScreenshotPinning: ScreenshotPinning {
    private(set) var pinnedData: Data?
    private(set) var sourceRect: CGRect?
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func pinPNGData(_ data: Data, sourceRect: CGRect?) throws {
        if let error {
            throw error
        }

        pinnedData = data
        self.sourceRect = sourceRect
    }
}

private enum FakeScreenshotSaveError: LocalizedError {
    case failed

    var errorDescription: String? {
        "保存失败。"
    }
}

private enum FakeScreenshotPinError: LocalizedError {
    case failed

    var errorDescription: String? {
        "固定失败。"
    }
}
