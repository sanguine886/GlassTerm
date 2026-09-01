@testable import AIAgent
import XCTest

private actor TriggerBox {
    private(set) var count = 0
    func bump() { count += 1 }
}

final class AgentKillSwitchTests: XCTestCase {
    private func pollUntilCount(_ box: TriggerBox, equals expected: Int) async {
        for _ in 0..<100 {
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
        XCTAssertFalse(await token.isCancelled)
        await token.cancel()
        await pollUntilCount(box, equals: 1)
        XCTAssertEqual(await box.count, 1)
        XCTAssertTrue(await token.isCancelled)
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
        XCTAssertEqual(await box.count, 0)
        XCTAssertTrue(await token.isCancelled)
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
        XCTAssertEqual(await box.count, 2)
    }

    func testCancelIsIdempotent() async {
        let token = AgentCancellationToken()
        let box = TriggerBox()
        _ = await token.register { await box.bump() }
        await token.cancel()
        await pollUntilCount(box, equals: 1)
        await token.cancel()
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(await box.count, 1)
    }
}
