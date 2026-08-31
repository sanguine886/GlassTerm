import Citadel
import Crypto
import Foundation
import NIOCore

/// Byte streams for an interactive shell session (PTY-backed).
public enum ShellEvent: Sendable, Equatable {
    case stdout(Data)
    case stderr(Data)
    case exited
}

/// Handle for writing to the remote shell. Sendable by confinement: the
/// underlying NIO channel hops writes to its own event loop.
public struct ShellStdin: Sendable {
    private let writeHandler: @Sendable (Data) async throws -> Void
    private let resizeHandler: @Sendable (Int, Int) async throws -> Void

    public func write(_ data: Data) async throws {
        try await writeHandler(data)
    }

    public func resize(cols: Int, rows: Int) async throws {
        try await resizeHandler(cols, rows)
    }
}

public struct ShellStreams: Sendable {
    public let output: AsyncStream<ShellEvent>
    public let stdin: ShellStdin
}

/// One open SSH connection's capabilities. Implemented by `CitadelTransport`
/// in production and by fakes in unit tests (spec §3.3: UI depends on
/// protocols).
public protocol SSHTransport: Sendable {
    /// Opens the connection; `validator` runs inside the handshake.
    func open(config: SSHHostConfig, validator: TOFUHostKeyValidator) async throws
    /// Runs a single command on a new exec channel.
    func run(_ command: String) async throws -> String
    /// Requests an interactive shell (PTY, xterm-256color).
    func requestShell(cols: Int, rows: Int) async throws -> ShellStreams
    /// Closes the connection; idempotent.
    func close() async
    /// Invoked when the connection drops unexpectedly.
    var onDrop: @Sendable () -> Void { get set }
    var isConnected: Bool { get }
}

/// Citadel-backed transport (ADR-0002: Citadel 0.12.1, SwiftNIO SSH).
public final class CitadelTransport: SSHTransport, @unchecked Sendable {
    // SSHClient is internally synchronized and only touched from this class;
    // confinement is enforced by SSHSession (one transport per session).
    private var client: SSHClient?
    private let clientLock = NSLock()
    private let dropBox = CallbackBox()

    public var onDrop: @Sendable () -> Void {
        get { dropBox.get() ?? {} }
        set { dropBox.set(newValue) }
    }

    public var isConnected: Bool {
        guard let client = currentClient() else { return false }
        return client.isConnected
    }

    public func open(config: SSHHostConfig, validator: TOFUHostKeyValidator) async throws {
        let method = try Self.authenticationMethod(for: config)
        let client = try await SSHClient.connect(
            host: config.host,
            port: config.port,
            authenticationMethod: method,
            hostKeyValidator: validator,
            reconnect: .never,
            connectTimeout: .seconds(15)
        )
        client.onDisconnect { [dropBox] in dropBox.get()?() }
        clientLock.lock()
        self.client = client
        clientLock.unlock()
    }

    public func run(_ command: String) async throws -> String {
        let client = try requireClient()
        let buffer = try await client.executeCommand(command)
        return String(buffer: buffer)
    }

    public func requestShell(cols _: Int, rows _: Int) async throws -> ShellStreams {
        let client = try requireClient()

        let (eventStream, continuation) = AsyncStream<ShellEvent>.makeStream(bufferingPolicy: .unbounded)
        let writerBox = TTYWriterBox()
        let opened = OpenSignal()

        let pump = Task {
            do {
                try await client.withTTY { inbound, outbound in
                    writerBox.set(outbound)
                    opened.succeed()
                    for try await event in inbound {
                        switch event {
                        case let .stdout(buffer):
                            continuation.yield(.stdout(Data(buffer: buffer)))
                        case let .stderr(buffer):
                            continuation.yield(.stderr(Data(buffer: buffer)))
                        }
                    }
                    continuation.yield(.exited)
                    continuation.finish()
                }
            } catch {
                if opened.settleIfFirst {
                    opened.fail(error)
                }
                continuation.yield(.exited)
                continuation.finish()
            }
        }
        _ = pump
        try await opened.wait()

        let stdin = ShellStdin(
            write: { data in
                guard let writer = writerBox.get() else { throw SSHError.sessionNotConnected }
                try await writer.write(ByteBuffer(data: data))
            },
            resize: { newCols, newRows in
                guard let writer = writerBox.get() else { throw SSHError.sessionNotConnected }
                try await writer.changeSize(cols: newCols, rows: newRows, pixelWidth: 0, pixelHeight: 0)
            }
        )
        return ShellStreams(output: eventStream, stdin: stdin)
    }

    public func close() async {
        clientLock.lock()
        let stale = client
        client = nil
        clientLock.unlock()
        try? await stale?.close()
    }

    // MARK: - Internals

    private func currentClient() -> SSHClient? {
        clientLock.lock()
        defer { clientLock.unlock() }
        return client
    }

    private func requireClient() throws -> SSHClient {
        guard let client = currentClient(), client.isConnected else {
            throw SSHError.sessionNotConnected
        }
        return client
    }

    static func authenticationMethod(for config: SSHHostConfig) throws -> SSHAuthenticationMethod {
        switch config.auth {
        case let .password(password):
            .passwordBased(username: config.username, password: password)
        case let .privateKey(pem, passphrase):
            let decryption = passphrase.flatMap { Data($0.utf8) }
            let trimmed = pem.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("BEGIN OPENSSH PRIVATE KEY") || trimmed.contains("ssh-ed25519") {
                do {
                    let key = try Curve25519.Signing.PrivateKey(sshEd25519: pem, decryptionKey: decryption)
                    return .ed25519(username: config.username, privateKey: key)
                } catch {
                    throw SSHError.keyParseFailed(error.localizedDescription)
                }
            }
            do {
                let key = try Insecure.RSA.PrivateKey(sshRsa: pem, decryptionKey: decryption)
                return .rsa(username: config.username, privateKey: key)
            } catch {
                throw SSHError.keyParseFailed(error.localizedDescription)
            }
        }
    }
}

/// Thread-safe holder for the escapee `TTYStdinWriter` (NIO channel writes are
/// internally event-loop hopped, so cross-actor use is safe).
final class TTYWriterBox: @unchecked Sendable {
    private let lock = NSLock()
    private var writer: Citadel.TTYStdinWriter?

    func set(_ writer: Citadel.TTYStdinWriter) {
        lock.lock()
        self.writer = writer
        lock.unlock()
    }

    func get() -> Citadel.TTYStdinWriter? {
        lock.lock()
        defer { lock.unlock() }
        return writer
    }
}

/// One-shot continuation gate signaled once the shell channel is live.
final class OpenSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var settled = false

    /// Resumes (and consumes) any pending waiter; safe to call multiple times.
    var settleIfFirst: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !settled
    }

    func wait() async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if settled {
                lock.unlock()
                continuation.resume()
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }

    func succeed() {
        lock.lock()
        let pending = continuation
        continuation = nil
        settled = true
        lock.unlock()
        pending?.resume()
    }

    func fail(_ error: Error) {
        lock.lock()
        let pending = continuation
        continuation = nil
        settled = true
        lock.unlock()
        pending?.resume(throwing: error)
    }
}

final class CallbackBox: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable () -> Void)?

    func set(_ callback: @Sendable () -> Void) {
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
