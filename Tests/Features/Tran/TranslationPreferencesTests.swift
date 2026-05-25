import Foundation
import Testing
@testable import ClipPixTran

@MainActor
struct TranslationPreferencesTests {
    @Test func defaultsToSimplifiedChinese() {
        let preferences = TranslationPreferences(
            defaults: makeDefaults(),
            preferredLanguages: []
        )

        #expect(preferences.defaultTargetLanguageCode == "zh-Hans")
    }

    @Test func defaultsToSupportedSystemPreferredLanguage() {
        let preferences = TranslationPreferences(
            defaults: makeDefaults(),
            preferredLanguages: ["ja-JP", "en-US"]
        )

        #expect(preferences.defaultTargetLanguageCode == "ja")
    }

    @Test func matchesSimplifiedChineseSystemLanguage() {
        let preferences = TranslationPreferences(
            defaults: makeDefaults(),
            preferredLanguages: ["zh-Hans-CN"]
        )

        #expect(preferences.defaultTargetLanguageCode == "zh-Hans")
    }

    @Test func persistsDefaultTargetLanguage() {
        let defaults = makeDefaults()
        var preferences = TranslationPreferences(defaults: defaults)

        preferences.updateDefaultTargetLanguage("ja")
        preferences = TranslationPreferences(defaults: defaults)

        #expect(preferences.defaultTargetLanguageCode == "ja")
    }

    @Test func ignoresLegacyStoredLanguageWithoutExplicitSelectionMarker() {
        let defaults = makeDefaults()
        defaults.set("ja", forKey: "tran.defaultTargetLanguageCode")

        let preferences = TranslationPreferences(
            defaults: defaults,
            preferredLanguages: ["zh-Hans-CN"]
        )

        #expect(preferences.defaultTargetLanguageCode == "zh-Hans")
        #expect(defaults.string(forKey: "tran.defaultTargetLanguageCode") == "zh-Hans")
        #expect(defaults.bool(forKey: "tran.hasUserSelectedDefaultTargetLanguage") == false)
    }

    @Test func respectsExplicitStoredLanguage() {
        let defaults = makeDefaults()
        defaults.set("ja", forKey: "tran.defaultTargetLanguageCode")
        defaults.set(true, forKey: "tran.hasUserSelectedDefaultTargetLanguage")

        let preferences = TranslationPreferences(
            defaults: defaults,
            preferredLanguages: ["zh-Hans-CN"]
        )

        #expect(preferences.defaultTargetLanguageCode == "ja")
    }

    @Test func ignoresUnsupportedStoredLanguage() {
        let defaults = makeDefaults()
        defaults.set("unknown", forKey: "tran.defaultTargetLanguageCode")

        let preferences = TranslationPreferences(
            defaults: defaults,
            preferredLanguages: []
        )

        #expect(preferences.defaultTargetLanguageCode == "zh-Hans")
        #expect(defaults.bool(forKey: "tran.hasUserSelectedDefaultTargetLanguage") == false)
    }
}

private func makeDefaults() -> UserDefaults {
    let suiteName = "TranslationPreferencesTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
