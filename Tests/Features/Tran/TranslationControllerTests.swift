import Foundation
import Testing
@testable import ClipPixTran

@MainActor
struct TranslationControllerTests {
    @Test func translateRecordsResult() async {
        let preferences = TranslationPreferences(defaults: makeDefaults())
        let controller = TranslationController(
            preferences: preferences,
            translationService: FallbackTranslationService(),
            pasteboard: CapturingClipboardService()
        )
        controller.sourceText = " hello "
        controller.lastErrorMessage = "旧错误"

        await controller.translate()

        #expect(controller.translatedText == "你好")
        #expect(controller.history.items.map(\.sourceText) == ["hello"])
        #expect(controller.history.items.first?.targetLanguageCode == "zh-Hans")
        #expect(controller.lastErrorMessage == nil)
    }

    @Test func emptySourceShowsValidationError() async {
        let controller = TranslationController(
            translationService: FakeTranslationService(
                result: .success(
                    TranslationResult(
                        translatedText: "unused",
                        sourceLanguageCode: nil,
                        targetLanguageCode: "zh-Hans"
                    )
                )
            ),
            pasteboard: CapturingClipboardService()
        )

        await controller.translate()

        #expect(controller.lastErrorMessage == TranslationValidationError.emptySource.localizedDescription)
        #expect(controller.history.items.isEmpty)
    }

    @Test func translateFailureShowsError() async {
        let controller = TranslationController(
            translationService: FakeTranslationService(
                result: .failure(FakeTranslationError.failed)
            ),
            pasteboard: CapturingClipboardService()
        )
        controller.sourceText = "hello"

        await controller.translate()

        #expect(controller.lastErrorMessage == FakeTranslationError.failed.localizedDescription)
        #expect(controller.history.items.isEmpty)
    }

    @Test func copiesResultToPasteboard() throws {
        let pasteboard = CapturingClipboardService()
        let controller = TranslationController(
            translationService: FakeTranslationService(
                result: .success(
                    TranslationResult(
                        translatedText: "你好",
                        sourceLanguageCode: "en",
                        targetLanguageCode: "zh-Hans"
                    )
                )
            ),
            pasteboard: pasteboard
        )
        controller.translatedText = "你好"

        controller.copyResultToPasteboard()

        #expect(pasteboard.text == "你好")
        #expect(controller.lastErrorMessage == nil)
    }

    @Test func emptyResultIsNotCopiedToPasteboard() {
        let pasteboard = CapturingClipboardService()
        let controller = TranslationController(
            translationService: FakeTranslationService(
                result: .success(
                    TranslationResult(
                        translatedText: "unused",
                        sourceLanguageCode: nil,
                        targetLanguageCode: "zh-Hans"
                    )
                )
            ),
            pasteboard: pasteboard
        )
        controller.translatedText = "   \n\t   "

        controller.copyResultToPasteboard()

        #expect(pasteboard.text == nil)
    }

    @Test func copyFailureSetsErrorMessage() {
        let pasteboard = CapturingClipboardService(error: ClipboardWriteError.rejected)
        let controller = TranslationController(
            translationService: FakeTranslationService(
                result: .success(
                    TranslationResult(
                        translatedText: "unused",
                        sourceLanguageCode: nil,
                        targetLanguageCode: "zh-Hans"
                    )
                )
            ),
            pasteboard: pasteboard
        )
        controller.translatedText = "你好"

        controller.copyResultToPasteboard()

        #expect(pasteboard.text == nil)
        #expect(controller.lastErrorMessage == ClipboardWriteError.rejected.localizedDescription)
    }

    @Test func loadsHistoryItemIntoEditor() {
        let controller = TranslationController(
            translationService: FakeTranslationService(
                result: .success(
                    TranslationResult(
                        translatedText: "unused",
                        sourceLanguageCode: nil,
                        targetLanguageCode: "zh-Hans"
                    )
                )
            ),
            pasteboard: CapturingClipboardService()
        )
        let item = TranslationHistoryItem(
            sourceText: "hello",
            translatedText: "こんにちは",
            targetLanguageCode: "ja"
        )

        controller.useHistoryItem(item)

        #expect(controller.sourceText == "hello")
        #expect(controller.translatedText == "こんにちは")
        #expect(controller.targetLanguageCode == "ja")
    }

