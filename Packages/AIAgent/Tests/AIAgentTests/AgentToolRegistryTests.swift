@testable import AIAgent
import XCTest

private final class EchoExecutor: AgentToolExecutor, @unchecked Sendable {
    func execute(
        _ invocation: AgentToolInvocation,
        cancelToken: AgentCancellationToken?
    ) async throws -> ToolResult {
        _ = cancelToken
        return ToolResult(
            toolCallID: invocation.toolCallID,
            text: "echo \(invocation.name)",
            status: .success,
            truncated: false
        )
    }
}

final class AgentToolRegistryTests: XCTestCase {
    func testDefaultToolSetHasAtLeastSevenTools() {
        XCTAssertGreaterThanOrEqual(AgentToolRegistry.defaultToolDefinitions.count, 7)
        let names = Set(AgentToolRegistry.defaultToolDefinitions.map { $0.name })
        XCTAssertTrue(names.contains("run_command"))
        XCTAssertTrue(names.contains("read_file"))
        XCTAssertTrue(names.contains("write_file"))
        XCTAssertTrue(names.contains("list_dir"))
        XCTAssertTrue(names.contains("get_system_info"))
        XCTAssertTrue(names.contains("create_snippet"))
        XCTAssertTrue(names.contains("run_snippet"))
    }

    func testRegisterAndQueryExecutor() {
        var registry = AgentToolRegistry(definitions: AgentToolRegistry.defaultToolDefinitions)
        let echo = EchoExecutor()
        let tool = AgentToolRegistry.defaultToolDefinitions[0]
        registry.register(tool, executor: echo)
        let queried = registry.executor(for: tool.name)
        XCTAssertNotNil(queried)
        XCTAssertTrue(queried is EchoExecutor)
    }

    func testExecutorMissingReturnsNil() {
        let registry = AgentToolRegistry(definitions: [])
        XCTAssertNil(registry.executor(for: "nope"))
    }

    func testToolResultClampOutput() {
        let clamped = ToolResult.clampOutput("hello world", limitBytes: 5)
        XCTAssertEqual(clamped.text, "hello")
        XCTAssertTrue(clamped.truncated)
    }

    func testToolResultClampNoTruncation() {
        let clamped = ToolResult.clampOutput("hi", limitBytes: 16)
        XCTAssertEqual(clamped.text, "hi")
        XCTAssertFalse(clamped.truncated)
    }

    func testToolResultStatusEquatable() {
        XCTAssertEqual(ToolResultStatus.success, .success)
        XCTAssertEqual(ToolResultStatus.failure("boom"), .failure("boom"))
        XCTAssertEqual(ToolResultStatus.cancelled, .cancelled)
        XCTAssertNotEqual(ToolResultStatus.failure("a"), .failure("b"))
    }

    func testAllDefaultDefinitionsCarrySafeToRunSchema() {
        for tool in AgentToolRegistry.defaultToolDefinitions {
            let properties = extractObject(tool.parameters)?["properties"] ?? .object([:])
            let safe = extractObject(properties)?["safe_to_run"]
            XCTAssertNotNil(safe, "\(tool.name) should declare safe_to_run")
        }
    }

    private func extractObject(_ value: JSONValue?) -> [String: JSONValue]? {
        if case let .object(dict)? = value { return dict }
        return nil
    }

    func testInvocationArgumentsRoundTrip() {
        let invocation = AgentToolInvocation(
            toolCallID: "call_1",
            name: "run_command",
            arguments: ["command": .string("ls /home")]
        )
        XCTAssertEqual(invocation.toolCallID, "call_1")
        XCTAssertEqual(invocation.name, "run_command")
        XCTAssertEqual(invocation.arguments["command"], .string("ls /home"))
    }
}
