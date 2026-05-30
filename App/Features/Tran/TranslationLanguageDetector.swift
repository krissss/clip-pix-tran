import Foundation
import NaturalLanguage

struct TranslationLanguageDetectionResult: Equatable {
    let languageCode: String?
    let confidence: Double
    let isReliable: Bool
}

protocol TranslationLanguageDetecting {
    func detect(
        _ text: String,
        threshold: Double,
        preferredSourceHints: [String: Double]?
    ) -> TranslationLanguageDetectionResult
}

struct NaturalLanguageTranslationLanguageDetector: TranslationLanguageDetecting {
    func detect(
        _ text: String,
        threshold: Double = 0.3,
        preferredSourceHints: [String: Double]? = nil
    ) -> TranslationLanguageDetectionResult {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let deterministicResult = Self.deterministicDetection(for: trimmedText) {
            return deterministicResult
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = Self.detectableLanguages

        var hints = Self.baseHints
        if let preferredSourceHints {
            for (code, weight) in preferredSourceHints {
                guard let language = Self.language(forCode: code) else {
                    continue
                }

                hints[language, default: 0] += weight
            }
        }
        recognizer.languageHints = hints
        recognizer.processString(trimmedText)

        let hypotheses = recognizer.languageHypotheses(withMaximum: Self.detectableLanguages.count)
        guard let best = hypotheses.max(by: { first, second in
            first.value < second.value
        }) else {
            return TranslationLanguageDetectionResult(
                languageCode: nil,
                confidence: 0,
                isReliable: false
            )
        }

        let effectiveThreshold = trimmedText.count <= 5 ? max(threshold, 0.5) : threshold
        let isReliable = best.value >= effectiveThreshold
        return TranslationLanguageDetectionResult(
            languageCode: isReliable ? Self.languageCode(for: best.key) : nil,
            confidence: best.value,
            isReliable: isReliable
        )
    }

    private static func deterministicDetection(for text: String) -> TranslationLanguageDetectionResult? {
        guard !text.isEmpty else {
            return nil
        }

        if containsScalar(in: text, ranges: [0xAC00...0xD7AF, 0x1100...0x11FF]) {
            return reliableResult("ko")
        }

        if containsScalar(in: text, ranges: [0x3040...0x30FF]) {
            return reliableResult("ja")
        }

        if containsScalar(in: text, ranges: [0x4E00...0x9FFF, 0x3400...0x4DBF]) {
            return reliableResult("zh-Hans")
        }

        return asciiLatinDetection(for: text)
    }

    private static func asciiLatinDetection(for text: String) -> TranslationLanguageDetectionResult? {
        let foldedText = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        let words = foldedText
            .split { !$0.isLetter }
            .map(String.init)

        guard !words.isEmpty,
              words.allSatisfy({ word in word.unicodeScalars.allSatisfy(\.isASCII) })
        else {
            return nil
        }

        let wordSet = Set(words)
        if !wordSet.isDisjoint(with: commonGermanWords) || !wordSet.isDisjoint(with: commonFrenchWords) {
            return nil
        }

        if !wordSet.isDisjoint(with: commonEnglishWords) {
            return reliableResult("en")
        }

        if words.count == 1, let word = words.first, (3...18).contains(word.count) {
            return reliableResult("en")
        }

        return nil
    }

    private static func reliableResult(_ languageCode: String) -> TranslationLanguageDetectionResult {
        TranslationLanguageDetectionResult(
            languageCode: languageCode,
            confidence: 1,
            isReliable: true
        )
    }

    private static let detectableLanguages: [NLLanguage] = [
        .english,
        .simplifiedChinese,
        .traditionalChinese,
        .japanese,
        .korean,
        .french,
        .german
    ]

    private static let baseHints: [NLLanguage: Double] = [
        .english: 2.0,
        .simplifiedChinese: 1.5,
        .traditionalChinese: 0.8,
        .japanese: 0.6,
        .korean: 0.5,
        .french: 0.4,
        .german: 0.3
    ]

    private static let commonEnglishWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by", "can",
        "copy", "cover", "clipboard", "do", "for", "from", "hello", "hi",
        "history", "i", "if", "in", "is", "it", "language", "no", "not",
        "of", "on", "or", "settings", "screenshot", "so", "test", "text",
        "the", "this", "to", "translate", "translation", "was", "we", "with",
        "yes", "you"
    ]

    private static let commonGermanWords: Set<String> = [
        "aber", "bitte", "danke", "das", "der", "die", "ein", "eine",
        "guten", "hallo", "ich", "ist", "ja", "mit", "nein", "nicht",
        "und", "von", "wie"
    ]

    private static let commonFrenchWords: Set<String> = [
        "avec", "bonjour", "bonsoir", "de", "des", "et", "je", "la", "le",
        "les", "merci", "non", "oui", "pas", "pour", "salut", "une", "vous"
    ]

    private static func containsScalar(in text: String, ranges: [ClosedRange<UInt32>]) -> Bool {
        text.unicodeScalars.contains { scalar in
            ranges.contains { range in
                range.contains(scalar.value)
            }
        }
    }

    private static func languageCode(for language: NLLanguage) -> String? {
        switch language {
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        case .traditionalChinese:
            return "zh-Hant"
        case .japanese:
            return "ja"
        case .korean:
            return "ko"
        case .french:
            return "fr"
        case .german:
            return "de"
        default:
            return nil
        }
    }

    private static func language(forCode code: String) -> NLLanguage? {
        switch code {
        case "en":
            return .english
        case "zh-Hans":
            return .simplifiedChinese
        case "zh-Hant":
            return .traditionalChinese
        case "ja":
            return .japanese
        case "ko":
            return .korean
        case "fr":
            return .french
        case "de":
            return .german
        default:
            return nil
        }
    }
}
