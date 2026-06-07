import Foundation
import Security

protocol TranslationSecretStore {
    func openAICompatibleAPIKey() -> String
    func updateOpenAICompatibleAPIKey(_ apiKey: String)
}

final class KeychainTranslationSecretStore: TranslationSecretStore {
    private let service = "com.kriss.ClipPixTran.translation"
    private let account = "openai-compatible-api-key"

    func openAICompatibleAPIKey() -> String {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return ""
        }

        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            return ""
        }

        return value
    }

    func updateOpenAICompatibleAPIKey(_ apiKey: String) {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else {
            SecItemDelete(baseQuery() as CFDictionary)
            return
        }

        let data = Data(trimmedAPIKey.utf8)
        let status = SecItemUpdate(
            baseQuery() as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecSuccess {
            return
        }

        var addQuery = baseQuery()
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
