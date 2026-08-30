import SwiftUI

/// Content card on the glass layer (spec §5.1 layer 2).
/// Screens with several co-visible glass elements must wrap them in one
/// `GlassEffectContainer`, and must never stack more than 2 glass layers.
public struct GlassCard<Content: View>: View {
    private let cornerRadius: CGFloat
    private let content: Content

    public init(cornerRadius: CGFloat = GlassSpacing.xl, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(GlassSpacing.lg)
            .glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
    }
}
