import Persistence
import XCTest

/// Secrets must live only in the Keychain (spec §6.3.1). These tests pin the
/// round-trip behavior and the accessibility attribute.
final class KeychainStoreTests: XCTestCase {
    private var store: KeychainStore!

    override func setUp() {
        super.setUp()
        store = KeychainStore(service: "com.glazeterm.tests.\(UUID().uuidString)")
    }

    func testSaveLoadRoundtrip() throws {
        try store.save("s3cret-值", account: "acct-1")
        XCTAssertEqual(try store.load(account: "acct-1"), "s3cret-值")
    }

    func testSaveOverwritesPreviousValue() throws {
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

    func testAccessibleWhenUnlockedThisDeviceOnly() throws {
        try store.save("check", account: "acct-attr")
        defer { try? store.delete(account: "acct-attr") }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: store.serviceForTesting,
            kSecAttrAccount as String: "acct-attr",
            kSecReturnAttributes as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        XCTAssertEqual(status, errSecSuccess)
        let attributes = try XCTUnwrap(result as? [String: Any])
        let accessible = attributes[kSecAttrAccessible as String] as? String
        XCTAssertEqual(accessible, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
    }
}

extension KeychainStore {
    var serviceForTesting: String {
        mirrorService()
    }

    private func mirrorService() -> String {
        let mirror = Mirror(reflecting: self)
        guard let child = mirror.children.first(where: { $0.label == "service" }),
              let service = child.value as? String
        else {
            return ""
        }
        return service
    }
}
