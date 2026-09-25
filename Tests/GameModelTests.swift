import XCTest
@testable import JiuzhouProtocol

private final class RecordingTransport: MudTransporting {
    var onFrame: ((MudFrame) -> Void)?
    var onStatus: ((String, Bool) -> Void)?
    var preservesNewlines = true
    var commands: [String] = []
    var endpoint = ""
    var connectCount = 0
    private(set) var isReady = false
    func connect(host: String, port: UInt16) {
        endpoint = "\(host):\(port)"; connectCount += 1; isReady = true
        onStatus?("已连接", true)
    }
    func send(_ command: String) { commands.append(command) }
    func disconnect() { isReady = false }
    func receive(_ code: String?, _ text: String) { onFrame?(MudFrame(code: code, text: text)) }
}

final class GameModelTests: XCTestCase {
    func testAndroidIndependentBrightAndNormalSpanInheritance() {
        var style = MudStyleStream()
        _ = style.render("\u{001B}[1;31m亮红\u{001B}[32m普通绿\u{001B}[42;1m亮背景\u{001B}[43m普通背景")
        XCTAssertEqual(style.render("继承"), "\u{001B}[32m\u{001B}[1;31m\u{001B}[42;1m\u{001B}[43m继承")
        _ = style.render("\u{001B}[f#123456m\u{001B}[b#654321m自定颜色")
        XCTAssertEqual(style.render("后续"), "\u{001B}[f#123456m\u{001B}[1;31m\u{001B}[b#654321m\u{001B}[43m后续")
        _ = style.render("\u{001B}[0m")
        XCTAssertEqual(style.render("恢复"), "恢复")
    }

