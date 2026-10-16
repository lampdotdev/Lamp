import SwiftUI

@main
struct MainApp: SwiftUI.App {
    // Kept in the App so the menu bar label follows it (LampMenuBar's rule).
    @StateObject private var store = CountdownStore()

    var body: some SwiftUI.Scene {
        LampMenuBar {
            PanelView().environmentObject(store)
        } label: {
            MenuBarLabel(store: store)
        }
        .commands { LampCommands() }

        Settings {
            SettingsView().environmentObject(store)
        }
    }
}

/// The icon in the menu bar, with the days to the next countdown beside it when that's switched on.
struct MenuBarLabel: View {
    @ObservedObject var store: CountdownStore

    var body: some View {
        Image(systemName: "calendar.badge.clock")
            .accessibilityLabel("Countdowns")
        if store.prefs.showsDaysInMenuBar, let next = store.upcoming.first {
            Text(next.shortLabel(from: store.today))
        }
    }
}
