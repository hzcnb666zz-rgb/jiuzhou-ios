import SwiftUI
import UIKit

struct AndroidEntryView: View {
    @ObservedObject var game: GameModel
    @State private var registering = false
    @State private var confirmedPassword = ""
    @State private var characterName = ""
    @State private var gender = "男性"
    @State private var chooseServer = false
    @State private var settings = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if game.inWorld { AndroidWorldView(game: game) }
            else if game.needsCharacter { character }
            else { login }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active && game.inWorld && !game.connected { game.notice = "连接已断开，请重新连接" }
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

    private var login: some View {
        ZStack(alignment: .top) {
            SplashBackground().ignoresSafeArea()
            if chooseServer {
                VStack(spacing: 10) {
                    Text("分区列表").font(.system(size: 18)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 50).background(.black)
                    Button { game.login() } label: {
                        HStack {
                            Image("GameMark").resizable().scaledToFit().frame(width: 48, height: 48)
                            Text("本地九州书剑录")
                            Spacer()
                        }.padding(8)
                    }.buttonStyle(LoginButtonStyle()).disabled(game.connecting || game.connected)
                    Text(game.status).font(.system(size: 13)).padding(10)
                    if game.connecting { ProgressView() }
                    Spacer()
                    HStack {
                        Button("服务器设置") { settings = true }
                        Spacer()
                        Button("返回") { game.logout(); chooseServer = false }
                    }.padding(10)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            Button("登 录") { registering = false }
                            Button("注 册") { registering = true }
                        }.buttonStyle(LoginButtonStyle()).padding(.bottom, 15)
                        fieldLabel(registering ? "创建你的账号" : "你的账号：")
                        TextField("请输入你的账号", text: $game.account)
                            .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .modifier(LoginFieldStyle())
                        fieldLabel(registering ? "创建你的密码" : "你的密码：")
                        SecureField("请输入你的密码", text: $game.password)
                            .textContentType(registering ? .newPassword : .password).modifier(LoginFieldStyle())
                        if registering {
                            fieldLabel("确认你的密码")
                            SecureField("请再输一次密码", text: $confirmedPassword).modifier(LoginFieldStyle())
                        }
                        HStack(spacing: 8) {
                            Button(registering ? "注 册" : "登 录") {
                                if registering && confirmedPassword != game.password {
                                    game.status = "两次输入的密码不一致"
                                } else if game.account.isEmpty || game.password.isEmpty {
                                    game.status = "请输入账号和密码"
                                } else {
                                    game.status = "请选择分区"; chooseServer = true
                                }
                            }
                            Button("退 出") { game.logout(); game.password = "" }
                        }.buttonStyle(LoginButtonStyle()).padding(.top, 50)
                        Text(game.status == "未连接" ? "" : game.status).font(.system(size: 13)).padding(10)
                    }.padding(.horizontal, 10)
                }
            }
        }.foregroundStyle(.black).font(.system(size: 18)).tint(.black).preferredColorScheme(.light)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text).padding(.leading, 20).frame(height: 80, alignment: .center)
    }

    private var character: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("创建你的角色").font(.system(size: 25)).foregroundStyle(.white)
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
            Text(game.notice).font(.system(size: 13)).padding(10)
            Spacer()
            HStack {
                Button("创 建") { game.createCharacter(name: characterName, gender: gender) }.frame(maxWidth: .infinity)
                Button("取 消", action: game.logout).frame(maxWidth: .infinity)
            }.frame(height: 45)
        }.background(.white).foregroundStyle(.black).tint(.black).preferredColorScheme(.light)
    }
}

private struct LoginButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(Color.black).frame(maxWidth: .infinity, minHeight: 45)
            .background(configuration.isPressed ? Color.white.opacity(0.3) : .clear)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.gray, lineWidth: 1))
    }
}

private struct SplashBackground: View {
    var body: some View {
        if let path = Bundle.main.path(forResource: "splash", ofType: "jpeg"),
           let image = UIImage(contentsOfFile: path) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Color.white
        }
    }
}

private struct LoginFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.system(size: 20)).padding(.horizontal, 20).frame(height: 40)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.gray, lineWidth: 1))
    }
}
