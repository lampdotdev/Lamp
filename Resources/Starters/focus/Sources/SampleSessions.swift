import Foundation

/// A few days of believable focus written on first launch, so the week's history shows what it's for before
/// the person has finished a session of their own. Each is marked `isExample`, which "Clear Examples" removes.
/// They fall on the six days before today, so today's dots start empty and fill with the person's own work.
enum SampleSessions {
    /// (days ago, hour started, what it was for)
    private static let plan: [(Int, Int, String)] = [
        (1, 9, "Write the quarterly update"),
        (1, 10, "Write the quarterly update"),
        (1, 14, "Inbox to zero"),
        (2, 9, "Read chapter 4"),
        (2, 11, "Sketch the onboarding flow"),
        (3, 10, "Sketch the onboarding flow"),
        (3, 11, "Sketch the onboarding flow"),
        (3, 15, "Practice Spanish"),
        (4, 9, "Write the quarterly update"),
        (5, 16, "Practice Spanish"),
        (6, 10, "Read chapter 3"),
        (6, 11, "Inbox to zero"),
    ]

    static func make(now: Date = Date()) -> [FocusSession] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return plan.compactMap { daysAgo, hour, intent in
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today),
                  let start = calendar.date(bySettingHour: hour, minute: 5, second: 0, of: day) else { return nil }
            return FocusSession(start: start, end: start.addingTimeInterval(25 * 60), minutes: 25,
                                intent: intent, isExample: true)
        }
    }
}
