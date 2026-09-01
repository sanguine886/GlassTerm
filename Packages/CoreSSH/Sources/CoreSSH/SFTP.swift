import Citadel
import Foundation
import NIOCore

/// One directory entry returned by the SFTP browser (spec §4.4).
public struct SFTPEntry: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case file
        case directory
        case symlink
        case unknown
    }

    public let name: String
    public let kind: Kind
    public let size: UInt64?
    public let permissions: UInt32?

    public init(name: String, kind: Kind, size: UInt64?, permissions: UInt32?) {
        self.name = name
        self.kind = kind
        self.size = size
        self.permissions = permissions
    }
}

public enum SFTPError: Error, Equatable {
    case notConnected
    case operationFailed(String)
}

/// SFTP capability of a transport. Implemented by `CitadelSFTP` in production;
/// fakes in unit tests (spec §3.3).
public protocol SFTPService: Sendable {
    func list(directory: String) async throws -> [SFTPEntry]
    func readFile(at path: String) async throws -> Data
    func writeFile(data: Data, to path: String) async throws
    func delete(at path: String, isDirectory: Bool) async throws
    func rename(from oldPath: String, to newPath: String) async throws
    func createDirectory(at path: String) async throws
}

/// Citadel-backed SFTP client. One per session; thread confinement mirrors
/// `CitadelTransport` (the SFTP channel is internally synchronized).
public final class CitadelSFTP: SFTPService, @unchecked Sendable {
    private let client: SFTPClient

    public init(client: SFTPClient) {
        self.client = client
    }

    public func list(directory: String) async throws -> [SFTPEntry] {
        let names = try await client.listDirectory(atPath: directory)
        return names
            .flatMap(\.components)
            .map { entry in
                SFTPEntry(
                    name: entry.filename,
                    kind: Self.kind(of: entry),
                    size: entry.attributes.size,
                    permissions: entry.attributes.permissions
                )
            }
            .sorted { $0.name < $1.name }
    }

    /// Infers entry kind from the Unix mode type bits (S_IFMT) in
    /// `attributes.permissions`, falling back to the `longname` ls-style prefix.
    static func kind(of entry: SFTPPathComponent) -> SFTPEntry.Kind {
        if let mode = entry.attributes.permissions {
            switch mode & 0xF000 {
            case 0x4000: return .directory
            case 0x8000: return .file
            case 0xA000: return .symlink
            default: break
            }
        }
        switch entry.longname.first {
        case "d": return .directory
        case "l": return .symlink
        case "-": return .file
        default: return .unknown
        }
    }

    public func readFile(at path: String) async throws -> Data {
        // `withFile` opens and always closes the handle, avoiding a detached
        // close Task that would capture the non-Sendable `SFTPFile` (Swift 6).
        try await client.withFile(filePath: path, flags: .read) { file in
            let buffer = try await file.readAll()
            return buffer.withUnsafeReadableBytes { Data($0) }
        }
    }

    public func writeFile(data: Data, to path: String) async throws {
        try await client.withFile(filePath: path, flags: [.write, .create, .truncate]) { file in
            var buffer = ByteBuffer(bytes: data)
            _ = try await file.write(buffer, at: 0)
        }
    }

    public func delete(at path: String, isDirectory: Bool) async throws {
        if isDirectory {
            _ = try await client.rmdir(at: path)
        } else {
            _ = try await client.remove(at: path)
        }
    }

    public func rename(from oldPath: String, to newPath: String) async throws {
        _ = try await client.rename(at: oldPath, to: newPath)
    }

    public func createDirectory(at path: String) async throws {
        var attributes = SFTPFileAttributes()
        attributes.permissions = 0o755
        _ = try await client.createDirectory(atPath: path, attributes: attributes)
    }
}
