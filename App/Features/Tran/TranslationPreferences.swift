import Foundation

@Observable
final class TranslationPreferences {
    private let defaults: UserDefaults
    private let defaultSourceLanguageKey = "tran.defaultSourceLanguageCode"
    private let defaultTargetLanguageKey = "tran.defaultTargetLanguageCode"
    private let hasUserSelectedDefaultTargetLanguageKey = "tran.hasUserSelectedDefaultTargetLanguage"
    private let enabledProviderIDsKey = "tran.enabledProviderIDs"

    private(set) var defaultSourceLanguageCode: String?
    private(set) var defaultTargetLanguageCode: String
    private(set) var enabledProviderIDs: [String]

    init(
        defaults: UserDefaults = .standard,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        self.defaults = defaults

        let storedSourceCode = defaults.string(forKey: defaultSourceLanguageKey)
        if let storedSourceCode,
           TranslationLanguage.isSupportedSource(storedSourceCode) {
            self.defaultSourceLanguageCode = storedSourceCode
        } else {
            self.defaultSourceLanguageCode = nil
            defaults.removeObject(forKey: defaultSourceLanguageKey)
        }

        let hasUserSelectedDefaultTargetLanguage = defaults.bool(
            forKey: hasUserSelectedDefaultTargetLanguageKey
        )
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
            let enabledProviderIDs = TranslationProviderDescriptor.builtIn.map(\.id)
            self.enabledProviderIDs = enabledProviderIDs
            defaults.set(enabledProviderIDs, forKey: enabledProviderIDsKey)
        } else {
            self.enabledProviderIDs = validProviderIDs
        }
    }

    func updateDefaultSourceLanguage(_ code: String?) {
        guard let code else {
            defaultSourceLanguageCode = nil
            defaults.removeObject(forKey: defaultSourceLanguageKey)
            return
        }

        guard TranslationLanguage.isSupportedSource(code) else {
            return
        }

        defaultSourceLanguageCode = code
        defaults.set(code, forKey: defaultSourceLanguageKey)
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
}
