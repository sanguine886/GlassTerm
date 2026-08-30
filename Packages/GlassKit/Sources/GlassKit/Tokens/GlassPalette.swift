import SwiftUI
import UIKit

/// Semantic color tokens for the three-layer glass structure (spec §5.1).
/// Values map to system semantic colors so dark and light themes both satisfy
/// the contrast requirements of spec §5.3 without hand-tuned palettes.
public extension Color {
    /// Background layer (spec §5.1 layer 1).
    static let glassBackground = Color(uiColor: .systemBackground)

    /// Elevated surface above glass, e.g. command preview blocks.
    static let glassSurface = Color(uiColor: .secondarySystemBackground)

    /// Primary text on glass (spec §5.3: ≥ 4.5:1).
    static let glassPrimaryText = Color(uiColor: .label)

    /// Supporting text on glass (spec §5.3: ≥ 3:1).
    static let glassSecondaryText = Color(uiColor: .secondaryLabel)

    /// Interactive accent across the app.
    static let glassAccent = Color.accentColor

    /// Danger tone for the warning form of approval cards (spec §5.2).
    static let glassDanger = Color.red
}
