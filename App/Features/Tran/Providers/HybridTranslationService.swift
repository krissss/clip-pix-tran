import Foundation

struct HybridTranslationService: TranslationService {
    private let primary: TranslationService
    private let fallback: TranslationService
    private let primaryRetryDelayNanoseconds: UInt64

    init(
        primary: TranslationService = SystemTranslationService(),
        fallback: TranslationService = FallbackTranslationService(),
        primaryRetryDelayNanoseconds: UInt64 = 150_000_000
    ) {
        self.primary = primary
        self.fallback = fallback
        self.primaryRetryDelayNanoseconds = primaryRetryDelayNanoseconds
    }

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        do {
            return try await primary.translate(request)
        } catch TranslationValidationError.emptySource {
            throw TranslationValidationError.emptySource
        } catch let error as CancellationError {
            throw error
        } catch {
            do {
                return try await retryPrimary(request)
            } catch TranslationValidationError.emptySource {
                throw TranslationValidationError.emptySource
            } catch let error as CancellationError {
                throw error
            } catch {
                return try await fallback.translate(request)
            }
        }
    }

    private func retryPrimary(_ request: TranslationRequest) async throws -> TranslationResult {
        if primaryRetryDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: primaryRetryDelayNanoseconds)
        }

        return try await primary.translate(request)
    }
}
