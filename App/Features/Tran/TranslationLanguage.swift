import Foundation

struct TranslationLanguage: Identifiable, Equatable {
    let code: String
    let name: String

    var id: String { code }
}

extension TranslationLanguage {
    static let automaticSourceCode = "auto"
    static let automaticSourceName = "自动识别"
    static let defaultTarget = TranslationLanguage(code: "zh-Hans", name: "简体中文")

    static let supported: [TranslationLanguage] = [
        defaultTarget,
        TranslationLanguage(code: "en", name: "英语"),
        TranslationLanguage(code: "ja", name: "日语"),
        TranslationLanguage(code: "ko", name: "韩语"),
        TranslationLanguage(code: "fr", name: "法语"),
        TranslationLanguage(code: "de", name: "德语")
    ]

    static let supportedSources: [TranslationLanguage] = [
        defaultTarget,
        TranslationLanguage(code: "zh-Hant", name: "繁体中文"),
        TranslationLanguage(code: "en", name: "英语"),
        TranslationLanguage(code: "ja", name: "日语"),
        TranslationLanguage(code: "ko", name: "韩语"),
        TranslationLanguage(code: "fr", name: "法语"),
        TranslationLanguage(code: "de", name: "德语")
    ]

    static func name(for code: String) -> String {
        supported.first { $0.code == code }?.name
            ?? supportedSources.first { $0.code == code }?.name
            ?? code
    }

    static func isSupported(_ code: String) -> Bool {
        supported.contains { $0.code == code }
    }

    static func isSupportedSource(_ code: String) -> Bool {
        supportedSources.contains { $0.code == code }
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
