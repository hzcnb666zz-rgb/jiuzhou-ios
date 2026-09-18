import SwiftUI

@main
struct JiuzhouApp: App {
    @StateObject private var game = GameModel()
    var body: some Scene {
        WindowGroup {
            AndroidEntryView(game: game)
                .preferredColorScheme(.dark)
        }
    }
}
