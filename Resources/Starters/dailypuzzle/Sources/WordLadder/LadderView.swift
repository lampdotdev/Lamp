import SwiftUI
import AppKit

/// Today's ladder: the start word at the top, each word entered below the one it came from with its changed
/// letter in honey, the row being typed, and the end word waiting at the bottom. Typing goes straight to the
/// board: letters fill the row, Delete takes one back, Return submits.
struct LadderView: View {
    let game: LadderGame
    let streak: Int

    @FocusState private var focused: Bool

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(spacing: 22) {
                    header
                    ladder
                    if let solve = game.solve {
                        DoneCard(solve: solve, streak: streak)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: game.steps)
                .animation(.spring(response: 0.5, dampingFraction: 0.75), value: game.isSolved)
            }
            .onChange(of: game.steps.count) {
                withAnimation { scroller.scrollTo("bottom", anchor: .bottom) }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat]) { press in handle(press) }
        .onAppear { focused = true }
        // Back from the history sheet or another app, typing goes to the board again.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in focused = true }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text(game.puzzle.start.uppercased())
                Image(systemName: "arrow.right").font(.title2).foregroundStyle(.secondary)
                Text(game.puzzle.end.uppercased()).foregroundStyle(Palette.goal)
            }
            .font(.system(size: 30, weight: .heavy, design: .rounded))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("From \(game.puzzle.start) to \(game.puzzle.end)")

            HStack(spacing: 16) {
                Label("Par \(game.puzzle.par)", systemImage: "flag")
                Label("Steps \(game.steps.count)", systemImage: "stairs")
                if game.usedHint {
                    Label("Hint used", systemImage: "lightbulb")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            if game.steps.isEmpty && !game.isSolved {
                Text(Game.wordLadder.rules)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var ladder: some View {
        VStack(spacing: 10) {
            row(label: "Start") {
                tiles(game.puzzle.start) { _ in .start }
            }
            .accessibilityLabel("Start: \(game.puzzle.start)")

            // Identified by the word (a ladder never repeats one), so a word entered after an undo arrives with its flip.
            ForEach(Array(game.steps.enumerated()), id: \.element) { index, word in
                let before = index == 0 ? game.puzzle.start : game.steps[index - 1]
                let changed = Set(WordLadder.differences(before, word))
                let isEnd = game.isSolved && index == game.steps.count - 1
                row(label: "\(index + 1)", mark: isEnd ? "checkmark.circle.fill" : nil) {
                    ForEach(Array(word.enumerated()), id: \.offset) { position, letter in
                        LetterTile(letter: letter, style: changed.contains(position) ? .changed : .word,
                                   flips: changed.contains(position))
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityLabel("Step \(index + 1): \(word)")
            }

            if !game.isSolved {
                typingRow
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .foregroundStyle(.tertiary)
                    .frame(height: 16)
                    .accessibilityHidden(true)
                row(label: "Goal") {
                    tiles(game.puzzle.end) { _ in .goal }
                }
                .accessibilityLabel("Goal: \(game.puzzle.end)")
            }
        }
    }

    /// The next word as it's typed. Empty slots show the letter they'd keep from the word above, a typed letter
    /// that differs from it is honey at once, and a hint marks its slot with the letter to put there.
    private var typingRow: some View {
        let typed = Array(game.typed)
        let current = Array(game.current)
        return VStack(spacing: 8) {
            row(label: "\(game.steps.count + 1)") {
                ForEach(0..<WordLadder.length, id: \.self) { position in
                    if position < typed.count {
                        LetterTile(letter: typed[position], style: typed[position] == current[position] ? .typing : .changed)
                    } else if let hint = game.hint, hint.position == position {
                        LetterTile(letter: hint.letter, style: .hint)
                    } else {
                        LetterTile(letter: current[position], style: .ghost)
                    }
                }
            }
            .modifier(Shake(shakes: CGFloat(game.shakes)))
            .animation(.linear(duration: 0.4), value: game.shakes)
            .accessibilityLabel(typed.isEmpty ? "Type the next word" : "Typing \(game.typed)")

            Text(game.problem ?? hintLine ?? "Type a word, then press Return.")
                .font(.callout)
                .foregroundStyle(game.problem == nil ? Color.secondary : Color.orange)
                .frame(height: 18)
        }
    }

    private var hintLine: String? {
        guard let hint = game.hint else { return nil }
        let ordinals = ["first", "second", "third", "fourth"]
        return "Hint: change the \(ordinals[hint.position]) letter to \(String(hint.letter).uppercased())."
    }

    /// A ladder row: a small label on the left, the tiles, and room on the right for a mark, so every row's
    /// tiles line up whatever is beside them.
    private func row<Tiles: View>(label: String, mark: String? = nil, @ViewBuilder tiles: () -> Tiles) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 44, alignment: .trailing)
            tiles()
            Group {
                if let mark { Image(systemName: mark).foregroundStyle(Palette.goal).font(.title2) }
            }
            .frame(width: 44, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
    }

    private func tiles(_ word: String, style: @escaping (Int) -> TileStyle) -> some View {
        ForEach(Array(word.enumerated()), id: \.offset) { position, letter in
            LetterTile(letter: letter, style: style(position))
        }
    }

    // MARK: Keys

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        // Shortcuts with ⌘ or ⌃ belong to the menus.
        guard press.modifiers.isDisjoint(with: [.command, .control]) else { return .ignored }
        switch press.key {
        case .return:
            game.submit()
            return .handled
        case .delete, .deleteForward:
            game.deleteBackward()
            return .handled
        default:
            guard press.characters.count == 1, let letter = press.characters.first,
                  letter.isLetter, letter.isASCII else { return .ignored }
            game.type(letter)
            return .handled
        }
    }
}
