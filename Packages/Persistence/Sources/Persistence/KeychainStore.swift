import Foundation
import Security

/// Storage abstraction for secrets (spec §6.3.1: passwords, keys, passphrases,
/// AI API keys live ONLY here — never SwiftData, logs, or UserDefaults).
public protocol SecretStoring: Sendable {
    func save(_ secret: String, account: String) throws
    func load(account: String) throws -> String?
    func delete(account: String) throws
}

public enum SecretStoreError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case encodingFailed
}

/// Keychain-backed implementation with `ThisDeviceOnly` accessibility, so
/// secrets never migrate to a new device through backups (spec §6.3.1).
public final class KeychainStore: SecretStoring, @unchecked Sendable {
    private let service: String

    public init(service: String = "com.glazeverre.GlazeVerre.secrets") {
        self.service = service
    }

    public func save(_ secret: String, account: String) throws {
        guard let data = secret.data(using: .utf8) else {
            throw SecretStoreError.encodingFailed
        }
        // Replace-or-add semantics: best-effort removal of any previous value.
        try? delete(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecretStoreError.unexpectedStatus(status)
        }
    }

    public func load(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw SecretStoreError.encodingFailed }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw SecretStoreError.unexpectedStatus(status)
        }
    }

    public func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw SecretStoreError.unexpectedStatus(status)
        }
    }
}
