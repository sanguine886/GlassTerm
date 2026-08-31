import Foundation
import NIOCore
import NIOSSH

/// TOFU host-key validator wired into the NIOSSH handshake (spec §4.1).
///
/// Runs synchronously on the NIO event loop: fingerprint the presented key,
/// record it for the caller, then accept only if it matches the pinned key.
/// Unknown or changed keys decline the handshake; `SSHSession` inspects
/// `presentedFingerprint()` to surface `hostKeyUnknown` / `hostKeyChanged`.
public final class TOFUHostKeyValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let knownHosts: KnownHostsStore
    private let hostIdentifier: String
    private let presentedBox = FingerprintBox()

    public init(knownHosts: KnownHostsStore, hostIdentifier: String) {
        self.knownHosts = knownHosts
        self.hostIdentifier = hostIdentifier
    }

    public func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        do {
            let fingerprint = try HostKeyFingerprint.make(from: hostKey)
            presentedBox.set(fingerprint)
            switch knownHosts.verify(hostIdentifier: hostIdentifier, fingerprint: fingerprint) {
            case .trusted:
                validationCompletePromise.succeed(())
            case .newHost, .changed:
                validationCompletePromise.fail(SSHError.hostKeyVerificationDeclined)
            }
        } catch {
            validationCompletePromise.fail(error)
        }
    }

    /// The fingerprint presented by the server during the last handshake.
    public func presentedFingerprint() -> HostKeyFingerprint? {
        presentedBox.get()
    }
}

/// Thread-safe single-value box for the last presented fingerprint.
final class FingerprintBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: HostKeyFingerprint?

    func set(_ fingerprint: HostKeyFingerprint) {
        lock.lock()
        value = fingerprint
        lock.unlock()
    }

    func get() -> HostKeyFingerprint? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
