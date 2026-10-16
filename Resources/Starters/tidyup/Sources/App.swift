import SwiftUI

@main
struct MainApp: SwiftUI.App {
    // One model for the whole app: the window, the Tidy menu and the folder watchers all see the same folders.
    @StateObject private var model = TidyModel.shared

    var body: some SwiftUI.Scene {
        WindowGroup("Tidy Up") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 880, height: 580)
        .commands { LampCommands() }
        .commands { TidyCommands(model: model) }

        Settings {
            SettingsView()
        }
    }
}
