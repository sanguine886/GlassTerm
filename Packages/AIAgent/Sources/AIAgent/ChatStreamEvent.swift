import Foundation

/// One incremental chunk of a tool-call argument stream (spec §2.1). Adaptors
/// accumulate deltas per tool-call id and finish the call into an
/// `AssistantToolCall` once the stream closes.
public struct ChatToolCallDelta: Sendable, Equatable {
    public var id: String
    public var name: String?
    public var argumentsJSON: String

    public init(id: String, name: String? = nil, argumentsJSON: String = "") {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

/// Normalized stream event produced by every adapter, regardless of the vendor
/// wire format (spec §4.5). The consumer switches on this single type.
public enum ChatStreamEvent: Sendable, Equatable {
    /// Incremental assistant text; `content` may be empty for tool-only deltas.
    case content(String)
    /// A tool-call argument delta. Accumulate by `id` into a tool call.
    case toolCall(ChatToolCallDelta)
    /// The model finished a tool call with a complete JSON argument document.
    case toolCallComplete(ChatToolCallDelta)
    /// Final raw usage numbers, when the vendor reports them out-of-band.
    case usage(TokenUsage)
    /// Sentinel: healthy end of stream. No further events follow.
    case done
}

/// Token accounting reported by adapters (spec §2.1).
public struct TokenUsage: Sendable, Equatable {
    public var promptTokens: Int
    public var completionTokens: Int
    public var totalTokens: Int

    public init(promptTokens: Int, completionTokens: Int, totalTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }
}

/// A completed chat turn, as surfaced by `AIChatStreaming.streamCompletion`
/// (spec §2.1).
public struct ChatResult: Sendable, Equatable {
    public var text: String
    public var toolCalls: [AssistantToolCall]
    public var usage: TokenUsage?

    public init(text: String, toolCalls: [AssistantToolCall], usage: TokenUsage? = nil) {
        self.text = text
        self.toolCalls = toolCalls
        self.usage = usage
    }
}

/// A "did the stream recover?" advisory (spec §2.6). Kept deliberately minimal:
/// the caller decides whether to retry, reconnect or surface the message.
public struct StreamRecovery: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Network/intermittent error recovered transparently.
        case recovered
        /// Zero-increment stall recovered after the retry budget was exhausted.
        case stallRecovered
        /// Total failure; `reason` is the transport error.
        case failed(String)
    }

    public var kind: Kind
    /// The message reconstructed from the partial stream, only when it is safe
    /// to resume with it (assistantMessage reconstruction, spec §2.6).
    public var assistantMessage: String?
    public var retriesUsed: Int

    public init(kind: Kind, assistantMessage: String? = nil, retriesUsed: Int = 0) {
        self.kind = kind
        self.assistantMessage = assistantMessage
        self.retriesUsed = retriesUsed
    }
}