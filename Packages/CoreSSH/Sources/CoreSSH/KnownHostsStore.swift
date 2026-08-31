import Foundation

/// TOFU verdict for a presented host key.
public enum HostKeyVerdict: Equatable, Sendable {
    case trusted
    case newHost
    case changed(pinned: HostKeyFingerprint)
}

/// One pinned host key (TOFU record).
public struct KnownHostEntry: Codable, Equatable, Sendable {
    public let hostIdentifier: String
    public var pinned: HostKeyFingerprint

    public init(hostIdentifier: String, pinned: HostKeyFingerprint) {
        self.hostIdentifier = hostIdentifier
        self.pinned = pinned
    }
}

/// Persists pinned host-key fingerprints (TOFU, spec §4.1). Fingerprints are not
/// secrets; the store is a small JSON file in Application Support.
///
/// Synchronous and lock-protected: the host-key validator runs on a NIO event
/// loop and must not block on actor hops.
public final class KnownHostsStore: @unchecked Sendable {
    private let fileURL: URL?
    private let lock = NSLock()
    private var entries: [String: HostKeyFingerprint]

    /// Default location: Application Support/GlassTerm/known-hosts.json.
    public convenience init() throws {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let directory = base.appendingPathComponent("GlassTerm", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.init(storeURL: directory.appendingPathComponent("known-hosts.json"))
    }

    /// Injectable store location; used by tests and previews. `nil` URL keeps
    /// everything in memory.
    public init(storeURL: URL?) {
        self.fileURL = storeURL
        self.entries = [:]
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([KnownHostEntry].self, from: data) {
            for entry in decoded {
                entries[entry.hostIdentifier] = entry.pinned
            }
        }
        // A corrupt file starts empty rather than crashing the app; the next
        // trust() rewrite heals it.
    }

    public func verify(hostIdentifier: String, fingerprint: HostKeyFingerprint) -> HostKeyVerdict {
        lock.lock()
        defer { lock.unlock() }
        guard let pinned = entries[hostIdentifier] else { return .newHost }
        if pinned == fingerprint { return .trusted }
        return .changed(pinned: pinned)
    }

    public func trust(hostIdentifier: String, fingerprint: HostKeyFingerprint) {
        lock.lock()
        entries[hostIdentifier] = fingerprint
        let snapshot = entries
        lock.unlock()
        persist(snapshot)
    }

    /// User-approved re-pinning after a key-change alert (spec §4.1).
    public func repin(hostIdentifier: String, fingerprint: HostKeyFingerprint) {
        trust(hostIdentifier: hostIdentifier, fingerprint: fingerprint)
    }

    public func removePin(hostIdentifier: String) {
        lock.lock()
        entries[hostIdentifier] = nil
        let snapshot = entries
        lock.unlock()
        persist(snapshot)
    }

    public func pinnedFingerprint(hostIdentifier: String) -> HostKeyFingerprint? {
        lock.lock()
        defer { lock.unlock() }
        return entries[hostIdentifier]
    }

    public func allEntries() -> [KnownHostEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries.map { KnownHostEntry(hostIdentifier: $0.key, pinned: $0.value) }
            .sorted { $0.hostIdentifier < $1.hostIdentifier }
    }

    private func persist(_ snapshot: [String: HostKeyFingerprint]) {
        guard let fileURL else { return }
        let payload = snapshot
            .map { KnownHostEntry(hostIdentifier: $0.key, pinned: $0.value) }
            .sorted { $0.hostIdentifier < $1.hostIdentifier }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let temporary = fileURL.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString + ".tmp")
        // Atomic replace: write tmp then rename.
        if (try? data.write(to: temporary, options: .atomic)) != nil {
            try? FileManager.default.removeItem(at: fileURL)
            try? FileManager.default.moveItem(at: temporary, to: fileURL)
        }
    }
}
