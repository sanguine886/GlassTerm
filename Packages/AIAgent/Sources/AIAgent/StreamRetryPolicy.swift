import Foundation

/// Retry policy for zero-increment stalls on a streaming response (spec §4.5:
/// "断流重试不重复计费请求"). Only *zero-increment* stalls — no content delta and
/// no tool-call delta within the allowance window — are retried. A stall that has
/// produced *some* progress is never retried (that would risk double-charging for
/// a completed turn).
public struct StreamRetryPolicy: Sendable {
    /// How many zero-increment stalls to absorb before giving up.
    public var maxZeroDeltaRetries: Int
    /// Base delay before the first retry.
    public var baseDelaySeconds: Double
    /// Cap for the exponential backoff.
    public var maxDelaySeconds: Double

    public static let `default` = StreamRetryPolicy()

    public init(
        maxZeroDeltaRetries: Int = 2,
        baseDelaySeconds: Double = 0.5,
        maxDelaySeconds: Double = 4
    ) {
        self.maxZeroDeltaRetries = maxZeroDeltaRetries
        self.baseDelaySeconds = baseDelaySeconds
        self.maxDelaySeconds = maxDelaySeconds
    }

    /// Whether a stall is worth retrying at all. `zeroDeltas` counts consecutive
    /// events that carried no progress; `hasProgress` says whether *any* content
    /// or tool-call delta was seen before the stall started.
    public func shouldAutoRetry(zeroDeltas: Int, hasProgress: Bool) -> Bool {
        guard !hasProgress, zeroDeltas > 0 else { return false }
        return zeroDeltas <= maxZeroDeltaRetries
    }

    /// Exponential backoff before retry `zeroDeltas` (1-based): `base * 2^n`,
    /// capped at `maxDelaySeconds`.
    public func delaySeconds(zeroDeltas: Int) -> Double {
        let exponent = Double(max(0, zeroDeltas - 1))
        return min(baseDelaySeconds * pow(2, exponent), maxDelaySeconds)
    }
}