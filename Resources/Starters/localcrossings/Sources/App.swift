import SwiftUI

@main
struct MainApp: SwiftUI.App {
    @State private var state = DailyState()

    var body: some SwiftUI.Scene {
        WindowGroup("Local Crossings") {
            PuzzleBoard(state: state)
        }
        // The paper runs to the window's edges, under where its title bar would be.
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 980, height: 720)
        .commands {
            LampCommands()
            PuzzleCommands(state: state)
        }
    }
}

/// The Puzzle menu, so everything in the masthead has a key.
struct PuzzleCommands: Commands {
    let state: DailyState

    var body: some Commands {
        CommandMenu("Puzzle") {
            Button("Check Puzzle") { state.crossword.check() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(!state.crossword.canHelp)
            Button("Reveal Square") { state.crossword.revealSquare() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(!state.crossword.canHelp)
            Button("Reveal Word") { state.crossword.revealWord() }
                .keyboardShortcut("h", modifiers: [.command, .option, .shift])
                .disabled(!state.crossword.canHelp)
            Divider()
            Button("Change Place…") { state.showingPlace = true }
            Button("History") { state.showingHistory = true }
                .keyboardShortcut("y")
            if state.history.hasExamples {
                Divider()
                Button("Clear Examples") { state.history.clearExamples() }
            }
        }
    }
}
