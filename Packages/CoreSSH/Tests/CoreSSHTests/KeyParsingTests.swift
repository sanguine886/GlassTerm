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

    private let rsaPKCS1PEM = """
    -----BEGIN RSA PRIVATE KEY-----
    MIIEpAIBAAKCAQEAqzFRjsQGHZ33MLIbbVHNKx/ppZDlsuOg3brtQsOuiRc+sFV+
    tvf+z4cmb9LfdbKWnbDqmV71TquRrb3VQN5GtA7VMrQ2guqnZ2s7LheEIBCh0UnI
    J87uiqawAbgV+Ob5pbtFSPzrmjit2CLaMghD5KrsT1Pyg+r433nFFqid/YQsmFWV
    EciCDdWSokjy8tZkUWzb2cHAxwowdDOxeoF+sbF8X+u4FIkKIwT6IoQcaI1RH+f+
    dS0Xtk3ZPjiNtGGAWoMmXH3a3qCf4si+Oh5HnuMod60SyNdMvNuVp+khHyTE/aat
    7qbfGQonWvRx+h0Z9uIaaYsKS4Ktaqjdimx7fQIDAQABAoIBABd4tBdwbew6n80n
    5lXHPOuYPQcrxiqQRhqQif446SG3s6smlbCNcPzQKWd0kJnJChiFzKyJlfWa1Wbu
    W6JAt43xaK7CgaTSenBWBe+sXrusvBr/VDeNCiytbP1XWX/eX0UnV3kJ4F2tPryf
    Dq6EbpaYDr1To7ENkuDFB84zATJkZpN8M+wOpz83tCtcsrp5qiMkIFhX0J14iLe3
    HkVptTOkhvCKMBvtufNtD2fUN2AOXzhYlQxGoG1aA3ESnFpYaBObYJmKdvYc/JYE
    QlKv7R0jFa9epAjLsAzlw2sM5SYlf9ilf6kpfk7lvzCHQTkKrypp15FBUaSftrbB
    zWi62BECgYEA6ysd1z8EzulnUuPYz2H32Z8yaT70L0HGy4vkVIPRlENSQuesdA17
    zHVOmj4+fRN12xbmSuruwbsqJrcgExxZOm7eXVW1QiGUAk93pYM8CjXIWlkRQ3jw
    /2KrsdtAUuqh1R+V+y2fQqxRLTuWjqvdu0JsBuG6XuaTnMpOjPNMoMUCgYEAultu
    i5oGFn3n7zpyMAorhP1K+POo6rOR78pxS6ekLKlE7PFXenDXT+h1jLInarP1G6v9
    xc5uH2TltVE7rkp1v99+bm31o8peuBJGMHZudfZMFZMcUXjZITfj1xHPj5it5o+q
    Ce4N6ILi8Nr2iDMHFNOhI9amsR9ZqovagJwhq1kCgYBhQhO1UXrLl/wDa/fezMWU
    WyKeJEsYwDtXMyPbUCj9CFqdEPNhi7IHfPxlDhkJ4WJ8mZvkoATeWmm0WUgKn07H
    u9J7B1dPYlO0IOl6qivKjTOvKebZ4MrK1CPuCp8vq5oCam2808Fp8Zog+uPpXWr2
    ZyIGNpS9at7hmUmjQXwPgQKBgQCUP34OUiX7qIdkeQMzkjOSpQkKSJOcueMjddFx
    FNh2quVo9IjZn4C5UbyJg4P1z1jyfXzw6coS8WoHNqsaeKN5Uuq6IIFjne6B0g/C
    J8Sx1JAsLY4+hbt9QH/grIuIuTXGD41+PsETsWOlpRqvuKAugjhTUUPj7YOgN4dH
    /myOaQKBgQCMZJg7jixI+JBjVuC1F9LxdliKyF9wd8aaQJjyVZPsWyhieBQTu2jv
    CYEzVaEjKPC8LEJXaL/PmKmOjsJzht33M+s4d+1/0tiifutweqYrR97DQr01LWd/
    NZBUwhh9ajX2nzj5Kx43MRHaWYob9ez+CNhBeU4uefgnj3FvOa3HAg==
    -----END RSA PRIVATE KEY-----
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

    func testParsesRSAPKCS1Key() throws {
        let method = try CitadelTransport.authenticationMethod(
            for: SSHHostConfig(host: "h", username: "u", auth: .privateKey(pem: rsaPKCS1PEM, passphrase: nil))
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