    func testStyleInheritanceAndCombatAreSeparateFromNotices() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        wire.receive(nil, "\u{001B}[31m红色")
        wire.receive(nil, "继承")
        XCTAssertEqual(game.messages.last?.text, "\u{001B}[31m继承")
        wire.receive(nil, "\u{001B}[0m恢复")
        wire.receive(nil, "普通")
        XCTAssertEqual(game.messages.last?.text, "普通")
        wire.receive("015", "通知")
        wire.receive("024", "伤害 100")
        XCTAssertEqual(game.notice, "通知")
        XCTAssertEqual(game.combatEffects.first?.text, "伤害 100")
        wire.receive("002", "新房间")
        XCTAssertTrue(game.combatEffects.isEmpty)
    }

    func testVoiceActionsDoNotSendPlaceholderCommands() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        wire.onStatus?("已连接", true)
        game.act(MudAction(label: "发送语音", command: "record"))
        XCTAssertTrue(game.voiceRecorderVisible)
        XCTAssertTrue(wire.commands.isEmpty)
        game.act("voice:123.amr")
        XCTAssertEqual(game.voiceFilename, "123.amr")
        XCTAssertTrue(wire.commands.isEmpty)
        game.logout()
        XCTAssertFalse(game.voiceRecorderVisible)
        XCTAssertNil(game.voiceFilename)
    }

    func testObjectDuplicatesAndDirectionalReplacement() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        wire.receive("005", "村民:look villager$zj#村民:look villager")
        wire.receive("005", "村民:look villager")
        XCTAssertEqual(game.objects.count, 3)
        XCTAssertEqual(Set(game.objects.map(\.id)).count, 3)
        wire.receive("003", "north:北路$zj#east:东路")
        wire.receive("003", "northup:山路:climb$zj#northdown:山谷:descend")
        XCTAssertEqual(game.exits.count, 2)
        XCTAssertEqual(game.exits.first?.command, "descend")
        wire.receive("903", "northdown")
        XCTAssertEqual(game.exits.map(\.slot), ["east"])
        wire.receive("905", "villager")
        XCTAssertTrue(game.objects.isEmpty)
    }

    func testNPCLayoutIsOnlySelectedForNPCResponses() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        wire.onStatus?("已连接", true)

        wire.receive("005", "老村长:look elder$zj#布衣:look cloth")
        game.act("look elder")
        wire.receive("007", "【布衣平民】导师「人见人爱」老村长$br#他的武功达到了深不可测。$br#他看起来气血充盈。")
        XCTAssertEqual(game.dialog?.kind, "npc")

        wire.receive("002", "未明谷")
        wire.receive("005", "布衣:look cloth")
        game.act("look cloth")
        wire.receive("007", "布衣$br#这是一件普通的布衣。$br#防御：5")
        wire.receive("008", "$3,3,9,30#装备:wear cloth$zj#丢弃:drop cloth")
        XCTAssertEqual(game.dialog?.kind, "interaction")

        wire.receive("008", "$2,3,9,30#交谈:ask elder")
        XCTAssertEqual(game.dialog?.kind, "interaction")

        wire.receive("002", "未明谷")
        wire.receive("005", "老村长:look elder")
        game.act("look elder")
        wire.receive("008", "$2,3,9,30#交谈:ask elder$zj#交易:list elder")
        XCTAssertEqual(game.dialog?.kind, "npc")
        wire.receive("007", "老村长$br#你想打听什么？")
        XCTAssertEqual(game.dialog?.actions.map(\.command), ["ask elder", "list elder"])

        wire.receive("002", "未明谷")
        wire.receive("007", "电子驿站$br#这里是邮件列表。")
        XCTAssertEqual(game.dialog?.kind, "interaction")

        wire.receive("013", "寻路结果")
        XCTAssertEqual(game.dialog?.kind, "pages")

        wire.receive("002", "未明谷")
        wire.receive("007", "导师系统说明")
        XCTAssertEqual(game.dialog?.kind, "interaction")
    }

    func testItemDescriptionUsesIsolatedDetailKindWithoutAffectingPages() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        wire.onStatus?("已连接", true)
        wire.receive("005", "三清剑:look sword")
        game.act("look sword")
        wire.receive("007", "物品描述：这是一把剑。$br#物品类型：武器$br#装备耐久：100")

        XCTAssertEqual(game.dialog?.kind, "item")
        wire.receive("013", "电子驿站邮件列表")
        XCTAssertEqual(game.dialog?.kind, "pages")
    }

    func testNPCActionFramesReplaceOnlyTheirMatchingAndroidActionTable() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        wire.onStatus?("已连接", true)
        wire.receive("005", "小龙女:look longnv")
        game.act("look longnv")
        wire.receive("007", "小龙女是古墓派导师，武功高强。她气血充盈。")
        XCTAssertEqual(game.dialog?.kind, "npc")
        wire.receive("008", "$4,3,9,30#剑:get sword$zj#拜师:join gumu")
        wire.receive("009", "$1,4,11,42#银索金铃:ask longnv")

        wire.receive("008", "$2,3,9,30#查看技能:skills longnv")
        XCTAssertEqual(game.dialog?.actions.map(\.command), ["skills longnv"])
        XCTAssertEqual(game.dialog?.secondary.map(\.command), ["ask longnv"])
        XCTAssertEqual(game.dialog?.layout.columns, 2)

        wire.receive("009", "$1,4,11,42#风神诀:canwu")
        XCTAssertEqual(game.dialog?.actions.map(\.command), ["skills longnv"])
        XCTAssertEqual(game.dialog?.secondary.map(\.command), ["canwu"])
        XCTAssertEqual(game.dialog?.secondaryLayout.columns, 1)
    }

    func testHandshakeAndRejectedLoginCanRetry() {
        let keys = ["account", "host", "port"]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { UserDefaults.standard.set(value, forKey: key) } }
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        game.account = "paritytest"; game.password = "fixture-only"; game.host = "127.0.0.1"; game.port = "6666"
        game.login()
        wire.receive(nil, "ver1.0,fixture")
        wire.receive(nil, "版本验证成功")
        XCTAssertEqual(wire.commands, ["local", "paritytest║fixture-only║123456789abcd║local@localhost"])
        wire.receive("015", "密码错误")
        XCTAssertEqual(game.status, "密码错误")
        XCTAssertFalse(game.inWorld)
        game.login()
        wire.receive(nil, "版本验证成功")
        XCTAssertEqual(wire.commands.count, 3)
        wire.receive("000", "0007")
        XCTAssertTrue(game.inWorld)
    }

    func testPopupKeepsUnderlyingDialogAndRoutesSelectedCommand() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        wire.onStatus?("已连接", true)
        wire.receive("007", "人物")
        game.act("\u{001B}020交谈|ask elder$z2#观察|look elder")
        XCTAssertEqual(game.dialog?.text, "人物")
        XCTAssertEqual(game.popup?.actions.count, 2)
        XCTAssertEqual(game.popup?.layout, MudLayout("", defaults: [1, 2, 8, 25]))
        game.act(game.popup!.actions[0].command)
        XCTAssertEqual(wire.commands, ["ask elder"])
        XCTAssertNil(game.popup)
        XCTAssertNil(game.dialog)
    }

    func testRewardParsingAndInspectDoesNotCloseConfirmation() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        wire.onStatus?("已连接", true)
        wire.receive("010", "礼物$br#$exp#经验100$br#$god#银两10$br#$obj#sword,missing,2$dh#ok11.accept$dh#no11.")
        XCTAssertEqual(game.dialog?.kind, "confirmation")
        XCTAssertEqual(game.dialog?.experience, "经验100")
        XCTAssertEqual(game.dialog?.money, "银两10")
        XCTAssertEqual(game.dialog?.rewards.first?.grade, 2)
        XCTAssertTrue(game.dialog?.numeric == true)
        game.confirmDialog("")
        XCTAssertTrue(wire.commands.isEmpty)
        if let item = game.dialog?.rewards.first { game.inspectReward(item) }
        XCTAssertEqual(wire.commands, ["litem sword"])
        XCTAssertNotNil(game.dialog)
        game.cancelConfirmation()
        XCTAssertNil(game.dialog)
        XCTAssertEqual(wire.commands, ["litem sword"])
    }

    func testOrdinaryCommandDoesNotSplitConfirmationDelimiter() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        wire.onStatus?("已连接", true)
        game.act("say literal$sock#text")
        XCTAssertEqual(wire.commands, ["say literal$sock#text"])
        wire.receive("045", "https://example.com/test")
        XCTAssertEqual(game.webURL?.absoluteString, "https://example.com/test")
        wire.receive("045", "javascript:alert(1)")
        XCTAssertEqual(game.webURL?.absoluteString, "https://example.com/test")
        game.logout()
        XCTAssertNil(game.webURL)
    }

    func testCombatSkillActionsPreserveCompleteServerCommands() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        wire.onStatus?("已连接", true)

        wire.receive("021", "激活:enable sword-style$zj#释放:perform sword-style target:body")
        XCTAssertEqual(game.topActions.map(\.command), ["enable sword-style", "perform sword-style target:body"])
        game.act(game.topActions[1])

        wire.receive("006", "b6:绝技:cast sword-style target:body")
        XCTAssertEqual(game.buttons.first(where: { $0.slot == "b6" })?.command, "cast sword-style target:body")
        game.act(game.buttons.first(where: { $0.slot == "b6" })!)

        XCTAssertEqual(wire.commands, ["perform sword-style target:body", "cast sword-style target:body"])
    }

    func testExertTwiceButtonIsCorrectedBeforeSending() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        wire.onStatus?("已连接", true)
        wire.receive("021", "战气:exert force.powerup twice")
        game.act(game.topActions[0])
        XCTAssertEqual(wire.commands, ["exert force.powerup"])
    }

    func testStatsUseServerNameValuesCommandsAndFiveColumns() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        let values = (1...10).map { "\($0 == 1 ? "牛逼" : "属性\($0)"):\($0)/10:#aa3300:score\($0)" }.joined(separator: "║")
        wire.receive("012", "$2,2,22,35#" + values)
        XCTAssertEqual(game.stats.count, 10)
        XCTAssertEqual(game.stats.first?.label, "牛逼")
        XCTAssertEqual(game.stats.first?.command, "score1")
        XCTAssertEqual(game.statsLayout.columns, 5)
    }

    func testReferenceStatsUseThreeColumnsForSixServerValues() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        let values = [
            "姓名：柠檬王子:100/100:#336666",
            "气血.850:850/850/850:#99FF0000",
            "精神.200:200/200/200:#99990000",
            "先天之炁.0:0/0/4000:#BB3F51B5",
            "内力.0:0/0/0:#990066FF",
            "元神.100:100/100/200:#990066CC"
        ].joined(separator: "║")
        wire.receive("012", "$2,2,40,35#" + values)
        XCTAssertEqual(game.stats.count, 6)
        XCTAssertEqual(game.statsLayout.columns, 3)
        XCTAssertEqual(game.stats[1].label, "气血.850")
    }

    func testStatsDisplayVitalEnergyAsInnateQiWithoutChangingServerBinding() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        wire.receive("012", "$2,2,40,35#精力.125:125/4000:#BB3F51B5:hp")

        XCTAssertEqual(game.stats.count, 1)
        XCTAssertEqual(game.stats[0].label, "先天之炁.125")
        XCTAssertEqual(game.stats[0].value, "125/4000")
        XCTAssertEqual(game.stats[0].color, "#72C51F")
        XCTAssertEqual(game.stats[0].command, "hp")
    }

    func testCurrentQiFrameBindsInnateQiAndCombatKeepsIt() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        wire.onStatus?("已连接", true)
        // Current non-combat frame names the bar "炁" with the real xiantian.
        wire.receive("012", "$3,3,25,40#姓名：试剑台:100/100:#336666║炁.100:100/4000/4000:#990066CC║经验.1000:1000/1000:#99CCCC66")
        let qiBar = game.stats.first { $0.label.hasPrefix("先天之炁") }
        XCTAssertNotNil(qiBar)
        XCTAssertEqual(qiBar?.value, "100/4000/4000")
        // Combat frames also use "炁"; the bar must keep tracking xiantian
        // instead of flipping to a different resource (or to zero).
        wire.receive("016", "你与对手交上了手。")
        wire.receive("012", "$6,6,25,40#我：试剑台:100/100:#333333║气血.800:800/800/800:#99FF0000║炁.120:120/4000/4000:#990066CC║忙乱.0:0/1:#BB3F51B5")
        let combatQiBar = game.stats.first { $0.label.hasPrefix("先天之炁") }
        XCTAssertEqual(combatQiBar?.value, "120/4000/4000")
    }

    private func enterWorld(_ wire: RecordingTransport, _ game: GameModel, account: String = "tester01", password: String = "secret") {
        game.account = account
        game.password = password
        wire.receive(nil, "ver1.0,x")
        wire.receive(nil, "版本验证成功")
        wire.receive("000", "0007")
    }

    func testUnexpectedDropWhileActiveReconnectsAndResendsCredentials() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        enterWorld(wire, game)
        XCTAssertTrue(game.inWorld)
        let firstConnect = wire.connectCount

        // The socket dies while the app is in the foreground.
        wire.onStatus?("服务器已断开连接", false)
        let settled = expectation(description: "auto-relogin timer")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { settled.fulfill() }
        wait(for: [settled], timeout: 3)

        XCTAssertEqual(wire.connectCount, firstConnect + 1)
        // Replay the server handshake; the client must re-send credentials.
        wire.commands.removeAll()
        wire.receive(nil, "ver1.0,x")
        wire.receive(nil, "版本验证成功")
        XCTAssertEqual(wire.commands.last, "tester01║secret║123456789abcd║local@localhost")
    }

    func testForegroundResumeWithDeadSocketReconnects() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        enterWorld(wire, game)
        let firstConnect = wire.connectCount

        // Simulate returning from background with a link that is no longer ready.
        #if canImport(UIKit)
        wire.disconnect()
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        let settled = expectation(description: "foreground reconnect")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
        XCTAssertEqual(wire.connectCount, firstConnect + 1)
        #else
        // Lifecycle notifications are UIKit-only; on macOS the reconnect core
        // is covered by the unexpected-drop test above.
        XCTAssertEqual(wire.connectCount, firstConnect)
        #endif
    }

    func testManualLogoutDoesNotAutoReconnect() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        enterWorld(wire, game)
        game.logout()
        let settled = expectation(description: "no relogin")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { settled.fulfill() }
        wait(for: [settled], timeout: 3)
        XCTAssertFalse(game.inWorld)
        // No connect must have happened: logout must not trigger re-login.
        XCTAssertEqual(wire.connectCount, 0)
    }

    func testReferenceStatColorsUseDisplayNames() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        let values = [
            "精神.200:200/200:#99990000:exert regenerate",
            "潜能.100:100:#99990000:potential",
            "先天之炁.125:125/4000:#BB3F51B5:hp"
        ].joined(separator: "║")

        wire.receive("012", "$3,2,22,35#" + values)

        XCTAssertEqual(game.stats.map(\.color), ["#6A1BB4", "#D84BC8", "#72C51F"])
        XCTAssertEqual(game.stats.map(\.command), ["exert regenerate", "potential", "hp"])
    }

    func testCombatFrameDoesNotChangeServerBoundStats() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        wire.receive("012", "$2,2,40,35#先天之炁.125:125/4000:#BB3F51B5:hp")
        let statsBeforeCombat = game.stats
        let layoutBeforeCombat = game.statsLayout

        wire.receive("016", "你与对手交上了手。")

        XCTAssertTrue(game.fighting)
        XCTAssertEqual(game.stats.map(\.label), statsBeforeCombat.map(\.label))
        XCTAssertEqual(game.stats.map(\.value), statsBeforeCombat.map(\.value))
        XCTAssertEqual(game.stats.map(\.color), statsBeforeCombat.map(\.color))
        XCTAssertEqual(game.stats.map(\.command), statsBeforeCombat.map(\.command))
        XCTAssertEqual(game.statsLayout, layoutBeforeCombat)
    }

    func testCombatStatRefreshUpdatesValuesWithoutChangingStatusBarStructure() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        wire.receive("012", "$3,3,25,40#姓名：试江青青:100/100:#336666║气血.850:850/850/850:#99FF0000:exert recover║精神.200:200/200/200:#99990000:exert regenerate║精力.125:125/4000:#BB3F51B5:hp║内力.300:300/500:#990066FF:hp║元神.80:80/200:#990066CC")
        let structureBeforeCombat = game.stats.map { $0.label.components(separatedBy: ".").first ?? $0.label }
        let layoutBeforeCombat = game.statsLayout

        wire.receive("016", "你与对手交上了手。")
        wire.receive("012", "$2,2,22,35#姓名：试江青青:100/100:#336666║气血.820:820/850/850:#99FF0000:exert recover║精神.190:190/200/200:#99990000:exert regenerate║精力.120:120/4000:#BB3F51B5:hp║内力.280:280/500:#990066FF:hp║元神.75:75/200:#990066CC")

        XCTAssertEqual(game.stats.map { $0.label.components(separatedBy: ".").first ?? $0.label }, structureBeforeCombat)
        XCTAssertEqual(game.stats[3].label, "先天之炁.120")
        XCTAssertEqual(game.stats[3].value, "120/4000")
        XCTAssertEqual(game.statsLayout, layoutBeforeCombat)
    }

    func testCombatStatFrameWithDifferentAttributesCannotReplaceStatusBar() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        let stableValues = (1...10).map { index in
            "属性\(index):\(index)/10:#aa3300:score\(index)"
        }.joined(separator: "║")
        wire.receive("012", "$5,2,22,35#" + stableValues)
        let statsBeforeCombat = game.stats
        let layoutBeforeCombat = game.statsLayout

        wire.receive("016", "你与对手交上了手。")
        wire.receive("012", "$3,3,25,40#姓名：试江青青:100/100:#336666║气血.820:820/850/850:#99FF0000║精神.190:190/200/200:#99990000")

        XCTAssertEqual(game.stats.map(\.label), statsBeforeCombat.map(\.label))
        XCTAssertEqual(game.stats.map(\.value), statsBeforeCombat.map(\.value))
        XCTAssertEqual(game.statsLayout, layoutBeforeCombat)
    }

    func testSkillActionsSurviveDescriptionFrameArrivingAfterButtons() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        wire.onStatus?("已连接", true)

        wire.receive("008", "$1,2,8,25#绝招:perform sword-style target:body")
        wire.receive("007", "选择要使用的武功")

        XCTAssertEqual(game.dialog?.text, "选择要使用的武功")
        XCTAssertEqual(game.dialog?.actions.map(\.command), ["perform sword-style target:body"])
    }

    func testSkillActionsKeepDuplicateCommandsWithDifferentLabels() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        wire.receive("008", "招式甲:perform sword-style$zj#招式乙:perform sword-style")
        XCTAssertEqual(game.dialog?.actions.map(\.label), ["招式甲", "招式乙"])
    }

    func testRedirectAndPagedTextClose() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        wire.receive("900", "127.0.0.1:6667")
        XCTAssertEqual(wire.endpoint, "127.0.0.1:6667")
        wire.receive("013", "第一页")
        let pageID = game.dialog?.id
        game.turnPage(next: true)
        game.turnPage(next: false)
        XCTAssertEqual(game.dialog?.id, pageID)
        game.closeDialog()
        XCTAssertEqual(wire.commands, ["n", "b", "q"])
        wire.receive("900", "broken:0")
        XCTAssertEqual(wire.endpoint, "127.0.0.1:6667")
        wire.receive("007", "对话")
        game.closeDialog()
        XCTAssertEqual(wire.commands, ["n", "b", "q"])
    }

    func testMailPageKeepsServerActions() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        wire.onStatus?("已连接", true)

        wire.receive("008", "上一页:prev$zj#下一页:next$zj#一键删除:mail delete$zj#一键领取:mail receive")
        wire.receive("013", "电子驿站邮件列表")

        XCTAssertEqual(game.dialog?.kind, "pages")
        XCTAssertEqual(game.dialog?.actions.map(\.command), ["prev", "next", "mail delete", "mail receive"])
    }

    func testRouteInlineLinksStayInBodyText() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        wire.receive("007", "寻路\u{001B}[u:cmds:walk]\u{001B}[s:28]\u{001B}[37m[搜索]\u{001B}[0m\u{001B}[u:cmds:recall]\u{001B}[s:28]\u{001B}[36m[回城]\u{001B}[0m")
        XCTAssertEqual(game.dialog?.kind, "pages")
        // Inline links stay in the body text as clickable colored text;
        // they are NOT extracted into footer actions.
        XCTAssertEqual(game.dialog?.actions.map(\.command), [])
        XCTAssertTrue(game.dialog?.text.contains("[搜索]") == true)
        XCTAssertTrue(game.dialog?.text.contains("[回城]") == true)
    }

    func testServerShowRespectsLocalPreferenceAndClearScreen() {
        let saved = UserDefaults.standard.object(forKey: "descriptionHidden")
        defer { UserDefaults.standard.set(saved, forKey: "descriptionHidden") }
        UserDefaults.standard.set(false, forKey: "descriptionHidden")
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        game.toggleDescription()
        wire.receive("023", "显示描述")
        XCTAssertTrue(game.descriptionHidden)
        game.toggleDescription()
        wire.receive("023", "屏蔽描述")
        wire.receive("023", "显示描述")
        XCTAssertFalse(game.descriptionHidden)
        wire.receive(nil, "old")
        wire.receive(nil, "\u{001B}[2Jnew")
        XCTAssertEqual(game.messages.count, 1)
        XCTAssertEqual(game.history.count, 2)
    }

    func testInputSurvivesActionUpdateAndSubmitsValue() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        wire.onStatus?("已连接", true)
        wire.receive("001", "给谁？$zj#give")
        let original = game.dialog?.id
        wire.receive("008", "$2,3,9,30#村长:give elder$zj#村民:give villager")
        XCTAssertEqual(game.dialog?.id, original)
        XCTAssertEqual(game.dialog?.actions.count, 2)
        game.submitInput("elder")
        XCTAssertEqual(wire.commands, ["give elder"])
        XCTAssertNil(game.dialog)
    }

    func testConfirmationExpandsNumberAndSendsOrderedCommands() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        wire.onStatus?("已连接", true)
        wire.receive("010", "数量$dh#numb.$dh#ok11.buy $N$dh#ok11.look")
        game.submitInput("3")
        XCTAssertEqual(wire.commands, ["buy 3", "look"])
    }

    func testNewlineModeMatchesAndroidWireBytes() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        wire.receive("997", "")
        XCTAssertFalse(wire.preservesNewlines)
        XCTAssertEqual(MudText.wireCommand("north\nsouth", preservesNewlines: wire.preservesNewlines), Data("north;south\n".utf8))
        wire.receive("998", "")
        XCTAssertTrue(wire.preservesNewlines)
        XCTAssertEqual(MudText.wireCommand("north\nsouth", preservesNewlines: wire.preservesNewlines), Data("north\nsouth\n".utf8))
        XCTAssertFalse(game.inWorld)
    }

    func testStatsAutomaticColumnsAndNoticeBufferSeparation() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        wire.receive("012", "$0,2,22,35#气血:8/10:#aa3300:hp║内力:5/10:#0000aa:hp║经验:100:#ffffff:score║潜能:30:#ffffff:score")
        XCTAssertEqual(game.statsLayout.columns, 2)
        XCTAssertEqual(game.stats.count, 4)
        XCTAssertEqual(game.stats.first?.fraction, 0.8)
        for i in 0..<60 { wire.receive(nil, "message \(i)") }
        wire.receive("015", "notice")
        XCTAssertEqual(game.messages.count, 50)
        XCTAssertEqual(game.messages.first?.text, "message 10")
        XCTAssertEqual(game.history.count, 61)
        XCTAssertEqual(game.history.last?.text, "notice")
    }

    func testServerShortcutPersistsAndLocalToggleRestoresCustomSlot() {
        let keys = ["button.12.label", "button.12.command", "button.1.label", "button.1.command"]
        let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) { UserDefaults.standard.set(value, forKey: key) }
        }
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        UserDefaults.standard.set("自定动作", forKey: "button.1.label")
        UserDefaults.standard.set("look", forKey: "button.1.command")
        wire.receive("006", "b12:背包:i$zj#b1:服务器动作:score")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "button.12.command"), "i")
        game.toggleCustomButtons()
        XCTAssertEqual(game.buttons.first { $0.slot == "b1" }?.command, "look")
    }

    func testInteractionActionResponseTriggersImmediateRoomRefresh() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        wire.onStatus?("已连接", true)
        game.inWorld = true
        // A mechanism panel (the 巨石 stone door) is an "interaction" dialog.
        wire.receive("007", "【巨石】")
        wire.receive("009", "$2,2,9,43#推一下:move shi")
        XCTAssertEqual(game.dialog?.kind, "interaction")
        game.act("move shi")
        XCTAssertTrue(wire.commands.contains("move shi"))
        XCTAssertFalse(wire.commands.contains("look"))
        // The action's own response arrives; the exit is set server-side, so
        // the client must look immediately instead of waiting 1.8s.
        wire.receive(nil, "你推动巨石，吱吱连声。")
        XCTAssertTrue(wire.commands.contains("look"))
    }

    func testMenuPanelDialogCancelsPendingRoomRefresh() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        wire.onStatus?("已连接", true)
        game.inWorld = true
        // The fly map is also an interaction panel.
        wire.receive("007", "江湖悠悠")
        wire.receive("009", "$3,3,10,35#应天:fly yingtian")
        wire.receive("008", "$1,5,10,35#❃ 门派 ❃:fly 门派$zj#❃ 活动 ❃:fly 活动")
        game.act("fly 门派")
        XCTAssertTrue(wire.commands.contains("fly 门派"))
        // The server answers with a new panel (sect list) — the pending look
        // must be cancelled so it cannot tear the panel down moments later.
        wire.receive("007", "请选择你要前往的门派")
        wire.receive("009", "$3,3,10,35#少林:fly shaolin$zj#武当:fly wudang")
        XCTAssertFalse(wire.commands.contains("look"))
        let fallback = expectation(description: "fallback look window")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { fallback.fulfill() }
        wait(for: [fallback], timeout: 2)
        XCTAssertFalse(wire.commands.contains("look"), "a late look must not close the menu panel")
        XCTAssertEqual(game.dialog?.kind, "interaction")
    }
}
