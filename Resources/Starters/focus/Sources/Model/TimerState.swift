import Foundation

/// Where the timer is, saved under "timer" so it carries on across a quit or a change to the app: a running
/// timer is kept as the moment it ends, so time passes correctly while the app is closed.
struct TimerState: Codable, Equatable {
    enum Status: Codable, Equatable {
        case idle
        case running(endsAt: Date)
        case paused(remaining: TimeInterval)
    }

    var phase: Phase = .focus
    var status: Status = .idle
    /// What the current (or next) focus session is for.
    var intent = ""
    /// The length the current phase started with, in seconds; nil until it starts.
    var length: TimeInterval?
    /// When the running focus session began, so a finished one is recorded with its real start.
    var startedAt: Date?
    /// Focus sessions finished since the last long break, and the day they were counted on: a new day starts
    /// the count over.
    var inARow = 0
    var countedOn: Date?
}
