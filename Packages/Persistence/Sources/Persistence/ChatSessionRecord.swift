import Foundation
import SwiftData

/// A persisted chat conversation (spec §4.5). Messages are stored as a JSON
/// blob keyed by role/content so the AI layer can round-trip them without
/// Persistence importing the AI types.
@Model
public final class ChatSessionRecord {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var providerID: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    /// JSON array of {role, content} pairs, kept as a blob for flexibility.
    public var messagesJSON: Data

    public init(
        id: UUID = UUID(),
        title: String,
        providerID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messagesJSON: Data = Data()
    ) {
        self.id = id
        self.title = title
        self.providerID = providerID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messagesJSON = messagesJSON
    }
}

/// CRUD facade over the SwiftData chat-session database. Tenets follow
/// `HostStore`/`SnippetStore`: contexts are per-operation and never escape.
public final class ChatSessionStore: @unchecked Sendable {
    public let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: ChatSessionRecord.self, configurations: configuration)
    }

    public func add(_ record: ChatSessionRecord) throws {
        let context = ModelContext(container)
        context.insert(record)
        try context.save()
    }

    public func update(_ record: ChatSessionRecord) throws {
        let context = ModelContext(container)
        let id = record.id
        let descriptor = FetchDescriptor<ChatSessionRecord>(predicate: #Predicate { $0.id == id })
        guard let managed = try context.fetch(descriptor).first else { return }
        managed.title = record.title
        managed.providerID = record.providerID
        managed.updatedAt = record.updatedAt
        managed.messagesJSON = record.messagesJSON
        try context.save()
    }

    public func delete(id: UUID) throws {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<ChatSessionRecord>(predicate: #Predicate { $0.id == id })
        for match in try context.fetch(descriptor) {
            context.delete(match)
        }
        try context.save()
    }

    public func all() throws -> [ChatSessionRecord] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<ChatSessionRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return try context.fetch(descriptor)
    }

    public func record(id: UUID) throws -> ChatSessionRecord? {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<ChatSessionRecord>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }
}
