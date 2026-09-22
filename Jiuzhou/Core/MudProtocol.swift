import Foundation

struct MudFrame: Equatable {
    let code: String?
    let text: String
}

// TCP can split both Telnet commands and UTF-8 characters between reads.
struct MudDecoder {
    private enum Mode { case text, iac, option(UInt8), sub, subIAC }
    private var mode = Mode.text
    private var line: [UInt8] = []
    private(set) var replies = Data()

    mutating func feed(_ bytes: Data) throws -> [MudFrame] {
        var frames: [MudFrame] = []
        replies.removeAll(keepingCapacity: true)
        for byte in bytes {
            switch mode {
            case .text:
                if byte == 255 { mode = .iac }
                else if byte == 10 {
                    frames += Self.frames(String(decoding: line, as: UTF8.self))
                    line.removeAll(keepingCapacity: true)
                } else if byte != 13 && byte != 0 {
                    line.append(byte)
                    if line.count > 1_048_576 { throw DecodeError.lineTooLong }
                }
            case .iac:
                if byte == 255 { line.append(byte); mode = .text }
                else if byte == 250 { mode = .sub }
                else if (251...254).contains(byte) { mode = .option(byte) }
                else { mode = .text }
            case .option(let verb):
                // Decline binary/compression negotiation; this client consumes UTF-8 text.
                if verb == 251 { replies.append(contentsOf: [255, 254, byte]) }
                if verb == 253 { replies.append(contentsOf: [255, 252, byte]) }
                mode = .text
            case .sub:
                if byte == 255 { mode = .subIAC }
            case .subIAC:
                mode = byte == 240 ? .text : .sub
            }
        }
        return frames
    }

    enum DecodeError: Error { case lineTooLong }

    static func frames(_ text: String) -> [MudFrame] {
        let ns = text as NSString
        let regex = try! NSRegularExpression(pattern: "\u{001B}[0-9]{3}")
        let linkPattern = try! NSRegularExpression(pattern: "\u{001B}\\[u:[^\\]]*\\]")
        let linkRanges = linkPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).map(\.range)
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).filter { match in
            if linkRanges.contains(where: { NSLocationInRange(match.range.location, $0) }) { return false }
            // ESC020 immediately after an action's colon is the popup command payload.
            return !(ns.substring(with: match.range) == "\u{001B}020" && match.range.location > 0 && ns.character(at: match.range.location - 1) == 58)
        }
        guard !matches.isEmpty else { return text.isEmpty ? [] : [MudFrame(code: nil, text: text)] }
        var result: [MudFrame] = []
        if matches[0].range.location > 0 {
            let prefix = ns.substring(to: matches[0].range.location)
            if !MudText.plain(prefix).isEmpty { result.append(MudFrame(code: nil, text: prefix)) }
        }
        for (index, match) in matches.enumerated() {
            let start = NSMaxRange(match.range)
            let end = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
            result.append(MudFrame(code: ns.substring(with: match.range).dropFirst().description,
                                   text: ns.substring(with: NSRange(location: start, length: end - start))))
        }
        return result
    }
}

struct MudAction: Identifiable, Equatable {
    let occurrence = UUID()
    var id: UUID { occurrence }
    let label: String
    let command: String
    var slot: String = ""
    var styledLabel: String? = nil
    var display: String { styledLabel ?? label }

    static func == (lhs: MudAction, rhs: MudAction) -> Bool {
        lhs.label == rhs.label && lhs.command == rhs.command && lhs.slot == rhs.slot && lhs.styledLabel == rhs.styledLabel
    }

    var direction: String? {
        for name in ["north", "south", "east", "west"] where [name, name + "up", name + "down"].contains(slot) { return name }
        return ["northwest", "northeast", "southwest", "southeast"].contains(slot) ? slot : nil
    }
}

struct MudLayout: Equatable {
    var columns = 1
    var widthDivisor = 3
    var heightDivisor = 9
    var fontDivisor = 30
    private(set) var automaticColumns = false

    init(_ raw: String = "", defaults: [Int] = [1, 3, 9, 30]) {
        var values = defaults
        if raw.hasPrefix("$"), let end = raw.firstIndex(of: "#") {
            let parsed = raw[raw.index(after: raw.startIndex)..<end].split(separator: ",").compactMap { Int($0) }
            if parsed.count == 4 { values = parsed }
        }
        automaticColumns = values[0] == 0
        columns = automaticColumns ? 1 : min(12, max(1, values[0]))
        widthDivisor = max(1, values[1])
        heightDivisor = max(1, values[2])
        fontDivisor = max(1, values[3])
    }

