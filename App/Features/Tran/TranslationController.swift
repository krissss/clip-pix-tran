import Foundation

@MainActor
@Observable
final class TranslationController {
    let history: TranslationHistoryStore
    let preferences: TranslationPreferences

    private let providers: [TranslationProvider]
    private let pasteboard: ClipboardService
    private let speechService: TranslationSpeechService
    private let languageDetector: TranslationLanguageDetecting
    private var historyProviderID: String?
    private var sessionDetectedSourceLanguageCode: String?

    var sourceText = ""
    private(set) var providerStates: [TranslationProviderState]
    private(set) var sourceLanguageCode: String?
    private(set) var targetLanguageCode: String
    var isTranslating = false
    private(set) var speakingTarget: TranslationSpeechTarget?
    var lastErrorMessage: String?

    private static let defaultIdleMessage = "输入文本后点击翻译，结果会显示在这里。"
    private static let historyIdleMessage = "载入历史记录后，可点击翻译刷新其它 provider。"
    private static let disabledProviderMessage = "此 provider 已在设置中关闭。"
    private static let languageDetectionThreshold = 0.3

    var enabledProviders: [TranslationProvider] {
        let providerIDs = Set(providers.map(\.id))
        let enabledProviderIDs = preferences.enabledProviderIDs.filter { providerIDs.contains($0) }
        if enabledProviderIDs.isEmpty {
            return providers.prefix(1).map(\.self)
        }

        return providers.filter { enabledProviderIDs.contains($0.id) }
    }

    var activeProviderStates: [TranslationProviderState] {
        let providerIDs = Set(providers.map(\.id))
        let enabledProviderIDs = preferences.enabledProviderIDs.filter { providerIDs.contains($0) }
        var effectiveProviderIDs = enabledProviderIDs.isEmpty
            ? Set(providers.prefix(1).map(\.id))
            : Set(enabledProviderIDs)
        if let historyProviderID {
            effectiveProviderIDs.insert(historyProviderID)
        }
        return providerStates.filter { state in
            effectiveProviderIDs.contains(state.provider.id)
        }
    }

    var translatedText: String {
        get {
            primarySuccessfulState?.translatedText ?? ""
        }
        set {
            let provider = activeProviderStates.first?.provider
                ?? providers.first?.descriptor
                ?? .systemTranslation
            upsertProviderState(
                provider,
                status: newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? .idle(Self.defaultIdleMessage)
                    : .success,
                result: TranslationResult(
                    translatedText: newValue,
                    sourceLanguageCode: sourceLanguageCode,
                    targetLanguageCode: targetLanguageCode
                )
            )
        }
    }

    var primaryTranslatedText: String? {
        primarySuccessfulState?.translatedText
    }

    var effectiveSourceLanguageCode: String? {
        sourceLanguageCode ?? detectedSourceLanguageCode
    }

    private var primarySuccessfulState: TranslationProviderState? {
        activeProviderStates.first { state in
            if case .success = state.status {
                return !state.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }

            return false
        }
    }

    init(
        history: TranslationHistoryStore? = nil,
        preferences: TranslationPreferences? = nil,
        translationService: TranslationService? = nil,
        providers: [TranslationProvider]? = nil,
        pasteboard: ClipboardService,
        speechService: TranslationSpeechService? = nil,
        languageDetector: TranslationLanguageDetecting? = nil
    ) {
        self.history = history ?? TranslationHistoryStore()
        self.preferences = preferences ?? TranslationPreferences()
        if let providers {
            self.providers = providers
        } else if let translationService {
            self.providers = [
                TranslationProvider(
                    descriptor: .systemTranslation,
                    service: translationService
                )
            ]
        } else {
            self.providers = TranslationProvider.builtIn()
        }
        self.pasteboard = pasteboard
        self.speechService = speechService ?? SystemTranslationSpeechService()
        self.languageDetector = languageDetector ?? NaturalLanguageTranslationLanguageDetector()
        self.sourceLanguageCode = self.preferences.defaultSourceLanguageCode
        self.targetLanguageCode = self.preferences.defaultTargetLanguageCode
        self.providerStates = self.providers.map { provider in
            TranslationProviderState(
                provider: provider.descriptor,
                status: .idle(Self.defaultIdleMessage),
                result: nil
            )
        }
    }

