import Citadel
import Foundation

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
        return names.map { entry in
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
    private static func kind(of entry: SFTPMessage.Name) -> SFTPEntry.Kind {
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
        let file = try await client.openFile(filePath: path, flags: .read)
        defer { Task { try? await file.close() } }
        let buffer = try await file.readToEnd()
        return Data(buffer: buffer)
    }

    public func writeFile(data: Data, to path: String) async throws {
        let file = try await client.openFile(filePath: path, flags: [.write, .create, .truncate])
        defer { Task { try? await file.close() } }
        _ = try await file.write(ByteBuffer(data: data), atOffset: 0)
    }

    public func delete(at path: String, isDirectory: Bool) async throws {
        if isDirectory {
            _ = try await client.removeDirectory(atPath: path)
        } else {
            _ = try await client.removeFile(atPath: path)
        }
    }

    public func rename(from oldPath: String, to newPath: String) async throws {
        _ = try await client.rename(from: oldPath, to: newPath)
    }

    public func createDirectory(at path: String) async throws {
        _ = try await client.createDirectory(atPath: path, attributes: .init(permissions: 0o755))
    }
}
