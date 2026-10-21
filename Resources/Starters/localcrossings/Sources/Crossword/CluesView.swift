import SwiftUI

/// The clue being answered, above the grid, in yellow like the square the cursor is on.
struct ClueBar: View {
    let game: CrosswordGame

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let entry = game.entry {
                Text("\(entry.number)\(entry.across ? "A" : "D")")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Paper.sunInk)
                Text("\(entry.clue) (\(entry.lengths))")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Paper.sunInk)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(" ").font(.system(size: 15))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(game.entry == nil ? Color.clear : Paper.haze)
        .accessibilityElement(children: .combine)
    }
}

/// Every clue, Across then Down, newspaper style. The one being answered is yellow, the one crossing it at the
/// cursor has a yellow bar beside it, and a click on either goes to that word.
struct CluesView: View {
    let game: CrosswordGame
    let puzzle: Crossword

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Across", puzzle.entries.filter(\.across))
                    section("Down", puzzle.entries.filter { !$0.across })
                }
                .padding(.bottom, 20)
            }
            .scrollIndicators(.never)
            .onChange(of: game.entry?.id) {
                guard let id = game.entry?.id else { return }
                withAnimation(.easeOut(duration: 0.2)) { scroller.scrollTo(id) }
            }
        }
    }

    private func section(_ title: String, _ entries: [Crossword.Entry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(Paper.label)
                .tracking(1.2)
                .foregroundStyle(Paper.ink)
                .padding(.bottom, 6)
            Rule(heavy: true)
                .padding(.bottom, 4)
            ForEach(entries) { entry in row(entry) }
        }
    }

    private func row(_ entry: Crossword.Entry) -> some View {
        let isCurrent = game.entry == entry
        let isCrossing = !isCurrent && game.selected.map { entry.cells.contains($0) } == true
        let isDone = entry.cells.allSatisfy { game.letters[$0] != nil }
        return Button { game.select(entry) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(entry.number)")
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .frame(width: 22, alignment: .trailing)
                Text("\(entry.clue) (\(entry.lengths))")
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(isDone && !isCurrent ? Paper.faded : Paper.ink)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isCurrent ? Paper.haze : Color.clear)
            .overlay(alignment: .leading) {
                if isCrossing { Rectangle().fill(Paper.sun).frame(width: 4) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(entry.id)
        .accessibilityLabel("\(entry.label): \(entry.clue), \(entry.lengths) letters")
    }
}
