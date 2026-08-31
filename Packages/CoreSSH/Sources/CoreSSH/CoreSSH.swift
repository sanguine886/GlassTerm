/// CoreSSH — SSH/SFTP engine built on Citadel (SwiftNIO SSH).
///
/// Pure logic, no UI imports (spec §6.1.2). The public surface is exposed
/// through protocols (`SSHTransport`, `SSHTransportMaking`) so UI depends on
/// abstractions (spec §3.3).
///
/// P1 scope: connection, authentication (password / OpenSSH ED25519+RSA key),
/// known-hosts TOFU with SHA256 fingerprints, exponential-backoff reconnect,
/// keepalive, exec, interactive shell streams. SFTP client lands in P3.
public enum CoreSSHInfo {
    public static let moduleName = "CoreSSH"
}
