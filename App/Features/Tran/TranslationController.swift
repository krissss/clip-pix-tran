import Foundation

@MainActor
@Observable
final class TranslationController {
    let history: TranslationHistoryStore

    let preferences: TranslationPreferences
    private let translationService: TranslationService
    private let pasteboard: ClipboardService

    var sourceText = ""
    var translatedText = ""
    private(set) var targetLanguageCode: String
    var isTranslating = false
    var lastErrorMessage: String?

    init(
        history: TranslationHistoryStore? = nil,
        preferences: TranslationPreferences? = nil,
        translationService: TranslationService,
        pasteboard: ClipboardService
    ) {
        self.history = history ?? TranslationHistoryStore()
        self.preferences = preferences ?? TranslationPreferences()
        self.translationService = translationService
        self.pasteboard = pasteboard
        self.targetLanguageCode = self.preferences.defaultTargetLanguageCode
    }

    func selectTargetLanguage(_ code: String) {
        guard TranslationLanguage.isSupported(code) else {
            return
        }

        targetLanguageCode = code
        preferences.updateDefaultTargetLanguage(code)
    }

    func translate() async {
        let trimmedText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            lastErrorMessage = TranslationValidationError.emptySource.localizedDescription
            return
        }

        guard !isTranslating else {
            return
        }

        isTranslating = true
        defer { isTranslating = false }

        let request = TranslationRequest(
            sourceText: trimmedText,
            targetLanguageCode: targetLanguageCode,
            sourceLanguageCode: nil
        )

        do {
            let result = try await translationService.translate(request)
            translatedText = result.translatedText
            history.record(request: request, result: result)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func prefillSourceText(_ text: String) {
        sourceText = text
        translatedText = ""
        lastErrorMessage = nil
    }

    func copyResultToPasteboard() {
        let trimmedText = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }

        do {
            try pasteboard.writePlainText(translatedText)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func useHistoryItem(_ item: TranslationHistoryItem) {
        sourceText = item.sourceText
        translatedText = item.translatedText
        targetLanguageCode = item.targetLanguageCode
        lastErrorMessage = nil
    }

    func deleteHistoryItem(_ item: TranslationHistoryItem) {
        history.delete(item)
    }

    func clearHistory() {
        history.clear()
    }
}

enum TranslationValidationError: LocalizedError, Equatable {
    case emptySource

    var errorDescription: String? {
        switch self {
        case .emptySource:
            "请输入要翻译的文本。"
        }
    }
}
