import CoreGraphics

/// Spacing scale fixed by design spec §5.3: 4 / 8 / 12 / 16 / 24 / 32.
/// The scale is closed — UI code must not invent intermediate values.
public enum GlassSpacing {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32

    /// All scale steps, ascending.
    public static let all: [CGFloat] = [xs, sm, md, lg, xl, xxl]
}
