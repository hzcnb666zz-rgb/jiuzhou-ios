import XCTest

final class InteractionTests: XCTestCase {
    func testRepeatedActionsStatsAndUpdatedDirection() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-check-world", "--ui-check-edge"]
        app.launch()
        XCTAssertTrue(app.buttons["刷新"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["查看"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "同名村民").count, 2)
        XCTAssertTrue(app.buttons["标题甲"].exists)
        XCTAssertTrue(app.buttons["标题乙"].exists)
        let first = app.buttons["world.stat.0"].frame
        let last = app.buttons["world.stat.2"].frame
        XCTAssertEqual(last.width, first.width * 2, accuracy: 1)
        XCTAssertEqual(first.height, app.windows.firstMatch.frame.width / 40, accuracy: 1)
        app.buttons["发送语音"].tap()
        XCTAssertTrue(app.buttons["开始录音"].waitForExistence(timeout: 5))
        app.buttons["world.custom"].tap()
        XCTAssertTrue(app.buttons["world.custom"].exists)
        app.buttons["world.custom"].tap()
        XCTAssertTrue(app.buttons["上山"].exists)
        XCTAssertFalse(app.buttons["旧北路"].exists)
    }

    func testRegistrationMatchesFourAndroidFieldsWithoutSubmitting() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["注 册"].tap()
        XCTAssertTrue(app.buttons["register.account"].exists)
        XCTAssertTrue(app.buttons["register.password"].exists)
        XCTAssertTrue(app.buttons["register.confirmation"].exists)
        XCTAssertTrue(app.buttons["register.phone"].exists)
        XCTAssertFalse(app.textFields["register.email"].exists)
        XCTAssertFalse(app.buttons["退 出"].exists)
        let account = app.buttons["register.account"].frame
        let password = app.buttons["register.password"].frame
        XCTAssertEqual(account.height, app.windows.firstMatch.frame.width / 11, accuracy: 1)
        let layoutWidth = try! XCTUnwrap(Double(app.buttons["register.submit"].value as? String ?? ""))
        let windowScale = app.windows.firstMatch.frame.width / CGFloat(layoutWidth)
        XCTAssertEqual(password.minY - account.maxY, 60 * windowScale, accuracy: 1)
        app.buttons["register.account"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["取消"].tap()
    }

    func testAccountCenterEditsAndReturnsWithoutNetworkMutation() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-check-account"]
        app.launch()
        XCTAssertTrue(app.buttons["account.newpwd"].waitForExistence(timeout: 5))
        app.buttons["account.newpwd"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["取消"].tap()
        app.buttons["account.server"].tap()
        XCTAssertTrue(app.buttons["取 消"].waitForExistence(timeout: 5))
        let name = app.textFields["account.serverfield.名称："]
        name.tap()
        name.typeText("-cancel-test")
        app.buttons["取 消"].tap()
        XCTAssertTrue(app.staticTexts["名　称：我的测试服"].exists)
        app.buttons["关 闭"].tap()
        XCTAssertTrue(app.buttons["login.account"].exists)
    }

    func testThemeSwitchesAndRotationKeepWorldControls() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-check-world"]
        app.launch()
        for theme in ["日间模式", "夜间模式", "正常模式"] {
            app.buttons["菜单"].tap()
            XCTAssertTrue(app.buttons[theme].waitForExistence(timeout: 5))
            app.buttons[theme].tap()
            XCTAssertTrue(app.buttons["山路"].exists)
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.buttons["菜单"].waitForExistence(timeout: 5))
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "landscape-world"
        capture.lifetime = .keepAlways
        add(capture)
    }

    override func setUpWithError() throws { continueAfterFailure = false }

    func testCommonInventoryAndItemGeometry() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-check-world", "--ui-check-common"]
        app.launch()
        let window = app.windows.firstMatch.frame
        let width = window.width
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
        let category = app.scrollViews["interaction.primary"].buttons["物品"]
        XCTAssertEqual(category.frame.width, width / 8 - 2, accuracy: 1)
        XCTAssertEqual(category.frame.minY, cloth.frame.minY, accuracy: 1)
        XCTAssertLessThan(app.buttons["干粮"].frame.maxX, window.maxX - 5)
        XCTAssertEqual(cloth.frame.height, width / 11 - 2, accuracy: 1)
        if !app.buttons["仓库"].isHittable {
            let clothY = cloth.frame.minY
            app.scrollViews["interaction.primary"].swipeUp()
            XCTAssertTrue(app.buttons["仓库"].isHittable)
            XCTAssertEqual(cloth.frame.minY, clothY, accuracy: 1)
        }
        let inventory = XCTAttachment(screenshot: app.screenshot())
        inventory.name = "common-to-inventory"
        inventory.lifetime = .keepAlways
        add(inventory)
        cloth.tap()
        XCTAssertTrue(app.buttons["丢弃"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["干粮"].exists)
        XCTAssertLessThan(app.buttons["给予"].frame.maxX, window.maxX - 5)
        XCTAssertEqual(app.scrollViews["interaction.primary"].buttons["装备"].frame.height, width / 9 - 2, accuracy: 1)
        XCTAssertTrue(app.buttons["interaction.close"].exists, app.debugDescription)
        app.buttons["interaction.close"].tap()
        XCTAssertTrue(backpack.exists)
        app.buttons["老村长"].tap()
        XCTAssertTrue(app.buttons["交谈"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["交易"].frame.width, app.buttons["交谈"].frame.width, accuracy: 1)
        app.buttons["interaction.close"].tap()
        XCTAssertFalse(app.buttons["交谈"].exists)
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
        // Use the app's measured layout width; the test runner has its own screen metrics.
        let layoutWidth = Double(app.buttons["确定"].value as? String ?? "") ?? 0
        XCTAssertGreaterThan(layoutWidth, 0)
        guard layoutWidth > 0 else { return }
        let windowScale = app.windows.firstMatch.frame.width / CGFloat(layoutWidth)
        XCTAssertEqual(app.buttons["确定"].frame.width, 65 * windowScale, accuracy: 1)
        XCTAssertEqual(app.buttons["确定"].frame.height, 40 * windowScale, accuracy: 1)
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
