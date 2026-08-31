import Foundation
import SwiftData

/// A saved shell command (spec §4.3 command panel / §7 P3 snippet library).
@Model
public final class SnippetRecord {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var command: String
    /// Optional binding to a specific host (reuse its connection).
    public var targetHostID: UUID?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        command: String,
        targetHostID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.targetHostID = targetHostID
        self.createdAt = createdAt
    }
}
