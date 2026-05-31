import Foundation

@Observable
final class TranslationPreferences {
    private let defaults: UserDefaults
    private let secretStore: TranslationSecretStore
    private let defaultSourceLanguageKey = "tran.defaultSourceLanguageCode"
    private let hasUserSelectedDefaultSourceLanguageKey = "tran.hasUserSelectedDefaultSourceLanguage"
    private let defaultTargetLanguageKey = "tran.defaultTargetLanguageCode"
    private let hasUserSelectedDefaultTargetLanguageKey = "tran.hasUserSelectedDefaultTargetLanguage"
    private let enabledProviderIDsKey = "tran.enabledProviderIDs"
    private let openAICompatibleBaseURLKey = "tran.openAICompatible.baseURL"
    private let openAICompatibleModelKey = "tran.openAICompatible.model"

    private(set) var defaultSourceLanguageCode: String?
    private(set) var defaultTargetLanguageCode: String
    private(set) var enabledProviderIDs: [String]
    private(set) var openAICompatibleConfiguration: OpenAICompatibleTranslationConfiguration

    init(
        defaults: UserDefaults = .standard,
        secretStore: TranslationSecretStore = KeychainTranslationSecretStore(),
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        self.defaults = defaults
        self.secretStore = secretStore

        let storedSourceCode = defaults.string(forKey: defaultSourceLanguageKey)
        let hasUserSelectedDefaultSourceLanguage = defaults.bool(
            forKey: hasUserSelectedDefaultSourceLanguageKey
        )
        let hasLegacyUnmarkedSourceLanguage = storedSourceCode != nil
            && !hasUserSelectedDefaultSourceLanguage
        if hasUserSelectedDefaultSourceLanguage,
           let storedSourceCode,
           TranslationLanguage.isSupportedSource(storedSourceCode) {
            self.defaultSourceLanguageCode = storedSourceCode
        } else {
            self.defaultSourceLanguageCode = nil
            defaults.removeObject(forKey: defaultSourceLanguageKey)
            defaults.set(false, forKey: hasUserSelectedDefaultSourceLanguageKey)
        }

        let hasUserSelectedDefaultTargetLanguage = defaults.bool(
            forKey: hasUserSelectedDefaultTargetLanguageKey
        ) && !hasLegacyUnmarkedSourceLanguage
        let storedCode = defaults.string(forKey: defaultTargetLanguageKey)
        if hasUserSelectedDefaultTargetLanguage,
           let storedCode,
           TranslationLanguage.isSupported(storedCode) {
            self.defaultTargetLanguageCode = storedCode
        } else {
            let defaultTargetLanguageCode = TranslationLanguage.bestTargetCode(
                forPreferredLanguages: preferredLanguages
            )
            self.defaultTargetLanguageCode = defaultTargetLanguageCode
            defaults.set(defaultTargetLanguageCode, forKey: defaultTargetLanguageKey)
            defaults.set(false, forKey: hasUserSelectedDefaultTargetLanguageKey)
        }

        let storedProviderIDs = defaults.stringArray(forKey: enabledProviderIDsKey) ?? []
        let knownProviderIDs = Set(TranslationProviderDescriptor.builtIn.map(\.id))
        let validProviderIDs = storedProviderIDs.filter { knownProviderIDs.contains($0) }
        if validProviderIDs.isEmpty {
            let enabledProviderIDs = Self.defaultEnabledProviderIDs
            self.enabledProviderIDs = enabledProviderIDs
            defaults.set(enabledProviderIDs, forKey: enabledProviderIDsKey)
        } else {
            self.enabledProviderIDs = validProviderIDs
            if validProviderIDs != storedProviderIDs {
                defaults.set(validProviderIDs, forKey: enabledProviderIDsKey)
            }
        }

        self.openAICompatibleConfiguration = OpenAICompatibleTranslationConfiguration(
            baseURL: defaults.string(forKey: openAICompatibleBaseURLKey)
                ?? OpenAICompatibleTranslationConfiguration.defaultBaseURL,
            apiKey: secretStore.openAICompatibleAPIKey(),
            model: defaults.string(forKey: openAICompatibleModelKey)
                ?? OpenAICompatibleTranslationConfiguration.defaultModel
        )
    }

    func updateDefaultSourceLanguage(_ code: String?) {
        guard let code else {
            defaultSourceLanguageCode = nil
            defaults.removeObject(forKey: defaultSourceLanguageKey)
            defaults.set(false, forKey: hasUserSelectedDefaultSourceLanguageKey)
            return
        }

        guard TranslationLanguage.isSupportedSource(code) else {
            return
        }

        defaultSourceLanguageCode = code
        defaults.set(code, forKey: defaultSourceLanguageKey)
        defaults.set(true, forKey: hasUserSelectedDefaultSourceLanguageKey)
    }

    func updateDefaultTargetLanguage(_ code: String) {
        guard TranslationLanguage.isSupported(code) else {
            return
        }

        defaultTargetLanguageCode = code
        defaults.set(code, forKey: defaultTargetLanguageKey)
        defaults.set(true, forKey: hasUserSelectedDefaultTargetLanguageKey)
    }

    func updateEnabledProvider(_ providerID: String, isEnabled: Bool) {
        let knownProviderIDs = TranslationProviderDescriptor.builtIn.map(\.id)
        guard knownProviderIDs.contains(providerID) else {
            return
        }

        var nextProviderIDs = enabledProviderIDs
        if isEnabled {
            guard !nextProviderIDs.contains(providerID) else {
                return
            }

            nextProviderIDs.append(providerID)
            nextProviderIDs.sort { first, second in
                knownProviderIDs.firstIndex(of: first) ?? 0
                    < knownProviderIDs.firstIndex(of: second) ?? 0
            }
        } else {
            nextProviderIDs.removeAll { $0 == providerID }
            guard !nextProviderIDs.isEmpty else {
                return
            }
        }

        enabledProviderIDs = nextProviderIDs
        defaults.set(enabledProviderIDs, forKey: enabledProviderIDsKey)
    }

    func updateOpenAICompatibleConfiguration(_ configuration: OpenAICompatibleTranslationConfiguration) {
        openAICompatibleConfiguration = configuration
        defaults.set(configuration.baseURL, forKey: openAICompatibleBaseURLKey)
        defaults.set(configuration.model, forKey: openAICompatibleModelKey)
        secretStore.updateOpenAICompatibleAPIKey(configuration.apiKey)
    }

    private static let defaultEnabledProviderIDs = [
        TranslationProviderDescriptor.systemTranslation.id
    ]
}
