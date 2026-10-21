import SwiftUI

/// The streak and a calendar of solved days, a month at a time.
struct HistoryView: View {
    let history: History

    @Environment(\.dismiss) private var dismiss
    @State private var month = Day.today

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 0) {
                stat("Streak", history.streak, symbol: "flame.fill", color: .orange)
                stat("Longest", history.longestStreak, symbol: "trophy.fill", color: Paper.sun)
                stat("Solved", history.solves.count, symbol: "checkmark.circle.fill", color: Paper.leaf)
                stat("Perfect", history.perfectCount, symbol: "star.fill", color: Paper.sun)
            }

            MonthCalendar(month: $month, history: history)

            HStack {
                if history.hasExamples {
                    Button("Clear Examples") { history.clearExamples() }
                        .help("Remove the sample days that came with the app")
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func stat(_ title: String, _ value: Int, symbol: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: symbol).foregroundStyle(color).font(.title3)
                Text("\(value)").font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
            }
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value)")
    }
}

/// One month of days, each marked by how its puzzle went: honey with a star for perfect, the accent color for
/// solved, a ring for today.
struct MonthCalendar: View {
    /// Any day in the month shown.
    @Binding var month: Day
    let history: History

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { move(by: -1) } label: { Image(systemName: "chevron.left") }
                    .help("Previous Month")
                Spacer()
                Text(month.date.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                Spacer()
                Button { move(by: 1) } label: { Image(systemName: "chevron.right") }
                    .help("Next Month")
                    .disabled(isCurrentMonth)
            }
            .buttonStyle(.borderless)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 36) }
                ForEach(days) { day in cell(day) }
            }
        }
    }

    private func cell(_ day: Day) -> some View {
        let solve = history.best(on: day)
        let isToday = day == .today
        return ZStack {
            Circle()
                .fill(solve == nil ? Color.clear : (solve!.isPerfect ? Paper.sun : Color.accentColor))
            if isToday {
                Circle().strokeBorder(Color.accentColor, lineWidth: 2).padding(solve == nil ? 0 : -3)
            }
            Text("\(day.day)")
                .font(.callout.monospacedDigit().weight(solve == nil ? .regular : .semibold))
                .foregroundStyle(solve == nil ? (day > .today ? Color.secondary.opacity(0.5) : Color.primary)
                                              : (solve!.isPerfect ? Paper.sunInk : Color.white))
            if solve?.isPerfect == true {
                Image(systemName: "star.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(Paper.sunInk)
                    .offset(y: 11)
            }
        }
        .frame(width: 34, height: 34)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(for: day, solve: solve))
    }

    private func label(for day: Day, solve: Solve?) -> String {
        let date = day.date.formatted(date: .long, time: .omitted)
        guard let solve else { return date }
        return "\(date), solved in \(Solve.time(solve.seconds))\(solve.isPerfect ? ", perfect" : "")"
    }

    // MARK: The month's layout

    private var firstOfMonth: Day { Day(year: month.year, month: month.month, day: 1) }

    private var days: [Day] {
        let count = Calendar.current.range(of: .day, in: .month, for: firstOfMonth.date)?.count ?? 30
        return (1...count).map { Day(year: month.year, month: month.month, day: $0) }
    }

    /// Empty cells before the 1st, so it falls under its weekday, counting from the week's first day here.
    private var leadingBlanks: Int {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: firstOfMonth.date)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var weekdays: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var isCurrentMonth: Bool {
        month.year == Day.today.year && month.month == Day.today.month
    }

    private func move(by months: Int) {
        let moved = Calendar.current.date(byAdding: .month, value: months, to: firstOfMonth.date) ?? firstOfMonth.date
        month = Day(moved)
    }
}
