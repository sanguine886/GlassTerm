import Foundation

/// AgentCancellationToken — cooperative cancellation for in-flight agent
/// work.
///
/// Register an async handler with `register` and call `cancel` from the UI
/// thread to stop network streams, shell sessions, and tool executions.
/// Callers should `unregister` their handler when done (a `defer` in a task
/// is the recommended pattern).
public actor AgentCancellationToken {
    public private(set) var isCancelled = false
    private var handlers: [UUID: @Sendable () async -> Void] = [:]

    public init() {}

    @discardableResult
    public func register(_ handler: @escaping @Sendable () async -> Void) -> UUID {
        let id = UUID()
        handlers[id] = handler
        return id
    }

    public func unregister(_ id: UUID) {
        handlers.removeValue(forKey: id)
    }

    /// Fires every registered handler, then marks the token cancelled.
    public func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        let handlersToFire = Array(handlers.values)
        handlers.removeAll()
        for handler in handlersToFire {
            Task.detached { await handler() }
        }
    }

    /// Throws `AgentError.cancelled` when the token has been cancelled, so
    /// cooperative loops can unwind and surface the short-circuit cleanly.
    public func throwIfCancelled() throws {
        if isCancelled {
            throw AgentError.cancelled
        }
    }
}
