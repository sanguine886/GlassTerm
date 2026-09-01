import Foundation

/// A single tool-call the model proposed, produced by the agent loop from a
/// completed `AssistantToolCall`. Carries the classification verdict and the
/// model's own `safe_to_run` claim so the approval policy can decide.
public struct AgentProposal: Sendable, Equatable {
    public let toolCallID: String
    public let toolName: String
    /// Parsed arguments (JSON object); empty for argument-free tools.
    public let arguments: [String: JSONValue]
    /// The raw command the tool would run, when the tool carries one.
    public let commandText: String?
    /// The model declared `safe_to_run: true` in the arguments.
    public let modelDeclaredSafe: Bool
    /// Local classifier verdict, computed before the proposal is surfaced.
    public let classification: CommandClassification
    /// Human-facing explanation the model gave alongside the call.
    public let explanation: String?

    public init(
        toolCallID: String,
        toolName: String,
        arguments: [String: JSONValue],
        commandText: String?,
        modelDeclaredSafe: Bool,
        classification: CommandClassification,
        explanation: String?
    ) {
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.arguments = arguments
        self.commandText = commandText
        self.modelDeclaredSafe = modelDeclaredSafe
        self.classification = classification
        self.explanation = explanation
    }
}

/// A single agent turn: either pure text (no tool), or one proposal awaiting
/// approval, or a final answer.
public struct AgentTurn: Sendable, Equatable {
    public let text: String?
    public let proposal: AgentProposal?

    public init(text: String?, proposal: AgentProposal?) {
        self.text = text
        self.proposal = proposal
    }
}
