@testable import TerminalKit
import XCTest

final class KeyboardLayoutTests: XCTestCase {
    func testDefaultLayoutHasCoreKeys() {
        let layout = KeyboardLayout.default
        XCTAssertEqual(layout.key(id: "esc")?.output, "\u{1B}")
        XCTAssertEqual(layout.key(id: "tab")?.output, "\t")
        XCTAssertEqual(layout.key(id: "up")?.output, "\u{1B}[A")
        XCTAssertEqual(layout.key(id: "pipe")?.output, "|")
    }

    func testDirectionKeysEmitEscapeSequences() {
        let layout = KeyboardLayout.default
        XCTAssertEqual(layout.key(id: "down")?.output, "\u{1B}[B")
        XCTAssertEqual(layout.key(id: "home")?.output, "\u{1B}[H")
        XCTAssertEqual(layout.key(id: "end")?.output, "\u{1B}[F")
    }

    func testLongPressVariants() {
        let layout = KeyboardLayout.default
        XCTAssertTrue(layout.key(id: "esc")?.variants.contains("\u{1B}[") == true)
        XCTAssertEqual(layout.key(id: "home")?.allOutputs, ["\u{1B}[H", "\u{1B}[1~"])
    }

    func testAllKeyIDsAreUnique() {
        let ids = KeyboardLayout.default.keys.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testLayoutJSONRoundtrip() throws {
        let layout = KeyboardLayout.default
        let data = try XCTUnwrap(layout.encoded())
        let decoded = try XCTUnwrap(KeyboardLayout.decode(data))
        XCTAssertEqual(decoded, layout)
    }

    func testCorruptLayoutJSONFailsGracefully() {
        XCTAssertNil(KeyboardLayout.decode(Data("not json".utf8)))
    }
}
