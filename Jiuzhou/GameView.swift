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
            if game.inWorld { AndroidWorldView(game: game) }
            else if game.needsCharacter { character }
            else { login }
        }
        .foregroundStyle(Theme.foreground)
        .font(.system(size: 14))
        .tint(Theme.foreground)
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
            HStack(spacing: 6) {
                Text(game.account).font(.system(size: 16)).lineLimit(1)
                Spacer()
                Circle().fill(game.connected ? Color.green : Color.red).frame(width: 10, height: 10)
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape").font(.system(size: 22))
                }
                .frame(width: 38, height: 30)
                .accessibilityLabel("连接设置")
            }
            .padding(.horizontal, 8)
            .frame(height: 34)

            if !game.stats.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)], spacing: 2) {
                    ForEach(game.stats) { stat in
                        statBar(stat)
                    }
                }
                .padding(.horizontal, 3)
                .padding(.vertical, 2)
            }

            rule
            HStack(spacing: 0) {
                Text(game.room)
                    .font(.system(size: 18))
                    .lineLimit(1)
                    .padding(.leading, 10)
                Spacer()
                Button { showDescription.toggle() } label: {
                    Image(systemName: showDescription ? "eye.slash" : "eye")
                        .font(.system(size: 20))
                }
                .frame(width: 42, height: 34)
                .accessibilityLabel("切换场景描述")
            }
            .frame(height: 38)

            if !game.topActions.isEmpty {
                actionStrip(game.topActions, buttonHeight: 38)
            }
            rule

            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(game.objects) { item in
                                actionButton(item, minHeight: 42)
                            }
                        }
                        .padding(3)
                    }
                    .frame(width: min(164, max(116, geometry.size.width * 0.25)))

                    Rectangle().fill(Theme.divider).frame(width: 1)

                    VStack(spacing: 0) {
                        if showDescription {
                            ScrollView {
                                MudRichText(raw: game.description, send: game.act)
                                    .font(.system(size: 15))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .padding(8)
                            }
                            .frame(maxHeight: geometry.size.height * 0.48)
                            rule
                        }

                        directions

                        if !game.notice.isEmpty {
                            Text(game.notice)
                                .font(.system(size: 12))
                                .lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(minHeight: 250)

            if !game.buttons.isEmpty {
                bottomTabs(game.buttons)
            }
            rule

            HStack {
                Text("消息").font(.system(size: 15))
                Spacer()
                Button { game.messages = [] } label: {
                    Image(systemName: "trash").font(.system(size: 18))
                }
                .frame(width: 34, height: 30)
                .accessibilityLabel("清空消息")
            }
            .padding(.horizontal, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(game.messages) { message in
                            MudRichText(raw: message.text, send: game.act)
                                .font(.system(size: 14))
                                .textSelection(.enabled)
                                .id(message.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                }
                .onChange(of: game.messages.last?.id) { id in
                    if let id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            .frame(minHeight: 150, maxHeight: 250)
            rule

            HStack(spacing: 6) {
                TextField("指令", text: $command)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .onSubmit(sendCommand)
                    .padding(.leading, 8)
                Button(action: sendCommand) {
                    Image(systemName: "paperplane.fill").font(.system(size: 22))
                }
                .frame(width: 46, height: 42)
                .accessibilityLabel("发送指令")
                .disabled(!game.connected)
            }
            .frame(height: 46)
        }
    }

    private var directions: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                directionButton("west")
                Button { game.act("look") } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 20))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.plain)
                .overlay(Rectangle().stroke(Theme.divider, lineWidth: 0.5))
                .accessibilityLabel("查看当前场景")
                directionButton("east")
            }
            HStack(spacing: 4) {
                directionButton("south")
                    .frame(maxWidth: .infinity)
            }
            let extras = game.exits.filter {
                !["north", "south", "east", "west", "northwest", "northeast", "southwest", "southeast"]
                    .contains($0.slot)
            }
            if !extras.isEmpty { actionStrip(extras, buttonHeight: 40) }
        }
        .padding(5)
    }

    @ViewBuilder
    private func directionButton(_ slot: String) -> some View {
        if let exit = game.exits.first(where: { $0.slot == slot || $0.slot == slot + "up" || $0.slot == slot + "down" }) {
            actionButton(exit, minHeight: 48)
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: 48)
        }
    }

    private func statBar(_ stat: GameStat) -> some View {
        Button { game.act(stat.command) } label: {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.black.opacity(0.22))
                    Rectangle()
                        .fill(statColor(stat.color).opacity(0.78))
                        .frame(width: geometry.size.width * stat.fraction)
                    Text(stat.label + " " + stat.value)
                        .font(.system(size: 14))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 6)
                }
            }
            .frame(height: 32)
        }
        .buttonStyle(.plain)
        .overlay(Rectangle().stroke(Color.black.opacity(0.2), lineWidth: 0.5))
    }

    private func actionButton(_ action: MudAction, minHeight: CGFloat = 40) -> some View {
        Button { game.act(action.command) } label: {
            Text(action.label).font(.system(size: 12)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).padding(4)
                .frame(maxWidth: .infinity, minHeight: minHeight)
                .background(Color.black.opacity(0.12))
                .overlay(Rectangle().stroke(Theme.divider, lineWidth: 0.5))
        }.buttonStyle(.plain).disabled(!game.connected)
    }

    private func actionStrip(_ actions: [MudAction], buttonHeight: CGFloat = 40) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(actions) { action in
                    actionButton(action, minHeight: buttonHeight).frame(minWidth: 65)
                }
            }
                .padding(3)
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func bottomTabs(_ actions: [MudAction]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(actions) { action in
                    Button { game.act(action.command) } label: {
                        Text(action.label)
                            .font(.system(size: 14))
                            .lineLimit(1)
                            .frame(minWidth: 74, minHeight: 42)
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.plain)
                    .overlay(Rectangle().stroke(Theme.divider, lineWidth: 0.5))
                    .disabled(!game.connected)
                }
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
        }
        .background(Color.black.opacity(0.10))
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
