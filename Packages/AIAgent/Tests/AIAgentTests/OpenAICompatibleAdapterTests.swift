@testable import AIAgent
import Foundation
import XCTest

final class OpenAICompatibleAdapterTests: XCTestCase {
    func testRequestURLAndAuthHeaders() throws {
        let url = try OpenAICompatibleAdapter.chatCompletionsURL(from: "https://api.example.com")
        XCTAssertEqual(url.absoluteString, "https://api.example.com/v1/chat/completions")

        let baseWithV1 = try OpenAICompatibleAdapter.chatCompletionsURL(from: "https://api.example.com/v1")
        XCTAssertEqual(baseWithV1.absoluteString, "https://api.example.com/v1/chat/completions")
    }

    func testRequestHeadersAndBody() async throws {
        let fake = FakeHTTPStreamingTransport([.init(
            statusCode: 200,
            chunks: chunkStream(["data: {\"choices\":[{\"delta\":{\"content\":\"hi\"}}]}\n\n", "data: [DONE]\n\n"])
        )])
        let adapter = OpenAICompatibleAdapter(config: testConfig, apiKey: testAPIKey, http: fake)

        let stream = try await adapter.streamCompletion(
            ChatCompletionRequest(model: "gpt-4o-mini", messages: [userMessage], temperature: 0.2)
        )
        var events: [ChatStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        let received = await fake.receivedRequests
        XCTAssertEqual(received.count, 1)
        let request = received[0]
        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(testAPIKey)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "Idempotency-Key"), "an idempotency key must be attached so retries are de-duplicated")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key")?.count, 36)

        XCTAssertEqual(events.filter { if case .content = $0 { return true } else { return false } }.count, 1)
        XCTAssertEqual(events.last, .done)
    }

    func testRequestBodySerialization() throws {
        let request = ChatCompletionRequest(
            model: "gpt-4o",
            messages: [
                ChatMessage(role: .system, content: "You are helpful."),
                ChatMessage(role: .user, content: "Run ls"),
            ],
            tools: [
                ToolDefinition(name: "run_command", description: "Run a shell command.", parameters: .object([:]), isReadonly: false),
            ]
        )
        let body = try OpenAICompatibleAdapter.encodeRequestBody(request)
        guard let dict = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return XCTFail("body not JSON")
        }
        XCTAssertEqual(dict["model"] as? String, "gpt-4o")
        XCTAssertEqual(dict["stream"] as? Bool, true)
        XCTAssertEqual(dict["temperature"] as? Double, 0.2)
        XCTAssertEqual((dict["tools"] as? [[String: Any]])?.first?["type"] as? String, "function")

        let messages = dict["messages"] as? [[String: Any]] ?? []
        XCTAssertEqual(messages.first?["role"] as? String, "system")
        XCTAssertEqual(messages.last?["role"] as? String, "user")
        XCTAssertNil(dict["system"])
    }

    func testToolCallFragmentsAggregateByIndex() async throws {
        let rawCalls = [
            // First chunk: ids + names + first argument fragments.
            #"{"choices":[{"delta":{"tool_calls":["# +
                #"{"index":0,"id":"call_1","type":"function","function":{"name":"run_command","arguments":"{\"com"}},"# +
                #"{"index":1,"id":"call_2","type":"function","function":{"name":"read_file","arguments":"{\"pat"}}]}}]}"#,
            // Continuation for both.
            #"{"choices":[{"delta":{"tool_calls":["# +
                #"{"index":0,"function":{"arguments":"mand\":\"ls -la\"}},"# +
                #"{"index":1,"function":{"arguments":"h\":\"/etc/passwd\"}"}}]}}]"#,
            // Finish reason chunk.
            #"{"choices":[{"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}"#,
        ]
        let frames = [
            sseRaw(rawCalls[0]),
            sseRaw(rawCalls[1]),
            sseRaw(rawCalls[2]) + sseRaw("[DONE]"),
        ]
        let fake = FakeHTTPStreamingTransport([.init(statusCode: 200, chunks: chunkStream(frames))])
        let adapter = OpenAICompatibleAdapter(config: testConfig, apiKey: testAPIKey, http: fake)

        let stream = try await adapter.streamCompletion(
            ChatCompletionRequest(model: "gpt-4o", messages: [userMessage])
        )
        var events: [ChatStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        var toolDeltas: [String] = []
        var completed: [ChatToolCallDelta] = []
        var sawUsage = false
        for event in events {
            switch event {
            case let .toolCall(delta):
                toolDeltas.append(delta.id)
            case let .toolCallComplete(delta):
                completed.append(delta)
            case .usage:
                sawUsage = true
            default:
                break
            }
        }

        // Fragments were emitted under both call ids.
        XCTAssertEqual(Set(toolDeltas), ["call_1", "call_2"])

        XCTAssertEqual(completed.count, 2)
        XCTAssertEqual(completed[0].id, "call_1", "first complete must be index 0")
        XCTAssertEqual(completed[0].name, "run_command")
        XCTAssertEqual(completed[0].argumentsJSON, #"{"command":"ls -la"}"#)
        XCTAssertEqual(completed[1].id, "call_2")
        XCTAssertEqual(completed[1].name, "read_file")
        XCTAssertEqual(completed[1].argumentsJSON, #"{"path":"/etc/passwd"}"#)

        XCTAssertTrue(sawUsage)
        XCTAssertEqual(events.last, .done)
    }

    func testHTTPErrorSurfacesStatus() async {
        let fake = FakeHTTPStreamingTransport([.init(statusCode: 401, chunks: [data("{\"error\":{\"message\":\"bad\"}}")])])
        let adapter = OpenAICompatibleAdapter(config: testConfig, apiKey: testAPIKey, http: fake)

        do {
            let stream = try await adapter.streamCompletion(
                ChatCompletionRequest(model: "gpt-4o", messages: [userMessage])
            )
            var iterator = stream.makeAsyncIterator()
            _ = try await iterator.next()
            XCTFail("expected AIProviderError.httpStatus")
        } catch let error as AIProviderError {
            guard case let .httpStatus(status, _) = error else {
                return XCTFail("wrong error \(error)")
            }
            XCTAssertEqual(status, 401)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testNetworkErrorRetriesOnceThenSucceeds() async throws {
        // First attempt throws a network error; the retry policy re-issues the
        // request and the second attempt succeeds.
        let fake = NeverFailingTransport(
            failures: 1,
            successChunks: chunkStream([
                "data: {\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n\n",
                "data: [DONE]\n\n",
            ])
        )
        let adapter = OpenAICompatibleAdapter(
            config: testConfig,
            apiKey: testAPIKey,
            http: fake,
            retryPolicy: StreamRetryPolicy(maxZeroDeltaRetries: 1, baseDelaySeconds: 0.01, maxDelaySeconds: 0.01)
        )
        let stream = try await adapter.streamCompletion(
            ChatCompletionRequest(model: "gpt-4o", messages: [userMessage])
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
        XCTAssertEqual(text, "ok")
        XCTAssertEqual(events.last, .done)
        XCTAssertEqual(await fake.calls, 2, "network failure must be retried once")
    }
}
