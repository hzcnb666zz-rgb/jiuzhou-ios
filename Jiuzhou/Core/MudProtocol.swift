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
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
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
    var id: String { command }
    let label: String
    let command: String
    var slot: String = ""
}

enum MudText {
    static func plain(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\u{001B}\\[[us]:[^\\]]*\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\u{001B}\\[[0-9;]*m", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\u{001B}\\[[fb]#[0-9A-Fa-f]{6}m", with: "", options: .regularExpression)
            .replacingOccurrences(of: "$br#", with: "\n")
            .replacingOccurrences(of: "\u{001B}", with: "")
    }

    static func withoutLayout(_ raw: String) -> String {
        raw.replacingOccurrences(of: "^\\$[0-9,]+#", with: "", options: .regularExpression)
    }

    static func actions(_ raw: String, exits: Bool = false, slots: Bool = false) -> [MudAction] {
        var seen = Set<String>()
        return withoutLayout(raw).components(separatedBy: "$zj#").compactMap { entry in
            // Strip styling before locating separators (style tags can contain colons).
            let parts = plain(entry).split(separator: ":", maxSplits: slots || exits ? 2 : 1,
                                          omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2 else { return nil }
            let command = slots ? (parts.count == 3 ? parts[2] : "") :
                (exits ? (parts.count == 3 ? parts[2] : parts[0]) : parts[1])
            guard !command.isEmpty, seen.insert(command).inserted else { return nil }
            return MudAction(label: slots || exits ? parts[1] : parts[0], command: command,
                             slot: slots || exits ? parts[0] : "")
        }
    }
}
