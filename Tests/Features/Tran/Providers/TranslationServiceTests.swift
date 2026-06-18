import Foundation
import Testing
import Translation
@testable import ClipPixTran

@MainActor
struct TranslationServiceTests {
    @Test func fallbackTranslatesHelloToSimplifiedChinese() async throws {
        let service = FallbackTranslationService()

        let result = try await service.translate(
            TranslationRequest(
                sourceText: "hello",
                targetLanguageCode: "zh-Hans",
                sourceLanguageCode: "en"
            )
        )

        #expect(result.translatedText == "你好")
        #expect(result.targetLanguageCode == "zh-Hans")
    }

    @Test func fallbackTranslatesHelloToOtherSupportedLanguages() async throws {
        let service = FallbackTranslationService()

        let japanese = try await service.translate(
            TranslationRequest(
                sourceText: "hello",
                targetLanguageCode: "ja",
                sourceLanguageCode: "en"
            )
        )
        let english = try await service.translate(
            TranslationRequest(
                sourceText: "hello",
                targetLanguageCode: "en",
                sourceLanguageCode: "zh-Hans"
            )
        )

        #expect(japanese.translatedText == "こんにちは")
        #expect(english.translatedText == "Hello")
    }

    @Test func fallbackDoesNotTreatMatchingTextAsUnavailable() async throws {
        let service = FallbackTranslationService()

        let result = try await service.translate(
            TranslationRequest(
                sourceText: "Hello",
                targetLanguageCode: "en",
                sourceLanguageCode: "zh-Hans"
            )
        )

        #expect(result.translatedText == "Hello")
        #expect(result.targetLanguageCode == "en")
    }

