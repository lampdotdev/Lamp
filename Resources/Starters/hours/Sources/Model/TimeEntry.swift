import Foundation

/// A stretch of work for one client. The running timer is simply the entry with no end yet.
struct TimeEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var clientID: UUID
    var start: Date
    /// Nil while the timer is running.
    var end: Date?
    /// A few words on what was done; it becomes the invoice's line description.
    var note: String
    var isExample: Bool? = nil

    var isRunning: Bool { end == nil }

    func duration(now: Date = .now) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start))
    }
}
