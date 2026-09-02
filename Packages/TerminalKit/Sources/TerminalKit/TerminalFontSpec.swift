import Foundation

/// Font/字号 validation (spec §4.3: 8–32pt, at least two monospace faces).
public enum TerminalFontSpec {
    public static let builtInNames = ["Menlo", "Courier New"]
    public static let sizeRange = 8 ... 32

    public static func isValidSize(_ size: Int) -> Bool {
        sizeRange.contains(size)
    }
}
