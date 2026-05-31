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
            TranslationProviderDescriptor.google.id,
            TranslationProviderDescriptor.openAICompatible.id
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

    @Test func persistsOpenAICompatibleConfiguration() {
        let defaults = makeDefaults()
        let secretStore = CapturingTranslationSecretStore()
        var preferences = TranslationPreferences(defaults: defaults, secretStore: secretStore)

        preferences.updateOpenAICompatibleConfiguration(
            OpenAICompatibleTranslationConfiguration(
                baseURL: "https://api.deepseek.com/v1",
                apiKey: "test-key",
                model: "deepseek-chat"
            )
        )
        preferences = TranslationPreferences(defaults: defaults, secretStore: secretStore)

        #expect(preferences.openAICompatibleConfiguration.baseURL == "https://api.deepseek.com/v1")
        #expect(preferences.openAICompatibleConfiguration.apiKey == "test-key")
        #expect(preferences.openAICompatibleConfiguration.model == "deepseek-chat")
        #expect(defaults.string(forKey: "tran.openAICompatible.apiKey") == nil)
    }
}

private func makeDefaults() -> UserDefaults {
    let suiteName = "TranslationPreferencesTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private final class CapturingTranslationSecretStore: TranslationSecretStore {
    private var apiKey = ""

    func openAICompatibleAPIKey() -> String {
        apiKey
    }

    func updateOpenAICompatibleAPIKey(_ apiKey: String) {
        self.apiKey = apiKey
    }
}
