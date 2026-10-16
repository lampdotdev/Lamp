import SwiftUI

/// The window: the table on its felt, the moves and the clock in the toolbar, and the win cascade and result
/// over the table at the end of a game.
struct ContentView: View {
    let game: Game

    @State private var showingStats = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                TableView(game: game)
                if game.celebrating {
                    WinCascade(layout: TableLayout(size: geometry.size), foundations: game.board.foundations) {
                        game.endCelebration()
                    }
                } else if game.board.isWon {
                    WinSummary(game: game)
                }
            }
        }
        .background(Felt())
        .frame(minWidth: 640, minHeight: 480)
        .navigationTitle("Solitaire")
        .toolbar { toolbar }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .status) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 14) {
                    Label("\(game.board.moves)", systemImage: "hand.point.up.left")
                        .help("Moves")
                    Label(Clock.text(game.elapsed(at: context.date)), systemImage: "clock")
                        .help("Time")
                }
                .labelStyle(.titleAndIcon)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(game.board.moves) moves, \(Clock.text(game.elapsed(at: context.date)))")
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                withAnimation(TableView.moveAnimation) { game.undo() }
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .help("Undo the last move (⌘Z)")
            .disabled(!game.canUndo)

            Button {
                withAnimation(.snappy(duration: 0.45)) { game.newGame() }
            } label: {
                Label("New Game", systemImage: "rectangle.stack.badge.plus")
            }
            .help("Deal a new game (⇧⌘N)")

            Button {
                showingStats.toggle()
            } label: {
                Label("Statistics", systemImage: "chart.bar")
            }
            .help("Games played and won")
            .popover(isPresented: $showingStats, arrowEdge: .bottom) {
                StatsView(stats: game.stats).padding()
            }
        }
    }
}

enum Clock {
    /// "4:07", or "1:02:33" past an hour.
    static func text(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let (hours, minutes, secs) = (total / 3600, total / 60 % 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

/// What the game came to, after the cascade.
struct WinSummary: View {
    let game: Game

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "crown.fill")
                .font(.system(size: 34))
                .foregroundStyle(.yellow)
            Text("You Won!")
                .font(.largeTitle.bold())
            Text("\(Clock.text(game.elapsed(at: .now))) · \(game.board.moves) moves")
                .font(.title3)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            StatsView(stats: game.stats)
            Button("New Game") {
                withAnimation(.snappy(duration: 0.45)) { game.newGame() }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}

struct StatsView: View {
    let stats: Stats

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
            row("Played", "\(stats.played)")
            row("Won", stats.played > 0 ? "\(stats.won) (\(stats.won * 100 / stats.played)%)" : "\(stats.won)")
            row("Best time", stats.bestTime.map(Clock.text) ?? "–")
            row("Fewest moves", stats.fewestMoves.map(String.init) ?? "–")
        }
        .monospacedDigit()
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).gridColumnAlignment(.trailing)
        }
    }
}
