import Foundation
import Security

/// The WordPress.com access token, in the login keychain as a generic password.
/// No data-protection or sync flags: those need entitlements this build cannot carry.
enum KeychainStore {
    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: WPComConfig.keychainService,
            kSecAttrAccount as String: "default",
        ]
    }

    static func saveToken(_ token: String) throws {
        let data = Data(token.utf8)
        var add = baseQuery
        add[kSecAttrLabel as String] = "Loominate WordPress.com"
        add[kSecValueData as String] = data
        var status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
        guard status == errSecSuccess else { throw WPComError.keychain(status) }
    }

    static func loadToken() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            throw WPComError.keychainAccessDenied
        default:
            throw WPComError.keychain(status)
        }
    }

    /// Attribute-only lookup: does not trigger the keychain access prompt.
    static func hasToken() -> Bool {
        var query = baseQuery
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }

    static func deleteToken() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw WPComError.keychain(status) }
    }
}
