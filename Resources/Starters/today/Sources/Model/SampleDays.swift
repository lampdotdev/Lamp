import Foundation

/// A believable past week, written once on the very first launch so the app shows what it does the moment it
/// opens: a few days of priorities and moods, something left over from yesterday to carry over, and a
/// half-planned today. Every part is marked as an example, so Clear Examples takes it all away, and the flag
/// saved here keeps it from ever coming back.
enum SampleDays {
    private static let flag = "samplesAdded"

    @MainActor
    static func addOnFirstLaunch(to model: TodayModel) {
        guard LampStore.load(Bool.self, from: flag) != true else { return }
        LampStore.save(true, to: flag)
        guard model.days.isEmpty else { return }
        model.insert(week())
    }

    /// Days before today, counted back from it, with what was planned, what got done and how it went.
    private static func week() -> [Day] {
        [
            day(0, [("Send the proposal to Maya", false), ("A walk at lunch, no phone", true)],
                notes: "Dentist moved to Tuesday, 9:30.\nOffsite ideas: shorter talks, longer lunch, one walk outside.\nCoffee beans running low.",
                mood: .good),
            day(1, [("Finish the proposal draft", true), ("Book train tickets for Saturday", false), ("Water the plants", true)],
                notes: "Maya wants the numbers by Thursday.", mood: .okay),
            day(2, [("Review Sam's pull request", true), ("Plan the offsite agenda", true), ("Pick up the dry cleaning", true)],
                mood: .great),
            day(3, [("Quarterly numbers", true), ("Reply to the landlord", false), ("Yoga at 6", true)],
                mood: .good),
            day(4, [("Interview prep", true), ("Call Mum", true), ("Clear the inbox", false)],
                notes: "Long day. Early night.", mood: .low),
            day(5, [("Sketch the new homepage", true), ("Groceries for the week", true)],
                mood: .good),
            day(6, [("Bike in for a service", false), ("Read for an hour", true), ("Batch-cook lunches", true)],
                mood: .okay),
        ]
    }

    private static func day(_ daysAgo: Int, _ priorities: [(String, Bool)], notes: String = "", mood: Mood) -> Day {
        Day(id: DayKey.key(daysBefore: daysAgo),
            priorities: priorities.map { Priority(title: $0.0, done: $0.1, isExample: true) },
            notes: notes,
            mood: mood,
            notesAreExample: !notes.isEmpty,
            moodIsExample: true)
    }
}
