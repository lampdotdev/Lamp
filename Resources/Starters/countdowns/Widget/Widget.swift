import WidgetKit
import SwiftUI

/// What the app shares under "countdowns": the same type as the app's `WidgetCountdown`, written here too
/// because the widget shares no code with the app.
struct WidgetCountdown: Codable, Identifiable {
    var name: String
    var date: Date
    var symbol: String
    var color: String
    var repeatsYearly: Bool

    var id: String { name + "\(date.timeIntervalSince1970)" }

    /// The day it next falls on from `today` (today included), or nil for a one-time day that's past. The same
    /// sum as the app's, so the widget turns over at midnight by itself, with the app closed.
    func nextDay(from today: Date, calendar: Calendar = .current) -> Date? {
        let start = calendar.startOfDay(for: today)
        guard repeatsYearly else {
            let day = calendar.startOfDay(for: date)
            return day >= start ? day : nil
        }
        let parts = calendar.dateComponents([.month, .day], from: date)
        return calendar.nextDate(after: start.addingTimeInterval(-1), matching: parts,
                                 matchingPolicy: .previousTimePreservingSmallerComponents)
    }

    func daysLeft(from today: Date, calendar: Calendar = .current) -> Int? {
        guard let next = nextDay(from: today, calendar: calendar) else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: next).day
    }

    var tint: Color {
        switch color {
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "mint": .mint
        case "teal": .teal
        case "blue": .blue
        case "purple": .purple
        case "pink": .pink
        default: .indigo
        }
    }
}

struct CountdownEntry: TimelineEntry {
    let date: Date
    /// Nil until the app has run once and shared its countdowns.
    let countdowns: [WidgetCountdown]?

    /// The ones still ahead on this entry's day, soonest first, each with its days left.
    var upcoming: [(countdown: WidgetCountdown, days: Int)] {
        (countdowns ?? [])
            .compactMap { countdown in countdown.daysLeft(from: date).map { (countdown, $0) } }
            .sorted { $0.days != $1.days ? $0.days < $1.days : $0.countdown.name < $1.countdown.name }
    }
}

struct CountdownProvider: TimelineProvider {
    func placeholder(in context: Context) -> CountdownEntry {
        CountdownEntry(date: Date(), countdowns: Self.preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (CountdownEntry) -> Void) {
        LampWidget.read([WidgetCountdown].self, from: "countdowns") { countdowns in
            // The gallery shows the examples before the app has shared anything, so it never looks empty.
            completion(CountdownEntry(date: Date(), countdowns: countdowns ?? (context.isPreview ? Self.preview : nil)))
        }
    }

    /// One entry now and one at each of the next seven midnights, so the numbers count down a day at a time
    /// even when the app isn't running.
    func getTimeline(in context: Context, completion: @escaping (Timeline<CountdownEntry>) -> Void) {
        LampWidget.read([WidgetCountdown].self, from: "countdowns") { countdowns in
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            var entries = [CountdownEntry(date: Date(), countdowns: countdowns)]
            for offset in 1...7 {
                if let midnight = calendar.date(byAdding: .day, value: offset, to: today) {
                    entries.append(CountdownEntry(date: midnight, countdowns: countdowns))
                }
            }
            completion(Timeline(entries: entries, policy: .atEnd))
        }
    }

    static let preview: [WidgetCountdown] = {
        let calendar = Calendar.current
        func inDays(_ days: Int) -> Date { calendar.date(byAdding: .day, value: days, to: Date()) ?? Date() }
        return [
            WidgetCountdown(name: "Concert", date: inDays(18), symbol: "music.mic", color: "purple", repeatsYearly: false),
            WidgetCountdown(name: "Weekend away", date: inDays(42), symbol: "airplane", color: "teal", repeatsYearly: false),
            WidgetCountdown(name: "Mum's birthday", date: inDays(75), symbol: "birthday.cake.fill", color: "pink", repeatsYearly: true),
        ]
    }()
}

@main
struct CountdownsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Countdowns", provider: CountdownProvider()) { entry in
            CountdownWidgetView(entry: entry)
        }
        .configurationDisplayName("Countdowns")
        .description("Days until the things you're waiting for.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
