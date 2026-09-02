import Foundation
import Persistence
import XCTest

/// Persistence is a standalone package that also lives inside the app, so its
/// coverage is measured here via `swift test --package-path Packages/Persistence`
/// (the app's xccov report omits package sources). These tests mirror the
/// GlazeVerreTests assertions and add snippet coverage (ADR-0002/ADR-0005).
final class HostStoreTests: XCTestCase {
    func testCRUDRoundtripInMemory() throws {
        let container = try HostStore.makeContainer(inMemory: true)
        let store = HostStore(container: container)
        let record = HostRecord(name: "sanguine", hostname: "3.144.150.31", port: 22, username: "glassterm", authKind: .privateKey, secretRef: "ref-1")
        try store.add(record)

        let fetched = try store.record(id: record.id)
        XCTAssertEqual(fetched?.name, "sanguine")
        XCTAssertEqual(fetched?.authKind, .privateKey)
        XCTAssertEqual(fetched?.secretRef, "ref-1")

        try store.markConnected(id: record.id)
        XCTAssertNotNil(try store.record(id: record.id)?.lastConnectedAt)

        try store.delete(id: record.id)
        XCTAssertNil(try store.record(id: record.id))
    }

    func testUpdatePersistsFieldChanges() throws {
        let container = try HostStore.makeContainer(inMemory: true)
        let store = HostStore(container: container)
        let record = HostRecord(name: "before", hostname: "h", username: "u")
        try store.add(record)

        record.name = "after"
        record.port = 2222
        try store.update(record)

        let fetched = try store.record(id: record.id)
        XCTAssertEqual(fetched?.name, "after")
        XCTAssertEqual(fetched?.port, 2222)
    }

    func testAllSortedByCreation() throws {
        let container = try HostStore.makeContainer(inMemory: true)
        let store = HostStore(container: container)
        let older = HostRecord(name: "older", hostname: "a", username: "u", createdAt: Date(timeIntervalSinceNow: -100))
        let newer = HostRecord(name: "newer", hostname: "b", username: "u", createdAt: Date())
        try store.add(newer)
        try store.add(older)

        XCTAssertEqual(try store.all().map(\.name), ["older", "newer"])
    }

    func testAuthKindDefaultsToPasswordWhenRawCorrupt() {
        let record = HostRecord(name: "h", hostname: "h", username: "u")
        record.authKindRaw = "bogus"
        XCTAssertEqual(record.authKind, .password)
    }
}

final class SnippetStoreTests: XCTestCase {
    func testCRUDRoundtripInMemory() throws {
        let container = try SnippetStore.makeContainer(inMemory: true)
        let store = SnippetStore(container: container)
        let snippet = SnippetRecord(name: "health", command: "df -h")
        try store.add(snippet)

        let fetched = try store.all().first
        XCTAssertEqual(fetched?.name, "health")
        XCTAssertEqual(fetched?.command, "df -h")

        snippet.name = "disk"
        try store.update(snippet)
        XCTAssertEqual(try store.all().first?.name, "disk")

        try store.delete(id: snippet.id)
        XCTAssertTrue(try store.all().isEmpty)
    }

    func testTargetHostBinding() throws {
        let container = try SnippetStore.makeContainer(inMemory: true)
        let store = SnippetStore(container: container)
        let hostID = UUID()
        let snippet = SnippetRecord(name: "deploy", command: "deploy.sh", targetHostID: hostID)
        try store.add(snippet)
        XCTAssertEqual(try store.all().first?.targetHostID, hostID)
    }
}

final class AIProviderStoreTests: XCTestCase {
    func testCRUDRoundtripInMemory() throws {
        let container = try AIProviderStore.makeContainer(inMemory: true)
        let store = AIProviderStore(container: container)
        let provider = AIProviderRecord(
            name: "Claude",
            kindRaw: "anthropic",
            baseURL: "https://api.anthropic.com",
            model: "claude-sonnet-4-5",
            temperature: 0.3,
            apiKeyRef: "ref-openai",
            isDefault: true
        )
        try store.add(provider)

        let fetched = try store.record(id: provider.id)
        XCTAssertEqual(fetched?.name, "Claude")
        XCTAssertEqual(fetched?.kindRaw, "anthropic")
        XCTAssertEqual(fetched?.model, "claude-sonnet-4-5")
        XCTAssertEqual(fetched?.temperature, 0.3)
        XCTAssertEqual(fetched?.isDefault, true)

        provider.name = "GPT"
        try store.update(provider)
        XCTAssertEqual(try store.record(id: provider.id)?.name, "GPT")

        try store.delete(id: provider.id)
        XCTAssertNil(try store.record(id: provider.id))
    }

    func testSetDefaultOnlyMarksOneActive() throws {
        let container = try AIProviderStore.makeContainer(inMemory: true)
        let store = AIProviderStore(container: container)
        let a = AIProviderRecord(name: "A", kindRaw: "openAICompatible", baseURL: "https://a", model: "m", apiKeyRef: "ra")
        let b = AIProviderRecord(name: "B", kindRaw: "anthropic", baseURL: "https://b", model: "m", apiKeyRef: "rb")
        try store.add(a)
        try store.add(b)

        try store.setDefault(id: b.id)
        let all = try store.all()
        XCTAssertTrue(all.first(where: { $0.id == a.id })?.isDefault == false)
        XCTAssertTrue(all.first(where: { $0.id == b.id })?.isDefault == true)
    }

