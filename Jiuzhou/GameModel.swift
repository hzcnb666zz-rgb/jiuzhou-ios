import Foundation
import Combine

struct GameMessage: Identifiable {
    let id = UUID()
    let text: String
}

struct GameDialog: Identifiable {
    let id = UUID()
    var text = ""
    var actions: [MudAction] = []
    var secondary: [MudAction] = []
    var inputCommand: String?
    var numeric = false
    var layout = MudLayout()
    var secondaryLayout = MudLayout()
    var kind = "interaction"
}

struct GameStat: Identifiable {
    var id: String { label }
    let label: String
    let value: String
    let color: String
    let command: String
    var fraction: Double {
        let values = value.split(separator: "/").compactMap { Double($0) }
        guard let first = values.first, let last = values.last, values.count > 1, last > 0 else { return 1 }
        return min(1, max(0, first / last))
    }
}

final class GameModel: ObservableObject {
    @Published var host = UserDefaults.standard.string(forKey: "host") ?? "10.220.35.229"
    @Published var port = UserDefaults.standard.string(forKey: "port") ?? "6666"
    @Published var account = UserDefaults.standard.string(forKey: "account") ?? ""
    @Published var password = ""
    @Published var status = "未连接"
    @Published var connected = false
    @Published var connecting = false
    @Published var inWorld = false
    @Published var needsCharacter = false
    @Published var room = "九州书剑录"
    @Published var description = ""
    @Published var objects: [MudAction] = []
    @Published var exits: [MudAction] = []
    @Published var topActions: [MudAction] = []
    @Published var buttons: [MudAction] = []
    @Published var stats: [GameStat] = []
    @Published var messages: [GameMessage] = []
    @Published var dialog: GameDialog?
    @Published var notice = ""
    @Published var chatMessages: [GameMessage] = []
    @Published var fightMessages: [GameMessage] = []
    @Published var history: [GameMessage] = []
    @Published var fighting = false
    @Published var descriptionHidden = UserDefaults.standard.bool(forKey: "descriptionHidden")
    @Published var customButtonsVisible = false
    @Published var objectHealth: [String: Double] = [:]
    @Published var statsLayout = MudLayout("", defaults: [2, 2, 22, 35])
    private let transport: MudTransporting
    private var sentCredentials = false

    func toggleDescription() {
        descriptionHidden.toggle()
        UserDefaults.standard.set(descriptionHidden, forKey: "descriptionHidden")
    }

    func closeDialog() {
        let pages = dialog?.kind == "pages"
        dialog = nil
        if pages { transport.send("q") }
    }

    func toggleCustomButtons() {
        buttons.removeAll { action in
            guard let slot = Int(action.slot.dropFirst()) else { return false }
            return (1...11).contains(slot)
        }
        for slot in 1...11 {
            buttons.append(MudAction(label: UserDefaults.standard.string(forKey: "button.\(slot).label") ?? (slot == 11 ? "观察" : "长按"),
                                     command: UserDefaults.standard.string(forKey: "button.\(slot).command") ?? (slot == 11 ? "look" : ""), slot: "b\(slot)"))
        }
        customButtonsVisible.toggle()
    }

    init(transport: MudTransporting = MudTransport()) {
        self.transport = transport
        transport.onFrame = { [weak self] in self?.receive($0) }
        transport.onStatus = { [weak self] text, ready in
            self?.status = text
            self?.connected = ready
            if ready || !text.hasPrefix("等待网络") && text != "正在连接" { self?.connecting = false }
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-check-world") {
            connected = true; inWorld = true; room = "未明谷"
            description = "这里是未明谷。清溪沿着山脚流过，石阶通向村中。"
            objects = [MudAction(label: "老村长", command: "look elder"), MudAction(label: "村民", command: "look villager")]
            exits = [MudAction(label: "青石桥", command: "south", slot: "south"), MudAction(label: "山路", command: "north", slot: "north")]
            messages = [GameMessage(text: "你来到未明谷。"), GameMessage(text: "老村长向你点了点头。")]
            stats = [GameStat(label: "气血", value: "80/100", color: "#aa3300", command: "hp"), GameStat(label: "内力", value: "50/100", color: "#0000aa", command: "hp")]
            if ProcessInfo.processInfo.arguments.contains("--ui-check-dialog") {
                dialog = GameDialog(text: "\u{001B}[1;32m老村长\u{001B}[0m$br#你想打听什么？", actions: MudText.actions("交谈|未明谷的故事:ask elder$zj#交易|查看随身物品:list elder"), layout: MudLayout("$2,3,9,30#"))
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-check-input") {
                dialog = GameDialog(text: "你想对老村长说些什么？", inputCommand: "say $txt#")
            }
        }
        #endif
    }

