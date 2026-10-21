import SwiftUI

/// The grid: white squares with ink edges where there are letters, and nothing where there aren't, so the map
/// shows between the words. The square the cursor is on is yellow and the rest of its word a paler yellow.
struct GridView: View {
    let game: CrosswordGame
    let puzzle: Crossword
    let size: CGFloat

    var body: some View {
        let solution = puzzle.solution
        let numbers = puzzle.numbers
        let word = Set(game.entry?.cells ?? [])
        VStack(spacing: -Self.edge) {
            ForEach(0..<puzzle.rows, id: \.self) { row in
                HStack(spacing: -Self.edge) {
                    ForEach(0..<puzzle.cols, id: \.self) { col in
                        let cell = Cell(row: row, col: col)
                        if solution[cell] != nil {
                            Square(letter: game.letters[cell], number: numbers[cell], size: size,
                                   fill: fill(cell, inWord: word.contains(cell)),
                                   revealed: game.revealed.contains(cell), wrong: game.wrong.contains(cell),
                                   solved: game.isSolved)
                                .onTapGesture { game.select(cell) }
                                .accessibilityLabel(label(cell, number: numbers[cell]))
                                .accessibilityAddTraits(.isButton)
                        } else {
                            Color.clear.frame(width: size, height: size)
                        }
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.12), value: game.selected)
        .animation(.easeOut(duration: 0.12), value: game.across)
    }

    static let edge: CGFloat = 1.5

    private func fill(_ cell: Cell, inWord: Bool) -> Color {
        if game.isSolved { return Paper.square }
        if game.selected == cell { return Paper.sun }
        return inWord ? Paper.haze : Paper.square
    }

    private func label(_ cell: Cell, number: Int?) -> String {
        let letter = game.letters[cell].map { String($0) } ?? "empty"
        return [number.map { "\($0)" }, letter].compactMap { $0 }.joined(separator: ", ")
    }
}

/// One square of the grid.
private struct Square: View {
    let letter: Character?
    let number: Int?
    let size: CGFloat
    let fill: Color
    let revealed: Bool
    let wrong: Bool
    let solved: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(fill)
            Rectangle().strokeBorder(Paper.ink, lineWidth: GridView.edge)
            if let number {
                Text("\(number)")
                    .font(.system(size: max(8, size * 0.24), weight: .medium))
                    .foregroundStyle(Paper.ink)
                    .padding(.leading, size * 0.08)
                    .padding(.top, size * 0.04)
            }
            if let letter {
                Text(String(letter))
                    .font(.system(size: size * 0.56, weight: .semibold))
                    .foregroundStyle(revealed ? Paper.leaf : (solved ? Paper.leaf : Paper.ink))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(y: size * 0.06)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            if revealed {
                // A corner folded down: Lamp gave this one away.
                Path { path in
                    path.move(to: CGPoint(x: size * 0.68, y: GridView.edge))
                    path.addLine(to: CGPoint(x: size - GridView.edge, y: GridView.edge))
                    path.addLine(to: CGPoint(x: size - GridView.edge, y: size * 0.32))
                    path.closeSubpath()
                }
                .fill(Paper.leaf)
            }
            if wrong {
                Path { path in
                    path.move(to: CGPoint(x: size * 0.18, y: size * 0.82))
                    path.addLine(to: CGPoint(x: size * 0.82, y: size * 0.18))
                }
                .stroke(Paper.wrong, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: letter)
        .contentShape(Rectangle())
    }
}
