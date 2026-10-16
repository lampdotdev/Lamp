import Foundation

/// How long each phase lasts and how the end sounds. Saved whole in LampStore under "settings"; new
/// properties are optional-friendly because each has a default and decoding falls back to it.
struct FocusSettings: Codable, Equatable {
    var focusMinutes = 25
    var shortBreakMinutes = 5
    var longBreakMinutes = 15
    /// A long break comes after this many finished focus sessions in a row.
    var longBreakEvery = 4
    /// Breaks start by themselves when a focus session ends; the next focus waits for the person.
    var autoStartBreaks = true
    var playSound = true
    /// The examples are written once, on first launch, and never again after they're cleared.
    var examplesWritten = false

    func minutes(for phase: Phase) -> Int {
        switch phase {
        case .focus: focusMinutes
        case .shortBreak: shortBreakMinutes
        case .longBreak: longBreakMinutes
        }
    }

    init() {}

    // Reads settings saved by an earlier version that lacked some of these, keeping the defaults for the rest.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FocusSettings()
        focusMinutes = try c.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? d.focusMinutes
        shortBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? d.shortBreakMinutes
        longBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? d.longBreakMinutes
        longBreakEvery = try c.decodeIfPresent(Int.self, forKey: .longBreakEvery) ?? d.longBreakEvery
        autoStartBreaks = try c.decodeIfPresent(Bool.self, forKey: .autoStartBreaks) ?? d.autoStartBreaks
        playSound = try c.decodeIfPresent(Bool.self, forKey: .playSound) ?? d.playSound
        examplesWritten = try c.decodeIfPresent(Bool.self, forKey: .examplesWritten) ?? d.examplesWritten
    }
}
