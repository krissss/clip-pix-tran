import Foundation

@Observable
final class TranslationPreferences {
    private let defaults: UserDefaults

    private static let defaultSourceLanguageKey = "tran.defaultSourceLanguageCode"
    private static let hasUserSelectedDefaultSourceLanguageKey = "tran.hasUserSelectedDefaultSourceLanguage"
    private static let defaultTargetLanguageKey = "tran.defaultTargetLanguageCode"
    private static let hasUserSelectedDefaultTargetLanguageKey = "tran.hasUserSelectedDefaultTargetLanguage"
    private static let enabledProviderIDsKey = "tran.enabledProviderIDs"
    private static let speechProviderIDKey = "tran.speechProviderID"
    private static let languageDefaultsMigrationVersionKey = "tran.languageDefaultsMigrationVersion"
    private static let currentLanguageDefaultsMigrationVersion = 1

    private(set) var defaultSourceLanguageCode: String?
    private(set) var defaultTargetLanguageCode: String
    private(set) var enabledProviderIDs: [String]
    private(set) var speechProviderID: String

    init(
        defaults: UserDefaults = .standard,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        self.defaults = defaults
        Self.migrateAccidentalGermanEnglishDefaultsIfNeeded(
            defaults: defaults,
            preferredLanguages: preferredLanguages
        )

        let storedSourceCode = defaults.string(forKey: Self.defaultSourceLanguageKey)
        let hasUserSelectedDefaultSourceLanguage = defaults.bool(
            forKey: Self.hasUserSelectedDefaultSourceLanguageKey
        )
        let hasLegacyUnmarkedSourceLanguage = storedSourceCode != nil
            && !hasUserSelectedDefaultSourceLanguage
        if hasUserSelectedDefaultSourceLanguage,
           let storedSourceCode,
           TranslationLanguage.isSupportedSource(storedSourceCode) {
            self.defaultSourceLanguageCode = storedSourceCode
        } else {
            self.defaultSourceLanguageCode = nil
            defaults.removeObject(forKey: Self.defaultSourceLanguageKey)
            defaults.set(false, forKey: Self.hasUserSelectedDefaultSourceLanguageKey)
        }

        let hasUserSelectedDefaultTargetLanguage = defaults.bool(
            forKey: Self.hasUserSelectedDefaultTargetLanguageKey
        ) && !hasLegacyUnmarkedSourceLanguage
        let storedCode = defaults.string(forKey: Self.defaultTargetLanguageKey)
        if hasUserSelectedDefaultTargetLanguage,
           let storedCode,
           TranslationLanguage.isSupported(storedCode) {
            self.defaultTargetLanguageCode = storedCode
        } else {
            let defaultTargetLanguageCode = TranslationLanguage.bestTargetCode(
                forPreferredLanguages: preferredLanguages
            )
            self.defaultTargetLanguageCode = defaultTargetLanguageCode
            defaults.set(defaultTargetLanguageCode, forKey: Self.defaultTargetLanguageKey)
            defaults.set(false, forKey: Self.hasUserSelectedDefaultTargetLanguageKey)
        }

        let storedProviderIDs = defaults.stringArray(forKey: Self.enabledProviderIDsKey) ?? []
        let knownProviderIDs = Set(TranslationProviderDescriptor.builtIn.map(\.id))
        let validProviderIDs = storedProviderIDs.filter { knownProviderIDs.contains($0) }
        if validProviderIDs.isEmpty {
            let enabledProviderIDs = Self.defaultEnabledProviderIDs
            self.enabledProviderIDs = enabledProviderIDs
            defaults.set(enabledProviderIDs, forKey: Self.enabledProviderIDsKey)
        } else {
            self.enabledProviderIDs = validProviderIDs
            if validProviderIDs != storedProviderIDs {
                defaults.set(validProviderIDs, forKey: Self.enabledProviderIDsKey)
            }
        }

        let knownSpeechProviderIDs = Set(TranslationSpeechProviderDescriptor.builtIn.map(\.id))
        if let storedSpeechProviderID = defaults.string(forKey: Self.speechProviderIDKey),
           knownSpeechProviderIDs.contains(storedSpeechProviderID) {
            self.speechProviderID = storedSpeechProviderID
        } else {
            self.speechProviderID = TranslationSpeechProviderDescriptor.system.id
            defaults.set(self.speechProviderID, forKey: Self.speechProviderIDKey)
        }
    }

    func updateDefaultSourceLanguage(_ code: String?) {
        guard let code else {
            defaultSourceLanguageCode = nil
            defaults.removeObject(forKey: Self.defaultSourceLanguageKey)
            defaults.set(false, forKey: Self.hasUserSelectedDefaultSourceLanguageKey)
            return
        }

        guard TranslationLanguage.isSupportedSource(code) else {
            return
        }

        defaultSourceLanguageCode = code
        defaults.set(code, forKey: Self.defaultSourceLanguageKey)
        defaults.set(true, forKey: Self.hasUserSelectedDefaultSourceLanguageKey)
    }

    func updateDefaultTargetLanguage(_ code: String) {
        guard TranslationLanguage.isSupported(code) else {
            return
        }

        defaultTargetLanguageCode = code
        defaults.set(code, forKey: Self.defaultTargetLanguageKey)
        defaults.set(true, forKey: Self.hasUserSelectedDefaultTargetLanguageKey)
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
        defaults.set(enabledProviderIDs, forKey: Self.enabledProviderIDsKey)
    }

    func updateSpeechProvider(_ providerID: String) {
        let knownProviderIDs = TranslationSpeechProviderDescriptor.builtIn.map(\.id)
        guard knownProviderIDs.contains(providerID) else {
            return
        }

        speechProviderID = providerID
        defaults.set(providerID, forKey: Self.speechProviderIDKey)
    }

    private static func migrateAccidentalGermanEnglishDefaultsIfNeeded(
        defaults: UserDefaults,
        preferredLanguages: [String]
    ) {
        guard defaults.integer(forKey: languageDefaultsMigrationVersionKey) < currentLanguageDefaultsMigrationVersion
        else {
            return
        }

        defer {
            defaults.set(currentLanguageDefaultsMigrationVersion, forKey: languageDefaultsMigrationVersionKey)
        }

        guard defaults.bool(forKey: hasUserSelectedDefaultSourceLanguageKey),
              defaults.bool(forKey: hasUserSelectedDefaultTargetLanguageKey),
              defaults.string(forKey: defaultSourceLanguageKey) == "de",
              defaults.string(forKey: defaultTargetLanguageKey) == "en"
        else {
            return
        }

        let defaultTargetLanguageCode = TranslationLanguage.bestTargetCode(
            forPreferredLanguages: preferredLanguages
        )
        defaults.removeObject(forKey: defaultSourceLanguageKey)
        defaults.set(false, forKey: hasUserSelectedDefaultSourceLanguageKey)
        defaults.set(defaultTargetLanguageCode, forKey: defaultTargetLanguageKey)
        defaults.set(false, forKey: hasUserSelectedDefaultTargetLanguageKey)
    }

    private static let defaultEnabledProviderIDs = [
        TranslationProviderDescriptor.systemTranslation.id
    ]
}
