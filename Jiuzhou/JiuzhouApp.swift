import SwiftUI

@main
struct JiuzhouApp: App {
    @StateObject private var game = GameModel()
    var body: some Scene {
        WindowGroup {
            GameView(game: game)
                .preferredColorScheme(.dark)
        }
    }
}
