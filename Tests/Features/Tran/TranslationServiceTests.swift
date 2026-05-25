import Foundation
import Testing
import Translation
@testable import ClipPixTran

@MainActor
struct TranslationServiceTests {
    @Test func fallbackTranslatesHelloToSimplifiedChinese() async throws {
        let service = FallbackTranslationService()

        let result = try await service.translate(
            TranslationRequest(
                sourceText: "hello",
                targetLanguageCode: "zh-Hans",
                sourceLanguageCode: "en"
            )
        )

        #expect(result.translatedText == "你好")
        #expect(result.targetLanguageCode == "zh-Hans")
    }

    @Test func fallbackTranslatesHelloToOtherSupportedLanguages() async throws {
        let service = FallbackTranslationService()

        let japanese = try await service.translate(
            TranslationRequest(
                sourceText: "hello",
                targetLanguageCode: "ja",
                sourceLanguageCode: "en"
            )
        )
        let english = try await service.translate(
            TranslationRequest(
                sourceText: "hello",
                targetLanguageCode: "en",
                sourceLanguageCode: "zh-Hans"
            )
        )

        #expect(japanese.translatedText == "こんにちは")
        #expect(english.translatedText == "Hello")
    }

    @Test func fallbackDoesNotTreatMatchingTextAsUnavailable() async throws {
        let service = FallbackTranslationService()

        let result = try await service.translate(
            TranslationRequest(
                sourceText: "Hello",
                targetLanguageCode: "en",
                sourceLanguageCode: "zh-Hans"
            )
        )

        #expect(result.translatedText == "Hello")
        #expect(result.targetLanguageCode == "en")
    }

    @Test func fallbackReportsUnavailableForUnknownText() async {
        let service = FallbackTranslationService()

        await #expect(throws: TranslationProviderError.unavailable) {
            try await service.translate(
                TranslationRequest(
                    sourceText: "a phrase that is not in the local fallback dictionary",
                    targetLanguageCode: "zh-Hans",
                    sourceLanguageCode: "en"
                )
            )
        }
    }

    @Test func hybridUsesFallbackWhenPrimaryFails() async throws {
        let service = HybridTranslationService(
            primary: FailingTranslationService(),
            fallback: FallbackTranslationService()
        )

        let result = try await service.translate(
            TranslationRequest(
                sourceText: "hello",
                targetLanguageCode: "zh-Hans",
                sourceLanguageCode: "en"
            )
        )

        #expect(result.translatedText == "你好")
    }

    @Test func systemUsesInstalledLanguagePairForDetectedSource() async throws {
        let service = SystemTranslationService(
            availabilityStatus: { source, target in
                source.languageCode?.identifier == "en"
                    && target?.languageCode?.identifier == "zh"
                    ? .installed
                    : .unsupported
            },
            installedTranslator: { source, target, sourceText, targetLanguageCode in
                TranslationResult(
                    translatedText: "\(sourceText)-translated",
                    sourceLanguageCode: source.languageCode?.identifier,
                    targetLanguageCode: targetLanguageCode
                )
            }
        )

        let result = try await service.translate(
            TranslationRequest(
                sourceText: "hello",
                targetLanguageCode: "zh-Hans",
                sourceLanguageCode: nil
            )
        )

        #expect(result.translatedText == "hello-translated")
        #expect(result.sourceLanguageCode == "en")
        #expect(result.targetLanguageCode == "zh-Hans")
    }

    @Test func systemRejectsSupportedButUninstalledLanguagePair() async {
        let service = SystemTranslationService(
            availabilityStatus: { _, _ in .supported },
            installedTranslator: { _, _, _, _ in
                throw UnexpectedTranslationCallError()
            }
        )

        await #expect(throws: TranslationProviderError.unavailable) {
            try await service.translate(
                TranslationRequest(
                    sourceText: "hello",
                    targetLanguageCode: "zh-Hans",
                    sourceLanguageCode: "en"
                )
            )
        }
    }
}

private struct FailingTranslationService: TranslationService {
    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        throw TranslationProviderError.unavailable
    }
}

private struct UnexpectedTranslationCallError: Error {}
