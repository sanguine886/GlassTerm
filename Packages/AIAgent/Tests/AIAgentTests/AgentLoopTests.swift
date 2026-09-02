@testable import AIAgent
import Foundation
import XCTest

/// Scripted chat provider for agent-loop tests (spec §6.5.2 fake injection).
actor FakeChatProvider: AIChatStreaming {
    /// Each entry is a scripted response; `toolCall` marks a tool proposal.
    struct Response: Sendable {
        var text: String
        var toolCall: AssistantToolCall?
    }

    private var script: [Response]
    private(set) var requests = 0

    init(_ script: [Response]) {
        self.script = script
    }

    func streamCompletion(
        _: ChatCompletionRequest
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let script = script
        let index = requests
        let response = script[min(index, script.count - 1)]
        requests += 1
        return AsyncThrowingStream { continuation in
            if !response.text.isEmpty {
                continuation.yield(.content(response.text))
            }
            if let call = response.toolCall {
                continuation.yield(.toolCallComplete(ChatToolCallDelta(id: call.id, name: call.name, argumentsJSON: call.argumentsJSON ?? "{}")))
            }
            continuation.yield(.done)
            continuation.finish()
        }
    }
}

/// Scripted host session (no network).
/// Scripted tool executor for the agent loop.
struct FakeToolExecutor: AgentToolExecutor, Sendable {
    var output: String

    func execute(
        _ invocation: AgentToolInvocation,
        cancelToken _: AgentCancellationToken?
    ) async throws -> ToolResult {
        ToolResult(toolCallID: invocation.toolCallID, text: output, status: .success, truncated: false)
    }
}

actor FakeHostSession: HostCommandSession {
    var runs: [String] = []
    var output: String
    var shouldThrow: Bool
    var cancelCalls = 0
    var connected = true

    init(output: String = "ok", shouldThrow: Bool = false) {
        self.output = output
        self.shouldThrow = shouldThrow
    }

    func run(command: String, timeout _: TimeInterval) async throws -> AsyncThrowingStream<String, Error> {
        try await Task.sleep(nanoseconds: 10_000_000)
        runs.append(command)
        if shouldThrow {
            throw AgentError.badState("host failed")
        }
        return AsyncThrowingStream { continuation in
            continuation.yield(output)
            continuation.finish()
        }
    }

    func cancelCurrentCommand() async {
        cancelCalls += 1
    }

    func isRemoteConnected() async -> Bool {
        connected
    }
}

final class AgentLoopTests: XCTestCase {
    /// Bundles the loop fixture so `makeLoop` returns a single struct instead
    /// of a 5-tuple (which swiftlint's `large_tuple` rejects).
    private struct Fixture {
        let loop: AgentLoop
        let provider: FakeChatProvider
        let host: FakeHostSession
        let audit: InMemoryAuditLog
    }

    @MainActor
    private func makeLoop(
        script: [FakeChatProvider.Response],
        host: FakeHostSession = FakeHostSession(),
        strategy: ApprovalStrategy = .alwaysAsk,
        toolName _: String = "run_command",
        toolArguments _: [String: JSONValue] = ["command": .string("ls -la /tmp"), "safe_to_run": .boolean(false)]
    ) -> Fixture {
        let provider = FakeChatProvider(script)
        var registry = AgentToolRegistry(definitions: AgentToolRegistry.defaultToolDefinitions)
        // Register a fake executor for run_command so the loop can execute it.
        registry.register(
            ToolDefinition(name: "run_command", description: "run a command", parameters: JSONSchemaBuilder.object(properties: [:]), isReadonly: false),
            executor: FakeToolExecutor(output: "fake output")
        )
        let decider = ApprovalDecider()
        let audit = InMemoryAuditLog()
        let config = AgentLoopConfiguration(model: "test-model", strategy: strategy)
        let loop = AgentLoop(
            provider: provider,
            host: host,
            registry: registry,
            decider: decider,
            auditLog: audit,
            configuration: config
        )
        return Fixture(loop: loop, provider: provider, host: host, audit: audit)
    }

