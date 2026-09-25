import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

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
    var rewards: [GameReward] = []
    var experience = ""
    var money = ""
}

struct GameReward: Identifiable {
    let id = UUID()
    let command: String
    let image: String
    let grade: Int
}

struct GameStat: Identifiable {
    let id = UUID()
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
    // Release builds always connect to the rented public server. The fields stay
    // mutable only so protocol tests can inject a local transport in DEBUG.
    @Published var host = "43.139.191.9"
    @Published var port = "6666"
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
    @Published var popup: GameDialog?
    @Published var notice = ""
    @Published var chatMessages: [GameMessage] = []
    @Published var fightMessages: [GameMessage] = []
    @Published var combatEffects: [GameMessage] = []
    @Published var voiceRecorderVisible = false
    @Published var voiceFilename: String?
    @Published var history: [GameMessage] = []
    @Published var fighting = false
    @Published var descriptionHidden = UserDefaults.standard.bool(forKey: "descriptionHidden")
    @Published var descriptionToggleLabel = UserDefaults.standard.bool(forKey: "descriptionHidden") ? "显示" : "-"
    @Published var webURL: URL?
    @Published var customButtonsVisible = false
    @Published var objectHealth: [String: Double] = [:]
    @Published var statsLayout = MudLayout("", defaults: [2, 2, 22, 35])
    private let transport: MudTransporting
    private var sentCredentials = false
    private var styleStream = MudStyleStream()
    private var pendingNPCObjectLook = false
    private let fixedHost = "43.139.191.9"
    private let fixedPort: UInt16 = 6666
    private var stableStats: [GameStat] = []
    private var stableStatsLayout = MudLayout("", defaults: [5, 2, 22, 35])
    // Post-action room refresh: some room mechanisms (e.g. pushing the 巨石
    // stone door) add an exit server-side without pushing an exit frame, so the
    // client must "look" to learn about it. The look is armed only for item /
    // interaction actions and is fired as soon as the server answers the action
    // (or by a short fallback timer). If a new dialog frame arrives first, the
    // action opened a menu panel (fly 门派 / fly 活动 / 定时活动...) and the
    // refresh is cancelled — otherwise the late "look" would tear that panel
    // down right after it appeared.
    private var pendingRoomRefresh = false
    private var roomRefreshTimer: DispatchWorkItem?
    private static let roomRefreshDialogCodes: Set<String> = ["001", "007", "008", "009", "010", "011", "013"]

    // Background / reconnect handling. iOS suspends the process (and freezes
    // the TCP socket) shortly after the app leaves the foreground; after a
    // longer switch the link is usually dead when the user returns. We keep a
    // short background grace window for quick switches, then transparently
    // re-login on resume (the MUD reattaches the net-dead session and sends
    // "重连完毕"), so the player doesn't have to type credentials again.
    private var intentionalDisconnect = false
    private var backgroundedAt: Date?
    private var autoReloginTimer: DispatchWorkItem?
    private var autoReloginAttempts = 0
    #if canImport(UIKit)
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    #endif
    private static let maxAutoReloginAttempts = 6

    private func styledActions(_ text: String, exits: Bool = false, slots: Bool = false) -> [MudAction] {
        MudText.actions(text, exits: exits, slots: slots).map { action in
            var result = action
            result.styledLabel = styleStream.render(action.display)
            return result
        }
    }

    private func styledInlinePageActions(_ text: String) -> [MudAction] {
        MudText.inlinePageActions(text).map { action in
            var result = action
            result.styledLabel = styleStream.render(action.display)
            return result
        }
    }

    private func appendUnique(_ additions: [MudAction], to current: [MudAction]) -> [MudAction] {
        var result = current
        for action in additions where !result.contains(where: { $0.command == action.command }) {
            result.append(action)
        }
        return result
    }

    func toggleDescription() {
        descriptionHidden.toggle()
        descriptionToggleLabel = descriptionHidden ? "显示" : "隐藏"
        UserDefaults.standard.set(descriptionHidden, forKey: "descriptionHidden")
    }

    func closeDialog() {
        let pages = dialog?.kind == "pages"
        dialog = nil
        if pages { transport.send("q") }
    }

