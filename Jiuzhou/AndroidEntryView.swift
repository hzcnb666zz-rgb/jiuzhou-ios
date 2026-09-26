import SwiftUI
import UIKit

struct AndroidEntryView: View {
    @ObservedObject var game: GameModel
    @State private var registering = false
    @State private var confirmedPassword = ""
    @State private var phone = ""
    @State private var registrationAccount = ""
    @State private var registrationPassword = ""
    @State private var registeringRequest = false
    @State private var characterName = ""
    @State private var gender = "男性"
    @State private var chooseServer = false
    @State private var accountCenter = false
    @State private var settings = false
    @State private var editingCredential = false
    @State private var editingPassword = false
    @State private var credentialDraft = ""
    @State private var showPassword = false
    @FocusState private var credentialFieldFocused: Bool
    @State private var keyboardHeight: CGFloat = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geometry in
        ZStack {
            if game.inWorld { AndroidWorldView(game: game) }
            else if game.needsCharacter { character(width: geometry.size.width, height: geometry.size.height) }
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
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            if let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                keyboardHeight = max(0, UIScreen.main.bounds.height - frame.origin.y)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
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

            VStack(spacing: width * 0.038) {
                // 账号（点击弹窗输入）
                Button {
                    credentialDraft = game.account
                    editingPassword = false
                    editingCredential = true
                } label: {
                    martialDisplayField(icon: "person.fill", value: game.account, placeholder: "你的账号：")
                }.buttonStyle(.plain)

                // 密码（点击弹窗输入）
                Button {
                    credentialDraft = game.password
                    editingPassword = true
                    editingCredential = true
                } label: {
                    martialDisplayField(icon: "lock.fill",
                                        value: game.password.isEmpty ? "" : String(repeating: "●", count: game.password.count),
                                        placeholder: "你的密码：")
                }.buttonStyle(.plain)

                // 服务器选择
                Button { chooseServer = true } label: {
                    HStack(spacing: 7) {
                        Circle().fill(Color(red: 120/255, green: 215/255, blue: 135/255)).frame(width: 7, height: 7)
                        Text("选择服务器").font(.system(size: 13)).foregroundStyle(.white.opacity(0.75))
                        Spacer()
                        Text("高武纪元").font(.system(size: 13)).foregroundStyle(Color(red: 235/255, green: 205/255, blue: 140/255))
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 11).frame(height: 38)
                    .background(MartialTagShape().fill(Color(red: 26/255, green: 19/255, blue: 11/255).opacity(0.68)))
                    .overlay(MartialTagShape().stroke(Color(red: 212/255, green: 178/255, blue: 105/255).opacity(0.7), lineWidth: 1))
                }.buttonStyle(.plain)

                // 登录 / 注册 并排
                HStack(spacing: width * 0.026) {
                    martialButton("登 录", glow: true) {
                        if game.account.isEmpty || game.password.isEmpty {
                            game.status = "请输入账号和密码"
                        } else {
                            game.login()
                        }
                    }
                    martialButton("注 册", glow: false) { registering = true }
                }

                Button("忘记密码？") { game.status = "请联系管理员找回密码" }
                    .font(.system(size: 12)).foregroundStyle(Color(red: 232/255, green: 200/255, blue: 135/255).opacity(0.9))

                Text(game.status == "未连接" ? "" : game.status)
                    .font(.system(size: 11)).foregroundStyle(Color(red: 240/255, green: 215/255, blue: 160/255))
            }
            .frame(width: width * 0.60)
            .frame(maxWidth: .infinity)
            .padding(.top, height * 0.55)

            if chooseServer {
                serverSelectPanel(width: width, height: height)
            }
            if registering {
                registerPopup(width: width, height: height)
            }
            if editingCredential {
                credentialAlert()
            }
        }
        .foregroundStyle(.white).preferredColorScheme(.dark)
        .ignoresSafeArea(.keyboard, edges: .all)
    }

    // 武侠尖角展示框（点击弹窗输入）
    private func martialDisplayField(icon: String, value: String, placeholder: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 228/255, green: 195/255, blue: 125/255))
            if value.isEmpty {
                Text(placeholder)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                Text(value)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 0)
            Image(systemName: "square.and.pencil")
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 228/255, green: 195/255, blue: 125/255).opacity(0.85))
        }
        .padding(.horizontal, 11).frame(height: 42)
        .background(MartialTagShape().fill(Color(red: 26/255, green: 19/255, blue: 11/255).opacity(0.68)))
        .overlay(MartialTagShape().stroke(Color(red: 212/255, green: 178/255, blue: 105/255).opacity(0.75), lineWidth: 1))
        .shadow(color: Color(red: 200/255, green: 160/255, blue: 90/255).opacity(0.28), radius: 5)
    }

    // 武侠菱形按钮
    private func martialButton(_ title: String, glow: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(glow ? Color.white : Color(red: 235/255, green: 205/255, blue: 140/255))
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(
                    MartialTagShape().fill(
                        glow
                        ? LinearGradient(colors: [Color(red: 175/255, green: 122/255, blue: 55/255), Color(red: 120/255, green: 78/255, blue: 34/255)], startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: [Color(red: 38/255, green: 28/255, blue: 16/255), Color(red: 26/255, green: 19/255, blue: 11/255)], startPoint: .top, endPoint: .bottom)
                    )
                )
                .overlay(MartialTagShape().stroke(Color(red: 222/255, green: 188/255, blue: 112/255), lineWidth: 1.1))
                .shadow(color: Color(red: 200/255, green: 155/255, blue: 85/255).opacity(glow ? 0.55 : 0.3), radius: glow ? 8 : 4)
        }.buttonStyle(.plain)
    }

    // MARK: - 账号/密码输入弹窗（系统alert外观，内部真输入框）
    private func credentialAlert() -> some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 0) {
                Text(editingPassword ? "请输入密码：" : "请输入账号：")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18).padding(.bottom, 14)

                // 输入框
                HStack(spacing: 6) {
                    Group {
                        if editingPassword && !showPassword {
                            SecureField("", text: $credentialDraft)
                        } else {
                            TextField("", text: $credentialDraft)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(editingPassword ? .default : .default)
                        }
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .focused($credentialFieldFocused)
                    if editingPassword {
                        Button { showPassword.toggle() } label: {
                            Image(systemName: showPassword ? "eye" : "eye.slash")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.6))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.16)))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                .padding(.horizontal, 16)

                // 分隔线 + 按钮
                Rectangle().fill(Color.white.opacity(0.15)).frame(height: 0.7)
                    .padding(.top, 16)
                HStack(spacing: 0) {
                    Button {
                        credentialFieldFocused = false
                        editingCredential = false
                        credentialDraft = ""
                    } label: {
                        Text("取消")
                            .font(.system(size: 17))
                            .foregroundStyle(Color(red: 0.1, green: 0.5, blue: 1))
                            .frame(maxWidth: .infinity).frame(height: 46)
                    }.buttonStyle(.plain)
                    Rectangle().fill(Color.white.opacity(0.15)).frame(width: 0.7, height: 46)
                    Button {
                        if editingPassword { game.password = credentialDraft }
                        else { game.account = credentialDraft }
                        credentialFieldFocused = false
                        editingCredential = false
                        credentialDraft = ""
                    } label: {
                        Text("确定")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color(red: 0.1, green: 0.5, blue: 1))
                            .frame(maxWidth: .infinity).frame(height: 46)
                    }.buttonStyle(.plain)
                }
            }
            .frame(width: 275)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 44/255, green: 44/255, blue: 47/255)))
            .clipped()
            .offset(y: -keyboardHeight / 2)
            .animation(.easeOut(duration: 0.25), value: keyboardHeight)
        }
        .onAppear {
            showPassword = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                credentialFieldFocused = true
            }
        }
    }

    // MARK: - 注册弹窗
    private func registerPopup(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { registering = false }
            VStack(spacing: 0) {
                // 弹窗标题
                HStack {
                    Text("注 册 账 号")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color(red: 240/255, green: 210/255, blue: 140/255))
                    Spacer()
                    Button { registering = false } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }.buttonStyle(.plain)
                }.padding(.bottom, 18)

                registerField("账号", text: $registrationAccount, placeholder: "字母开头，4-12位")
                registerField("密码", text: $registrationPassword, placeholder: "15位以内", secure: true)
                registerField("确认密码", text: $confirmedPassword, placeholder: "再输一次密码", secure: true)
                registerField("手机号", text: $phone, placeholder: "11位手机号", keyboard: .numberPad, maxLength: 11)

                Button(action: register) {
                    Text("注 册")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            Capsule().fill(
                                LinearGradient(
                                    colors: [Color(red: 160/255, green: 110/255, blue: 50/255), Color(red: 110/255, green: 70/255, blue: 30/255)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                        )
                        .overlay(Capsule().strokeBorder(Color(red: 230/255, green: 190/255, blue: 110/255), lineWidth: 1.2))
                }.buttonStyle(.plain).disabled(registeringRequest)
                    .accessibilityIdentifier("register.submit")

                Text(game.status == "未连接" ? "" : game.status)
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.9)).padding(.top, 8)
            }
            .padding(24)
            .frame(width: width - 50)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(red: 25/255, green: 18/255, blue: 12/255).opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color(red: 210/255, green: 175/255, blue: 100/255).opacity(0.6), lineWidth: 1.2)
            )
        }
    }

    private func registerField(_ label: String, text: Binding<String>, placeholder: String, secure: Bool = false, keyboard: UIKeyboardType = .default, maxLength: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 13)).foregroundStyle(Color(red: 228/255, green: 195/255, blue: 125/255))
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(keyboard)
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .tint(Color(red: 228/255, green: 195/255, blue: 125/255))
            .onChange(of: text.wrappedValue) { newValue in
                if let maxLength, newValue.count > maxLength {
                    text.wrappedValue = String(newValue.prefix(maxLength))
                }
            }
            .padding(.horizontal, 14).frame(height: 42)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(red: 212/255, green: 178/255, blue: 105/255).opacity(0.35), lineWidth: 1))
        }.padding(.bottom, 12)
    }

    private func serverSelectPanel(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("选择服务器")
                    .font(.system(size: 20, weight: .bold)).foregroundStyle(Color(red: 240/255, green: 210/255, blue: 140/255))
                serverItem(name: "高武纪元", status: "流畅", dot: Color(red: 120/255, green: 220/255, blue: 130/255), zone: "1区", recommended: true)
                Button { chooseServer = false } label: {
                    Text("确 定")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Capsule().fill(
                            LinearGradient(colors: [Color(red: 160/255, green: 110/255, blue: 50/255), Color(red: 110/255, green: 70/255, blue: 30/255)], startPoint: .leading, endPoint: .trailing)
                        ))
                        .overlay(Capsule().strokeBorder(Color(red: 230/255, green: 190/255, blue: 110/255), lineWidth: 1.2))
                }.buttonStyle(.plain)
            }
            .padding(24).frame(width: width - 60)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 25/255, green: 18/255, blue: 12/255).opacity(0.95)))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(red: 210/255, green: 175/255, blue: 100/255).opacity(0.6), lineWidth: 1.2))
        }
    }

    private func serverItem(name: String, status: String, dot: Color, zone: String, recommended: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "shield.fill").foregroundStyle(Color(red: 220/255, green: 185/255, blue: 110/255))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(name).font(.system(size: 15)).foregroundStyle(.white)
                    if recommended {
                        Text("推荐").font(.system(size: 10)).foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color(red: 200/255, green: 90/255, blue: 70/255)))
                    }
                }
                HStack(spacing: 5) {
                    Circle().fill(dot).frame(width: 7, height: 7)
                    Text("状态: \(status)").font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer()
            Text(zone).font(.system(size: 13)).foregroundStyle(.white.opacity(0.8))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(red: 200/255, green: 170/255, blue: 100/255).opacity(0.3), lineWidth: 1))
    }

    private func register() {
        guard ![registrationAccount, registrationPassword, confirmedPassword, phone].contains(where: { $0.isEmpty }) else {
            game.status = "请确保各项都不为空！"; return
        }
        guard confirmedPassword == registrationPassword else { game.status = "两次输入密码不一致！"; return }
        guard phone.count == 11, phone.first == "1", phone.allSatisfy({ $0.isNumber }) else {
            game.status = "请输入正确的11位手机号！"; return
        }
        registeringRequest = true
        game.status = "正在注册"
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

    private func character(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            // 仙侠背景（满屏铺满）
            if let path = Bundle.main.path(forResource: "charcreate", ofType: "jpeg"),
               let image = UIImage(contentsOfFile: path) {
                Image(uiImage: image).resizable().scaledToFill().ignoresSafeArea()
            } else {
                Color(red: 13/255, green: 16/255, blue: 26/255).ignoresSafeArea()
            }

            VStack(spacing: 0) {
                // 标题金字 Logo（透明图）
                if let path = Bundle.main.path(forResource: "charcreate_title", ofType: "png"),
                   let image = UIImage(contentsOfFile: path) {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(width: width * 0.80)
                        .padding(.top, height * 0.07)
                } else {
                    Text("创建你的角色").font(.system(size: 25, weight: .bold))
                        .foregroundStyle(Color(red: 235/255, green: 205/255, blue: 140/255))
                        .padding(.top, height * 0.10)
                }

                // 表单卡片（深色磨砂）
                VStack(alignment: .leading, spacing: 14) {
                    Text("你的称呼，2-4个中文字符")
                        .font(.system(size: 13)).foregroundStyle(Color(red: 228/255, green: 195/255, blue: 125/255))
                    TextField("", text: $characterName)
                        .font(.system(size: 15)).foregroundStyle(.white)
                        .tint(Color(red: 228/255, green: 195/255, blue: 125/255))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(.horizontal, 11).frame(height: 42)
                        .background(MartialTagShape().fill(Color(red: 26/255, green: 19/255, blue: 11/255).opacity(0.68)))
                        .overlay(MartialTagShape().stroke(Color(red: 212/255, green: 178/255, blue: 105/255).opacity(0.75), lineWidth: 1))
                        .shadow(color: Color(red: 200/255, green: 160/255, blue: 90/255).opacity(0.28), radius: 5)
                    Text("你的性别").font(.system(size: 13)).foregroundStyle(Color(red: 228/255, green: 195/255, blue: 125/255))
                    HStack(spacing: 14) {
                        genderButton("男", "男性")
                        genderButton("女", "女性")
                    }
                    Text(game.notice).font(.system(size: 12)).foregroundStyle(Color(red: 240/255, green: 215/255, blue: 160/255))
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 25/255, green: 18/255, blue: 12/255).opacity(0.88)))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(red: 210/255, green: 175/255, blue: 100/255).opacity(0.6), lineWidth: 1.2))
                .padding(.horizontal, width * 0.12)
                .padding(.top, height * 0.05)

                Spacer()

                // 创建（左）/取消（右），样式与登录/注册按钮一致
                HStack(spacing: width * 0.026) {
                    martialButton("创 建", glow: true) { game.createCharacter(name: characterName, gender: gender) }
                    martialButton("取 消", glow: false) { game.logout() }
                }
                .frame(width: width * 0.60)
                .padding(.bottom, height * 0.07)
            }
        }
        .foregroundStyle(.white).preferredColorScheme(.dark)
    }

    private func genderButton(_ label: String, _ value: String) -> some View {
        Button {
            gender = value
        } label: {
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .strokeBorder(gender == value ? Color(red: 255/255, green: 230/255, blue: 170/255) : Color.white.opacity(0.45), lineWidth: 1.2)
                        .background(Circle().fill(gender == value ? Color(red: 120/255, green: 78/255, blue: 34/255).opacity(0.9) : Color.white.opacity(0.12)))
                        .frame(width: 17, height: 17)
                    if gender == value {
                        Circle().fill(Color(red: 235/255, green: 205/255, blue: 140/255)).frame(width: 8, height: 8)
                    }
                }
                Text(label).font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(gender == value ? Color(red: 235/255, green: 205/255, blue: 140/255) : .white.opacity(0.85))
            }
            .frame(maxWidth: .infinity).frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 10).fill(gender == value ? Color(red: 38/255, green: 28/255, blue: 16/255).opacity(0.95) : Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(gender == value ? Color(red: 222/255, green: 188/255, blue: 112/255).opacity(0.85) : Color.white.opacity(0.2), lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

private struct SplashBackground: View {
    var body: some View {
        ZStack {
            Color(red: 13/255, green: 16/255, blue: 26/255).ignoresSafeArea()
            if let path = Bundle.main.path(forResource: "splash", ofType: "jpeg"),
               let image = UIImage(contentsOfFile: path) {
                Image(uiImage: image).resizable().scaledToFill().ignoresSafeArea()
            }
        }
    }
}

// 武侠符文标签形状：两端秀气尖角
private struct MartialTagShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let point: CGFloat = 8
        p.move(to: CGPoint(x: rect.minX + point, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - point, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX - point, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + point, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}

private struct ScalelessButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}
