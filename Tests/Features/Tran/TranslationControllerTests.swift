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
        #expect(controller.history.items.first?.sourceLanguageCode == nil)
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

    @Test func autoDetectsSourceLanguageBeforeTranslation() async throws {
        let service = CapturingTranslationService(
            result: TranslationResult(
                translatedText: "你好",
                sourceLanguageCode: "en",
                targetLanguageCode: "zh-Hans"
            )
        )
        let controller = TranslationController(
            preferences: TranslationPreferences(defaults: makeDefaults()),
            translationService: service,
            pasteboard: CapturingClipboardService(),
            languageDetector: StubTranslationLanguageDetector(languageCode: "en")
        )
        controller.sourceText = "hello"

        await controller.translate()

        let request = try #require(service.requests.first)
        #expect(request.sourceLanguageCode == "en")
        #expect(request.targetLanguageCode == "zh-Hans")
        #expect(controller.effectiveSourceLanguageCode == "en")
        #expect(controller.history.items.first?.sourceLanguageCode == nil)
        #expect(controller.history.items.first?.detectedSourceLanguageCode == "en")
    }

    @Test func fixedSourceLanguageSkipsAutoDetection() async throws {
        let detector = CapturingTranslationLanguageDetector(languageCode: "zh-Hans")
        let service = CapturingTranslationService(
            result: TranslationResult(
                translatedText: "Hallo",
                sourceLanguageCode: "de",
                targetLanguageCode: "en"
            )
        )
        let controller = TranslationController(
            preferences: TranslationPreferences(defaults: makeDefaults()),
            translationService: service,
            pasteboard: CapturingClipboardService(),
            languageDetector: detector
        )
        controller.sourceText = "hallo"
        controller.selectSourceLanguage("de", persistsDefault: false)
        controller.selectTargetLanguage("en", persistsDefault: false)

        await controller.translate()

        let request = try #require(service.requests.first)
        #expect(request.sourceLanguageCode == "de")
        #expect(request.targetLanguageCode == "en")
        #expect(detector.detectedTexts.isEmpty)
    }

    @Test func unreliableAutoDetectionKeepsConfiguredTargetLanguage() async throws {
        let preferences = TranslationPreferences(defaults: makeDefaults())
        preferences.updateDefaultTargetLanguage("ja")
        let service = CapturingTranslationService(
            result: TranslationResult(
                translatedText: "translated",
                sourceLanguageCode: nil,
                targetLanguageCode: "ja"
            )
        )
        let controller = TranslationController(
            preferences: preferences,
            translationService: service,
            pasteboard: CapturingClipboardService(),
            languageDetector: StubTranslationLanguageDetector(languageCode: nil)
        )
        controller.sourceText = "???"

        await controller.translate()

        let request = try #require(service.requests.first)
        #expect(request.sourceLanguageCode == nil)
        #expect(request.targetLanguageCode == "ja")
        #expect(controller.targetLanguageCode == "ja")
        #expect(preferences.defaultTargetLanguageCode == "ja")
    }

    @Test func autoDetectionFlipsTargetWhenDetectedSourceMatchesTarget() async throws {
        let preferences = TranslationPreferences(defaults: makeDefaults())
        let service = CapturingTranslationService(
            result: TranslationResult(
                translatedText: "Hello",
                sourceLanguageCode: "zh-Hans",
                targetLanguageCode: "en"
            )
        )
        let controller = TranslationController(
            preferences: preferences,
            translationService: service,
            pasteboard: CapturingClipboardService(),
            languageDetector: StubTranslationLanguageDetector(languageCode: "zh-Hans")
        )
        controller.sourceText = "你好"

        await controller.translate()

        let request = try #require(service.requests.first)
        #expect(request.sourceLanguageCode == "zh-Hans")
        #expect(request.targetLanguageCode == "en")
        #expect(controller.targetLanguageCode == "zh-Hans")
        #expect(preferences.defaultTargetLanguageCode == "zh-Hans")
        #expect(controller.effectiveSourceLanguageCode == "zh-Hans")
        #expect(controller.history.items.first?.targetLanguageCode == "en")
    }

    @Test func emptySourceShowsValidationError() async {
        let controller = TranslationController(
            preferences: TranslationPreferences(defaults: makeDefaults()),
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

    @Test func editingSourceTextClearsPreviousResultAndUsesEditedText() async throws {
        let service = CapturingTranslationService(
            result: TranslationResult(
                translatedText: "新的译文",
                sourceLanguageCode: "en",
                targetLanguageCode: "zh-Hans"
            )
        )
        let controller = TranslationController(
            translationService: service,
            pasteboard: CapturingClipboardService()
        )
        controller.sourceText = "old"
        controller.translatedText = "旧译文"
        controller.lastErrorMessage = "旧错误"

        controller.editSourceText("new")

        #expect(controller.sourceText == "new")
        #expect(controller.translatedText.isEmpty)
        #expect(controller.lastErrorMessage == nil)

        await controller.translate()

        let request = try #require(service.requests.first)
        #expect(request.sourceText == "new")
        #expect(controller.translatedText == "新的译文")
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

    @Test func selectingMatchingTargetLanguageFlipsWhenSourceIsFixed() {
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
        controller.selectSourceLanguage("en", persistsDefault: false)

        controller.selectTargetLanguage("en", persistsDefault: false)

        #expect(controller.sourceLanguageCode == "en")
        #expect(controller.targetLanguageCode == "zh-Hans")
        #expect(preferences.defaultTargetLanguageCode == "zh-Hans")
    }

    @Test func selectingSessionTargetLanguageDoesNotUpdatePreferences() {
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

        controller.selectTargetLanguage("de", persistsDefault: false)

        #expect(controller.targetLanguageCode == "de")
        #expect(preferences.defaultTargetLanguageCode == "zh-Hans")
    }

    @Test func selectingSameTargetLanguageCanStillPersistDefault() {
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
        controller.selectTargetLanguage("de", persistsDefault: false)

        controller.selectTargetLanguage("de")

        #expect(controller.targetLanguageCode == "de")
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

    @Test func selectingSessionSourceLanguageDoesNotUpdatePreferences() {
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

        controller.selectSourceLanguage("de", persistsDefault: false)

        #expect(controller.sourceLanguageCode == "de")
        #expect(preferences.defaultSourceLanguageCode == nil)
    }

    @Test func selectingSameSourceLanguageCanStillPersistDefault() {
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
        controller.selectSourceLanguage("de", persistsDefault: false)

        controller.selectSourceLanguage("de")

        #expect(controller.sourceLanguageCode == "de")
        #expect(preferences.defaultSourceLanguageCode == "de")
    }

    @Test func selectingMatchingSourceLanguageFlipsTargetLanguage() {
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

        controller.selectSourceLanguage("zh-Hans", persistsDefault: false)

        #expect(controller.sourceLanguageCode == "zh-Hans")
        #expect(controller.targetLanguageCode == "en")
        #expect(preferences.defaultTargetLanguageCode == "zh-Hans")
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

    @Test func loadingAutoDetectedHistoryKeepsAutomaticSourceLanguage() {
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
        let item = TranslationHistoryItem(
            sourceText: "hallo",
            translatedText: "hello",
            sourceLanguageCode: nil,
            detectedSourceLanguageCode: "de",
            targetLanguageCode: "en"
        )

        controller.useHistoryItem(item)

        #expect(controller.sourceLanguageCode == nil)
        #expect(controller.effectiveSourceLanguageCode == "de")
        #expect(preferences.defaultSourceLanguageCode == nil)
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

    @Test func translatesWithEnabledProvidersAndRecordsFirstHistoryResultWithVariants() async {
        let preferences = TranslationPreferences(defaults: makeDefaults())
        preferences.updateEnabledProvider(TranslationProviderDescriptor.google.id, isEnabled: true)
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
                descriptor: .google,
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
            preferences: preferences,
            providers: providers,
            pasteboard: CapturingClipboardService()
        )
        controller.sourceText = "hello"

        await controller.translate()

        #expect(controller.activeProviderStates.count == 2)
        #expect(controller.history.items.map(\.providerID) == [
            TranslationProviderDescriptor.systemTranslation.id
        ])
        #expect(controller.history.items.first?.translatedText == "你好")
        #expect(controller.history.items.first?.providerResults.map(\.providerID) == [
            TranslationProviderDescriptor.systemTranslation.id,
            TranslationProviderDescriptor.google.id
        ])
    }

    @Test func providerFailureDoesNotBlockOtherProviders() async {
        let preferences = TranslationPreferences(defaults: makeDefaults())
        preferences.updateEnabledProvider(TranslationProviderDescriptor.google.id, isEnabled: true)
        let providers = [
            TranslationProvider(
                descriptor: .systemTranslation,
                service: FakeTranslationService(result: .failure(FakeTranslationError.failed))
            ),
            TranslationProvider(
                descriptor: .google,
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
            preferences: preferences,
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
                    descriptor: .google,
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

        controller.setProvider(TranslationProviderDescriptor.google.id, isEnabled: false)
        controller.setProvider(TranslationProviderDescriptor.google.id, isEnabled: true)

        let googleState = controller.activeProviderStates.first {
            $0.provider.id == TranslationProviderDescriptor.google.id
        }
        #expect(googleState != nil)
        if case .idle(let message) = googleState?.status {
            #expect(message == "输入文本后点击翻译，结果会显示在这里。")
        } else {
            Issue.record("Expected re-enabled provider to be idle.")
        }
    }

    @Test func historyItemFromDisabledProviderStaysVisible() {
        let preferences = TranslationPreferences(defaults: makeDefaults())
        preferences.updateEnabledProvider(TranslationProviderDescriptor.google.id, isEnabled: false)
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
                    descriptor: .google,
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
            providerID: TranslationProviderDescriptor.google.id,
            providerName: TranslationProviderDescriptor.google.name
        )

        controller.useHistoryItem(item)

        #expect(controller.translatedText == "您好")
        #expect(controller.activeProviderStates.contains {
            $0.provider.id == TranslationProviderDescriptor.google.id
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

    @Test func speaksSourceTextUsingSelectedSourceLanguage() {
        let speechService = CapturingTranslationSpeechService()
        let controller = TranslationController(
            preferences: TranslationPreferences(defaults: makeDefaults()),
            translationService: FakeTranslationService(
                result: .success(
                    TranslationResult(
                        translatedText: "unused",
                        sourceLanguageCode: nil,
                        targetLanguageCode: "zh-Hans"
                    )
                )
            ),
            pasteboard: CapturingClipboardService(),
            speechService: speechService
        )
        controller.sourceText = " hello "
        controller.selectSourceLanguage("en")

        controller.speakSourceText()

        #expect(controller.speakingTarget == .source)
        #expect(speechService.requests == [
            TranslationSpeechRequest(text: "hello", languageCode: "en")
        ])
    }

    @Test func speaksProviderTranslationUsingResultTargetLanguage() {
        let speechService = CapturingTranslationSpeechService()
        let controller = TranslationController(
            preferences: TranslationPreferences(defaults: makeDefaults()),
            translationService: FakeTranslationService(
                result: .success(
                    TranslationResult(
                        translatedText: "unused",
                        sourceLanguageCode: nil,
                        targetLanguageCode: "zh-Hans"
                    )
                )
            ),
            pasteboard: CapturingClipboardService(),
            speechService: speechService
        )
        controller.translatedText = " 你好 "

        controller.speakResult(providerID: TranslationProviderDescriptor.systemTranslation.id)

        #expect(controller.isSpeakingResult(providerID: TranslationProviderDescriptor.systemTranslation.id))
        #expect(speechService.requests == [
            TranslationSpeechRequest(text: "你好", languageCode: "zh-Hans")
        ])
    }

    @Test func speakingSameSourceAgainStopsPlayback() {
        let speechService = CapturingTranslationSpeechService()
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
            pasteboard: CapturingClipboardService(),
            speechService: speechService
        )
        controller.sourceText = "hello"

        controller.speakSourceText()
        controller.speakSourceText()

        #expect(controller.speakingTarget == nil)
        #expect(speechService.stopCount == 1)
    }

    @Test func naturalSpeechFinishClearsPlaybackState() {
        let speechService = CapturingTranslationSpeechService()
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
            pasteboard: CapturingClipboardService(),
            speechService: speechService
        )
        controller.sourceText = "hello"

        controller.speakSourceText()
        speechService.finishLatest()

        #expect(controller.speakingTarget == nil)
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

