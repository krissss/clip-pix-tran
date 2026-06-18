import Foundation

struct TranslationProviderDescriptor: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let name: String
    let systemImage: String
    let isLocal: Bool

    init(
        id: String,
        name: String,
        systemImage: String,
        isLocal: Bool
    ) {
        self.id = id
        self.name = name
        self.systemImage = systemImage
        self.isLocal = isLocal
    }
}

extension TranslationProviderDescriptor {
    static let systemTranslation = TranslationProviderDescriptor(
        id: "system",
        name: "System Translation",
        systemImage: "apple.logo",
        isLocal: true
    )

    static let google = TranslationProviderDescriptor(
        id: "google",
        name: "Google Translate",
        systemImage: "globe",
        isLocal: false
    )

    static let builtIn: [TranslationProviderDescriptor] = [
        .systemTranslation,
        .google
    ]

    static func descriptor(for id: String) -> TranslationProviderDescriptor {
        if id == "local-dictionary" {
            return TranslationProviderDescriptor(
                id: id,
                name: "Local Dictionary",
                systemImage: "book.closed",
                isLocal: true
            )
        }

        return builtIn.first { $0.id == id } ?? TranslationProviderDescriptor(
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
        return [
            TranslationProvider(
                descriptor: .systemTranslation,
                service: HybridTranslationService()
            ),
            TranslationProvider(
                descriptor: .google,
                service: GoogleTranslationService()
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
