import Foundation
import Observation
import OSLog
import Persistence

/// App-side snippet library CRUD (spec §4.3 command panel / §7 P3).
@MainActor
@Observable
final class SnippetManager {
    private static let logger = Logger(subsystem: "com.glazeverre.GlazeVerre", category: "snippets")

    private let store: SnippetStore
    private(set) var snippets: [SnippetRecord] = []

    init(store: SnippetStore) {
        self.store = store
    }

    func refresh() {
        snippets = (try? store.all()) ?? []
    }

    func add(name: String, command: String, targetHostID: UUID? = nil) {
        do {
            let record = SnippetRecord(name: name, command: command, targetHostID: targetHostID)
            try store.add(record)
            refresh()
        } catch {
            Self.logger.error("snippet add failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func delete(_ record: SnippetRecord) {
        try? store.delete(id: record.id)
        refresh()
    }
}
