import SwiftUI

/// What a finished crossword came to, in the clues' place: a headline, the time, the streak. It stays for the
/// rest of the day; the next paper comes at midnight.
struct DoneCard: View {
    let solve: Solve
    let streak: Int
    let perfect: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text([solve.edition.map { "No. \($0)" }, solve.place].compactMap { $0 }.joined(separator: " · ").uppercased())
                .font(Paper.label)
                .tracking(1.2)
                .padding(.bottom, 6)
            Rule(heavy: true)
            Text(headline)
                .font(Paper.serif(34))
                .padding(.top, 14)
            Text(solve.isPerfect ? "Every square, no help." : "Some letters were checked or revealed.")
                .font(Paper.serif(15, weight: .regular))
                .italic()
                .foregroundStyle(Paper.faded)
                .padding(.top, 4)
            HStack(spacing: 0) {
                stat("Time", Solve.time(solve.seconds))
                stat("Streak", "\(streak)")
                stat("Perfect", "\(perfect)")
            }
            .padding(.vertical, 14)
            .overlay(alignment: .top) { Rule() }
            .overlay(alignment: .bottom) { Rule() }
            .padding(.top, 22)
            Text("Tomorrow's paper comes at midnight.")
                .font(Paper.label)
                .textCase(.uppercase)
                .tracking(1)
                .padding(.top, 14)
        }
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        solve.isPerfect ? "Solved." : "Solved, with a little help."
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 24, weight: .bold).monospacedDigit())
            Text(title.uppercased()).font(Paper.label).tracking(1).foregroundStyle(Paper.faded)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
