import Foundation

/// A nudge at nine each morning that the day's crossword is ready. A week of them is scheduled at a time, so they
/// keep coming while the app stays closed; each launch and each delivery schedules the week again, and a day
/// already solved gets none.
enum Reminder {
    static let hour = 9

    static func schedule(for place: String, solvedToday: Bool) {
        let calendar = Calendar.current
        for offset in 0..<7 {
            let day = Day.today.adding(days: offset)
            let id = "reminder \(day.key)"
            guard let at = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day.date) else { continue }
            if at <= Date() || (offset == 0 && solvedToday) {
                LampNotifications.cancel(id)
            } else {
                LampNotifications.send("Today's crossword is ready", body: "The \(place) Crossword, fresh this morning.", at: at, id: id)
            }
        }
    }
}
