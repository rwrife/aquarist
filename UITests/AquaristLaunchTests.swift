import XCTest

final class AquaristLaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCreateTankQuickLogWaterChangeUpdatesWallAge() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        let addTank = app.buttons["wall.addTank"]
        XCTAssertTrue(addTank.waitForExistence(timeout: 10))
        addTank.tap()
        let name = app.textFields["tank.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Kitchen")

        app.buttons["tank.save"].tap()

        let card = app.buttons["tank.card.Kitchen"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()

        app.buttons["quick.waterChange"].tap()
        let save = app.buttons["quick.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        let detailWaterAge = app.staticTexts["detail.waterAge"]
        XCTAssertTrue(detailWaterAge.waitForExistence(timeout: 5))
        XCTAssertTrue(detailWaterAge.label.contains("Water change: Today"))

        app.navigationBars.buttons.element(boundBy: 0).tap()

        let wallWaterAge = app.staticTexts["tank.waterAge.Kitchen"]
        XCTAssertTrue(wallWaterAge.waitForExistence(timeout: 5))
        XCTAssertTrue(wallWaterAge.label.contains("Water change: Today"))
    }

    @MainActor
    func testWallKeyAgesRenderAtAccessibilityDynamicType() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launchEnvironment["UIPreferredContentSizeCategoryName"] = "UICTContentSizeCategoryAccessibilityXXXL"
        app.launch()

        app.buttons["wall.addTank"].tap()
        let name = app.textFields["tank.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("AX Tank")
        app.buttons["tank.save"].tap()

        let card = app.buttons["tank.card.AX Tank"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let keyAge = app.staticTexts["tank.waterAge.AX Tank"]
        XCTAssertTrue(keyAge.waitForExistence(timeout: 5))
        XCTAssertTrue(keyAge.label.contains("Water change:"))
    }
}
