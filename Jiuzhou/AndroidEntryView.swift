import SwiftUI
import UIKit

struct AndroidEntryView: View {
    @ObservedObject var game: GameModel
    @State private var registering = false
    @State private var confirmedPassword = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var registeringRequest = false
    @State private var characterName = ""
    @State private var gender = "男性"
    @State private var chooseServer = false
    @State private var accountCenter = false
    @State private var settings = false
    @State private var editingCredential = false
    @State private var editingPassword = false
    @State private var credentialDraft = ""
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geometry in
        ZStack {
            if game.inWorld { AndroidWorldView(game: game) }
            else if game.needsCharacter { character }
            else { login(width: geometry.size.width, height: geometry.size.height) }
            if accountCenter { AndroidAccountView(game: game) { accountCenter = false } }
            if let url = game.webURL { AndroidWebPanel(url: url) { game.webURL = nil } }
        }
        .onAppear {
            #if DEBUG
            chooseServer = ProcessInfo.processInfo.arguments.contains("--ui-check-servers")
            registering = ProcessInfo.processInfo.arguments.contains("--ui-check-register")
            accountCenter = ProcessInfo.processInfo.arguments.contains("--ui-check-account")
            #endif
        }
        .environment(\.mudDisplayWidth, geometry.size.width)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active && game.inWorld && !game.connected { game.notice = "连接已断开，请重新连接" }
        }
        .alert(editingPassword ? "请输入密码：" : "请输入账号：", isPresented: $editingCredential) {
            if editingPassword { SecureField("", text: $credentialDraft) }
            else { TextField("", text: $credentialDraft).textInputAutocapitalization(.never).autocorrectionDisabled() }
            Button("取消", role: .cancel) {}
            Button("确定") {
                if editingPassword { game.password = credentialDraft }
                else { game.account = credentialDraft }
                credentialDraft = ""
            }
        }
        .sheet(isPresented: $settings) {
            NavigationStack {
                Form {
                    TextField("服务器地址", text: $game.host).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("端口", text: $game.port).keyboardType(.numberPad)
                }.navigationTitle("服务器设置").toolbar { Button("完成") { settings = false } }
            }
        }
    }

    private func login(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            SplashBackground()
            if chooseServer {
                VStack(spacing: 0) {
                    Text("分区列表").font(.android(size: 18)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 50).background(.black).padding(.bottom, 5)
                    serverHeading("最近登录分区:", size: 13)
                    serverRow(width: width - 23, height: height, screenWidth: width).padding(.horizontal, 11.5)
                    serverHeading("更 多 分 区", size: 18)
                    serverRow(width: (width - 62) / 2, height: height, screenWidth: width)
                        .padding(.top, 25).padding(.bottom, 65)
                    HStack {
                        Button("会员中心") { accountCenter = true }
                        Button("返回登录") { game.logout(); chooseServer = false }
                    }.buttonStyle(LoginButtonStyle()).padding(.horizontal, 10)
                    Button("服务器设置") { settings = true }.font(.android(size: 13)).padding(10)
                    Text(game.status).font(.android(size: 13)).padding(10)
                    if game.connecting { ProgressView() }
                    Spacer(minLength: 0)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            Button("登 录") { registering = false }
                                .buttonStyle(.plain).frame(maxWidth: .infinity, minHeight: 45)
                            Button("注 册") { registering = true }
                        }.buttonStyle(LoginButtonStyle()).padding(.bottom, 15)
                        fieldLabel(registering ? "创建你的账号" : "你的账号：")
                        credentialField(password: false)
                        fieldLabel(registering ? "创建你的密码" : "你的密码：")
                        credentialField(password: true)
                        if registering {
                            fieldLabel("确认你的密码")
                            SecureField("请再输一次密码", text: $confirmedPassword).modifier(LoginFieldStyle())
                            fieldLabel("你的手机号码")
                            TextField("", text: $phone).keyboardType(.phonePad).modifier(LoginFieldStyle())
                                .accessibilityIdentifier("register.phone")
                            fieldLabel("你的邮箱")
                            TextField("", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                                .autocorrectionDisabled().modifier(LoginFieldStyle()).accessibilityIdentifier("register.email")
                        }
                        HStack(spacing: 8) {
                            Button(registering ? "注 册" : "登 录") {
                                if registering {
                                    register()
                                } else if game.account.isEmpty || game.password.isEmpty {
                                    game.status = "请输入账号和密码"
                                } else {
                                    game.status = "请选择分区"; chooseServer = true
                                }
                            }
                            Button("退 出") { game.logout(); game.password = "" }
                        }.buttonStyle(LoginButtonStyle()).padding(.top, 50).disabled(registeringRequest)
                        Text(game.status == "未连接" ? "" : game.status).font(.android(size: 13)).padding(10)
                    }.padding(.horizontal, 10)
                }
            }
        }.foregroundStyle(.black).font(.android(size: 18)).tint(.black).preferredColorScheme(.light)
    }

    private func serverHeading(_ text: String, size: CGFloat) -> some View {
        Text(text).font(.android(size: size)).foregroundStyle(.yellow)
            .frame(maxWidth: .infinity).frame(height: 35)
            .background(entryArt("flag")).padding(.horizontal, 5)
    }

    private func serverRow(width: CGFloat, height: CGFloat, screenWidth: CGFloat) -> some View {
        let iconSize = max(1, (height - 180 - screenWidth / 9 - screenWidth / 10) / 10)
        return Button { game.login() } label: {
            HStack(spacing: 0) {
                entryArt("licon").frame(width: iconSize, height: iconSize).padding(3)
                Text("本地九州书剑录").font(.android(size: screenWidth / 28))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color(red: 180/255, green: 105/255, blue: 62/255).opacity(0.2)))
                    .padding(.leading, 5).background(Color(white: 238/255).opacity(34/255))
            }.padding(1).frame(width: max(0, width), height: iconSize + 8)
        }.buttonStyle(.plain).disabled(game.connecting)
    }

    private func entryArt(_ name: String) -> some View {
        Group {
            if let url = Bundle.main.url(forResource: name, withExtension: "png"), let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable()
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text).padding(.leading, 20).frame(height: 80, alignment: .center)
    }

    private func register() {
        guard ![game.account, game.password, confirmedPassword, phone, email].contains(where: { $0.isEmpty }) else {
            game.status = "请确保各项都不为空！"; return
        }
        guard confirmedPassword == game.password else { game.status = "两次输入密码不一致！"; return }
        registeringRequest = true
        game.status = "正在注册"
        let request = LegacyService.registration(account: game.account, password: game.password, phone: phone, email: email)
        Task { @MainActor in
            defer { registeringRequest = false }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      let result = String(data: data, encoding: .utf8), !result.isEmpty else {
                    game.status = "注册失败，服务器连接错误！"; return
                }
                game.status = result
                if result == "注册成功" { registering = false; confirmedPassword = "" }
            } catch { game.status = "注册失败，请检查网络！" }
        }
    }

    private func credentialField(password: Bool) -> some View {
        let value = password ? game.password : game.account
        return Button {
            editingPassword = password; credentialDraft = value; editingCredential = true
        } label: {
            Text(value.isEmpty ? (password ? "请输入你的密码" : "请输入你的账号") : password ? String(repeating: "•", count: value.count) : value)
                .foregroundStyle(value.isEmpty ? Color.gray : Color.black)
                .frame(maxWidth: .infinity, alignment: .leading).modifier(LoginFieldStyle())
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier(password ? "login.password" : "login.account")
    }

    private var character: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("创建你的角色").font(.android(size: 25)).foregroundStyle(.white)
                .padding(5).frame(maxWidth: .infinity, alignment: .leading).background(Color(red: 0.12, green: 0.53, blue: 0.90))
            Text("你的称呼，2-4个中文字符").padding(10)
            TextField("", text: $characterName).modifier(LoginFieldStyle())
            Text("你的性别").padding(10)
            HStack {
                ForEach(["男性", "女性"], id: \.self) { value in
                    Button { gender = value } label: {
                        HStack { Image(systemName: gender == value ? "largecircle.fill.circle" : "circle"); Text(value == "男性" ? "男" : "女") }
                    }.frame(maxWidth: .infinity)
                }
            }.frame(height: 55)
            Text(game.notice).font(.android(size: 13)).padding(10)
            Spacer()
            HStack {
                Button("创 建") { game.createCharacter(name: characterName, gender: gender) }.frame(maxWidth: .infinity)
                Button("取 消", action: game.logout).frame(maxWidth: .infinity)
            }.frame(height: 45)
        }.background(.white).foregroundStyle(.black).tint(.black).preferredColorScheme(.light)
    }
}

private struct LoginButtonStyle: ButtonStyle {
    @Environment(\.mudDisplayWidth) private var width
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(Color.black).frame(maxWidth: .infinity, minHeight: width / 10)
            .background(configuration.isPressed ? Color.white.opacity(0.3) : .clear)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.gray, lineWidth: 1))
    }
}

private struct SplashBackground: View {
    var body: some View {
        if let path = Bundle.main.path(forResource: "splash", ofType: "jpeg"),
           let image = UIImage(contentsOfFile: path) {
            Image(uiImage: image).resizable()
        } else {
            Color.white
        }
    }
}

private struct LoginFieldStyle: ViewModifier {
    @Environment(\.mudDisplayWidth) private var width
    func body(content: Content) -> some View {
        content.font(.android(size: 20)).padding(.horizontal, 20).frame(height: width / 11)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.gray, lineWidth: 1))
    }
}