    @Test func fallbackReportsUnavailableForUnknownText() async {
        let service = FallbackTranslationService()

        await #expect(throws: TranslationProviderError.unavailable) {
            try await service.translate(
                TranslationRequest(
                    sourceText: "a phrase that is not in the local fallback dictionary",
                    targetLanguageCode: "zh-Hans",
                    sourceLanguageCode: "en"
                )
            )
        }
    }

    @Test func hybridUsesFallbackWhenPrimaryFails() async throws {
        let service = HybridTranslationService(
            primary: FailingTranslationService(),
            fallback: FallbackTranslationService(),
            primaryRetryDelayNanoseconds: 0
        )

        let result = try await service.translate(
            TranslationRequest(
                sourceText: "hello",
                targetLanguageCode: "zh-Hans",
                sourceLanguageCode: "en"
            )
        )

        #expect(result.translatedText == "你好")
    }

    @Test func hybridRetriesPrimaryBeforeFallback() async throws {
        let primary = FlakyTranslationService()
        let fallback = UnexpectedFallbackTranslationService()
        let service = HybridTranslationService(
            primary: primary,
            fallback: fallback,
            primaryRetryDelayNanoseconds: 0
        )

        let result = try await service.translate(
            TranslationRequest(
                sourceText: "result",
                targetLanguageCode: "zh-Hans",
                sourceLanguageCode: "en"
            )
        )

        #expect(result.translatedText == "重试成功")
        #expect(primary.callCount == 2)
        #expect(fallback.callCount == 0)
    }

    @Test func systemUsesInstalledLanguagePairForDetectedSource() async throws {
        let service = SystemTranslationService(
            availabilityStatus: { source, target in
                source.languageCode?.identifier == "en"
                    && target?.languageCode?.identifier == "zh"
                    && target?.script?.identifier == "Hans"
                    && target?.region?.identifier == "CN"
                    ? .installed
                    : .unsupported
            },
            installedTranslator: { source, target, sourceText, targetLanguageCode in
                TranslationResult(
                    translatedText: "\(sourceText)-translated",
                    sourceLanguageCode: source.languageCode?.identifier,
                    targetLanguageCode: targetLanguageCode
                )
            }
        )

        let result = try await service.translate(
            TranslationRequest(
                sourceText: "hello",
                targetLanguageCode: "zh-Hans",
                sourceLanguageCode: nil
            )
        )

        #expect(result.translatedText == "hello-translated")
        #expect(result.sourceLanguageCode == "en")
        #expect(result.targetLanguageCode == "zh-Hans")
    }

    @Test func systemPrefersDeterministicEnglishForShortWords() async throws {
        var attemptedSourceCodes: [String] = []
        let service = SystemTranslationService(
            availabilityStatus: { source, target in
                attemptedSourceCodes.append(source.languageCode?.identifier ?? "")
                return source.languageCode?.identifier == "en"
                    && target?.languageCode?.identifier == "zh"
                    && target?.script?.identifier == "Hans"
                    && target?.region?.identifier == "CN"
                    ? .installed
                    : .unsupported
            },
            installedTranslator: { source, _, sourceText, targetLanguageCode in
                TranslationResult(
                    translatedText: "\(sourceText)-translated",
                    sourceLanguageCode: source.languageCode?.identifier,
                    targetLanguageCode: targetLanguageCode
                )
            }
        )

        let result = try await service.translate(
            TranslationRequest(
                sourceText: "translate",
                targetLanguageCode: "zh-Hans",
                sourceLanguageCode: nil
            )
        )

        #expect(attemptedSourceCodes.first == "en")
        #expect(result.sourceLanguageCode == "en")
    }

    @Test func systemAttemptsSupportedLanguagePair() async throws {
        let service = SystemTranslationService(
            availabilityStatus: { _, _ in .supported },
            installedTranslator: { source, _, sourceText, targetLanguageCode in
                TranslationResult(
                    translatedText: "\(sourceText)-supported",
                    sourceLanguageCode: source.languageCode?.identifier,
                    targetLanguageCode: targetLanguageCode
                )
            }
        )

        let result = try await service.translate(
            TranslationRequest(
                sourceText: "hello",
                targetLanguageCode: "zh-Hans",
                sourceLanguageCode: "en"
            )
        )

        #expect(result.translatedText == "hello-supported")
        #expect(result.sourceLanguageCode == "en")
    }

    @Test func googleTranslationBuildsRequestAndParsesResponse() async throws {
        var capturedRequest: URLRequest?
        let responseData = #"[[["你好","hello",null,null,1]],null,"en"]"#.data(using: .utf8)!
        let service = GoogleTranslationService { request in
            capturedRequest = request
            return (
                responseData,
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }

        let result = try await service.translate(
            TranslationRequest(
                sourceText: "hello",
                targetLanguageCode: "zh-Hans",
                sourceLanguageCode: "en"
            )
        )

        let url = try #require(capturedRequest?.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        #expect(components.host == "translate.googleapis.com")
        #expect(queryItems["sl"] == "en")
        #expect(queryItems["tl"] == "zh-CN")
        #expect(queryItems["q"] == "hello")
        #expect(result.translatedText == "你好")
        #expect(result.sourceLanguageCode == "en")
        #expect(result.targetLanguageCode == "zh-Hans")
    }

    @Test func googleSpeechBuildsTextToSpeechRequest() throws {
        let request = try GoogleTranslationSpeechService.makeRequest(
            for: TranslationSpeechRequest(
                text: " 你好 ",
                languageCode: "zh-Hans"
            )
        )

        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        #expect(components.host == "translate.google.com")
        #expect(components.path == "/translate_tts")
        #expect(queryItems["client"] == "tw-ob")
        #expect(queryItems["tl"] == "zh-CN")
        #expect(queryItems["q"] == "你好")
        #expect(request.value(forHTTPHeaderField: "User-Agent") != nil)
    }

    @Test func openAITextToSpeechBuildsChatAudioRequest() throws {
        let request = try OpenAITextToSpeechService.makeRequest(
            for: TranslationSpeechRequest(text: " Hello ", languageCode: "en"),
            configuration: OpenAITextToSpeechConfiguration(
                baseURL: "https://api.openai.com/v1",
                apiKey: "test-key",
                model: "gpt-audio",
                voice: "alloy"
            )
        )

        #expect(request.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        let body = try #require(request.httpBody)
        let bodyObject = try JSONSerialization.jsonObject(with: body)
        let payload = try #require(bodyObject as? [String: Any])
        #expect(payload["model"] as? String == "gpt-audio")
        #expect(payload["modalities"] as? [String] == ["text", "audio"])
        let audio = try #require(payload["audio"] as? [String: Any])
        #expect(audio["format"] as? String == "wav")
        #expect(audio["voice"] as? String == "alloy")
        let messages = try #require(payload["messages"] as? [[String: String]])
        #expect(messages.map { $0["role"] } == ["user"])
        #expect(messages.first?["content"]?.contains("Hello") == true)
    }

    @Test func openAITextToSpeechBuildsMiMoChatAudioRequest() throws {
        let request = try OpenAITextToSpeechService.makeRequest(
            for: TranslationSpeechRequest(text: "你好", languageCode: "zh-Hans"),
            configuration: OpenAITextToSpeechConfiguration(
                baseURL: "https://api.xiaomimimo.com/v1",
                apiKey: "mimo-key",
                model: "mimo-v2.5-tts",
                voice: "mimo_default"
            )
        )

        #expect(request.url?.absoluteString == "https://api.xiaomimimo.com/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer mimo-key")
        #expect(request.value(forHTTPHeaderField: "api-key") == "mimo-key")
        let body = try #require(request.httpBody)
        let bodyObject = try JSONSerialization.jsonObject(with: body)
        let payload = try #require(bodyObject as? [String: Any])
        #expect(payload["model"] as? String == "mimo-v2.5-tts")
        #expect(payload["modalities"] == nil)
        let audio = try #require(payload["audio"] as? [String: Any])
        #expect(audio["format"] as? String == "wav")
        #expect(audio["voice"] as? String == "mimo_default")
        let messages = try #require(payload["messages"] as? [[String: String]])
        #expect(messages[1]["role"] == "assistant")
        #expect(messages[1]["content"] == "你好")
    }

    @Test func openAITextToSpeechBuildsMiMoRequestFromHostBaseURLAndDefaultVoice() throws {
        let request = try OpenAITextToSpeechService.makeRequest(
            for: TranslationSpeechRequest(text: "你好", languageCode: "zh-Hans"),
            configuration: OpenAITextToSpeechConfiguration(
                baseURL: "https://token-plan-cn.xiaomimimo.com",
                apiKey: "mimo-key",
                model: "mimo-v2.5-tts",
                voice: "alloy"
            )
        )

        #expect(request.url?.absoluteString == "https://token-plan-cn.xiaomimimo.com/v1/chat/completions")
        let body = try #require(request.httpBody)
        let bodyObject = try JSONSerialization.jsonObject(with: body)
        let payload = try #require(bodyObject as? [String: Any])
        #expect(payload["modalities"] == nil)
        let audio = try #require(payload["audio"] as? [String: Any])
        #expect(audio["voice"] as? String == "mimo_default")
    }

    @Test func openAITextToSpeechAcceptsDirectChatCompletionsEndpointBaseURL() throws {
        let request = try OpenAITextToSpeechService.makeRequest(
            for: TranslationSpeechRequest(text: "Hello", languageCode: "en"),
            configuration: OpenAITextToSpeechConfiguration(
                baseURL: "https://api.openai.com/v1/chat/completions/",
                apiKey: "test-key",
                model: "gpt-audio",
                voice: "alloy"
            )
        )

        #expect(request.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
    }

    @Test func openAITextToSpeechRequiresConfiguration() throws {
        #expect(throws: TranslationSpeechError.providerNotConfigured) {
            try OpenAITextToSpeechService.makeRequest(
                for: TranslationSpeechRequest(text: "Hello", languageCode: "en"),
                configuration: OpenAITextToSpeechConfiguration(
                    baseURL: "",
                    apiKey: "",
                    model: "",
                    voice: ""
                )
            )
        }
    }

    @Test func openAITextToSpeechReportsTopLevelErrorMessage() async {
        let service = OpenAITextToSpeechService(
            configurationProvider: {
                OpenAITextToSpeechConfiguration(
                    baseURL: "https://token-plan-cn.xiaomimimo.com",
                    apiKey: "mimo-key",
                    model: "mimo-v2.5-tts",
                    voice: "mimo_default"
                )
            },
            dataLoader: { request in
                (
                    #"{"message":"voice is invalid"}"#.data(using: .utf8)!,
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 400,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
        )

        let error = await withCheckedContinuation { continuation in
            service.speak(
                TranslationSpeechRequest(text: "你好", languageCode: "zh-Hans"),
                onStart: {},
                onFinish: { error in
                    continuation.resume(returning: error)
                }
            )
        }

        #expect(error?.localizedDescription == "voice is invalid")
    }

    @Test func openAICompatibleTranslationBuildsChatCompletionRequest() async throws {
        var capturedRequest: URLRequest?
        let responseData = #"{"choices":[{"message":{"role":"assistant","content":"你好"}}]}"#.data(using: .utf8)!
        let service = OpenAICompatibleTranslationService(
            configurationProvider: {
                OpenAICompatibleTranslationConfiguration(
                    baseURL: "https://api.openai.com/v1",
                    apiKey: "test-key",
                    model: "gpt-test"
                )
            },
            dataLoader: { request in
                capturedRequest = request
                return (
                    responseData,
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!
                )
            }
        )

        let result = try await service.translate(
            TranslationRequest(
                sourceText: "hello",
                targetLanguageCode: "zh-Hans",
                sourceLanguageCode: "en"
            )
        )

        let request = try #require(capturedRequest)
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        let body = try #require(request.httpBody)
        let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(payload?["model"] as? String == "gpt-test")
        #expect(result.translatedText == "你好")
    }

    @Test func openAICompatibleRequiresConfiguration() async {
        let service = OpenAICompatibleTranslationService(
            configurationProvider: {
                OpenAICompatibleTranslationConfiguration(baseURL: "", apiKey: "", model: "")
            }
        )

        await #expect(throws: TranslationProviderError.providerNotConfigured) {
            try await service.translate(
                TranslationRequest(
                    sourceText: "hello",
                    targetLanguageCode: "zh-Hans",
                    sourceLanguageCode: "en"
                )
            )
        }
    }
}

private struct FailingTranslationService: TranslationService {
    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        throw TranslationProviderError.unavailable
    }
}

private final class FlakyTranslationService: TranslationService {
    private(set) var callCount = 0

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        callCount += 1
        if callCount == 1 {
            throw TranslationProviderError.unavailable
        }

        return TranslationResult(
            translatedText: "重试成功",
            sourceLanguageCode: request.sourceLanguageCode,
            targetLanguageCode: request.targetLanguageCode
        )
    }
}

private final class UnexpectedFallbackTranslationService: TranslationService {
    private(set) var callCount = 0

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        callCount += 1
        throw UnexpectedTranslationCallError()
    }
}

private struct UnexpectedTranslationCallError: Error {}
