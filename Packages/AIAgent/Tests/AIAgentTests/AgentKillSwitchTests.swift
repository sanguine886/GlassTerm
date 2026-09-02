@testable import AIAgent
import XCTest

private actor TriggerBox {
    private(set) var count = 0
    func bump() {
        count += 1
    }
}

final class AgentKillSwitchTests: XCTestCase {
    private func pollUntilCount(_ box: TriggerBox, equals expected: Int) async {
        for _ in 0 ..< 100 {
            if await box.count == expected {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func testCancelTriggersRegisteredHandler() async {
        let token = AgentCancellationToken()
        let box = TriggerBox()
        await token.register { await box.bump() }
        let notCancelled = await token.isCancelled
        XCTAssertFalse(notCancelled)
        await token.cancel()
        await pollUntilCount(box, equals: 1)
        let firedCount = await box.count
        XCTAssertEqual(firedCount, 1)
        let cancelledNow = await token.isCancelled
        XCTAssertTrue(cancelledNow)
    }

    func testUnregisteredHandlerIsNotFiredOnCancel() async {
        let token = AgentCancellationToken()
        let box = TriggerBox()
        let id = await token.register {
            await box.bump()
        }
        await token.unregister(id)
        await token.cancel()
        try? await Task.sleep(for: .milliseconds(50))
        let count = await box.count
        XCTAssertEqual(count, 0)
        let isCancelled = await token.isCancelled
        XCTAssertTrue(isCancelled)
    }

    func testThrowIfCancelledThrowsAfterCancel() async {
        let token = AgentCancellationToken()
        try? await token.throwIfCancelled()
        await token.cancel()
        do {
            try await token.throwIfCancelled()
            XCTFail("throwIfCancelled should have thrown after cancel")
        } catch let error as AgentError {
            XCTAssertEqual(error, .cancelled)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testMultipleHandlersAllFiredOnCancel() async {
        let token = AgentCancellationToken()
        let box = TriggerBox()
        _ = await token.register { await box.bump() }
        _ = await token.register { await box.bump() }
        await token.cancel()
        await pollUntilCount(box, equals: 2)
        let fired = await box.count
        XCTAssertEqual(fired, 2)
    }

    func testCancelIsIdempotent() async {
        let token = AgentCancellationToken()
        let box = TriggerBox()
        _ = await token.register { await box.bump() }
        await token.cancel()
        await pollUntilCount(box, equals: 1)
        await token.cancel()
        try? await Task.sleep(for: .milliseconds(30))
        let stillOnce = await box.count
        XCTAssertEqual(stillOnce, 1)
    }
}
