import Foundation

/// How a due date reads in a row: "Today", "Tomorrow", "Thu", "Oct 30", with the time when it has one, or how late.
enum Format {
    static func due(_ todo: Todo, now: Date = .now) -> String? {
        guard let due = todo.due else { return nil }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0
        let time = todo.hasTime ? " " + due.formatted(date: .omitted, time: .shortened) : ""
        switch days {
        case ..<(-1) where !todo.isDone: return "\(-days) days late"
        case -1 where !todo.isDone: return "Yesterday"
        case 0: return "Today" + time
        case 1: return "Tomorrow" + time
        case 2...6: return due.formatted(.dateTime.weekday(.abbreviated)) + time
        default: return due.formatted(.dateTime.month(.abbreviated).day()) + time
        }
    }

    /// "month", "two months", "three months".
    static func lookBack(_ days: Int) -> String {
        switch days / 30 {
        case ...1: "month"
        case 2: "two months"
        case 3: "three months"
        default: "\(days / 30) months"
        }
    }

    static func isLate(_ todo: Todo, now: Date = .now) -> Bool {
        guard let due = todo.due, !todo.isDone else { return false }
        return due < Calendar.current.startOfDay(for: now)
    }
}
