import SwiftUI

/// Everything the app knows: every day kept, which day is today, and the changes the window, the Day menu,
/// the widget and Siri make. Each change saves the day it touched and tells the widget.
@MainActor
final class TodayModel: ObservableObject {
    static let shared = TodayModel()

    /// How many priorities a day has. The rows, the widget and the week's dots all follow this number.
    static let prioritiesPerDay = 3

    /// How far back the week strip and the carry-over offer look.
    static let daysShown = 7

    @Published private(set) var days: [String: Day] = [:]
    @Published private(set) var todayKey = DayKey.key(for: Date())

    private let store = LampStore.collection("days", of: Day.self)

    private init() {
        for day in store.all() { days[day.id] = day }
        SampleDays.addOnFirstLaunch(to: self)
        shareWithWidget()
        // The widget's checkboxes come here, also those pressed while the app was closed.
        LampWidget.onAction { name, payload in
            guard name == "toggle", let text = payload.decode(String.self), let id = UUID(uuidString: text) else { return }
            TodayModel.shared.toggle(id)
        }
    }

    // MARK: Reading

    var today: Day { days[todayKey] ?? Day(id: todayKey) }

    var todaySlots: [Priority] { today.slots(Self.prioritiesPerDay) }

    /// The last `daysShown` days, oldest first, ending with today. Days with nothing saved come back blank.
    var recentDays: [Day] {
        (0..<Self.daysShown).reversed().map { offset in
            let key = DayKey.key(daysBefore: offset)
            return days[key] ?? Day(id: key)
        }
    }

    var hasExamples: Bool { days.values.contains(where: \.hasExamples) }

    /// What's left from the most recent earlier day, when today still has room for it and hasn't answered.
    var carryOverOffer: CarryOver? {
        guard !today.carryOverHandled, todaySlots.contains(where: \.isEmpty) else { return nil }
        let earlier = recentDays.dropLast().reversed().first { !$0.written.isEmpty }
        guard let earlier, !earlier.unfinished.isEmpty else { return nil }
        // Leave out what's already on today's list, carried or written again.
        let titles = Set(today.written.map(\.title))
        let left = earlier.unfinished.filter { !titles.contains($0.title) }
        return left.isEmpty ? nil : CarryOver(from: earlier, priorities: left)
    }

    struct CarryOver {
        let from: Day
        let priorities: [Priority]

        /// "yesterday", or the weekday when the last planned day was earlier.
        var when: String {
            if Calendar.current.isDateInYesterday(from.date) { return "yesterday" }
            return from.date.formatted(.dateTime.weekday(.wide))
        }
    }

    // MARK: Changing today

    func setTitle(_ title: String, at index: Int) {
        changeToday { day in
            var slots = day.slots(max(Self.prioritiesPerDay, day.priorities.count))
            slots[index].title = title
            slots[index].isExample = false
            if slots[index].isEmpty { slots[index].done = false }
            day.priorities = slots
        }
    }

    func toggle(_ id: UUID) {
        changeToday { day in
            guard let index = day.priorities.firstIndex(where: { $0.id == id }), !day.priorities[index].isEmpty else { return }
            day.priorities[index].done.toggle()
        }
    }

    func toggle(at index: Int) {
        let slot = todaySlots[index]
        guard !slot.isEmpty else { return }
        toggle(slot.id)
    }

    func setNotes(_ notes: String) {
        changeToday { day in
            day.notes = notes
            day.notesAreExample = false
        }
    }

    /// Choosing the mood already chosen takes it back.
    func setMood(_ mood: Mood) {
        changeToday { day in
            day.mood = day.mood == mood ? nil : mood
            day.moodIsExample = false
        }
    }

    /// Puts a priority in the first empty slot. False when today is full.
    @discardableResult
    func addPriority(_ title: String) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let index = todaySlots.firstIndex(where: \.isEmpty) else { return false }
        setTitle(title, at: index)
        return true
    }

    /// Fills today's empty slots with what was left, in order, as far as they go.
    func carryOver() {
        guard let offer = carryOverOffer else { return }
        changeToday { day in
            var slots = day.slots(Self.prioritiesPerDay)
            var waiting = offer.priorities[...]
            for index in slots.indices where slots[index].isEmpty {
                guard let next = waiting.popFirst() else { break }
                // A new id: it's today's priority now, checked off separately from the day it came from.
                slots[index] = Priority(title: next.title, isExample: next.isExample)
            }
            day.priorities = slots
            day.carryOverHandled = true
        }
    }

    func dismissCarryOver() {
        changeToday { $0.carryOverHandled = true }
    }

    // MARK: The day turning over

    /// Called when the date changes and when the app comes forward, since a Mac can sleep through midnight.
    func refreshDay() {
        let key = DayKey.key(for: Date())
        guard key != todayKey else { return }
        todayKey = key
        shareWithWidget()
    }

    // MARK: Examples

    /// Takes away the sample content and nothing the person wrote: example priorities, notes and moods go, and
    /// a day left with nothing in it goes with them.
    func clearExamples() {
        for var day in days.values where day.hasExamples {
            day.priorities.removeAll(where: \.isExample)
            if day.notesAreExample { day.notes = ""; day.notesAreExample = false }
            if day.moodIsExample { day.mood = nil; day.moodIsExample = false }
            if day.isBlank {
                days[day.id] = nil
                store.delete(day.id)
            } else {
                days[day.id] = day
                store.put(day)
            }
        }
        shareWithWidget()
    }

    /// Saves days written by `SampleDays`, without touching the widget (the model shares once it's ready).
    func insert(_ newDays: [Day]) {
        for day in newDays { days[day.id] = day }
        store.put(newDays)
    }

    // MARK: Saving

    private func changeToday(_ change: (inout Day) -> Void) {
        var day = today
        change(&day)
        guard day != today else { return }
        days[day.id] = day
        store.put(day)
        shareWithWidget()
    }

    private func shareWithWidget() {
        LampWidget.share(TodaySummary(today: today, slots: todaySlots), as: "today")
    }
}
