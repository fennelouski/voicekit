//
//  KeychainStore.swift
//  Dictate
//
//  Minimal generic-password storage. The Anthropic API key lives here —
//  never in UserDefaults, never in logs.
//

#if os(macOS)
import Foundation
import Security

enum KeychainStore {
    private static let service = "studio.100apps.Dictate"

    static func string(forKey account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Nil or empty deletes the item.
    static func set(_ value: String?, forKey account: String) {
        // ponytail: delete-then-add instead of the add/update dance
        SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var query = baseQuery(account: account)
        query[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
#endif
