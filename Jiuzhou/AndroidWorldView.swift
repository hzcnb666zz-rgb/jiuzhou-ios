import SwiftUI

struct AndroidButtonStyle: ButtonStyle {
    var image: String? = nil
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if let image {
                    Image(image + (configuration.isPressed ? "2" : "") + ".png").resizable()
                } else {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(configuration.isPressed ? Color(red: 0.05, green: 0.46, blue: 0.88) :
                                Color.white.opacity(filled ? 0.13 : 0))
                }
            }
            .overlay {
                if image == nil {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(configuration.isPressed ? Color.pink : Color(red: 0.71, green: 0.41, blue: 0.24).opacity(0.2), lineWidth: 1)
                }
            }
    }
}

struct AndroidWorldView: View {
    @ObservedObject var game: GameModel
    @AppStorage("androidMode") private var mode = "night"
    @AppStorage("androidShortChat") private var shortChat = false
    @State private var menuVisible = false
    @State private var historyVisible = false
    @State private var historyTab = 0
    @State private var settingsVisible = false
    @State private var editingSlot: Int?
    @State private var editLabel = ""
    @State private var editCommand = ""
    @State private var editVisible = false
    @State private var revision = 0
    @State private var dialogInput = ""
    @State private var quitVisible = false

    private let compass = ["northwest", "north", "northeast", "west", "", "east", "southwest", "south", "southeast"]
    private var ink: Color { mode == "day" ? Color(red: 0.31, green: 0.15, blue: 0.08) : mode == "mud" ? Color(white: 0.67) : .white }
    private var background: String { mode == "day" ? "bk1.jpeg" : mode == "mud" ? "huashan.png" : "bk2.jpeg" }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let unit = min(width, 600)
            ZStack(alignment: .top) {
                Image(background).resizable().ignoresSafeArea()
                VStack(spacing: 0) {
                    if !game.chatMessages.isEmpty {
                        messages(Array(game.chatMessages.suffix(100)))
                            .frame(height: shortChat ? unit / 8 : unit / 5)
                    }
                    rule
                    titleBar
                    rule
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            ScrollView {
                                LazyVStack(spacing: 2) {
                                    ForEach(game.objects) { object in
                                        Button { game.act(object.command) } label: {
                                            VStack(spacing: 1) {
                                                if let fraction = game.objectHealth[object.command] {
                                                    GeometryReader { g in
                                                        Color.red.frame(width: g.size.width * fraction)
                                                    }.frame(height: 4)
                                                }
                                                MudRichText(raw: object.display, send: game.act)
                                                    .font(.system(size: 11)).multilineTextAlignment(.center)
                                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            }.padding(2).frame(height: unit / 10)
                                        }.buttonStyle(AndroidButtonStyle(filled: true))
                                    }
                                }.padding(1)
                            }
                            ForEach(extraExits) { exit in
                                action(exit, height: unit / 11)
                            }
                        }.frame(width: unit / 7 + 2)
                        Rectangle().fill(Color(white: 0.4)).frame(width: 1)
                        VStack(spacing: 0) {
                            ZStack(alignment: .topLeading) {
                                VStack(spacing: 0) {
                                    if !game.descriptionHidden && !game.fighting {
                                        ScrollView {
                                            MudRichText(raw: game.description, send: game.act)
                                                .font(.system(size: 15)).frame(maxWidth: .infinity, alignment: .leading).padding(5)
                                        }.frame(maxHeight: geometry.size.height * 0.26)
                                        rule
                                    }
                                    messages(game.fighting ? game.fightMessages : game.messages)
                                }
                                if game.dialog != nil { interaction }
                                if !game.notice.isEmpty {
                                    Text(game.notice).font(.system(size: 14)).foregroundStyle(.cyan)
                                        .padding(2).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color(white: 0.4)).allowsHitTesting(false)
                                        .task(id: game.notice) {
                                            let notice = game.notice
                                            try? await Task.sleep(nanoseconds: 5_000_000_000)
                                            if !Task.isCancelled && game.notice == notice { game.notice = "" }
                                        }
                                }
                            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                            rule
                            exits(unit: unit)
                        }
                    }.frame(maxHeight: .infinity)
                    stats(unit: unit)
                    rule
                    bottomBar(unit: unit)
                }.padding(1)
                if menuVisible { mainMenu.padding(.top, 45) }
                if historyVisible { historyPanel }
            }
            .foregroundStyle(ink).font(.system(size: 13))
        }
        .onChange(of: game.dialog?.id) { _ in dialogInput = "" }
        .alert("修改按钮", isPresented: $editVisible) {
            TextField("名称", text: $editLabel)
            TextField("指令", text: $editCommand).textInputAutocapitalization(.never)
            Button("保存") {
                if let slot = editingSlot {
                    UserDefaults.standard.set(editLabel, forKey: "button.\(slot).label")
                    UserDefaults.standard.set(editCommand, forKey: "button.\(slot).command")
                    game.buttons.removeAll { $0.slot == "b\(slot)" }
                    revision += 1
                }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("确认要退出么？", isPresented: $quitVisible) {
            Button("退出", role: .destructive) { game.act("quit"); game.logout() }
            Button("留下来", role: .cancel) {}
        }
        .sheet(isPresented: $settingsVisible) {
            NavigationStack {
                Form {
                    TextField("服务器地址", text: $game.host).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("端口", text: $game.port).keyboardType(.numberPad)
                    Text(game.status)
                    Button("重新连接") { settingsVisible = false; game.login() }
                }.navigationTitle("连接设置").toolbar { Button("完成") { settingsVisible = false } }
            }
        }
    }

    private var rule: some View { Color(white: 0.4).frame(height: 1) }

    private var titleBar: some View {
        HStack(spacing: 3) {
            MudRichText(raw: game.room, send: game.act).font(.system(size: 20))
                .lineLimit(1).minimumScaleFactor(0.6).padding(.leading, 18)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(game.topActions) { item in action(item, height: 28) }
                }
            }
            Button(game.descriptionHidden ? "显示" : "隐藏") { game.descriptionHidden.toggle() }
                .font(.system(size: 14)).padding(.horizontal, 8).frame(height: 28)
                .background(Color.white.opacity(0.13))
        }.padding(3).frame(height: 40)
            .background { if mode == "night" { Image("bar.png").resizable() } }
    }

    private func messages(_ items: [GameMessage]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(items) { item in
                        MudRichText(raw: item.text, send: game.act).font(.system(size: 14))
                            .frame(maxWidth: .infinity, alignment: .leading).id(item.id)
                    }
                }.padding(5)
            }.onChange(of: items.last?.id) { id in
                if let id { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }

    private var extraExits: [MudAction] {
        game.exits.filter { exit in !compass.filter { !$0.isEmpty }.contains { exit.slot == $0 || exit.slot == $0 + "up" || exit.slot == $0 + "down" } }
    }

    private func exits(unit: CGFloat) -> some View {
        HStack(spacing: 2) {
            if game.customButtonsVisible {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 5), spacing: 2) {
                    ForEach(1...10, id: \.self) { slot in quickButton(slot, height: unit * 3 / 22 - 2) }
                }
            } else {
                GeometryReader { g in
                    ForEach(Array(compass.enumerated()), id: \.offset) { index, slot in
                        let column = index % 3
                        let row = index / 3
                        if slot.isEmpty {
                            Button { game.act(game.buttons.first { $0.slot == "bs" }?.command ?? "look") } label: {
                                MudRichText(raw: game.room, send: game.act).font(.system(size: 12))
                                    .lineLimit(1).minimumScaleFactor(0.5)
                                    .frame(width: min(unit / 4, g.size.width * 0.44), height: unit / 15)
                                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(red: 0.86, green: 0.93, blue: 0.78).opacity(0.44)))
                            }.buttonStyle(.plain).position(x: g.size.width / 2, y: g.size.height / 2)
                        } else if let exit = game.exits.first(where: { $0.slot == slot || $0.slot == slot + "up" || $0.slot == slot + "down" }) {
                            let bw = min(unit / 5, g.size.width / 3)
                            let bh = unit / 12
                            Button { game.act(exit.command) } label: {
                                MudRichText(raw: exit.display, send: game.act).font(.system(size: 12))
                                    .lineLimit(2).minimumScaleFactor(0.65).multilineTextAlignment(.center)
                                    .frame(width: bw, height: bh)
                            }.buttonStyle(AndroidButtonStyle(image: mode == "night" ? imageName(slot) : nil))
                                .position(x: column == 0 ? bw / 2 : column == 1 ? g.size.width / 2 : g.size.width - bw / 2,
                                          y: row == 0 ? bh / 2 : row == 1 ? g.size.height / 2 : g.size.height - bh / 2)
                        }
                    }
                }
            }
            VStack(spacing: 2) {
                Button(game.customButtonsVisible ? "关闭" : "自定") { game.customButtonsVisible.toggle() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity).buttonStyle(AndroidButtonStyle())
                quickButton(11, height: unit * 3 / 22 - 2)
            }.frame(width: unit / 7, height: unit * 3 / 11)
        }.frame(height: unit * 4 / 13).padding(.horizontal, 2)
    }

    private func imageName(_ slot: String) -> String {
        ["northwest": "nw", "northeast": "ne", "southwest": "sw", "southeast": "se"][slot] ?? slot
    }

    private func quickAction(_ slot: Int) -> MudAction {
        _ = revision
        if let action = game.buttons.first(where: { $0.slot == "b\(slot)" }) { return action }
        let defaults: [Int: (String, String)] = [1: ("属性", "score"), 2: ("物品", "i"), 3: ("技能", "skills"), 4: ("状态", "hp"), 5: ("队伍", "team"), 6: ("任务", "quest"), 11: ("观察", "look"), 12: ("物品", "i"), 13: ("技能", "skills"), 14: ("属性", "score"), 15: ("状态", "hp"), 16: ("队伍", "team"), 17: ("任务", "quest")]
        let fallback = defaults[slot] ?? ("长按", "")
        return MudAction(label: UserDefaults.standard.string(forKey: "button.\(slot).label") ?? fallback.0,
                         command: UserDefaults.standard.string(forKey: "button.\(slot).command") ?? fallback.1, slot: "b\(slot)")
    }

    private func quickButton(_ slot: Int, height: CGFloat) -> some View {
        let item = quickAction(slot)
        return MudRichText(raw: item.display, send: game.act)
            .font(.system(size: 12)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity).frame(height: height)
            .background(Color.white.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color(red: 0.71, green: 0.41, blue: 0.24).opacity(0.2)))
            .contentShape(Rectangle())
            .onTapGesture { game.act(item.command) }
            .onLongPressGesture {
                editingSlot = slot; editLabel = item.label; editCommand = item.command; editVisible = true
            }
            .accessibilityAddTraits(.isButton)
    }

    private func bottomBar(unit: CGFloat) -> some View {
        HStack(spacing: 1) {
            Button { game.dialog = GameDialog(text: "请输入指令：", inputCommand: "$txt#") } label: {
                Image("command.png").resizable().scaledToFit().frame(width: 38, height: unit / 8)
            }.buttonStyle(.plain).accessibilityLabel("输入指令")
            ForEach(12...17, id: \.self) { slot in quickButton(slot, height: unit / 8) }
            Button { menuVisible.toggle() } label: {
                Image("mainbt.png").resizable().scaledToFit().frame(width: 30, height: unit / 8)
            }.buttonStyle(.plain).accessibilityLabel("菜单")
        }.background(Color.white.opacity(0.13))
    }

    private func stats(unit: CGFloat) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: game.statsLayout.columns), spacing: 1) {
            ForEach(game.stats) { stat in
                Button { game.act(stat.command) } label: {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Color.clear
                            color(stat.color).frame(width: g.size.width * stat.fraction)
                            MudRichText(raw: stat.label + (stat.value.contains("/") ? "" : ":" + stat.value), send: game.act)
                                .font(.system(size: 11)).lineLimit(1).minimumScaleFactor(0.6)
                        }
                    }.frame(height: max(16, unit / CGFloat(game.statsLayout.heightDivisor)))
                }.buttonStyle(.plain)
            }
        }
    }

    private func color(_ hex: String) -> Color {
        let value = UInt32(hex.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }

    private func action(_ item: MudAction, height: CGFloat) -> some View {
        Button { game.act(item.command) } label: {
            MudRichText(raw: item.display, send: game.act).font(.system(size: 12))
                .multilineTextAlignment(.center).padding(3).frame(maxWidth: .infinity, minHeight: height)
        }.buttonStyle(AndroidButtonStyle())
    }

    private var interaction: some View {
        VStack(spacing: 3) {
            if let dialog = game.dialog {
                ScrollView([.vertical, .horizontal]) {
                    MudRichText(raw: dialog.text, send: game.act).font(.system(size: 13))
                        .padding(5).frame(maxWidth: .infinity, alignment: .leading)
                }.fixedSize(horizontal: false, vertical: dialog.kind != "map" && dialog.kind != "pages")
                if dialog.inputCommand != nil {
                    HStack(spacing: 3) {
                        TextField("", text: $dialogInput).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .keyboardType(dialog.numeric ? .numberPad : .default).onSubmit { game.submitInput(dialogInput) }
                            .padding(5).background(Color.white.opacity(0.1))
                        Button("确定") { game.submitInput(dialogInput) }.frame(width: 60, height: 40).buttonStyle(AndroidButtonStyle())
                    }.padding(.horizontal, 5)
                }
                ScrollView {
                    HStack(alignment: .top, spacing: 3) {
                        actionGrid(dialog.actions, layout: dialog.layout)
                        if !dialog.secondary.isEmpty { actionGrid(dialog.secondary, layout: dialog.secondaryLayout) }
                    }
                }
                HStack {
                    if dialog.kind == "pages" {
                        Button("上一页") { game.act("b") }
                        Button("下一页") { game.act("n") }
                    }
                    Spacer()
                    Button("关闭") { game.dialog = nil }.padding(6)
                }.buttonStyle(AndroidButtonStyle())
            }
        }.padding(3).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background { Image(background).resizable() }
    }

    private func actionGrid(_ items: [MudAction], layout: MudLayout) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: layout.columns), spacing: 2) {
            ForEach(items) { item in action(item, height: max(28, 390 / CGFloat(layout.heightDivisor))) }
        }
    }

    private var mainMenu: some View {
        VStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                let modes = [("日间模式", "day"), ("夜间模式", "night"), ("正常模式", "mud")]
                Button(modes[index].0) { mode = modes[index].1; menuVisible = false; game.act("mycmds"); game.act("look") }
            }
            Button("单行聊天") { shortChat = true; menuVisible = false }
            Button("多行聊天") { shortChat = false; menuVisible = false }
            Button("信息记录") { historyVisible = true; menuVisible = false }
            Button("连接设置") { settingsVisible = true; menuVisible = false }
            Button("退 出") { quitVisible = true; menuVisible = false }
            Button("关闭") { menuVisible = false }
        }.buttonStyle(.bordered).padding(8).frame(width: 180).background(Color.black.opacity(0.95))
    }

    private var historyPanel: some View {
        VStack(spacing: 3) {
            Picker("记录", selection: $historyTab) { Text("聊天").tag(0); Text("信息").tag(1) }.pickerStyle(.segmented)
            messages(historyTab == 0 ? game.chatMessages : game.history)
            Button("关 闭") { historyVisible = false }.frame(maxWidth: .infinity, minHeight: 40).buttonStyle(AndroidButtonStyle())
        }.padding(3).background(Color(white: 0.14)).foregroundStyle(.white)
    }
}
