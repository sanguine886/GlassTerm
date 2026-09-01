/// TerminalKit — SwiftTerm wrapper, extended key accessory bar, terminal themes,
/// and session views.
///
/// Bridges SwiftUI with UIKit-backed `TerminalView` (spec §4.3). SwiftTerm is
/// pinned exact-version and lands in P2 (ADR-0002 in docs/ARCHITECTURE.md).
#if canImport(UIKit)
    /// Re-export SwiftTerm so the app layer can reference `TerminalView` in its
    /// `UIViewRepresentable` bridge without depending on SwiftTerm directly
    /// (which stays a TerminalKit-internal dependency).
    @_exported import SwiftTerm
#endif
