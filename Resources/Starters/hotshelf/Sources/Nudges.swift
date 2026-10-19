import Foundation

/// Notifications from a friend who knows your kitchen. Scheduled ahead, so they arrive with the app closed,
/// and rewritten whenever the shelf changes so they're always about the shelf as it is.
enum Nudges {
    static var fridayOn: Bool { UserDefaults.standard.object(forKey: "nudge.friday") as? Bool ?? true }
    static var quarterlyOn: Bool { UserDefaults.standard.object(forKey: "nudge.quarterly") as? Bool ?? true }

    static func reschedule(_ bottles: [Bottle]) {
        scheduleFriday(bottles)
        scheduleQuarterly(bottles)
    }

    private static func scheduleFriday(_ bottles: [Bottle]) {
        let cal = Calendar.current
        guard fridayOn,
              let friday = cal.nextDate(after: Date(), matching: DateComponents(hour: 18, minute: 0, weekday: 6),
                                        matchingPolicy: .nextTime) else {
            LampNotifications.cancel("friday"); return
        }
        let forgotten = bottles.filter { !$0.isRetired && friday.timeIntervalSince($0.lastTouched) > 30 * 86400 }
            .sorted { $0.lastTouched < $1.lastTouched }
        guard let b = forgotten.first else { LampNotifications.cancel("friday"); return }
        let lines = [
            "\(b.name) hasn't left the shelf in a month. It's Friday. Be nice to it.",
            "Friday night, and \(b.name) is still waiting for a turn. Tonight's the night.",
            "Remember \(b.name)? It remembers you. Open it with dinner.",
        ]
        let extra = forgotten.count > 1 ? " (\(forgotten.count - 1) more are feeling left out too.)" : ""
        LampNotifications.send("Open something forgotten", body: lines[abs(b.id.hashValue) % lines.count] + extra,
                               at: friday, id: "friday")
    }

    private static func scheduleQuarterly(_ bottles: [Bottle]) {
        let cal = Calendar.current
        let now = Date()
        let month = cal.component(.month, from: now)
        let startMonth = ((month - 1) / 3) * 3 + 1
        guard quarterlyOn,
              let quarterStart = cal.date(from: DateComponents(year: cal.component(.year, from: now), month: startMonth, day: 1)),
              let next = cal.date(byAdding: .month, value: 3, to: quarterStart),
              let at = cal.date(bySettingHour: 10, minute: 0, second: 0, of: next) else {
            LampNotifications.cancel("quarterly"); return
        }
        let bought = bottles.filter { $0.addedAt >= quarterStart }
        let finished = bottles.filter { ($0.retiredAt ?? .distantPast) >= quarterStart }
        guard !bought.isEmpty || !finished.isEmpty else { LampNotifications.cancel("quarterly"); return }
        let names = finished.prefix(3).map(\.name).joined(separator: ", ")
        var body = "You finished \(finished.count) and bought \(bought.count) this quarter."
        if !names.isEmpty { body += " Gone but not forgotten: \(names)." }
        if bought.count > finished.count + 2 {
            body += " The shelf is winning. Maybe pour a little heavier?"
        } else if finished.count >= bought.count, !finished.isEmpty {
            body += " Respect. You actually use what you buy."
        }
        LampNotifications.send("Your quarter in hot sauce", body: body, at: at, id: "quarterly")
    }
}
