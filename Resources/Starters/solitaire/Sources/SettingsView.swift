import SwiftUI

struct SettingsView: View {
    let game: Game

    var body: some View {
        Form {
            Picker("Draw from the stock", selection: Binding(get: { game.preferences.drawThree }, set: game.setDrawThree)) {
                Text("One card at a time").tag(false)
                Text("Three cards at a time").tag(true)
            }
            .pickerStyle(.radioGroup)
            Text("Starts with the next game.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize()
    }
}

/// The Game menu, and Undo in the Edit menu.
struct GameCommands: Commands {
    let game: Game

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo Move") {
                withAnimation(TableView.moveAnimation) { game.undo() }
            }
            .keyboardShortcut("z")
            .disabled(!game.canUndo)
        }
        CommandMenu("Game") {
            // ⌘N stays New Window, which Lamp uses to bring the window back after it's closed.
            Button("New Game") {
                withAnimation(.snappy(duration: 0.45)) { game.newGame() }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Picker("Draw", selection: Binding(get: { game.preferences.drawThree }, set: game.setDrawThree)) {
                Text("One Card").tag(false)
                Text("Three Cards").tag(true)
            }
        }
    }
}
