import AIAgent
import Foundation
import Observation
import OSLog
import Persistence

/// App-side audit trail (spec §4.6 / §6.3.3): bridges AIAgent's in-memory
/// `AuditEntry` into the persisted `AuditStore`, and offers export/clear.
@MainActor
@Observable
final class AuditManager {
    private static let logger = Logger(subsystem: "com.glazeterm.GlassTerm", category: "audit")

    private let auditStore: AuditStore
    private(set) var entries: [AuditRecord] = []

    init(auditStore: AuditStore) {
        self.auditStore = auditStore
    }

    /// A Sendable `AuditLogging` sink for the agent loop that persists into the
    /// same SwiftData store the UI reads back from.
    func loggingSink() -> any AuditLogging {
        AuditLoggingFactory.make(store: auditStore)
    }

    func refresh() {
        entries = (try? auditStore.all()) ?? []
    }

    /// Persists every entry recorded by the agent loop (through `AuditLogging`)
    /// into SwiftData.
    func record(_ entry: AuditEntry) {
        let record = AuditRecord(
            timestamp: entry.timestamp,
            toolName: entry.toolName,
            commandText: entry.commandText,
            resultSummary: entry.resultSummary,
            approver: entry.approver,
            strategyRaw: entry.strategy.rawValue,
            outcomeRaw: entry.outcome.rawValue
        )
        do {
            try auditStore.add(record)
        } catch {
            Self.logger.error("audit persist failed: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    func clear() {
        try? auditStore.clear()
        refresh()
    }

    /// Encodes the trail as plaintext lines for sharing (spec §6.3.3 export).
    func exportText() -> String {
        entries.map { entry in
            let time = Self.dateFormatter.string(from: entry.timestamp)
            return "\(time)\t[\(entry.outcomeRaw)]\t\(entry.approver)\t\(entry.strategyRaw)"
                + "\t\(entry.toolName): \(entry.commandText) → \(entry.resultSummary)"
        }.joined(separator: "\n")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
