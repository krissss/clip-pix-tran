import Testing
@testable import ClipPixTran

struct TranslationLanguageTests {
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
        #expect(TranslationLanguage.name(for: "zh-Hant") == "繁体中文")
    }

    @Test func supportCheckDistinguishesKnownAndUnknownCodes() {
        #expect(TranslationLanguage.isSupported("ja"))
        #expect(!TranslationLanguage.isSupported("es"))
    }
}
