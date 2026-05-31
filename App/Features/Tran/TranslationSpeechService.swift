import AVFoundation
import Foundation

struct TranslationSpeechProviderDescriptor: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let name: String
    let systemImage: String
    let isLocal: Bool
}

extension TranslationSpeechProviderDescriptor {
    static let system = TranslationSpeechProviderDescriptor(
        id: "system",
        name: "System Voice",
        systemImage: "speaker.wave.2",
        isLocal: true
    )

    static let google = TranslationSpeechProviderDescriptor(
        id: "google",
        name: "Google Translate",
        systemImage: "globe",
        isLocal: false
    )

    static let openAITextToSpeech = TranslationSpeechProviderDescriptor(
        id: "openai-tts",
        name: "Chat Audio TTS",
        systemImage: "sparkles",
        isLocal: false
    )

    static let builtIn: [TranslationSpeechProviderDescriptor] = [
        .system,
        .google,
        .openAITextToSpeech
    ]

    static func descriptor(for id: String) -> TranslationSpeechProviderDescriptor {
        builtIn.first { $0.id == id } ?? TranslationSpeechProviderDescriptor(
            id: id,
            name: id,
            systemImage: "questionmark.app",
            isLocal: true
        )
    }
}

@MainActor
struct TranslationSpeechProvider: Identifiable {
    let descriptor: TranslationSpeechProviderDescriptor
    let service: TranslationSpeechService

    var id: String {
        descriptor.id
    }
}

extension TranslationSpeechProvider {
    static func builtIn(preferences: TranslationPreferences? = nil) -> [TranslationSpeechProvider] {
        let preferences = preferences ?? TranslationPreferences()
        return [
            TranslationSpeechProvider(
                descriptor: .system,
                service: SystemTranslationSpeechService()
            ),
            TranslationSpeechProvider(
                descriptor: .google,
                service: GoogleTranslationSpeechService()
            ),
            TranslationSpeechProvider(
                descriptor: .openAITextToSpeech,
                service: OpenAITextToSpeechService(
                    configurationProvider: { preferences.openAITextToSpeechConfiguration }
                )
            )
        ]
    }
}

struct OpenAITextToSpeechConfiguration: Equatable, Sendable {
    static let defaultModel = "gpt-audio"
    static let defaultVoice = "alloy"
    static let defaultMiMoVoice = "mimo_default"

    static let supportedModels = [
        "gpt-audio",
        "gpt-audio-mini",
        "gpt-4o-mini-audio-preview",
        "gpt-4o-audio-preview",
        "mimo-v2.5-tts",
        "mimo-v2.5-tts-voicedesign",
        "mimo-v2.5-tts-voiceclone"
    ]

    static let supportedMiMoVoices = [
        "mimo_default",
        "Chloe",
        "Mia",
        "Milo",
        "Dean"
    ]

    static let supportedVoices = supportedMiMoVoices + [
        "marin",
        "cedar",
        "alloy",
        "ash",
        "ballad",
        "coral",
        "echo",
        "fable",
        "nova",
        "onyx",
        "sage",
        "shimmer",
        "verse"
    ]

    var baseURL: String
    var apiKey: String
    var model: String
    var voice: String

    var normalizedBaseURL: String {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedModel: String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedVoice: String {
        voice.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum TranslationSpeechError: LocalizedError, Equatable {
    case unavailable
    case providerNotConfigured
    case noAudioData
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "当前发音服务不可用。请稍后重试，或检查发音 provider 配置。"
        case .providerNotConfigured:
            "发音 provider 尚未配置。请到设置里填写 Base URL、API Key、TTS Model 和 TTS Voice。"
        case .noAudioData:
            "发音服务没有返回可播放的音频数据。"
        case .requestFailed(let message):
            message
        }
    }
}

struct TranslationSpeechRequest: Equatable {
    let text: String
    let languageCode: String?
}

enum TranslationSpeechTarget: Equatable {
    case source
    case result(providerID: String)
}

@MainActor
protocol TranslationSpeechService {
    func speak(
        _ request: TranslationSpeechRequest,
        onStart: @escaping () -> Void,
        onFinish: @escaping (Error?) -> Void
    )
    func stop()
}

@MainActor
final class SystemTranslationSpeechService: NSObject, TranslationSpeechService {
    private let synthesizer: AVSpeechSynthesizer
    private var activeUtterance: AVSpeechUtterance?
    private var finishHandler: ((Error?) -> Void)?

    override init() {
        synthesizer = AVSpeechSynthesizer()
        super.init()
        synthesizer.delegate = self
    }

    func speak(
        _ request: TranslationSpeechRequest,
        onStart: @escaping () -> Void,
        onFinish: @escaping (Error?) -> Void
    ) {
        let trimmedText = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }

        stop()

