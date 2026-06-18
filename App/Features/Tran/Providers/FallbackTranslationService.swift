import Foundation

struct FallbackTranslationService: TranslationService {
    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        let sourceText = request.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else {
            throw TranslationValidationError.emptySource
        }

        guard let translatedText = LocalTranslationDictionary.translate(
            sourceText,
            targetLanguageCode: request.targetLanguageCode
        ) else {
            throw TranslationProviderError.unavailable
        }

        return TranslationResult(
            translatedText: translatedText,
            sourceLanguageCode: request.sourceLanguageCode,
            targetLanguageCode: request.targetLanguageCode
        )
    }
}

private enum LocalTranslationDictionary {
    private static let translations: [String: [String: String]] = [
        "hello": [
            "zh-Hans": "你好",
            "en": "Hello",
            "ja": "こんにちは",
            "ko": "안녕하세요",
            "fr": "Bonjour",
            "de": "Hallo"
        ],
        "hello world": [
            "zh-Hans": "你好，世界",
            "en": "Hello, world",
            "ja": "こんにちは、世界",
            "ko": "안녕하세요, 세상",
            "fr": "Bonjour, le monde",
            "de": "Hallo, Welt"
        ],
        "hi": [
            "zh-Hans": "你好",
            "en": "Hi",
            "ja": "やあ",
            "ko": "안녕",
            "fr": "Salut",
            "de": "Hi"
        ],
        "good morning": [
            "zh-Hans": "早上好",
            "en": "Good morning",
            "ja": "おはようございます",
            "ko": "좋은 아침",
            "fr": "Bonjour",
            "de": "Guten Morgen"
        ],
        "good afternoon": [
            "zh-Hans": "下午好",
            "en": "Good afternoon",
            "ja": "こんにちは",
            "ko": "좋은 오후",
            "fr": "Bon après-midi",
            "de": "Guten Tag"
        ],
        "good evening": [
            "zh-Hans": "晚上好",
            "en": "Good evening",
            "ja": "こんばんは",
            "ko": "좋은 저녁",
            "fr": "Bonsoir",
            "de": "Guten Abend"
        ],
        "good night": [
            "zh-Hans": "晚安",
            "en": "Good night",
            "ja": "おやすみなさい",
            "ko": "안녕히 주무세요",
            "fr": "Bonne nuit",
            "de": "Gute Nacht"
        ],
        "thank you": [
            "zh-Hans": "谢谢",
            "en": "Thank you",
            "ja": "ありがとうございます",
            "ko": "감사합니다",
            "fr": "Merci",
            "de": "Danke"
        ],
        "thanks": [
            "zh-Hans": "谢谢",
            "en": "Thanks",
            "ja": "ありがとう",
            "ko": "고마워",
            "fr": "Merci",
            "de": "Danke"
        ],
        "yes": [
            "zh-Hans": "是",
            "en": "Yes",
            "ja": "はい",
            "ko": "네",
            "fr": "Oui",
            "de": "Ja"
        ],
        "no": [
            "zh-Hans": "不是",
            "en": "No",
            "ja": "いいえ",
            "ko": "아니요",
            "fr": "Non",
            "de": "Nein"
        ],
        "copy": [
            "zh-Hans": "复制",
            "en": "Copy",
            "ja": "コピー",
            "ko": "복사",
            "fr": "Copier",
            "de": "Kopieren"
        ],
        "clipboard": [
            "zh-Hans": "剪贴板",
            "en": "Clipboard",
            "ja": "クリップボード",
            "ko": "클립보드",
            "fr": "Presse-papiers",
            "de": "Zwischenablage"
        ],
        "screenshot": [
            "zh-Hans": "截图",
            "en": "Screenshot",
            "ja": "スクリーンショット",
            "ko": "스크린샷",
            "fr": "Capture d'écran",
            "de": "Bildschirmfoto"
        ],
        "translate": [
            "zh-Hans": "翻译",
            "en": "Translate",
            "ja": "翻訳",
            "ko": "번역",
            "fr": "Traduire",
            "de": "Übersetzen"
        ],
        "translation": [
            "zh-Hans": "翻译",
            "en": "Translation",
            "ja": "翻訳",
            "ko": "번역",
            "fr": "Traduction",
            "de": "Übersetzung"
        ],
        "settings": [
            "zh-Hans": "设置",
            "en": "Settings",
            "ja": "設定",
            "ko": "설정",
            "fr": "Réglages",
            "de": "Einstellungen"
        ],
        "history": [
            "zh-Hans": "历史记录",
            "en": "History",
            "ja": "履歴",
            "ko": "기록",
            "fr": "Historique",
            "de": "Verlauf"
        ]
    ]

    static func translate(
        _ sourceText: String,
        targetLanguageCode: String
    ) -> String? {
        let normalizedText = sourceText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return translations[normalizedText]?[targetLanguageCode]
    }
}

enum TranslationProviderError: LocalizedError, Equatable {
    case unavailable
    case noEnabledProviders
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            L10n.tranProviderUnavailable
        case .noEnabledProviders:
            L10n.tranProviderNoneEnabled
        case .requestFailed(let message):
            message
        }
    }
}
