import Foundation

struct TranslationRequest: Equatable {
    var sourceText: String
    var targetLanguageCode: String
    var sourceLanguageCode: String?
}

struct TranslationResult: Equatable {
    var translatedText: String
    var sourceLanguageCode: String?
    var targetLanguageCode: String
}

protocol TranslationService {
    func translate(_ request: TranslationRequest) async throws -> TranslationResult
}
