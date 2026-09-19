import XCTest

final class InteractionTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testMenuAndCustomButtons() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-check-world"]
        app.launch()
        app.buttons["菜单"].tap()
        XCTAssertTrue(app.buttons["日间模式"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["夜间模式"].exists)
        XCTAssertTrue(app.buttons["正常模式"].exists)
        app.buttons["多行聊天"].tap()
        XCTAssertFalse(app.buttons["日间模式"].exists)
        app.buttons["world.custom"].tap()
        XCTAssertTrue(app.buttons["长按"].firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["world.custom"].tap()
        XCTAssertTrue(app.buttons["山路"].exists)
    }

    func testInputFocusAndSubmit() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-check-world", "--ui-check-input"]
        app.launch()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.exists)
        field.typeText("hello")
        app.buttons["确定"].tap()
        let disappeared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [disappeared], timeout: 5), .completed)
    }

    func testLoginFieldsOpenEditDialogs() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["login.account"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        app.alerts.textFields.firstMatch.typeText("paritytest")
        app.alerts.buttons["确定"].tap()
        XCTAssertTrue(app.buttons["login.account"].label.contains("paritytest"))
        app.buttons["login.password"].tap()
        XCTAssertTrue(app.alerts.secureTextFields.firstMatch.waitForExistence(timeout: 5))
        app.alerts.secureTextFields.firstMatch.typeText("fixture-only")
        app.alerts.buttons["取消"].tap()
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
