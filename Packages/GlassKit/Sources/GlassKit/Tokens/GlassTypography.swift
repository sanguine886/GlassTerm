import SwiftUI

public extension Font {
    /// Monospaced font for terminal content and command previews.
    /// Bundled monospace fonts and user-facing font settings land in P2 (spec §4.3).
    static func glassMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