    @MainActor
    func testAlwaysAskSurfacesApprovalCard() async throws {
        let call = AssistantToolCall(id: "1", name: "run_command", argumentsJSON: #"{"command":"ls -la /tmp","safe_to_run":false}"#)
        let fixture = makeLoop(script: [.init(text: "let me list", toolCall: call)])
        let loop = fixture.loop
        let context = AgentContext(userPrompt: "list tmp", host: HostSummary(alias: "host", workingPaths: ["/tmp"]))
        let turn = try await loop.requestTurn(prompt: "list tmp", context: context)
        XCTAssertEqual(turn.proposal?.toolName, "run_command")
        XCTAssertEqual(turn.proposal?.classification.verdict, .safe)
    }

    @MainActor
    func testApproveThenToolRunsAndFinishes() async throws {
        let call = AssistantToolCall(id: "2", name: "run_command", argumentsJSON: #"{"command":"df -h","safe_to_run":true}"#)
        let fixture = makeLoop(
            script: [
                .init(text: "checking disk", toolCall: call),
                .init(text: "done: 1MB used", toolCall: nil),
            ],
            host: FakeHostSession(output: "1MB used")
        )
        let loop = fixture.loop
        try await loop.requestTurn(prompt: "disk", context: AgentContext(userPrompt: "disk", host: HostSummary(alias: "h", workingPaths: [])))
        let proposal = AgentProposal(
            toolCallID: "2",
            toolName: "run_command",
            arguments: ["command": .string("df -h"), "safe_to_run": .boolean(true)],
            commandText: "df -h",
            modelDeclaredSafe: true,
            classification: CommandClassification(verdict: .safe, matchedRule: nil),
            explanation: nil
        )
        try await loop.continueAfterApproval(proposal: proposal, editedCommand: nil)
        let audit = fixture.audit
        let entries = await audit.entries()
        XCTAssertEqual(entries.count, 1, "approved tool run must be recorded in audit")
        XCTAssertEqual(entries[0].outcome, .userApproved)
    }

    @MainActor
    func testEditedCommandIsReclassifiedBeforeRun() async throws {
        let call = AssistantToolCall(id: "3", name: "run_command", argumentsJSON: #"{"command":"ls","safe_to_run":true}"#)
        let fixture = makeLoop(
            script: [
                .init(text: "list", toolCall: call),
                .init(text: "blocked", toolCall: nil),
            ]
        )
        let loop = fixture.loop
        let host = fixture.host
        let first = try await loop.requestTurn(prompt: "show", context: AgentContext(userPrompt: "show", host: HostSummary(alias: "h", workingPaths: [])))
        guard let proposal = first.proposal else {
            return XCTFail("expected proposal")
        }
        // User edits `ls` into a dangerous `rm -rf /` — the loop must re-review.
        let next = try await loop.continueAfterApproval(proposal: proposal, editedCommand: "rm -rf /")
        XCTAssertNotNil(next.proposal, "dangerous edit must go back for human review")
        let runs = await host.runs
        XCTAssertTrue(runs.isEmpty, "dangerous edit must NOT execute")
    }

    @MainActor
    func testRejectThenModelContinues() async throws {
        let call = AssistantToolCall(id: "4", name: "run_command", argumentsJSON: #"{"command":"rm x","safe_to_run":true}"#)
        let fixture = makeLoop(
            script: [
                .init(text: "propose", toolCall: call),
                .init(text: "understood", toolCall: nil),
            ]
        )
        let loop = fixture.loop
        let host = fixture.host
        let audit = fixture.audit
        let first = try await loop.requestTurn(prompt: "help", context: AgentContext(userPrompt: "help", host: HostSummary(alias: "h", workingPaths: [])))
        guard let proposal = first.proposal else {
            return XCTFail("expected proposal")
        }
        let next = try await loop.continueAfterRejection(proposal: proposal)
        XCTAssertEqual(next.text, "understood")
        XCTAssertNil(next.proposal)
        let entries = await audit.entries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].outcome, .rejected)
        let runs = await host.runs
        XCTAssertTrue(runs.isEmpty)
    }

    @MainActor
    func testKillSwitchStopsExecution() async throws {
        let call = AssistantToolCall(id: "5", name: "run_command", argumentsJSON: #"{"command":"sleep 100","safe_to_run":false}"#)
        let fixture = makeLoop(
            script: [.init(text: "long", toolCall: call)],
            host: FakeHostSession(output: "never", shouldThrow: false)
        )
        let loop = fixture.loop
        let first = try await loop.requestTurn(prompt: "long", context: AgentContext(userPrompt: "long", host: HostSummary(alias: "h", workingPaths: [])))
        guard let proposal = first.proposal else {
            return XCTFail("expected proposal")
        }
        await loop.cancel()
        let phase = loop.currentPhase()
        XCTAssertEqual(phase, .cancelledByUser)
    }

    @MainActor
    func testDangerousCommandIsBlockedByEveryStrategy() async throws {
        let call = AssistantToolCall(id: "6", name: "run_command", argumentsJSON: #"{"command":"rm -rf /","safe_to_run":true}"#)
        for strategy in [ApprovalStrategy.alwaysAsk, .autoReview, .readOnly] {
            let fixture = makeLoop(
                script: [.init(text: "bad", toolCall: call)],
                strategy: strategy
            )
            let loop = fixture.loop
            let host = fixture.host
            let turn = try await loop.requestTurn(prompt: "go", context: AgentContext(userPrompt: "go", host: HostSummary(alias: "h", workingPaths: [])))
            XCTAssertEqual(turn.proposal?.classification.verdict, .dangerous, "strategy \(strategy) must classify rm -rf / as dangerous")
            let runs = await host.runs
            XCTAssertTrue(runs.isEmpty, "no strategy may run a critical command")
        }
    }
}
