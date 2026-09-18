import SwiftUI

private enum Theme {
    static let background = Color(red: 0.13, green: 0.08, blue: 0.02)
    static let foreground = Color(red: 0.87, green: 0.73, blue: 0.60)
    static let divider = Color.white.opacity(0.22)
}

struct GameView: View {
    @ObservedObject var game: GameModel
    @State private var command = ""
    @State private var characterName = ""
    @State private var gender = "男性"
    @State private var showDescription = true
    @State private var showSettings = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if game.inWorld { world }
            else if game.needsCharacter { character }
            else { login }
        }
        .foregroundStyle(Theme.foreground)
        .font(.system(size: 14))
        .tint(Theme.foreground)
        .sheet(item: $game.dialog) { _ in DialogView(game: game) }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                Form {
                    LabeledContent("服务器", value: game.host + ":" + game.port)
                    LabeledContent("账号", value: game.account)
                    Button("重新连接") { showSettings = false; game.login() }
                    Button("退出登录", role: .destructive) { showSettings = false; game.logout() }
                }
                .navigationTitle("连接")
                .toolbar { Button("完成") { showSettings = false } }
            }
        }
        .onChange(of: scenePhase) { phase in
            // iOS may suspend a background TCP session. Reconnect remains an explicit action.
            if phase == .active && game.inWorld && !game.connected {
                game.notice = "连接已断开，请重新连接"
            }
        }
    }

    private var login: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image("GameMark").resizable().scaledToFit().frame(width: 80, height: 80)
                    .accessibilityHidden(true)
                Text("九州书剑录").font(.title2.bold())
                VStack(alignment: .leading, spacing: 12) {
                    TextField("服务器地址", text: $game.host).keyboardType(.URL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("端口", text: $game.port).keyboardType(.numberPad)
                    TextField("账号", text: $game.account).textContentType(.username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("密码", text: $game.password).textContentType(.password)
                }
                .textFieldStyle(.roundedBorder)
                Button(action: game.login) {
                    HStack { if game.connecting { ProgressView() }; Text("进入江湖") }
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered).disabled(game.connecting || game.connected)
                if game.connecting || game.connected { Button("取消连接", action: game.logout) }
                Text(game.status).font(.footnote).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 400).padding(24).frame(maxWidth: .infinity)
        }
    }

    private var character: some View {
        VStack(spacing: 20) {
            Text("初入江湖").font(.title2)
            TextField("角色姓名", text: $characterName).textFieldStyle(.roundedBorder)
            Picker("性别", selection: $gender) { Text("男性").tag("男性"); Text("女性").tag("女性") }
                .pickerStyle(.segmented)
            Button("创建角色") { game.createCharacter(name: characterName, gender: gender) }
                .buttonStyle(.bordered).disabled(!game.connected)
            Text(game.notice).font(.footnote)
            if !game.connected { Text(game.status).font(.footnote) }
            Button("返回", action: game.logout)
        }.frame(maxWidth: 400).padding(24)
    }

    private var world: some View {
        VStack(spacing: 0) {
            HStack {
                Text(game.account).lineLimit(1)
                Spacer()
                Circle().fill(game.connected ? Color.green : Color.red).frame(width: 8, height: 8)
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .frame(width: 44, height: 36).accessibilityLabel("连接设置")
            }.padding(.leading, 8)
            if !game.connected {
                HStack {
                    Text(game.status).font(.caption)
                    Spacer()
                    Button("重新连接", action: game.login)
                }.padding(8).background(Color.red.opacity(0.15))
            }
            if !game.stats.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 2) {
                    ForEach(game.stats) { stat in
                        Button { game.act(stat.command) } label: {
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.white.opacity(0.05))
                                GeometryReader { geo in
                                    Rectangle().fill(statColor(stat.color).opacity(0.55))
                                        .frame(width: geo.size.width * stat.fraction)
                                }
                                Text(stat.label + " " + stat.value).font(.system(size: 11))
                                    .lineLimit(1).minimumScaleFactor(0.65).padding(.horizontal, 4)
                            }.frame(height: 24)
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 2)
            }
            rule
            HStack {
                Text(game.room).font(.system(size: 16, weight: .semibold)).lineLimit(2)
                Spacer(minLength: 4)
                Button { showDescription.toggle() } label: {
                    Image(systemName: showDescription ? "eye.slash" : "eye")
                }.frame(width: 40, height: 40).accessibilityLabel("切换场景描述")
            }.padding(.leading, 8)
            if !game.topActions.isEmpty { actionStrip(game.topActions) }
            rule
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(game.objects) { item in
                                actionButton(item).frame(maxWidth: .infinity, minHeight: 44)
                            }
                        }.padding(3)
                    }.frame(width: min(100, geometry.size.width * 0.23))
                    Rectangle().fill(Theme.divider).frame(width: 1)
                    VStack(spacing: 0) {
                        if showDescription {
                            ScrollView {
                                MudRichText(raw: game.description, send: game.act).frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled).padding(8)
                            }.frame(maxHeight: geometry.size.height * 0.42)
                            rule
                        }
                        directions
                        if !game.notice.isEmpty {
                            Text(game.notice).font(.caption).lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }.frame(minHeight: 150)
            if !game.buttons.isEmpty { actionStrip(game.buttons) }
            rule
            HStack {
                Text("消息").font(.caption)
                Spacer()
                Button { game.messages = [] } label: { Image(systemName: "trash") }
                    .accessibilityLabel("清空消息").frame(width: 32, height: 28)
            }.padding(.horizontal, 8)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(game.messages) { message in
                            MudRichText(raw: message.text, send: game.act).font(.system(size: 12)).textSelection(.enabled).id(message.id)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8)
                }
                .onChange(of: game.messages.last?.id) { id in
                    if let id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }.frame(height: 110)
            rule
            HStack(spacing: 8) {
                TextField("指令", text: $command).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.send).onSubmit(sendCommand)
                Button(action: sendCommand) { Image(systemName: "paperplane.fill") }
                    .frame(width: 44, height: 44).accessibilityLabel("发送指令").disabled(!game.connected)
            }.padding(.leading, 10)
        }
    }

    private var directions: some View {
        VStack(spacing: 4) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                ForEach(["northwest", "north", "northeast", "west", "look", "east", "southwest", "south", "southeast"], id: \.self) { direction in
                    if direction == "look" {
                        Button { game.act("look") } label: { Image(systemName: "arrow.clockwise") }
                            .frame(maxWidth: .infinity, minHeight: 44).accessibilityLabel("查看当前场景")
                    } else if let exit = game.exits.first(where: { $0.slot == direction || $0.slot == direction + "up" || $0.slot == direction + "down" }) {
                        actionButton(exit).frame(maxWidth: .infinity, minHeight: 44)
                    } else { Color.clear.frame(height: 44) }
                }
            }
            let extras = game.exits.filter { !["north", "south", "east", "west"].contains(where: $0.slot.hasPrefix) }
            if !extras.isEmpty { actionStrip(extras) }
        }.padding(5)
    }

    private func actionButton(_ action: MudAction) -> some View {
        Button { game.act(action.command) } label: {
            Text(action.label).font(.system(size: 12)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).padding(4)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Color.white.opacity(0.045))
                .overlay(Rectangle().stroke(Theme.divider, lineWidth: 0.5))
        }.buttonStyle(.plain).disabled(!game.connected)
    }

    private func actionStrip(_ actions: [MudAction]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) { ForEach(actions) { action in actionButton(action).frame(minWidth: 65) } }
                .padding(3)
        }.fixedSize(horizontal: false, vertical: true)
    }

    private var rule: some View { Rectangle().fill(Theme.divider).frame(height: 1) }
    private func sendCommand() {
        let text = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty && game.connected { game.act(text); command = "" }
    }
    private func statColor(_ value: String) -> Color {
        let hex = value.replacingOccurrences(of: "#", with: "")
        guard let n = UInt32(hex, radix: 16) else { return .green }
        return Color(red: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255, blue: Double(n & 255) / 255)
    }
}

private struct DialogView: View {
    @ObservedObject var game: GameModel
    @State private var input = ""
    var body: some View {
        NavigationStack {
            ScrollView {
                if let dialog = game.dialog {
                    VStack(alignment: .leading, spacing: 14) {
                        MudRichText(raw: dialog.text, send: game.act).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        if dialog.inputCommand != nil {
                            TextField("请输入", text: $input).textFieldStyle(.roundedBorder)
                                .keyboardType(dialog.numeric ? .numberPad : .default)
                                .onSubmit { game.submitInput(input) }
                            Button("确定") { game.submitInput(input) }.buttonStyle(.bordered)
                        }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(dialog.actions + dialog.secondary) { action in
                                Button { game.act(action.command) } label: {
                                    Text(action.label).frame(maxWidth: .infinity, minHeight: 44)
                                }.buttonStyle(.bordered)
                            }
                        }
                    }.padding()
                }
            }
            .background(Theme.background).foregroundStyle(Theme.foreground)
            .navigationTitle("江湖").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("关闭") { game.dialog = nil } }
            .onChange(of: game.dialog?.id) { _ in input = "" }
        }.tint(Theme.foreground)
    }
}
