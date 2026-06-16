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
        #expect(controller.history.items.first?.captureSource == .fullScreen)
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
        #expect(controller.history.items.first?.captureSource == .selectedRegion)
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

    @Test func selectedRegionPermissionFailureDoesNotOpenSelection() async {
        let screenshotService = FakeScreenshotService(
            mainDisplayResult: .success(Data()),
            selectedRegionResult: .success(ScreenshotCaptureOutput(data: Data())),
            permissionResult: .failure(ScreenshotCaptureError.permissionDenied)
        )
        let controller = ScreenshotController(
            screenshotService: screenshotService,
            pasteboard: FakeScreenshotPasteboardService(),
            fileSaver: FakeScreenshotFileSaver()
        )

        await controller.captureSelectedRegion()

        #expect(screenshotService.ensurePermissionCallCount == 1)
        #expect(screenshotService.selectedRegionInitialModes.isEmpty)
        #expect(controller.history.items.isEmpty)
        #expect(controller.isCapturing == false)
        #expect(controller.lastErrorMessage == ScreenshotCaptureError.permissionDenied.localizedDescription)
        #expect(controller.lastCaptureError == .permissionDenied)
        #expect(controller.needsScreenRecordingPermission)
    }

    @Test func recordingPermissionFailureDoesNotOpenSelection() async {
        let screenshotService = FakeScreenshotService(
            mainDisplayResult: .success(Data()),
            selectedRegionResult: .success(
                ScreenshotCaptureOutput(
                    data: Data(),
                    completion: .startRecording,
                    sourceRect: CGRect(x: 10, y: 20, width: 100, height: 80)
                )
            ),
            permissionResult: .failure(ScreenshotCaptureError.permissionDenied)
        )
        let recordingService = FakeScreenRecordingService(
            session: FakeScreenRecordingSession(
                output: ScreenRecordingOutput(
                    fileURL: ScreenRecordingFileStore.defaultDirectoryURL.appending(path: "blocked.mp4"),
                    createdAt: Date(),
                    duration: 1,
                    pixelSize: CGSize(width: 100, height: 80),
                    fileSize: 1
                )
            )
        )
        let overlayFactory = FakeScreenRecordingRegionOverlayFactory()
        let controller = ScreenshotController(
            screenshotService: screenshotService,
            recordingService: recordingService,
            pasteboard: FakeScreenshotPasteboardService(),
            fileSaver: FakeScreenshotFileSaver(),
            recordingRegionOverlayFactory: overlayFactory.make
        )
        controller.captureMode = .recording

        await controller.performPrimaryCapture()

        #expect(screenshotService.ensurePermissionCallCount == 1)
        #expect(screenshotService.selectedRegionInitialModes.isEmpty)
        #expect(recordingService.selectedRects.isEmpty)
        #expect(overlayFactory.overlays.isEmpty)
        #expect(controller.isCapturing == false)
        #expect(controller.isRecording == false)
        #expect(controller.lastErrorMessage == ScreenshotCaptureError.permissionDenied.localizedDescription)
        #expect(controller.lastCaptureError == .permissionDenied)
    }

    @Test func mainDisplayCaptureTimeoutReleasesCapturingStateBeforeServiceReturns() async throws {
        let data = try #require("late-shot".data(using: .utf8))
        let controller = ScreenshotController(
            screenshotService: DelayedScreenshotService(
                delayNanoseconds: 5_000_000_000,
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

    @Test func primaryCaptureUsesRecordingMode() async throws {
        let outputURL = ScreenRecordingFileStore.defaultDirectoryURL
            .appending(path: "mode-recording.mp4")
        let session = FakeScreenRecordingSession(
            output: ScreenRecordingOutput(
                fileURL: outputURL,
                createdAt: Date(timeIntervalSince1970: 12),
                duration: 2.5,
                pixelSize: CGSize(width: 320, height: 240),
                fileSize: 500
            )
        )
        let recordingService = FakeScreenRecordingService(
            session: session
        )
        let overlayFactory = FakeScreenRecordingRegionOverlayFactory()
        let screenshotService = FakeScreenshotService(
            mainDisplayResult: .success(Data()),
            selectedRegionResult: .success(
                ScreenshotCaptureOutput(
                    data: Data(),
                    completion: .startRecording,
                    sourceRect: CGRect(x: 12, y: 20, width: 320, height: 240)
                )
            )
        )
        let controller = ScreenshotController(
            screenshotService: screenshotService,
            recordingService: recordingService,
            pasteboard: FakeScreenshotPasteboardService(),
            fileSaver: FakeScreenshotFileSaver(),
            recordingRegionOverlayFactory: overlayFactory.make
        )
        controller.captureMode = .recording

        await controller.performPrimaryCapture()

        let overlay = try #require(overlayFactory.overlays.first)
        #expect(screenshotService.selectedRegionInitialModes == [.recording])
        #expect(recordingService.startCallCount == 0)
        #expect(recordingService.selectedRects == [CGRect(x: 12, y: 20, width: 320, height: 240)])
        #expect(recordingService.excludedWindowIDs.count == 1)
        #expect(recordingService.excludedWindowIDs.first?.contains(101) == true)
        #expect(overlay.recordingRect == CGRect(x: 12, y: 20, width: 320, height: 240))
        #expect(overlay.showCallCount == 1)
        #expect(overlay.closeCallCount == 0)
        #expect(controller.isRecording)
        #expect(controller.history.items.isEmpty)

        controller.cancelRecording()
        try await waitUntil {
            controller.isRecording == false
                && session.cancelCallCount == 1
                && overlay.closeCallCount == 1
        }
    }

    @Test func selectedRegionStartRecordingUsesExistingSelection() async throws {
        let selectedRect = CGRect(x: 10, y: 20, width: 300, height: 180)
        let outputURL = ScreenRecordingFileStore.defaultDirectoryURL
            .appending(path: "toolbar-recording.mp4")
        let session = FakeScreenRecordingSession(
            output: ScreenRecordingOutput(
                fileURL: outputURL,
                createdAt: Date(timeIntervalSince1970: 16),
                duration: 1,
                pixelSize: CGSize(width: 300, height: 180),
                fileSize: 256
            )
        )
        let recordingService = FakeScreenRecordingService(
            session: session
        )
        let overlayFactory = FakeScreenRecordingRegionOverlayFactory()
        let screenshotService = FakeScreenshotService(
            mainDisplayResult: .success(Data()),
            selectedRegionResult: .success(
                ScreenshotCaptureOutput(
                    data: Data(),
                    completion: .startRecording,
                    sourceRect: selectedRect
                )
            )
        )
        let controller = ScreenshotController(
            screenshotService: screenshotService,
            recordingService: recordingService,
            pasteboard: FakeScreenshotPasteboardService(),
            fileSaver: FakeScreenshotFileSaver(),
            recordingRegionOverlayFactory: overlayFactory.make
        )

        await controller.captureSelectedRegion()

        let overlay = try #require(overlayFactory.overlays.first)
        #expect(screenshotService.selectedRegionInitialModes == [.screenshot])
        #expect(recordingService.startCallCount == 0)
        #expect(recordingService.selectedRects == [selectedRect])
        #expect(recordingService.excludedWindowIDs.count == 1)
        #expect(recordingService.excludedWindowIDs.first?.contains(101) == true)
        #expect(overlay.recordingRect == selectedRect)
        #expect(overlay.showCallCount == 1)
        #expect(overlay.closeCallCount == 0)
        #expect(controller.isRecording)
        #expect(controller.history.items.isEmpty)

        controller.cancelRecording()
        try await waitUntil {
            controller.isRecording == false
                && session.cancelCallCount == 1
                && overlay.closeCallCount == 1
        }
    }

    @Test func stoppingRecordingRecordsOutput() async throws {
        let createdAt = Date(timeIntervalSince1970: 123)
        let outputURL = ScreenRecordingFileStore.defaultDirectoryURL
            .appending(path: "recorded.mp4")
        let session = FakeScreenRecordingSession(
            output: ScreenRecordingOutput(
                fileURL: outputURL,
                createdAt: createdAt,
                duration: 4,
                pixelSize: CGSize(width: 640, height: 360),
                fileSize: 2048
            )
        )
        let selectedRect = CGRect(x: 20, y: 30, width: 640, height: 360)
        let overlayFactory = FakeScreenRecordingRegionOverlayFactory()
        let screenshotService = FakeScreenshotService(
            mainDisplayResult: .success(Data()),
            selectedRegionResult: .success(
                ScreenshotCaptureOutput(
                    data: Data(),
                    completion: .startRecording,
                    sourceRect: selectedRect
                )
            )
        )
        let controller = ScreenshotController(
            screenshotService: screenshotService,
            recordingService: FakeScreenRecordingService(session: session),
            pasteboard: FakeScreenshotPasteboardService(),
            fileSaver: FakeScreenshotFileSaver(),
            recordingRegionOverlayFactory: overlayFactory.make
        )
        var finishCallCount = 0
        controller.recordingDidFinish = {
            finishCallCount += 1
        }

        await controller.startSelectedRegionRecording()
        let overlay = try #require(overlayFactory.overlays.first)
        #expect(overlay.recordingRect == selectedRect)
        #expect(overlay.showCallCount == 1)
        controller.stopRecording()

        #expect(screenshotService.selectedRegionInitialModes == [.recording])
        try await waitUntil {
            controller.isRecording == false
                && controller.history.items.count == 1
                && overlay.closeCallCount == 1
                && finishCallCount == 1
        }

        let item = try #require(controller.history.items.first)
        #expect(session.stopCallCount == 1)
        #expect(finishCallCount == 1)
        #expect(item.kind == .recording)
        #expect(item.recordingFileName == "recorded.mp4")
        #expect(item.createdAt == createdAt)
        #expect(item.duration == 4)
        #expect(item.pixelSize == CGSize(width: 640, height: 360))
        #expect(item.byteCount == 2048)
        #expect(controller.lastErrorMessage == nil)
        #expect(controller.lastCaptureError == nil)
    }

    @Test func cancellingRecordingDoesNotRecordOutput() async throws {
        let selectedRect = CGRect(x: 30, y: 40, width: 300, height: 200)
        let overlayFactory = FakeScreenRecordingRegionOverlayFactory()
        let session = FakeScreenRecordingSession(
            output: ScreenRecordingOutput(
                fileURL: ScreenRecordingFileStore.defaultDirectoryURL.appending(path: "cancelled.mp4"),
                createdAt: Date(),
                duration: 1,
                pixelSize: CGSize(width: 10, height: 10),
                fileSize: 1
            )
        )
        let controller = ScreenshotController(
            screenshotService: FakeScreenshotService(
                mainDisplayResult: .success(Data()),
                selectedRegionResult: .success(
                    ScreenshotCaptureOutput(
                        data: Data(),
                        completion: .startRecording,
                        sourceRect: selectedRect
                    )
                )
            ),
            recordingService: FakeScreenRecordingService(session: session),
            pasteboard: FakeScreenshotPasteboardService(),
            fileSaver: FakeScreenshotFileSaver(),
            recordingRegionOverlayFactory: overlayFactory.make
        )
        var finishCallCount = 0
        controller.recordingDidFinish = {
            finishCallCount += 1
        }

        await controller.startSelectedRegionRecording()
        let overlay = try #require(overlayFactory.overlays.first)
        #expect(overlay.recordingRect == selectedRect)
        #expect(overlay.showCallCount == 1)
        controller.cancelRecording()

        try await waitUntil {
            controller.isRecording == false
                && session.cancelCallCount == 1
                && overlay.closeCallCount == 1
        }

        #expect(controller.history.items.isEmpty)
        #expect(finishCallCount == 0)
    }

    @Test func gifExportOptionsClampToSupportedRange() {
        let options = ScreenRecordingGIFExportOptions(
            frameRate: 120,
            playbackSpeed: 0.1,
            maximumPixelSize: 4096,
            maximumFrameCount: 6000
        ).sanitized

        #expect(options.frameRate == 120)
        #expect(options.playbackSpeed == 0.25)
        #expect(options.maximumPixelSize == 1920)
        #expect(options.maximumFrameCount == 6000)
    }

    @Test func gifExportOptionsPreserveMinimumViableValues() {
        let options = ScreenRecordingGIFExportOptions(
            frameRate: .infinity,
            playbackSpeed: 0,
            maximumPixelSize: 0,
            maximumFrameCount: 0
        ).sanitized

        #expect(options.frameRate == 10)
        #expect(options.playbackSpeed == 0.25)
        #expect(options.maximumPixelSize == 320)
        #expect(options.maximumFrameCount == 1)
    }

    @Test func gifFramePlanDoesNotApplyPreviewFrameCap() throws {
        let options = ScreenRecordingGIFExportOptions(
            frameRate: 60,
            playbackSpeed: 1,
            maximumPixelSize: 960,
            maximumFrameCount: 6000
        )

        let framePlan = try #require(
            ScreenRecordingGIFFramePlan(
                sourceDuration: 10.53,
                options: options,
                maximumFrameCount: options.maximumFrameCount
            )
        )

        #expect(framePlan.requestedFrameCount == 632)
        #expect(framePlan.exportFrameCount == 632)
        #expect(framePlan.frameCount == 632)
        #expect(framePlan.frameDelay < 0.02)
        #expect(framePlan.isTruncated == false)
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
        #expect(fileSaver.suggestedFileName?.hasPrefix("Pix-") == true)
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

    // MARK: - OCR

    @Test func recognizeTextWritesResultToHistory() async throws {
        let data = try #require("ocr-image".data(using: .utf8))
        let controller = makeController(
            screenshotService: FakeScreenshotService(
                mainDisplayResult: .success(Data()),
                selectedRegionResult: .success(ScreenshotCaptureOutput(data: data))
            ),
            ocrProvider: { _ in OCRResult(text: "Recognized line", confidence: 0.8) }
        )
        controller.history.record(data)

        let item = try #require(controller.history.items.first)
        #expect(item.recognizedText == nil)

        await controller.recognizeText(item)

        #expect(controller.history.items.first?.recognizedText == "Recognized line")
        #expect(controller.lastErrorMessage == nil)
    }

    @Test func recognizeTextRecordsOCRErrorAsLastMessage() async throws {
        let data = try #require("ocr-image".data(using: .utf8))
        let controller = makeController(
            screenshotService: FakeScreenshotService(
                mainDisplayResult: .success(Data()),
                selectedRegionResult: .success(ScreenshotCaptureOutput(data: data))
            ),
            ocrProvider: { _ in throw OCRError.noTextRecognized }
        )
        controller.history.record(data)
        let item = try #require(controller.history.items.first)

        await controller.recognizeText(item)

        #expect(controller.history.items.first?.recognizedText == nil)
        #expect(controller.lastErrorMessage == OCRError.noTextRecognized.errorDescription)
    }

    @Test func copyRecognizedTextWritesToPasteboard() throws {
        let pasteboard = FakeScreenshotPasteboardService()
        let data = try #require("img".data(using: .utf8))
        let controller = ScreenshotController(
            screenshotService: FakeScreenshotService(
                mainDisplayResult: .success(Data()),
                selectedRegionResult: .success(ScreenshotCaptureOutput(data: data))
            ),
            pasteboard: pasteboard,
            fileSaver: FakeScreenshotFileSaver(),
            ocrService: OCRService(provider: ClosureOCRProvider(body: { @Sendable _ in OCRResult(text: "to copy", confidence: nil) }))
        )
        controller.history.record(data)
        let itemID = controller.history.items.first!.id
        controller.history.updateRecognizedText("to copy", for: itemID)
        let item = controller.history.items.first!

        controller.copyRecognizedText(item)

        #expect(pasteboard.copiedString == "to copy")
    }

    @Test func translateRecognizedTextInvokesCallback() throws {
        let data = try #require("img".data(using: .utf8))
        let controller = ScreenshotController(
            screenshotService: FakeScreenshotService(
                mainDisplayResult: .success(Data()),
                selectedRegionResult: .success(ScreenshotCaptureOutput(data: data))
            ),
            pasteboard: FakeScreenshotPasteboardService(),
            fileSaver: FakeScreenshotFileSaver()
        )
        controller.history.record(data)
        let itemID = controller.history.items.first!.id
        controller.history.updateRecognizedText("请翻译", for: itemID)

        var received: String?
        controller.translateText = { received = $0 }
        controller.translateRecognizedText(controller.history.items.first!)

        #expect(received == "请翻译")
    }

    @Test func translateRecognizedTextIgnoresEmptyText() throws {
        let data = try #require("img".data(using: .utf8))
        let controller = ScreenshotController(
            screenshotService: FakeScreenshotService(
                mainDisplayResult: .success(Data()),
                selectedRegionResult: .success(ScreenshotCaptureOutput(data: data))
            ),
            pasteboard: FakeScreenshotPasteboardService(),
            fileSaver: FakeScreenshotFileSaver()
        )
        controller.history.record(data)

        var received: String?
        controller.translateText = { received = $0 }
        controller.translateRecognizedText(controller.history.items.first!)

        #expect(received == nil)
    }

    @Test func recognizeTextCompletionRecordsAndCopiesText() async throws {
        let data = try #require("region-ocr".data(using: .utf8))
        let pasteboard = FakeScreenshotPasteboardService()
        let controller = makeController(
            screenshotService: FakeScreenshotService(
                mainDisplayResult: .success(Data()),
                selectedRegionResult: .success(
                    ScreenshotCaptureOutput(data: data, completion: .recognizeText)
                )
            ),
            pasteboard: pasteboard,
            ocrProvider: { _ in OCRResult(text: "from region", confidence: nil) }
        )

        await controller.captureSelectedRegion()

        #expect(controller.history.items.map(\.data) == [data])
        #expect(controller.history.items.first?.recognizedText == "from region")
        #expect(pasteboard.copiedString == "from region")
        #expect(controller.lastErrorMessage == nil)
    }

    @Test func recognizeTextCompletionNotifiesAfterRecordingImage() async throws {
        let data = try #require("region-ocr-open".data(using: .utf8))
        let controller = makeController(
            screenshotService: FakeScreenshotService(
                mainDisplayResult: .success(Data()),
                selectedRegionResult: .success(
                    ScreenshotCaptureOutput(data: data, completion: .recognizeText)
                )
            ),
            ocrProvider: { _ in OCRResult(text: "from region", confidence: nil) }
        )
        var recordedItemCounts: [Int] = []
        controller.ocrCaptureDidRecord = {
            recordedItemCounts.append(controller.history.items.count)
        }

        await controller.captureSelectedRegion()

        #expect(recordedItemCounts == [1])
        #expect(controller.history.items.first?.data == data)
    }

    @Test func recognizeTextCompletionWithoutOCRServiceStillRecordsImage() async throws {
        let data = try #require("region-no-ocr".data(using: .utf8))
        let controller = ScreenshotController(
            screenshotService: FakeScreenshotService(
                mainDisplayResult: .success(Data()),
                selectedRegionResult: .success(
                    ScreenshotCaptureOutput(data: data, completion: .recognizeText)
                )
            ),
            pasteboard: FakeScreenshotPasteboardService(),
            fileSaver: FakeScreenshotFileSaver()
        )

        await controller.captureSelectedRegion()

        // 没有 OCRService 时，图仍入历史，只是不做识别。
        #expect(controller.history.items.map(\.data) == [data])
        #expect(controller.history.items.first?.recognizedText == nil)
    }

    private func makeController(
        screenshotService: ScreenshotService,
        pasteboard: ScreenshotPasteboardService = FakeScreenshotPasteboardService(),
        ocrProvider: @escaping @Sendable (Data) async throws -> OCRResult
    ) -> ScreenshotController {
        ScreenshotController(
            screenshotService: screenshotService,
            pasteboard: pasteboard,
            fileSaver: FakeScreenshotFileSaver(),
            ocrService: OCRService(provider: ClosureOCRProvider(body: ocrProvider))
        )
    }
}

private struct ClosureOCRProvider: OCRProvider {
    let body: @Sendable (Data) async throws -> OCRResult

    func recognize(textIn data: Data) async throws -> OCRResult {
        try await body(data)
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

    func captureSelectedRegion(initialMode: ScreenshotRegionCaptureMode) async throws -> ScreenshotCaptureOutput {
        ScreenshotCaptureOutput(data: try await delayedData(), completion: .copy)
    }

    private func delayedData() async throws -> Data {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return data
    }
}

private final class FakeScreenshotService: ScreenshotService, @unchecked Sendable {
    let mainDisplayResult: Result<Data, Error>
    let selectedRegionResult: Result<ScreenshotCaptureOutput, Error>
    let permissionResult: Result<Void, Error>
    private(set) var ensurePermissionCallCount = 0
    private(set) var selectedRegionInitialModes: [ScreenshotRegionCaptureMode] = []

    init(
        mainDisplayResult: Result<Data, Error>,
        selectedRegionResult: Result<ScreenshotCaptureOutput, Error>,
        permissionResult: Result<Void, Error> = .success(())
    ) {
        self.mainDisplayResult = mainDisplayResult
        self.selectedRegionResult = selectedRegionResult
        self.permissionResult = permissionResult
    }

    func ensureScreenCaptureAccess() async throws {
        ensurePermissionCallCount += 1
        try permissionResult.get()
    }

    func captureMainDisplay() async throws -> Data {
        try mainDisplayResult.get()
    }

    func captureSelectedRegion(initialMode: ScreenshotRegionCaptureMode) async throws -> ScreenshotCaptureOutput {
        selectedRegionInitialModes.append(initialMode)
        return try selectedRegionResult.get()
    }
}

private final class FakeScreenRecordingService: ScreenRecordingService, @unchecked Sendable {
    private let session: ScreenRecordingSession
    private(set) var startCallCount = 0
    private(set) var selectedRects: [CGRect] = []
    private(set) var excludedWindowIDs: [Set<CGWindowID>] = []

    init(session: ScreenRecordingSession) {
        self.session = session
    }

    func startSelectedRegionRecording() async throws -> ScreenRecordingSession {
        startCallCount += 1
        return session
    }

    func startRecording(
        in selectedRect: CGRect,
        excludingWindowIDs: Set<CGWindowID>
    ) async throws -> ScreenRecordingSession {
        selectedRects.append(selectedRect)
        self.excludedWindowIDs.append(excludingWindowIDs)
        return session
    }
}

private final class FakeScreenRecordingSession: ScreenRecordingSession, @unchecked Sendable {
    let startedAt: Date
    private let output: ScreenRecordingOutput
    private(set) var stopCallCount = 0
    private(set) var cancelCallCount = 0

    init(output: ScreenRecordingOutput) {
        self.output = output
        self.startedAt = output.createdAt
    }

    func stop() async throws -> ScreenRecordingOutput {
        stopCallCount += 1
        return output
    }

    func cancel() async {
        cancelCallCount += 1
    }
}

private final class FakeScreenRecordingRegionOverlayFactory {
    private(set) var overlays: [FakeScreenRecordingRegionOverlay] = []

    func make(_ recordingRect: CGRect) -> ScreenRecordingRegionOverlayPresenting {
        let overlay = FakeScreenRecordingRegionOverlay(recordingRect: recordingRect)
        overlays.append(overlay)
        return overlay
    }
}

private final class FakeScreenRecordingRegionOverlay: ScreenRecordingRegionOverlayPresenting {
    let recordingRect: CGRect
    private(set) var showCallCount = 0
    private(set) var closeCallCount = 0
    var excludedWindowIDs: Set<CGWindowID> {
        showCallCount > 0 ? [101] : []
    }

    init(recordingRect: CGRect) {
        self.recordingRect = recordingRect
    }

    func show() {
        showCallCount += 1
    }

    func close() {
        closeCallCount += 1
    }
}

private final class FakeScreenshotPasteboardService: ScreenshotPasteboardService {
    private(set) var copiedData: Data?
    private(set) var copiedString: String?
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

    func writeString(_ string: String) {
        copiedString = string
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