    func testAllSortedByCreation() throws {
        let container = try AIProviderStore.makeContainer(inMemory: true)
        let store = AIProviderStore(container: container)
        let older = AIProviderRecord(
            name: "old",
            kindRaw: "openAICompatible",
            baseURL: "https://o",
            model: "m",
            apiKeyRef: "ro",
            createdAt: Date(timeIntervalSinceNow: -100)
        )
        let newer = AIProviderRecord(
            name: "new",
            kindRaw: "gemini",
            baseURL: "https://n",
            model: "m",
            apiKeyRef: "rn"
        )
        try store.add(newer)
        try store.add(older)

        XCTAssertEqual(try store.all().map(\.name), ["old", "new"])
    }
}

final class ChatSessionStoreTests: XCTestCase {
    func testCRUDRoundtripInMemory() throws {
        let container = try ChatSessionStore.makeContainer(inMemory: true)
        let store = ChatSessionStore(container: container)
        let session = ChatSessionRecord(
            title: "Disk clean",
            providerID: UUID(),
            messagesJSON: Data(#"[{"role":"user","text":"hi"}]"#.utf8)
        )
        try store.add(session)

        let fetched = try store.record(id: session.id)
        XCTAssertEqual(fetched?.title, "Disk clean")
        XCTAssertEqual(fetched?.messagesJSON, Data(#"[{"role":"user","text":"hi"}]"#.utf8))

        session.title = "Renamed"
        session.messagesJSON = Data(#"[{"role":"user","text":"hey"}]"#.utf8)
        try store.update(session)
        XCTAssertEqual(try store.record(id: session.id)?.title, "Renamed")

        try store.delete(id: session.id)
        XCTAssertNil(try store.record(id: session.id))
    }

    func testAllSortedByUpdatedDescending() throws {
        let container = try ChatSessionStore.makeContainer(inMemory: true)
        let store = ChatSessionStore(container: container)
        let older = ChatSessionRecord(title: "old", updatedAt: Date(timeIntervalSinceNow: -100))
        let newer = ChatSessionRecord(title: "new", updatedAt: Date())
        try store.add(older)
        try store.add(newer)

        XCTAssertEqual(try store.all().map(\.title), ["new", "old"])
    }
}

final class AuditStoreTests: XCTestCase {
    func testAddAndAll() throws {
        let container = try AuditStore.makeContainer(inMemory: true)
        let store = AuditStore(container: container)
        let entry = AuditRecord(
            timestamp: Date(),
            toolName: "run_command",
            commandText: "rm -rf /tmp",
            resultSummary: "ok",
            approver: "user",
            strategyRaw: "alwaysAsk",
            outcomeRaw: "userApproved"
        )
        try store.add(entry)
        XCTAssertEqual(try store.all().count, 1)
        XCTAssertEqual(try store.all().first?.commandText, "rm -rf /tmp")
        XCTAssertEqual(try store.all().first?.outcomeRaw, "userApproved")
    }

    func testClearEmptiesAll() throws {
        let container = try AuditStore.makeContainer(inMemory: true)
        let store = AuditStore(container: container)
        try store.add(AuditRecord(
            timestamp: Date(),
            toolName: "read_file",
            commandText: "cat x",
            resultSummary: "-",
            approver: "auto",
            strategyRaw: "readOnly",
            outcomeRaw: "autoApproved"
        ))
        try store.clear()
        XCTAssertTrue(try store.all().isEmpty)
    }

    func testAllSortedByTimestampDescending() throws {
        let container = try AuditStore.makeContainer(inMemory: true)
        let store = AuditStore(container: container)
        let older = AuditRecord(
            timestamp: Date(timeIntervalSinceNow: -100),
            toolName: "t",
            commandText: "a",
            resultSummary: "-",
            approver: "u",
            strategyRaw: "alwaysAsk",
            outcomeRaw: "rejected"
        )
        let newer = AuditRecord(
            timestamp: Date(),
            toolName: "t",
            commandText: "b",
            resultSummary: "-",
            approver: "u",
            strategyRaw: "alwaysAsk",
            outcomeRaw: "rejected"
        )
        try store.add(older)
        try store.add(newer)

        XCTAssertEqual(try store.all().map(\.commandText), ["b", "a"])
    }
}

final class KeychainStoreTests: XCTestCase {
    private var store: KeychainStore!

    override func setUp() {
        super.setUp()
        store = KeychainStore(service: "com.glazeverre.tests.\(UUID().uuidString)")
    }

    func testSaveLoadRoundtrip() throws {
        try store.save("s3cret", account: "acct-1")
        XCTAssertEqual(try store.load(account: "acct-1"), "s3cret")
    }

    func testSaveOverwrites() throws {
        try store.save("first", account: "acct-1")
        try store.save("second", account: "acct-1")
        XCTAssertEqual(try store.load(account: "acct-1"), "second")
    }

    func testLoadMissingReturnsNil() throws {
        XCTAssertNil(try store.load(account: "never-saved"))
    }

    func testDeleteRemovesValue() throws {
        try store.save("bye", account: "acct-1")
        try store.delete(account: "acct-1")
        XCTAssertNil(try store.load(account: "acct-1"))
    }

    func testDeleteMissingIsNotAnError() throws {
        try store.delete(account: "never-saved")
    }
}
