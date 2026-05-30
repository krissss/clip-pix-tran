import Foundation
import NaturalLanguage
import Translation

struct SystemTranslationService: TranslationService {
    typealias AvailabilityStatusProvider = @Sendable (
        Locale.Language,
        Locale.Language?
    ) async -> LanguageAvailability.Status
    typealias InstalledTranslator = @Sendable (
        Locale.Language,
        Locale.Language,
        String,
        String
    ) async throws -> TranslationResult

    private let availabilityStatus: AvailabilityStatusProvider
    private let installedTranslator: InstalledTranslator

    init(
        availabilityStatus: @escaping AvailabilityStatusProvider = { source, target in
            await LanguageAvailability().status(from: source, to: target)
        },
        installedTranslator: @escaping InstalledTranslator = Self.translateInstalled
    ) {
        self.availabilityStatus = availabilityStatus
        self.installedTranslator = installedTranslator
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        guard #available(macOS 26.0, *) else {
            throw TranslationProviderError.unavailable
        }

        let sourceText = request.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else {
            throw TranslationValidationError.emptySource
        }

        let targetLanguage = Locale.Language(identifier: request.targetLanguageCode)
        let sourceLanguage = try await sourceLanguage(
            for: request,
            sourceText: sourceText,
            targetLanguage: targetLanguage
        )
        return try await installedTranslator(
            sourceLanguage,
            targetLanguage,
            sourceText,
            request.targetLanguageCode
        )
    }

    private static func translateInstalled(
        sourceLanguage: Locale.Language,
        targetLanguage: Locale.Language,
        sourceText: String,
        targetLanguageCode: String
    ) async throws -> TranslationResult {
        let session = TranslationSession(
            installedSource: sourceLanguage,
            target: targetLanguage
        )
        let response = try await session.translate(sourceText)

        return TranslationResult(
            translatedText: response.targetText,
            sourceLanguageCode: response.sourceLanguage.languageCode?.identifier,
            targetLanguageCode: targetLanguageCode
        )
    }

    private func sourceLanguage(
        for request: TranslationRequest,
        sourceText: String,
        targetLanguage: Locale.Language
    ) async throws -> Locale.Language {
        if let sourceLanguageCode = request.sourceLanguageCode {
            let sourceLanguage = Locale.Language(identifier: sourceLanguageCode)
            guard await isInstalled(from: sourceLanguage, to: targetLanguage) else {
                throw TranslationProviderError.unavailable
            }

            return sourceLanguage
        }

        for sourceLanguage in sourceLanguageCandidates(for: sourceText) {
            if await isInstalled(from: sourceLanguage, to: targetLanguage) {
                return sourceLanguage
            }
        }

        throw TranslationProviderError.unavailable
    }

    private func isInstalled(
        from sourceLanguage: Locale.Language,
        to targetLanguage: Locale.Language
    ) async -> Bool {
        await availabilityStatus(sourceLanguage, targetLanguage) == .installed
    }

    private func sourceLanguageCandidates(for sourceText: String) -> [Locale.Language] {
        let deterministicLanguageCode = NaturalLanguageTranslationLanguageDetector()
            .detect(sourceText, threshold: 0.3, preferredSourceHints: nil)
            .languageCode

        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = Self.detectableLanguages
        recognizer.processString(sourceText)

        var languageCodes = recognizer
            .languageHypotheses(withMaximum: Self.detectableLanguages.count)
            .filter { $0.value >= Self.minimumLanguageConfidence }
            .sorted { first, second in
                first.value > second.value
            }
            .compactMap { language, _ in
                Self.languageCode(for: language)
            }
        if let deterministicLanguageCode {
            languageCodes.insert(deterministicLanguageCode, at: 0)
        }

        var seenLanguageCodes = Set<String>()
        return languageCodes.compactMap { languageCode in
            guard seenLanguageCodes.insert(languageCode).inserted else {
                return nil
            }

            return Locale.Language(identifier: languageCode)
        }
    }

    private static let minimumLanguageConfidence = 0.1
    private static let detectableLanguages: [NLLanguage] = [
        .english,
        .simplifiedChinese,
        .traditionalChinese,
        .japanese,
        .korean,
        .french,
        .german
    ]

    private static func languageCode(for language: NLLanguage) -> String? {
        if language == .english {
            return "en"
        }
        if language == .simplifiedChinese {
            return "zh-Hans"
        }
        if language == .traditionalChinese {
            return "zh-Hant"
        }
        if language == .japanese {
            return "ja"
        }
        if language == .korean {
            return "ko"
        }
        if language == .french {
            return "fr"
        }
        if language == .german {
            return "de"
        }

        return nil
    }
}
