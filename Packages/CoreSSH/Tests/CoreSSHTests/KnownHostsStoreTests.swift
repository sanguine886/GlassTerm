import CoreSSH
import XCTest

final class KnownHostsStoreTests: XCTestCase {
    private var storeURL: URL!

    override func setUpWithError() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("knownhosts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appendingPathComponent("known-hosts.json")
    }

    override func tearDownWithError() {
        try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent())
    }

    private let ed25519 = HostKeyFingerprint(algorithm: "ssh-ed25519", sha256: "SHA256:aYH6")
    private let other = HostKeyFingerprint(algorithm: "ssh-ed25519", sha256: "SHA256:tt45")

    func testUnpinnedHostVerifiesAsNew() {
        let store = KnownHostsStore(storeURL: storeURL)
        XCTAssertEqual(store.verify(hostIdentifier: "h:22", fingerprint: ed25519), .newHost)
    }

    func testTrustThenVerifyTrusted() {
        let store = KnownHostsStore(storeURL: storeURL)
        store.trust(hostIdentifier: "h:22", fingerprint: ed25519)
        XCTAssertEqual(store.verify(hostIdentifier: "h:22", fingerprint: ed25519), .trusted)
    }

    func testChangedKeyReportsPinnedFingerprint() {
        let store = KnownHostsStore(storeURL: storeURL)
        store.trust(hostIdentifier: "h:22", fingerprint: ed25519)
        XCTAssertEqual(
            store.verify(hostIdentifier: "h:22", fingerprint: other),
            .changed(pinned: ed25519)
        )
    }

    func testRemovePinReturnsToNewHost() {
        let store = KnownHostsStore(storeURL: storeURL)
        store.trust(hostIdentifier: "h:22", fingerprint: ed25519)
        store.removePin(hostIdentifier: "h:22")
        XCTAssertEqual(store.verify(hostIdentifier: "h:22", fingerprint: ed25519), .newHost)
    }

    func testPinsPersistAcrossInstances() {
        KnownHostsStore(storeURL: storeURL).trust(hostIdentifier: "h:22", fingerprint: ed25519)

        let reloaded = KnownHostsStore(storeURL: storeURL)
        XCTAssertEqual(reloaded.verify(hostIdentifier: "h:22", fingerprint: ed25519), .trusted)
        XCTAssertEqual(reloaded.pinnedFingerprint(hostIdentifier: "h:22"), ed25519)
    }

    func testCorruptFileStartsEmptyInsteadOfCrashing() throws {
        try Data("not json at all".utf8).write(to: storeURL)
        let store = KnownHostsStore(storeURL: storeURL)
        XCTAssertEqual(store.verify(hostIdentifier: "h:22", fingerprint: ed25519), .newHost)
        // And the store heals on next trust.
        store.trust(hostIdentifier: "h:22", fingerprint: ed25519)
        let healed = KnownHostsStore(storeURL: storeURL)
        XCTAssertEqual(healed.verify(hostIdentifier: "h:22", fingerprint: ed25519), .trusted)
    }

    func testHostsAreIsolated() {
        let store = KnownHostsStore(storeURL: storeURL)
        store.trust(hostIdentifier: "a:22", fingerprint: ed25519)
        XCTAssertEqual(store.verify(hostIdentifier: "b:22", fingerprint: ed25519), .newHost)
    }
}
