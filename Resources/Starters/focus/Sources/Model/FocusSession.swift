import Foundation

/// What the timer is counting down: a stretch of focus, or one of the two kinds of break.
enum Phase: String, Codable {
    case focus, shortBreak, longBreak

    var isBreak: Bool { self != .focus }

    var title: String {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Short Break"
        case .longBreak: "Long Break"
        }
    }

    var symbol: String {
        switch self {
        case .focus: "timer"
        case .shortBreak, .longBreak: "cup.and.saucer"
        }
    }
}

/// One finished stretch of focus. Breaks aren't recorded: the history is about what the person worked on.
struct FocusSession: Codable, Identifiable, Hashable {
    var id = UUID()
    var start: Date
    var end: Date
    /// The length it was set to; pauses can make end minus start longer.
    var minutes: Int
    /// What it was for, in the person's words; empty when they didn't say.
    var intent: String
    /// Sample sessions written on first launch, so "Clear Examples" can take out just those.
    var isExample = false
}
