import Foundation
import Testing
@testable import ClipPixTran

@MainActor
struct ScreenshotControllerTests {
    @Test func captureRecordsScreenshot() async throws {
        let data = try #require("shot".data(using: .utf8))
        let controller = ScreenshotController(
            screenshotService: FakeScreenshotService(
                mainDisplayResult: .success(data),
                selectedRegionResult: .success(Data())
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
        let controller = ScreenshotController(
            screenshotService: FakeScreenshotService(
                mainDisplayResult: .success(Data()),
                selectedRegionResult: .success(data)
            ),
            pasteboard: FakeScreenshotPasteboardService(),
            fileSaver: FakeScreenshotFileSaver()
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
                selectedRegionResult: .success(Data())
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

    @Test func captureTimeoutReleasesCapturingStateBeforeServiceReturns() async throws {
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
            await controller.captureSelectedRegion()
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
                selectedRegionResult: .success(Data())
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
                selectedRegionResult: .success(Data())
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
                selectedRegionResult: .success(Data())
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
                selectedRegionResult: .success(Data())
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
                selectedRegionResult: .success(Data())
            ),
            pasteboard: FakeScreenshotPasteboardService(),
            fileSaver: FakeScreenshotFileSaver(error: FakeScreenshotSaveError.failed)
        )
        let item = ScreenshotItem(data: data)

        controller.save(item)

        #expect(controller.lastErrorMessage == FakeScreenshotSaveError.failed.localizedDescription)
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
                selectedRegionResult: .success(Data())
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
    timeoutNanoseconds: UInt64 = 1_000_000_000,
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

    func captureSelectedRegion() async throws -> Data {
        try await delayedData()
    }

    private func delayedData() async throws -> Data {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return data
    }
}

private struct FakeScreenshotService: ScreenshotService {
    let mainDisplayResult: Result<Data, Error>
    let selectedRegionResult: Result<Data, Error>

    func captureMainDisplay() async throws -> Data {
        try mainDisplayResult.get()
    }

    func captureSelectedRegion() async throws -> Data {
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

private enum FakeScreenshotSaveError: LocalizedError {
    case failed

    var errorDescription: String? {
        "保存失败。"
    }
}
