import Foundation

/// What the widget is given: today's priorities and nothing else. The widget can't read LampStore, so the app
/// shares this with `LampWidget.share` whenever today changes. Widget/TodaySummary.swift is the same type,
/// written again there: change both together.
struct TodaySummary: Codable {
    struct Item: Codable, Hashable {
        var id: String
        var title: String
        var done: Bool
    }

    /// The day this is about ("2026-10-15"), so the widget can tell yesterday's list from today's.
    var day: String
    var items: [Item]
    var mood: Int?

    init(today: Day, slots: [Priority]) {
        day = today.id
        items = slots.filter { !$0.isEmpty }.map { Item(id: $0.id.uuidString, title: $0.title, done: $0.done) }
        mood = today.mood?.rawValue
    }
}
