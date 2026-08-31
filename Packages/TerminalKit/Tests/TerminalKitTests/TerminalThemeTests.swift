@testable import TerminalKit
import XCTest

final class TerminalThemeTests: XCTestCase {
    func testProvidesFiveBuiltInThemes() {
        XCTAssertEqual(TerminalTheme.all.count, 5)
        XCTAssertNotNil(TerminalTheme.theme(named: "Light"))
        XCTAssertNotNil(TerminalTheme.theme(named: "Dark"))
        XCTAssertNotNil(TerminalTheme.theme(named: "Solarized"))
        XCTAssertNotNil(TerminalTheme.theme(named: "Dracula"))
        XCTAssertNotNil(TerminalTheme.theme(named: "Glass"))
    }

    func testEveryThemeHasFullANSI16() {
        for theme in TerminalTheme.all {
            XCTAssertEqual(theme.ansi.count, 16, "\(theme.name) must define all 16 ANSI colors")
        }
    }

    func testThemeNamesAreUnique() {
        let names = TerminalTheme.all.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
    }

    func testHexParsing() {
        let color = TerminalRGBA(hex: 0x112233)
        XCTAssertEqual(color.red, 0x11 / 255, accuracy: 0.0001)
        XCTAssertEqual(color.green, 0x22 / 255, accuracy: 0.0001)
        XCTAssertEqual(color.blue, 0x33 / 255, accuracy: 0.0001)
        XCTAssertEqual(color.alpha, 1)
    }

    func testThemesAreCodableRoundtrip() throws {
        let data = try JSONEncoder().encode(TerminalTheme.dracula)
        let decoded = try JSONDecoder().decode(TerminalTheme.self, from: data)
        XCTAssertEqual(decoded, TerminalTheme.dracula)
    }

    func testDarkThemeBackgroundIsNotBlackerThanForeground() {
        // Readability smoke: dark themes must have a lighter foreground.
        for theme in [TerminalTheme.dark, .solarized, .dracula, .glass] {
            let luminance = theme.foreground.red + theme.foreground.green + theme.foreground.blue
            let background = theme.background.red + theme.background.green + theme.background.blue
            XCTAssertGreaterThan(luminance, background, "\(theme.name): foreground must be brighter than background")
        }
    }
}
