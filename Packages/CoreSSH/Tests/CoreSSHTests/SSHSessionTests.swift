@testable import CoreSSH
import NIO
import NIOCore
import NIOSSH
import XCTest

/// A transport whose handshake runs the REAL TOFU validator against a fixture
/// host key, then either accepts (after `failFirst` simulated network failures)
/// or behaves like a live connection. Shared attempt counter survives
/// reconnect-driven factory calls.
final class FakeTransport: SSHTransport, @unchecked Sendable {
    let onDropBox = CallbackBoxForTests()
    private let state: FakeState
    private var opened = false

    init(state: FakeState) {
        self.state = state
    }

    var onDrop: @Sendable () -> Void {
        get { onDropBox.get() ?? {} }
        set { onDropBox.set(newValue) }
    }

    var isConnected: Bool {
        opened
    }

    func open(config _: SSHHostConfig, validator: TOFUHostKeyValidator) async throws {
        let index = state.nextAttempt()
        if index <= state.failFirstAttempts {
            throw SSHError.connectionFailed("simulated network failure #\(index)")
        }

        // Simulate the SSH handshake's host-key step with the real validator.
        let key = try NIOSSHPublicKey(openSSHPublicKey: FakeState.fixtureOpenSSHPublicKey)
        let promise = state.eventLoop.makePromise(of: Void.self)
        validator.validateHostKey(hostKey: key, validationCompletePromise: promise)
        try await promise.futureResult.get()

        opened = true
    }

    func run(_ command: String) async throws -> String {
        guard opened else { throw SSHError.sessionNotConnected }
        // A 1ms pause keeps CommandResult.durationSeconds > 0 (two Date()
        // reads in the same tick would otherwise round to 0.0).
        try await Task.sleep(for: .milliseconds(1))
        return "ok:\(command)"
    }

    func requestShell(cols _: Int, rows _: Int) async throws -> ShellStreams {
        throw SSHError.sessionNotConnected
    }

    func close() async {
        opened = false
    }

    func simulateDrop() {
        onDrop()
    }
}

final class CallbackBoxForTests: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable () -> Void)?

    func set(_ callback: @escaping @Sendable () -> Void) {
        lock.lock()
        self.callback = callback
        lock.unlock()
    }

    func get() -> (@Sendable () -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        return callback
    }
}

/// Shared mutable state for the fake fleet (thread-safe).
final class FakeState: @unchecked Sendable {
    static let fixtureOpenSSHPublicKey =
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdOFc0vV/LiSNEtJoDVtThtAaMk7b6SZ782Dj/Ho9qg root@ip-172-31-40-233"
    static let fixtureFingerprint = HostKeyFingerprint(
        algorithm: "ssh-ed25519", sha256: "SHA256:aYH6L7FFK1mXfAbF15/6NFLEev9nIzJBFpMXJVyvgmM"
    )

    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let eventLoop: EventLoop
    let lock = NSLock()
    var attempts = 0
    var failFirstAttempts: Int

    init(failFirstAttempts: Int = 0) {
        self.failFirstAttempts = failFirstAttempts
        eventLoop = group.next()
    }

    func nextAttempt() -> Int {
        lock.lock()
        defer { lock.unlock() }
        attempts += 1
        return attempts
    }
}

private struct FakeFactory: SSHTransportMaking {
    let state: FakeState

    func makeTransport() -> any SSHTransport {
        FakeTransport(state: state)
    }
}

final class SSHSessionTests: XCTestCase {
    private var store: KnownHostsStore!
    private var state: FakeState!
    private var fastPolicy = ReconnectPolicy.standard

    override func setUp() {
        super.setUp()
        store = KnownHostsStore(storeURL: nil)
        state = FakeState()
        fastPolicy = ReconnectPolicy(maxAttempts: 3, baseDelaySeconds: 0.01, maxDelaySeconds: 0.02)
        store.trust(hostIdentifier: "host:22", fingerprint: FakeState.fixtureFingerprint)
    }

    private func makeSession(failFirstAttempts: Int = 0) -> SSHSession {
        state.failFirstAttempts = failFirstAttempts
        return SSHSession(transportMaker: FakeFactory(state: state), policy: fastPolicy)
    }

