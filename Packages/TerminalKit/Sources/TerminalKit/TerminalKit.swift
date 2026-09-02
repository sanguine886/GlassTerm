// TerminalKit — SwiftTerm wrapper, extended key accessory bar, terminal themes,
// and session views. Bridges SwiftUI with UIKit-backed `TerminalView` (spec
// §4.3); SwiftTerm is pinned exact-version in P2 (ADR-0002).
#if canImport(UIKit)
    // Re-export SwiftTerm so the app layer can reference `TerminalView` in its
    // `UIViewRepresentable` bridge without depending on SwiftTerm directly.
    @_exported import SwiftTerm
#endif

/// Build metadata for the TerminalKit module.
public enum TerminalKitInfo {
    public static let moduleName = "TerminalKit"
}
