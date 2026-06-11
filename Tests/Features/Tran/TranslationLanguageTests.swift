import Testing
@testable import ClipPixTran

struct TranslationLanguageTests {
    @Test func detectsShortEnglishWordsBeforeStatisticalRecognition() {
        let detector = NaturalLanguageTranslationLanguageDetector()

        #expect(
            detector.detect("translate", threshold: 0.3, preferredSourceHints: nil).languageCode == "en"
        )
        #expect(
            detector.detect("Cover", threshold: 0.3, preferredSourceHints: nil).languageCode == "en"
        )
    }

    @Test func shortEnglishFallbackDoesNotOverrideCommonGermanOrFrenchWords() {
        let detector = NaturalLanguageTranslationLanguageDetector()

        #expect(
            detector.detect("danke", threshold: 0.3, preferredSourceHints: nil).languageCode != "en"
        )
        #expect(
            detector.detect("merci", threshold: 0.3, preferredSourceHints: nil).languageCode != "en"
        )
    }

    @Test func deterministicDetectionHandlesCJKAndKanaScripts() {
        let detector = NaturalLanguageTranslationLanguageDetector()

        #expect(
            detector.detect("你好", threshold: 0.3, preferredSourceHints: nil).languageCode == "zh-Hans"
        )
        #expect(
            detector.detect("こんにちは", threshold: 0.3, preferredSourceHints: nil).languageCode == "ja"
        )
        #expect(
            detector.detect("안녕하세요", threshold: 0.3, preferredSourceHints: nil).languageCode == "ko"
        )
    }

    @Test func matchesRegionSpecificPreferredLanguage() {
        #expect(
            TranslationLanguage.bestTargetCode(
                forPreferredLanguages: ["en-US"]
            ) == "en"
        )
    }

    @Test func matchesSimplifiedChineseIdentifierWithUnderscores() {
        #expect(
            TranslationLanguage.bestTargetCode(
                forPreferredLanguages: ["zh_Hans_CN"]
            ) == "zh-Hans"
        )
    }

    @Test func skipsUnsupportedPreferredLanguages() {
        #expect(
            TranslationLanguage.bestTargetCode(
                forPreferredLanguages: ["es-ES", "ko-KR"]
            ) == "ko"
        )
    }

    @Test func fallsBackToDefaultTargetWhenNoPreferredLanguageIsSupported() {
        #expect(
            TranslationLanguage.bestTargetCode(
                forPreferredLanguages: ["es-ES"]
            ) == TranslationLanguage.defaultTarget.code
        )
    }

    @Test func nameForUnknownLanguageReturnsCode() {
        #expect(TranslationLanguage.name(for: "es") == "es")
    }

    @Test func nameForSourceOnlyLanguageReturnsDisplayName() {
        #expect(TranslationLanguage.name(for: "zh-Hant") == L10n.languageZhHant)
    }

    @Test func supportCheckDistinguishesKnownAndUnknownCodes() {
        #expect(TranslationLanguage.isSupported("ja"))
        #expect(!TranslationLanguage.isSupported("es"))
    }
}
