import Foundation

/// One parsed server-sent event frame (spec §2.1). `jsonData` holds the payload
/// of the first `data:` field when present.
public struct SSELine: Sendable, Equatable {
    public let event: String?
    public let jsonData: Data?

    public init(event: String?, jsonData: Data?) {
        self.event = event
        self.jsonData = jsonData
    }
}

/// Incremental SSE parser. Consume raw UTF-8 data with arbitrary chunk
/// boundaries; each `parse(_:)` returns the complete frames that were finished
/// by that chunk. `[DONE]` marks the logical end of the stream and the parser
/// stays done afterwards.
public struct SSEParser: Sendable {
    public private(set) var buffer: String
    /// The most recent complete frame's `data:` payload (none after `[DONE]`).
    public private(set) var jsonData: Data?
    /// Whether the stream reached the `[DONE]` sentinel.
    public private(set) var isDone: Bool
    /// The most recent frame's `event:` field (rarely provided).
    public private(set) var lastEvent: String?

    public init() {
        buffer = ""
        jsonData = nil
        isDone = false
        lastEvent = nil
    }

    /// Consumes `data` and returns the frames completed by this chunk.
    /// Frames are returned in wire order; empty-data frames are skipped.
    @discardableResult
    public mutating func parse(_ data: Data) -> [SSELine] {
        guard let chunk = String(data: data, encoding: .utf8) else { return [] }
        buffer.append(chunk)

        var frames: [SSELine] = []
        while !isDone {
            guard let boundary = nextFrameBoundary() else { break }

            let frame = String(buffer[..<boundary.lowerBound])
            buffer.removeSubrange(..<boundary.upperBound)

            let payload = Self.framePayload(from: frame)
            if Self.isDoneSentinel(payload) {
                isDone = true
                jsonData = nil
                break
            }
            if payload.isEmpty {
                continue
            }
            jsonData = Data(payload.utf8)
            lastEvent = Self.frameEvent(from: frame)
            frames.append(SSELine(event: lastEvent, jsonData: jsonData))
        }
        return frames
    }

    /// Parses a single complete frame atomically (used directly by unit tests).
    public mutating func parseFrame(_ frame: String) {
        let payload = Self.framePayload(from: frame)
        if Self.isDoneSentinel(payload) {
            isDone = true
            jsonData = nil
            return
        }
        if payload.isEmpty {
            jsonData = nil
            return
        }
        jsonData = Data(payload.utf8)
        lastEvent = Self.frameEvent(from: frame)
    }

    // MARK: - Internals

    /// Concatenates every `data:` field value in a frame (SSE semantics: data
    /// fields join with a newline).
    static func framePayload(from frame: String) -> String {
        frame
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line in
                guard line.hasPrefix("data:") else { return nil }
                var value = line.dropFirst("data:".count)
                if value.first == " " {
                    value = value.dropFirst()
                }
                return String(value)
            }
            .joined(separator: "\n")
    }

    /// Returns the `event:` field value of a frame, or `nil`.
    static func frameEvent(from frame: String) -> String? {
        for line in frame.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("event:") {
                var value = line.dropFirst("event:".count)
                if value.first == " " {
                    value = value.dropFirst()
                }
                return String(value)
            }
        }
        return nil
    }

    /// The first frame delimiter (`\n\n` or `\r\n\r\n`) still buffered.
    private func nextFrameBoundary() -> Range<String.Index>? {
        if let range = buffer.range(of: "\r\n\r\n") {
            return range
        }
        if let range = buffer.range(of: "\n\n") {
            return range
        }
        return nil
    }

    private static func isDoneSentinel(_ payload: String) -> Bool {
        payload.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]"
    }
}