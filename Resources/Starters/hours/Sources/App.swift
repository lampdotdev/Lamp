import SwiftUI

@main
struct MainApp: SwiftUI.App {
    @StateObject private var model = HoursModel()

    var body: some SwiftUI.Scene {
        WindowGroup("Hours") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 720, minHeight: 460)
        }
        .defaultSize(width: 900, height: 600)
        .commands {
            LampCommands()
            HoursCommands(model: model)
        }

        // The timer lives in the menu bar too, so it can be started and stopped without opening the window.
        // The model is handed over inside the braces, as LampMenuBar asks.
        LampMenuBar(dockIcon: true) {
            MenuBarPanel().environmentObject(model)
        } label: {
            MenuBarLabel(model: model, ticker: model.ticker)
        }

        Settings {
            SettingsView().environmentObject(model)
        }
    }
}

/// The Timer menu: the same actions as the toolbar, with keyboard shortcuts.
struct HoursCommands: Commands {
    @ObservedObject var model: HoursModel

    var body: some Commands {
        CommandMenu("Timer") {
            if let running = model.running {
                Button("Stop \(model.client(running.clientID)?.name ?? "Timer")") { model.stopTimer() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
            } else {
                Menu("Start Timer") {
                    ForEach(model.clients) { client in
                        Button(client.name) { model.startTimer(for: client.id) }
                    }
                }
                .disabled(model.clients.isEmpty)
            }
            Divider()
            Button("New Entry…") { model.sheet = .newEntry(clientID: nil) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(model.clients.isEmpty)
            Button("New Client…") { model.sheet = .newClient }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Button("Make Invoice…") { model.sheet = .invoice(clientID: nil) }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(model.clients.isEmpty)
            if model.hasExamples {
                Divider()
                Button("Clear Examples") { model.clearExamples() }
            }
        }
    }
}
