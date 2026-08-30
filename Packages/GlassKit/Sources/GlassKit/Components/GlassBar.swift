import SwiftUI

/// Horizontal floating bar on the glass layer: bottom accessory strips and
/// tool bars (spec §5.1 layer 2).
public struct GlassBar<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        GlassEffectContainer(spacing: GlassSpacing.sm) {
            HStack(spacing: GlassSpacing.md) {
                content
            }
            .padding(.horizontal, GlassSpacing.lg)
            .padding(.vertical, GlassSpacing.sm)
            .glassEffect(.regular, in: Capsule())
        }
    }
}
