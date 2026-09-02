import Foundation
import SwiftData

/// CRUD facade over the SwiftData snippet database. Same pattern as
/// `HostStore`; contexts are created per operation and never escape.
public final class SnippetStore: @unchecked Sendable {
    public let container: ModelContainer

    /// Business model container covering all SwiftData models in the app.
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(
            for: HostRecord.self, SnippetRecord.self,
            configurations: configuration
        )
    }

    public init(container: ModelContainer) {
        self.container = container
    }

    public func add(_ record: SnippetRecord) throws {
        let context = ModelContext(container)
        context.insert(record)
        try context.save()
    }

    public func update(_ record: SnippetRecord) throws {
        let context = ModelContext(container)
        let id = record.id
        let descriptor = FetchDescriptor<SnippetRecord>(predicate: #Predicate { $0.id == id })
        guard let managed = try context.fetch(descriptor).first else { return }
        managed.name = record.name
        managed.command = record.command
        managed.targetHostID = record.targetHostID
        try context.save()
    }

    public func delete(id: UUID) throws {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<SnippetRecord>(predicate: #Predicate { $0.id == id })
        for match in try context.fetch(descriptor) {
            context.delete(match)
        }
        try context.save()
    }

    public func all() throws -> [SnippetRecord] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<SnippetRecord>(sortBy: [SortDescriptor(\.createdAt)])
        return try context.fetch(descriptor)
    }
}
