import XCTest
@testable import TerminalKit

final class TmuxDetectorTests: XCTestCase {
    func testDetectsTmuxDA1Response() {
        // tmux answers the DA1 query with CSI ? 62 c.
        let data = Data("\u{1B}[?62c".utf8)
        XCTAssertTrue(TmuxDetector.containsTmuxMarker(in: data))
    }

    func testDetectsTmuxDCSWrapper() {
        let data = Data("\u{1B}Ptmux;escape\u{1B}\\".utf8)
        XCTAssertTrue(TmuxDetector.containsTmuxMarker(in: data))
    }

    func testPlainTerminalOutputIsNotTmux() {
        let data = Data("$ ls -la\n".utf8)
        XCTAssertFalse(TmuxDetector.containsTmuxMarker(in: data))
    }

    func testOtherDA1ResponsesAreNotTmux() {
        // xterm answers CSI ? 1;2 c.
        let data = Data("\u{1B}[?1;2c".utf8)
        XCTAssertFalse(TmuxDetector.containsTmuxMarker(in: data))
    }

    func testEmptyDataIsNotTmux() {
        XCTAssertFalse(TmuxDetector.containsTmuxMarker(in: Data()))
    }
}
