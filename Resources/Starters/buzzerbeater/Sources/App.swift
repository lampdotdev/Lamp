import SwiftUI

@main
struct MainApp: SwiftUI.App {
    @StateObject private var watcher = Watcher.shared

    var body: some SwiftUI.Scene {
        LampMenuBar {
            PanelView().environmentObject(watcher)
        } label: {
            MenuBarLabel(count: watcher.hotGames.count)
        }
        .commands { LampCommands() }

        Settings {
            SettingsView().environmentObject(watcher)
        }
        .windowResizability(.contentMinSize)
    }
}

private struct MenuBarLabel: View {
    let count: Int

    var body: some View {
        if count > 0 {
            HStack(spacing: 3) {
                Image(systemName: "flame.fill")
                Text("\(count)")
            }
            .accessibilityLabel("Buzzer Beater: \(count) good games")
        } else {
            Image(systemName: "basketball")
                .accessibilityLabel("Buzzer Beater")
        }
    }
}
