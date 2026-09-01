import Foundation

extension URLSession.AsyncBytes {
    /// Bridges `AsyncBytes` to `AsyncThrowingStream<Data, Error>`, coalescing
    /// into 4 KiB chunks so adapters parse at reasonable boundaries.
    func asData() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var chunk = Data()
                chunk.reserveCapacity(4096)
                do {
                    for try await byte in self {
                        chunk.append(byte)
                        if chunk.count >= 4096 {
                            continuation.yield(chunk)
                            chunk.removeAll(keepingCapacity: true)
                        }
                    }
                    if !chunk.isEmpty {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Transport abstraction for adapter HTTP calls. Implemented by
/// `URLSessionHTTPStreamingTransport` in production and by fakes in unit tests
/// (spec §3.3). `streamData` returns an `AsyncThrowingStream` of raw body bytes;
/// adapters run their own SSE/JSON parsing on it.
public protocol HTTPStreamingTransport: Sendable {
    func streamData(
        request: URLRequest
    ) async throws -> (statusCode: Int, AsyncThrowingStream<Data, Error>)
    func data(for request: URLRequest) async throws -> (statusCode: Int, Data)
}

/// Production `HTTPStreamingTransport` over `URLSession`. Kept dependency-free:
/// no third-party networking stack (spec §3.2).
public struct URLSessionHTTPStreamingTransport: HTTPStreamingTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func streamData(
        request: URLRequest
    ) async throws -> (statusCode: Int, AsyncThrowingStream<Data, Error>) {
        let (bytes, response) = try await session.bytes(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (statusCode, bytes.asData())
    }

    public func data(for request: URLRequest) async throws -> (statusCode: Int, Data) {
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (statusCode, data)
    }
}

/// Builds the right adapter for a provider kind (spec §4.5). Returns an opaque
/// `any AIChatStreaming` so consumers depend on the protocol only.
public enum AIProviderAdapterFactory {
    public static func make(
        kind: AIProviderKind,
        config: AIProviderConfig,
        apiKey: String,
        http: any HTTPStreamingTransport = URLSessionHTTPStreamingTransport(),
        retryPolicy: StreamRetryPolicy = .default
    ) -> any AIChatStreaming {
        switch kind {
        case .openAICompatible:
            return OpenAICompatibleAdapter(config: config, apiKey: apiKey, http: http, retryPolicy: retryPolicy)
        case .anthropic:
            return AnthropicAdapter(config: config, apiKey: apiKey, http: http, retryPolicy: retryPolicy)
        case .gemini:
            return GeminiAdapter(config: config, apiKey: apiKey, http: http, retryPolicy: retryPolicy)
        }
    }
}