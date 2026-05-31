import Foundation

struct TranslationHistoryProviderResult: Codable, Identifiable, Equatable, Sendable {
    let providerID: String
    let providerName: String
    let translatedText: String
    let detectedSourceLanguageCode: String?
    let targetLanguageCode: String

    var id: String {
        providerID
    }
}

struct TranslationHistoryItem: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceText: String
    let translatedText: String
    let sourceLanguageCode: String?
    let detectedSourceLanguageCode: String?
    let targetLanguageCode: String
    let providerID: String
    let providerName: String
    let providerResults: [TranslationHistoryProviderResult]
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
        providerResults: [TranslationHistoryProviderResult]? = nil,
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
        self.providerResults = providerResults ?? [
            TranslationHistoryProviderResult(
                providerID: providerID,
                providerName: providerName,
                translatedText: translatedText,
                detectedSourceLanguageCode: detectedSourceLanguageCode,
                targetLanguageCode: targetLanguageCode
            )
        ]
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
        case providerResults
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let providerID = try container.decodeIfPresent(String.self, forKey: .providerID)
            ?? TranslationProviderDescriptor.systemTranslation.id
        let providerName = try container.decodeIfPresent(String.self, forKey: .providerName)
            ?? TranslationProviderDescriptor.descriptor(for: providerID).name
        let translatedText = try container.decode(String.self, forKey: .translatedText)
        let detectedSourceLanguageCode = try container.decodeIfPresent(
            String.self,
            forKey: .detectedSourceLanguageCode
        )
        let targetLanguageCode = try container.decode(String.self, forKey: .targetLanguageCode)

        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            sourceText: try container.decode(String.self, forKey: .sourceText),
            translatedText: translatedText,
            sourceLanguageCode: try container.decodeIfPresent(String.self, forKey: .sourceLanguageCode),
            detectedSourceLanguageCode: detectedSourceLanguageCode,
            targetLanguageCode: targetLanguageCode,
            providerID: providerID,
            providerName: providerName,
            providerResults: try container.decodeIfPresent(
                [TranslationHistoryProviderResult].self,
                forKey: .providerResults
            ),
            createdAt: try container.decode(Date.self, forKey: .createdAt)
        )
    }
}