    func login() {
        guard account.range(of: "^[A-Za-z][A-Za-z0-9]{3,19}$", options: .regularExpression) != nil,
              !password.isEmpty, !password.contains(where: { "║\r\n".contains($0) }),
              let number = UInt16(port), number > 0, !host.trimmingCharacters(in: .whitespaces).isEmpty else {
            status = "账号需为4至20位字母数字，以字母开头；请填写密码和有效地址端口"
            return
        }
        UserDefaults.standard.set(host, forKey: "host")
        UserDefaults.standard.set(port, forKey: "port")
        UserDefaults.standard.set(account, forKey: "account")
        sentCredentials = false
        needsCharacter = false
        inWorld = false
        dialog = nil
        objects = []; exits = []; buttons = []; topActions = []; stats = []; messages = []
        description = ""; notice = ""
        chatMessages = []; fightMessages = []; history = []; objectHealth = [:]
        fighting = false; customButtonsVisible = false
        connecting = true
        transport.connect(host: host.trimmingCharacters(in: .whitespaces), port: number)
    }

    func logout() {
        transport.disconnect()
        connected = false; connecting = false; inWorld = false; needsCharacter = false
        dialog = nil; status = "未连接"
    }

    func createCharacter(name: String, gender: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.range(of: "^[\\u4E00-\\u9FFF]{2,4}$", options: .regularExpression) != nil else {
            notice = "请输入2至4个汉字的角色名"; return
        }
        transport.send(gender + "║║" + name)
    }

    func act(_ command: String) {
        guard connected, !command.isEmpty else { return }
        if command.hasPrefix("\u{001B}020") {
            dialog = GameDialog(actions: MudText.actions(String(command.dropFirst(4))))
        } else if command.contains("$txt#") {
            // Let the server produce its INPUTTXT prompt, matching the Android client.
            transport.send(command)
        } else {
            dialog = nil
            command.components(separatedBy: "$sock#").filter { !$0.isEmpty }.forEach(transport.send)
        }
    }

    func submitInput(_ value: String) {
        guard let template = dialog?.inputCommand, !value.isEmpty,
              !value.contains(where: { "\r\n".contains($0) }) else { return }
        let command = MudText.inputCommand(template: template, value: value, confirmation: dialog?.numeric == true)
        act(command)
    }

    private func log(_ text: String) {
        if text.contains("\u{001B}[2J") { messages = [] }
        let clean = MudText.plain(text)
        guard !clean.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        messages.append(GameMessage(text: text))
        if messages.count > 50 { messages.removeFirst(messages.count - 50) }
        history.append(GameMessage(text: text))
        if history.count > 500 { history.removeFirst(history.count - 500) }
    }

    private func merge(_ additions: [MudAction], into current: [MudAction]) -> [MudAction] {
        var result = current
        for action in additions {
            if let index = result.firstIndex(where: { $0.id == action.id }) { result[index] = action }
            else { result.append(action) }
        }
        return result
    }

