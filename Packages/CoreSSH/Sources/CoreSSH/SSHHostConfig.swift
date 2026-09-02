import Foundation

/// Authentication credentials for one connection. Secrets live here only in
/// memory; at rest they are Keychain-managed by the Persistence package.
public enum SSHAuthMethod: Equatable, Sendable {
    case password(String)
    /// OpenSSH-format private key content (ED25519 or RSA) with optional passphrase.
    case privateKey(pem: String, passphrase: String?)
}

/// Everything needed to open one SSH connection.
public struct SSHHostConfig: Equatable, Sendable {
    public var host: String
    public var port: Int
    public var username: String
    public var auth: SSHAuthMethod
    /// SSH keepalive cadence in seconds (spec §4.1: default 15, configurable).
    public var keepaliveIntervalSeconds: Int

    public init(
        host: String,
        port: Int = 22,
        username: String,
        auth: SSHAuthMethod,
        keepaliveIntervalSeconds: Int = 15
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.auth = auth
        self.keepaliveIntervalSeconds = max(5, keepaliveIntervalSeconds)
    }

    /// Stable key for known-hosts pinning.
    public var hostIdentifier: String {
        "\(host):\(port)"
    }
}
