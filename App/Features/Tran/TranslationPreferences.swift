import Foundation

@Observable
final class TranslationPreferences {
    private let defaults: UserDefaults
    private let defaultTargetLanguageKey = "tran.defaultTargetLanguageCode"
    private let hasUserSelectedDefaultTargetLanguageKey = "tran.hasUserSelectedDefaultTargetLanguage"

    private(set) var defaultTargetLanguageCode: String

    init(
        defaults: UserDefaults = .standard,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        self.defaults = defaults

        let hasUserSelectedDefaultTargetLanguage = defaults.bool(
            forKey: hasUserSelectedDefaultTargetLanguageKey
        )
        let storedCode = defaults.string(forKey: defaultTargetLanguageKey)
        if hasUserSelectedDefaultTargetLanguage,
           let storedCode,
           TranslationLanguage.isSupported(storedCode) {
            self.defaultTargetLanguageCode = storedCode
        } else {
            self.defaultTargetLanguageCode = TranslationLanguage.bestTargetCode(
                forPreferredLanguages: preferredLanguages
            )
            defaults.set(defaultTargetLanguageCode, forKey: defaultTargetLanguageKey)
            defaults.set(false, forKey: hasUserSelectedDefaultTargetLanguageKey)
        }
    }

    func updateDefaultTargetLanguage(_ code: String) {
        guard TranslationLanguage.isSupported(code) else {
            return
        }

        defaultTargetLanguageCode = code
        defaults.set(code, forKey: defaultTargetLanguageKey)
        defaults.set(true, forKey: hasUserSelectedDefaultTargetLanguageKey)
    }
}
