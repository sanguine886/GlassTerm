import CoreSSH
import Foundation

/// Remote command execution abstraction used by the agent loop.
///
/// Production wraps `SSHSession` (dependency direction `AIAgent → CoreSSH`);
/// the agent tests inject a fake. Commands run on a fresh exec channel and
/// stream their text out; cancelling the current command is what backs the
/// kill switch (spec §4.6).
public protocol HostCommandSession: Sendable {
    /// Runs `command` on a new exec channel and streams stdout/stderr as
    /// decoded text. Completes normally when the channel closes. Throws
    /// `AgentError.cancelled` when the caller invoked `cancelCurrentCommand`.
    func run(command: String, timeout: TimeInterval) async throws -> AsyncThrowingStream<String, Error>
    /// Hard-interrupts the current exec channel (kill switch, spec §4.6).
    func cancelCurrentCommand() async
    /// True when the underlying SSH connection is alive.
    func isRemoteConnected() async -> Bool
}

/// Production `HostCommandSession` backed by `CoreSSH.SSHSession`.
///
/// `SSHSession` is an actor; every call hops onto it. `cancelCurrentCommand`
/// disconnects the transport, which aborts any in-flight exec channel (the
/// reconnect policy restores it before the next turn).
public struct SSHSessionCommandAdapter: HostCommandSession, Sendable {
    private let session: SSHSession

    public init(session: SSHSession) {
        self.session = session
    }

    public func isRemoteConnected() async -> Bool {
        await session.state == .connected
    }

    public func run(command: String, timeout _: TimeInterval) async throws -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let result = try await session.run(command)
                    continuation.yield(result.output)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: AgentError.badState(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func cancelCurrentCommand() async {
        // SSHSession exposes no per-exec cancel; disconnecting the transport
        // aborts any in-flight exec channel. A reconnect policy restores it.
        await session.disconnect()
    }
}
