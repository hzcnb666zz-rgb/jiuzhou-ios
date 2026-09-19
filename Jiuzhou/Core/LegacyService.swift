import Foundation
import CryptoKit

enum LegacyService {
    static let base = URL(string: "http://60.205.8.72")!

    static func registration(account: String, password: String, phone: String, email: String) -> URLRequest {
        let digest = Insecure.MD5.hash(data: Data((account + password + phone + "AP4s3dF5").utf8))
        var url = URLComponents(url: base.appendingPathComponent("mobi/reg.php"), resolvingAgainstBaseURL: false)!
        url.queryItems = [URLQueryItem(name: "id", value: account), URLQueryItem(name: "pass", value: password),
                         URLQueryItem(name: "phone", value: phone), URLQueryItem(name: "email", value: email),
                         URLQueryItem(name: "key", value: digest.map { String(format: "%02x", $0) }.joined())]
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return URLRequest(url: url.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
    }

    static func voiceURL(_ filename: String) -> URL? {
        guard filename.range(of: "^[A-Za-z0-9_-][A-Za-z0-9_.-]*\\.amr$", options: .regularExpression) != nil,
              !filename.contains("..") else { return nil }
        return base.appendingPathComponent("voice").appendingPathComponent(filename)
    }

    static func voiceUpload(_ data: Data, filename: String) -> URLRequest? {
        guard voiceURL(filename) != nil else { return nil }
        let boundary = "Jiuzhou-" + UUID().uuidString
        var request = URLRequest(url: base.appendingPathComponent("upload.php"), timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"uploadfile\";filename=\"\(filename)\"\r\nContent-Type: audio/amr\r\n\r\n".utf8)
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        return request
    }
}
