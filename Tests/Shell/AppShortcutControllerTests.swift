import Foundation
import Testing
@testable import ClipPixTran

@MainActor
struct AppShortcutControllerTests {
    @Test func capturePermissionFailureOpensPixSection() async throws {
        let screenshotService = ShortcutFakeScreenshotService(
            permissionResult: .failure(ScreenshotCaptureError.permissionDenied)
        )
        let shortcutController = AppShortcutController(
            clipboardMonitor: ClipboardMonitor(pasteboard: ShortcutFakeClipboardService()),
            screenshotController: ScreenshotController(
                screenshotService: screenshotService,
                pasteboard: ShortcutFakeScreenshotPasteboardService(),
                fileSaver: ShortcutFakeScreenshotFileSaver()
            ),
            translationController: TranslationController(
                translationService: ShortcutFakeTranslationService(),
                pasteboard: ShortcutFakeClipboardService()
            )
        )
        var openedSections: [AppSection] = []
        shortcutController.openSection = { section in
            openedSections.append(section)
        }

        shortcutController.captureSelectedRegion()

        try await waitUntil {
            openedSections == [.pix]
        }
        #expect(openedSections == [.pix])
        #expect(screenshotService.ensurePermissionCallCount == 1)
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

private final class ShortcutFakeScreenshotService: ScreenshotService, @unchecked Sendable {
    private let permissionResult: Result<Void, Error>
    private(set) var ensurePermissionCallCount = 0

    init(permissionResult: Result<Void, Error> = .success(())) {
        self.permissionResult = permissionResult
    }

    func ensureScreenCaptureAccess() async throws {
        ensurePermissionCallCount += 1
        try permissionResult.get()
    }

    func captureMainDisplay() async throws -> Data {
        Data()
    }

    func captureSelectedRegion(initialMode: ScreenshotRegionCaptureMode) async throws -> ScreenshotCaptureOutput {
        ScreenshotCaptureOutput(data: Data(), completion: .copy)
    }
}

private final class ShortcutFakeClipboardService: ClipboardService {
    var changeCount = 0

    func readItem() -> ClipboardItem? {
        nil
    }

    func writeItem(_ item: ClipboardItem) throws {
        changeCount += 1
    }

    func readPlainText() -> String? {
        nil
    }

    func writePlainText(_ text: String) throws {
        changeCount += 1
    }
}

private final class ShortcutFakeScreenshotPasteboardService: ScreenshotPasteboardService {
    func writePNGData(_ data: Data) throws {
    }

    func writeString(_ string: String) {
    }
}

private final class ShortcutFakeScreenshotFileSaver: ScreenshotFileSaving {
    func savePNGData(_ data: Data, suggestedFileName: String) throws {
    }
}

private struct ShortcutFakeTranslationService: TranslationService {
    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        TranslationResult(
            translatedText: request.sourceText,
            sourceLanguageCode: request.sourceLanguageCode,
            targetLanguageCode: request.targetLanguageCode
        )
    }
}
