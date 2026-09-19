import Foundation

// Capture inherited spans when a server message arrives, not when SwiftUI redraws it.
struct MudStyleStream {
    private var spans: [String: String] = [:]
    private static let tags = try! NSRegularExpression(pattern: "\u{001B}\\[(?:[0-9;]*m|[fb]#[0-9a-fA-F]{6}m|[us]:[^\\]]*\\])")

    mutating func render(_ text: String) -> String {
        let prefix = ["bold", "fullwidth", "foreground", "background", "size", "link"].compactMap { spans[$0] }.joined()
        let ns = text as NSString
        for match in Self.tags.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: match.range)
            let code = String(tag.dropFirst(2))
            if code.hasPrefix("u:") { spans["link"] = tag }
            else if code.hasPrefix("s:") { spans["size"] = tag }
            else if code.hasPrefix("f#") { spans["foreground"] = tag }
            else if code.hasPrefix("b#") { spans["background"] = tag }
            else {
                let numbers = code.dropLast().split(separator: ";").compactMap { Int($0) }
                if numbers.isEmpty || numbers.contains(0) { spans.removeAll(); continue }
                if numbers == [1] { spans["bold"] = tag }
                if numbers == [9] { spans["fullwidth"] = tag }
                if numbers.contains(where: { (30...37).contains($0) }) { spans["foreground"] = tag }
                if numbers.contains(where: { (40...47).contains($0) }) { spans["background"] = tag }
            }
        }
        return prefix + text
    }
}
