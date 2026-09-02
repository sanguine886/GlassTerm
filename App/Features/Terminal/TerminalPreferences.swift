import Foundation
import Observation
import TerminalKit

/// User terminal preferences (font, size, theme) persisted in UserDefaults —
/// explicitly NOT secrets, so UserDefaults is allowed (spec §6.3.1).
@MainActor
@Observable
final class TerminalPreferences {
    static let shared = TerminalPreferences()

    var fontName: String {
        didSet { defaults.set(fontName, forKey: Keys.fontName) }
    }

    var fontSize: Int {
        didSet { defaults.set(fontSize, forKey: Keys.fontSize) }
    }

    var themeName: String {
        didSet { defaults.set(themeName, forKey: Keys.themeName) }
    }

    private let defaults: UserDefaults
    private enum Keys {
        static let fontName = "terminal.fontName"
        static let fontSize = "terminal.fontSize"
        static let themeName = "terminal.themeName"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        fontName = defaults.string(forKey: Keys.fontName)
            ?? TerminalFontSpec.builtInNames.first ?? "Menlo"
        let storedSize = defaults.integer(forKey: Keys.fontSize)
        fontSize = storedSize == 0 ? 12 : storedSize
        themeName = defaults.string(forKey: Keys.themeName) ?? TerminalTheme.dark.name
    }

    var theme: TerminalTheme {
        TerminalTheme.theme(named: themeName) ?? .dark
    }

    func saveSize(_ size: Int) {
        fontSize = min(max(size, TerminalFontSpec.sizeRange.lowerBound), TerminalFontSpec.sizeRange.upperBound)
    }
}
