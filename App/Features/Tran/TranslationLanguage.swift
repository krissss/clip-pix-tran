import Foundation

struct TranslationLanguage: Identifiable, Equatable {
    let code: String
    let name: String

    var id: String { code }
}

extension TranslationLanguage {
    static let automaticSourceCode = "auto"
    static var automaticSourceName: String { L10n.languageAutoDetect }
    static var defaultTarget: TranslationLanguage {
        TranslationLanguage(code: "zh-Hans", name: L10n.languageZhHans)
    }

    static var supported: [TranslationLanguage] { [
        defaultTarget,
        TranslationLanguage(code: "en", name: L10n.languageEnglish),
        TranslationLanguage(code: "ja", name: L10n.languageJapanese),
        TranslationLanguage(code: "ko", name: L10n.languageKorean),
        TranslationLanguage(code: "fr", name: L10n.languageFrench),
        TranslationLanguage(code: "de", name: L10n.languageGerman)
    ] }

    static var supportedSources: [TranslationLanguage] { [
        defaultTarget,
        TranslationLanguage(code: "zh-Hant", name: L10n.languageZhHant),
        TranslationLanguage(code: "en", name: L10n.languageEnglish),
        TranslationLanguage(code: "ja", name: L10n.languageJapanese),
        TranslationLanguage(code: "ko", name: L10n.languageKorean),
        TranslationLanguage(code: "fr", name: L10n.languageFrench),
        TranslationLanguage(code: "de", name: L10n.languageGerman)
    ] }

    static func name(for code: String) -> String {
        supported.first { $0.code == code }?.name
            ?? supportedSources.first { $0.code == code }?.name
            ?? code
    }

    nonisolated static func englishName(for code: String) -> String {
        switch code {
        case "zh-Hans":
            "Simplified Chinese"
        case "zh-Hant":
            "Traditional Chinese"
        case "en":
            "English"
        case "ja":
            "Japanese"
        case "ko":
            "Korean"
        case "fr":
            "French"
        case "de":
            "German"
        default:
            code
        }
    }

    static func isSupported(_ code: String) -> Bool {
        supported.contains { $0.code == code }
    }

    static func isSupportedSource(_ code: String) -> Bool {
        supportedSources.contains { $0.code == code }
    }

    static func isChinese(_ code: String) -> Bool {
        code.hasPrefix("zh")
    }

    static func bestTargetCode(forPreferredLanguages preferredLanguages: [String]) -> String {
        for preferredLanguage in preferredLanguages {
            if let supportedCode = supportedCode(matching: preferredLanguage) {
                return supportedCode
            }
        }

        return defaultTarget.code
    }

    private static func supportedCode(matching languageIdentifier: String) -> String? {
        let normalizedIdentifier = languageIdentifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()

        if let exactMatch = supported.first(where: { $0.code.lowercased() == normalizedIdentifier }) {
            return exactMatch.code
        }

        if normalizedIdentifier.hasPrefix("zh-hans") || normalizedIdentifier == "zh" {
            return defaultTarget.code
        }

        let languageCode = normalizedIdentifier.split(separator: "-").first.map(String.init)
        return supported.first { $0.code.lowercased() == languageCode }?.code
    }
}
