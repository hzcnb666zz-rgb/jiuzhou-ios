import SwiftUI

@main
struct JiuzhouApp: App {
    init() {
        #if DEBUG
        precondition(UIFont(name: "NotoSansCJKsc-Regular", size: 14) != nil, "Android reference font is missing")
        VoiceCodec.verify()
        #endif
    }
    @StateObject private var game = GameModel()
    var body: some Scene {
        WindowGroup {
            AndroidEntryView(game: game)
                .preferredColorScheme(.dark)
        }
    }
}
