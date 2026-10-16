import SwiftUI

/// What a finished puzzle came to: steps against par, the time, and the streak. It stays in place for the rest
/// of the day; tomorrow brings a new puzzle.
struct DoneCard: View {
    let solve: Solve
    let streak: Int

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: solve.isPerfect ? "star.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 46))
                .foregroundStyle(solve.isPerfect ? Palette.honey : Palette.goal)
                .symbolEffect(.bounce, value: appeared)
                .accessibilityHidden(true)

            Text(headline)
                .font(.title2.weight(.semibold))

            HStack(spacing: 30) {
                stat("Steps", "\(solve.steps)")
                stat("Par", "\(solve.par)")
                stat("Time", Solve.time(solve.seconds))
                stat("Streak", "\(streak)", symbol: "flame.fill")
            }

            Text("A new puzzle tomorrow.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 30)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.08))
        }
        .onAppear { appeared = true }
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        if solve.isPerfect { return "Perfect climb." }
        if solve.usedHint { return "Solved, with a little help." }
        let over = solve.steps - solve.par
        return over == 1 ? "Solved, one step over par." : "Solved, \(over) steps over par."
    }

    private func stat(_ title: String, _ value: String, symbol: String? = nil) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).foregroundStyle(.orange) }
                Text(value)
            }
            .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
