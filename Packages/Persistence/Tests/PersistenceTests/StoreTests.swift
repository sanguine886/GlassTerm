import Foundation
import Persistence
import XCTest

/// Persistence is a standalone package that also lives inside the app, so its
/// coverage is measured here via `swift test --package-path Packages/Persistence`
/// (the app's xccov report omits package sources). These tests mirror the
/// GlassTermTests assertions and add snippet coverage (ADR-0002/ADR-0005).
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

final class KeychainStoreTests: XCTestCase {
    private var store: KeychainStore!

    override func setUp() {
        super.setUp()
        store = KeychainStore(service: "com.glazeterm.tests.\(UUID().uuidString)")
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
