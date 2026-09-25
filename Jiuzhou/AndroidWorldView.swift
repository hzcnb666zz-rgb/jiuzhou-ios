import SwiftUI
import UIKit

private struct InteractionTextHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct BundleImage: View {
    let name: String
    let ext: String
    var body: some View {
        if let path = Bundle.main.path(forResource: name, ofType: ext),
           let image = UIImage(contentsOfFile: path) {
            Image(uiImage: image).resizable()
        } else {
            Color.clear
                .onAppear { assertionFailure("Missing Android image: \(name).\(ext)") }
        }
    }
}

struct AndroidButtonStyle: ButtonStyle {
    var image: String? = nil
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if image == "exitbt" && !configuration.isPressed {
                    RoundedRectangle(cornerRadius: 5, style: .circular)
                        .strokeBorder(Color(red: 220/255, green: 237/255, blue: 200/255).opacity(111/255), lineWidth: 1)
                } else if let image {
                    BundleImage(name: image == "buttonx1" ? (configuration.isPressed ? "buttonx2" : "buttonx1") : image == "bt1" ? (configuration.isPressed ? "bt2" : "bt1") : image + (configuration.isPressed ? "2" : ""), ext: "png")
                } else {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(configuration.isPressed ? Color(red: 13/255, green: 118/255, blue: 225/255) :
                                Color.white.opacity(filled ? 0.13 : 0))
                }
            }
            .overlay {
                if image == nil {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(configuration.isPressed ? Color(red: 244/255, green: 3/255, blue: 201/255) : Color(red: 180/255, green: 105/255, blue: 62/255).opacity(51/255), lineWidth: 1)
                }
            }
    }
}

private struct CombatEffect: View {
    let text: String
    let unit: CGFloat
    @State private var scale: CGFloat = 0
    @State private var rise: CGFloat = 0
    @State private var opacity = 0.0

    var body: some View {
        GeometryReader { geometry in
            let pixels = UIScreen.main.scale
            ZStack(alignment: .topLeading) {
                MudRichText(raw: text, send: { _ in }).foregroundStyle(Color(white: 0.2)).offset(x: 2, y: 2)
                MudRichText(raw: text, send: { _ in }).foregroundStyle(.white).offset(x: 1, y: 1)
                MudRichText(raw: text, send: { _ in }).foregroundStyle(.red)
            }.font(.android(size: unit / 22))
                .scaleEffect(scale, anchor: .bottomLeading).opacity(opacity)
                .offset(x: 10 / pixels, y: max(0, geometry.size.height - 100 / pixels - unit / 22) - rise / pixels)
        }.allowsHitTesting(false).accessibilityIdentifier("world.combatEffect")
            .task {
                withAnimation(.easeInOut(duration: 0.1)) { scale = 2; rise = 100; opacity = 1 }
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 1.8)) { rise = 1100 }
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 1.8)) { opacity = 0 }
            }
    }
}

@MainActor
struct AndroidWorldView: View {
    @ObservedObject var game: GameModel
    @StateObject private var voice = MudVoice()
    @AppStorage("androidMode") private var mode = "night"
    @AppStorage("androidChatDivisor") private var chatDivisor = 5
    @FocusState private var inputFocused: Bool
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
    @AppStorage("centerCommand") private var centerCommand = ""
    @State private var centerEditVisible = false
    @State private var interactionTextHeight: CGFloat = 0

