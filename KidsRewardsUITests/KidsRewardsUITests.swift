import XCTest

final class KidsRewardsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchShowsMainTabs() throws {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["Kids Rewards"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Kids"].exists)
        XCTAssertTrue(app.buttons["Work"].exists)
        XCTAssertTrue(app.buttons["Settings"].exists)
    }

    func testCanNavigateToWorkAndSettingsTabs() throws {
        let app = makeApp()
        app.launch()

        app.buttons["Work"].tap()
        XCTAssertTrue(app.staticTexts["Work"].waitForExistence(timeout: 3))

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 3))
    }

    func testSettingsShowsNoPINSetWhenThereIsNoParentPIN() throws {
        let app = makeApp()
        app.launch()

        app.buttons["Settings"].tap()

        XCTAssertTrue(app.buttons["No PIN Set"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["No parent PIN is set."].exists)
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset"]
        return app
    }
}