        let utterance = AVSpeechUtterance(string: trimmedText)
        if let voiceLanguage = Self.voiceLanguage(for: request.languageCode),
           let voice = AVSpeechSynthesisVoice(language: voiceLanguage) {
            utterance.voice = voice
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        activeUtterance = utterance
        finishHandler = onFinish
        onStart()
        synthesizer.speak(utterance)
    }

    func stop() {
        activeUtterance = nil
        finishHandler = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func finishSpeech(for utterance: AVSpeechUtterance) {
        guard let activeUtterance, activeUtterance === utterance else {
            return
        }

        self.activeUtterance = nil
        let handler = finishHandler
        finishHandler = nil
        handler?(nil)
    }

    private static func voiceLanguage(for code: String?) -> String? {
        switch code {
        case "zh-Hans":
            "zh-CN"
        case "zh-Hant":
            "zh-TW"
        case "en":
            "en-US"
        case "ja":
            "ja-JP"
        case "ko":
            "ko-KR"
        case "fr":
            "fr-FR"
        case "de":
            "de-DE"
        default:
            nil
        }
    }
}

@MainActor
final class GoogleTranslationSpeechService: TranslationSpeechService {
    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let dataLoader: DataLoader
    private var activeTask: Task<Void, Never>?
    private var player: AVAudioPlayer?
    private var playbackDelegate: TranslationAudioPlaybackDelegate?
    private var finishHandler: ((Error?) -> Void)?
    private var audioCache: [String: Data] = [:]

    init(dataLoader: @escaping DataLoader = { request in
        try await URLSession.shared.data(for: request)
    }) {
        self.dataLoader = dataLoader
    }

    func speak(
        _ request: TranslationSpeechRequest,
        onStart: @escaping () -> Void,
        onFinish: @escaping (Error?) -> Void
    ) {
        let trimmedText = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }

        stop()
        finishHandler = onFinish

        let cacheKey = Self.cacheKey(for: TranslationSpeechRequest(text: trimmedText, languageCode: request.languageCode))
        if let cachedData = audioCache[cacheKey] {
            playAudioData(cachedData, onStart: onStart)
            return
        }

        activeTask = Task { [weak self, dataLoader] in
            do {
                let urlRequest = try Self.makeRequest(
                    for: TranslationSpeechRequest(
                        text: trimmedText,
                        languageCode: request.languageCode
                    )
                )
                let (data, response) = try await dataLoader(urlRequest)
                try Self.validateHTTPResponse(response)
                guard !Task.isCancelled else {
                    return
                }

                self?.storeAudioData(data, for: cacheKey)
                self?.playAudioData(data, onStart: onStart)
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                self?.finishPlayback(error: error)
            }
        }
    }

    func stop() {
        activeTask?.cancel()
        activeTask = nil
        player?.stop()
        player = nil
        playbackDelegate = nil
        finishHandler = nil
    }

    static func makeRequest(for request: TranslationSpeechRequest) throws -> URLRequest {
        let trimmedText = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty,
              var components = URLComponents(string: "https://translate.google.com/translate_tts")
        else {
            throw TranslationValidationError.emptySource
        }

        components.queryItems = [
            URLQueryItem(name: "ie", value: "UTF-8"),
            URLQueryItem(name: "client", value: "tw-ob"),
            URLQueryItem(name: "tl", value: googleLanguageCode(for: request.languageCode) ?? "en"),
            URLQueryItem(name: "q", value: trimmedText)
        ]

        guard let url = components.url else {
            throw TranslationSpeechError.unavailable
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.timeoutInterval = 20
        urlRequest.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        return urlRequest
    }

    private func playAudioData(_ data: Data, onStart: () -> Void) {
        do {
            let player = try AVAudioPlayer(data: data)
            let playbackDelegate = TranslationAudioPlaybackDelegate { [weak self] in
                Task { @MainActor in
                    self?.finishPlayback()
                }
            }
            self.player = player
            self.playbackDelegate = playbackDelegate
            player.delegate = playbackDelegate
            player.prepareToPlay()
            if player.play() {
                onStart()
            } else {
                finishPlayback(error: TranslationSpeechError.unavailable)
            }
        } catch {
            finishPlayback(error: error)
        }
    }

    private func storeAudioData(_ data: Data, for key: String) {
        if audioCache.count > 40 {
            audioCache.removeAll(keepingCapacity: true)
        }
        audioCache[key] = data
    }

    private func finishPlayback(error: Error? = nil) {
        activeTask = nil
        player = nil
        playbackDelegate = nil
        let handler = finishHandler
        finishHandler = nil
        handler?(error)
    }

    private static func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            return
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw TranslationSpeechError.requestFailed("发音服务请求失败（HTTP \(httpResponse.statusCode)）。")
        }
    }

