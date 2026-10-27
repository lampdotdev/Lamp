import SwiftUI
import AppKit

/// The window: the map of the place in gray behind a sheet of newsprint, the masthead, and today's crossword
/// with its clues. Before the paper is ready the same page shows the first launch's question, the paper being
/// made, or what went wrong.
struct PuzzleBoard: View {
    @Bindable var state: DailyState

    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Paper.page
            if let spot = state.delivery.backdrop {
                MapBackdrop(latitude: spot.latitude, longitude: spot.longitude)
                    .opacity(0.9)
            }
            // The newsprint over the map: thin enough that the streets show, thick enough to read on.
            Paper.page.opacity(0.74)

            VStack(spacing: 0) {
                Masthead(state: state)
                    .padding(.horizontal, 36)
                    .padding(.top, 34)
                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea()
        .frame(minWidth: 820, minHeight: 600)
        .foregroundStyle(Paper.ink)
        .sheet(isPresented: $state.showingHistory) { HistoryView(history: state.history) }
        .sheet(isPresented: $state.showingPlace) { PlaceSheet(delivery: state.delivery) }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat]) { press in handle(press) }
        .onAppear { focused = true }
        // Back from a sheet or another app, typing goes to the grid again.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in focused = true }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in state.refreshDay() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in state.refreshDay() }
    }

    @ViewBuilder private var page: some View {
        switch state.delivery.status {
        case .needsLocation:
            NeedsLocation(state: state)
        case .making:
            VStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Printing today's paper…").font(Paper.serif(17, weight: .regular)).italic()
            }
        case .failed(let reason):
            VStack(spacing: 14) {
                Text("No paper today, yet.").font(Paper.serif(24))
                Text(reason).foregroundStyle(Paper.faded).multilineTextAlignment(.center).frame(maxWidth: 360)
                HStack {
                    Button("Change Place…") { state.showingPlace = true }
                    Button("Try Again") { state.delivery.tryAgain() }
                        .keyboardShortcut(.defaultAction)
                }
                .controlSize(.large)
            }
        case .ready:
            if let puzzle = state.crossword.puzzle {
                Board(state: state, puzzle: puzzle)
            }
        }
    }

    // MARK: Keys

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        let game = state.crossword
        // Shortcuts with ⌘ or ⌃ belong to the menus.
        guard state.delivery.status == .ready, game.puzzle != nil,
              press.modifiers.isDisjoint(with: [.command, .control]) else { return .ignored }
        switch press.key {
        case .leftArrow: game.move(rows: 0, cols: -1)
        case .rightArrow: game.move(rows: 0, cols: 1)
        case .upArrow: game.move(rows: -1, cols: 0)
        case .downArrow: game.move(rows: 1, cols: 0)
        case .tab: game.nextEntry(backward: press.modifiers.contains(.shift))
        case .return: game.nextEntry()
        case .space: game.select(game.selected ?? Cell(row: 0, col: 0))
        case .delete, .deleteForward: game.deleteBackward()
        default:
            guard press.characters.count == 1, let letter = press.characters.first,
                  letter.isLetter, letter.isASCII else { return .ignored }
            game.type(letter)
        }
        return .handled
    }
}

/// The paper's name across the top, between two rules: the edition's number, the place, the date. Under it,
/// where the paper is from, the clock, and the streak.
private struct Masthead: View {
    let state: DailyState

    var body: some View {
        let edition = state.delivery.edition
        VStack(spacing: 0) {
            Rule(heavy: true)
            HStack(alignment: .center) {
                Text(edition.map { "No. \($0.number)" } ?? "Daily")
                    .font(Paper.label)
                    .textCase(.uppercase)
                    .tracking(1)
                    .frame(width: 150, alignment: .leading)
                Spacer()
                Text(edition.map { "The \($0.place) Crossword" } ?? "The Crossword")
                    .font(Paper.serif(34))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.opacity)
                Spacer()
                Text(Day.today.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(Paper.label)
                    .textCase(.uppercase)
                    .tracking(1)
                    .frame(width: 150, alignment: .trailing)
            }
            .padding(.vertical, 10)
            Rule()
            HStack(spacing: 14) {
                Spacer()
                if state.delivery.status == .ready {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(Solve.time(state.crossword.solve?.seconds ?? state.crossword.seconds))
                            .monospacedDigit()
                    }
                    .accessibilityLabel("Time")
                    Menu {
                        Button("Check Puzzle") { state.crossword.check() }
                        Button("Reveal Square") { state.crossword.revealSquare() }
                        Button("Reveal Word") { state.crossword.revealWord() }
                    } label: {
                        Label("Help", systemImage: "lightbulb")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .disabled(!state.crossword.canHelp)
                    .help("Check or reveal letters. Today won't count as perfect.")
                }
                Button { state.showingHistory = true } label: {
                    Label("\(state.history.streak)", systemImage: "flame.fill").monospacedDigit()
                }
                .accessibilityLabel("History, \(state.history.streak)-day streak")
                .help("Your streak is \(state.history.streak) \(state.history.streak == 1 ? "day" : "days"). Show the calendar (⌘Y)")
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Paper.faded)
            .padding(.vertical, 8)
        }
    }
}

