import AIAgent
import CoreSSH
import Foundation
import Observation
import OSLog
import Persistence

/// App-side agent runner (spec §4.6): wires a real `AgentLoop` onto a live
/// SSH host + the active AI provider, drives approvals/rejections, surfaces the
/// kill switch, and relays executed commands into a terminal ring buffer.
@MainActor
@Observable
final class AgentRunner {
    private static let logger = Logger(subsystem: "com.glazeterm.GlassTerm", category: "agent")

    /// Where executed commands echo back (spec §4.6 double-view). A plain
    /// buffer suffices; the terminal layer may render it.
    private(set) var echoLines: [String] = []

    /// The most recent proposal awaiting approval, or nil.
    private(set) var pendingProposal: AgentProposal?

    /// Lifecycle label for the UI.
    private(set) var phaseLabel: String = "agent.idle"

    /// True while the loop is running (streaming/executing).
    private(set) var isRunning = false

    /// The live AgentLoop once connected, or nil.
    private(set) var loop: AgentLoop?

    /// Optional Sendable audit sink bound from the view.
    private var auditSink: (any AuditLogging)?

    private var host: SSHSession?

    /// Bound from the view's environment audit manager.
    func setAudit(_ audit: (any AuditLogging)?) {
        auditSink = audit
    }

    /// Starts a run bound to `host` and `provider`. Returns an error message on
    /// failure, nil on success.
    func start(
        hostRecord: HostRecord,
        provider: AIProviderConfig,
        hostManager: HostManager,
        prompt: String,
        strategy: ApprovalStrategy = .alwaysAsk
    ) async -> String? {
        guard !isRunning else { return String(localized: "agent.alreadyRunning") }

        // Build the real host session.
        var session: SSHSession
        var config: SSHHostConfig
        do {
            let opened = try hostManager.openSession(for: hostRecord)
            session = opened.0
            config = opened.1
        } catch {
            return error.localizedDescription
        }
        host = session

        // Confirm connectivity (throws on failure).
        do {
            try await session.connect(config: config, knownHosts: hostManager.knownHosts)
        } catch {
            return error.localizedDescription
        }
        hostManager.markConnected(hostRecord)

        // Build the provider adapter from the stored key.
        guard let apiKey = try? KeychainStore().load(account: provider.apiKeyRef), !apiKey.isEmpty else {
            return String(localized: "agent.noKey")
        }
        let adapter = AIProviderAdapterFactory.make(kind: provider.kind, config: provider, apiKey: apiKey)

        // Wire the registry with real executors (SSH-backed) for the tools the model
        // may actually propose. Tools without an executor are not broadcast, so the
        // model never proposes something that would end in unknownToolCall.
        var registry = AgentToolRegistry(definitions: [])
        let sshExecutor = SSHCommandExecutor(session: session)
        for definition in AgentToolRegistry.defaultToolDefinitions
            where !Self.isAppManagedTool(definition.name)
        {
            registry.register(definition, executor: sshExecutor)
        }

        let decider = ApprovalDecider()
        // Bridge the loop's audit records into SwiftData when the view bound a
        // store-based sink; otherwise keep an in-memory trail.
        let auditLogger = auditSink ?? InMemoryAuditLog()
        let loopConfig = AgentLoopConfiguration(model: provider.model, strategy: strategy)
        let loop = AgentLoop(
            provider: adapter,
            host: SSHSessionCommandAdapter(session: session),
            registry: registry,
            decider: decider,
            auditLog: auditLogger,
            configuration: loopConfig
        )
        self.loop = loop
        isRunning = true
        phaseLabel = "agent.thinking"

        let context = AgentContext(
            userPrompt: prompt,
            host: HostSummary(alias: hostRecord.name, workingPaths: [])
        )
        do {
            let turn = try await loop.requestTurn(prompt: prompt, context: context)
            surface(turn)
            return nil
        } catch {
            isRunning = false
            phaseLabel = "agent.failed"
            return error.localizedDescription
        }
    }

    /// Runs the next model turn after the user decided on a proposal.
    func proceed(approve: Bool, editedCommand: String?) async -> String? {
        guard let loop, let proposal = pendingProposal else { return nil }
        // Consume the pending proposal BEFORE running the loop so a re-proposal
        // returned by an edit re-approval (dangerous edit) can be reassigned by
        // surface() instead of being cleared by a late defer.
        pendingProposal = nil
        do {
            let turn: AgentTurn = if approve {
                try await loop.continueAfterApproval(proposal: proposal, editedCommand: editedCommand)
            } else {
                try await loop.continueAfterRejection(proposal: proposal)
            }
            surface(turn)
            return nil
        } catch {
            isRunning = false
            phaseLabel = "agent.failed"
            return error.localizedDescription
        }
    }

    /// Kill switch: aborts in-flight work (spec §4.6). Disconnects the host so any
    /// running exec channel is aborted; the session's reconnect policy restores
    /// it before the next run.
    func kill() async {
        await loop?.cancel()
        await host?.disconnect()
        host = nil
        isRunning = false
        phaseLabel = "agent.idle"
    }

    /// Surfaces a turn (proposal vs final answer).
    private func surface(_ turn: AgentTurn) {
        if let proposal = turn.proposal {
            pendingProposal = proposal
            phaseLabel = proposal.classification.verdict == .safe ? "agent.awaitingApproval" : "agent.dangerous"
        } else if let text = turn.text {
            echoLines.append("— " + text)
            phaseLabel = "agent.finished"
            isRunning = false
        }
    }

    /// Tools that are App-internal and get no broadcast executor.
    private static func isAppManagedTool(_ name: String) -> Bool {
        switch name {
        case "create_snippet", "run_snippet":
            true
        default:
            false
        }
    }
}

/// A real executor that runs commands over the SSH session.
private struct SSHCommandExecutor: AgentToolExecutor, Sendable {
    let session: SSHSession

    func execute(_ invocation: AgentToolInvocation, cancelToken: AgentCancellationToken?) async throws -> ToolResult {
        let command = invocation.arguments["command"]?.stringValue ?? ""
        // Kill switch must actually abort the in-flight exec. SSHSession exposes
        // no per-exec cancel, so we disconnect the transport (which aborts the
        // exec channel); the reconnect policy restores it before the next turn.
        var handlerID: UUID?
        if let cancelToken {
            handlerID = await cancelToken.register { [session] in
                await session.disconnect()
            }
        }
        defer {
            if let handlerID, let cancelToken {
                Task { await cancelToken.unregister(handlerID) }
            }
        }
        do {
            let result = try await session.run(command)
            return ToolResult(toolCallID: invocation.toolCallID, text: result.output, status: .success, truncated: false)
        } catch {
            let message = error.localizedDescription
            return ToolResult(toolCallID: invocation.toolCallID, text: message, status: .failure(message), truncated: false)
        }
    }
}