    private static func googleLanguageCode(for code: String?) -> String? {
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

    private static func cacheKey(for request: TranslationSpeechRequest) -> String {
        [
            "google",
            googleLanguageCode(for: request.languageCode) ?? "en",
            request.text
        ].joined(separator: "\u{1f}")
    }
}

@MainActor
final class OpenAITextToSpeechService: TranslationSpeechService {
    typealias ConfigurationProvider = () -> OpenAITextToSpeechConfiguration
    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let configurationProvider: ConfigurationProvider
    private let dataLoader: DataLoader
    private var activeTask: Task<Void, Never>?
    private var player: AVAudioPlayer?
    private var playbackDelegate: TranslationAudioPlaybackDelegate?
    private var finishHandler: ((Error?) -> Void)?
    private var audioCache: [String: Data] = [:]

    init(
        configurationProvider: @escaping ConfigurationProvider,
        dataLoader: @escaping DataLoader = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.configurationProvider = configurationProvider
        self.dataLoader = dataLoader
    }

    func speak(
        _ request: TranslationSpeechRequest,
        onStart: @escaping () -> Void,
        onFinish: @escaping (Error?) -> Void
    ) {
        let trimmedText = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }

        stop()
        finishHandler = onFinish

        let configuration = configurationProvider()
        let isMiMo = Self.isMiMoConfiguration(configuration)
        let voice = Self.speechVoice(for: configuration, isMiMo: isMiMo)
        let cacheKey = Self.cacheKey(
            text: trimmedText,
            languageCode: request.languageCode,
            configuration: configuration,
            voice: voice,
            isMiMo: isMiMo
        )
        if let cachedData = audioCache[cacheKey] {
            playAudioData(cachedData, onStart: onStart)
            return
        }

        activeTask = Task { [weak self, dataLoader] in
            do {
                let urlRequest = try Self.makeRequest(
                    for: TranslationSpeechRequest(
                        text: trimmedText,
                        languageCode: request.languageCode
                    ),
                    configuration: configuration
                )
                let (data, response) = try await dataLoader(urlRequest)
                try Self.validateHTTPResponse(response, data: data)
                guard !Task.isCancelled else {
                    return
                }

                let audioData = try Self.decodeAudioData(from: data)
                self?.storeAudioData(audioData, for: cacheKey)
                self?.playAudioData(audioData, onStart: onStart)
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                self?.finishPlayback(error: error)
            }
        }
    }

    func stop() {
        activeTask?.cancel()
        activeTask = nil
        player?.stop()
        player = nil
        playbackDelegate = nil
        finishHandler = nil
    }

    static func makeRequest(
        for request: TranslationSpeechRequest,
        configuration: OpenAITextToSpeechConfiguration
    ) throws -> URLRequest {
        let trimmedText = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw TranslationValidationError.emptySource
        }

        guard !configuration.normalizedBaseURL.isEmpty,
              !configuration.trimmedAPIKey.isEmpty,
              !configuration.trimmedModel.isEmpty,
              !configuration.trimmedVoice.isEmpty
        else {
            throw TranslationSpeechError.providerNotConfigured
        }

        let isMiMo = isMiMoConfiguration(configuration)
        guard let url = chatCompletionsURL(for: configuration.normalizedBaseURL, isMiMo: isMiMo) else {
            throw TranslationSpeechError.unavailable
        }
        let voice = speechVoice(for: configuration, isMiMo: isMiMo)
        let payload = OpenAITextToSpeechRequestPayload(
            model: configuration.trimmedModel,
            modalities: isMiMo ? nil : ["text", "audio"],
            messages: speechMessages(for: trimmedText, isMiMo: isMiMo),
            audio: OpenAITextToSpeechAudioOptions(
                format: "wav",
                voice: voice
            )
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 45
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("Bearer \(configuration.trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        if isMiMo {
            urlRequest.setValue(configuration.trimmedAPIKey, forHTTPHeaderField: "api-key")
        }
        urlRequest.httpBody = try JSONEncoder().encode(payload)
        return urlRequest
    }

    private func playAudioData(_ data: Data, onStart: () -> Void) {
        do {
            let player = try AVAudioPlayer(data: data)
            let playbackDelegate = TranslationAudioPlaybackDelegate { [weak self] in
                Task { @MainActor in
                    self?.finishPlayback()
                }
            }
            self.player = player
            self.playbackDelegate = playbackDelegate
            player.delegate = playbackDelegate
            player.prepareToPlay()
            if player.play() {
                onStart()
            } else {
                finishPlayback(error: TranslationSpeechError.unavailable)
            }
        } catch {
            finishPlayback(error: error)
        }
    }

    private func storeAudioData(_ data: Data, for key: String) {
        if audioCache.count > 40 {
            audioCache.removeAll(keepingCapacity: true)
        }
        audioCache[key] = data
    }