    func selectSourceLanguage(_ code: String?, persistsDefault: Bool = true) {
        guard let code else {
            guard sourceLanguageCode != nil else {
                return
            }

            sourceLanguageCode = nil
            if persistsDefault {
                preferences.updateDefaultSourceLanguage(nil)
            }
            resetProviderResults()
            return
        }

        guard TranslationLanguage.isSupportedSource(code) else {
            return
        }

        guard code != sourceLanguageCode else {
            return
        }

        sourceLanguageCode = code
        autoAdjustTargetLanguage(forSourceLanguage: code)
        if persistsDefault {
            preferences.updateDefaultSourceLanguage(code)
        }
        resetProviderResults()
    }

    func selectTargetLanguage(_ code: String, persistsDefault: Bool = true) {
        guard TranslationLanguage.isSupported(code) else {
            return
        }

        guard code != targetLanguageCode else {
            return
        }

        targetLanguageCode = code
        autoAdjustTargetLanguageForCurrentSource()
        if persistsDefault {
            preferences.updateDefaultTargetLanguage(code)
        }
        resetProviderResults()
    }

    func setProvider(_ providerID: String, isEnabled: Bool) {
        preferences.updateEnabledProvider(providerID, isEnabled: isEnabled)
        resetDisabledProviderStates()
    }

    func translate() async {
        let trimmedText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            lastErrorMessage = TranslationValidationError.emptySource.localizedDescription
            setActiveProviderStates(
                status: .failed(TranslationValidationError.emptySource.localizedDescription),
                result: nil
            )
            return
        }

        guard !isTranslating else {
            return
        }

        historyProviderID = nil
        let activeProviders = enabledProviders
        guard !activeProviders.isEmpty else {
            lastErrorMessage = TranslationProviderError.noEnabledProviders.localizedDescription
            return
        }

        isTranslating = true
        lastErrorMessage = nil
        setActiveProviderStates(status: .loading("正在翻译..."), result: nil)
        defer { isTranslating = false }

        let languageResolution = resolveLanguages(for: trimmedText)
        sessionDetectedSourceLanguageCode = languageResolution.detectedSourceLanguageCode

        let request = TranslationRequest(
            sourceText: trimmedText,
            targetLanguageCode: languageResolution.targetLanguageCode,
            sourceLanguageCode: languageResolution.sourceLanguageCode
        )

        var successfulResults: [TranslationProviderResult] = []
        var failureMessages: [String] = []

        for provider in activeProviders {
            do {
                let result = try await provider.service.translate(request)
                let providerResult = TranslationProviderResult(
                    provider: provider.descriptor,
                    result: result
                )
                successfulResults.append(providerResult)
                upsertProviderState(
                    provider.descriptor,
                    status: .success,
                    result: result
                )
                history.record(request: request, providerResult: providerResult)
            } catch {
                let message = error.localizedDescription
                let displayMessage = activeProviders.count > 1
                    ? "\(provider.descriptor.name): \(message)"
                    : message
                failureMessages.append(displayMessage)
                upsertProviderState(
                    provider.descriptor,
                    status: .failed(message),
                    result: nil
                )
            }
        }

