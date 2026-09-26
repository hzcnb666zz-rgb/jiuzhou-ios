import SwiftUI
import UIKit

struct AndroidEntryView: View {
    @ObservedObject var game: GameModel
    @State private var registering = false
    @State private var confirmedPassword = ""
    @State private var phone = ""
    @State private var registrationAccount = ""
    @State private var registrationPassword = ""
    @State private var registrationFieldIndex: Int?
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
        .alert(credentialTitle, isPresented: $editingCredential) {
            if editingPassword { SecureField("", text: $credentialDraft) }
            else { TextField("", text: $credentialDraft).textInputAutocapitalization(.never).autocorrectionDisabled() }
            Button("取消", role: .cancel) {}
            Button("确定") {
                if let index = registrationFieldIndex {
                    switch index {
                    case 0: registrationAccount = credentialDraft
                    case 1: registrationPassword = credentialDraft
                    case 2: confirmedPassword = credentialDraft
                    default: phone = credentialDraft
                    }
                } else if editingPassword { game.password = credentialDraft }
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
                        .frame(maxWidth: .infinity).frame(height: 50).background(.black.opacity(0.4)).padding(.bottom, 5)
                    serverHeading("最近登录分区:", size: 13)
                    serverRow(width: width - 23, height: height, screenWidth: width).padding(.horizontal, 11.5)
                    serverHeading("更 多 分 区", size: 18)
                    serverRow(width: (width - 62) / 2, height: height, screenWidth: width)
                        .padding(.top, 25).padding(.bottom, 65)
                    HStack {
                        Button("会员中心") { accountCenter = true }
                        Button("返回登录") { game.logout(); chooseServer = false }
                    }.buttonStyle(LoginButtonStyle(heightDivisor: 9)).padding(.horizontal, 10)
                    #if DEBUG
                    Button("服务器设置") { settings = true }.font(.android(size: 13)).padding(10)
                    #endif
                    Text(game.status).font(.android(size: 13)).foregroundStyle(.white).padding(10)
                    if game.connecting { ProgressView() }
                    Spacer(minLength: 0)
                }
            } else if registering {
                registration(width: width)
            } else {
                VStack(spacing: 0) {
                    Spacer().frame(height: height * 0.10)
                    // 标题区
                    Text("九州书剑录")
                        .font(.system(size: width / 9, weight: .heavy))
                        .foregroundStyle(.white)
                        .shadow(color: .blue.opacity(0.9), radius: 14, x: 0, y: 0)
                        .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 2)
                    Text("以剑为书 · 以武入道")
                        .font(.android(size: 14))
                        .foregroundStyle(Color(red: 180/255, green: 210/255, blue: 255/255))
                        .padding(.top, 8)
                    Spacer()
                    // 登录表单
                    VStack(spacing: 14) {
                        HStack(spacing: 8) {
                            Button("登 录") { registering = false }
                                .buttonStyle(.plain).frame(maxWidth: .infinity, minHeight: 40)
                            Button("注 册") { registering = true }
                                .buttonStyle(.plain).frame(maxWidth: .infinity, minHeight: 40)
                        }.buttonStyle(LoginTabStyle(active: !registering))
                        credentialField(password: false)
                        credentialField(password: true)
                        Button {
                            if game.account.isEmpty || game.password.isEmpty {
                                game.status = "请输入账号和密码"
                            } else {
                                game.status = "请选择分区"; chooseServer = true
                            }
                        } label: {
                            Text("进入游戏")
                                .font(.android(size: 20)).fontWeight(.bold)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .foregroundStyle(.white)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(red: 20/255, green: 60/255, blue: 140/255).opacity(0.55))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(Color(red: 120/255, green: 190/255, blue: 255/255), lineWidth: 1.5)
                                        .shadow(color: .blue.opacity(0.6), radius: 8)
                                )
                        }.disabled(registeringRequest)
                        Button("退 出") { game.logout(); game.password = "" }
                            .font(.android(size: 14)).foregroundStyle(.white.opacity(0.8))
                            .padding(.top, 4)
                        Text(game.status == "未连接" ? "" : game.status)
                            .font(.android(size: 13)).foregroundStyle(.white).padding(.top, 4)
                    }.padding(.horizontal, 28)
                    Spacer().frame(height: height * 0.12)
                }
            }
        }.foregroundStyle(.white).font(.android(size: 18)).preferredColorScheme(.dark)
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

    private var credentialTitle: String {
        if let index = registrationFieldIndex {
            return ["请输4-12位的ID(字母开头可包含数字)：", "请输入15位以内的密码：", "请再次输入密码：", "请输入11位数字的手机号："][index]
        }
        return editingPassword ? "请输入密码：" : "请输入账号："
    }

    private func registration(width: CGFloat) -> some View {
        ScrollView {
            ZStack(alignment: .top) {
                HStack(spacing: 0) {
                    Button("登 录") { registering = false }.buttonStyle(LoginButtonStyle())
                    Text("注 册").frame(maxWidth: .infinity).frame(height: 45)
                }
                VStack(alignment: .leading, spacing: 0) {
                    registrationField("你的账号", hint: "字母开头，4-12位字母或数字", value: registrationAccount, index: 0)
                    registrationField("你的密码", hint: "15位以内字母或数字", value: registrationPassword, index: 1)
                    registrationField("确认你的密码", hint: "请再输一次密码", value: confirmedPassword, index: 2)
                    registrationField("你的手机号", hint: "请输入您的手机号码", value: phone, index: 3)
                    Button("注 册", action: register).buttonStyle(LoginButtonStyle())
                        .accessibilityIdentifier("register.submit")
                        #if DEBUG
                        .accessibilityValue(String(Double(width)))
                        #endif
                        .padding(.leading, 13).padding(.trailing, 16).padding(.top, 43)
                        .disabled(registeringRequest)
                    Text(game.status == "未连接" ? "" : game.status).font(.android(size: 13)).padding(10)
                }.padding(.top, 70)
            }.padding(1)
        }.disabled(registeringRequest)
    }

    private func registrationField(_ label: String, hint: String, value: String, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.android(size: 18)).foregroundStyle(Color(red: 180/255, green: 210/255, blue: 255/255)).padding(.horizontal, 4).frame(height: 36)
            Button {
                registrationFieldIndex = index
                editingPassword = false
                credentialDraft = value
                editingCredential = true
            } label: {
                Text(value.isEmpty ? hint : value).font(.android(size: 16))
                    .foregroundStyle(value.isEmpty ? Color.white.opacity(0.5) : Color.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).modifier(LoginFieldStyle())
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).padding(.horizontal, 10)
                .accessibilityIdentifier("register.\(["account", "password", "confirmation", "phone"][index])")
        }.padding(.bottom, 18)
    }

    private func register() {
        guard ![registrationAccount, registrationPassword, confirmedPassword, phone].contains(where: { $0.isEmpty }) else {
            game.status = "请确保各项都不为空！"; return
        }
        guard confirmedPassword == registrationPassword else { game.status = "两次输入密码不一致！"; return }
        registeringRequest = true
        game.status = "正在注册"
        // loginx.xml hides the email field and supplies this default.
        let request = LegacyService.registration(account: registrationAccount, password: registrationPassword, phone: phone, email: "a1@qq.com")
        Task { @MainActor in
            defer { registeringRequest = false }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      let result = String(data: data, encoding: .utf8), !result.isEmpty else {
                    game.status = "注册失败，服务器连接错误！"; return
                }
                game.status = result == "Error" ? "注册失败，服务器链接错误！" : result
                if result == "注册成功" {
                    game.account = registrationAccount; game.password = registrationPassword
                    registering = false
                }
            } catch { game.status = "注册失败，请检查网络！" }
        }
    }

    private func credentialField(password: Bool) -> some View {
        let value = password ? game.password : game.account
        return Button {
            registrationFieldIndex = nil
            editingPassword = password; credentialDraft = value; editingCredential = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: password ? "lock.fill" : "person.fill")
                    .foregroundStyle(Color(red: 120/255, green: 190/255, blue: 255/255))
                Text(value.isEmpty ? (password ? "请输入密码" : "请输入账号") : password ? String(repeating: "•", count: value.count) : value)
                    .foregroundStyle(value.isEmpty ? Color.white.opacity(0.5) : Color.white)
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.35)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(red: 120/255, green: 190/255, blue: 255/255).opacity(0.6), lineWidth: 1))
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
    var heightDivisor: CGFloat = 10
    @Environment(\.mudDisplayWidth) private var width
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(Color.white).frame(maxWidth: .infinity, minHeight: width / heightDivisor)
            .background(configuration.isPressed ? Color.white.opacity(0.2) : Color.black.opacity(0.25))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(red: 120/255, green: 190/255, blue: 255/255).opacity(0.5), lineWidth: 1))
    }
}

private struct LoginTabStyle: ButtonStyle {
    var active: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(active ? Color.white : Color.white.opacity(0.6))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(active ? Color(red: 30/255, green: 80/255, blue: 160/255).opacity(0.6) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(red: 120/255, green: 190/255, blue: 255/255).opacity(active ? 0.8 : 0.3), lineWidth: 1)
            )
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
        content.font(.android(size: 18)).padding(.horizontal, 16).frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.35)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(red: 120/255, green: 190/255, blue: 255/255).opacity(0.6), lineWidth: 1))
    }
}
