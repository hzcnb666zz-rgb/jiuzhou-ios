import XCTest
@testable import JiuzhouProtocol

final class MudProtocolTests: XCTestCase {
    func testRepeatedCommandsPreserveLabelsOrderAndIdentity() {
        let items = MudText.actions("查看:look$zj#刷新:look$zj#查看:look")
        XCTAssertEqual(items.map(\.label), ["查看", "刷新", "查看"])
        XCTAssertEqual(Set(items.map(\.id)).count, 3)
        let popup = MudText.popupActions("查看|look$z2#刷新|look")
        XCTAssertEqual(popup.count, 2)
        XCTAssertNotEqual(popup[0].id, popup[1].id)
    }

    func testPopupPayloadAndLinkedCommandsDoNotBecomeFrames() {
        let actions = "更多:\u{001B}020交谈|ask elder"
        XCTAssertEqual(MudDecoder.frames("\u{001B}008" + actions), [MudFrame(code: "008", text: actions)])
        XCTAssertEqual(MudText.actions(actions).first?.command, "\u{001B}020交谈|ask elder")
        XCTAssertEqual(MudText.popupActions("$2,2,8,25#交谈|ask elder$z2#观察|look elder").map(\.command), ["ask elder", "look elder"])
        let linked = "\u{001B}[u:cmds:\u{001B}020交谈:ask elder]更多\u{001B}[0m"
        XCTAssertEqual(MudDecoder.frames(linked + "\u{001B}002村庄"), [MudFrame(code: nil, text: linked), MudFrame(code: "002", text: "村庄")])
    }

    func testInputCommandMatchesAndroidInputAndConfirmation() {
        XCTAssertEqual(MudText.inputCommand(template: "give", value: "银两", confirmation: false), "give 银两")
        XCTAssertEqual(MudText.inputCommand(template: "ask $txt# about $txt#", value: "村长", confirmation: false), "ask 村长 about 村长")
        XCTAssertEqual(MudText.inputCommand(template: "buy $N$sock#look", value: "3", confirmation: true), "buy 3$sock#look")
        XCTAssertEqual(MudText.inputCommand(template: "accept", value: "3", confirmation: true), "accept")
    }

    func testActualServerSessionByteByByte() throws {
        let file = try XCTUnwrap(Bundle.module.url(forResource: "local-session", withExtension: "bin", subdirectory: "Fixtures"))
        let bytes = try Data(contentsOf: file)
        var whole = MudDecoder()
        let expected = try whole.feed(bytes)
        var fragmented = MudDecoder()
        var actual: [MudFrame] = []
        for byte in bytes { actual += try fragmented.feed(Data([byte])) }
        XCTAssertEqual(actual, expected)
        XCTAssertTrue(actual.contains { $0.code == "000" && $0.text == "0007" })
        XCTAssertTrue(actual.contains { $0.code == "002" && MudText.plain($0.text) == "未明谷" })
        XCTAssertTrue(actual.contains { $0.code == "008" && !MudText.actions($0.text).isEmpty })
        XCTAssertTrue(actual.contains { $0.code == "002" && MudText.plain($0.text).contains("洗心池") })
    }

    func testEveryByteBoundaryIncludingChineseAndTelnet() throws {
        let wire = Data([255, 253, 24]) + Data("\nver1.0,challenge\r\n\u{1B}002未明谷\r\n\u{1B}004溪水\u{1B}008交谈:ask elder\n".utf8)
        var whole = MudDecoder()
        let expected = try whole.feed(wire)
        XCTAssertEqual(whole.replies, Data([255, 252, 24]))
        for split in 0...wire.count {
            var decoder = MudDecoder()
            let first = try decoder.feed(Data(wire.prefix(split)))
            let second = try decoder.feed(Data(wire.dropFirst(split)))
            XCTAssertEqual(first + second, expected, "split at \(split)")
        }
        XCTAssertEqual(expected.last, MudFrame(code: "008", text: "交谈:ask elder"))
    }

    func testSubnegotiationCannotLeakIntoUTF8() throws {
        var decoder = MudDecoder()
        var output: [MudFrame] = []
        for byte in [UInt8(255), 250, 24, 1, 65, 255, 240] + Array("\u{1B}002未明谷\n".utf8) {
            output += try decoder.feed(Data([byte]))
        }
        XCTAssertEqual(output, [MudFrame(code: "002", text: "未明谷")])
    }

    func testLayoutAndCommandColons() {
        XCTAssertEqual(MudText.actions("$2,3,9,30#查看:look npc:123$zj#交谈:ask npc"), [
            MudAction(label: "查看", command: "look npc:123"), MudAction(label: "交谈", command: "ask npc")])
        XCTAssertEqual(MudText.actions("south:青石桥头$zj#east:树林:go east", exits: true), [
            MudAction(label: "青石桥头", command: "south", slot: "south"),
            MudAction(label: "树林", command: "go east", slot: "east")])
    }

    func testZeroLayoutUsesAndroidAutomaticColumns() {
        let layout = MudLayout("$0,3,9,30#")
        XCTAssertEqual(layout.resolvedColumns(for: 6), 3)
        XCTAssertEqual(layout.resolvedColumns(for: 5), 2)
        XCTAssertEqual(layout.resolved(for: 6).columns, 3)
    }

    func testColorsDoNotConsumeFollowingText() {
        XCTAssertEqual(MudText.plain("\u{1B}[31m红色\u{1B}[0m正常\u{1B}[s:16]标题$br#下一行"), "红色正常标题\n下一行")
        XCTAssertEqual(MudText.actions("\u{1B}[s:16]人物:look me").first?.label, "人物")
    }

    func testKnownInlinePageLinksBecomeFixedActions() {
        let text = "\u{001B}[u:cmds:walk]\u{001B}[s:28]\u{001B}[1;37m[搜索]\u{001B}[0m\t\u{001B}[u:cmds:recall]\u{001B}[s:28]\u{001B}[36m[回城]\u{001B}[0m"
        XCTAssertEqual(MudText.inlinePageActions(text).map(\.label), ["[搜索]", "[回城]"])
        XCTAssertEqual(MudText.inlinePageActions(text).map(\.command), ["walk", "recall"])
        XCTAssertEqual(MudText.plain(MudText.removingInlinePageActions("寻路" + text)), "寻路")
    }

    func testCommandNormalizationOnlyRemovesExertTwice() {
        XCTAssertEqual(MudText.normalizedCommand("exert force.powerup twice"), "exert force.powerup")
        XCTAssertEqual(MudText.normalizedCommand("perform sword.foo twice"), "perform sword.foo twice")
        XCTAssertEqual(MudText.normalizedCommand("perform sword.foo target:body"), "perform sword.foo target:body")
    }

    func testMalformedAndEmptyRecords() throws {
        var decoder = MudDecoder()
        XCTAssertEqual(try decoder.feed(Data("\r\n\u{1B}008\n".utf8)), [MudFrame(code: "008", text: "")])
        XCTAssertTrue(MudText.actions("broken$zj#: ").count <= 1)
        XCTAssertTrue(MudText.actions("").isEmpty)
    }
}
