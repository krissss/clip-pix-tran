import Foundation

struct GoogleTranslationService: TranslationService {
    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let dataLoader: DataLoader

    init(dataLoader: @escaping DataLoader = { request in
        try await URLSession.shared.data(for: request)
    }) {
        self.dataLoader = dataLoader
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        let sourceText = request.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else {
            throw TranslationValidationError.emptySource
        }

        guard var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single") else {
            throw TranslationProviderError.unavailable
        }

        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "sl", value: googleLanguageCode(for: request.sourceLanguageCode) ?? "auto"),
            URLQueryItem(name: "tl", value: googleLanguageCode(for: request.targetLanguageCode)),
            URLQueryItem(name: "q", value: sourceText)
        ]

        guard let url = components.url else {
            throw TranslationProviderError.unavailable
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.timeoutInterval = 20

        let (data, response) = try await dataLoader(urlRequest)
        try validateHTTPResponse(response)

        let translatedText = try parseTranslatedText(from: data)
        return TranslationResult(
            translatedText: translatedText,
            sourceLanguageCode: request.sourceLanguageCode,
            targetLanguageCode: request.targetLanguageCode
        )
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            return
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw TranslationProviderError.unavailable
        }
    }

    private func parseTranslatedText(from data: Data) throws -> String {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [Any],
              let segments = payload.first as? [Any]
        else {
            throw TranslationProviderError.unavailable
        }

        let translatedText = segments.compactMap { segment -> String? in
            guard let values = segment as? [Any],
                  let text = values.first as? String
            else {
                return nil
            }

            return text
        }
        .joined()
        .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !translatedText.isEmpty else {
            throw TranslationProviderError.unavailable
        }

        return translatedText
    }

    private func googleLanguageCode(for code: String?) -> String? {
        switch code {
        case "zh-Hans":
            "zh-CN"
        case "zh-Hant":
            "zh-TW"
        case let code?:
            code
        case nil:
            nil
        }
    }
}
