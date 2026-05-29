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
        #expect(controller.history.items.first?.detectedSourceLanguageCode == "en")
        #expect(controller.history.items.first?.providerID == TranslationProviderDescriptor.systemTranslation.id)
        #expect(controller.history.items.first?.targetLanguageCode == "zh-Hans")
        #expect(controller.lastErrorMessage == nil)
    }

    @Test func translateUsesSelectedSourceLanguage() async throws {
        let service = CapturingTranslationService(
            result: TranslationResult(
                translatedText: "Hallo",
                sourceLanguageCode: "de",
                targetLanguageCode: "en"
            )
        )
        let controller = TranslationController(
            translationService: service,
            pasteboard: CapturingClipboardService()
        )
        controller.sourceText = "hallo"
        controller.selectSourceLanguage("de")
        controller.selectTargetLanguage("en")

        await controller.translate()

        let request = try #require(service.requests.first)
        #expect(request.sourceLanguageCode == "de")
        #expect(request.targetLanguageCode == "en")
        #expect(controller.history.items.first?.sourceLanguageCode == "de")
        #expect(controller.history.items.first?.detectedSourceLanguageCode == "de")
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

    @Test func selectingTargetLanguageClearsExistingResults() {
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
        controller.translatedText = "你好"

        controller.selectTargetLanguage("ja")

        #expect(controller.targetLanguageCode == "ja")
        #expect(controller.translatedText.isEmpty)
        #expect(controller.activeProviderStates.allSatisfy { state in
            if case .idle = state.status {
                return state.result == nil
            }

            return false
        })
    }

    @Test func selectingSourceLanguageUpdatesPreferences() {
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

        controller.selectSourceLanguage("ja")

        #expect(controller.sourceLanguageCode == "ja")
        #expect(preferences.defaultSourceLanguageCode == "ja")
    }

    @Test func selectingSourceLanguageClearsExistingResults() {
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
        controller.translatedText = "你好"

        controller.selectSourceLanguage("en")

        #expect(controller.sourceLanguageCode == "en")
        #expect(controller.translatedText.isEmpty)
    }

    @Test func selectingAutomaticSourceLanguageUpdatesPreferences() {
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
        controller.selectSourceLanguage("ja")

        controller.selectSourceLanguage(nil)

        #expect(controller.sourceLanguageCode == nil)
        #expect(preferences.defaultSourceLanguageCode == nil)
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
        #expect(controller.sourceLanguageCode == nil)
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

    @Test func translatesWithEnabledProvidersAndRecordsEachProvider() async {
        let providers = [
            TranslationProvider(
                descriptor: .systemTranslation,
                service: FakeTranslationService(
                    result: .success(
                        TranslationResult(
                            translatedText: "你好",
                            sourceLanguageCode: "en",
                            targetLanguageCode: "zh-Hans"
                        )
                    )
                )
            ),
            TranslationProvider(
                descriptor: .localDictionary,
                service: FakeTranslationService(
                    result: .success(
                        TranslationResult(
                            translatedText: "您好",
                            sourceLanguageCode: "en",
                            targetLanguageCode: "zh-Hans"
                        )
                    )
                )
            )
        ]
        let controller = TranslationController(
            preferences: TranslationPreferences(defaults: makeDefaults()),
            providers: providers,
            pasteboard: CapturingClipboardService()
        )
        controller.sourceText = "hello"

        await controller.translate()

        #expect(controller.activeProviderStates.count == 2)
        #expect(controller.history.items.map(\.providerID) == [
            TranslationProviderDescriptor.localDictionary.id,
            TranslationProviderDescriptor.systemTranslation.id
        ])
    }

    @Test func providerFailureDoesNotBlockOtherProviders() async {
        let providers = [
            TranslationProvider(
                descriptor: .systemTranslation,
                service: FakeTranslationService(result: .failure(FakeTranslationError.failed))
            ),
            TranslationProvider(
                descriptor: .localDictionary,
                service: FakeTranslationService(
                    result: .success(
                        TranslationResult(
                            translatedText: "你好",
                            sourceLanguageCode: "en",
                            targetLanguageCode: "zh-Hans"
                        )
                    )
                )
            )
        ]
        let controller = TranslationController(
            preferences: TranslationPreferences(defaults: makeDefaults()),
            providers: providers,
            pasteboard: CapturingClipboardService()
        )
        controller.sourceText = "hello"

        await controller.translate()

        #expect(controller.lastErrorMessage == nil)
        #expect(controller.translatedText == "你好")
        #expect(controller.history.items.count == 1)
    }

    @Test func reenabledProviderReturnsToIdleState() {
        let preferences = TranslationPreferences(defaults: makeDefaults())
        let controller = TranslationController(
            preferences: preferences,
            providers: [
                TranslationProvider(
                    descriptor: .systemTranslation,
                    service: FakeTranslationService(
                        result: .success(
                            TranslationResult(
                                translatedText: "unused",
                                sourceLanguageCode: nil,
                                targetLanguageCode: "zh-Hans"
                            )
                        )
                    )
                ),
                TranslationProvider(
                    descriptor: .localDictionary,
                    service: FakeTranslationService(
                        result: .success(
                            TranslationResult(
                                translatedText: "unused",
                                sourceLanguageCode: nil,
                                targetLanguageCode: "zh-Hans"
                            )
                        )
                    )
                )
            ],
            pasteboard: CapturingClipboardService()
        )

        controller.setProvider(TranslationProviderDescriptor.localDictionary.id, isEnabled: false)
        controller.setProvider(TranslationProviderDescriptor.localDictionary.id, isEnabled: true)

        let localDictionaryState = controller.activeProviderStates.first {
            $0.provider.id == TranslationProviderDescriptor.localDictionary.id
        }
        #expect(localDictionaryState != nil)
        if case .idle(let message) = localDictionaryState?.status {
            #expect(message == "输入文本后点击翻译，结果会显示在这里。")
        } else {
            Issue.record("Expected re-enabled provider to be idle.")
        }
    }

    @Test func historyItemFromDisabledProviderStaysVisible() {
        let preferences = TranslationPreferences(defaults: makeDefaults())
        preferences.updateEnabledProvider(TranslationProviderDescriptor.localDictionary.id, isEnabled: false)
        let controller = TranslationController(
            preferences: preferences,
            providers: [
                TranslationProvider(
                    descriptor: .systemTranslation,
                    service: FakeTranslationService(
                        result: .success(
                            TranslationResult(
                                translatedText: "unused",
                                sourceLanguageCode: nil,
                                targetLanguageCode: "zh-Hans"
                            )
                        )
                    )
                ),
                TranslationProvider(
                    descriptor: .localDictionary,
                    service: FakeTranslationService(
                        result: .success(
                            TranslationResult(
                                translatedText: "unused",
                                sourceLanguageCode: nil,
                                targetLanguageCode: "zh-Hans"
                            )
                        )
                    )
                )
            ],
            pasteboard: CapturingClipboardService()
        )
        let item = TranslationHistoryItem(
            sourceText: "hello",
            translatedText: "您好",
            targetLanguageCode: "zh-Hans",
            providerID: TranslationProviderDescriptor.localDictionary.id,
            providerName: TranslationProviderDescriptor.localDictionary.name
        )

        controller.useHistoryItem(item)

        #expect(controller.translatedText == "您好")
        #expect(controller.activeProviderStates.contains {
            $0.provider.id == TranslationProviderDescriptor.localDictionary.id
                && $0.translatedText == "您好"
        })
    }

    @Test func copiesSourceToPasteboard() {
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
        controller.sourceText = "hello"

        controller.copySourceToPasteboard()

        #expect(pasteboard.text == "hello")
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

private final class CapturingTranslationService: TranslationService {
    let result: TranslationResult
    private(set) var requests: [TranslationRequest] = []

    init(result: TranslationResult) {
        self.result = result
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        requests.append(request)
        return result
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
