import SwiftUI

struct AndroidAccountView: View {
    @ObservedObject var game: GameModel
    let close: () -> Void
    @State private var phone = ""
    @State private var email = ""
    @State private var serverName = "我的测试服"
    @State private var serverHost = "127.0.0.1"
    @State private var serverPort = "3000"
    @State private var editingServer = false
    @State private var editing = ""
    @State private var draft = ""
    @State private var editVisible = false
    @State private var busy = false
    @State private var status = ""

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack {
                if let url = Bundle.main.url(forResource: "ucenterbg", withExtension: "jpeg"), let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image).resizable()
                }
                VStack(spacing: 0) {
                    Text(editingServer ? "服 务 器 设 置" : "用  户  中  心")
                        .font(.android(size: 25)).frame(height: 40).padding(.top, 40)
                    if editingServer {
                        VStack(spacing: 0) {
                            serverField("名称：", value: $serverName)
                            serverField("地址：", value: $serverHost)
                            serverField("端口：", value: $serverPort)
                        }.padding(.top, 20)
                        Spacer(minLength: 0)
                        HStack {
                            Button("确 认", action: updateServer)
                            Button("取 消") { editingServer = false }
                        }.buttonStyle(AccountButtonStyle(height: width / 9))
                    } else {
                        VStack(spacing: 5) {
                            accountRow("账　号：" + game.account, key: nil, width: width)
                            accountRow("密　码：" + game.password, key: "newpwd", width: width)
                            accountRow("手机号：" + phone, key: "phone", width: width)
                            accountRow("邮　箱：" + email, key: "email", width: width)
                            Color.clear.frame(height: width / 10)
                        }.padding(.top, 20)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("我 的 服 务 器").font(.android(size: 18)).frame(maxWidth: .infinity).frame(height: 40)
                                Text("名　称：" + serverName).frame(height: width / 10)
                                Text("地　址：" + serverHost).frame(height: width / 10)
                                Text("端　口：" + serverPort).frame(height: width / 10)
                                Text("密　钥：123456789abcd").frame(height: 35)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HStack {
                            Button("更改信息") { editingServer = true }.accessibilityIdentifier("account.server")
                            Button("关 闭", action: close)
                        }.buttonStyle(AccountButtonStyle(height: width / 9))
                    }
                    if !status.isEmpty { Text(status).font(.android(size: 13)).padding(5) }
                    if busy { ProgressView() }
                }.padding(8).padding(.horizontal, 8).disabled(busy)
            }.foregroundStyle(.black).font(.android(size: 13)).tint(.black)
        }.task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-check-account") { return }
            #endif
            await request()
        }
        .alert(editing == "newpwd" ? "请输入新密码：" : editing == "phone" ? "请输入手机号：" : "请输入邮箱：", isPresented: $editVisible) {
            TextField("", text: $draft).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("确定") {
                guard !draft.isEmpty else { status = "请输入内容"; return }
                let key = editing, value = draft
                Task { await request(changes: [key: value]) }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func accountRow(_ text: String, key: String?, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text(text).padding(.leading, 5).frame(maxWidth: .infinity, alignment: .leading)
            if let key {
                Button("修 改") { editing = key; draft = ""; editVisible = true }
                    .frame(width: 65).accessibilityIdentifier("account." + key)
            }
        }.frame(height: width / 10)
    }

    private func serverField(_ label: String, value: Binding<String>) -> some View {
        HStack {
            Text(label)
            TextField("", text: value).textInputAutocapitalization(.never).autocorrectionDisabled()
                .overlay(alignment: .bottom) { Color.gray.frame(height: 1) }
        }.frame(height: 40)
    }

    private func updateServer() {
        guard !serverName.isEmpty, !serverHost.isEmpty, let port = UInt16(serverPort), port > 0, port < 65535 else {
            status = "请保证信息完整，端口有效"; return
        }
        let value = "\(serverName)&\(serverHost)&\(port)&\(Int(port) + 1)"
        Task { await request(changes: ["myserver": value]) }
    }

    @MainActor private func request(changes: [String: String] = [:]) async {
        busy = true
        defer { busy = false }
        do {
            let request = LegacyService.accountRequest(account: game.account, password: game.password, changes: changes)
            let (data, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let text = String(data: data, encoding: .utf8) else { status = "服务器连接错误"; return }
            if text.hasPrefix("$i#") {
                let fields = text.dropFirst(3).components(separatedBy: "|")
                guard fields.count >= 5 else { status = "服务器返回数据不完整"; return }
                phone = fields[2]; email = fields[3]
                let server = fields[4].components(separatedBy: "&")
                if server.count >= 3 { serverName = server[0]; serverHost = server[1]; serverPort = server[2] }
            } else {
                status = text
                if text.hasPrefix("密码修改成功"), let value = changes["newpwd"] { game.password = value }
                if text.hasPrefix("手机号绑定成功"), let value = changes["phone"] { phone = value }
                if text.hasPrefix("邮箱绑定成功"), let value = changes["email"] { email = value }
                if text.hasPrefix("测试服务器修改成功") { editingServer = false }
            }
        } catch is CancellationError { }
        catch { status = "连接失败，请检查网络" }
    }
}

private struct AccountButtonStyle: ButtonStyle {
    let height: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(maxWidth: .infinity).frame(height: height)
            .background(configuration.isPressed ? Color.white.opacity(0.3) : .clear)
    }
}
