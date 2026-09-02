import Foundation
import SwiftData

/// A user-configured AI provider (spec §4.5). The API key itself is never
/// stored here — only a Keychain account reference, resolved at request time
/// through `SecretStoring` by the caller.
@Model
public final class AIProviderRecord {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var kindRaw: String
    public var baseURL: String
    public var model: String
    public var temperature: Double
    /// Keychain account reference for the API key (spec §6.3.1).
    public var apiKeyRef: String
    public var isDefault: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        kindRaw: String,
        baseURL: String,
        model: String,
        temperature: Double = 0.2,
        apiKeyRef: String,
        isDefault: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.kindRaw = kindRaw
        self.baseURL = baseURL
        self.model = model
        self.temperature = temperature
        self.apiKeyRef = apiKeyRef
        self.isDefault = isDefault
        self.createdAt = createdAt
    }
}

/// CRUD facade over the SwiftData provider database. API key material is
/// resolved through `SecretStoring` by the caller; it never lives here.
public final class AIProviderStore: @unchecked Sendable {
    public let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: AIProviderRecord.self, configurations: configuration)
    }

    public func add(_ record: AIProviderRecord) throws {
        let context = ModelContext(container)
        context.insert(record)
        try context.save()
    }

    public func update(_ record: AIProviderRecord) throws {
        let context = ModelContext(container)
        let id = record.id
        let descriptor = FetchDescriptor<AIProviderRecord>(predicate: #Predicate { $0.id == id })
        guard let managed = try context.fetch(descriptor).first else { return }
        managed.name = record.name
        managed.kindRaw = record.kindRaw
        managed.baseURL = record.baseURL
        managed.model = record.model
        managed.temperature = record.temperature
        managed.apiKeyRef = record.apiKeyRef
        managed.isDefault = record.isDefault
        try context.save()
    }

    public func delete(id: UUID) throws {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<AIProviderRecord>(predicate: #Predicate { $0.id == id })
        for match in try context.fetch(descriptor) {
            context.delete(match)
        }
        try context.save()
    }

    public func all() throws -> [AIProviderRecord] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<AIProviderRecord>(sortBy: [SortDescriptor(\.createdAt)])
        return try context.fetch(descriptor)
    }

    public func record(id: UUID) throws -> AIProviderRecord? {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<AIProviderRecord>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    /// Ensures exactly one provider is the active default.
    public func setDefault(id: UUID) throws {
        let context = ModelContext(container)
        let all = try context.fetch(FetchDescriptor<AIProviderRecord>())
        for provider in all {
            provider.isDefault = provider.id == id
        }
        try context.save()
    }
}
