import Foundation

struct TranslationProviderDescriptor: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let name: String
    let systemImage: String
    let isLocal: Bool
}

extension TranslationProviderDescriptor {
    static let systemTranslation = TranslationProviderDescriptor(
        id: "system",
        name: "System Translation",
        systemImage: "apple.logo",
        isLocal: true
    )

    static let localDictionary = TranslationProviderDescriptor(
        id: "local-dictionary",
        name: "Local Dictionary",
        systemImage: "book.closed",
        isLocal: true
    )

    static let builtIn: [TranslationProviderDescriptor] = [
        .systemTranslation,
        .localDictionary
    ]

    static func descriptor(for id: String) -> TranslationProviderDescriptor {
        builtIn.first { $0.id == id } ?? TranslationProviderDescriptor(
            id: id,
            name: id,
            systemImage: "questionmark.app",
            isLocal: true
        )
    }
}

struct TranslationProvider: Identifiable {
    let descriptor: TranslationProviderDescriptor
    let service: TranslationService

    var id: String {
        descriptor.id
    }
}

extension TranslationProvider {
    static func builtIn() -> [TranslationProvider] {
        [
            TranslationProvider(
                descriptor: .systemTranslation,
                service: SystemTranslationService()
            ),
            TranslationProvider(
                descriptor: .localDictionary,
                service: FallbackTranslationService()
            )
        ]
    }
}

enum TranslationProviderStatus: Equatable {
    case idle(String)
    case loading(String)
    case success
    case failed(String)
}

struct TranslationProviderState: Identifiable, Equatable {
    let provider: TranslationProviderDescriptor
    var status: TranslationProviderStatus
    var result: TranslationResult?

    var id: String {
        provider.id
    }

    var translatedText: String {
        result?.translatedText ?? ""
    }

    var detectedSourceLanguageCode: String? {
        result?.sourceLanguageCode
    }
}
