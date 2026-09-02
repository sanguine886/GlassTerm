import XCTest

@MainActor
final class RootTabsSmokeTests: XCTestCase {
    /// Spec §6.5.3 smoke path: the four root tabs all switch screens.
    /// The servers screen no longer has a static placeholder — its add button
    /// is the stable element instead.
    func testAllFourTabsSwitchScreens() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertEqual(app.tabBars.buttons.count, 4)

        let checks: [(index: Int, identifier: String)] = [
            (0, "screen.servers.add"),
            (1, "screen.terminal.heading"),
            (2, "screen.assistant.heading"),
            (3, "screen.settings.heading"),
        ]

        for check in checks {
            app.tabBars.buttons.element(boundBy: check.index).tap()
            XCTAssertTrue(
                app.descendants(matching: .any)
                    .matching(identifier: check.identifier)
                    .firstMatch
                    .waitForExistence(timeout: 5),
                "Expected \(check.identifier) after switching to tab \(check.index)"
            )
        }
    }
}
