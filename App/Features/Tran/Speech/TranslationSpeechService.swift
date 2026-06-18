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

    static let builtIn: [TranslationSpeechProviderDescriptor] = [
        .system,
        .google
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
    static func builtIn() -> [TranslationSpeechProvider] {
        return [
            TranslationSpeechProvider(
                descriptor: .system,
                service: SystemTranslationSpeechService()
            ),
            TranslationSpeechProvider(
                descriptor: .google,
                service: GoogleTranslationSpeechService()
            )
        ]
    }
}

enum TranslationSpeechError: LocalizedError, Equatable {
    case unavailable
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            L10n.speechProviderUnavailable
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
            throw TranslationSpeechError.requestFailed(L10n.speechRequestFailed(statusCode: httpResponse.statusCode))
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
