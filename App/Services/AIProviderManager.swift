import AIAgent
import Foundation
import Observation
import OSLog
import Persistence

/// App-side orchestration for AI providers (spec §4.5): CRUD over
/// `AIProviderStore`, Keychain-backed API keys (`apiKeyRef`), active-provider
/// switching, connection testing and model discovery. Business logic lives
/// here, not in views.
@MainActor
@Observable
final class AIProviderManager {
    private static let logger = Logger(subsystem: "com.glazeterm.GlassTerm", category: "ai-providers")

    private let providerStore: AIProviderStore
    private let secrets: SecretStoring

    private(set) var providers: [AIProviderRecord] = []
    private(set) var activeProviderID: UUID?
    /// Connection-test in-flight flag; a provider is testing while non-nil.
    private(set) var testingID: UUID?

    init(providerStore: AIProviderStore, secrets: SecretStoring) {
        self.providerStore = providerStore
        self.secrets = secrets
    }

    // MARK: - CRUD

    func refresh() {
        providers = (try? providerStore.all()) ?? []
        activeProviderID = providers.first(where: \.isDefault)?.id ?? providers.first?.id
    }

    /// Saves a draft. `apiKeyRef` is (re)stored in the Keychain when provided;
    /// an existing provider that leaves the field empty keeps its stored key.
    func save(
        id: UUID?,
        name: String,
        kind: AIProviderKind,
        baseURL: String,
        model: String,
        temperature: Double,
        apiKey: String
    ) throws {
        guard !name.isEmpty, !baseURL.isEmpty, !model.isEmpty else {
            throw AIProviderError.invalidBaseURL(baseURL)
        }

        let existing = id.flatMap { (try? providerStore.record(id: $0)) ?? nil }
        let apiKeyRef = existing?.apiKeyRef ?? UUID().uuidString
        if !apiKey.isEmpty {
            try secrets.save(apiKey, account: apiKeyRef)
        }
        if existing == nil {
            try providerStore.add(AIProviderRecord(
                name: name,
                kindRaw: kind.rawValue,
                baseURL: baseURL,
                model: model,
                temperature: temperature,
                apiKeyRef: apiKeyRef
            ))
        } else {
            existing!.name = name
            existing!.kindRaw = kind.rawValue
            existing!.baseURL = baseURL
            existing!.model = model
            existing!.temperature = temperature
            existing!.apiKeyRef = apiKeyRef
            try providerStore.update(existing!)
            try providerStore.setDefault(id: existing!.id)
        }
        refresh()
    }

    func delete(_ provider: AIProviderRecord) {
        // Best-effort key scrubbing from the Keychain on delete.
        if let ref = provider.apiKeyRef {
            try? secrets.delete(account: ref)
        }
        try? providerStore.delete(id: provider.id)
        refresh()
    }

    /// Marks `id` the default across all providers.
    func setActive(_ id: UUID) {
        try? providerStore.setDefault(id: id)
        refresh()
    }

    /// The active provider's config, resolving its API key from the Keychain.
    func activeConfig() throws -> (AIProviderConfig, AIProviderRecord)? {
        guard let id = activeProviderID,
              let record = (try? providerStore.record(id: id)) ?? nil,
              let apiKey = try? secrets.load(account: record.apiKeyRef),
              !apiKey.isEmpty
        else {
            return nil
        }
        let config = AIProviderConfig(
            name: record.name,
            kind: AIProviderKind(rawValue: record.kindRaw) ?? .openAICompatible,
            baseURL: record.baseURL,
            model: record.model,
            temperature: record.temperature,
            apiKeyRef: record.apiKeyRef
        )
        return (config, record)
    }

    /// Non-throwing convenience: the fully resolved active config, or nil when
    /// none is configured / key is missing. Views use this to gate chat UI.
    var activeProviderConfig: AIProviderConfig? {
        (try? activeConfig())?.0
    }

    // MARK: - Model discovery (spec §4.5)

    /// Fetches the provider's model catalogue when its protocol supports it.
    /// Returns nil when unsupported; a non-nil array otherwise.
    func discoverModels(id: UUID) async -> [String]? {
        guard let record = (try? providerStore.record(id: id)) ?? nil,
              let apiKey = try? secrets.load(account: record.apiKeyRef)
        else {
            return nil
        }
        let config = AIProviderConfig(
            name: record.name,
            kind: AIProviderKind(rawValue: record.kindRaw) ?? .openAICompatible,
            baseURL: record.baseURL,
            model: record.model,
            temperature: record.temperature,
            apiKeyRef: record.apiKeyRef
        )
        guard let discoverable = AIProviderAdapterFactory.discoverableAdapter(
            kind: config.kind,
            config: config,
            apiKey: apiKey
        ) else {
            return nil
        }
        let result = await (try? discoverable.discoverModels()) ?? DiscoveredModels(models: [])
        return result.unsupported ? nil : result.models
    }

    // MARK: - Connection test (spec §4.5: 1-token request)

    /// Sends a minimal request to verify credentials + connectivity. Returns
    /// nil on success; non-nil error otherwise.
    func testConnection(id: UUID) async -> String? {
        guard let record = (try? providerStore.record(id: id)) ?? nil,
              let apiKey = try? secrets.load(account: record.apiKeyRef)
        else {
            return String(localized: "ai.test.noKey")
        }
        let config = AIProviderConfig(
            name: record.name,
            kind: AIProviderKind(rawValue: record.kindRaw) ?? .openAICompatible,
            baseURL: record.baseURL,
            model: record.model,
            temperature: record.temperature,
            apiKeyRef: record.apiKeyRef
        )
        let adapter = AIProviderAdapterFactory.make(kind: config.kind, config: config, apiKey: apiKey)
        testingID = id
        defer { testingID = nil }

        do {
            let request = ChatCompletionRequest(
                model: config.model,
                messages: [ChatMessage(role: .user, content: "ping")],
                temperature: 0,
                stream: true
            )
            let stream = try await adapter.streamCompletion(request)
            var sawSomething = false
            for try await event in stream {
                switch event {
                case .content, .usage, .toolCall, .toolCallComplete:
                    sawSomething = true
                case .done:
                    break
                }
            }
            return sawSomething ? nil : String(localized: "ai.test.noResponse")
        } catch {
            Self.logger.error("provider test failed: \(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }
    }
}
