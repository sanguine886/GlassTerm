import Foundation
import os

/// Anthropic Messages API adapter (spec §2.4). Speaks `POST /v1/messages` with
/// `stream: true` and an `anthropic-version` header. `content_block_start/delta`
/// events are normalized into `.content` / `.toolCall` and finished with
/// `.toolCallComplete`. A `system` top-level field carries the system prompt
/// (Anthropic requires it there, not as a `system` role message).
public struct AnthropicAdapter: AIChatStreaming {
    private static let logger = Logger(subsystem: "com.glazeterm.AIAgent", category: "Anthropic")

    private let config: AIProviderConfig
    private let apiKey: String
    private let http: any HTTPStreamingTransport
    private let retryPolicy: StreamRetryPolicy

    public init(
        config: AIProviderConfig,
        apiKey: String,
        http: any HTTPStreamingTransport,
        retryPolicy: StreamRetryPolicy = .default
    ) {
        self.config = config
        self.apiKey = apiKey
        self.http = http
        self.retryPolicy = retryPolicy
    }

    // MARK: - AIChatStreaming

    public func streamCompletion(
        _ request: ChatCompletionRequest
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let url = try Self.messagesURL(from: config.baseURL)
        return AsyncThrowingStream<ChatStreamEvent, Error>(bufferingPolicy: .unbounded) { continuation in
            let task = Task { await self.run(request: request, url: url, continuation: continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Internals

    private func run(
        request: ChatCompletionRequest,
        url: URL,
        continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation
    ) async {
        var attempts = 0
        while true {
            if Task.isCancelled {
                continuation.finish()
                return
            }
            do {
                let outcome = try await streamOnce(request: request, url: url, continuation: continuation)
                switch outcome {
                case .completed:
                    continuation.yield(.done)
                    continuation.finish()
                    return
                case let .unfinished(hasProgress):
                    if !hasProgress, attempts < retryPolicy.maxZeroDeltaRetries {
                        Self.logger.info("Retrying stalled Anthropic stream (attempt \(attempts + 1))")
                        try? await Task.sleep(for: .seconds(retryPolicy.delaySeconds(zeroDeltas: attempts + 1)))
                        attempts += 1
                        continue
                    }
                    continuation.finish(throwing: AIProviderError.streamEndedUnexpectedly)
                    return
                }
            } catch is CancellationError {
                continuation.finish()
                return
            } catch let error as AIProviderError {
                if case .network = error,
                   error != AIProviderError.network("cancelled"),
                   attempts < retryPolicy.maxZeroDeltaRetries
                {
                    Self.logger.info("Retrying Anthropic stream after network error (attempt \(attempts + 1))")
                    try? await Task.sleep(for: .seconds(retryPolicy.delaySeconds(zeroDeltas: attempts + 1)))
                    attempts += 1
                    continue
                }
                continuation.finish(throwing: error)
                return
            } catch {
                continuation.finish(throwing: error)
                return
            }
        }
    }

    private func streamOnce(
        request: ChatCompletionRequest,
        url: URL,
        continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation
    ) async throws -> StreamOutcome {
        let body = try Self.encodeRequestBody(request)
        let urlRequest = Self.makeRequest(url: url, apiKey: apiKey, body: body)
        let (status, stream): (Int, AsyncThrowingStream<Data, Error>)
        do {
            (status, stream) = try await http.streamData(request: urlRequest)
        } catch {
            throw Self.mapStreamError(error)
        }

        guard (200 ..< 300).contains(status) else {
            let bodyText = try await Self.collectBoundedBody(from: stream)
            throw AIProviderError.httpStatus(status, Self.sanitizeBody(bodyText))
        }

        var parser = SSEParser()
        let accumulator = ToolCallAccumulator()
        var hasProgress = false
        var messageDone = false
        var usage: TokenUsage?

        do {
            for try await chunk in stream {
                if Task.isCancelled {
                    throw CancellationError()
                }
                for line in parser.parse(chunk) {
                    guard let data = line.jsonData else { continue }
                    let event = try Self.decodeEvent(from: data)
                    switch event {
                    case .contentStart:
                        // Text block start carries no payload we act on.
                        break
                    case let .contentDelta(_, text):
                        if !text.isEmpty {
                            hasProgress = true
                            continuation.yield(.content(text))
                        }
                    case let .contentBlockStart(index, toolUse):
                        if let toolUse {
                            let running = await accumulator.accumulate(
                                fragment: "",
                                at: index,
                                id: toolUse.id,
                                name: toolUse.name
                            )
                            continuation.yield(.toolCall(running))
                        }
                    case let .contentBlockDelta(index, part):
                        if let text = part.text, !text.isEmpty {
                            hasProgress = true
                            continuation.yield(.content(text))
                        } else if let input = part.inputJSON {
                            hasProgress = true
                            let running = await accumulator.accumulate(
                                fragment: input,
                                at: index,
                                id: nil,
                                name: nil
                            )
                            continuation.yield(.toolCall(running))
                        }
                    case let .messageDelta(usageDelta):
                        if let usageDelta {
                            usage = usageDelta
                            continuation.yield(.usage(usageDelta))
                        }
                    case .messageStop:
                        messageDone = true
                    case .unhandled:
                        break
                    }
                }
                if messageDone {
                    break
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Self.mapStreamError(error)
        }

        // Finalize any tool blocks left open.
        let open = await accumulator.remainingIndices.sorted()
        for index in open {
            if let finalCall = await accumulator.complete(at: index) {
                continuation.yield(.toolCallComplete(finalCall))
            }
        }

        if messageDone {
            return .completed
        }
        if hasProgress || usage != nil {
            return .completed
        }
        return .unfinished(hasProgress: false)
    }

    // MARK: - Request building

    /// `…/v1/messages`, tolerating a base URL that already carries `/v1`.
    static func messagesURL(from baseURL: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = trimmed.hasSuffix("/v1") ? "/messages" : "/v1/messages"
        guard let url = URL(string: trimmed + suffix) else {
            throw AIProviderError.invalidBaseURL(baseURL)
        }
        return url
    }

    static func makeRequest(url: URL, apiKey: String, body: Data) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = body
        return request
    }

    static func encodeRequestBody(_ request: ChatCompletionRequest) throws -> Data {
        var payload: [String: JSONValue] = [
            "model": .string(request.model),
            "max_tokens": .integer(2048),
            "temperature": .number(request.temperature),
            "stream": .boolean(request.stream),
            "messages": .array(Self.encodeMessages(request.messages)),
        ]
        if let systemPrompt = request.systemPrompt, !systemPrompt.isEmpty {
            payload["system"] = .string(systemPrompt)
        }
        if !request.tools.isEmpty {
            payload["tools"] = .array(request.tools.map(Self.encodeTool))
        }
        return try JSONEncoder().encode(payload)
    }

    static func encodeMessages(_ messages: [ChatMessage]) -> [JSONValue] {
        var out: [JSONValue] = []
        for message in messages {
            var fields: [String: JSONValue] = ["role": .string(Self.anthropicRole(message.role))]
            switch message.role {
            case .system:
                // Anthropic carries the system prompt at the top level; a literal
                // system message is downgraded to a user turn.
                fields["role"] = .string("user")
                fields["content"] = .string(message.content)
            case .user:
                fields["content"] = .string(message.content)
            case .assistant:
                fields["content"] = .string(message.content)
                if !message.toolCalls.isEmpty {
                    var content: [JSONValue] = []
                    if !message.content.isEmpty {
                        content.append(.object(["type": .string("text"), "text": .string(message.content)]))
                    }
                    for call in message.toolCalls {
                        let args: JSONValue = Self.parseArgumentsJSON(call.argumentsJSON) ?? .object([:])
                        content.append(.object([
                            "type": .string("tool_use"),
                            "id": .string(call.id),
                            "name": .string(call.name),
                            "input": args,
                        ]))
                    }
                    fields["content"] = .array(content)
                }
            case .tool:
                fields["role"] = .string("user")
                fields["content"] = .array([
                    .object([
                        "type": .string("tool_result"),
                        "tool_use_id": .string(message.toolCallID ?? ""),
                        "content": .string(message.content),
                    ]),
                ])
            }
            out.append(.object(fields))
        }
        return out
    }

    static func encodeTool(_ tool: ToolDefinition) -> JSONValue {
        // Anthropic wants parameters inside `input_schema` without a top-level type.
        var schema = tool.parameters
        if case let .object(fields) = tool.parameters, fields["type"] == nil {
            var fused = fields
            fused["type"] = .string("object")
            schema = .object(fused)
        }
        return .object([
            "name": .string(tool.name),
            "description": .string(tool.description),
            "input_schema": schema,
        ])
    }

    // MARK: - Stream event decoding

    enum AnthropicStreamEvent: Sendable {
        case contentStart(Int, String?)
        case contentDelta(Int, String)
        case contentBlockStart(Int, AnthropicToolUse?)
        case contentBlockDelta(Int, AnthropicContentPart)
        case messageDelta(TokenUsage?)
        case messageStop
        case unhandled
    }

    /// A `tool_use` content block's opening fields.
    struct AnthropicToolUse: Sendable {
        var id: String
        var name: String
    }

    struct AnthropicContentPart: Sendable {
        var text: String?
        var inputJSON: String?
    }

    static func decodeEvent(from data: Data) throws -> AnthropicStreamEvent {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else {
            throw AIProviderError.invalidJSON(String(data: data, encoding: .utf8) ?? "<binary>")
        }

        switch type {
        case "content_block_start":
            guard let index = json["index"] as? Int else { return .unhandled }
            if let contentBlock = json["content_block"] as? [String: Any],
               let blockType = contentBlock["type"] as? String
            {
                if blockType == "tool_use", let name = contentBlock["name"] as? String {
                    let toolUse = AnthropicToolUse(
                        id: contentBlock["id"] as? String ?? "",
                        name: name
                    )
                    return .contentBlockStart(index, toolUse)
                }
                if blockType == "text" {
                    return .contentStart(index, contentBlock["text"] as? String)
                }
            }
            return .unhandled
        case "content_block_delta":
            guard let index = json["index"] as? Int,
                  let delta = json["delta"] as? [String: Any]
            else {
                return .unhandled
            }
            let deltaType = delta["type"] as? String
            if deltaType == "text_delta", let text = delta["text"] as? String {
                return .contentDelta(index, text)
            }
            if deltaType == "input_json_delta", let partial = delta["partial_json"] as? String {
                return .contentBlockDelta(index, AnthropicContentPart(inputJSON: partial))
            }
            return .unhandled
        case "message_delta":
            if let usage = json["usage"] as? [String: Any],
               let inputTokens = usage["input_tokens"] as? Int,
               let outputTokens = usage["output_tokens"] as? Int
            {
                return .messageDelta(
                    TokenUsage(
                        promptTokens: inputTokens,
                        completionTokens: outputTokens,
                        totalTokens: inputTokens + outputTokens
                    )
                )
            }
            return .messageDelta(nil)
        case "message_stop":
            return .messageStop
        default:
            return .unhandled
        }
    }

    // MARK: - Shared helpers

    static func anthropicRole(_ role: ChatRole) -> String {
        switch role {
        case .system: return "user"
        case .tool: return "user"
        case .user: return "user"
        case .assistant: return "assistant"
        }
    }

    static func parseArgumentsJSON(_ text: String?) -> JSONValue? {
        guard let text, let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    static func collectBoundedBody(from stream: AsyncThrowingStream<Data, Error>) async throws -> Data {
        var body = Data()
        for try await chunk in stream {
            body.append(chunk)
            if body.count > 4096 {
                break
            }
        }
        return body
    }

    static func sanitizeBody(_ raw: Data) -> String? {
        let text = String(data: raw, encoding: .utf8) ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count > 256 ? String(trimmed.prefix(256)) : trimmed
    }

    static func mapStreamError(_ error: Error) -> AIProviderError {
        if let providerError = error as? AIProviderError {
            return providerError
        }
        if error is CancellationError {
            return .network("cancelled")
        }
        return .network(error.localizedDescription)
    }
}

/// Outcome of one adapter stream attempt.
private enum StreamOutcome: Sendable {
    case completed
    case unfinished(hasProgress: Bool)
}
