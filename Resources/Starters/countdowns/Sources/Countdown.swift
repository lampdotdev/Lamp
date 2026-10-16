import SwiftUI

/// One thing the person is waiting for. `date` is the day itself (its time is ignored); for a yearly one it is
/// any year's date, and only its month and day count.
struct Countdown: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var date: Date
    var symbol: String
    var color: CountdownColor
    var repeatsYearly = false
    /// Written on first launch to show what the app does; Clear Examples removes only these.
    var isExample = false

    /// The day it next falls on, counted from `today`: for a yearly one this year's or next year's, so a
    /// birthday shows "Today!" on the day and rolls over the day after. Nil for a one-time date that's past.
    func nextDay(from today: Date, calendar: Calendar = .current) -> Date? {
        let start = calendar.startOfDay(for: today)
        guard repeatsYearly else {
            let day = calendar.startOfDay(for: date)
            return day >= start ? day : nil
        }
        let parts = calendar.dateComponents([.month, .day], from: date)
        // Searching from just before today includes today. A 29 February falls on the 28th in other years.
        return calendar.nextDate(after: start.addingTimeInterval(-1), matching: parts,
                                 matchingPolicy: .previousTimePreservingSmallerComponents)
    }

    /// Whole days from `today` to the next day it falls on: 0 on the day, nil once a one-time date is past.
    func daysLeft(from today: Date, calendar: Calendar = .current) -> Int? {
        guard let next = nextDay(from: today, calendar: calendar) else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: next).day
    }

    /// "Today!", "Tomorrow" or "12 days", for rows.
    func daysText(from today: Date) -> String {
        switch daysLeft(from: today) {
        case nil: return "Done"
        case 0: return "Today!"
        case 1: return "Tomorrow"
        case let days?: return "\(days) days"
        }
    }

    /// The short form beside the menu bar icon: "Today!" or "12d".
    func shortLabel(from today: Date) -> String {
        guard let days = daysLeft(from: today) else { return "" }
        return days == 0 ? "Today!" : "\(days)d"
    }
}

/// The small set of colors a countdown can take, named so they read the same on both sides of the widget.
enum CountdownColor: String, Codable, CaseIterable, Identifiable {
    case red, orange, yellow, green, mint, teal, blue, indigo, purple, pink
    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        }
    }

    var name: String { rawValue.capitalized }
}

/// The symbols offered in the editor: things people count down to.
enum CountdownSymbols {
    static let all = [
        "airplane", "beach.umbrella.fill", "gift.fill", "birthday.cake.fill", "music.mic", "figure.run",
        "heart.fill", "star.fill", "graduationcap.fill", "briefcase.fill", "house.fill", "car.fill",
        "tent.fill", "party.popper.fill", "sparkles", "calendar",
    ]
}