private final class CapturingTranslationSpeechService: TranslationSpeechService {
    private(set) var requests: [TranslationSpeechRequest] = []
    private var finishHandlers: [() -> Void] = []
    private(set) var stopCount = 0

    func speak(_ request: TranslationSpeechRequest, onFinish: @escaping () -> Void) {
        requests.append(request)
        finishHandlers.append(onFinish)
    }

    func stop() {
        stopCount += 1
    }

    func finishLatest() {
        finishHandlers.last?()
    }
}

private struct StubTranslationLanguageDetector: TranslationLanguageDetecting {
    let languageCode: String?

    func detect(
        _ text: String,
        threshold: Double,
        preferredSourceHints: [String: Double]?
    ) -> TranslationLanguageDetectionResult {
        TranslationLanguageDetectionResult(
            languageCode: languageCode,
            confidence: languageCode == nil ? 0 : 1,
            isReliable: languageCode != nil
        )
    }
}

private final class CapturingTranslationLanguageDetector: TranslationLanguageDetecting {
    let languageCode: String?
    private(set) var detectedTexts: [String] = []

    init(languageCode: String?) {
        self.languageCode = languageCode
    }

    func detect(
        _ text: String,
        threshold: Double,
        preferredSourceHints: [String: Double]?
    ) -> TranslationLanguageDetectionResult {
        detectedTexts.append(text)
        return TranslationLanguageDetectionResult(
            languageCode: languageCode,
            confidence: languageCode == nil ? 0 : 1,
            isReliable: languageCode != nil
        )
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
