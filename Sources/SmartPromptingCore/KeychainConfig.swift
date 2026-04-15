import Foundation
#if canImport(Security)
import Security
#endif

/// Stores a single API key in the macOS/iOS Keychain.
/// Falls back to a `SMART_PROMPTING_ANTHROPIC_KEY` env var on non-Apple platforms.
public enum KeychainConfig {
    public static let service = "com.smartprompting.api"
    public static let anthropicAccount = "anthropic"

    public static func anthropicAPIKey() -> String? {
        if let fromEnv = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
           !fromEnv.isEmpty {
            return fromEnv
        }
        if let fromAlias = ProcessInfo.processInfo.environment["SMART_PROMPTING_ANTHROPIC_KEY"],
           !fromAlias.isEmpty {
            return fromAlias
        }
        #if canImport(Security)
        return read(account: anthropicAccount)
        #else
        return nil
        #endif
    }

    @discardableResult
    public static func setAnthropicAPIKey(_ key: String) -> Bool {
        #if canImport(Security)
        return write(account: anthropicAccount, value: key)
        #else
        return false
        #endif
    }

    @discardableResult
    public static func clearAnthropicAPIKey() -> Bool {
        #if canImport(Security)
        return delete(account: anthropicAccount)
        #else
        return false
        #endif
    }

    // MARK: - Keychain primitives

    #if canImport(Security)
    private static func baseQuery(account: String) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func read(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func write(account: String, value: String) -> Bool {
        let data = Data(value.utf8)
        let query = baseQuery(account: account)
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let attrs: [String: Any] = [kSecValueData as String: data]
            return SecItemUpdate(query as CFDictionary, attrs as CFDictionary) == errSecSuccess
        }
        var add = query
        add[kSecValueData as String] = data
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    private static func delete(account: String) -> Bool {
        SecItemDelete(baseQuery(account: account) as CFDictionary) == errSecSuccess
    }
    #endif
}
