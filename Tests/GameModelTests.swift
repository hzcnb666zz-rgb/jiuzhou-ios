import XCTest
@testable import JiuzhouProtocol

private final class RecordingTransport: MudTransporting {
    var onFrame: ((MudFrame) -> Void)?
    var onStatus: ((String, Bool) -> Void)?
    var preservesNewlines = true
    var commands: [String] = []
    var endpoint = ""
    func connect(host: String, port: UInt16) { endpoint = "\(host):\(port)"; onStatus?("已连接", true) }
    func send(_ command: String) { commands.append(command) }
    func disconnect() {}
    func receive(_ code: String?, _ text: String) { onFrame?(MudFrame(code: code, text: text)) }
}

final class GameModelTests: XCTestCase {
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

    func testRedirectAndPagedTextClose() {
        let wire = RecordingTransport()
        let game = GameModel(transport: wire)
        wire.receive("900", "127.0.0.1:6667")
        XCTAssertEqual(wire.endpoint, "127.0.0.1:6667")
        wire.receive("013", "第一页")
        game.closeDialog()
        XCTAssertEqual(wire.commands, ["q"])
        wire.receive("900", "broken:0")
        XCTAssertEqual(wire.endpoint, "127.0.0.1:6667")
        wire.receive("007", "对话")
        game.closeDialog()
        XCTAssertEqual(wire.commands, ["q"])
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
}
