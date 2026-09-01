import Foundation

/// Who produced a chat message (spec §2.1). Tool roles tell the consumer how a
/// tool call ended so the agent loop can build the follow-up `tool` message.
public enum ChatRole: String, Codable, Sendable, Equatable {
    case system
    case user
    case assistant
    case tool
}

/// One message in a conversation. Tool calls issued by the assistant are carried
/// as `AssistantToolCall`; their results come back as a `chatRole: .tool` message
/// with the matching `toolCallID`.
public struct ChatMessage: Sendable, Equatable {
    public var role: ChatRole
    public var content: String
    /// The assistant's tool calls, in order. Populated when `role == .assistant`.
    public var toolCalls: [AssistantToolCall]
    /// Non-`nil` only for `role == .tool`; bonds this result to its tool call.
    public var toolCallID: String?

    public init(role: ChatRole, content: String, toolCalls: [AssistantToolCall] = [], toolCallID: String? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
    }
}

/// A tool call the model asked for (spec §2.1). `argumentsJSON` is kept as a JSON
/// document (single quotes, compact) so adapters can round-trip it verbatim.
public struct AssistantToolCall: Sendable, Equatable, Identifiable {
    public typealias ID = String

    public var id: String
    public var name: String
    public var argumentsJSON: String?

    public init(id: String, name: String, argumentsJSON: String?) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}
