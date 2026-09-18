import XCTest
@testable import JiuzhouProtocol

final class MudProtocolTests: XCTestCase {
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

    func testColorsDoNotConsumeFollowingText() {
        XCTAssertEqual(MudText.plain("\u{1B}[31m红色\u{1B}[0m正常\u{1B}[s:16]标题$br#下一行"), "红色正常标题\n下一行")
        XCTAssertEqual(MudText.actions("\u{1B}[s:16]人物:look me").first?.label, "人物")
    }

    func testMalformedAndEmptyRecords() throws {
        var decoder = MudDecoder()
        XCTAssertEqual(try decoder.feed(Data("\r\n\u{1B}008\n".utf8)), [MudFrame(code: "008", text: "")])
        XCTAssertTrue(MudText.actions("broken$zj#: ").count <= 1)
        XCTAssertTrue(MudText.actions("").isEmpty)
    }
}