    private func makeConfig() -> SSHHostConfig {
        SSHHostConfig(host: "host", port: 22, username: "glassterm", auth: .password("secret"), keepaliveIntervalSeconds: 3600)
    }

    func testConnectRunAndClose() async throws {
        let session = makeSession()

        try await session.connect(config: makeConfig(), knownHosts: store)
        let connectedState = await session.state
        XCTAssertEqual(connectedState, .connected)

        let result = try await session.run("uname -a")
        XCTAssertEqual(result.output, "ok:uname -a")
        XCTAssertGreaterThan(result.durationSeconds, 0)

        await session.disconnect()
        let finalState = await session.state
        XCTAssertEqual(finalState, .closed)
    }

    func testUnpinnedHostSurfacesTOFUError() async throws {
        let unpinnedStore = KnownHostsStore(storeURL: nil)
        let session = makeSession()

        do {
            try await session.connect(config: makeConfig(), knownHosts: unpinnedStore)
            XCTFail("Expected hostKeyUnknown")
        } catch let error as SSHError {
            guard case let .hostKeyUnknown(fingerprint) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(fingerprint, FakeState.fixtureFingerprint)
        }
        // The connection attempt failed, so the session reports failure state.
        let failedState = await session.state
        XCTAssertEqual(failedState, .failed(.hostKeyUnknown(fingerprint: FakeState.fixtureFingerprint)))
    }

    func testChangedHostKeyIsBlocked() async throws {
        let impostor = HostKeyFingerprint(algorithm: "ssh-ed25519", sha256: "SHA256:tt45JPYHSqQ1kvgOPMu5tO7lQT+ccsZZS0Z7AitT7pM")
        store.trust(hostIdentifier: "host:22", fingerprint: impostor)
        let session = makeSession()

        do {
            try await session.connect(config: makeConfig(), knownHosts: store)
            XCTFail("Expected hostKeyChanged")
        } catch let error as SSHError {
            guard case let .hostKeyChanged(pinned, presented) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(pinned, impostor)
            XCTAssertEqual(presented, FakeState.fixtureFingerprint)
        }
    }

