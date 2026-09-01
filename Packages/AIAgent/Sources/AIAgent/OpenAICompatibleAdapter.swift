import Foundation
import os

/// OpenAI-compatible adapter (spec §2.3). Speaks `POST /v1/chat/completions`
/// with `stream: true` and normalizes the `choices[].delta` SSE chunks into
/// `ChatStreamEvent`s. Tool calls arrive fragmented per `index` and are
/// accumulated by `ToolCallAccumulator`.
public struct OpenAICompatibleAdapter: AIChatStreaming {
    private static let logger = Logger(subsystem: "com.glazeterm.AIAgent", category: "OpenAI")

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
        let url = try Self.chatCompletionsURL(from: config.baseURL)
        // One idempotency key per logical turn; retries reuse it so the vendor
        // can de-duplicate restarted requests (spec §4.5).
        let idempotencyKey = UUID().uuidString
        return AsyncThrowingStream<ChatStreamEvent, Error>(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                await run(
                    request: request,
                    url: url,
                    idempotencyKey: idempotencyKey,
                    continuation: continuation
                )
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Internals

    private func run(
        request: ChatCompletionRequest,
        url: URL,
        idempotencyKey: String,
        continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation
    ) async {
        var attempts = 0
        while true {
            if Task.isCancelled {
                continuation.finish()
                return
            }
            do {
                let outcome = try await streamOnce(
                    request: request,
                    url: url,
                    idempotencyKey: idempotencyKey,
                    continuation: continuation
                )
                switch outcome {
                case .completed:
                    continuation.yield(.done)
                    continuation.finish()
                    return
                case let .unfinished(hasProgress):
                    if !hasProgress, attempts < retryPolicy.maxZeroDeltaRetries {
                        Self.logger.info("Retrying stalled OpenAI stream (attempt \(attempts + 1))")
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
                    Self.logger.info("Retrying OpenAI stream after network error (attempt \(attempts + 1))")
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

    /// One HTTP round-trip. Yields normalized events into `continuation`.
    /// Returns `.completed` once a terminal state was reached, or
    /// `.unfinished` when the provider hangs up without ending progress.
    private func streamOnce(
        request: ChatCompletionRequest,
        url: URL,
        idempotencyKey: String,
        continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation
    ) async throws -> StreamOutcome {
        let body = try Self.encodeRequestBody(request)
        let urlRequest = Self.makeRequest(url: url, apiKey: apiKey, body: body, idempotencyKey: idempotencyKey)
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
        var doneEmitted = false
        var usage: TokenUsage?

        do {
            for try await chunk in stream {
                if Task.isCancelled {
                    throw CancellationError()
                }
                for line in parser.parse(chunk) {
                    guard let data = line.jsonData else { continue }
                    let delta = try Self.decodeDelta(from: data)
                    if let text = delta.content, !text.isEmpty {
                        hasProgress = true
                        continuation.yield(.content(text))
                    }
                    for fragment in delta.toolFragments {
                        hasProgress = true
                        let running = await accumulator.accumulate(
                            fragment: fragment.argumentsFragment,
                            at: fragment.index,
                            id: fragment.id,
                            name: fragment.name
                        )
                        continuation.yield(.toolCall(running))
                    }
                    if let tokenUsage = delta.usage {
                        usage = tokenUsage
                        continuation.yield(.usage(tokenUsage))
                    }
                }
                if parser.isDone {
                    doneEmitted = true
                    break
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Self.mapStreamError(error)
        }

        // Finalize any tool calls left open when the stream ended.
        let open = await accumulator.remainingIndices.sorted()
        for index in open {
            if let finalCall = await accumulator.complete(at: index) {
                continuation.yield(.toolCallComplete(finalCall))
            }
        }

        if doneEmitted {
            return .completed
        }
        if hasProgress || usage != nil {
            return .completed
        }
        return .unfinished(hasProgress: false)
    }

    // MARK: - Request building

    /// `…/v1/chat/completions`, tolerating a base URL that already carries `/v1`.
    static func chatCompletionsURL(from baseURL: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = trimmed.hasSuffix("/v1") ? "/chat/completions" : "/v1/chat/completions"
        guard let url = URL(string: trimmed + suffix) else {
            throw AIProviderError.invalidBaseURL(baseURL)
        }
        return url
    }

    static func makeRequest(
        url: URL,
        apiKey: String,
        body: Data,
        idempotencyKey: String = UUID().uuidString
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = body
        return request
    }

    static func encodeRequestBody(_ request: ChatCompletionRequest) throws -> Data {
        var payload: [String: JSONValue] = [
            "model": .string(request.model),
            "temperature": .number(request.temperature),
            "stream": .boolean(request.stream),
            "messages": .array(Self.encodeMessages(request.messages)),
        ]
        if !request.tools.isEmpty {
            payload["tools"] = .array(request.tools.map(Self.encodeTool))
        }
        // systemPrompt rides as the first `system` message so tool-order is stable.
        if let systemPrompt = request.systemPrompt, !systemPrompt.isEmpty {
            let systemMessage = JSONValue.object([
                "role": .string("system"),
                "content": .string(systemPrompt),
            ])
            payload["messages"] = .array([systemMessage] + Self.encodeMessages(request.messages))
        }
        return try JSONEncoder().encode(payload)
    }

    static func encodeMessages(_ messages: [ChatMessage]) -> [JSONValue] {
        var out: [JSONValue] = []
        for message in messages {
            var fields: [String: JSONValue] = ["role": .string(message.role.rawValue)]
            switch message.role {
            case .system, .user:
                fields["content"] = .string(message.content)
            case .assistant:
                fields["content"] = .string(message.content)
                if !message.toolCalls.isEmpty {
                    fields["tool_calls"] = .array(message.toolCalls.map(Self.encodeToolCall))
                }
            case .tool:
                fields["content"] = .string(message.content)
                fields["tool_call_id"] = .string(message.toolCallID ?? "")
            }
            out.append(.object(fields))
        }
        return out
    }

    static func encodeToolCall(_ call: AssistantToolCall) -> JSONValue {
        .object([
            "id": .string(call.id),
            "type": .string("function"),
            "function": .object([
                "name": .string(call.name),
                "arguments": .string(call.argumentsJSON ?? ""),
            ]),
        ])
    }

    static func encodeTool(_ tool: ToolDefinition) -> JSONValue {
        .object([
            "type": .string("function"),
            "function": .object([
                "name": .string(tool.name),
                "description": .string(tool.description),
                "parameters": tool.parameters,
            ]),
        ])
    }

    // MARK: - SSE chunk decoding

    struct OpenAIToolFragment: Sendable {
        var index: Int
        var id: String?
        var name: String?
        var argumentsFragment: String
    }

    struct OpenAIDelta: Sendable {
        var content: String?
        var toolFragments: [OpenAIToolFragment]
        var usage: TokenUsage?

        init(content: String? = nil, toolFragments: [OpenAIToolFragment] = [], usage: TokenUsage? = nil) {
            self.content = content
            self.toolFragments = toolFragments
            self.usage = usage
        }
    }

    static func decodeDelta(from data: Data) throws -> OpenAIDelta {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let choice = choices.first
        else {
            throw AIProviderError.invalidJSON(String(data: data, encoding: .utf8) ?? "<binary>")
        }

        var delta = OpenAIDelta()
        if let rawDelta = choice["delta"] as? [String: Any] {
            delta.content = rawDelta["content"] as? String
            if let toolCalls = rawDelta["tool_calls"] as? [[String: Any]] {
                for toolCall in toolCalls {
                    guard let index = toolCall["index"] as? Int else { continue }
                    var fragment = OpenAIToolFragment(index: index, id: nil, name: nil, argumentsFragment: "")
                    fragment.id = toolCall["id"] as? String
                    if let function = toolCall["function"] as? [String: Any] {
                        fragment.name = function["name"] as? String
                        fragment.argumentsFragment = function["arguments"] as? String ?? ""
                    }
                    delta.toolFragments.append(fragment)
                }
            }
        }
        if let usage = json["usage"] as? [String: Any],
           let prompt = usage["prompt_tokens"] as? Int,
           let completion = usage["completion_tokens"] as? Int,
           let total = usage["total_tokens"] as? Int
        {
            delta.usage = TokenUsage(promptTokens: prompt, completionTokens: completion, totalTokens: total)
        }
        return delta
    }

    // MARK: - Shared helpers

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

    /// Maps a transport throw into an `AIProviderError`, preserving already
    /// normalized decode errors untouched.
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
