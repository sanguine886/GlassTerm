import AIAgent
import Foundation

/// Scripted in-memory transport for adapter unit tests (spec §6.5.2: fake
/// provider injection). No network is touched.
actor FakeHTTPStreamingTransport: HTTPStreamingTransport {
    struct Pending {
        var statusCode: Int
        var chunks: [Data]
        var body: Data?

        init(statusCode: Int, chunks: [Data] = [], body: Data? = nil) {
            self.statusCode = statusCode
            self.chunks = chunks
            self.body = body
        }
    }

    private var queue: [Pending]
    private(set) var receivedRequests: [URLRequest] = []

    init(_ pending: [Pending]) {
        queue = pending
    }

    func streamData(
        request: URLRequest
    ) async throws -> (statusCode: Int, AsyncThrowingStream<Data, Error>) {
        receivedRequests.append(request)
        let pending = queue.removeFirst()
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            for chunk in pending.chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
        return (pending.statusCode, stream)
    }

    func data(for request: URLRequest) async throws -> (statusCode: Int, Data) {
        receivedRequests.append(request)
        let pending = queue.removeFirst()
        return (pending.statusCode, pending.body ?? Data())
    }
}

/// Transport that fails the first `failures` stream calls, then serves the
/// scripted `successChunks` on the next call (for retry-policy tests). The
/// fallthrough avoids exhausting `FakeHTTPStreamingTransport`'s queue and
/// crashing on an empty `removeFirst`.
actor NeverFailingTransport: HTTPStreamingTransport {
    let failures: Int
    let successChunks: [Data]
    private(set) var calls = 0

    init(failures: Int = 1, successChunks: [Data]) {
        self.failures = failures
        self.successChunks = successChunks
    }

    func streamData(
        request _: URLRequest
    ) async throws -> (statusCode: Int, AsyncThrowingStream<Data, Error>) {
        calls += 1
        if calls <= failures {
            throw URLError(.notConnectedToInternet)
        }
        let chunks = successChunks
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
        return (200, stream)
    }

    func data(for _: URLRequest) async throws -> (statusCode: Int, Data) {
        calls += 1
        return (200, Data())
    }
}

/// A `data: ...\n\n` frame whose payload is the literal string given.
func sseRaw(_ payload: String) -> String {
    "data: \(payload)\n\n"
}

func data(_ content: String) -> Data {
    Data(content.utf8)
}

/// Convenience for building chunk arrays.
func chunkStream(_ chunks: [String]) -> [Data] {
    chunks.map(data)
}

let testConfig = AIProviderConfig(
    name: "Test",
    kind: .openAICompatible,
    baseURL: "https://api.example.com",
    model: "gpt-4o-mini",
    apiKeyRef: "test-key-ref"
)

let testAPIKey = "sk-test-123"

let userMessage = ChatMessage(role: .user, content: "Hi there")
