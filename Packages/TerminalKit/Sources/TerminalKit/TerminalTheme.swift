import Foundation

/// RGBA color with 0...1 components; UIKit-free so themes are unit-testable
/// and convertible to SwiftTerm's palette on demand.
public struct TerminalRGBA: Equatable, Sendable, Codable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// 0xRRGGBB convenience.
    public init(hex: UInt32, alpha: Double = 1) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }

    public static let clear = TerminalRGBA(red: 0, green: 0, blue: 0, alpha: 0)
}

/// Terminal color scheme (spec §4.3: at least 5 themes incl. light, dark,
/// Solarized, Dracula, Glass custom).
public struct TerminalTheme: Equatable, Sendable, Codable {
    public let name: String
    public let background: TerminalRGBA
    public let foreground: TerminalRGBA
    public let cursor: TerminalRGBA
    /// 16 ANSI colors, indices 0...7 normal, 8...15 bright.
    public let ansi: [TerminalRGBA]

    public init(
        name: String,
        background: TerminalRGBA,
        foreground: TerminalRGBA,
        cursor: TerminalRGBA,
        ansi: [TerminalRGBA]
    ) {
        self.name = name
        self.background = background
        self.foreground = foreground
        self.cursor = cursor
        self.ansi = ansi
    }

    /// Convenience init from 16 hex values (normal 0-7, bright 8-15).
    public init(name: String, background: UInt32, foreground: UInt32, cursor: UInt32, ansi: [UInt32]) {
        self.init(
            name: name,
            background: TerminalRGBA(hex: background),
            foreground: TerminalRGBA(hex: foreground),
            cursor: TerminalRGBA(hex: cursor),
            ansi: ansi.map { TerminalRGBA(hex: $0) }
        )
    }

    public static let light = TerminalTheme(
        name: "Light",
        background: 0xFFFFFF, foreground: 0x1A1A1A, cursor: 0x1A1A1A,
        ansi: [
            0x000000, 0xCD3131, 0x0DBC79, 0xE5E510,
            0x2472C8, 0xBC3FBC, 0x11A8CD, 0xE5E5E5,
            0x666666, 0xF14C4C, 0x23D18B, 0xF5F543,
            0x3B8EEA, 0xD670D6, 0x29B8DB, 0xFFFFFF,
        ]
    )

    public static let dark = TerminalTheme(
        name: "Dark",
        background: 0x1E1E1E, foreground: 0xD4D4D4, cursor: 0xFFFFFF,
        ansi: [
            0x000000, 0xCD3131, 0x0DBC79, 0xE5E510,
            0x2472C8, 0xBC3FBC, 0x11A8CD, 0xE5E5E5,
            0x666666, 0xF14C4C, 0x23D18B, 0xF5F543,
            0x3B8EEA, 0xD670D6, 0x29B8DB, 0xFFFFFF,
        ]
    )

    public static let solarized = TerminalTheme(
        name: "Solarized",
        background: 0x002B36, foreground: 0x839496, cursor: 0x93A1A1,
        ansi: [
            0x073642, 0xDC322F, 0x859900, 0xB58900,
            0x268BD2, 0xD33682, 0x2AA198, 0xEEE8D5,
            0x002B36, 0xCB4B16, 0x586E75, 0x657B83,
            0x839496, 0x6C71C4, 0x93A1A1, 0xFDF6E3,
        ]
    )

    public static let dracula = TerminalTheme(
        name: "Dracula",
        background: 0x282A36, foreground: 0xF8F8F2, cursor: 0xF8F8F2,
        ansi: [
            0x21222C, 0xFF5555, 0x50FA7B, 0xF1FA8C,
            0xBD93F9, 0xFF79C6, 0x8BE9FD, 0xF8F8F2,
            0x6272A4, 0xFF6E6E, 0x69FF94, 0xFFFFA5,
            0xD6ACFF, 0xFF92DF, 0xA4FFFF, 0xFFFFFF,
        ]
    )

    public static let glass = TerminalTheme(
        name: "Glass",
        background: 0x0E0E14, foreground: 0xE8E8F2, cursor: 0x8AB4FF,
        ansi: [
            0x1C1C26, 0xFF6B81, 0x6BE08A, 0xFFE08A,
            0x7FA8FF, 0xD08AFF, 0x7AE2E8, 0xD8D8E8,
            0x44445A, 0xFF8FA0, 0x9CF0B2, 0xFFEF9F,
            0xA5C4FF, 0xE0B0FF, 0x9FF0F5, 0xFFFFFF,
        ]
    )

    public static let all: [TerminalTheme] = [.light, .dark, .solarized, .dracula, .glass]

    public static func theme(named: String) -> TerminalTheme? {
        all.first { $0.name == named }
    }
}
