import XCTest
@testable import JiuzhouProtocol

final class LegacyServiceTests: XCTestCase {
    func testRegistrationEncodesFieldsWithoutInjectingQueryParameters() throws {
        let request = LegacyService.registration(account: "test", password: "p&x=1", phone: "123", email: "a+b@example.com")
        let url = try XCTUnwrap(request.url)
        let fields = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(fields.count, 5)
        XCTAssertEqual(fields.first { $0.name == "pass" }?.value, "p&x=1")
        XCTAssertEqual(fields.first { $0.name == "email" }?.value, "a+b@example.com")
        XCTAssertEqual(fields.first { $0.name == "key" }?.value?.count, 32)
        XCTAssertEqual(url.path, "/mobi/reg.php")
    }

    func testVoiceMultipartUsesAndroidUploadFieldAndExactAudioBytes() throws {
        let audio = Data([35, 33, 65, 77, 82, 10, 0, 255, 0])
        let request = try XCTUnwrap(LegacyService.voiceUpload(audio, filename: "123.amr"))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/upload.php")
        let body = try XCTUnwrap(request.httpBody)
        XCTAssertNotNil(body.range(of: audio))
        XCTAssertNotNil(body.range(of: Data("name=\"uploadfile\";filename=\"123.amr\"".utf8)))
        XCTAssertNil(LegacyService.voiceURL("../private.amr"))
        XCTAssertNil(LegacyService.voiceUpload(audio, filename: "a\r\n.amr"))
    }

    func testAccountUpdateEncodesServerRecordAsOneParameter() throws {
        let request = LegacyService.accountRequest(account: "test", password: "fixture", changes: ["myserver": "九州&127.0.0.1&6666&6667"])
        let url = try XCTUnwrap(request.url)
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(url.path, "/mobi/updateuser.php")
        XCTAssertEqual(query.count, 3)
        XCTAssertEqual(query.last?.value, "九州&127.0.0.1&6666&6667")
        XCTAssertEqual(LegacyService.accountRequest(account: "test", password: "fixture").url?.path, "/mobi/userinfo.php")
    }

    func testStyleStreamRetainsAndResetsFontAndLinks() {
        var stream = MudStyleStream()
        _ = stream.render("\u{001B}[s:20]\u{001B}[u:cmds:look]查看")
        let next = stream.render("继续")
        XCTAssertTrue(next.contains("\u{001B}[s:20]"))
        XCTAssertTrue(next.contains("\u{001B}[u:cmds:look]"))
        _ = stream.render("\u{001B}[2;37;0m普通")
        XCTAssertEqual(stream.render("新文本"), "新文本")
    }
}