/// Today's grid with the clue being answered above it, and every clue beside it; once it's solved, what it
/// came to takes the clues' place.
private struct Board: View {
    let state: DailyState
    let puzzle: Crossword

    var body: some View {
        GeometryReader { geometry in
            let side = squareSize(in: geometry.size)
            HStack(alignment: .top, spacing: 36) {
                VStack(alignment: .leading, spacing: 18) {
                    if !state.crossword.isSolved { ClueBar(game: state.crossword) }
                    GridView(game: state.crossword, puzzle: puzzle, size: side)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(width: max(CGFloat(puzzle.cols) * side, 380))
                Group {
                    if let solve = state.crossword.solve {
                        DoneCard(solve: solve, streak: state.history.streak, perfect: state.history.perfectCount)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else {
                        CluesView(game: state.crossword, puzzle: puzzle)
                    }
                }
                .frame(width: 300)
            }
            .padding(.horizontal, 36)
            .padding(.top, 14)
            .frame(maxWidth: .infinity, alignment: .center)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: state.crossword.isSolved)
        }
    }

    /// As big as fits beside the clues, up to 46 points a square.
    private func squareSize(in size: CGSize) -> CGFloat {
        let width = (size.width - 300 - 36 - 72) / CGFloat(puzzle.cols)
        let height = (size.height - 90) / CGFloat(puzzle.rows)
        return max(24, min(46, width, height)).rounded(.down)
    }
}

/// When the Mac doesn't say where it is: the puzzles are made from there, so the page says how to allow it, or
/// to choose a place instead.
private struct NeedsLocation: View {
    let state: DailyState

    var body: some View {
        VStack(spacing: 16) {
            Text("A crossword made of\nthe streets around you.")
                .font(Paper.serif(32))
                .multilineTextAlignment(.center)
            Text("Allow Local Crossings to use your location in System Settings, or choose a place.")
                .font(Paper.serif(16, weight: .regular))
                .italic()
                .foregroundStyle(Paper.faded)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
            } label: {
                Text("Open System Settings").font(.system(size: 14, weight: .semibold)).padding(.horizontal, 22).padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Paper.page)
            .background(Paper.ink, in: Capsule())
            .keyboardShortcut(.defaultAction)
            .padding(.top, 6)
            Button("Choose a Place…") { state.showingPlace = true }
                .buttonStyle(.plain)
                .foregroundStyle(Paper.faded)
        }
        .padding(.bottom, 60)
    }
}

/// Change Place: the puzzles from somewhere else, typed, or from where the Mac is.
struct PlaceSheet: View {
    let delivery: Delivery

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var problem: String?
    @State private var looking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Where should the puzzles come from?").font(Paper.serif(20))
            TextField("Town or neighborhood", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit { find() }
            if let problem {
                Text(problem).font(.callout).foregroundStyle(Paper.wrong)
            }
            HStack {
                Button("Use My Location") {
                    delivery.choose(.here)
                    dismiss()
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Make Puzzle") { find() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || looking)
            }
        }
        .padding(22)
        .frame(width: 400)
    }

    private func find() {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        looking = true
        problem = nil
        Task {
            defer { looking = false }
            do {
                let found = try await Survey.find(query)
                delivery.choose(.named(found.name, latitude: found.latitude, longitude: found.longitude))
                dismiss()
            } catch {
                problem = "Couldn't find \(query) on the map."
            }
        }
    }
}