    func resolvedColumns(for itemCount: Int) -> Int {
        automaticColumns ? min(12, max(1, itemCount / 2)) : columns
    }

    func resolved(for itemCount: Int) -> MudLayout {
        var copy = self
        copy.columns = resolvedColumns(for: itemCount)
        copy.automaticColumns = false
        return copy
    }
}

enum MudText {
    static func wireCommand(_ command: String, preservesNewlines: Bool) -> Data {
        Data(((preservesNewlines ? command : command.replacingOccurrences(of: "\n", with: ";")) + "\n").utf8)
    }

    static func inputCommand(template: String, value: String, confirmation: Bool) -> String {
        if confirmation { return template.replacingOccurrences(of: "$N", with: value).replacingOccurrences(of: "$txt#", with: value) }
        if template.contains("$txt#") { return template.replacingOccurrences(of: "$txt#", with: value) }
        return template + " " + value
    }

    static func normalizedCommand(_ command: String) -> String {
        let parts = command.split { $0 == " " || $0 == "\t" }
        // The old saved Huashan button is "exert force.powerup twice".
        // "twice" belongs to perform, while exert has no such argument.
        if parts.count == 3, parts[0] == "exert", parts[2] == "twice" {
            return String(parts[0]) + " " + String(parts[1])
        }
        return command
    }

