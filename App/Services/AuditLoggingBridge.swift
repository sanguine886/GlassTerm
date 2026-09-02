import AIAgent
import Foundation
import Persistence

/// Sendable `AuditLogging` bridge that persists `AuditEntry`s into SwiftData's
/// `AuditStore` off the main actor. Designed to be handed to `AgentLoop` (which
/// requires `AuditLogging: Sendable`) while the UI keeps using `AuditManager`.
actor AuditLoggingBridge: AuditLogging {
    private let store: AuditStore

    init(store: AuditStore) {
        self.store = store
    }

    func record(_ entry: AuditEntry) async {
        let record = AuditRecord(
            timestamp: entry.timestamp,
            toolName: entry.toolName,
            commandText: entry.commandText,
            resultSummary: entry.resultSummary,
            approver: entry.approver,
            strategyRaw: entry.strategy.rawValue,
            outcomeRaw: entry.outcome.rawValue
        )
        try? store.add(record)
    }

    func entries() async -> [AuditEntry] {
        []
    }

    func clear() async {}
}

/// App-visible factory behind `AuditManager.loggingSink()`.
public enum AuditLoggingFactory {
    public static func make(store: AuditStore) -> any AuditLogging {
        AuditLoggingBridge(store: store)
    }
}
