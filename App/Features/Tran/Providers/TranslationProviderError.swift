import Foundation

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
