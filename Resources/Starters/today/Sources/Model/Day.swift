import Foundation

/// One day in the planner: its priorities, its notes and how it went. Saved whole in LampStore's "days"
/// collection, keyed by the calendar date ("2026-10-15"), so a day is found without any date arithmetic.
///
/// Sample content is marked part by part (`isExample` on a priority, `notesAreExample`, `moodIsExample`) rather
/// than per day: today starts with examples the person may keep editing, and Clear Examples takes away only
/// the parts they never touched.
struct Day: Codable, Identifiable, Equatable {
    var id: String
    var priorities: [Priority] = []
    var notes: String = ""
    var mood: Mood?
    var notesAreExample = false
    var moodIsExample = false
    /// Set once the carry-over offer was taken or waved away, so it isn't offered again that day.
    var carryOverHandled = false

    var date: Date { DayKey.date(for: id) ?? Date() }

    /// The priorities with something written in them.
    var written: [Priority] { priorities.filter { !$0.isEmpty } }
    var doneCount: Int { written.filter(\.done).count }
    var unfinished: [Priority] { written.filter { !$0.done } }

    var hasExamples: Bool { notesAreExample || moodIsExample || priorities.contains(where: \.isExample) }

    /// Nothing worth keeping: no priorities, notes or mood.
    var isBlank: Bool { written.isEmpty && notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && mood == nil }

    /// Always exactly `count` slots, padded with empty ones, so the view can bind to a fixed list of rows.
    /// Anything past `count` (from a time there were more slots) is kept in storage but not shown.
    func slots(_ count: Int) -> [Priority] {
        var shown = Array(priorities.prefix(count))
        while shown.count < count { shown.append(Priority()) }
        return shown
    }
}

struct Priority: Codable, Identifiable, Equatable {
    var id = UUID()
    var title = ""
    var done = false
    var isExample = false

    var isEmpty: Bool { title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// How the day's going, as weather: a calm way to say it without picking a face.
enum Mood: Int, Codable, CaseIterable, Identifiable {
    case rough = 1, low, okay, good, great

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .rough: "Rough"
        case .low: "Low"
        case .okay: "Okay"
        case .good: "Good"
        case .great: "Great"
        }
    }

    var symbol: String {
        switch self {
        case .rough: "cloud.bolt.rain.fill"
        case .low: "cloud.drizzle.fill"
        case .okay: "cloud.fill"
        case .good: "cloud.sun.fill"
        case .great: "sun.max.fill"
        }
    }
}

/// The calendar date as text, in the person's own time zone. The widget has its own copy (Widget/), and
/// the two must agree, since it's how the widget tells whether what it shows is today's.
enum DayKey {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func key(for date: Date) -> String { formatter.string(from: date) }
    static func date(for key: String) -> Date? { formatter.date(from: key) }

    static func key(daysBefore count: Int, _ date: Date = Date()) -> String {
        key(for: Calendar.current.date(byAdding: .day, value: -count, to: date) ?? date)
    }
}
