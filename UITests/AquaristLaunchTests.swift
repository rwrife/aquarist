import XCTest

final class AquaristLaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBootstrapHomeLaunches() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        XCTAssertTrue(app.otherElements["bootstrap.home"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Aquarist"].exists)
        XCTAssertTrue(app.staticTexts["The tank wall and quick-log sheets arrive in the next milestones."].exists)
    }
}
