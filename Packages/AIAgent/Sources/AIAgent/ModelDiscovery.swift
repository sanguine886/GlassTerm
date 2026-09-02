import Foundation

// Model discovery for a provider (spec §4.5: "模型发现"). Not every vendor
// exposes a public catalogue: OpenAI-compatible endpoints list `/v1/models`;
// Anthropic and Gemini offer no stable anonymous catalogue, so their adapters
// return an empty list with a nil error.

/// Result of a model-discovery call.
public struct DiscoveredModels: Sendable, Equatable {
    public var models: [String]
    /// When the protocol has no catalogue (Anthropic/Gemini), models is empty.
    public var unsupported: Bool

    public init(models: [String], unsupported: Bool = false) {
        self.models = models
        self.unsupported = unsupported
    }
}

/// Adapter capability: list available models. Conforming adapters expose their
/// vendor catalogue; the provider manager calls this for discovery.
public protocol ModelDiscovering: Sendable {
    func discoverModels() async throws -> DiscoveredModels
}

public extension AIProviderAdapterFactory {
    /// Returns the discovery-capable adapter for a provider kind, or nil when
    /// the kind has no model catalogue. The transport defaults to URLSession so
    /// callers don't need to construct one for discovery.
    static func discoverableAdapter(
        kind: AIProviderKind,
        config: AIProviderConfig,
        apiKey: String,
        http: any HTTPStreamingTransport = URLSessionHTTPStreamingTransport()
    ) -> (any ModelDiscovering)? {
        switch kind {
        case .openAICompatible:
            OpenAICompatibleAdapter(config: config, apiKey: apiKey, http: http)
        case .anthropic:
            nil
        case .gemini:
            nil
        }
    }
}

extension OpenAICompatibleAdapter: ModelDiscovering {
    /// Lists `data[].id` from `GET /v1/models`. Concrete implementation lives in
    /// the type's own file so it can read the private request fields.
    public func discoverModels() async throws -> DiscoveredModels {
        try await openAIDiscover()
    }
}
