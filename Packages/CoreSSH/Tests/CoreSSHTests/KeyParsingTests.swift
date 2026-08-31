import Citadel
@testable import CoreSSH
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

    private let rsaOpenSSHPEM = """
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAABFwAAAAdzc2gtcn
    NhAAAAAwEAAQAAAQEAyZs6rLFwgnsVCTOzjIGCM1Kl9l+U9EBAC6f+7O+3Uk1iAno12nt1
    5bum0yFL/t4Sib+tRh49siyW0UG42BZEctu0hjcC7wp64QzEVKw4dTnhbbFJssU4xGe35Y
    Uhi1LQOgvtI3073O/oF2AG66nV9hIW0dOf6lLd37wY8sB3AvtJJHi7wfMU2t85SkcjIpOT
    oYQ3kq4Vzt6Mvq4RP/zR7P+ZMSoox8eQt8EtWSywqHodU5b1zWudhZDkiRlZf5UfhUwMW/
    A8H7cppdeNcS1XiMhRxKTJ19ue77uSm+Yo2NTEv2F/vxufgX4eZHbJ4lUVafNSywtOA5Zk
    JqdYe2wzVwAAA8jcE4di3BOHYgAAAAdzc2gtcnNhAAABAQDJmzqssXCCexUJM7OMgYIzUq
    X2X5T0QEALp/7s77dSTWICejXae3Xlu6bTIUv+3hKJv61GHj2yLJbRQbjYFkRy27SGNwLv
    CnrhDMRUrDh1OeFtsUmyxTjEZ7flhSGLUtA6C+0jfTvc7+gXYAbrqdX2EhbR05/qUt3fvB
    jywHcC+0kkeLvB8xTa3zlKRyMik5OhhDeSrhXO3oy+rhE//NHs/5kxKijHx5C3wS1ZLLCo
    eh1TlvXNa52FkOSJGVl/lR+FTAxb8Dwftyml141xLVeIyFHEpMnX257vu5Kb5ijY1MS/YX
    +/G5+Bfh5kdsniVRVp81LLC04DlmQmp1h7bDNXAAAAAwEAAQAAAQAe62w/HRg/eBIHWcMR
    QFw6ySkD6q/acATX5M7aVtTQ+LuYhqwTaI5HNWrwrtwhaBIEHKi9/BhZPFvFwc8lcPDULs
    b2iKGuDfeU5BOJAEAea8nw5q5XY8ZWNP6wDaV8i9m8n/n20JepmwUHmhDQUY6rkSWnzk2U
    hLCw8NULXKJEC1vNs28XIYWGYB9NfJ1qzUdEWkhlo620Gmp1gKu5nukt56DWuHotNzEz1+
    owQFRn39pUrQ9jxJmE25NAe/pmmYQXm0HjNDA9yU5AddBU/6202q1DcrqHAz7+I8t6wX6R
    Qr2CLkSqg9xumrvw6ry+6IjsYotcwaUGXiQHFgus8Qd9AAAAgQDBCz1lhm4eIY/CEYHNtl
    fe7fwOshpci5VDyusLGkSqKHol6FYIG5Y2ZWEuS4QJ4p0d1k88gnQnpqeIisACZ6yu4chH
    ssWcb2Pq+BbXlwJklYqlEAKAZirErxltox5jCkPYDDnmYuPhOuyEedC8+U+kBAcpR1brie
    nu4N4LY5epGQAAAIEA9VrhvX/8CCcw1hD8n6psSc8dQmivKdT+yPKI7TU4oCuEnRRtweI7
    CVyPLrqp3gEcwseaIVLPXQ5M/FR7P7z3e6jr/AyK4gj6Hc0hUQ3pqA/4Dm+9EC9eWeWQ9L
    1e4RLWoo7ra07PIq5TislbKCx2ardR4LABv7lp5gu9LMA+4f0AAACBANJacDZh+SwgJx9A
    POcHOF0xRoUZdJ8FT6j4sUcUtow2OKn/Ywb25sC/O6NodJXnRAgXnXygK3+smcIgeUQSZb
    3yeVnb7EU76h0ovXup2Eh2lWqkE+/dPijw6hlT9y6BVv+31YOu2gP1mfEM4F9Q1TnfleBO
    JXR2klx6uKfE0hDjAAAAC2ZpeHR1cmUtcnNhAQIDBAUGBw==
    -----END OPENSSH PRIVATE KEY-----
    """

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

    func testParsesRSAOpenSSHKey() throws {
        let method = try CitadelTransport.authenticationMethod(
            for: SSHHostConfig(host: "h", username: "u", auth: .privateKey(pem: rsaOpenSSHPEM, passphrase: nil))
        )
        XCTAssertNotNil(method)
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
