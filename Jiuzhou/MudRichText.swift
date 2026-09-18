import SwiftUI

struct MudRichText: View {
    let raw: String
    let send: (String) -> Void

    var body: some View {
        Text(attributed)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "mudcmd",
                      let command = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "command" })?.value else { return .discarded }
                send(command)
                return .handled
            })
    }

    private var attributed: AttributedString {
        let text = raw.replacingOccurrences(of: "$br#", with: "\n")
        let ns = text as NSString
        let pattern = "\u{001B}\\[(?:[0-9;]*m|[fb]#[0-9a-fA-F]{6}m|[us]:[^\\]]*\\])"
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return AttributedString(MudText.plain(text)) }
        var result = AttributedString()
        var cursor = 0
        var color: Color?
        var link: URL?
        var size: Double?
        func append(_ string: String) {
            var part = AttributedString(string)
            part.foregroundColor = color
            part.link = link
            if let size { part.font = .system(size: size) }
            result += part
        }
        for match in expression.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            append(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            let code = String(ns.substring(with: match.range).dropFirst(2))
            if code.hasPrefix("u:") {
                let target = String(code.dropFirst(2).dropLast())
                if target.hasPrefix("cmds:") {
                    var components = URLComponents()
                    components.scheme = "mudcmd"
                    components.host = "send"
                    components.queryItems = [URLQueryItem(name: "command", value: String(target.dropFirst(5)))]
                    link = components.url
                } else { link = nil }
            } else if code.hasPrefix("s:") {
                // Android sizes are screen-width divisors, not point sizes.
                let divisor = Double(code.dropFirst(2).dropLast()) ?? 30
                size = min(24, max(11, 390 / max(1, divisor)))
            } else if code.hasPrefix("f#"), let hex = UInt32(code.dropFirst(2).dropLast(), radix: 16) {
                color = Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
            } else if code.hasSuffix("m") {
                let numbers = code.dropLast().split(separator: ";").compactMap { Int($0) }
                if numbers.contains(0) { color = nil; link = nil; size = nil }
                else {
                    for number in numbers {
                        switch number {
                        case 30: color = .gray
                        case 31: color = .red
                        case 32: color = .green
                        case 33: color = .yellow
                        case 34: color = .blue
                        case 35: color = .purple
                        case 36: color = .cyan
                        case 37: color = .white
                        default: break
                        }
                    }
                }
            }
            cursor = NSMaxRange(match.range)
        }
        append(ns.substring(from: cursor))
        return result
    }
}