    private func receive(_ frame: MudFrame) {
        let text = frame.text
        if frame.code == nil {
            if text.hasPrefix("ver1.0,") { transport.send("local") }
            else if text == "版本验证成功", !sentCredentials {
                sentCredentials = true
                transport.send(account + "║" + password + "║123456789abcd║local@localhost")
            } else {
                log(text)
                if !inWorld { status = MudText.plain(text) }
            }
            return
        }
        switch frame.code {
        case "000":
            if text == "0008" { needsCharacter = true }
            if text == "0007" {
                needsCharacter = false; inWorld = true; status = "已进入江湖"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    if self?.connected == true && self?.inWorld == true { self?.transport.send("look") }
                }
            }
            if text == "0003" { transport.send(password) }
            if text == "重连完毕" { transport.send("look") }
        case "001":
            let parts = text.components(separatedBy: "$zj#")
            if parts.count >= 2 { dialog = GameDialog(text: parts[0], inputCommand: parts[1]) }
        case "002":
            room = text; objects = []; exits = []; dialog = nil
            fighting = false; customButtonsVisible = false; objectHealth = [:]
        case "003": exits = merge(MudText.actions(text, exits: true), into: exits)
        case "004": description = text
        case "005": objects = merge(MudText.actions(text), into: objects)
        case "006":
            for button in MudText.actions(text, slots: true) {
                buttons.removeAll { $0.slot == button.slot }
                buttons.append(button)
                if let slot = Int(button.slot.dropFirst()), (12...17).contains(slot) {
                    UserDefaults.standard.set(button.display, forKey: "button.\(slot).label")
                    UserDefaults.standard.set(button.command, forKey: "button.\(slot).command")
                }
                if let slot = Int(button.slot.dropFirst()), (1...10).contains(slot) { customButtonsVisible = true }
            }
            buttons.sort { (Int($0.slot.dropFirst()) ?? 0) < (Int($1.slot.dropFirst()) ?? 0) }
        case "007": dialog = GameDialog(text: text)
        case "008", "009":
            var next = dialog ?? GameDialog()
            if frame.code == "008" { next.actions = MudText.actions(text); next.layout = MudLayout(text) }
            else { next.secondary = MudText.actions(text); next.secondaryLayout = MudLayout(text) }
            dialog = next
        case "010": receiveConfirmation(text)
        case "011", "013": dialog = GameDialog(text: text, kind: frame.code == "011" ? "map" : "pages")
        case "012":
            let count = MudText.withoutLayout(text).components(separatedBy: "║").count
            statsLayout = MudLayout(text, defaults: [max(1, count / 2), 2, 22, 35])
            if text.hasPrefix("$0,") { statsLayout.columns = max(1, count / 2) }
            stats = MudText.withoutLayout(text).components(separatedBy: "║").compactMap { entry in
                let parts = entry.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 3 else { return nil }
                return GameStat(label: parts[0], value: parts[1], color: parts[2],
                                command: parts.count > 3 ? parts[3] : "")
            }
        case "014": transport.send(text)
        case "015":
            notice = MudText.plain(text)
            history.append(GameMessage(text: text))
            if history.count > 500 { history.removeFirst(history.count - 500) }
            if !inWorld { status = notice }
        case "016":
            fighting = true
            fightMessages.append(GameMessage(text: text))
            if fightMessages.count > 50 { fightMessages.removeFirst() }
            history.append(GameMessage(text: text))
            if history.count > 500 { history.removeFirst() }
        case "100":
            chatMessages.append(GameMessage(text: text))
            if chatMessages.count > 500 { chatMessages.removeFirst() }
        case "024": notice = MudText.plain(text)
        case "017": fighting = false; fightMessages = []
        case "022":
            let parts = text.components(separatedBy: "$zj#")
            if parts.count == 2 {
                let values = parts[1].split(separator: "/").compactMap { Double($0) }
                if values.count >= 2, let maximum = values.last, maximum > 0 {
                    objectHealth[parts[0]] = min(1, max(0, values[0] / maximum))
                }
            }
        case "023":
            if text == "屏蔽描述" { descriptionHidden = true }
            else if !UserDefaults.standard.bool(forKey: "descriptionHidden") { descriptionHidden = false }
        case "020": dialog = GameDialog(actions: MudText.actions(text))
        case "021": topActions = MudText.actions(text)
        case "903": exits.removeAll { $0.slot == text || $0.command == text }
        case "997": transport.preservesNewlines = false
        case "998": transport.preservesNewlines = true
        case "900":
            guard let separator = text.lastIndex(of: ":"),
                  let number = UInt16(text[text.index(after: separator)...]), number > 0 else { return }
            let target = String(text[..<separator])
            guard !target.isEmpty else { return }
            host = target; port = String(number); connecting = true
            transport.connect(host: target, port: number)
        case "913": exits = []
        case "905": objects.removeAll { $0.command == text || $0.command == "look " + text }
        case "999": logout()
        default: log(text)
        }
    }

    private func receiveConfirmation(_ text: String) {
        var next = GameDialog()
        var confirm: [String] = []
        for part in text.components(separatedBy: "$dh#") {
            if part.hasPrefix("ok11.") { confirm.append(String(part.dropFirst(5))) }
            else if part.hasPrefix("no11.") { next.secondary.append(MudAction(label: "取消", command: String(part.dropFirst(5)))) }
            else if part.hasPrefix("numb.") { next.numeric = true }
            else { next.text += part + "\n" }
        }
        let command = confirm.joined(separator: "$sock#")
        if next.numeric { next.inputCommand = command }
        else if !command.isEmpty { next.actions = [MudAction(label: "确定", command: command)] }
        dialog = next
    }
}