    static func plain(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\u{001B}\\[[us]:[^\\]]*\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\u{001B}\\[[0-9;]*m", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\u{001B}\\[[fb]#[0-9A-Fa-f]{6}m", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\u{001B}\\[(?:2J|H)", with: "", options: .regularExpression)
            .replacingOccurrences(of: "$br#", with: "\n")
            .replacingOccurrences(of: "\u{001B}", with: "")
    }

    static func withoutLayout(_ raw: String) -> String {
        raw.replacingOccurrences(of: "^\\$[0-9,]+#", with: "", options: .regularExpression)
    }

    static func popupActions(_ raw: String) -> [MudAction] {
        withoutLayout(raw).components(separatedBy: "$z2#").compactMap { entry in
            let fields = entry.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 2 else { return nil }
            return MudAction(label: plain(fields[0]), command: fields[1], styledLabel: fields[0])
        }
    }

    static func inlinePageActions(_ raw: String) -> [MudAction] {
        let linkPattern = "\u{001B}\\[u:([^\\]]*)\\]"
        let controlPattern = "\u{001B}\\[(?:[us]:[^\\]]*\\]|[fb]#[0-9A-Fa-f]{6}m|[0-9;]*m)"
        guard let links = try? NSRegularExpression(pattern: linkPattern),
              let controls = try? NSRegularExpression(pattern: controlPattern) else { return [] }
        let ns = raw as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let allowedLabels = Set(["上一页", "下一页", "搜索", "回城", "门派", "家园", "一键删除", "一键领取", "添加草稿", "返回"])
        var result: [MudAction] = []

        for match in links.matches(in: raw, range: fullRange) {
            let target = ns.substring(with: match.range(at: 1))
            var cursor = NSMaxRange(match.range)
            while cursor < ns.length {
                let rest = ns.substring(from: cursor)
                if rest.hasPrefix("$br#") || rest.hasPrefix("\n") || rest.hasPrefix("\r") { break }
                let remaining = NSRange(location: cursor, length: ns.length - cursor)
                if let control = controls.firstMatch(in: raw, range: remaining), control.range.location == cursor {
                    cursor = NSMaxRange(control.range)
                    continue
                }
                let character = ns.substring(with: NSRange(location: cursor, length: 1))
                if character == " " || character == "\t" { cursor += 1; continue }
                break
            }
            let labelStart = cursor
            while cursor < ns.length {
                let character = ns.substring(with: NSRange(location: cursor, length: 1))
                if character == "\u{001B}" || character == "\n" || character == "\r" || ns.substring(from: cursor).hasPrefix("$br#") { break }
                cursor += 1
            }
            let label = plain(ns.substring(with: NSRange(location: labelStart, length: cursor - labelStart)))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let key = label.trimmingCharacters(in: CharacterSet(charactersIn: "[]()"))
            guard allowedLabels.contains(key) else { continue }

            let command: String
            if target.hasPrefix("cmds:") { command = String(target.dropFirst(5)) }
            else if target.hasPrefix("pops:") { command = "\u{001B}020" + String(target.dropFirst(5)) }
            else { continue }
            guard !command.isEmpty, !result.contains(where: { $0.command == command }) else { continue }
            result.append(MudAction(label: label, command: command))
        }
        return result
    }

    static func removingInlinePageActions(_ raw: String) -> String {
        let linkPattern = "\u{001B}\\[u:([^\\]]*)\\]"
        let controlPattern = "\u{001B}\\[(?:[us]:[^\\]]*\\]|[fb]#[0-9A-Fa-f]{6}m|[0-9;]*m)"
        guard let links = try? NSRegularExpression(pattern: linkPattern),
              let controls = try? NSRegularExpression(pattern: controlPattern) else { return raw }

        let ns = raw as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let allowedLabels = Set(["上一页", "下一页", "搜索", "回城", "门派", "家园", "一键删除", "一键领取", "添加草稿", "返回"])
        var removals: [NSRange] = []

        for match in links.matches(in: raw, range: fullRange) {
            let target = ns.substring(with: match.range(at: 1))
            guard target.hasPrefix("cmds:") || target.hasPrefix("pops:") else { continue }
            var cursor = NSMaxRange(match.range)
            while cursor < ns.length {
                let rest = ns.substring(from: cursor)
                if rest.hasPrefix("$br#") || rest.hasPrefix("\n") || rest.hasPrefix("\r") { break }
                let remaining = NSRange(location: cursor, length: ns.length - cursor)
                if let control = controls.firstMatch(in: raw, range: remaining), control.range.location == cursor {
                    cursor = NSMaxRange(control.range)
                    continue
                }
                let character = ns.substring(with: NSRange(location: cursor, length: 1))
                if character == " " || character == "\t" { cursor += 1; continue }
                break
            }
            let labelStart = cursor
            while cursor < ns.length {
                let character = ns.substring(with: NSRange(location: cursor, length: 1))
                if character == "\u{001B}" || character == "\n" || character == "\r" || ns.substring(from: cursor).hasPrefix("$br#") { break }
                cursor += 1
            }
            let label = plain(ns.substring(with: NSRange(location: labelStart, length: cursor - labelStart)))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let key = label.trimmingCharacters(in: CharacterSet(charactersIn: "[]()"))
            if allowedLabels.contains(key) {
                removals.append(NSRange(location: match.range.location, length: cursor - match.range.location))
            }
        }

        var result = raw
        for range in removals.sorted(by: { $0.location > $1.location }) {
            result = (result as NSString).replacingCharacters(in: range, with: "")
        }
        // A tab is only a visual separator between adjacent inline links. Once
        // those links are promoted to fixed actions, do not leave the separator
        // behind in the page description.
        result = result.replacingOccurrences(of: "\\t(?=\u{001B}\\[u:)", with: "", options: .regularExpression,
                                              range: nil)
        return result
    }

    static func actions(_ raw: String, exits: Bool = false, slots: Bool = false) -> [MudAction] {
        return withoutLayout(raw).components(separatedBy: "$zj#").compactMap { entry in
            // A colon inside an ANSI link/size tag is not an action separator.
            let tag = try! NSRegularExpression(pattern: "\u{001B}\\[[us]:[^\\]]*\\]")
            let protected = NSMutableString(string: entry)
            for match in tag.matches(in: entry, range: NSRange(location: 0, length: protected.length)).reversed() {
                protected.replaceCharacters(in: match.range, with: protected.substring(with: match.range).replacingOccurrences(of: ":", with: "\u{E000}"))
            }
            let parts = (protected as String).split(separator: ":", maxSplits: slots || exits ? 2 : 1,
                    omittingEmptySubsequences: false).map { String($0).replacingOccurrences(of: "\u{E000}", with: ":") }
            guard parts.count >= 2 else { return nil }
            let command = slots ? (parts.count == 3 ? parts[2] : "") :
                (exits ? (parts.count == 3 ? parts[2] : parts[0]) : parts[1])
            let slot = slots || exits ? plain(parts[0]) : ""
            guard !command.isEmpty else { return nil }
            let label = slots || exits ? parts[1] : parts[0]
            let clean = plain(label)
            return MudAction(label: clean, command: command, slot: slot,
                             styledLabel: clean == label ? nil : label)
        }
    }
}
