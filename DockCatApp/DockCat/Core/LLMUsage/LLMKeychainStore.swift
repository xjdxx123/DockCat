import Foundation
import Security

final class LLMKeychainStore {
    private let service: String

    init(service: String = "com.dockcat.llm-usage") {
        self.service = service
    }

    func save(_ key: String, for provider: LLMProviderID) throws {
        try? delete(provider)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw LLMUsageError.keychain(status: status)
        }
    }

    func load(_ provider: LLMProviderID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            DockCatLog.app.error("LLMKeychainStore.load failed for \(provider.rawValue) with status \(status)")
            return nil
        }
    }

    func delete(_ provider: LLMProviderID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw LLMUsageError.keychain(status: status)
        }
    }

    func hasKey(for provider: LLMProviderID) -> Bool {
        load(provider) != nil
    }
}
