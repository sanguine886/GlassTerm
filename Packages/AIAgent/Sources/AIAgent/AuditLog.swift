import Foundation

/// AuditEntry — a single immutable record of a tool execution decision.
public struct AuditEntry: Codable, Sendable, Equatable {
    public enum Outcome: String, Codable, Sendable, Equatable {
        case autoApproved
        case userApproved
        case editedApproved
        case rejected
        case denied
        case cancelled
        case failed
    }

    public let timestamp: Date
    public let toolName: String
    public let commandText: String
    public let resultSummary: String
    public let approver: String
    public let strategy: ApprovalStrategy
    public let outcome: Outcome

    public init(
        timestamp: Date,
        toolName: String,
        commandText: String,
        resultSummary: String,
        approver: String,
        strategy: ApprovalStrategy,
        outcome: Outcome
    ) {
        self.timestamp = timestamp
        self.toolName = toolName
        self.commandText = commandText
        self.resultSummary = resultSummary
        self.approver = approver
        self.strategy = strategy
        self.outcome = outcome
    }
}

/// AuditLogging — the persistence boundary for audit entries.
///
/// The default `InMemoryAuditLog` keeps entries in memory for the lifetime of
/// the process. A disk-backed implementation can replace it without changing
/// callers.
public protocol AuditLogging: Sendable {
    func record(_ entry: AuditEntry) async
    func entries() async -> [AuditEntry]
    func clear() async
}

/// InMemoryAuditLog — actor-backed in-memory audit trail.
public actor InMemoryAuditLog: AuditLogging {
    public private(set) var entries: [AuditEntry] = []

    public init() {}

    public func record(_ entry: AuditEntry) async {
        entries.append(entry)
    }

    public func entries() async -> [AuditEntry] {
        entries
    }

    public func clear() async {
        entries.removeAll()
    }
}
