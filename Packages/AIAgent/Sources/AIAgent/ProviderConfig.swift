import Foundation

/// The wire protocol a configured provider speaks (spec §4.5). Only these three
/// are supported; anything else is rejected at configuration time.
public enum AIProviderKind: String, Codable, Sendable, Equatable {
    case openAICompatible
    case anthropic
    case gemini
}

/// A user-configured AI provider. Secrets never live here: `apiKeyRef` is a
/// Keychain reference (`KeychainStore`), resolved at request time through the
/// `APIKeyProviding` service (spec §6.3.1).
public struct AIProviderConfig: Sendable, Equatable {
    public var name: String
    public var kind: AIProviderKind
    public var baseURL: String
    public var model: String
    public var temperature: Double
    public var apiKeyRef: String

    public init(
        name: String,
        kind: AIProviderKind,
        baseURL: String,
        model: String,
        temperature: Double = 0.2,
        apiKeyRef: String
    ) {
        self.name = name
        self.kind = kind
        self.baseURL = baseURL
        self.model = model
        self.temperature = temperature
        self.apiKeyRef = apiKeyRef
    }
}

/// Resolves stored API keys. Implemented by the Keychain facade in production
/// and by fakes in unit tests. Key material never crosses this boundary except
/// inside the transport (spec §3.3/§6.3.1).
public protocol APIKeyProviding: Sendable {
    func apiKey(forRef ref: String) async throws -> String
}
