import SwiftUI

@main
struct MainApp: SwiftUI.App {
    @State private var game = Game()

    var body: some SwiftUI.Scene {
        WindowGroup("Solitaire") {
            ContentView(game: game)
        }
        .defaultSize(width: 900, height: 640)
        .commands {
            LampCommands()
            GameCommands(game: game)
        }

        Settings {
            SettingsView(game: game)
        }
    }
}
