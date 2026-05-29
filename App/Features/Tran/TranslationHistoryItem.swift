import Foundation

struct TranslationHistoryItem: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceText: String
    let translatedText: String
    let sourceLanguageCode: String?
    let detectedSourceLanguageCode: String?
    let targetLanguageCode: String
    let providerID: String
    let providerName: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        sourceText: String,
        translatedText: String,
        sourceLanguageCode: String? = nil,
        detectedSourceLanguageCode: String? = nil,
        targetLanguageCode: String,
        providerID: String = TranslationProviderDescriptor.systemTranslation.id,
        providerName: String = TranslationProviderDescriptor.systemTranslation.name,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.sourceLanguageCode = sourceLanguageCode
        self.detectedSourceLanguageCode = detectedSourceLanguageCode
        self.targetLanguageCode = targetLanguageCode
        self.providerID = providerID
        self.providerName = providerName
        self.createdAt = createdAt
    }
}

extension TranslationHistoryItem {
    private enum CodingKeys: String, CodingKey {
        case id
        case sourceText
        case translatedText
        case sourceLanguageCode
        case detectedSourceLanguageCode
        case targetLanguageCode
        case providerID
        case providerName
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let providerID = try container.decodeIfPresent(String.self, forKey: .providerID)
            ?? TranslationProviderDescriptor.systemTranslation.id
        let providerName = try container.decodeIfPresent(String.self, forKey: .providerName)
            ?? TranslationProviderDescriptor.descriptor(for: providerID).name

        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            sourceText: try container.decode(String.self, forKey: .sourceText),
            translatedText: try container.decode(String.self, forKey: .translatedText),
            sourceLanguageCode: try container.decodeIfPresent(String.self, forKey: .sourceLanguageCode),
            detectedSourceLanguageCode: try container.decodeIfPresent(String.self, forKey: .detectedSourceLanguageCode),
            targetLanguageCode: try container.decode(String.self, forKey: .targetLanguageCode),
            providerID: providerID,
            providerName: providerName,
            createdAt: try container.decode(Date.self, forKey: .createdAt)
        )
    }
}