    func testReconnectAfterUnexpectedDrop() async throws {
        let session = makeSession()
        try await session.connect(config: makeConfig(), knownHosts: store)

        // Simulate a network drop; the current transport's onDrop fires. The
        // drop handler runs on the session actor, so wait for the reconnect
        // attempt counter to advance instead of the state (which may briefly
        // still read `.connected` before the handler is scheduled).
        let live = await session.activeTransport
        let fake = try XCTUnwrap(live as? FakeTransport)
        fake.simulateDrop()

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if state.attempts >= 2, await session.state == .connected {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let postReconnect = await session.state
        XCTAssertEqual(postReconnect, .connected)
        XCTAssertGreaterThanOrEqual(state.attempts, 2, "Expected at least one reconnect attempt")
    }

    func testReconnectGivesUpAfterMaxAttempts() async throws {
        let session = makeSession()
        try await session.connect(config: makeConfig(), knownHosts: store)
        // Arm "every open fails" only after the initial connect succeeded, so
        // the reconnect loop is the part that exhausts its attempts.
        state.failFirstAttempts = Int.max

        let live = await session.activeTransport
        let fake = try XCTUnwrap(live as? FakeTransport)
        fake.simulateDrop()

        let deadline = Date().addingTimeInterval(5)
        var failedSeen = false
        while Date() < deadline {
            if case .failed(.connectionLost) = await session.state {
                failedSeen = true
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(failedSeen, "Expected connectionLost failure after exhausting retries")
        XCTAssertGreaterThanOrEqual(state.attempts, 1 + fastPolicy.maxAttempts)
    }

    func testRunWithoutConnectionThrows() async throws {
        let session = makeSession()
        do {
            _ = try await session.run("ls")
            XCTFail("Expected sessionNotConnected")
        } catch let error as SSHError {
            XCTAssertEqual(error, .sessionNotConnected)
        }
    }

    func testRequestShellWithoutConnectionThrows() async throws {
        let session = makeSession()
        do {
            _ = try await session.requestShell(cols: 80, rows: 24)
            XCTFail("Expected sessionNotConnected")
        } catch let error as SSHError {
            XCTAssertEqual(error, .sessionNotConnected)
        }
    }

    func testConnectTwiceIsNoOp() async throws {
        let session = makeSession()
        try await session.connect(config: makeConfig(), knownHosts: store)
        let attemptsAfterFirst = state.attempts
        try await session.connect(config: makeConfig(), knownHosts: store)
        XCTAssertEqual(state.attempts, attemptsAfterFirst, "Second connect must not open another transport")
    }

    func testStateStreamEmitsInitialAndConnected() async throws {
        let session = makeSession()
        let stream = await session.stateStream()
        var iterator = stream.makeAsyncIterator()

        let initial = await iterator.next()
        XCTAssertEqual(initial, .idle)

        try await session.connect(config: makeConfig(), knownHosts: store)
        let deadline = Date().addingTimeInterval(2)
        var seenConnected = false
        while let emitted = await iterator.next(), Date() < deadline {
            if emitted == .connected {
                seenConnected = true
                break
            }
        }
        XCTAssertTrue(seenConnected, "State stream never reported .connected")
    }

    // MARK: - mapHostKeyError translation (UI-facing TOFU errors)

    private func runValidation(on validator: TOFUHostKeyValidator) throws {
        let key = try NIOSSHPublicKey(openSSHPublicKey: FakeState.fixtureOpenSSHPublicKey)
        let promise = state.eventLoop.makePromise(of: Void.self)
        validator.validateHostKey(hostKey: key, validationCompletePromise: promise)
    }

    func testMapHostKeyErrorNewHost() throws {
        let unpinned = KnownHostsStore(storeURL: nil)
        let validator = TOFUHostKeyValidator(knownHosts: unpinned, hostIdentifier: "host:22")
        try runValidation(on: validator)

        let mapped = SSHSession.mapHostKeyError(
            SSHError.hostKeyVerificationDeclined,
            validator: validator, knownHosts: unpinned, config: makeConfig()
        )
        guard case let .hostKeyUnknown(fingerprint) = mapped else {
            return XCTFail("Expected hostKeyUnknown, got \(mapped)")
        }
        XCTAssertEqual(fingerprint, FakeState.fixtureFingerprint)
    }

    func testMapHostKeyErrorChanged() throws {
        let impostor = HostKeyFingerprint(algorithm: "ssh-ed25519", sha256: "SHA256:tt45JPYHSqQ1kvgOPMu5tO7lQT+ccsZZS0Z7AitT7pM")
        store.trust(hostIdentifier: "host:22", fingerprint: impostor)
        let validator = TOFUHostKeyValidator(knownHosts: store, hostIdentifier: "host:22")
        try runValidation(on: validator)

        let mapped = SSHSession.mapHostKeyError(
            SSHError.hostKeyVerificationDeclined,
            validator: validator, knownHosts: store, config: makeConfig()
        )
        guard case let .hostKeyChanged(pinned, presented) = mapped else {
            return XCTFail("Expected hostKeyChanged, got \(mapped)")
        }
        XCTAssertEqual(pinned, impostor)
        XCTAssertEqual(presented, FakeState.fixtureFingerprint)
    }

    func testMapHostKeyErrorTrustedHostBecomesConnectionFailure() throws {
        let validator = TOFUHostKeyValidator(knownHosts: store, hostIdentifier: "host:22")
        try runValidation(on: validator)

        let mapped = SSHSession.mapHostKeyError(
            SSHError.hostKeyVerificationDeclined,
            validator: validator, knownHosts: store, config: makeConfig()
        )
        guard case .connectionFailed = mapped else {
            return XCTFail("Expected connectionFailed, got \(mapped)")
        }
    }

    func testMapHostKeyErrorPassesThroughNonDeclined() {
        let validator = TOFUHostKeyValidator(knownHosts: store, hostIdentifier: "host:22")
        let original = SSHError.sessionNotConnected
        let mapped = SSHSession.mapHostKeyError(
            original, validator: validator, knownHosts: store, config: makeConfig()
        )
        XCTAssertEqual(mapped, original)
    }
}
