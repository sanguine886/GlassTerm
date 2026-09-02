import CoreSSH
import XCTest

final class ReconnectPolicyTests: XCTestCase {
    func testExponentialBackoffProgression() {
        let policy = ReconnectPolicy(maxAttempts: 5, baseDelaySeconds: 0.5, maxDelaySeconds: 8)

        XCTAssertEqual(policy.delaySeconds(afterFailedAttempts: 0), 0.5)
        XCTAssertEqual(policy.delaySeconds(afterFailedAttempts: 1), 1.0)
        XCTAssertEqual(policy.delaySeconds(afterFailedAttempts: 2), 2.0)
        XCTAssertEqual(policy.delaySeconds(afterFailedAttempts: 3), 4.0)
        XCTAssertEqual(policy.delaySeconds(afterFailedAttempts: 4), 8.0)
    }

    func testDelayIsCapped() {
        let policy = ReconnectPolicy(maxAttempts: 10, baseDelaySeconds: 0.5, maxDelaySeconds: 8)
        XCTAssertEqual(policy.delaySeconds(afterFailedAttempts: 6), 8)
        XCTAssertEqual(policy.delaySeconds(afterFailedAttempts: 20), 8)
    }

    func testRetryStopsAtMaxAttempts() {
        let policy = ReconnectPolicy(maxAttempts: 5)

        for failed in 0 ..< 5 {
            XCTAssertTrue(policy.shouldRetry(afterFailedAttempts: failed))
        }
        XCTAssertFalse(policy.shouldRetry(afterFailedAttempts: 5))
        XCTAssertFalse(policy.shouldRetry(afterFailedAttempts: 6))
    }

    func testJitterIsAdded() {
        let policy = ReconnectPolicy(maxAttempts: 5, baseDelaySeconds: 1, maxDelaySeconds: 8)
        XCTAssertEqual(policy.delaySeconds(afterFailedAttempts: 0, jitterSeconds: 0.25), 1.25)
    }

    func testNegativeAttemptClampsToBaseDelay() {
        let policy = ReconnectPolicy(maxAttempts: 5, baseDelaySeconds: 0.5)
        XCTAssertEqual(policy.delaySeconds(afterFailedAttempts: -3), 0.5)
    }
}
