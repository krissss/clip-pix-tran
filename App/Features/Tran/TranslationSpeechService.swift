import AVFoundation
import Foundation

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
    func speak(_ request: TranslationSpeechRequest, onFinish: @escaping () -> Void)
    func stop()
}

@MainActor
final class SystemTranslationSpeechService: NSObject, TranslationSpeechService {
    private let synthesizer: AVSpeechSynthesizer
    private var activeUtterance: AVSpeechUtterance?
    private var finishHandler: (() -> Void)?

    override init() {
        synthesizer = AVSpeechSynthesizer()
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ request: TranslationSpeechRequest, onFinish: @escaping () -> Void) {
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
        handler?()
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
