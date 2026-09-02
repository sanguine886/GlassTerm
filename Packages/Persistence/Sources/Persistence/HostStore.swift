import Foundation
import SwiftData

/// CRUD facade over the SwiftData host database. Contexts are created per
/// operation and never escape; secrets are resolved through `SecretStoring`
/// by the caller, not here.
public final class HostStore: @unchecked Sendable {
    public let container: ModelContainer

    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: HostRecord.self, SnippetRecord.self, configurations: configuration)
    }

    public init(container: ModelContainer) {
        self.container = container
    }

    public func add(_ record: HostRecord) throws {
        let context = ModelContext(container)
        context.insert(record)
        try context.save()
    }

    /// Persists field changes made to `record` (e.g. from a view's main
    /// context) into this store's own context — SwiftData contexts do not see
    /// each other's unsaved mutations.
    public func update(_ record: HostRecord) throws {
        let context = ModelContext(container)
        let id = record.id
        let descriptor = FetchDescriptor<HostRecord>(predicate: #Predicate { $0.id == id })
        guard let managed = try context.fetch(descriptor).first else { return }
        managed.name = record.name
        managed.hostname = record.hostname
        managed.port = record.port
        managed.username = record.username
        managed.authKindRaw = record.authKindRaw
        managed.secretRef = record.secretRef
        managed.passphraseRef = record.passphraseRef
        managed.group = record.group
        managed.createdAt = record.createdAt
        managed.lastConnectedAt = record.lastConnectedAt
        try context.save()
    }

    public func delete(id: UUID) throws {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<HostRecord>(predicate: #Predicate { $0.id == id })
        for match in try context.fetch(descriptor) {
            context.delete(match)
        }
        try context.save()
    }

    public func all() throws -> [HostRecord] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<HostRecord>(sortBy: [SortDescriptor(\.createdAt)])
        return try context.fetch(descriptor)
    }

    public func record(id: UUID) throws -> HostRecord? {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<HostRecord>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    public func markConnected(id: UUID, at date: Date = Date()) throws {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<HostRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try context.fetch(descriptor).first else { return }
        record.lastConnectedAt = date
        try context.save()
    }
}