    @Test func prefillSourceTextClearsPreviousResultAndError() {
        let controller = TranslationController(
            translationService: FakeTranslationService(
                result: .success(
                    TranslationResult(
                        translatedText: "unused",
                        sourceLanguageCode: nil,
                        targetLanguageCode: "zh-Hans"
                    )
                )
            ),
            pasteboard: CapturingClipboardService()
        )
        controller.sourceText = "old"
        controller.translatedText = "旧译文"
        controller.lastErrorMessage = "旧错误"

        controller.prefillSourceText("clip text")

        #expect(controller.sourceText == "clip text")
        #expect(controller.translatedText.isEmpty)
        #expect(controller.lastErrorMessage == nil)
    }

    @Test func selectingTargetLanguageUpdatesPreferences() {
        let preferences = TranslationPreferences(defaults: makeDefaults())
        let controller = TranslationController(
            preferences: preferences,
            translationService: FakeTranslationService(
                result: .success(
                    TranslationResult(
                        translatedText: "unused",
                        sourceLanguageCode: nil,
                        targetLanguageCode: "zh-Hans"
                    )
                )
            ),
            pasteboard: CapturingClipboardService()
        )

        controller.selectTargetLanguage("de")

        #expect(preferences.defaultTargetLanguageCode == "de")
    }

    @Test func selectingUnsupportedTargetLanguageDoesNotChangePreferences() {
        let preferences = TranslationPreferences(defaults: makeDefaults())
        let controller = TranslationController(
            preferences: preferences,
            translationService: FakeTranslationService(
                result: .success(
                    TranslationResult(
                        translatedText: "unused",
                        sourceLanguageCode: nil,
                        targetLanguageCode: "zh-Hans"
                    )
                )
            ),
            pasteboard: CapturingClipboardService()
        )

        controller.selectTargetLanguage("es")

        #expect(controller.targetLanguageCode == "zh-Hans")
        #expect(preferences.defaultTargetLanguageCode == "zh-Hans")
    }

    @Test func loadingHistoryItemDoesNotUpdateDefaultTargetLanguage() {
        let preferences = TranslationPreferences(
            defaults: makeDefaults(),
            preferredLanguages: ["zh-Hans-CN"]
        )
        let controller = TranslationController(
            preferences: preferences,
            translationService: FakeTranslationService(
                result: .success(
                    TranslationResult(
                        translatedText: "unused",
                        sourceLanguageCode: nil,
                        targetLanguageCode: "zh-Hans"
                    )
                )
            ),
            pasteboard: CapturingClipboardService()
        )
        let item = TranslationHistoryItem(
            sourceText: "hello",
            translatedText: "こんにちは",
            targetLanguageCode: "ja"
        )

        controller.useHistoryItem(item)

        #expect(controller.targetLanguageCode == "ja")
        #expect(preferences.defaultTargetLanguageCode == "zh-Hans")
    }

    @Test func translateWhileInProgressDoesNotStartAnotherRequest() async {
        let service = BlockingTranslationService(
            result: TranslationResult(
                translatedText: "你好",
                sourceLanguageCode: "en",
                targetLanguageCode: "zh-Hans"
            )
        )
        let controller = TranslationController(
            translationService: service,
            pasteboard: CapturingClipboardService()
        )
        controller.sourceText = "hello"

        let translateTask = Task {
            await controller.translate()
        }
        while service.requestCount == 0 {
            await Task.yield()
        }

        await controller.translate()
        service.finish()
        await translateTask.value

        #expect(service.requestCount == 1)
        #expect(controller.translatedText == "你好")
    }
}

private func makeDefaults() -> UserDefaults {
    let suiteName = "TranslationControllerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private struct FakeTranslationService: TranslationService {
    let result: Result<TranslationResult, Error>

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        try result.get()
    }
}

private enum FakeTranslationError: LocalizedError {
    case failed

    var errorDescription: String? {
        "翻译失败。"
    }
}

private final class CapturingClipboardService: ClipboardService {
    private(set) var text: String?
    var changeCount = 0
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func readItem() -> ClipboardItem? {
        text.map { ClipboardItem(text: $0) }
    }

    func writeItem(_ item: ClipboardItem) throws {
        if let error {
            throw error
        }

        text = item.text
        changeCount += 1
    }

    func readPlainText() -> String? {
        text
    }

    func writePlainText(_ text: String) throws {
        if let error {
            throw error
        }

        self.text = text
        changeCount += 1
    }
}

private final class BlockingTranslationService: TranslationService {
    private let result: TranslationResult
    private var continuation: CheckedContinuation<TranslationResult, Never>?
    private(set) var requestCount = 0

    init(result: TranslationResult) {
        self.result = result
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        requestCount += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finish() {
        continuation?.resume(returning: result)
        continuation = nil
    }
}
