import SwiftUI

private struct MudDisplayWidthKey: EnvironmentKey { static let defaultValue: CGFloat = 390 }
extension EnvironmentValues {
    var mudDisplayWidth: CGFloat {
        get { self[MudDisplayWidthKey.self] }
        set { self[MudDisplayWidthKey.self] = newValue }
    }
}

struct MudRichText: View {
    let raw: String
    let send: (String) -> Void
    @Environment(\.mudDisplayWidth) private var displayWidth
    @AppStorage("androidMode") private var mode = "night"

    var body: some View {
        Text(attributed)
            .environment(\.openURL, OpenURLAction { url in
                if ["http", "https"].contains(url.scheme ?? "") { return .systemAction }
                guard url.scheme == "mudcmd",
                      let command = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "command" })?.value else { return .discarded }
                send(command)
                return .handled
            })
    }

    private var attributed: AttributedString {
        let text = raw.replacingOccurrences(of: "$br#", with: "\n")
            .replacingOccurrences(of: "\u{001B}[2J", with: "").replacingOccurrences(of: "\u{001B}[H", with: "")
        let ns = text as NSString
        let pattern = "\u{001B}\\[(?:[0-9;]*m|[fb]#[0-9a-fA-F]{6}m|[us]:[^\\]]*\\])"
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return AttributedString(MudText.plain(text)) }
        var result = AttributedString()
        var cursor = 0
        var color: Color?
        var link: URL?
        var size: Double?
        var background: Color?
        var bold = false
        var fullwidth = false
        func rgb(_ value: UInt32) -> Color {
            Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
        }
        func append(_ string: String) {
            let rendered = fullwidth ? String(String.UnicodeScalarView(string.unicodeScalars.map { scalar in
                scalar.value == 32 ? UnicodeScalar(0x3000)! : (33...126).contains(scalar.value) ? UnicodeScalar(scalar.value + 65248)! : scalar
            })) : string
            var part = AttributedString(rendered)
            part.foregroundColor = color
            part.backgroundColor = background
            part.link = link
            if link != nil { part.underlineStyle = .single }
            if let size { part.font = .system(size: size, weight: bold ? .bold : .regular) }
            else if bold { part.inlinePresentationIntent = .stronglyEmphasized }
            result += part
        }
        for match in expression.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            append(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            let code = String(ns.substring(with: match.range).dropFirst(2))
            if code.hasPrefix("u:") {
                let target = String(code.dropFirst(2).dropLast())
                if target.hasPrefix("cmds:") || target.hasPrefix("pops:") {
                    var components = URLComponents()
                    components.scheme = "mudcmd"
                    components.host = "send"
                    components.queryItems = [URLQueryItem(name: "command", value: (target.hasPrefix("pops:") ? "\u{001B}020" : "") + String(target.dropFirst(5)))]
                    link = components.url
                } else { link = URL(string: target) }
            } else if code.hasPrefix("s:") {
                // Android sizes are screen-width divisors, not point sizes.
                let divisor = Double(code.dropFirst(2).dropLast()) ?? 30
                size = Double(displayWidth) / max(1, divisor)
            } else if code.hasPrefix("f#"), let hex = UInt32(code.dropFirst(2).dropLast(), radix: 16) {
                color = Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
            } else if code.hasPrefix("b#"), let hex = UInt32(code.dropFirst(2).dropLast(), radix: 16) {
                background = rgb(hex)
            } else if code.hasSuffix("m") {
                let numbers = code.dropLast().split(separator: ";").compactMap { Int($0) }
                if numbers.isEmpty || numbers.contains(0) { color = nil; link = nil; size = nil; background = nil; bold = false; fullwidth = false }
                else {
                    let normal: [UInt32] = [0x000000,0xaa3300,0x00bb00,0xeeee00,0x0000aa,0xaa00aa,0x00bbbb,0xaaaaaa]
                    let bright: [UInt32] = [0x000000,0xff3300,0x88ff00,0xffff00,0x0000ff,0xff00ff,0x88ffff,0xffffff]
                    let bg: [UInt32] = [0x222222,0xaa0000,0x00aa00,0xaaaa00,0x0000ff,0xaa00aa,0x00aaaa,0xaaaaaa]
                    let brightBg: [UInt32] = [0x000000,0xff0000,0x00ff00,0xffff00,0x0000ff,0xff00ff,0x00ffff,0xffffff]
                    if numbers == [1] { bold = true }
                    if numbers == [9] { fullwidth = true }
                    for number in numbers {
                        if (30...37).contains(number) {
                            let index = mode == "day" && [32,33,36,37].contains(number) ? 4 : number - 30
                            color = rgb((numbers.contains(1) ? bright : normal)[index])
                        } else if (40...47).contains(number) {
                            background = rgb((numbers.contains(1) ? brightBg : bg)[number - 40])
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
