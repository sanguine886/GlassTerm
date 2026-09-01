@testable import AIAgent
import XCTest

final class AuditLogTests: XCTestCase {
    func testRecordAndEntriesRoundTrip() async {
        let log = InMemoryAuditLog()
        let now = Date(timeIntervalSince1970: 1700000000)
        let entry = AuditEntry(
            timestamp: now,
            toolName: "run_command",
            commandText: "ls /home",
            resultSummary: "home  user",
            approver: "auto",
            strategy: .autoReview,
            outcome: .autoApproved
        )

        await log.record(entry)
        let entries = await log.entries()

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].timestamp, now)
        XCTAssertEqual(entries[0].toolName, "run_command")
        XCTAssertEqual(entries[0].commandText, "ls /home")
        XCTAssertEqual(entries[0].resultSummary, "home  user")
        XCTAssertEqual(entries[0].approver, "auto")
        XCTAssertEqual(entries[0].strategy, .autoReview)
        XCTAssertEqual(entries[0].outcome, .autoApproved)
    }

    func testRecordAppendsInOrder() async {
        let log = InMemoryAuditLog()
        for index in 0..<3 {
            await log.record(
                AuditEntry(
                    timestamp: Date(),
                    toolName: "run_command",
                    commandText: "cmd \(index)",
                    resultSummary: "",
                    approver: "auto",
                    strategy: .alwaysAsk,
                    outcome: .userApproved
                )
            )
        }
        let entries = await log.entries()
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].commandText, "cmd 0")
        XCTAssertEqual(entries[2].commandText, "cmd 2")
    }

    func testClearEmptiesLog() async {
        let log = InMemoryAuditLog()
        await log.record(
            AuditEntry(
                timestamp: Date(),
                toolName: "read_file",
                commandText: "cat /etc/hostname",
                resultSummary: "host",
                approver: "auto",
                strategy: .readOnly,
                outcome: .denied
            )
        )
        XCTAssertEqual(await log.entries().count, 1)
        await log.clear()
        XCTAssertEqual(await log.entries().count, 0)
    }

    func testInitialStateEmpty() async {
        let log = InMemoryAuditLog()
        XCTAssertEqual(await log.entries().count, 0)
    }
}
