@testable import AIAgent
import Foundation
import XCTest

final class AnthropicAdapterTests: XCTestCase {
    func testSystemFieldIsExtractedToTopLevel() throws {
        let request = ChatCompletionRequest(
            model: "claude-sonnet-4-5",
            messages: [
                ChatMessage(role: .system, content: "Be terse."),
                ChatMessage(role: .user, content: "Explain exit codes."),
            ]
        )
        let body = try AnthropicAdapter.encodeRequestBody(request)
        guard let dict = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return XCTFail("body not JSON")
        }

        XCTAssertEqual(dict["system"] as? String, "Be terse.")
        XCTAssertEqual(dict["model"] as? String, "claude-sonnet-4-5")

        let messages = dict["messages"] as? [[String: Any]] ?? []
        // The literal system role is downgraded to user, not dropped.
        XCTAssertEqual(messages.compactMap { $0["role"] as? String }, ["user", "user"])
        XCTAssertNil(dict["systemPrompt"])
    }

    func testRequestURLAndHeaders() throws {
        let url = try AnthropicAdapter.messagesURL(from: "https://api.anthropic.com")
        XCTAssertEqual(url.absoluteString, "https://api.anthropic.com/v1/messages")

        let baseWithV1 = try AnthropicAdapter.messagesURL(from: "https://api.anthropic.com/v1")
        XCTAssertEqual(baseWithV1.absoluteString, "https://api.anthropic.com/v1/messages")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("x", forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "x")
    }

    func testToolUseBlockEncodesAsToolResultInConversation() throws {
        let request = ChatCompletionRequest(
            model: "claude-sonnet-4-5",
            messages: [
                ChatMessage(role: .assistant, content: "", toolCalls: [
                    AssistantToolCall(id: "t1", name: "run_command", argumentsJSON: #"{"command":"ls"}"#),
                ]),
                ChatMessage(role: .tool, content: "total 0", toolCallID: "t1"),
            ]
        )
        let body = try AnthropicAdapter.encodeRequestBody(request)
        guard let dict = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return XCTFail("body not JSON")
        }
        let messages = dict["messages"] as? [[String: Any]] ?? []
        XCTAssertEqual(messages.count, 2)

        let assistant = messages[0]
        XCTAssertEqual(assistant["role"] as? String, "assistant")
        let assistantContent = assistant["content"] as? [[String: Any]] ?? []
        XCTAssertEqual(assistantContent.count, 1, "empty assistant text must not emit a text block")
        XCTAssertEqual(assistantContent[0]["type"] as? String, "tool_use")
        XCTAssertEqual(assistantContent[0]["name"] as? String, "run_command")
        XCTAssertEqual((assistantContent[0]["input"] as? [String: Any])?["command"] as? String, "ls")

        let toolResult = messages[1]
        XCTAssertEqual(toolResult["role"] as? String, "user")
        let resultContent = toolResult["content"] as? [[String: Any]] ?? []
        XCTAssertEqual(resultContent[0]["type"] as? String, "tool_result")
        XCTAssertEqual(resultContent[0]["tool_use_id"] as? String, "t1")
    }

    func testStreamingContentBlockNormalization() async throws {
        let frames = [
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" world"}}"#,
            #"{"type":"message_delta","usage":{"input_tokens":5,"output_tokens":3}}"#,
            #"{"type":"message_stop"}"#,
        ]
        let fake = FakeHTTPStreamingTransport([.init(statusCode: 200, chunks: chunkStream(frames.map { sseRaw($0) }))])
        let adapter = AnthropicAdapter(
            config: AIProviderConfig(name: "A", kind: .anthropic, baseURL: "https://api.anthropic.com", model: "claude-sonnet-4-5", apiKeyRef: "k"),
            apiKey: testAPIKey,
            http: fake
        )

        let stream = try await adapter.streamCompletion(
            ChatCompletionRequest(model: "claude-sonnet-4-5", messages: [userMessage])
        )
        var events: [ChatStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        let text = events.compactMap { event -> String? in
            if case let .content(s) = event {
                return s
            }
            return nil
        }.joined()
        XCTAssertEqual(text, "Hello world")

        let usage = events.compactMap { event -> TokenUsage? in
            if case let .usage(u) = event {
                return u
            }
            return nil
        }.first
        XCTAssertEqual(usage?.promptTokens, 5)
        XCTAssertEqual(usage?.completionTokens, 3)

        XCTAssertNotNil(events.last)
    }

    func testToolUseContentBlockNormalization() async throws {
        let frames = [
            #"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"tool_1","name":"run_command"}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"command\":"}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"\"pwd\"}"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"message_stop"}"#,
        ]
        let fake = FakeHTTPStreamingTransport([.init(statusCode: 200, chunks: chunkStream(frames.map { sseRaw($0) }))])
        let adapter = AnthropicAdapter(
            config: AIProviderConfig(name: "A", kind: .anthropic, baseURL: "https://api.anthropic.com", model: "claude-sonnet-4-5", apiKeyRef: "k"),
            apiKey: testAPIKey,
            http: fake
        )

        let stream = try await adapter.streamCompletion(
            ChatCompletionRequest(model: "claude-sonnet-4-5", messages: [userMessage])
        )
        var events: [ChatStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        var completes: [ChatToolCallDelta] = []
        for event in events {
            if case let .toolCallComplete(delta) = event {
                completes.append(delta)
            }
        }
        XCTAssertEqual(completes.count, 1)
        XCTAssertEqual(completes[0].id, "tool_1")
        XCTAssertEqual(completes[0].name, "run_command")
        // Fragments joined: `{"command":` + `"pwd"}`.
        XCTAssertEqual(completes[0].argumentsJSON, #"{"command":"pwd"}"#)
    }

    func testNonStreamMessagesRequest() throws {
        let request = ChatCompletionRequest(
            model: "claude-sonnet-4-5",
            messages: [userMessage],
            stream: false
        )
        let body = try AnthropicAdapter.encodeRequestBody(request)
        guard let dict = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return XCTFail("body not JSON")
        }
        XCTAssertEqual(dict["stream"] as? Bool, false)
    }
}
