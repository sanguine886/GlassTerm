import XCTest
@testable import TerminalKit

@MainActor
final class SessionTabsTests: XCTestCase {
    func testAddActivatesNewTab() {
        let model = SessionTabsModel()
        let id = model.add(title: "host-a")
        XCTAssertEqual(model.tabs.count, 1)
        XCTAssertEqual(model.activeID, id)
        XCTAssertTrue(model.tabs[0].isActive)
    }

    func testActivateSwitchesActiveFlag() {
        let model = SessionTabsModel()
        let first = model.add(title: "a")
        let second = model.add(title: "b")
        model.activate(id: first)
        XCTAssertEqual(model.activeID, first)
        XCTAssertTrue(model.tabs[0].isActive)
        XCTAssertFalse(model.tabs[1].isActive)
        XCTAssertEqual(second, model.tabs[1].id)
    }

    func testCloseActiveTabFallsBackToNeighbor() {
        let model = SessionTabsModel()
        let first = model.add(title: "a")
        let second = model.add(title: "b")
        model.close(id: second)
        XCTAssertEqual(model.tabs.count, 1)
        XCTAssertEqual(model.activeID, first)
        XCTAssertTrue(model.tabs[0].isActive)
    }

    func testCloseLastTabClearsActive() {
        let model = SessionTabsModel()
        let id = model.add(title: "only")
        model.close(id: id)
        XCTAssertTrue(model.tabs.isEmpty)
        XCTAssertNil(model.activeID)
    }

    func testRename() {
        let model = SessionTabsModel()
        let id = model.add(title: "old")
        model.rename(id: id, to: "new")
        XCTAssertEqual(model.tabs[0].title, "new")
    }

    func testActivateUnknownIDIsNoOp() {
        let model = SessionTabsModel()
        _ = model.add(title: "a")
        model.activate(id: UUID())
        XCTAssertNotNil(model.activeID)
    }
}
