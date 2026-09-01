import Foundation

/// Explicit error model for the agent loop and approval surfaces (spec §4.6,
/// §6.2.3). UI layers map these to localized user-facing copy. Designed for P5:
/// the agent loop throws these when the model's proposal cannot proceed.
public enum AgentError: Error, Equatable, Sendable {
    /// User (or the carrier) cancelled the current operation.
    case cancelled
    /// The agent was asked to act while host/session state is unusable.
    case badState(String)
    /// A tool call failed while executing on the host.
    case toolFailed(String)
    /// The host is unreachable; the transport could not be opened.
    case hostUnavailable
    /// The model proposal was blocked for approval reasons.
    case approvalDenied(String)
    /// The classifier deemed the command dangerous and it requires manual input.
    case dangerousCommand(String)
    /// The model requested a tool that is not registered.
    case unknownToolCall(String)
    /// The model returned malformed tool arguments.
    case malformedToolArguments(String)
}

extension AgentError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .cancelled:
            "Operation cancelled."
        case let .badState(detail):
            "Agent is in an invalid state: \(detail)"
        case let .toolFailed(detail):
            "Tool execution failed: \(detail)"
        case .hostUnavailable:
            "Host is unreachable."
        case let .approvalDenied(detail):
            "Approval denied: \(detail)"
        case let .dangerousCommand(detail):
            "Dangerous command blocked: \(detail)"
        case let .unknownToolCall(name):
            "Unknown tool call: \(name)"
        case let .malformedToolArguments(detail):
            "Malformed tool arguments: \(detail)"
        }
    }
}