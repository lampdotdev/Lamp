import Foundation

/// What the app shares for the widget: today's priorities. The same type as Sources/Model/TodaySummary.swift,
/// written again here because the widget shares no code with the app: change both together.
struct TodaySummary: Codable {
    struct Item: Codable, Hashable {
        var id: String
        var title: String
        var done: Bool
    }

    var day: String
    var items: [Item]
    var mood: Int?

    var doneCount: Int { items.filter(\.done).count }

    /// Whether this is about the day it is at `date`, written the way the app writes it ("2026-10-15").
    func isFor(_ date: Date) -> Bool { day == Self.key(for: date) }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func key(for date: Date) -> String { formatter.string(from: date) }
}