        if successfulResults.isEmpty {
            lastErrorMessage = failureMessages.first
        } else {
            lastErrorMessage = nil
        }
    }

    func prefillSourceText(_ text: String) {
        stopSpeech()
        sourceText = text
        resetProviderResults()
    }

    func editSourceText(_ text: String) {
        guard text != sourceText else {
            return
        }

        stopSpeech()
        sourceText = text
        resetProviderResults()
    }

    func copyResultToPasteboard() {
        guard let state = primarySuccessfulState else {
            return
        }

        copyResultToPasteboard(providerID: state.provider.id)
    }

    func copyResultToPasteboard(providerID: String) {
        guard let state = providerStates.first(where: { $0.provider.id == providerID }) else {
            return
        }

        let trimmedText = state.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }

        do {
            try pasteboard.writePlainText(state.translatedText)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            upsertProviderState(
                state.provider,
                status: .failed(error.localizedDescription),
                result: state.result
            )
        }
    }

    func copySourceToPasteboard() {
        let trimmedText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }

        do {
            try pasteboard.writePlainText(sourceText)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func speakSourceText() {
        let trimmedText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }

        speak(
            target: .source,
            TranslationSpeechRequest(
                text: trimmedText,
                languageCode: sourceLanguageCode ?? detectedSourceLanguageCode
            )
        )
    }

    func speakResult(providerID: String) {
        guard let state = providerStates.first(where: { $0.provider.id == providerID }) else {
            return
        }

        let trimmedText = state.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }

        speak(
            target: .result(providerID: providerID),
            TranslationSpeechRequest(
                text: trimmedText,
                languageCode: state.result?.targetLanguageCode ?? targetLanguageCode
            )
        )
    }

    func stopSpeech() {
        guard speakingTarget != nil else {
            return
        }

        speakingTarget = nil
        speechService.stop()
    }

    func isSpeakingResult(providerID: String) -> Bool {
        speakingTarget == .result(providerID: providerID)
    }

    func useHistoryItem(_ item: TranslationHistoryItem) {
        sourceText = item.sourceText
        sourceLanguageCode = item.sourceLanguageCode
        targetLanguageCode = item.targetLanguageCode
        historyProviderID = item.providerID
        let historyState = TranslationProviderState(
            provider: TranslationProviderDescriptor.descriptor(for: item.providerID),
            status: .success,
            result: TranslationResult(
                translatedText: item.translatedText,
                sourceLanguageCode: item.detectedSourceLanguageCode,
                targetLanguageCode: item.targetLanguageCode
            )
        )
        providerStates = providers.map { provider in
            if provider.id == item.providerID {
                return historyState
            }

            return TranslationProviderState(
                provider: provider.descriptor,
                status: .idle(Self.historyIdleMessage),
                result: nil
            )
        }
        if !providerStates.contains(where: { $0.provider.id == item.providerID }) {
            providerStates.insert(historyState, at: 0)
        }
        lastErrorMessage = nil
    }

    func deleteHistoryItem(_ item: TranslationHistoryItem) {
        history.delete(item)
    }

    func clearHistory() {
        history.clear()
    }

    private func setActiveProviderStates(
        status: TranslationProviderStatus,
        result: TranslationResult?
    ) {
        for provider in enabledProviders {
            upsertProviderState(provider.descriptor, status: status, result: result)
        }
    }

    private func resetDisabledProviderStates() {
        let enabledProviderIDs = Set(preferences.enabledProviderIDs)
        providerStates = providerStates.map { state in
            if historyProviderID == state.provider.id {
                return state
            }

            if enabledProviderIDs.contains(state.provider.id) {
                if case .idle(let message) = state.status,
                   message == Self.disabledProviderMessage,
                   state.result == nil {
                    return TranslationProviderState(
                        provider: state.provider,
                        status: .idle(Self.defaultIdleMessage),
                        result: nil
                    )
                }

                return state
            }

            return TranslationProviderState(
                provider: state.provider,
                status: .idle(Self.disabledProviderMessage),
                result: nil
            )
        }
    }

    private func resetProviderResults() {
        historyProviderID = nil
        sessionDetectedSourceLanguageCode = nil
        providerStates = providerStates.map { state in
            TranslationProviderState(
                provider: state.provider,
                status: .idle(Self.defaultIdleMessage),
                result: nil
            )
        }
        lastErrorMessage = nil
    }

    private var detectedSourceLanguageCode: String? {
        sessionDetectedSourceLanguageCode
            ?? activeProviderStates.compactMap(\.detectedSourceLanguageCode).first
    }

    private func resolveLanguages(for text: String) -> LanguageResolution {
        if let sourceLanguageCode {
            return LanguageResolution(
                sourceLanguageCode: sourceLanguageCode,
                detectedSourceLanguageCode: sourceLanguageCode,
                targetLanguageCode: resolvedTargetLanguage(forDetectedSource: sourceLanguageCode)
            )
        }

        let detectedLanguageCode = languageDetector.detect(
            text,
            threshold: Self.languageDetectionThreshold,
            preferredSourceHints: languageDetectionHints()
        ).languageCode

        return LanguageResolution(
            sourceLanguageCode: detectedLanguageCode,
            detectedSourceLanguageCode: detectedLanguageCode,
            targetLanguageCode: resolvedTargetLanguage(forDetectedSource: detectedLanguageCode)
        )
    }

    private func resolvedTargetLanguage(forDetectedSource detectedSourceLanguageCode: String?) -> String {
        guard let detectedSourceLanguageCode else {
            return targetLanguageCode
        }

        if TranslationLanguage.isChinese(detectedSourceLanguageCode),
           TranslationLanguage.isChinese(targetLanguageCode) {
            return "en"
        }

        if detectedSourceLanguageCode == targetLanguageCode {
            return TranslationLanguage.isChinese(detectedSourceLanguageCode) ? "en" : "zh-Hans"
        }

        return targetLanguageCode
    }

    private func languageDetectionHints() -> [String: Double]? {
        var hints: [String: Double] = [:]
        switch targetLanguageCode {
        case let code where code.hasPrefix("zh"):
            hints["en", default: 0] += 0.2
            hints["ja", default: 0] += 0.1
            hints["ko", default: 0] += 0.05
        case "en":
            hints["zh-Hans", default: 0] += 0.2
            hints["ja", default: 0] += 0.1
            hints["ko", default: 0] += 0.05
            hints["fr", default: 0] += 0.05
            hints["de", default: 0] += 0.05
        case "ja":
            hints["en", default: 0] += 0.2
            hints["zh-Hans", default: 0] += 0.1
        case "ko":
            hints["en", default: 0] += 0.2
            hints["zh-Hans", default: 0] += 0.1
            hints["ja", default: 0] += 0.05
        case "fr", "de":
            hints["en", default: 0] += 0.2
            hints["fr", default: 0] += 0.05
            hints["de", default: 0] += 0.05
        default:
            break
        }

        hints.removeValue(forKey: targetLanguageCode)
        return hints.isEmpty ? nil : hints
    }

    private func autoAdjustTargetLanguageForCurrentSource() {
        guard let sourceLanguageCode else {
            return
        }

        autoAdjustTargetLanguage(forSourceLanguage: sourceLanguageCode)
    }

    private func autoAdjustTargetLanguage(forSourceLanguage sourceLanguageCode: String) {
        let resolvedTargetLanguage = resolvedTargetLanguage(forDetectedSource: sourceLanguageCode)
        guard resolvedTargetLanguage != targetLanguageCode else {
            return
        }

        targetLanguageCode = resolvedTargetLanguage
    }

    private func speak(
        target: TranslationSpeechTarget,
        _ request: TranslationSpeechRequest
    ) {
        if speakingTarget == target {
            stopSpeech()
            return
        }

        if speakingTarget != nil {
            stopSpeech()
        }
        speakingTarget = target
        speechService.speak(request) { [weak self] in
            guard self?.speakingTarget == target else {
                return
            }

            self?.speakingTarget = nil
        }
    }

    private func upsertProviderState(
        _ provider: TranslationProviderDescriptor,
        status: TranslationProviderStatus,
        result: TranslationResult?
    ) {
        if let index = providerStates.firstIndex(where: { $0.provider.id == provider.id }) {
            providerStates[index] = TranslationProviderState(
                provider: provider,
                status: status,
                result: result
            )
        } else {
            providerStates.append(
                TranslationProviderState(
                    provider: provider,
                    status: status,
                    result: result
                )
            )
        }
    }
}

private struct LanguageResolution {
    let sourceLanguageCode: String?
    let detectedSourceLanguageCode: String?
    let targetLanguageCode: String
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