    func inspectReward(_ item: GameReward) { transport.send("litem " + item.command) }

    func turnPage(next: Bool) {
        guard dialog?.kind == "pages", connected else { return }
        transport.send(next ? "n" : "b")
    }

    func confirmDialog(_ value: String) {
        guard let current = dialog else { return }
        if current.numeric {
            if !value.isEmpty && current.inputCommand == "" { dialog = nil }
            else { submitInput(value) }
        }
        else if let command = current.actions.first?.command { act(command) }
        else { dialog = nil }
    }

    func cancelConfirmation() {
        let command = dialog?.secondary.first?.command ?? ""
        dialog = nil; popup = nil
        if !command.isEmpty { transport.send(command) }
    }

    func toggleCustomButtons() {
        voiceRecorderVisible = false
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
            guard let self else { return }
            self.status = text
            self.connected = ready
            if ready || !text.hasPrefix("等待网络") && text != "正在连接" { self.connecting = false }
            if !ready { self.handleUnexpectedDisconnect(after: text) }
        }
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.handleBackground() }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.handleForeground() }
        #endif
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
            if ProcessInfo.processInfo.arguments.contains("--ui-check-confirmation") {
                receiveConfirmation("#ffffff你获得了村长赠送的礼物。$br#$exp#经验 100$br#$god#银两 10$br#$obj#gift,missing,2$dh#ok11.accept$dh#no11.cancel")
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-check-popup") { showPopup("交谈|ask elder$z2#观察|look elder") }
            if ProcessInfo.processInfo.arguments.contains("--ui-check-map") {
                dialog = GameDialog(text: "山路$br# |$br#未明谷 -- 村口$br# |$br#青石桥", kind: "map")
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-check-pages") {
                dialog = GameDialog(text: "寻路\u{001B}[u:cmds:prev][上一页]  \u{001B}[u:cmds:next][下一页]$br#\u{001B}[u:cmds:search][搜索]  \u{001B}[u:cmds:recall][回城]$br#未明谷记事$br#清溪沿着山脚流过。", kind: "pages")
            }
            for scene in ["common", "inventory", "item", "player", "npc", "edge"] where ProcessInfo.processInfo.arguments.contains("--ui-check-" + scene) {
                replayParityScene("common")
                if scene == "npc" { pendingNPCObjectLook = true }
                replayParityScene(scene)
            }
            if ProcessInfo.processInfo.arguments.contains("--ui-check-voice") { voiceRecorderVisible = true }
            if ProcessInfo.processInfo.arguments.contains("--ui-check-combat") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.receive(MudFrame(code: "024", text: "伤害 100")) }
            }
        }
        #endif
    }

    func login() {
        guard account.range(of: "^[A-Za-z][A-Za-z0-9]{3,19}$", options: .regularExpression) != nil,
              !password.isEmpty, !password.contains(where: { "║\r\n".contains($0) }) else {
            status = "账号需为4至20位字母数字，以字母开头；请填写密码"
            return
        }
        #if DEBUG
        guard let connectionPort = UInt16(port), connectionPort > 0,
              !host.trimmingCharacters(in: .whitespaces).isEmpty else {
            status = "测试连接地址无效"
            return
        }
        let connectionHost = host.trimmingCharacters(in: .whitespaces)
        #else
        let connectionHost = fixedHost
        let connectionPort = fixedPort
        #endif
        UserDefaults.standard.set(account, forKey: "account")
        sentCredentials = false
        intentionalDisconnect = false
        autoReloginAttempts = 0
        autoReloginTimer?.cancel()
        cancelRoomRefresh()
        styleStream = MudStyleStream(); combatEffects = []
        needsCharacter = false
        inWorld = false
        dialog = nil; popup = nil; webURL = nil
        objects = []; exits = []; buttons = []; topActions = []; stats = []; stableStats = []; messages = []
        description = ""; notice = ""
        chatMessages = []; fightMessages = []; history = []; objectHealth = [:]
        fighting = false; customButtonsVisible = false
        pendingNPCObjectLook = false
        connecting = true
        #if !DEBUG
        host = fixedHost
        port = String(fixedPort)
        #endif
        transport.connect(host: connectionHost, port: connectionPort)
    }

    func logout() {
        intentionalDisconnect = true
        autoReloginTimer?.cancel()
        endBackgroundTask()
        transport.disconnect()
        cancelRoomRefresh()
        connected = false; connecting = false; inWorld = false; needsCharacter = false
        dialog = nil; popup = nil; webURL = nil; status = "未连接"
        combatEffects = []; voiceRecorderVisible = false; voiceFilename = nil
        pendingNPCObjectLook = false
    }

    private var hasSessionCredentials: Bool {
        account.range(of: "^[A-Za-z][A-Za-z0-9]{3,19}$", options: .regularExpression) != nil
            && !password.isEmpty
            && !password.contains(where: { "║\r\n".contains($0) })
    }

    private func handleBackground() {
        backgroundedAt = Date()
        #if canImport(UIKit)
        endBackgroundTask()
        let task = UIApplication.shared.beginBackgroundTask(withName: "JiuzhouKeepAlive") { [weak self] in
            self?.endBackgroundTask()
        }
        backgroundTask = task
        // Release the grace window a little before the OS hard limit; after
        // that the foreground handler rebuilds the connection if needed.
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            guard let self, self.backgroundTask != .invalid else { return }
            self.endBackgroundTask()
        }
        #endif
    }

    private func endBackgroundTask() {
        #if canImport(UIKit)
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
        #endif
    }

    private func handleForeground() {
        endBackgroundTask()
        let elapsed = backgroundedAt.map { Date().timeIntervalSince($0) } ?? 0
        backgroundedAt = nil
        guard inWorld, hasSessionCredentials, !intentionalDisconnect else { return }
        // Beyond the background grace the socket is suspended or dead; also
        // reconnect whenever the transport no longer reports a ready link.
        if elapsed >= 20 || !transport.isReady {
            scheduleAutoRelogin(delay: 0.2)
        }
    }

    private func handleUnexpectedDisconnect(after text: String) {
        // Only react to a hard drop, not "正在连接"/"等待网络" transient states.
        guard text != "正在连接", !text.hasPrefix("等待网络") else { return }
        #if canImport(UIKit)
        guard UIApplication.shared.applicationState == .active else { return }
        #endif
        guard inWorld, hasSessionCredentials, !intentionalDisconnect else { return }
        scheduleAutoRelogin(delay: 1)
    }

    private func scheduleAutoRelogin(delay: TimeInterval) {
        guard !intentionalDisconnect, inWorld, hasSessionCredentials else { return }
        autoReloginTimer?.cancel()
        guard autoReloginAttempts < Self.maxAutoReloginAttempts else {
            status = "多次重连失败，请手动登录"
            connecting = false
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.performAutoRelogin() }
        autoReloginTimer = work
        status = "正在重连…"
        connecting = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func performAutoRelogin() {
        guard !intentionalDisconnect, inWorld, hasSessionCredentials else { return }
        autoReloginAttempts += 1
        sentCredentials = false
        needsCharacter = false
        connecting = true
        #if DEBUG
        guard let connectionPort = UInt16(port), connectionPort > 0,
              !host.trimmingCharacters(in: .whitespaces).isEmpty else {
            status = "测试连接地址无效"; connecting = false; return
        }
        transport.connect(host: host.trimmingCharacters(in: .whitespaces), port: connectionPort)
        #else
        transport.connect(host: fixedHost, port: fixedPort)
        #endif
    }

    private func noteReconnected() {
        autoReloginAttempts = 0
        autoReloginTimer?.cancel()
        connecting = false
    }

    func createCharacter(name: String, gender: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.range(of: "^[\\u4E00-\\u9FFF]{2,4}$", options: .regularExpression) != nil else {
            notice = "请输入2至4个汉字的角色名"; return
        }
        transport.send(gender + "║║" + name)
    }

    func act(_ action: MudAction) {
        if action.label.components(separatedBy: "|").first == "发送语音" {
            voiceRecorderVisible = true; customButtonsVisible = false
            if !action.command.contains("$txt#") { dialog = nil }
        } else { act(action.command) }
    }

    func act(_ command: String) {
        pendingNPCObjectLook = objects.contains { $0.command == command }
        if command.hasPrefix("voice:"), LegacyService.voiceURL(String(command.dropFirst(6))) != nil {
            voiceFilename = String(command.dropFirst(6))
            voiceRecorderVisible = true
            return
        }
        let command = MudText.normalizedCommand(command)
        guard connected, !command.isEmpty else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-check-common"),
           let scene = ["mycmds ofen": "common", "i": "inventory", "look cloth": "item", "look player": "player", "look elder": "npc"][command] {
            dialog = nil
            replayParityScene(scene)
            return
        }
        #endif
        if command.hasPrefix("\u{001B}020") {
            showPopup(String(command.dropFirst(4)))
        } else if command.contains("$txt#") {
            // Let the server produce its INPUTTXT prompt, matching the Android client.
            transport.send(command)
        } else {
            let confirmation = dialog?.kind == "confirmation"
            // Interacting with a scene object can reveal a new exit in the SAME
            // room (e.g. pushing the 巨石 stone door). Such panels are classified
            // as "item" (equipment), "interaction" (generic objects like the
            // stone), or "npc" — not just "item". The server may not push that
            // exit until the next "look", so refresh the room shortly after.
            // "pages" (route/mail lists) and confirmations are excluded.
            let refreshKinds = Set(["item", "interaction"])
            let needsRoomRefresh = dialog.map { refreshKinds.contains($0.kind) } ?? false
            dialog = nil; popup = nil
            if confirmation { command.components(separatedBy: "$sock#").filter { !$0.isEmpty }.forEach(transport.send) }
            else { transport.send(command) }
            if needsRoomRefresh { armRoomRefresh() }
        }
    }

    // The server sets the mechanism's exit synchronously inside the command
    // handler (mumen.c sets exits/south before its 5s close call_out), so the
    // refresh can run the moment the action's own response arrives. A 0.5s
    // fallback covers mechanisms that answer silently.
    private func armRoomRefresh() {
        pendingRoomRefresh = true
        roomRefreshTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.fireRoomRefresh() }
        roomRefreshTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func fireRoomRefresh() {
        roomRefreshTimer = nil
        guard pendingRoomRefresh else { return }
        pendingRoomRefresh = false
        if connected && inWorld { transport.send("look") }
    }

    private func cancelRoomRefresh() {
        pendingRoomRefresh = false
        roomRefreshTimer?.cancel()
        roomRefreshTimer = nil
    }

    func submitInput(_ value: String) {
        guard let template = dialog?.inputCommand, !value.isEmpty,
              !value.contains(where: { "\r\n".contains($0) }) else { return }
        let command = MudText.inputCommand(template: template, value: value, confirmation: dialog?.numeric == true)
        act(command)
    }

    private func log(_ text: String) {
        if text.contains("\u{001B}[2J") { messages = [] }
        let styled = styleStream.render(text)
        let clean = MudText.plain(text)
        guard !clean.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        messages.append(GameMessage(text: styled))
        if messages.count > 50 { messages.removeFirst(messages.count - 50) }
        history.append(GameMessage(text: styled))
        if history.count > 500 { history.removeFirst(history.count - 500) }
    }

    private func merge(_ additions: [MudAction], into current: [MudAction]) -> [MudAction] {
        var result = current
        for action in additions {
            if let index = result.firstIndex(where: { action.direction != nil && $0.direction == action.direction }) { result[index] = action }
            else { result.append(action) }
        }
        return result
    }

    private func receive(_ frame: MudFrame) {
        // A room-refresh look is pending. The action's own response frames
        // (message text with no code) mean the server already finished the
        // command, so the new exit is in place — refresh immediately. If a new
        // dialog frame arrives instead, the action opened a menu panel, so drop
        // the refresh rather than having a late "look" close that panel.
        if pendingRoomRefresh {
            if frame.code == nil {
                fireRoomRefresh()
            } else if let code = frame.code, Self.roomRefreshDialogCodes.contains(code) || code == "002" {
                cancelRoomRefresh()
            }
        }
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
                noteReconnected()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    if self?.connected == true && self?.inWorld == true { self?.transport.send("look") }
                }
            }
            if text == "0003" { transport.send(password) }
            if text == "重连完毕" { noteReconnected(); transport.send("look") }
        case "001":
            let parts = text.components(separatedBy: "$zj#")
            if parts.count >= 2 { dialog = GameDialog(text: styleStream.render(parts[0]), inputCommand: parts[1]) }
        case "002":
            room = styleStream.render(text); objects = []; exits = []; dialog = nil
            combatEffects = []
            voiceRecorderVisible = false
            fighting = false; customButtonsVisible = false; objectHealth = [:]
            pendingNPCObjectLook = false
        case "003": exits = merge(styledActions(text, exits: true), into: exits)
        case "004": description = styleStream.render(text)
        case "005": objects += styledActions(text)
        case "006":
            for button in styledActions(text, slots: true) {
                buttons.removeAll { $0.slot == button.slot }
                buttons.append(button)
                if let slot = Int(button.slot.dropFirst()), (12...17).contains(slot) {
                    UserDefaults.standard.set(button.display, forKey: "button.\(slot).label")
                    UserDefaults.standard.set(button.command, forKey: "button.\(slot).command")
                }
                if let slot = Int(button.slot.dropFirst()), (1...10).contains(slot) { customButtonsVisible = true }
            }
            buttons.sort { (Int($0.slot.dropFirst()) ?? 0) < (Int($1.slot.dropFirst()) ?? 0) }
            applyQuickButtonOverride()
        case "007":
            // Android keeps the description and action frames in one overlay even
            // when the server delivers the action frame first.
            let npc = dialog?.kind == "npc" || (pendingNPCObjectLook && looksLikeNPCDescription(text))
            let item = !npc && (dialog?.kind == "item" || looksLikeItemDescription(text))
            let pageActions = styledInlinePageActions(text)
            let canReuse = dialog?.kind == "pages" || dialog?.kind == "interaction" || dialog?.kind == "npc" || dialog?.kind == "item"
            var next = canReuse ? dialog! : GameDialog()
            // Keep inline page links in the body text so they render as
            // colored clickable text right after the description, matching
            // the Android client. The 008/009 footer buttons carry the
            // actual content grid (destinations, mailbox folders).
            next.text = styleStream.render(text)
            next.kind = npc ? "npc" : (item ? "item" : (pageActions.isEmpty ? "interaction" : "pages"))
            dialog = next
            pendingNPCObjectLook = false
        case "008", "009":
            var next = dialog ?? GameDialog()
            if frame.code == "008" {
                next.actions = styledActions(text)
                next.layout = MudLayout(text)
            } else {
                next.secondary = styledActions(text)
                next.secondaryLayout = MudLayout(text)
            }
            if next.kind == "interaction", pendingNPCObjectLook, looksLikeNPCActionFrame(text) {
                next.kind = "npc"
                pendingNPCObjectLook = false
            }
            dialog = next
            applyTaskPageButtonOverride()
            applyActivityPanelLayout()
        case "010": receiveConfirmation(text)
        case "011": dialog = GameDialog(text: styleStream.render(text), kind: "map")
        case "013":
            // The mail station sends the page text and its action frames separately.
            // Keep inline links in the body; footer buttons come from 008/009.
            let canReuse = dialog?.kind == "pages" || dialog?.kind == "interaction"
            var next = canReuse ? dialog! : GameDialog()
            next.text = styleStream.render(text)
            next.kind = "pages"
            dialog = next
        case "012":
            let count = MudText.withoutLayout(text).components(separatedBy: "║").count
            var layout = MudLayout(text, defaults: [max(1, count / 2), 2, 22, 35]).resolved(for: count)
            // The reference MUD status panel is five columns by two rows for
            // name plus the nine server-provided resource values.
            if count >= 10 { layout.columns = 5 }
            if count == 6 { layout.columns = 3 }
            let updatedStats: [GameStat] = MudText.withoutLayout(text).components(separatedBy: "║").compactMap { entry -> GameStat? in
                let parts = entry.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 3 else { return nil }
                // The status frame names the innate-qi bar "精力" (older frames)
                // or "炁" (current frames). Both are the same 先天之炁 resource;
                // normalize the label so the bar reads "先天之炁" and tracks the
                // real xiantian value instead of a different resource.
                let rawLabel = parts[0]
                let label: String
                if rawLabel.hasPrefix("精力.") || rawLabel == "精力" {
                    label = "先天之炁" + String(rawLabel.dropFirst("精力".count))
                } else if rawLabel.hasPrefix("炁.") || rawLabel == "炁" {
                    label = "先天之炁" + String(rawLabel.dropFirst("炁".count))
                } else {
                    label = rawLabel
                }
                return GameStat(label: label, value: parts[1], color: statDisplayColor(label, serverColor: parts[2]),
                                command: parts.count > 3 ? parts[3] : "")
            }
            // Decide whether this frame establishes the stable status schema
            // or is a transient combat refresh that must map onto it.
            // - Establish when no schema exists yet, or a same/larger frame
            //   arrives while not fighting.
            // - Map when fighting, or a shorter frame arrives (combat format
            //   can precede the fighting flag in the real game).
            let shouldEstablish = stableStats.isEmpty
                || (!fighting && count >= stableStats.count)
            if shouldEstablish {
                statsLayout = layout
                stableStatsLayout = layout
                stableStats = updatedStats
                stats = stableStats
            } else if !stableStats.isEmpty {
                // Combat label bases map onto stable schema bases.
                let combatAliases: [String: String] = [
                    "我": "姓名", "血量": "气血", "血": "气血",
                    "炁": "先天之炁", "精力": "先天之炁"
                ]
                let identity: (GameStat) -> String = { stat in
                    let separators: Set<Character> = [".", ":", "："]
                    let base = String(stat.label.prefix { !separators.contains($0) })
                    if base == "精力" { return "先天之炁" }
                    return combatAliases[base] ?? base
                }
                // Swap an incoming label's base for the stable base so that
                // e.g. "我:X" -> "姓名:X" and "炁.0" -> "先天之炁.0", while
                // resource bars keep their refreshed embedded value.
                let relabel: (String, String) -> String = { incomingLabel, stableBase in
                    let separators: Set<Character> = [".", ":", "："]
                    if let sep = incomingLabel.firstIndex(where: { separators.contains($0) }) {
                        return stableBase + incomingLabel[sep...]
                    }
                    return stableBase
                }
                let incoming = Dictionary(updatedStats.map { (identity($0), $0) }) { first, _ in first }
                stats = stableStats.map { original in
                    guard let update = incoming[identity(original)] else { return original }
                    let stableBase = identity(original)
                    return GameStat(label: relabel(update.label, stableBase),
                                    value: update.value, color: original.color, command: original.command)
                }
                statsLayout = stableStatsLayout
            }
        case "014": transport.send(text)
        case "015":
            notice = styleStream.render(text)
            history.append(GameMessage(text: notice))
            if history.count > 500 { history.removeFirst(history.count - 500) }
            if !inWorld { status = MudText.plain(notice) }
        case "016":
            fighting = true
            let styled = styleStream.render(text)
            fightMessages.append(GameMessage(text: styled))
            if fightMessages.count > 50 { fightMessages.removeFirst() }
            history.append(GameMessage(text: styled))
            if history.count > 500 { history.removeFirst() }
        case "100":
            chatMessages.append(GameMessage(text: styleStream.render(text)))
            if chatMessages.count > 500 { chatMessages.removeFirst() }
        case "024":
            let effect = GameMessage(text: styleStream.render(text))
            combatEffects.append(effect)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) { [weak self] in
                self?.combatEffects.removeAll { $0.id == effect.id }
            }
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
            if text == "屏蔽描述" { descriptionHidden = true; descriptionToggleLabel = "显示" }
            else if !UserDefaults.standard.bool(forKey: "descriptionHidden") { descriptionHidden = false; descriptionToggleLabel = "隐藏" }
        case "045":
            if let url = URL(string: text), ["http", "https"].contains(url.scheme ?? "") { webURL = url }
        case "020": showPopup(text)
        case "021": topActions = styledActions(text)
        case "903": exits.removeAll { $0.slot == text || $0.command == text }
        case "997": transport.preservesNewlines = false
        case "998": transport.preservesNewlines = true
        case "900":
            guard let separator = text.lastIndex(of: ":"),
                  let number = UInt16(text[text.index(after: separator)...]), number > 0 else { return }
            let target = String(text[..<separator])
            guard !target.isEmpty else { return }
            // Release builds must not be redirected to a laptop or an internal
            // address supplied by an old server configuration.
            #if DEBUG
            host = target; port = String(number); connecting = true; sentCredentials = false
            transport.connect(host: target, port: number)
            #endif
        case "913": exits = []
        case "905": objects.removeAll { $0.command == text || $0.command == "look " + text }
        case "999": logout()
        default: log(text)
        }
    }

    private func receiveConfirmation(_ text: String) {
        // duihuax.xml keeps the quantity field visible, including prompts without numb.
        var next = GameDialog(numeric: true, kind: "confirmation")
        var confirm: [String] = []
        for part in text.components(separatedBy: "$dh#") {
            if part.hasPrefix("ok11.") { confirm.append(String(part.dropFirst(5))) }
            else if part.hasPrefix("no11.") { next.secondary.append(MudAction(label: "取消", command: String(part.dropFirst(5)))) }
            else if part.hasPrefix("numb.") { next.numeric = true }
            else {
                for line in part.components(separatedBy: "$br#") {
                    if line.hasPrefix("$exp#") { next.experience = String(line.dropFirst(5)) }
                    else if line.hasPrefix("$god#") { next.money = String(line.dropFirst(5)) }
                    else if line.hasPrefix("$obj#") {
                        let fields = line.dropFirst(5).split(separator: ",", omittingEmptySubsequences: false).map(String.init)
                        if fields.count >= 3 { next.rewards.append(GameReward(command: fields[0], image: fields[1], grade: Int(fields[2]) ?? 0)) }
                    } else if line.hasPrefix("#"), line.count >= 7, UInt32(line.dropFirst().prefix(6), radix: 16) != nil {
                        next.text += "\u{001B}[f" + String(line.prefix(7)) + "m" + String(line.dropFirst(7)) + "\u{001B}[0m\n"
                    } else { next.text += line + "\n" }
                }
            }
        }
        let command = confirm.joined(separator: "$sock#")
        if next.secondary.isEmpty { next.secondary = [MudAction(label: "取消", command: "")] }
        if next.numeric { next.inputCommand = command }
        else if !command.isEmpty { next.actions = [MudAction(label: "确定", command: command)] }
        dialog = next
    }

    private func showPopup(_ text: String) {
        let actions = MudText.popupActions(text).map { action in
            var result = action
            result.styledLabel = styleStream.render(action.display)
            return result
        }
        popup = GameDialog(actions: actions, layout: MudLayout(text, defaults: [1, 2, 8, 25]), kind: "popup")
    }

    private func looksLikeNPCDescription(_ text: String) -> Bool {
        let plain = MudText.plain(text)
        return plain.contains("装备着") || plain.contains("导师") ||
            (plain.contains("武功") && plain.contains("气血")) ||
            (plain.contains("先天") && plain.contains("气血"))
    }

    private func looksLikeNPCActionFrame(_ text: String) -> Bool {
        let plain = MudText.plain(text)
        return ["ask ", "follow ", "guard ", "touxi ", "attack ", "exert force."]
            .contains { plain.contains($0) }
    }

    private func looksLikeItemDescription(_ text: String) -> Bool {
        let plain = MudText.plain(text)
        return ["物品描述", "物品特性", "物品类型", "装备位置", "物品效果", "装备持有", "装备耐久", "装备评分", "镶嵌"]
            .contains { plain.contains($0) }
    }

    /// 任务第二页中，"宝石合成"旁边的"暂无"按钮替换为"活动"，点击后发送 renwu 活动 打开活动面板。
    private func applyTaskPageButtonOverride() {
        guard var current = dialog else { return }
        let allLabels = (current.actions + current.secondary).map { $0.label }
        // 任务第二页的特征：同时存在"宝石合成"和"上一页"按钮
        guard allLabels.contains("宝石合成"), allLabels.contains("上一页") else { return }

        // 在 actions 中找到"宝石合成"后面的第一个"暂无"
        if let gemIndex = current.actions.firstIndex(where: { $0.label == "宝石合成" }) {
            let tail = current.actions.indices.suffix(from: gemIndex + 1)
            if let noneIndex = tail.first(where: { current.actions[$0].label == "暂无" }) {
                let old = current.actions[noneIndex]
                current.actions[noneIndex] = MudAction(label: "活动", command: "renwu 活动",
                                                        slot: old.slot, styledLabel: "\u{001B}[1;32m活动\u{001B}[0m")
                dialog = current
                return
            }
        }
        // 若 actions 中没有，则在 secondary 中查找
        if let gemIndex = current.secondary.firstIndex(where: { $0.label == "宝石合成" }) {
            let tail = current.secondary.indices.suffix(from: gemIndex + 1)
            if let noneIndex = tail.first(where: { current.secondary[$0].label == "暂无" }) {
                let old = current.secondary[noneIndex]
                current.secondary[noneIndex] = MudAction(label: "活动", command: "renwu 活动",
                                                         slot: old.slot, styledLabel: "\u{001B}[1;32m活动\u{001B}[0m")
                dialog = current
            }
        }
    }

    /// 任务第二页的快捷按钮（b1-b11）中，"宝石合成"后面的"暂无"替换为"活动"。
    private func applyQuickButtonOverride() {
        // 只处理 b1-b11 的快捷按钮（自定义按钮区域）
        let quick = buttons.filter { action in
            guard let slot = Int(action.slot.dropFirst()) else { return false }
            return (1...11).contains(slot)
        }.sorted { (Int($0.slot.dropFirst()) ?? 0) < (Int($1.slot.dropFirst()) ?? 0) }
        let labels = quick.map { $0.label }
        // 任务第二页特征：同时存在"宝石合成"和"上一页"
        guard labels.contains("宝石合成"), labels.contains("上一页") else { return }
        guard let gemIndex = quick.firstIndex(where: { $0.label == "宝石合成" }) else { return }
        let tail = quick.indices.suffix(from: gemIndex + 1)
        guard let noneIndex = tail.first(where: { quick[$0].label == "暂无" }) else { return }
        let targetSlot = quick[noneIndex].slot
        // 替换 buttons 数组中对应 slot 的按钮
        if let idx = buttons.firstIndex(where: { $0.slot == targetSlot }) {
            let old = buttons[idx]
            buttons[idx] = MudAction(label: "活动", command: "renwu 活动",
                                     slot: old.slot, styledLabel: "\u{001B}[1;32m活动\u{001B}[0m")
        }
    }

    /// 活动面板：去掉左侧分类竖列，将活动列表移到主区域占满宽度，改为3列布局。
    private func applyActivityPanelLayout() {
        guard var current = dialog else { return }
        let categoryLabels: Set<String> = ["主线任务", "支线任务", "江湖奇遇", "副本刷怪", "定时活动"]
        let hasCategoryColumn = current.actions.contains { categoryLabels.contains($0.label) }
        guard hasCategoryColumn, !current.secondary.isEmpty else { return }
        // 将右侧活动列表移到主区域，清空左侧分类列
        current.actions = current.secondary
        current.secondary = []
        // 3列布局，占满整个面板宽度
        current.layout = MudLayout("$3,3,9,30#")
        current.secondaryLayout = MudLayout()
        dialog = current
    }

    private func statDisplayColor(_ label: String, serverColor: String) -> String {
        let name = label.components(separatedBy: ".").first ?? label
        switch name {
        case "精神": return "#6A1BB4"
        case "潜能": return "#D84BC8"
        case "先天之炁", "精力": return "#72C51F"
        default: return serverColor
        }
    }

    #if DEBUG
    private func replayParityScene(_ name: String) {
        guard let url = Bundle.main.url(forResource: "parity-scenes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let scenes = try? JSONDecoder().decode([String: [[String: String]]].self, from: data),
              let frames = scenes[name] else { preconditionFailure("Missing parity scene: " + name) }
        for frame in frames { receive(MudFrame(code: frame["code"], text: frame["text"] ?? "")) }
    }
    #endif
}
