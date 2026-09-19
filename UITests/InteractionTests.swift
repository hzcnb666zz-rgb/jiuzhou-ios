import XCTest

final class InteractionTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testCommonInventoryAndItemGeometry() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-check-world", "--ui-check-common"]
        app.launch()
        let width = app.windows.firstMatch.frame.width
        let backpack = app.buttons["world.slot.1"]
        XCTAssertTrue(backpack.waitForExistence(timeout: 5), app.debugDescription)
        let nextRow = app.buttons["world.slot.6"]
        let custom = app.buttons["world.custom"]
        XCTAssertEqual(backpack.frame.minY, custom.frame.minY, accuracy: 1)
        XCTAssertEqual(backpack.frame.height, (width * 3 / 11 - 2) / 2 - 2, accuracy: 1)
        XCTAssertEqual(nextRow.frame.minY - backpack.frame.maxY, 2, accuracy: 1)
        backpack.tap()
        let cloth = app.buttons["布衣"]
        XCTAssertTrue(cloth.waitForExistence(timeout: 5))
        let category = app.buttons["物品"].firstMatch
        XCTAssertEqual(category.frame.width, width / 8 - 2, accuracy: 1)
        XCTAssertEqual(category.frame.minY, cloth.frame.minY, accuracy: 1)
        XCTAssertLessThan(app.buttons["干粮"].frame.maxX, width - 5)
        XCTAssertEqual(cloth.frame.height, width / 11 - 2, accuracy: 1)
        let inventory = XCTAttachment(screenshot: app.screenshot())
        inventory.name = "common-to-inventory"
        inventory.lifetime = .keepAlways
        add(inventory)
        cloth.tap()
        XCTAssertTrue(app.buttons["丢弃"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["干粮"].exists)
        XCTAssertLessThan(app.buttons["给予"].frame.maxX, width - 5)
        XCTAssertEqual(app.buttons["装备"].firstMatch.frame.height, width / 9 - 2, accuracy: 1)
        XCTAssertTrue(app.buttons["interaction.close"].exists, app.debugDescription)
        app.buttons["interaction.close"].tap()
        XCTAssertTrue(backpack.exists)
    }

    func testPlayerPartialActionRowAndNPC() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-check-world", "--ui-check-player"]
        app.launch()
        let talk = app.buttons["交谈"]
        XCTAssertTrue(talk.waitForExistence(timeout: 5))
        XCTAssertEqual(talk.frame.width, app.windows.firstMatch.frame.width / 3 - 2, accuracy: 1)
        XCTAssertEqual(app.buttons["组队"].frame.width, talk.frame.width * 2 + 2, accuracy: 1)
        XCTAssertEqual(app.buttons["组队"].frame.minX, talk.frame.minX, accuracy: 1)
        app.buttons["interaction.close"].tap()
        XCTAssertFalse(talk.exists)
    }

    func testPagedTextStaysOpenUntilClose() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-check-world", "--ui-check-pages"]
        app.launch()
        app.buttons["下一页"].tap()
        XCTAssertTrue(app.buttons["上一页"].exists)
        app.buttons["上一页"].tap()
        XCTAssertTrue(app.buttons["下一页"].exists)
        app.buttons["关闭"].tap()
        XCTAssertTrue(app.buttons["菜单"].waitForExistence(timeout: 5))
    }

    func testRewardConfirmationRequiresInputAndCancelCloses() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-check-world", "--ui-check-confirmation"]
        app.launch()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.buttons["确 定"].tap()
        XCTAssertTrue(app.buttons["取 消"].exists)
        app.buttons["取 消"].tap()
        XCTAssertTrue(app.buttons["菜单"].waitForExistence(timeout: 5))
    }

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
