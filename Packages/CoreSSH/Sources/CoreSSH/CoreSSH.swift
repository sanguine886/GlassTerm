/// CoreSSH — SSH/SFTP engine built on Citadel (SwiftNIO SSH).
///
/// Pure logic, no UI imports (spec §6.1.2). The public surface is exposed through
/// protocols so UI depends on abstractions (spec §3.3).
///
/// Scope by phase: connection/auth/known-hosts TOFU/reconnect backoff/keepalive/exec/PTY
/// land in P1; SFTP client in P3. Dependencies are pinned exact-version when first
/// used (ADR-0002 in docs/ARCHITECTURE.md).
public enum CoreSSHInfo {
    public static let moduleName = "CoreSSH"
}
