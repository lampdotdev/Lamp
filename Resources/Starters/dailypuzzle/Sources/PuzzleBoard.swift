import SwiftUI
import AppKit

/// The window: today's puzzle with its toolbar. With more than one game, a picker in the toolbar chooses which
/// is shown; each game's view is one line in `board`.
struct PuzzleBoard: View {
    @Bindable var state: DailyState
    @SceneStorage("game") private var game: Game = .wordLadder

    var body: some View {
        board
            .frame(minWidth: 480, minHeight: 540)
            .background(.background)
            .navigationTitle(game.title)
            .navigationSubtitle(Day.today.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
            .toolbar { toolbar }
            .sheet(isPresented: $state.showingHistory) { HistoryView(history: state.history) }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                state.refreshDay()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                state.refreshDay()
            }
    }

    @ViewBuilder private var board: some View {
        switch game {
        case .wordLadder: LadderView(game: state.ladder, streak: state.history.streak)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if Game.allCases.count > 1 {
            ToolbarItem(placement: .principal) {
                Picker("Puzzle", selection: $game) {
                    ForEach(Game.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        ToolbarItemGroup {
            Button { state.ladder.undoStep() } label: { Label("Undo Last Word", systemImage: "arrow.uturn.backward") }
                .help("Take back the last word (⌘Z)")
                .disabled(!state.ladder.canUndoStep)
            Button { state.ladder.showHint() } label: { Label("Hint", systemImage: "lightbulb") }
                .help("Show the next letter to change. Today won't count as perfect.")
                .disabled(!state.ladder.canHint)
            Button { state.showingHistory = true } label: {
                Label("\(state.history.streak)", systemImage: "flame.fill")
                    .labelStyle(.titleAndIcon)
                    .monospacedDigit()
            }
            .accessibilityLabel("History, \(state.history.streak)-day streak")
            .help("Your streak is \(state.history.streak) \(state.history.streak == 1 ? "day" : "days"). Show the calendar (⌘Y)")
        }
    }
}
