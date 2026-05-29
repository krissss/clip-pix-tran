import Foundation

struct TranslationRequest: Equatable, Sendable {
    var sourceText: String
    var targetLanguageCode: String
    var sourceLanguageCode: String?
}

struct TranslationResult: Equatable, Sendable {
    var translatedText: String
    var sourceLanguageCode: String?
    var targetLanguageCode: String
}

struct TranslationProviderResult: Equatable, Sendable {
    var provider: TranslationProviderDescriptor
    var result: TranslationResult
}

protocol TranslationService {
    func translate(_ request: TranslationRequest) async throws -> TranslationResult
}
