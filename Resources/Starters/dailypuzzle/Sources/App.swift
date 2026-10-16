import SwiftUI

@main
struct MainApp: SwiftUI.App {
    @State private var state = DailyState()

    var body: some SwiftUI.Scene {
        WindowGroup("Daily Puzzle") {
            PuzzleBoard(state: state)
        }
        .defaultSize(width: 600, height: 640)
        .commands {
            LampCommands()
            PuzzleCommands(state: state)
        }
    }
}

/// The Puzzle menu, and Undo taking back the last word, so everything in the toolbar has a key.
struct PuzzleCommands: Commands {
    let state: DailyState

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo Last Word") { state.ladder.undoStep() }
                .keyboardShortcut("z")
                .disabled(!state.ladder.canUndoStep)
        }
        CommandMenu("Puzzle") {
            Button("Show Hint") { state.ladder.showHint() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(!state.ladder.canHint)
            Button("History") { state.showingHistory = true }
                .keyboardShortcut("y")
            if state.history.hasExamples {
                Divider()
                Button("Clear Examples") { state.history.clearExamples() }
            }
        }
    }
}
