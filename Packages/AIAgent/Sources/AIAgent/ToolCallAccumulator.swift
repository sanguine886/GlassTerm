import Foundation

/// Accumulates tool-call fragments by the vendor's chunk index. OpenAI streams
/// `tool_calls[].index` while ids and names arrive only on the first chunk;
/// Anthropic keys content blocks by `index`. Storing the running delta lets
/// adapters emit normalized `.toolCall` events and finish with
/// `.toolCallComplete`. Actor-isolated so concurrent stream tasks (rare) never
/// interleave fragments.
actor ToolCallAccumulator {
    private var frames: [Int: ChatToolCallDelta] = [:]

    /// Appends one fragment to the frame at `index`. The first id wins; a
    /// non-nil name overwrites a missing one. Returns the running delta.
    func accumulate(
        fragment: String,
        at index: Int,
        id: String?,
        name: String?
    ) -> ChatToolCallDelta {
        var delta = frames[index] ?? ChatToolCallDelta(id: id ?? "call\(index)")
        if delta.name == nil, let name {
            delta.name = name
        }
        delta.argumentsJSON += fragment
        frames[index] = delta
        return delta
    }

    /// Finalizes and removes the frame at `index`.
    func complete(at index: Int) -> ChatToolCallDelta? {
        frames.removeValue(forKey: index)
    }

    /// Indices still being accumulated (for finalization after stream close).
    var remainingIndices: [Int] {
        Array(frames.keys)
    }
}
