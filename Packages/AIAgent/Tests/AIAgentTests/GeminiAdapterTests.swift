@testable import AIAgent
import Foundation
import XCTest

let geminiConfig = AIProviderConfig(
    name: "G",
    kind: .gemini,
    baseURL: "https://generativelanguage.googleapis.com",
    model: "gemini-2.0-flash",
    apiKeyRef: "k"
)

final class GeminiAdapterTests: XCTestCase {
    func testStreamGenerateContentURL() throws {
        let url = try GeminiAdapter.streamGenerateContentURL(
            model: "gemini-2.0-flash",
            baseURL: "https://generativelanguage.googleapis.com"
        )
        XCTAssertEqual(
            url.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:streamGenerateContent"
        )
    }

    func testRequestBodyWithSystemInstruction() throws {
        let request = ChatCompletionRequest(
            model: "gemini-2.0-flash",
            messages: [
                ChatMessage(role: .system, content: "You are a sysadmin."),
                ChatMessage(role: .user, content: "Check disk"),
            ],
            tools: [
                ToolDefinition(name: "run_command", description: "Run a shell command.", parameters: .object([:]), isReadonly: false),
            ]
        )
        let body = try GeminiAdapter.encodeRequestBody(request)
        guard let dict = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return XCTFail("body not JSON")
        }

        let systemInstruction = dict["systemInstruction"] as? [String: Any]
        XCTAssertEqual((systemInstruction?["parts"] as? [[String: Any]])?.first?["text"] as? String, "You are a sysadmin.")

        let contents = dict["contents"] as? [[String: Any]] ?? []
        XCTAssertEqual(contents.count, 1)
        XCTAssertEqual(contents[0]["role"] as? String, "user")
        XCTAssertEqual(((contents[0]["parts"] as? [[String: Any]])?.first)?["text"] as? String, "Check disk")
    }

    func testFunctionCallFromAssistantIsEncoded() throws {
        let request = ChatCompletionRequest(
            model: "gemini-2.0-flash",
            messages: [
                ChatMessage(role: .assistant, content: "", toolCalls: [
                    AssistantToolCall(id: "g1", name: "list_dir", argumentsJSON: #"{"path":"/tmp"}"#),
                ]),
                ChatMessage(role: .tool, content: "", toolCallID: "g1"),
            ]
        )
        let body = try GeminiAdapter.encodeRequestBody(request)
        guard let dict = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return XCTFail("body not JSON")
        }
        let contents = dict["contents"] as? [[String: Any]] ?? []
        XCTAssertEqual(contents.count, 2)
        let modelPart = contents[0]
        XCTAssertEqual(modelPart["role"] as? String, "model")
        let functionCall = ((modelPart["parts"] as? [[String: Any]])?.first)?["functionCall"] as? [String: Any]
        XCTAssertEqual(functionCall?["name"] as? String, "list_dir")
    }

    func testStreamingTextChunksNormalization() async throws {
        let candidate0 = #"{"content":{"parts":[{"text":"Hello"}],"role":"model"}}"#
        let frames = [
            #"{"candidates":["# + candidate0 + #"],"usageMetadata":{"promptTokenCount":4,"candidatesTokenCount":2,"totalTokenCount":6}}"#,
            #"{"candidates":[{"content":{"parts":[{"text":" world"}],"role":"model"}}]}"#,
            #"{"candidates":[{"finishReason":"STOP"}]}"#,
        ]
        let fake = FakeHTTPStreamingTransport([.init(statusCode: 200, chunks: chunkStream(frames.map { $0 + "\n" }))])
        let adapter = GeminiAdapter(
            config: geminiConfig,
            apiKey: testAPIKey,
            http: fake
        )

        let stream = try await adapter.streamCompletion(
            ChatCompletionRequest(model: "gemini-2.0-flash", messages: [userMessage])
        )
        var events: [ChatStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        let text = events.compactMap { event -> String? in
            if case let .content(s) = event { return s }
            return nil
        }.joined()
        XCTAssertEqual(text, "Hello world")

        let usage = events.compactMap { event -> TokenUsage? in
            if case let .usage(u) = event { return u }
            return nil
        }.first
        XCTAssertEqual(usage?.promptTokens, 4)
        XCTAssertEqual(usage?.completionTokens, 2)

        // FinishReason should end the stream as completed, with `.done` last.
        XCTAssertEqual(events.last, .done)
    }

    func testFunctionCallNormalizationComplete() async throws {
        let frames = [
            #"{"candidates":[{"content":{"parts":[{"functionCall":{"name":"list_dir","args":{"path":"/tmp"}}}],"role":"model"},"finishReason":"STOP"}]}"#,
        ]
        let fake = FakeHTTPStreamingTransport([.init(statusCode: 200, chunks: chunkStream([frames[0] + "\n"]))])
        let adapter = GeminiAdapter(
            config: geminiConfig,
            apiKey: testAPIKey,
            http: fake
        )

        let stream = try await adapter.streamCompletion(
            ChatCompletionRequest(model: "gemini-2.0-flash", messages: [userMessage])
        )
        var events: [ChatStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        let completes = events.compactMap { event -> ChatToolCallDelta? in
            if case let .toolCallComplete(delta) = event { return delta }
            return nil
        }
        XCTAssertEqual(completes.count, 1)
        XCTAssertEqual(completes[0].name, "list_dir")
        XCTAssertEqual(completes[0].argumentsJSON, #"{"path":"/tmp"}"#)
    }

    func testEmptyObjectEndsStreamWithNoIncrement() async throws {
        // A `{}` line closes the stream without any candidates.
        let fake = FakeHTTPStreamingTransport([.init(statusCode: 200, chunks: [data("{}\n")])])
        let adapter = GeminiAdapter(
            config: geminiConfig,
            apiKey: testAPIKey,
            http: fake
        )
        let stream = try await adapter.streamCompletion(
            ChatCompletionRequest(model: "gemini-2.0-flash", messages: [userMessage])
        )
        var events: [ChatStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }
        XCTAssertEqual(events, [.done])
    }
}