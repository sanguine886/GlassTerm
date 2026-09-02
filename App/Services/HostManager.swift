import CoreSSH
import Foundation
import Observation
import Persistence

/// App-side orchestration: host CRUD with Keychain-backed secrets, and session
/// construction (spec §4.1). Business logic lives here, not in views.
@Observable
@MainActor
final class HostManager {
    struct HostDraft {
        var name: String
        var hostname: String
        var port: Int
        var username: String
        var group: String?
        var authKind: HostAuthKind
        /// Password or private-key PEM, depending on `authKind`.
        var secret: String
        var passphrase: String?
    }

    private let hostStore: HostStore
    private let secrets: SecretStoring
    let knownHosts: KnownHostsStore

    init(hostStore: HostStore, secrets: SecretStoring, knownHosts: KnownHostsStore) {
        self.hostStore = hostStore
        self.secrets = secrets
        self.knownHosts = knownHosts
    }

    /// Creates or updates a host, (re)storing its secret in the Keychain.
    func save(draft: HostDraft, existing: HostRecord?) throws -> HostRecord {
        let reference = existing?.secretRef ?? UUID().uuidString
        try secrets.save(draft.secret, account: reference)

        var passphraseRef = existing?.passphraseRef
        if let passphrase = draft.passphrase, !passphrase.isEmpty, draft.authKind == .privateKey {
            passphraseRef = reference + ".passphrase"
            try secrets.save(passphrase, account: passphraseRef ?? "")
        } else if let old = passphraseRef {
            try? secrets.delete(account: old)
            passphraseRef = nil
        }

        let record = existing ?? HostRecord(name: draft.name, hostname: draft.hostname, username: draft.username)
        record.name = draft.name
        record.hostname = draft.hostname
        record.port = draft.port
        record.username = draft.username
        record.group = draft.group?.isEmpty == true ? nil : draft.group
        record.authKind = draft.authKind
        record.secretRef = reference
        record.passphraseRef = passphraseRef

        if existing == nil {
            try hostStore.add(record)
        } else {
            try hostStore.update(record)
        }
        return record
    }

    func delete(_ record: HostRecord) throws {
        if let ref = record.secretRef {
            try? secrets.delete(account: ref)
        }
        if let ref = record.passphraseRef {
            try? secrets.delete(account: ref)
        }
        try hostStore.delete(id: record.id)
    }

    func record(id: UUID) -> HostRecord? {
        (try? hostStore.record(id: id)) ?? nil
    }

    /// All hosts, for pickers (snippet runner).
    var allHosts: [HostRecord] {
        (try? hostStore.all()) ?? []
    }

    func markConnected(_ record: HostRecord) {
        try? hostStore.markConnected(id: record.id)
    }

    /// Builds a session plus its config, resolving secrets from the Keychain
    /// just-in-time. The secret never persists anywhere else.
    func openSession(for record: HostRecord) throws -> (SSHSession, SSHHostConfig) {
        guard let reference = record.secretRef else {
            throw SSHError.invalidConfiguration("no credentials stored")
        }
        guard let secret = try secrets.load(account: reference) else {
            throw SSHError.invalidConfiguration("credentials missing from keychain")
        }

        let auth: SSHAuthMethod
        switch record.authKind {
        case .password:
            auth = .password(secret)
        case .privateKey:
            var passphrase: String?
            if let passphraseRef = record.passphraseRef {
                passphrase = try secrets.load(account: passphraseRef)
            }
            auth = .privateKey(pem: secret, passphrase: passphrase)
        }

        let config = SSHHostConfig(host: record.hostname, port: record.port, username: record.username, auth: auth)
        return (SSHSession(), config)
    }
}
