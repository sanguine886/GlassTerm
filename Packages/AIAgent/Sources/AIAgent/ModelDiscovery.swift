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
    /// Lists `data[].id` from `GET /v1/models`. The base URL may already carry
    /// `/v1`; the same tolerance as `chatCompletionsURL`.
    public func discoverModels() async throws -> DiscoveredModels {
        let trimmed = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = trimmed.hasSuffix("/v1") ? "/models" : "/v1/models"
        guard let url = URL(string: trimmed + suffix) else {
            return DiscoveredModels(models: [], unsupported: true)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (status, data) = try await http.data(for: request)
        guard (200 ..< 300).contains(status),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = json["data"] as? [[String: Any]]
        else {
            return DiscoveredModels(models: [], unsupported: true)
        }
        let names = list.compactMap { $0["id"] as? String }.sorted()
        return DiscoveredModels(models: names)
    }
}
