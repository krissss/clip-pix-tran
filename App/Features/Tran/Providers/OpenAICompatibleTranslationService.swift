import Foundation

struct OpenAICompatibleTranslationConfiguration: Equatable, Sendable {
    static let defaultBaseURL = "https://api.openai.com/v1"
    static let defaultModel = "gpt-4o-mini"

    var baseURL: String
    var apiKey: String
    var model: String

    var normalizedBaseURL: String {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedModel: String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct OpenAICompatibleTranslationService: TranslationService {
    typealias ConfigurationProvider = @Sendable () -> OpenAICompatibleTranslationConfiguration
    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let configurationProvider: ConfigurationProvider
    private let dataLoader: DataLoader
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        configurationProvider: @escaping ConfigurationProvider,
        dataLoader: @escaping DataLoader = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.configurationProvider = configurationProvider
        self.dataLoader = dataLoader
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        let sourceText = request.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else {
            throw TranslationValidationError.emptySource
        }

        let configuration = configurationProvider()
        guard !configuration.normalizedBaseURL.isEmpty,
              !configuration.trimmedAPIKey.isEmpty,
              !configuration.trimmedModel.isEmpty
        else {
            throw TranslationProviderError.providerNotConfigured
        }

        guard let url = chatCompletionsURL(for: configuration.normalizedBaseURL) else {
            throw TranslationProviderError.unavailable
        }

        let payload = OpenAIChatCompletionsRequest(
            model: configuration.trimmedModel,
            messages: [
                OpenAIChatMessage(
                    role: "system",
                    content: systemPrompt(
                        sourceLanguageCode: request.sourceLanguageCode,
                        targetLanguageCode: request.targetLanguageCode
                    )
                ),
                OpenAIChatMessage(role: "user", content: sourceText)
            ],
            temperature: 0.2
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 45
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(configuration.trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try encoder.encode(payload)

        let (data, response) = try await dataLoader(urlRequest)
        try validateHTTPResponse(response, data: data)

        let decoded = try decoder.decode(OpenAIChatCompletionsResponse.self, from: data)
        let translatedText = decoded.choices.first?.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !translatedText.isEmpty else {
            throw TranslationProviderError.unavailable
        }

        return TranslationResult(
            translatedText: translatedText,
            sourceLanguageCode: request.sourceLanguageCode,
            targetLanguageCode: request.targetLanguageCode
        )
    }

    private func chatCompletionsURL(for baseURL: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.hasSuffix("/chat/completions") {
            return URL(string: trimmed)
        }

        return URL(string: "\(trimmed)/chat/completions")
    }

    private func systemPrompt(sourceLanguageCode: String?, targetLanguageCode: String) -> String {
        let targetLanguage = TranslationLanguage.englishName(for: targetLanguageCode)
        let sourceLanguage = sourceLanguageCode.map(TranslationLanguage.englishName(for:)) ?? "the detected source language"

        return """
        Translate the user's text from \(sourceLanguage) to \(targetLanguage).
        Return only the translated text. Do not explain, quote, or add notes.
        Preserve line breaks and formatting where possible.
        """
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            return
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let error = try? decoder.decode(OpenAIErrorResponse.self, from: data),
               let message = error.error?.message,
               !message.isEmpty {
                throw TranslationProviderError.requestFailed(message)
            }

            throw TranslationProviderError.unavailable
        }
    }
}

private struct OpenAIChatCompletionsRequest: Encodable {
    let model: String
    let messages: [OpenAIChatMessage]
    let temperature: Double
}

private struct OpenAIChatMessage: Codable {
    let role: String
    let content: String
}

private struct OpenAIChatCompletionsResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: OpenAIChatMessage
    }
}

private struct OpenAIErrorResponse: Decodable {
    let error: OpenAIError?

    struct OpenAIError: Decodable {
        let message: String?
    }
}
