import Citadel
import CoreSSH
import Crypto
import XCTest

/// OpenSSH private-key parsing for key auth (ED25519 / RSA, with passphrase).
final class KeyParsingTests: XCTestCase {
    private let ed25519PEM = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
    QyNTUxOQAAACA4QX1xfU+mtALq2DcIpliHJIHYwHgZyBXTPq1nGlrViAAAAKAjffisI334
    rAAAAAtzc2gtZWQyNTUxOQAAACA4QX1xfU+mtALq2DcIpliHJIHYwHgZyBXTPq1nGlrViA
    AAAEBQKnOcQymNsKRu4rRD9M1Zn/2hUnADNe4Fh42qsoVlvThBfXF9T6a0AurYNwimWIck
    gdjAeBnIFdM+rWcaWtWIAAAAGWdsYXNzdGVybS1maXh0dXJlLWVkMjU1MTkBAgME
    -----END OPENSSH PRIVATE KEY-----
    """

    private let ed25519ProtectedPEM = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAACmFlczI1Ni1jdHIAAAAGYmNyeXB0AAAAGAAAABBlqIME0u
    hs6yzcpFK0oenOAAAAGAAAAAEAAAAzAAAAC3NzaC1lZDI1NTE5AAAAID4XelceSQswVraD
    L+TmIpPabr7s+1jcVCzEql9664rRAAAAkNyWIfACFm6DzzxC7qD0iU3RpOmytZVnu9uCiQ
    eywu2SIBs8cX6j7pX5AJhMfXfzHzrBzjC1lIrkq82MiJS4QKjP9PHYZGpWKaclDfQNOx9x
    zZqWWq06UB0QS2b0213lw/6ZThIMGIakrZmOWvrkayUCPdjEghzFTpdTDArPOmKz8IeZwP
    Q8eFR4Fkq3pRNxTw==
    -----END OPENSSH PRIVATE KEY-----
    """

    private let config = SSHHostConfig(host: "h", port: 22, username: "glassterm", auth: .password("x"))

    func testParsesUnprotectedEd25519Key() throws {
        let method = try CitadelTransport.authenticationMethod(
            for: SSHHostConfig(host: "h", username: "u", auth: .privateKey(pem: ed25519PEM, passphrase: nil))
        )
        XCTAssertNotNil(method)
    }

    func testParsesProtectedEd25519KeyWithPassphrase() throws {
        let method = try CitadelTransport.authenticationMethod(
            for: SSHHostConfig(host: "h", username: "u", auth: .privateKey(pem: ed25519ProtectedPEM, passphrase: "secret123"))
        )
        XCTAssertNotNil(method)
    }

    func testProtectedKeyWithoutPassphraseFailsWithKeyParseError() {
        XCTAssertThrowsError(
            try CitadelTransport.authenticationMethod(
                for: SSHHostConfig(host: "h", username: "u", auth: .privateKey(pem: ed25519ProtectedPEM, passphrase: nil))
            )
        ) { error in
            guard case SSHError.keyParseFailed = error else {
                return XCTFail("Expected keyParseFailed, got \(error)")
            }
        }
    }

    func testPasswordAuthMethodBuilt() throws {
        let method = try CitadelTransport.authenticationMethod(
            for: SSHHostConfig(host: "h", username: "u", auth: .password("pw"))
        )
        XCTAssertNotNil(method)
    }

    func testGarbageKeyFailsCleanly() {
        XCTAssertThrowsError(
            try CitadelTransport.authenticationMethod(
                for: SSHHostConfig(host: "h", username: "u", auth: .privateKey(pem: "garbage", passphrase: nil))
            )
        ) { error in
            guard case SSHError.keyParseFailed = error else {
                return XCTFail("Expected keyParseFailed, got \(error)")
            }
        }
    }

    func testHostIdentifierFormat() {
        XCTAssertEqual(config.hostIdentifier, "h:22")
        XCTAssertEqual(
            SSHHostConfig(host: "h", port: 2222, username: "u", auth: .password("x")).hostIdentifier,
            "h:2222"
        )
    }

    func testKeepaliveIntervalHasFloor() {
        let tooLow = SSHHostConfig(host: "h", username: "u", auth: .password("x"), keepaliveIntervalSeconds: 1)
        XCTAssertEqual(tooLow.keepaliveIntervalSeconds, 5)
    }
}
