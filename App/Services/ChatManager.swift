import AIAgent
import Foundation
import Observation
import OSLog
import Persistence

/// A single display row in a chat transcript. Wraps `ChatMessage` plus the
/// pending assistant stream so the view can render text + tool calls.
struct ChatTurn: Identifiable, Sendable {
    enum Body: Sendable {
        case text(String)
        case toolCall(String) // rendered JSON of the assistant tool call
    }

    var id = UUID()
    var role: ChatRole
    var body: Body
    var timestamp = Date()
}

/// App-side chat orchestration (spec §4.5): multi-session CRUD over
/// `ChatSessionStore`, streaming turns through the active provider, and a
/// "what will be sent" preview built from the system prompt.
@MainActor
@Observable
final class ChatManager {
    private static let logger = Logger(subsystem: "com.glazeterm.GlassTerm", category: "chat")

    private let chatStore: ChatSessionStore
    private let secrets: SecretStoring
    private(set) var sessions: [ChatSessionRecord] = []
    private(set) var activeSessionID: UUID?
    private(set) var turns: [ChatTurn] = []
    /// Non-nil while a turn is streaming.
    private(set) var isStreaming = false
    private(set) var lastError: String?

    init(chatStore: ChatSessionStore, secrets: SecretStoring = KeychainStore()) {
        self.chatStore = chatStore
        self.secrets = secrets
    }

    // MARK: - Session CRUD

    func refresh() {
        sessions = (try? chatStore.all()) ?? []
        if activeSessionID == nil, let first = sessions.first {
            load(sessionID: first.id)
        }
    }

    func newSession(title: String = String(localized: "chat.newSession")) {
        let record = ChatSessionRecord(title: title)
        try? chatStore.add(record)
        refresh()
        load(sessionID: record.id)
    }

    func renameSession(id: UUID, to title: String) {
        guard let record = (try? chatStore.record(id: id)) ?? nil else { return }
        record.title = title
        try? chatStore.update(record)
        refresh()
    }

    func deleteSession(id: UUID) {
        try? chatStore.delete(id: id)
        if activeSessionID == id {
            activeSessionID = nil
            turns = []
        }
        refresh()
    }

    func load(sessionID: UUID) {
        activeSessionID = sessionID
        let record = (try? chatStore.record(id: sessionID)) ?? nil
        guard let data = record?.messagesJSON else {
            turns = []
            return
        }
        let stored = (try? JSONDecoder().decode([StoredMessage].self, from: data)) ?? []
        turns = stored.map { ChatTurn(role: $0.role, body: .text($0.text)) }
    }

    // MARK: - Sending

    /// Streams a user prompt through the active provider, appending turns, and
    /// persists the transcript. Returns true on completion.
    func send(
        _ prompt: String,
        provider: AIProviderConfig,
        hostContext: AgentContext? = nil
    ) async -> Bool {
        guard !isStreaming else { return false }
        guard let sessionID = activeSessionID else {
            newSession()
            return await send(prompt, provider: provider, hostContext: hostContext)
        }

        turns.append(ChatTurn(role: .user, body: .text(prompt)))
        isStreaming = true
        lastError = nil

        let apiKey = resolveAPIKey(for: provider)
        guard !apiKey.isEmpty else {
            lastError = String(localized: "ai.send.noKey")
            isStreaming = false
            return false
        }

        let adapter = AIProviderAdapterFactory.make(kind: provider.kind, config: provider, apiKey: apiKey)
        var messages: [ChatMessage] = [
            ChatMessage(role: .system, content: systemPrompt(hostContext: hostContext)),
        ]
        for turn in turns.dropLast() {
            messages.append(ChatMessage(role: turn.role, content: Self.text(of: turn.body)))
        }
        if !prompt.isEmpty {
            messages.append(ChatMessage(role: .user, content: prompt))
        }
        let request = ChatCompletionRequest(
            model: provider.model,
            messages: messages,
            tools: [],
            systemPrompt: systemPrompt(hostContext: hostContext),
            stream: true
        )

        var assistantText = ""
        do {
            let stream = try await adapter.streamCompletion(request)
            for try await event in stream {
                switch event {
                case let .content(text):
                    assistantText += text
                    if var last = turns.last {
                        last = ChatTurn(role: .assistant, body: .text(assistantText))
                        turns[turns.count - 1] = last
                    } else {
                        turns.append(ChatTurn(role: .assistant, body: .text(assistantText)))
                    }
                case let .toolCall(delta), let .toolCallComplete(delta):
                    turns.append(ChatTurn(role: .assistant, body: .toolCall(delta.argumentsJSON)))
                case .usage, .done:
                    break
                }
            }
            persist(sessionID: sessionID)
            isStreaming = false
            return true
        } catch {
            lastError = error.localizedDescription
            Self.logger.error("chat send failed: \(error.localizedDescription, privacy: .public)")
            isStreaming = false
            return false
        }
    }

    /// The system prompt for this turn, including host context when the agent
    /// is attached (spec §4.6). This is what the preview panel shows.
    func systemPrompt(hostContext: AgentContext? = nil) -> String {
        if let context = hostContext {
            return AgentContextBuilder.systemPrompt(
                tools: [],
                context: context,
                approvedWorkingDir: context.host.workingPaths.first
            )
        }
        return "You are GlassTerm's AI assistant. Answer concisely with no markdown headers unless asked."
    }

    // MARK: - Persistence

    private func persist(sessionID: UUID) {
        guard let record = (try? chatStore.record(id: sessionID)) ?? nil else { return }
        let stored = turns.map { StoredMessage(role: $0.role, text: Self.text(of: $0.body)) }
        record.messagesJSON = (try? JSONEncoder().encode(stored)) ?? Data()
        record.updatedAt = Date()
        try? chatStore.update(record)
        refresh()
    }

    private func resolveAPIKey(for provider: AIProviderConfig) -> String {
        (try? secrets.load(account: provider.apiKeyRef)) ?? ""
    }

    static func text(of body: ChatTurn.Body) -> String {
        switch body {
        case let .text(t): t
        case let .toolCall(j): j
        }
    }
}

/// Codable mirror of a message for JSON blob persistence.
private struct StoredMessage: Codable, Sendable {
    var role: ChatRole
    var text: String
}
