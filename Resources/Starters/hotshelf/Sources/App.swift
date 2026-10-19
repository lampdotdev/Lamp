import SwiftUI

@main
struct MainApp: SwiftUI.App {
    @StateObject private var shelf = Shelf.shared

    var body: some SwiftUI.Scene {
        WindowGroup("Hot Shelf") {
            ShelfView()
                .environmentObject(shelf)
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            LampCommands()
            CommandGroup(after: .newItem) {
                Button("Add Bottle…") { shelf.showAdd = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Taste Map") { shelf.showMap = true }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
        }
    }
}
