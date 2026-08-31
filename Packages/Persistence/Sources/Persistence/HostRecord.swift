import Foundation
import SwiftData

/// How a host authenticates. The secret itself is never stored here — only a
/// Keychain account reference (spec §6.3.1).
public enum HostAuthKind: String, Codable, Sendable {
    case password
    case privateKey
}

/// SwiftData model for one managed server.
/// Audit rule (spec §8): no property may ever hold a password, key material,
/// or passphrase — those live in the Keychain behind `secretRef`.
@Model
public final class HostRecord {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var hostname: String
    public var port: Int
    public var username: String
    public var authKindRaw: String
    public var secretRef: String?
    /// Separate reference for the optional key passphrase.
    public var passphraseRef: String?
    public var group: String?
    public var createdAt: Date
    public var lastConnectedAt: Date?

    public var authKind: HostAuthKind {
        get { HostAuthKind(rawValue: authKindRaw) ?? .password }
        set { authKindRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        name: String,
        hostname: String,
        port: Int = 22,
        username: String,
        authKind: HostAuthKind = .password,
        secretRef: String? = nil,
        passphraseRef: String? = nil,
        group: String? = nil,
        createdAt: Date = Date(),
        lastConnectedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.port = port
        self.username = username
        authKindRaw = authKind.rawValue
        self.secretRef = secretRef
        self.passphraseRef = passphraseRef
        self.group = group
        self.createdAt = createdAt
        self.lastConnectedAt = lastConnectedAt
    }
}