    private let compass = ["northwest", "north", "northeast", "west", "", "east", "southwest", "south", "southeast"]
    private var ink: Color { mode == "day" ? Color(red: 0.31, green: 0.15, blue: 0.08) : mode == "mud" ? Color(white: 0.67) : .white }
    private var background: String { mode == "day" ? "bk1.jpeg" : mode == "mud" ? "huashan.png" : "bk2.jpeg" }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            // Android uses the actual screen width (scrw) for every main-face dimension.
            let unit = width
            ZStack(alignment: .top) {
                BundleImage(name: background.replacingOccurrences(of: ".jpeg", with: "").replacingOccurrences(of: ".png", with: ""), ext: background.hasSuffix("jpeg") ? "jpeg" : "png")
                VStack(spacing: 0) {
                    // Keep the chat rail's height stable. New messages must not
                    // resize the world/detail area underneath it.
                    ZStack(alignment: .bottomLeading) {
                        if !game.chatMessages.isEmpty {
                            messages(Array(game.chatMessages.suffix(100)))
                        }
                    }
                    .frame(height: unit / CGFloat(max(1, chatDivisor)))
                    .clipped()
                    rule
                    titleBar(unit: unit)
                    rule
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(game.objects) { object in
                                        Button { game.act(object.command) } label: {
                                            VStack(spacing: 0) {
                                                if let fraction = game.objectHealth[object.command] {
                                                    GeometryReader { g in
                                                        Color.red.frame(width: g.size.width * fraction)
                                                    }.frame(height: 4)
                                                }
                                                MudRichText(raw: object.display, send: game.act)
                                                    .foregroundStyle(mode == "night" ? Color(red: 221/255, green: 187/255, blue: 153/255) : ink)
                                                    .font(.android(size: unit / 35)).multilineTextAlignment(.center)
                                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color(red: 180/255, green: 105/255, blue: 62/255).opacity(0.2)))
                                            }.padding(.vertical, 3)
                                                .background(mode == "night" ? Color(white: 238/255).opacity(34/255) : .clear)
                                                .padding(1).frame(width: unit / 7, height: unit / 10)
                                        }.buttonStyle(.plain)
                                    }
                                }.padding(.top, 2).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            ForEach(extraExits) { exit in
                                Button { game.act(exit.command) } label: {
                                    MudRichText(raw: exit.display, send: game.act)
                                        .font(.android(size: unit / 35)).multilineTextAlignment(.center)
                                        .frame(width: unit / 7, height: unit / 11)
                                }.buttonStyle(AndroidButtonStyle(image: mode == "night" ? "exitbt" : nil))
                                    .padding(.top, 3).padding(.bottom, 1)
                            }
                        }.frame(width: unit / 7 + 2)
                        Rectangle().fill(Color(white: 0.4)).frame(width: 1)
                        VStack(spacing: 0) {
                            ZStack(alignment: .topLeading) {
                                VStack(spacing: 0) {
                                    if !game.descriptionHidden && !game.fighting {
                                        MudRichText(raw: game.description, send: game.act)
                                            .font(.android(size: (unit - 14) / 25))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .fixedSize(horizontal: false, vertical: true).padding(5)
                                        rule
                                    }
                                    messages(game.fighting ? game.fightMessages : game.messages)
                                 }
                                 if let dialog = game.dialog {
                                     if dialog.kind == "map" { mapPanel(dialog, unit: unit) }
                                     else if dialog.kind == "npc" || dialog.kind == "item" {
                                         isolatedInteraction(unit: unit)
                                     } else if dialog.kind == "pages" {
                                         pagesPanel(dialog, unit: unit)
                                     } else if dialog.kind == "interaction" {
                                         interaction(unit: unit, usesNPCLayout: dialog.kind == "npc")
                                     }
                                }
                                if !game.notice.isEmpty {
                                    MudRichText(raw: game.notice, send: game.act).font(.android(size: 14)).foregroundStyle(.cyan)
                                        .padding(2).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color(white: 0.4)).allowsHitTesting(false)
                                        .task(id: game.notice) {
                                            let notice = game.notice
                                            try? await Task.sleep(nanoseconds: 5_000_000_000)
                                            if !Task.isCancelled && game.notice == notice { game.notice = "" }
                                        }
                                }
                                ForEach(game.combatEffects) { effect in
                                    CombatEffect(text: effect.text, unit: unit)
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
                // NPC and item details are isolated from the transient top chat rail.
                // The messages remain available in the history panel instead of
                // consuming or covering the detail panel's viewport.
                if menuVisible { mainMenu(unit: unit).frame(maxHeight: .infinity) }
                if historyVisible { historyPanel(unit: unit) }
                if let popup = game.popup { popupMenu(popup, unit: unit) }
                if game.dialog?.kind == "confirmation" { confirmation(unit: unit) }
            }
            .foregroundStyle(ink).font(.android(size: unit / 28))
            .environment(\.mudDisplayWidth, unit)
        }
        .onAppear {
            #if DEBUG
            menuVisible = ProcessInfo.processInfo.arguments.contains("--ui-check-menu")
            historyVisible = ProcessInfo.processInfo.arguments.contains("--ui-check-history")
            #endif
            inputFocused = game.dialog?.inputCommand != nil
        }
        .onChange(of: game.dialog?.id) { _ in
            dialogInput = ""
            inputFocused = game.dialog?.inputCommand != nil
        }
        .onChange(of: game.voiceFilename) { filename in
            if let filename { voice.play(filename: filename); game.voiceFilename = nil }
        }
        .onChange(of: game.voiceRecorderVisible) { visible in if !visible { voice.cancel() } }
        .onDisappear { voice.cancel() }
        .alert("请输入快捷键指令：", isPresented: $centerEditVisible) {
            TextField("指令", text: $editCommand)
            Button("确定") { centerCommand = editCommand; game.buttons.removeAll { $0.slot == "bs" } }
            Button("取消", role: .cancel) {}
        }
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

    private func titleBar(unit: CGFloat) -> some View {
        HStack(spacing: 3) {
            MudRichText(raw: game.room, send: game.act).font(.android(size: (unit - 14) / 18))
                .lineLimit(1).minimumScaleFactor(0.6).padding(3).padding(.leading, 18).padding(.bottom, 2)
            GeometryReader { bounds in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(game.topActions) { item in
                        Button { game.act(item.command) } label: {
                            MudRichText(raw: item.display, send: game.act).font(.android(size: unit / 30))
                                .padding(.horizontal, 3).frame(height: max(0, unit / 13 - 6))
                                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color(red: 180/255, green: 105/255, blue: 62/255).opacity(0.2)))
                                .padding(.horizontal, 4)
                        }.buttonStyle(AndroidButtonStyle()).padding(.vertical, 3)
                    }
                }.frame(minWidth: bounds.size.width, alignment: .trailing)
            }
            }.frame(height: unit / 13)
            Button(game.descriptionToggleLabel) { game.toggleDescription() }
                .font(.android(size: (unit - 14) / 25)).padding(.horizontal, 8).frame(height: unit / 13)
                .background(Color.white.opacity(0.13))
        }.padding(3).frame(minHeight: 40)
            .background { if mode == "night" { BundleImage(name: "bar", ext: "png") } }
    }

    private func messages(_ items: [GameMessage]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(items) { item in
                        MudRichText(raw: item.text, send: game.act)
                            .frame(maxWidth: .infinity, alignment: .leading).id(item.id)
                    }
                }.padding(5)
            }.onChange(of: items.last?.id) { id in
                if let id { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }

    private var extraExits: [MudAction] {
        let hidden = Set(["发送坐标", "任务"])
        return game.exits.filter { exit in
            !hidden.contains(exit.label) &&
            !compass.filter { !$0.isEmpty }.contains { exit.slot == $0 || exit.slot == $0 + "up" || exit.slot == $0 + "down" }
        }
    }

    private func exits(unit: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if game.voiceRecorderVisible {
                HStack(spacing: 2) {
                    VStack(spacing: 2) {
                        ProgressView(value: voice.level).tint(.green).frame(maxHeight: .infinity)
                        Button { voice.play() } label: {
                            Text(voice.status).font(.android(size: 15)).frame(maxWidth: .infinity, maxHeight: .infinity)
                        }.buttonStyle(AndroidButtonStyle()).disabled(voice.recording || voice.busy)
                    }
                    Button {
                        if voice.recording { voice.finish(send: game.act) } else { voice.start() }
                    } label: {
                        Text(voice.recording ? "结束并发送" : "开始录音").font(.android(size: 15))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }.buttonStyle(AndroidButtonStyle()).disabled(voice.busy)
                }.padding(3)
            } else if game.customButtonsVisible {
                VStack(spacing: 0) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach((row * 5 + 1)...(row * 5 + 5), id: \.self) { slot in
                                quickButton(slot, height: (unit * 3 / 11 - 2) / 2 - 2, unit: unit).padding(1)
                            }
                        }
                    }
                }.padding(.vertical, 1)
            } else {
                GeometryReader { g in
                    ForEach(Array(compass.enumerated()), id: \.offset) { index, slot in
                        let column = index % 3
                        let row = index / 3
                        if slot.isEmpty {
                            Button { game.act(game.buttons.first { $0.slot == "bs" }?.command ?? centerCommand) } label: {
                                MudRichText(raw: game.room, send: game.act).font(.android(size: unit / 33))
                                    .lineLimit(1).minimumScaleFactor(0.5)
                                    .frame(width: unit / 4, height: unit / 15)
                            }.buttonStyle(AndroidButtonStyle(image: mode == "night" ? "exitbt" : nil))
                                .simultaneousGesture(LongPressGesture().onEnded { _ in editCommand = centerCommand; centerEditVisible = true })
                                .position(x: g.size.width / 2, y: g.size.height / 2)
                        } else if let exit = game.exits.first(where: { $0.slot == slot || $0.slot == slot + "up" || $0.slot == slot + "down" }) {
                            let bw = unit / 5
                            let bh = unit / 12
                            Button { game.act(exit.command) } label: {
                                MudRichText(raw: exit.display, send: game.act).font(.android(size: unit / 33))
                                    .lineLimit(2).minimumScaleFactor(0.65).multilineTextAlignment(.center)
                                    .frame(width: bw, height: bh)
                            }.buttonStyle(AndroidButtonStyle(image: mode == "night" ? imageName(slot) : nil))
                                .position(x: column == 0 ? bw / 2 : column == 1 ? g.size.width / 2 : g.size.width - bw / 2,
                                          y: row == 0 ? bh / 2 : row == 1 ? g.size.height / 2 : g.size.height - bh / 2)
                        }
                    }
                }
            }
            VStack(spacing: 0) {
                Button { game.toggleCustomButtons() } label: {
                    Text(game.customButtonsVisible ? "关闭" : "自定")
                        .font(.android(size: unit / 31))
                        .frame(maxWidth: .infinity).frame(height: (unit * 3 / 11 - 2) / 2 - 2)
                }.buttonStyle(AndroidButtonStyle()).accessibilityIdentifier("world.custom").padding(1)
                quickButton(11, height: (unit * 3 / 11 - 2) / 2 - 2, unit: unit).padding(1)
            }.padding(.vertical, 1).frame(width: unit / 7 + 2, height: unit * 3 / 11, alignment: .top)
        }.frame(height: game.customButtonsVisible ? unit * 3 / 11 : unit * 4 / 13, alignment: .top).padding(.leading, 2)
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

    private func quickButton(_ slot: Int, height: CGFloat, unit: CGFloat) -> some View {
        let item = quickAction(slot)
        return MudRichText(raw: item.display, send: game.act)
            .font(.android(size: unit / 31)).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).frame(height: height)
            .foregroundStyle(slot >= 12 ? Color(white: 170/255) : ink)
            .background(Color.white.opacity(slot >= 12 ? 0.13 : 0))
            .overlay {
                if slot < 12 { RoundedRectangle(cornerRadius: 3).stroke(Color(red: 0.71, green: 0.41, blue: 0.24).opacity(0.2)) }
            }
            .contentShape(Rectangle())
            .onTapGesture { game.act(item.command) }
            .onLongPressGesture {
                editingSlot = slot; editLabel = item.label; editCommand = item.command; editVisible = true
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("world.slot.\(slot)")
    }

    private func bottomBar(unit: CGFloat) -> some View {
        HStack(spacing: 0) {
            Button { game.dialog = GameDialog(text: "请输入指令：", inputCommand: "$txt#") } label: {
                BundleImage(name: "command", ext: "png").scaledToFit().frame(width: 40, height: unit / 8)
            }.buttonStyle(.plain).accessibilityLabel("输入指令")
            ForEach(12...17, id: \.self) { slot in
                quickButton(slot, height: unit / 8, unit: unit).frame(width: max(0, (unit - 2 - 40 - 260) / 7 + 40))
            }
            Button { menuVisible.toggle() } label: {
                BundleImage(name: "mainbt", ext: "png").scaledToFit().frame(width: max(0, (unit - 2 - 40 - 260) / 7 + 20), height: unit / 8)
            }.buttonStyle(.plain).accessibilityLabel("菜单")
        }.background(Color.white.opacity(0.13)).accessibilityIdentifier("world.bottom")
    }

    private func stats(unit: CGFloat) -> some View {
        let columns = game.statsLayout.columns
        return VStack(spacing: 0) {
            ForEach(0..<((game.stats.count + columns - 1) / columns), id: \.self) { row in
            HStack(spacing: 0) {
            ForEach((row * columns)..<min(game.stats.count, (row + 1) * columns), id: \.self) { index in
                let stat = game.stats[index]
                Button { game.act(stat.command) } label: {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Color.black
                            color(stat.color).frame(width: g.size.width * stat.fraction)
                            MudRichText(raw: stat.label + (stat.value.contains("/") ? "" : ":" + stat.value), send: game.act)
                                .font(.android(size: unit / CGFloat(game.statsLayout.fontDivisor))).lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .overlay(Rectangle().stroke(Color(white: 0.38), lineWidth: 1))
                    }.frame(height: unit / CGFloat(game.statsLayout.heightDivisor))
                }.buttonStyle(.plain).frame(maxWidth: .infinity).padding(.horizontal, 1).padding(.bottom, 1)
                    .accessibilityIdentifier("world.stat.\(index)")
            }
            }
        }
    }
    }

    private func color(_ hex: String) -> Color {
        let digits = hex.replacingOccurrences(of: "#", with: "")
        let rgbDigits = digits.count > 6 ? String(digits.suffix(6)) : digits
        let value = UInt32(rgbDigits, radix: 16) ?? 0
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }

    private func interaction(unit: CGFloat, usesNPCLayout: Bool = false) -> some View {
        GeometryReader { geometry in
        VStack(alignment: .leading, spacing: 0) {
            if let dialog = game.dialog {
                let inputHeight: CGFloat = dialog.inputCommand == nil ? 0 : 40
                let actionHeight = interactionActionHeight(dialog, unit: unit)
                let availableHeight = max(0, geometry.size.height - 11 - inputHeight)
                let descriptionHeight = usesNPCLayout
                    ? min(interactionTextHeight, max(0, availableHeight - actionHeight))
                    : min(interactionTextHeight, max(0, availableHeight - actionHeight))
                ScrollView {
                    MudRichText(raw: dialog.text, send: game.act).font(.android(size: unit / 30))
                        .padding(5).frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(GeometryReader { textGeometry in
                            Color.clear.preference(key: InteractionTextHeight.self, value: textGeometry.size.height)
                        })
                }.frame(height: descriptionHeight)
                    .accessibilityIdentifier("interaction.description")
                if dialog.inputCommand != nil {
                    HStack(spacing: 0) {
                        TextField("", text: $dialogInput).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($inputFocused)
                            .keyboardType(dialog.numeric ? .numberPad : .default).onSubmit { game.submitInput(dialogInput) }
                            .font(.android(size: 15)).padding(.leading, 15).frame(height: 40)
                            .background(BundleImage(name: "input_bg", ext: "png"))
                        Button { game.submitInput(dialogInput) } label: {
                            Text("确定").font(.android(size: 14)).frame(width: 65, height: 40).contentShape(Rectangle())
                        }.buttonStyle(AndroidButtonStyle())
                        #if DEBUG
                        .accessibilityValue(String(Double(unit)))
                        #endif
                    }.padding(.horizontal, 5)
                }
                let availableWidth = max(0, geometry.size.width - 14)
                let dialogColumns = dialog.layout.resolvedColumns(for: dialog.actions.count)
                let firstWidth = min(max(0, availableWidth - 4), unit * CGFloat(min(dialogColumns, dialog.actions.count)) / CGFloat(dialog.layout.widthDivisor))
                let listHeight = usesNPCLayout
                    ? max(0, geometry.size.height - 15 - descriptionHeight - inputHeight)
                    : max(0, geometry.size.height - 15 - descriptionHeight - inputHeight)
                HStack(alignment: .top, spacing: 2) {
                    actionList(dialog.actions, layout: dialog.layout, unit: unit, width: firstWidth, maxHeight: listHeight, identifier: "interaction.primary")
                        .padding(.trailing, 4)
                    if !dialog.secondary.isEmpty {
                        actionList(dialog.secondary, layout: dialog.secondaryLayout, unit: unit, width: max(0, availableWidth - firstWidth - 8), maxHeight: listHeight, identifier: "interaction.secondary")
                            .padding(.leading, 2)
                    }
                }.padding(2)
                Spacer(minLength: 0)
            }
        }.padding(.bottom, 3).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                if mode == "mud" {
                    RoundedRectangle(cornerRadius: 4).fill(Color(white: 34/255))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(red: 238/255, green: 232/255, blue: 205/255).opacity(0.6)))
                } else {
                    BundleImage(name: mode == "day" ? "bk1" : "bk2", ext: "jpeg")
                }
            }
            .overlay(alignment: .topTrailing) {
                Button { game.closeDialog() } label: {
                    BundleImage(name: "exitxx", ext: "png").frame(width: unit / 12, height: unit / 14)
                }.buttonStyle(.plain).accessibilityLabel("关闭").accessibilityIdentifier("interaction.close")
            }
            .padding(1)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color(white: 34/255)).overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(red: 238/255, green: 232/255, blue: 205/255).opacity(0.6))))
            .padding(.horizontal, 4).padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color(red: 180/255, green: 105/255, blue: 62/255).opacity(0.2)))
            .onPreferenceChange(InteractionTextHeight.self) { interactionTextHeight = $0 }
        }
    }

    private func isolatedInteraction(unit: CGFloat) -> some View {
        GeometryReader { geometry in
            if let dialog = game.dialog {
                let inputHeight: CGFloat = dialog.inputCommand == nil ? 0 : 40
                let availableHeight = max(0, geometry.size.height - 11 - inputHeight)
                let hasActions = !dialog.actions.isEmpty || !dialog.secondary.isEmpty
                // Reserve a fixed action viewport. Extra NPC actions scroll inside
                // this viewport instead of consuming the description area.
                let actionViewport = hasActions
                    ? min(availableHeight * 0.4, unit / 2)
                    : 0
                let descriptionHeight = max(0, availableHeight - actionViewport)
                let availableWidth = max(0, geometry.size.width - 14)
                let hasSpecialActions = dialog.kind == "npc" &&
                    !dialog.actions.isEmpty && !dialog.secondary.isEmpty
                let dialogColumns = dialog.layout.resolvedColumns(for: dialog.actions.count)
                let calculatedWidth = min(max(0, availableWidth - 4), unit * CGFloat(min(dialogColumns, max(1, dialog.actions.count))) / CGFloat(dialog.layout.widthDivisor))
                let firstWidth = hasSpecialActions ? calculatedWidth : availableWidth
                let listHeight = actionViewport
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView(.vertical) {
                        MudRichText(raw: dialog.text, send: game.act)
                            .font(.android(size: unit / 30))
                            .padding(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .background(GeometryReader { textGeometry in
                                Color.clear.preference(key: InteractionTextHeight.self, value: textGeometry.size.height)
                            })
                    }.frame(height: descriptionHeight)
                        .accessibilityIdentifier("interaction.description")
                    if dialog.inputCommand != nil {
                        HStack(spacing: 0) {
                            TextField("", text: $dialogInput)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($inputFocused)
                                .keyboardType(dialog.numeric ? .numberPad : .default)
                                .onSubmit { game.submitInput(dialogInput) }
                                .font(.android(size: 15))
                                .padding(.leading, 15)
                                .frame(height: 40)
                                .background(BundleImage(name: "input_bg", ext: "png"))
                            Button { game.submitInput(dialogInput) } label: {
                                Text("确定").font(.android(size: 14)).frame(width: 65, height: 40)
                            }.buttonStyle(AndroidButtonStyle())
                        }.padding(.horizontal, 5)
                    }
                    HStack(alignment: .top, spacing: 2) {
                    if hasSpecialActions {
                        actionList(dialog.actions,
                                   layout: dialog.layout,
                                   unit: unit,
                                   width: firstWidth,
                                   maxHeight: listHeight,
                                   identifier: "interaction.primary")
                            .padding(.trailing, 4)
                        let secondaryWidth = max(0, availableWidth - firstWidth - 8)
                        actionList(dialog.secondary,
                                   layout: dialog.secondaryLayout,
                                   unit: unit,
                                   width: secondaryWidth,
                                   maxHeight: listHeight,
                                   identifier: "interaction.secondary")
                                .padding(.leading, 2)
                    } else if !dialog.actions.isEmpty || !dialog.secondary.isEmpty {
                        actionList(dialog.actions.isEmpty ? dialog.secondary : dialog.actions,
                                   layout: dialog.actions.isEmpty ? dialog.secondaryLayout : dialog.layout,
                                   unit: unit,
                                   width: availableWidth,
                                   maxHeight: listHeight,
                                   identifier: "interaction.primary")
                    }
                }.padding(2).frame(height: actionViewport, alignment: .top)
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background {
                    if mode == "mud" {
                        RoundedRectangle(cornerRadius: 4).fill(Color(white: 34/255))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(red: 238/255, green: 232/255, blue: 205/255).opacity(0.6)))
                    } else {
                        BundleImage(name: mode == "day" ? "bk1" : "bk2", ext: "jpeg")
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Button { game.closeDialog() } label: {
                        BundleImage(name: "exitxx", ext: "png").frame(width: unit / 12, height: unit / 14)
                    }.buttonStyle(.plain).accessibilityLabel("关闭").accessibilityIdentifier("interaction.close")
                }
                .padding(1)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color(white: 34/255)).overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(red: 238/255, green: 232/255, blue: 205/255).opacity(0.6))))
                .padding(.horizontal, 4).padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color(red: 180/255, green: 105/255, blue: 62/255).opacity(0.2)))
                .onPreferenceChange(InteractionTextHeight.self) { interactionTextHeight = $0 }
            }
        }
    }

    private func interactionActionHeight(_ dialog: GameDialog, unit: CGFloat) -> CGFloat {
        func height(_ items: [MudAction], layout: MudLayout) -> CGFloat {
            guard !items.isEmpty else { return 0 }
            let resolved = layout.resolved(for: items.count)
            let rows = (items.count + resolved.columns - 1) / resolved.columns
            return CGFloat(rows) * (unit / CGFloat(resolved.heightDivisor) + 2)
        }
        return max(height(dialog.actions, layout: dialog.layout),
                   height(dialog.secondary, layout: dialog.secondaryLayout)) + 4
    }

    private func actionList(_ items: [MudAction], layout: MudLayout, unit: CGFloat, width: CGFloat, maxHeight: CGFloat, identifier: String) -> some View {
        let resolvedLayout = layout.resolved(for: items.count)
        let rows = (items.count + resolvedLayout.columns - 1) / resolvedLayout.columns
        return ScrollView(.vertical, showsIndicators: true) {
            actionGrid(items, layout: resolvedLayout, unit: unit, width: width)
        }.frame(width: width, height: min(maxHeight, CGFloat(rows) * (unit / CGFloat(resolvedLayout.heightDivisor) + 2)))
            .accessibilityIdentifier(identifier)
    }

    private func actionGrid(_ items: [MudAction], layout: MudLayout, unit: CGFloat, width: CGFloat) -> some View {
        let resolvedLayout = layout.resolved(for: items.count)
        let rows = (items.count + resolvedLayout.columns - 1) / resolvedLayout.columns
        return VStack(spacing: 2) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                ForEach((row * resolvedLayout.columns)..<min(items.count, (row + 1) * resolvedLayout.columns), id: \.self) { index in
                let item = items[index]
                Button { game.act(item) } label: {
                    let parts = item.display.components(separatedBy: "|")
                    VStack(spacing: 0) {
                        MudRichText(raw: parts[0], send: game.act)
                    }.font(.android(size: unit / CGFloat(resolvedLayout.fontDivisor)))
                        .padding(.horizontal, 3).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color(red: 180/255, green: 105/255, blue: 62/255).opacity(0.2)))
                        .padding(.leading, 2)
                }.buttonStyle(AndroidButtonStyle()).padding(1)
                    .frame(height: unit / CGFloat(resolvedLayout.heightDivisor))
                    .frame(maxWidth: .infinity)
                }
                }
            }
        }.padding(.bottom, 2).frame(width: width, alignment: .leading)
    }

    private func mainMenu(unit: CGFloat) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    let modes = [("日间模式", "day"), ("夜间模式", "mud"), ("正常模式", "night")]
                    menuButton(modes[index].0, unit: unit) {
                        mode = modes[index].1; game.messages = []; game.chatMessages = []
                        menuVisible = false; game.act("mycmds"); game.act("look")
                    }
                }
            }
            Color.gray.opacity(0.4).frame(width: 200, height: 1)
            HStack(spacing: 3) {
                menuButton("单行聊天", unit: unit) { chatDivisor = 8; menuVisible = false }
                menuButton("多行聊天", unit: unit) { chatDivisor = 3; menuVisible = false }
                menuButton("信息记录", unit: unit) { historyVisible = true; menuVisible = false }
            }
            Color.gray.opacity(0.4).frame(width: 200, height: 1)
            menuButton("退　出", unit: unit) { quitVisible = true; menuVisible = false }
        }.padding(5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear.contentShape(Rectangle()).onTapGesture { menuVisible = false })
    }

    private func menuButton(_ label: String, unit: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.android(size: unit / 22)).foregroundStyle(Color(red: 244/255, green: 164/255, blue: 96/255))
                .frame(width: unit / 4, height: unit / 9)
        }.buttonStyle(AndroidButtonStyle(image: "buttonx1"))
    }

    private func popupMenu(_ popup: GameDialog, unit: CGFloat) -> some View {
        let popupLayout = popup.layout.resolved(for: popup.actions.count)
        return ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(unit / CGFloat(popupLayout.widthDivisor)), spacing: 0), count: popupLayout.columns), spacing: 0) {
                ForEach(popup.actions) { item in
                    Button { game.act(item.command) } label: {
                        MudRichText(raw: item.display, send: game.act)
                            .font(.android(size: unit / CGFloat(popupLayout.fontDivisor)))
                            .foregroundStyle(mode == "mud" ? Color(white: 170/255) : Color(red: 80/255, green: 32/255, blue: 21/255))
                            .frame(width: unit / CGFloat(popupLayout.widthDivisor), height: unit / CGFloat(popupLayout.heightDivisor))
                    }.buttonStyle(AndroidButtonStyle(image: mode == "mud" ? nil : "buttonx1"))
                }
            }
        }.fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear.contentShape(Rectangle()).onTapGesture { game.popup = nil })
    }

    private func mapPanel(_ dialog: GameDialog, unit: CGFloat) -> some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                MudRichText(raw: dialog.text, send: game.act).font(.android(size: unit / 32))
                    .fixedSize().frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
            }.background(.black)
                .overlay(alignment: .topTrailing) {
                    Button { game.closeDialog() } label: {
                        Text("Ｘ").font(.android(size: unit / 16)).foregroundStyle(Color(red: 238/255, green: 0, blue: 0).opacity(170/255))
                            .frame(width: unit / 12, height: unit / 12)
                    }.buttonStyle(AndroidButtonStyle()).accessibilityLabel("关闭地图")
                }
        }
    }

    private func pagesPanel(_ dialog: GameDialog, unit: CGFloat) -> some View {
        GeometryReader { geometry in
            let availableWidth = max(0, geometry.size.width - 10)
            // Inline links stay in the body text as clickable colored text.
            let primaryActions = dialog.actions
            let secondaryActions = dialog.secondary
            // Mail = a few folder buttons + one content box (secondary <= 2).
            // Route = a long destination list (often all in secondary).
            let isMailLayout = !secondaryActions.isEmpty && secondaryActions.count <= 2
                && (primaryActions.count + secondaryActions.count) <= 8
            // For route, merge primary+secondary into one full-width list.
            let routeActions = primaryActions + secondaryActions
            let routeLayout = dialog.layout.resolved(for: routeActions.count)
            let gridLayout = routeActions.count > 8 ? routeLayout.withColumns(4) : routeLayout
            ScrollView {
                VStack(spacing: 0) {
                    MudRichText(raw: dialog.text, send: game.act)
                        .font(.android(size: unit / 32))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(5)
                    if isMailLayout {
                        // Mail: narrow left column (folders) + wider right (content).
                        HStack(alignment: .top, spacing: 4) {
                            actionGrid(primaryActions, layout: dialog.layout.resolved(for: primaryActions.count), unit: unit, width: availableWidth * 0.38)
                            actionGrid(secondaryActions, layout: dialog.secondaryLayout.resolved(for: secondaryActions.count), unit: unit, width: availableWidth * 0.58)
                        }
                    } else if !routeActions.isEmpty {
                        // Route: full-width merged grid (4 columns when long).
                        actionGrid(routeActions, layout: gridLayout, unit: unit, width: availableWidth)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .foregroundStyle(Color(white: 221/255))
            .background(Color.black)
            .overlay(alignment: .topTrailing) {
                Button { game.closeDialog() } label: {
                    BundleImage(name: "exitxx", ext: "png").frame(width: unit / 12, height: unit / 14)
                }.buttonStyle(.plain).accessibilityLabel("关闭页面")
            }
        }
    }

    private func historyPanel(unit: CGFloat) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 0) {
                ForEach(0..<2, id: \.self) { tab in
                    Button { historyTab = tab } label: {
                        Text(tab == 0 ? "聊天" : "信息").font(.android(size: 14)).foregroundStyle(.black)
                            .frame(maxWidth: .infinity).frame(height: unit / 10)
                            .overlay(alignment: .bottom) { if historyTab == tab { Color.gray.frame(height: 2) } }
                    }.buttonStyle(.plain)
                }
            }
            messages(historyTab == 0 ? game.chatMessages : game.history)
            HStack {
                Spacer()
                Button { historyVisible = false } label: {
                    Text("关 闭").font(.android(size: unit / 20)).foregroundStyle(Color(red: 221/255, green: 187/255, blue: 153/255))
                        .frame(width: 150, height: unit / 10)
                }.buttonStyle(AndroidButtonStyle(image: "bt1"))
            }
        }.padding(3).background(Color(white: 36/255)).foregroundStyle(.white)
    }

    private func confirmation(unit: CGFloat) -> some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if let dialog = game.dialog {
                    // Keep the action area outside the scroll view so long mail/reward
                    // text can never push the buttons beyond the visible screen.
                    ScrollView {
                        MudRichText(raw: dialog.text.trimmingCharacters(in: .newlines), send: game.act)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }.frame(maxHeight: max(80, geometry.size.height - 190)).padding(10)
                HStack(spacing: 5) {
                    ForEach(dialog.rewards) { reward in
                        Button { game.inspectReward(reward) } label: {
                            BundleImage(name: "icon", ext: "jpeg").scaledToFit().padding(2)
                                .frame(width: unit / 6, height: unit / 6)
                                .background(rewardBackground(reward.grade))
                        }.buttonStyle(.plain).accessibilityLabel("查看物品")
                    }
                }.padding(.bottom, 5)
                if dialog.numeric {
                    TextField("", text: $dialogInput).focused($inputFocused)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .frame(width: 90, height: unit / 10)
                        .tint(Color(red: 128/255, green: 203/255, blue: 196/255))
                        .overlay(alignment: .bottom) { Color(red: 128/255, green: 203/255, blue: 196/255).frame(height: 2) }
                        .onChange(of: dialogInput) { value in if value.count > 3 { dialogInput = String(value.prefix(3)) } }
                }
                if !dialog.experience.isEmpty { Text(dialog.experience).foregroundStyle(Color(red: 0, green: 1, blue: 0)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.bottom, 5) }
                if !dialog.money.isEmpty { Text(dialog.money).foregroundStyle(Color(red: 1, green: 215/255, blue: 0)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.bottom, 5) }
                HStack(spacing: 30) {
                    Button { game.confirmDialog(dialogInput) } label: { Text("确 定").frame(width: unit / 4, height: unit / 9) }
                    if !dialog.secondary.isEmpty {
                        Button { game.cancelConfirmation() } label: { Text("取 消").frame(width: unit / 4, height: unit / 9) }
                    }
                }.buttonStyle(AndroidButtonStyle(image: "bt1")).padding(.top, 5).padding(.bottom, 8)
                }
            }.font(.android(size: unit / 26)).foregroundStyle(Color(white: 221/255))
                .frame(width: min(unit - 20, unit / 2 + 100), height: min(geometry.size.height - 20, geometry.size.height * 0.9))
                .background(Color(red: 54/255, green: 34/255, blue: 22/255))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(white: 48/255))
        }
    }

    private func rewardBackground(_ grade: Int) -> some View {
        let palette = ["333333", "dddddd", "20e000", "0066ff", "ec00ec", "ffb400", "ff3300"]
        return LinearGradient(colors: [color(palette.indices.contains(grade) ? palette[grade] : palette[0]).opacity(0.6), color(grade == 0 ? "999999" : "bbbbbb").opacity(0.6)], startPoint: .leading, endPoint: .trailing)
            .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}
