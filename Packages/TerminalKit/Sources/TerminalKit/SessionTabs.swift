import Foundation

/// Tab-bar state for multiple terminal sessions (spec §4.3: 标签页式，左滑关闭).
/// UI-agnostic so tab logic is unit-testable.
@MainActor
@Observable
public final class SessionTabsModel {
    public struct Tab: Identifiable, Equatable {
        public let id: UUID
        public var title: String
        public var isActive: Bool

        public init(id: UUID = UUID(), title: String, isActive: Bool = false) {
            self.id = id
            self.title = title
            self.isActive = isActive
        }
    }

    public private(set) var tabs: [Tab] = []
    public var activeID: UUID? {
        didSet {
            guard oldValue != activeID else { return }
            for index in tabs.indices {
                tabs[index].isActive = tabs[index].id == activeID
            }
        }
    }

    public init() {}

    public func add(title: String) -> UUID {
        let tab = Tab(title: title, isActive: true)
        tabs.append(tab)
        activeID = tab.id
        return tab.id
    }

    public func activate(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeID = id
    }

    public func close(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if activeID == id {
            activeID = tabs.indices.contains(index) ? tabs[index].id : tabs.last?.id
        }
    }

    public func rename(id: UUID, to title: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].title = title
    }

    public var activeTab: Tab? {
        tabs.first { $0.id == activeID }
    }
}
