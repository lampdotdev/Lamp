import SwiftUI

@main
struct MainApp: SwiftUI.App {
    @StateObject private var backpack = Backpack.shared

    var body: some SwiftUI.Scene {
        LampMenuBar {
            PanelView().environmentObject(backpack)
        } label: {
            MenuBarLabel(soon: backpack.soon)
        }
        .commands { LampCommands() }

        Settings {
            SettingsView().environmentObject(backpack)
        }
    }
}

private struct MenuBarLabel: View {
    let soon: Int

    var body: some View {
        if soon > 0 {
            HStack(spacing: 3) {
                Image(systemName: "backpack.fill")
                Text("\(soon)")
            }
            .accessibilityLabel("Backpack: \(soon) due soon")
        } else {
            Image(systemName: "backpack")
                .accessibilityLabel("Backpack")
        }
    }
}
