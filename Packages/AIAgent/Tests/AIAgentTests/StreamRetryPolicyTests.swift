import AIAgent
import XCTest

final class StreamRetryPolicyTests: XCTestCase {
    func testDefaultPolicy() {
        let policy = StreamRetryPolicy.default
        XCTAssertEqual(policy.maxZeroDeltaRetries, 2)
        XCTAssertEqual(policy.baseDelaySeconds, 0.5)
        XCTAssertEqual(policy.maxDelaySeconds, 4)
    }

    func testZeroDeltaStallIsRetried() {
        let policy = StreamRetryPolicy()
        XCTAssertTrue(policy.shouldAutoRetry(zeroDeltas: 1, hasProgress: false))
        XCTAssertTrue(policy.shouldAutoRetry(zeroDeltas: 2, hasProgress: false))
    }

    func testRetryBudgetExhausted() {
        let policy = StreamRetryPolicy(maxZeroDeltaRetries: 2)
        XCTAssertFalse(policy.shouldAutoRetry(zeroDeltas: 3, hasProgress: false))
    }

    func testZeroDeltasCannotBeZero() {
        let policy = StreamRetryPolicy()
        XCTAssertFalse(policy.shouldAutoRetry(zeroDeltas: 0, hasProgress: false))
    }

    func testProgressStallIsNeverRetried() {
        // Once the stream produced *something*, retrying risks double-charging.
        let policy = StreamRetryPolicy(maxZeroDeltaRetries: 5)
        XCTAssertFalse(policy.shouldAutoRetry(zeroDeltas: 1, hasProgress: true))
        XCTAssertFalse(policy.shouldAutoRetry(zeroDeltas: 5, hasProgress: true))
    }

    func testExponentialBackoff() {
        let policy = StreamRetryPolicy(baseDelaySeconds: 0.5, maxDelaySeconds: 4)
        XCTAssertEqual(policy.delaySeconds(zeroDeltas: 1), 0.5)
        XCTAssertEqual(policy.delaySeconds(zeroDeltas: 2), 1.0)
        XCTAssertEqual(policy.delaySeconds(zeroDeltas: 3), 2.0)
    }

    func testBackoffCapped() {
        let policy = StreamRetryPolicy(baseDelaySeconds: 0.5, maxDelaySeconds: 4)
        XCTAssertEqual(policy.delaySeconds(zeroDeltas: 10), 4)
    }

    func testNegativeDeltaClampsToBase() {
        let policy = StreamRetryPolicy(baseDelaySeconds: 0.5)
        XCTAssertEqual(policy.delaySeconds(zeroDeltas: 0), 0.5)
    }
}
