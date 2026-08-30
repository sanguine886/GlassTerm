import XCTest

@MainActor
final class RootTabsSmokeTests: XCTestCase {
    /// Spec §6.5.3 smoke path (P0 scope): the four root tabs all switch screens.
    func testAllFourTabsSwitchScreens() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertEqual(app.tabBars.buttons.count, 4)

        let headings = [
            "screen.servers.heading",
            "screen.terminal.heading",
            "screen.assistant.heading",
            "screen.settings.heading",
        ]

        for (index, heading) in headings.enumerated() {
            app.tabBars.buttons.element(boundBy: index).tap()
            XCTAssertTrue(
                app.staticTexts[heading].waitForExistence(timeout: 5),
                "Expected heading \(heading) after switching to tab \(index)"
            )
        }
    }
}
