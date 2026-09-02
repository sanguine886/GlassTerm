import Foundation
import SwiftData

/// A single persisted audit record (spec §4.6 / §6.3.3). Fields mirror
/// `AIAgent.AuditEntry` without importing AIAgent, keeping Persistence the
/// zero-dependency persistence floor. Encryption is the caller's job (spec
/// §6.3.3: AES-GCM keyed from the biometric gate) — the stored payload may be
/// the encrypted blob or, behind that, the plaintext fields.
@Model
public final class AuditRecord {
    @Attribute(.unique) public var id: UUID
    public var timestamp: Date
    public var toolName: String
    public var commandText: String
    public var resultSummary: String
    public var approver: String
    public var strategyRaw: String
    public var outcomeRaw: String

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        toolName: String,
        commandText: String,
        resultSummary: String,
        approver: String,
        strategyRaw: String,
        outcomeRaw: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.toolName = toolName
        self.commandText = commandText
        self.resultSummary = resultSummary
        self.approver = approver
        self.strategyRaw = strategyRaw
        self.outcomeRaw = outcomeRaw
    }
}

/// CRUD facade over the SwiftData audit trail. Same per-operation context
/// pattern as the other stores.
public final class AuditStore: @unchecked Sendable {
    public let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: AuditRecord.self, configurations: configuration)
    }

    public func add(_ record: AuditRecord) throws {
        let context = ModelContext(container)
        context.insert(record)
        try context.save()
    }

    public func all() throws -> [AuditRecord] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<AuditRecord>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        return try context.fetch(descriptor)
    }

    public func clear() throws {
        let context = ModelContext(container)
        try context.delete(model: AuditRecord.self)
        try context.save()
    }
}
