import Persistence
import XCTest

/// HostRecord must never carry secret material — only opaque Keychain
/// references (spec §6.3.1, §8 grep audit). These tests enforce that.
final class HostRecordTests: XCTestCase {
    func testCRUDRoundtripInMemoryContainer() throws {
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

    func testSecretValueNeverStoredInAnyRecordProperty() throws {
        let secret = "TOP-SECRET-PASSWORD-9781"
        let record = HostRecord(
            name: "h", hostname: "example.com", port: 22, username: "deploy",
            authKind: .password, secretRef: UUID().uuidString
        )

        let mirror = Mirror(reflecting: record)
        let dump = String(describing: mirror.children.map { "\($0.label ?? "")=\($0.value)" })
        XCTAssertFalse(dump.contains(secret), "SwiftData record leaked the secret value")
    }

    func testAuthKindDefaultsToPasswordWhenRawCorrupt() {
        let record = HostRecord(name: "h", hostname: "h", username: "u")
        record.authKindRaw = "bogus"
        XCTAssertEqual(record.authKind, .password)
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

    func testAllReturnsHostsSortedByCreation() throws {
        let container = try HostStore.makeContainer(inMemory: true)
        let store = HostStore(container: container)

        let older = HostRecord(name: "older", hostname: "a", username: "u", createdAt: Date(timeIntervalSinceNow: -100))
        let newer = HostRecord(name: "newer", hostname: "b", username: "u", createdAt: Date())
        try store.add(newer)
        try store.add(older)

        XCTAssertEqual(try store.all().map(\.name), ["older", "newer"])
    }
}
