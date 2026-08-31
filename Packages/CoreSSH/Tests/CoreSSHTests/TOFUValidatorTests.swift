import CoreSSH
import NIOCore
import NIOSSH
import XCTest

/// Direct tests of the TOFU validator: unknown key declines, pinned key
/// accepts, changed key declines and is reported.
final class TOFUValidatorTests: XCTestCase {
    private let serverKey = try! NIOSSHPublicKey(
        openSSHPublicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdOFc0vV/LiSNEtJoDVtThtAaMk7b6SZ782Dj/Ho9qg root@ip-172-31-40-233"
    )
    private let serverFingerprint = HostKeyFingerprint(
        algorithm: "ssh-ed25519", sha256: "SHA256:aYH6L7FFK1mXfAbF15/6NFLEev9nIzJBFpMXJVyvgmM"
    )

    func testUnknownHostDeclinesAndRecordsFingerprint() throws {
        let store = KnownHostsStore(storeURL: nil)
        let validator = TOFUHostKeyValidator(knownHosts: store, hostIdentifier: "h:22")

        let outcome = try runValidation(validator)

        XCTAssertFalse(outcome.succeeded)
        XCTAssertEqual(validator.presentedFingerprint(), serverFingerprint)
    }

    func testPinnedHostAccepts() throws {
        let store = KnownHostsStore(storeURL: nil)
        store.trust(hostIdentifier: "h:22", fingerprint: serverFingerprint)
        let validator = TOFUHostKeyValidator(knownHosts: store, hostIdentifier: "h:22")

        let outcome = try runValidation(validator)

        XCTAssertTrue(outcome.succeeded)
    }

    func testChangedHostDeclines() throws {
        let store = KnownHostsStore(storeURL: nil)
        let impostor = HostKeyFingerprint(algorithm: "ssh-ed25519", sha256: "SHA256:tt45JPYHSqQ1kvgOPMu5tO7lQT+ccsZZS0Z7AitT7pM")
        store.trust(hostIdentifier: "h:22", fingerprint: impostor)
        let validator = TOFUHostKeyValidator(knownHosts: store, hostIdentifier: "h:22")

        let outcome = try runValidation(validator)

        XCTAssertFalse(outcome.succeeded)
        XCTAssertEqual(validator.presentedFingerprint(), serverFingerprint)
    }

    // MARK: - Helpers

    private func runValidation(_ validator: TOFUHostKeyValidator) throws -> (succeeded: Bool, error: Error?) {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let promise = group.next().makePromise(of: Void.self)
        validator.validateHostKey(hostKey: serverKey, validationCompletePromise: promise)

        var outcome: Result<Void, Error>?
        let expectation = expectation(description: "validation completes")
        promise.futureResult.whenComplete { value in
            outcome = value
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)

        switch outcome {
        case .success:
            return (true, nil)
        case let .failure(error):
            return (false, error)
        case nil:
            return (false, nil)
        }
    }
}
