import Foundation

/// Explicit error model for the SSH engine (spec §6.2.3).
/// UI layers map these to localized user-facing copy.
public enum SSHError: Error, Equatable, Sendable {
    case invalidConfiguration(String)
    case connectionFailed(String)
    case authenticationFailed
    case connectionLost
    case timedOut
    case cancelled
    case sessionNotConnected
    case keyParseFailed(String)
    /// Host key not pinned yet — first contact (TOFU prompt required).
    case hostKeyUnknown(fingerprint: HostKeyFingerprint)
    /// Host key differs from the pinned one — connection must be blocked.
    case hostKeyChanged(pinned: HostKeyFingerprint, presented: HostKeyFingerprint)
    /// Host key algorithm could not be fingerprinted.
    case hostKeyUnsupported(String)
    /// Internal marker: the TOFU validator declined the key during handshake.
    case hostKeyVerificationDeclined
}

extension SSHError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let detail):
            "Invalid host configuration: \(detail)"
        case .connectionFailed(let detail):
            "Connection failed: \(detail)"
        case .authenticationFailed:
            "Authentication failed. Check username, password or key."
        case .connectionLost:
            "Connection lost."
        case .timedOut:
            "Connection timed out."
        case .cancelled:
            "Operation cancelled."
        case .sessionNotConnected:
            "Not connected."
        case .keyParseFailed(let detail):
            "Could not read the private key: \(detail)"
        case .hostKeyUnknown(let fingerprint):
            "Unknown host key. Fingerprint \(fingerprint.sha256)"
        case .hostKeyChanged(let pinned, let presented):
            "Host key changed! Pinned \(pinned.sha256), server now presents \(presented.sha256)."
        case .hostKeyUnsupported(let detail):
            "Unsupported host key: \(detail)"
        case .hostKeyVerificationDeclined:
            "Host key verification declined."
        }
    }
}
