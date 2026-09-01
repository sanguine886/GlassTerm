import Foundation

/// The wire-agnostic request an adapter translates into a vendor payload
/// (spec §2.1).
public struct ChatCompletionRequest: Sendable, Equatable {
    public var model: String
    public var messages: [ChatMessage]
    public var temperature: Double
    /// Tools the model may propose. Empty = plain chat.
    public var tools: [ToolDefinition]
    /// Additional system-style preamble the vendor stringifies per its format.
    public var systemPrompt: String?
    /// Whether the vendor should stream (`true` for `AIChatStreaming.streamCompletion`).
    public var stream: Bool

    public init(
        model: String,
        messages: [ChatMessage],
        temperature: Double = 0.2,
        tools: [ToolDefinition] = [],
        systemPrompt: String? = nil,
        stream: Bool = true
    ) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.tools = tools
        self.systemPrompt = systemPrompt
        self.stream = stream
    }
}

/// Streaming chat capability shared by every adapter (OpenAI-compatible,
/// Anthropic, Gemini). A single `AsyncThrowingStream<ChatStreamEvent>` carries
/// normalized deltas; callers accumulate them into a `ChatResult`
/// (spec §2.1, §4.5). Adapters must never throw non-`AIProviderError` types.
public protocol AIChatStreaming: Sendable {
    /// Starts a streaming completion and returns the normalized event stream.
    /// The stream ends with `.done` on success, or throws `AIProviderError`.
    func streamCompletion(
        _ request: ChatCompletionRequest
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error>
}

/// A whole non-streaming completion for "connected?" smoke tests and low-level
/// callers (spec §4.5, model discovery uses a separate path in adapters).
public protocol AIChatCompleting: Sendable {
    func complete(_ request: ChatCompletionRequest) async throws -> ChatResult
}

/// Errors adapters surface. Kept `LocalizedError` so the red status pill and
/// alerts show readable copy (spec §6.2.3). No key material ever appears in a
/// message (spec §6.2.4).
public enum AIProviderError: Error, Equatable, Sendable {
    /// The base URL failed to parse.
    case invalidBaseURL(String)
    /// HTTP status other than 2xx. `body` is truncated and sanitized.
    case httpStatus(Int, String?)
    /// The vendor response was not valid JSON.
    case invalidJSON(String)
    /// The vendor sent a malformed SSE frame.
    case malformedSSE(String)
    /// The vendor stream ended without a terminal event.
    case streamEndedUnexpectedly
    /// The network request failed; `detail` is the underlying error description.
    case network(String)
    /// Missing, empty or refused API key.
    case missingAPIKey
}

extension AIProviderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidBaseURL(url):
            "Invalid provider base URL: \(url)"
        case let .httpStatus(code, body):
            "Provider returned HTTP \(code)\(body.flatMap { ": \($0)" } ?? "")"
        case let .invalidJSON(detail):
            "Provider returned invalid JSON: \(detail)"
        case let .malformedSSE(detail):
            "Provider sent malformed stream data: \(detail)"
        case .streamEndedUnexpectedly:
            "Provider stream ended unexpectedly."
        case let .network(detail):
            "Network error: \(detail)"
        case .missingAPIKey:
            "API key is missing or empty."
        }
    }
}