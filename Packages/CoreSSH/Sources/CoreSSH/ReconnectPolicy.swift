import Foundation

/// Exponential-backoff reconnect policy (spec §4.1: exponential backoff, max 5 attempts).
public struct ReconnectPolicy: Equatable, Sendable {
    public let maxAttempts: Int
    public let baseDelaySeconds: Double
    public let maxDelaySeconds: Double

    public static let standard = ReconnectPolicy()

    public init(maxAttempts: Int = 5, baseDelaySeconds: Double = 0.5, maxDelaySeconds: Double = 8.0) {
        self.maxAttempts = maxAttempts
        self.baseDelaySeconds = baseDelaySeconds
        self.maxDelaySeconds = maxDelaySeconds
    }

    /// Whether another reconnect attempt may run after `failedAttempts` consecutive failures.
    public func shouldRetry(afterFailedAttempts failedAttempts: Int) -> Bool {
        failedAttempts < maxAttempts
    }

    /// Delay before the attempt following `failedAttempts` consecutive failures:
    /// base * 2^n, capped at `maxDelaySeconds`, plus caller-supplied jitter.
    public func delaySeconds(afterFailedAttempts failedAttempts: Int, jitterSeconds: Double = 0) -> Double {
        let exponential = baseDelaySeconds * pow(2, Double(max(0, failedAttempts)))
        return min(exponential, maxDelaySeconds) + jitterSeconds
    }
}
