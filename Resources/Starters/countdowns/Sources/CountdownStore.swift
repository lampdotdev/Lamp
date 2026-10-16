import SwiftUI
import AppKit

/// The person's settings, saved whole.
struct Prefs: Codable, Equatable {
    var showsDaysInMenuBar = true
}

/// What the widget is handed: every countdown, with what it needs to draw and to work out the days itself, so
/// it stays right at midnight while the app is closed. The widget declares the same type.
struct WidgetCountdown: Codable {
    var name: String
    var date: Date
    var symbol: String
    var color: String
    var repeatsYearly: Bool
}

/// Holds the countdowns, saves every change to LampStore and hands the widget what it shows.
@MainActor
final class CountdownStore: ObservableObject {
    @Published private(set) var countdowns: [Countdown] = []
    /// The day everything is counted from. Moved on at midnight and on wake, so the numbers never go stale.
    @Published private(set) var today = Date()
    @Published var prefs: Prefs {
        didSet { LampStore.save(prefs, to: "prefs") }
    }

    private let saved = LampStore.collection("countdowns", of: Countdown.self)
    private var observers: [NSObjectProtocol] = []

    init() {
        prefs = LampStore.load(Prefs.self, from: "prefs") ?? Prefs()
        writeExamplesOnce()
        countdowns = saved.all()
        shareWithWidget()
        watchTheDay()
    }

    /// Countdowns still ahead (today included), soonest first.
    var upcoming: [Countdown] {
        let today = today
        let ahead: [(countdown: Countdown, days: Int)] = countdowns.compactMap { countdown in
            guard let days = countdown.daysLeft(from: today) else { return nil }
            return (countdown, days)
        }
        let sorted = ahead.sorted { a, b in a.days != b.days ? a.days < b.days : a.countdown.name < b.countdown.name }
        return sorted.map { $0.countdown }
    }

    /// One-time countdowns whose day has gone: no longer shown in the widget, kept here to be removed.
    var past: [Countdown] {
        countdowns.filter { $0.daysLeft(from: today) == nil }.sorted { $0.date > $1.date }
    }

    var hasExamples: Bool { countdowns.contains(where: \.isExample) }

    // MARK: Changes

    /// A sample the person changes and saves is theirs from then on, so Clear Examples keeps it.
    func save(_ countdown: Countdown) {
        var countdown = countdown
        if countdowns.first(where: { $0.id == countdown.id }) != countdown { countdown.isExample = false }
        saved.put(countdown)
        if let index = countdowns.firstIndex(where: { $0.id == countdown.id }) {
            countdowns[index] = countdown
        } else {
            countdowns.append(countdown)
        }
        shareWithWidget()
    }

    func delete(_ countdown: Countdown) {
        saved.delete(countdown.id)
        countdowns.removeAll { $0.id == countdown.id }
        shareWithWidget()
    }

    func clearExamples() {
        for countdown in countdowns where countdown.isExample { saved.delete(countdown.id) }
        countdowns.removeAll(where: \.isExample)
        shareWithWidget()
    }

    // MARK: Examples

    /// Sample countdowns on the very first launch only, dated from that day so they're always ahead. A flag
    /// remembers they were written, so clearing them (or deleting each) never brings them back.
    private func writeExamplesOnce() {
        guard LampStore.load(Bool.self, from: "examplesWritten") != true else { return }
        let calendar = Calendar.current
        func inDays(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: Date())) ?? Date()
        }
        saved.put([
            Countdown(name: "Concert", date: inDays(18), symbol: "music.mic", color: .purple, isExample: true),
            Countdown(name: "Weekend away", date: inDays(42), symbol: "airplane", color: .teal, isExample: true),
            Countdown(name: "Mum's birthday", date: inDays(75), symbol: "birthday.cake.fill", color: .pink,
                      repeatsYearly: true, isExample: true),
            Countdown(name: "Half marathon", date: inDays(110), symbol: "figure.run", color: .orange, isExample: true),
        ])
        LampStore.save(true, to: "examplesWritten")
    }

    // MARK: The widget

    private func shareWithWidget() {
        let shared = countdowns.map {
            WidgetCountdown(name: $0.name, date: $0.date, symbol: $0.symbol, color: $0.color.rawValue,
                            repeatsYearly: $0.repeatsYearly)
        }
        LampWidget.share(shared, as: "countdowns")
    }

    // MARK: The day

    /// Midnight, a change of time zone or clock, and waking from sleep all may mean a new day.
    private func watchTheDay() {
        let refresh: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in self?.today = Date() }
        }
        observers = [
            NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main, using: refresh),
            NotificationCenter.default.addObserver(forName: NSNotification.Name.NSSystemClockDidChange, object: nil, queue: .main, using: refresh),
            NotificationCenter.default.addObserver(forName: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil, queue: .main, using: refresh),
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: refresh),
        ]
    }
}
