import Foundation

struct HybridTranslationService: TranslationService {
    private let primary: TranslationService
    private let fallback: TranslationService

    init(
        primary: TranslationService = SystemTranslationService(),
        fallback: TranslationService = FallbackTranslationService()
    ) {
        self.primary = primary
        self.fallback = fallback
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        do {
            return try await primary.translate(request)
        } catch TranslationValidationError.emptySource {
            throw TranslationValidationError.emptySource
        } catch {
            return try await fallback.translate(request)
        }
    }
}
