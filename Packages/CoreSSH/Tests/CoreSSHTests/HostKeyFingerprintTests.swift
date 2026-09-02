import CoreSSH
import Crypto
import NIOSSH
import XCTest

/// Guard tests for the reflection-based fingerprint extractor (ADR-0008):
/// each fixture is a real key whose fingerprint was computed by `ssh-keygen -lf`.
/// If swift-nio-ssh's internal layout changes, these fail loudly in CI.
final class HostKeyFingerprintTests: XCTestCase {
    func testExtractsEd25519FingerprintOfRealTestServer() throws {
        let key = try NIOSSHPublicKey(
            openSSHPublicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdOFc0vV/LiSNEtJoDVtThtAaMk7b6SZ782Dj/Ho9qg root@ip-172-31-40-233"
        )

        let fingerprint = try HostKeyFingerprint.make(from: key)

        XCTAssertEqual(fingerprint.algorithm, "ssh-ed25519")
        XCTAssertEqual(fingerprint.sha256, "SHA256:aYH6L7FFK1mXfAbF15/6NFLEev9nIzJBFpMXJVyvgmM")
    }

    func testExtractsSecondEd25519Fingerprint() throws {
        let key = try NIOSSHPublicKey(
            openSSHPublicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDhBfXF9T6a0AurYNwimWIckgdjAeBnIFdM+rWcaWtWI glassterm-fixture-ed25519"
        )

        let fingerprint = try HostKeyFingerprint.make(from: key)

        XCTAssertEqual(fingerprint.sha256, "SHA256:tt45JPYHSqQ1kvgOPMu5tO7lQT+ccsZZS0Z7AitT7pM")
    }

    func testExtractsECDSAP256Fingerprint() throws {
        let key = try NIOSSHPublicKey(
            openSSHPublicKey: "ecdsa-sha2-nistp256 "
                + "AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBELiZJAMCEip"
                + "RVxsPUcv7KHuMudxDLfLuCDAuJuVAHEgB50uzOuBWJtsKWK4dyCHge3qRtEa/"
                + "N047Gl29t7cnls= glassterm-fixture-ecdsa"
        )

        let fingerprint = try HostKeyFingerprint.make(from: key)

        XCTAssertEqual(fingerprint.algorithm, "ecdsa-sha2-nistp256")
        XCTAssertEqual(fingerprint.sha256, "SHA256:RfGtOBv4AMcq4PlSs2KyfCGp4ghrTyhEgcGQ8+DBZ1c")
    }

    func testExtractsECDSAP384Fingerprint() throws {
        let key = try NIOSSHPublicKey(
            openSSHPublicKey: "ecdsa-sha2-nistp384 "
                + "AAAAE2VjZHNhLXNoYTItbmlzdHAzODQAAAAIbmlzdHAzODQAAABhBCf9r0YfW7ONTJsz"
                + "FC118jY0aDrz2pr4/t0xIuXotxU3WYJfSf8dJo5j6R0riyeGKtZ8NG2XEJ1TPjmPud8ps"
                + "r3JZD65WvKpg9JaBr8k93RXlVtRuawgqnceMQ4nCtk8sQ== glassterm-fixture-ecdsa-p384"
        )

        let fingerprint = try HostKeyFingerprint.make(from: key)

        XCTAssertEqual(fingerprint.algorithm, "ecdsa-sha2-nistp384")
        XCTAssertEqual(fingerprint.sha256, "SHA256:wDy/nO4CXdoWR4Oz4ZWD4m6oeYfVeu0png57VqeJVVs")
    }

    func testExtractsECDSAP521Fingerprint() throws {
        let key = try NIOSSHPublicKey(
            openSSHPublicKey: "ecdsa-sha2-nistp521 "
                + "AAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlzdHA1MjEAAACFBAHmbR5/WbrQFrUR"
                + "OZHKKBtLArum/+1bYo5gs6xjaU9cjE5Yzr4FG421tOPlJNr1oenLi0CoYF6MtpQwBm9uNy"
                + "Rp4QFSpNCXgTIpYTthlTF8BSza5arD6myf4YxSBCBH5DJV50hL1iAca02YQuuHBasubo5b"
                + "akjTv5C+UKstYBcIQFxLhw== glassterm-fixture-ecdsa-p521"
        )

        let fingerprint = try HostKeyFingerprint.make(from: key)

        XCTAssertEqual(fingerprint.algorithm, "ecdsa-sha2-nistp521")
        XCTAssertEqual(fingerprint.sha256, "SHA256:1UeVJ6CVbqSaeXpJr39D+6SCSkJAPyew+t8Wjmcpyfw")
    }

    func testDifferentKeysProduceDifferentFingerprints() throws {
        let first = try NIOSSHPublicKey(
            openSSHPublicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdOFc0vV/LiSNEtJoDVtThtAaMk7b6SZ782Dj/Ho9qg root@ip-172-31-40-233"
        )
        let second = try NIOSSHPublicKey(
            openSSHPublicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDhBfXF9T6a0AurYNwimWIckgdjAeBnIFdM+rWcaWtWI glassterm-fixture-ed25519"
        )

        XCTAssertNotEqual(try HostKeyFingerprint.make(from: first), try HostKeyFingerprint.make(from: second))
    }

    func testFingerprintIsCodableRoundtrip() throws {
        let key = try NIOSSHPublicKey(
            openSSHPublicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDhBfXF9T6a0AurYNwimWIckgdjAeBnIFdM+rWcaWtWI glassterm-fixture-ed25519"
        )
        let fingerprint = try HostKeyFingerprint.make(from: key)

        let data = try JSONEncoder().encode(fingerprint)
        let decoded = try JSONDecoder().decode(HostKeyFingerprint.self, from: data)

        XCTAssertEqual(decoded, fingerprint)
    }
}
