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
    @discardableResult
    static func set(_ value: String?, forKey account: String) -> Bool {
        let query = baseQuery(account: account)
        guard let value, !value.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let attributes = [kSecValueData as String: Data(value.utf8)]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return true }
        // A failed update must never delete a previously valid key.
        guard updated == errSecItemNotFound else { return false }
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        let added = SecItemAdd(item as CFDictionary, nil)
        if added == errSecDuplicateItem {
            return SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecSuccess
        }
        return added == errSecSuccess
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
