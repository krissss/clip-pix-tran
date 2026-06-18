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

    @Test func defaultsToAutomaticSourceLanguage() {
        let preferences = TranslationPreferences(defaults: makeDefaults())

        #expect(preferences.defaultSourceLanguageCode == nil)
    }

    @Test func persistsDefaultSourceLanguage() {
        let defaults = makeDefaults()
        var preferences = TranslationPreferences(defaults: defaults)

        preferences.updateDefaultSourceLanguage("en")
        preferences = TranslationPreferences(defaults: defaults)

        #expect(preferences.defaultSourceLanguageCode == "en")
        #expect(defaults.bool(forKey: "tran.hasUserSelectedDefaultSourceLanguage"))
    }

    @Test func clearingDefaultSourceLanguageRestoresAutomaticDetection() {
        let defaults = makeDefaults()
        var preferences = TranslationPreferences(defaults: defaults)
        preferences.updateDefaultSourceLanguage("ja")

        preferences.updateDefaultSourceLanguage(nil)
        preferences = TranslationPreferences(defaults: defaults)

        #expect(preferences.defaultSourceLanguageCode == nil)
    }

    @Test func ignoresLegacyStoredSourceLanguageWithoutExplicitSelectionMarker() {
        let defaults = makeDefaults()
        defaults.set("de", forKey: "tran.defaultSourceLanguageCode")

        let preferences = TranslationPreferences(defaults: defaults)

        #expect(preferences.defaultSourceLanguageCode == nil)
        #expect(defaults.string(forKey: "tran.defaultSourceLanguageCode") == nil)
        #expect(defaults.bool(forKey: "tran.hasUserSelectedDefaultSourceLanguage") == false)
    }

    @Test func respectsExplicitStoredSourceLanguage() {
        let defaults = makeDefaults()
        defaults.set("de", forKey: "tran.defaultSourceLanguageCode")
        defaults.set(true, forKey: "tran.hasUserSelectedDefaultSourceLanguage")

        let preferences = TranslationPreferences(defaults: defaults)

        #expect(preferences.defaultSourceLanguageCode == "de")
    }

    @Test func ignoresUnsupportedDefaultSourceLanguage() {
        let defaults = makeDefaults()
        defaults.set("unknown", forKey: "tran.defaultSourceLanguageCode")

        let preferences = TranslationPreferences(defaults: defaults)

        #expect(preferences.defaultSourceLanguageCode == nil)
        #expect(defaults.string(forKey: "tran.defaultSourceLanguageCode") == nil)
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

    @Test func legacyStoredSourceLanguageClearsAccidentalTargetLanguagePair() {
        let defaults = makeDefaults()
        defaults.set("de", forKey: "tran.defaultSourceLanguageCode")
        defaults.set("en", forKey: "tran.defaultTargetLanguageCode")
        defaults.set(true, forKey: "tran.hasUserSelectedDefaultTargetLanguage")

        let preferences = TranslationPreferences(
            defaults: defaults,
            preferredLanguages: ["zh-Hans-CN"]
        )

        #expect(preferences.defaultSourceLanguageCode == nil)
        #expect(preferences.defaultTargetLanguageCode == "zh-Hans")
        #expect(defaults.string(forKey: "tran.defaultSourceLanguageCode") == nil)
        #expect(defaults.string(forKey: "tran.defaultTargetLanguageCode") == "zh-Hans")
        #expect(defaults.bool(forKey: "tran.hasUserSelectedDefaultTargetLanguage") == false)
    }

    @Test func migratesAccidentalGermanEnglishDefaultPair() {
        let defaults = makeDefaults()
        defaults.set("de", forKey: "tran.defaultSourceLanguageCode")
        defaults.set("en", forKey: "tran.defaultTargetLanguageCode")
        defaults.set(true, forKey: "tran.hasUserSelectedDefaultSourceLanguage")
        defaults.set(true, forKey: "tran.hasUserSelectedDefaultTargetLanguage")

        let preferences = TranslationPreferences(
            defaults: defaults,
            preferredLanguages: ["zh-Hans-CN"]
        )

        #expect(preferences.defaultSourceLanguageCode == nil)
        #expect(preferences.defaultTargetLanguageCode == "zh-Hans")
        #expect(defaults.string(forKey: "tran.defaultSourceLanguageCode") == nil)
        #expect(defaults.string(forKey: "tran.defaultTargetLanguageCode") == "zh-Hans")
        #expect(defaults.bool(forKey: "tran.hasUserSelectedDefaultSourceLanguage") == false)
        #expect(defaults.bool(forKey: "tran.hasUserSelectedDefaultTargetLanguage") == false)
        #expect(defaults.integer(forKey: "tran.languageDefaultsMigrationVersion") == 1)
    }

    @Test func keepsGermanEnglishDefaultPairAfterLanguageDefaultsMigration() {
        let defaults = makeDefaults()
        defaults.set("de", forKey: "tran.defaultSourceLanguageCode")
        defaults.set("en", forKey: "tran.defaultTargetLanguageCode")
        defaults.set(true, forKey: "tran.hasUserSelectedDefaultSourceLanguage")
        defaults.set(true, forKey: "tran.hasUserSelectedDefaultTargetLanguage")
        defaults.set(1, forKey: "tran.languageDefaultsMigrationVersion")

        let preferences = TranslationPreferences(
            defaults: defaults,
            preferredLanguages: ["zh-Hans-CN"]
        )

        #expect(preferences.defaultSourceLanguageCode == "de")
        #expect(preferences.defaultTargetLanguageCode == "en")
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

    @Test func defaultsToAllBuiltInProvidersEnabled() {
        let preferences = TranslationPreferences(defaults: makeDefaults())

        #expect(preferences.enabledProviderIDs == [
            TranslationProviderDescriptor.systemTranslation.id
        ])
    }

    @Test func builtInProviderListIncludesExternalProviders() {
        #expect(TranslationProviderDescriptor.builtIn.map(\.id) == [
            TranslationProviderDescriptor.systemTranslation.id,
            TranslationProviderDescriptor.google.id
        ])
    }

    @Test func persistsEnabledProviders() {
        let defaults = makeDefaults()
        var preferences = TranslationPreferences(defaults: defaults)

        preferences.updateEnabledProvider(TranslationProviderDescriptor.google.id, isEnabled: true)
        preferences = TranslationPreferences(defaults: defaults)

        #expect(preferences.enabledProviderIDs == [
            TranslationProviderDescriptor.systemTranslation.id,
            TranslationProviderDescriptor.google.id
        ])
    }

    @Test func removesLegacyLocalDictionaryProviderFromStoredProviders() {
        let defaults = makeDefaults()
        defaults.set([
            TranslationProviderDescriptor.systemTranslation.id,
            "local-dictionary"
        ], forKey: "tran.enabledProviderIDs")

        let preferences = TranslationPreferences(defaults: defaults)

        #expect(preferences.enabledProviderIDs == [
            TranslationProviderDescriptor.systemTranslation.id
        ])
        #expect(defaults.stringArray(forKey: "tran.enabledProviderIDs") == [
            TranslationProviderDescriptor.systemTranslation.id
        ])
    }

    @Test func keepsAtLeastOneProviderEnabled() {
        let defaults = makeDefaults()
        let preferences = TranslationPreferences(defaults: defaults)

        preferences.updateEnabledProvider(TranslationProviderDescriptor.systemTranslation.id, isEnabled: false)

        #expect(preferences.enabledProviderIDs == [TranslationProviderDescriptor.systemTranslation.id])
    }

    @Test func defaultsToSystemSpeechProvider() {
        let preferences = TranslationPreferences(defaults: makeDefaults())

        #expect(preferences.speechProviderID == TranslationSpeechProviderDescriptor.system.id)
    }

    @Test func builtInSpeechProviderListIncludesExternalProviders() {
        #expect(TranslationSpeechProviderDescriptor.builtIn.map(\.id) == [
            TranslationSpeechProviderDescriptor.system.id,
            TranslationSpeechProviderDescriptor.google.id
        ])
    }

    @Test func persistsSpeechProvider() {
        let defaults = makeDefaults()
        var preferences = TranslationPreferences(defaults: defaults)

        preferences.updateSpeechProvider(TranslationSpeechProviderDescriptor.google.id)
        preferences = TranslationPreferences(defaults: defaults)

        #expect(preferences.speechProviderID == TranslationSpeechProviderDescriptor.google.id)
    }

    @Test func ignoresUnknownStoredSpeechProvider() {
        let defaults = makeDefaults()
        defaults.set("unknown", forKey: "tran.speechProviderID")

        let preferences = TranslationPreferences(defaults: defaults)

        #expect(preferences.speechProviderID == TranslationSpeechProviderDescriptor.system.id)
        #expect(defaults.string(forKey: "tran.speechProviderID") == TranslationSpeechProviderDescriptor.system.id)
    }

}

private func makeDefaults() -> UserDefaults {
    let suiteName = "TranslationPreferencesTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
