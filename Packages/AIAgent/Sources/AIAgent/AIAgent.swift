/// AIAgent — AI provider adapters (OpenAI-compatible / Anthropic / Gemini), tool
/// registry, agent loop, and approval policies.
///
/// Pure logic, no UI imports (spec §6.1.2). Security boundary: the model may only
/// propose; execution always requires human approval via the approval card
/// (spec §4.6). Provider adapters and chat land in P4; the agent loop and the
/// dangerous-command classifier in P5 (ADR-0002 in docs/ARCHITECTURE.md).
public enum AIAgentInfo {
    public static let moduleName = "AIAgent"
}