    private func finishPlayback(error: Error? = nil) {
        activeTask = nil
        player = nil
        playbackDelegate = nil
        let handler = finishHandler
        finishHandler = nil
        handler?(error)
    }

    private static func chatCompletionsURL(for baseURL: String, isMiMo: Bool) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.hasSuffix("/chat/completions") {
            return URL(string: trimmed)
        }

        if isMiMo,
           let url = URL(string: trimmed),
           url.path.isEmpty || url.path == "/" {
            return URL(string: "\(trimmed)/v1/chat/completions")
        }

        return URL(string: "\(trimmed)/chat/completions")
    }

    private static func speechVoice(for configuration: OpenAITextToSpeechConfiguration, isMiMo: Bool) -> String {
        if isMiMo, configuration.trimmedVoice == OpenAITextToSpeechConfiguration.defaultVoice {
            return OpenAITextToSpeechConfiguration.defaultMiMoVoice
        }

        return configuration.trimmedVoice
    }

    private static func cacheKey(
        text: String,
        languageCode: String?,
        configuration: OpenAITextToSpeechConfiguration,
        voice: String,
        isMiMo: Bool
    ) -> String {
        [
            isMiMo ? "mimo" : "chat-audio",
            configuration.normalizedBaseURL,
            configuration.trimmedModel,
            voice,
            languageCode ?? "",
            text
        ].joined(separator: "\u{1f}")
    }

    private static func speechMessages(for text: String, isMiMo: Bool) -> [OpenAITextToSpeechMessage] {
        if isMiMo {
            return [
                OpenAITextToSpeechMessage(
                    role: "user",
                    content: "Use a natural voice and synthesize the assistant message exactly."
                ),
                OpenAITextToSpeechMessage(role: "assistant", content: text)
            ]
        }

        return [
            OpenAITextToSpeechMessage(
                role: "user",
                content: """
                Read the following text aloud exactly as written. Do not add, omit, quote, or explain anything.

                \(text)
                """
            )
        ]
    }

    private static func isMiMoConfiguration(_ configuration: OpenAITextToSpeechConfiguration) -> Bool {
        let baseURL = configuration.normalizedBaseURL.lowercased()
        let model = configuration.trimmedModel.lowercased()
        return baseURL.contains("xiaomimimo") || model.hasPrefix("mimo-")
    }

    private static func decodeAudioData(from data: Data) throws -> Data {
        let decoded = try JSONDecoder().decode(OpenAITextToSpeechResponse.self, from: data)
        guard let encodedAudio = decoded.choices.first?.message.audio?.data,
              let audioData = Data(base64Encoded: encodedAudio),
              !audioData.isEmpty
        else {
            throw TranslationSpeechError.noAudioData
        }

        return audioData
    }

    private static func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            return
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let error = try? JSONDecoder().decode(OpenAITextToSpeechErrorResponse.self, from: data),
               let message = error.message,
               !message.isEmpty {
                throw TranslationSpeechError.requestFailed(message)
            }

            throw TranslationSpeechError.requestFailed("发音服务请求失败（HTTP \(httpResponse.statusCode)）。")
        }
    }
}

private struct OpenAITextToSpeechRequestPayload: Encodable {
    let model: String
    let modalities: [String]?
    let messages: [OpenAITextToSpeechMessage]
    let audio: OpenAITextToSpeechAudioOptions

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encodeIfPresent(modalities, forKey: .modalities)
        try container.encode(messages, forKey: .messages)
        try container.encode(audio, forKey: .audio)
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case modalities
        case messages
        case audio
    }
}

private struct OpenAITextToSpeechMessage: Codable {
    let role: String
    let content: String
}

private struct OpenAITextToSpeechAudioOptions: Codable {
    let format: String
    let voice: String
}

private struct OpenAITextToSpeechResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let audio: Audio?
    }

    struct Audio: Decodable {
        let data: String?
    }
}

private struct OpenAITextToSpeechErrorResponse: Decodable {
    let message: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let nestedError = try? container.decode(OpenAIError.self, forKey: .error),
           let message = nestedError.message {
            self.message = message
            return
        }

        if let error = try? container.decode(String.self, forKey: .error) {
            self.message = error
            return
        }

        self.message = (try? container.decode(String.self, forKey: .message))
            ?? (try? container.decode(String.self, forKey: .msg))
    }

    private enum CodingKeys: String, CodingKey {
        case error
        case message
        case msg
    }

    struct OpenAIError: Decodable {
        let message: String?
    }
}

private final class TranslationAudioPlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        onFinish()
    }
}

extension SystemTranslationSpeechService: @preconcurrency AVSpeechSynthesizerDelegate {
    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        finishSpeech(for: utterance)
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        finishSpeech(for: utterance)
    }
}
