import SwiftUI

/// Focus lives in the menu bar: the icon shows the time left while a session runs, and a click opens the panel
/// with the timer and the week's history. Settings is a window of its own.
@main
struct MainApp: SwiftUI.App {
    init() {
        // "Start Focus" on the break-over notification starts the next session without opening the panel.
        LampNotifications.onAction { action, _ in
            let timer = FocusTimer.shared
            if action == "Start Focus", timer.state.phase == .focus, !timer.isRunning { timer.start() }
        }
    }

    var body: some Scene {
        LampMenuBar {
            PanelView(timer: .shared)
        } label: {
            MenuBarLabel(timer: .shared)
        }
        .commands {
            LampCommands()
            FocusCommands(timer: .shared)
        }

        Settings {
            SettingsView(timer: .shared)
        }
    }
}

/// The menus shown while the Settings window is in front, the only time a menu bar app has menus.
struct FocusCommands: Commands {
    @ObservedObject var timer: FocusTimer

    var body: some Commands {
        CommandMenu("Timer") {
            Button(timer.isRunning ? "Pause" : "Start") { timer.toggle() }
                .keyboardShortcut(.return, modifiers: .command)
            Button("Skip") { timer.skip() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Divider()
            Button("Clear Examples") { timer.clearExamples() }
                .disabled(!timer.hasExamples)
        }
    }
}
