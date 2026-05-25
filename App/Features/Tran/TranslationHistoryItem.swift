import Foundation

struct TranslationHistoryItem: Codable, Identifiable, Equatable {
    let id: UUID
    let sourceText: String
    let translatedText: String
    let sourceLanguageCode: String?
    let targetLanguageCode: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        sourceText: String,
        translatedText: String,
        sourceLanguageCode: String? = nil,
        targetLanguageCode: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.sourceLanguageCode = sourceLanguageCode
        self.targetLanguageCode = targetLanguageCode
        self.createdAt = createdAt
    }
}
