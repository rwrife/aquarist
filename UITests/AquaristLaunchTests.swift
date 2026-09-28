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

        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(String(describing: card.value).contains("Water change: Today"))
    }

    @MainActor
    func testQuickLogInitialControlsFollowLogicalOrderAndToolbarActionsAreHittable() throws {
        let app = launchApp()
        createTank(named: "Focus Tank", in: app)

        let card = app.buttons["tank.card.Focus Tank"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.label, "Focus Tank")
        XCTAssertTrue(String(describing: card.value).contains("History unknown"))
        card.tap()

        app.buttons["quick.testReading"].tap()
        let parameter = app.descendants(matching: .any)
            .matching(identifier: "quick.testParameter")
            .firstMatch
        let value = app.textFields["quick.testRawValue"]
        let cancel = app.buttons["quick.cancel"]
        let save = app.buttons["quick.save"]

        XCTAssertTrue(parameter.waitForExistence(timeout: 5))
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertLessThan(parameter.frame.minY, value.frame.minY)

        // The sheet begins at the medium detent, where lower optional Form rows
        // may be lazily unrealized. Assert the initial, always-visible controls
        // and standard system-toolbar actions instead of depending on offscreen
        // cells or toolbar-label AX bounds (which exclude the system hit slop).
        XCTAssertTrue(cancel.isHittable)
        XCTAssertTrue(save.isHittable)
    }

    @MainActor
    func testWallAndQuickLogRenderAtAccessibilityDynamicType() throws {
        let app = launchApp(accessibilityDynamicType: true)
        createTank(named: "AX Tank", in: app)

        let card = app.buttons["tank.card.AX Tank"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.label, "AX Tank")
        XCTAssertTrue(String(describing: card.value).contains("Water change: Unknown"))
        captureScreenshot(of: app, named: "AX5-Tank-Wall")

        card.tap()
        app.buttons["quick.waterChange"].tap()
        let waterPercent = app.descendants(matching: .any)
            .matching(identifier: "quick.wcPercent")
            .firstMatch
        XCTAssertTrue(waterPercent.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quick.save"].waitForExistence(timeout: 5))
        captureScreenshot(of: app, named: "AX5-Water-Change-Quick-Log")
    }

    @MainActor
    private func launchApp(accessibilityDynamicType: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        if accessibilityDynamicType {
            let category = "UICTContentSizeCategoryAccessibilityXXXL"
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", category]
            app.launchEnvironment["UIPreferredContentSizeCategoryName"] = category
        }
        app.launch()
        XCTAssertTrue(app.buttons["wall.addTank"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func createTank(named tankName: String, in app: XCUIApplication) {
        app.buttons["wall.addTank"].tap()
        let name = app.textFields["tank.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(tankName)
        app.buttons["tank.save"].tap()
    }

    private func captureScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
