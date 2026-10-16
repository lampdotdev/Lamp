import AppKit
import SwiftUI

/// The one model behind the menu bar label, the panel and Settings: the timer, the settings and the sessions
/// already finished. Everything it changes is saved at once in LampStore.
@MainActor
final class FocusTimer: ObservableObject {
    /// One shared timer: the menu bar label, the panel and Settings all show the same one.
    static let shared = FocusTimer()

    @Published private(set) var state: TimerState
    @Published var settings: FocusSettings {
        didSet { if settings != oldValue { LampStore.save(settings, to: "settings") } }
    }
    /// Every finished focus session, newest first.
    @Published private(set) var sessions: [FocusSession]
    /// Moves once a second while running, so views showing the time left draw again.
    @Published private(set) var now = Date()

    private let store = LampStore.collection("sessions", of: FocusSession.self)
    private var ticker: Timer?
    private static let notificationID = "focus.phase-end"

    private init() {
        state = LampStore.load(TimerState.self, from: "timer") ?? TimerState()
        settings = LampStore.load(FocusSettings.self, from: "settings") ?? FocusSettings()
        sessions = []
        if !settings.examplesWritten {
            store.put(SampleSessions.make())
            settings.examplesWritten = true
            LampStore.save(settings, to: "settings")
        }
        reloadSessions()
        startOverOnNewDay()
        catchUp()
        if case .running = state.status { startTicking() }
        // Today's dots and the week start over at midnight even while nothing is running.
        NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                FocusTimer.shared.startOverOnNewDay()
                FocusTimer.shared.now = Date()
            }
        }
    }

    // MARK: What the views read

    var isRunning: Bool { if case .running = state.status { true } else { false } }
    var isPaused: Bool { if case .paused = state.status { true } else { false } }

    /// The phase's length: the one it started with, so changing Settings mid-session moves only the next one.
    var totalSeconds: TimeInterval { state.length ?? TimeInterval(settings.minutes(for: state.phase) * 60) }

    var remaining: TimeInterval {
        switch state.status {
        case .idle: totalSeconds
        case .running(let endsAt): max(0, endsAt.timeIntervalSince(now))
        case .paused(let remaining): remaining
        }
    }

    /// How much of the phase is done, from 0 to 1, for the ring.
    var progress: Double { totalSeconds > 0 ? 1 - remaining / totalSeconds : 0 }

    /// "18:42", rounded up so the last second reads 0:01 rather than 0:00.
    var remainingText: String {
        let seconds = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var todaysSessions: [FocusSession] { sessions.filter { Calendar.current.isDateInToday($0.end) } }

    /// What recent sessions were for, most recent first and each once, to pick from instead of typing.
    var recentIntents: [String] {
        var seen = Set<String>()
        return sessions.map(\.intent).filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }.prefix(6).map { $0 }
    }

    var hasExamples: Bool { sessions.contains(where: \.isExample) }

    // MARK: What the person does

    func setIntent(_ intent: String) {
        update { $0.intent = intent }
    }

    /// Starts the phase from the top, or carries on after a pause.
    func start() {
        let length = state.status == .idle ? totalSeconds : remaining
        update {
            if $0.status == .idle {
                $0.length = length
                if $0.phase == .focus { $0.startedAt = Date() }
            }
            $0.status = .running(endsAt: Date().addingTimeInterval(length))
        }
        scheduleNotification()
        startTicking()
    }

    func pause() {
        guard isRunning else { return }
        update { $0.status = .paused(remaining: remaining) }
        LampNotifications.cancel(Self.notificationID)
        stopTicking()
    }

    func toggle() { isRunning ? pause() : start() }

    /// Moves on to the next phase without counting this one: a skipped focus session isn't a finished one.
    func skip() {
        LampNotifications.cancel(Self.notificationID)
        stopTicking()
        let next: Phase = state.phase == .focus ? breakAfterFocus(counting: false) : .focus
        update {
            $0.phase = next
            $0.status = .idle
            $0.startedAt = nil
            $0.length = nil
        }
        if next.isBreak, settings.autoStartBreaks { start() }
    }

    /// Takes out the sessions written on first launch, leaving the person's own.
    func clearExamples() {
        for session in sessions where session.isExample { store.delete(session.id) }
        reloadSessions()
    }

    // MARK: Phases ending

    /// Ends the running phase at `endedAt`. `live` is false when catching up on time that passed while the app
    /// was closed: the notification already went off then, so there's no sound.
    private func finishPhase(endedAt: Date, live: Bool) {
        let finished = state.phase
        if finished == .focus {
            let minutes = Int((totalSeconds / 60).rounded())
            let start = state.startedAt ?? endedAt.addingTimeInterval(-Double(minutes * 60))
            store.put(FocusSession(start: start, end: endedAt, minutes: minutes,
                                   intent: state.intent.trimmingCharacters(in: .whitespacesAndNewlines)))
            reloadSessions()
        }
        let next: Phase = finished == .focus ? breakAfterFocus(counting: true) : .focus
        update {
            $0.phase = next
            $0.status = .idle
            $0.startedAt = nil
            $0.length = nil
        }
        if live, settings.playSound { NSSound(named: "Glass")?.play() }

        if next.isBreak, settings.autoStartBreaks {
            // The break started when the focus ended, even if the app only notices later.
            let length = totalSeconds
            let endsAt = endedAt.addingTimeInterval(length)
            update {
                $0.length = length
                $0.status = .running(endsAt: endsAt)
            }
            if endsAt > Date() { scheduleNotification() }
        }
    }

    /// Short or long, and counts the session toward the next long break when it was finished.
    private func breakAfterFocus(counting: Bool) -> Phase {
        guard counting else { return .shortBreak }
        let inARow = state.inARow + 1
        let long = inARow >= max(1, settings.longBreakEvery)
        update {
            $0.inARow = long ? 0 : inARow
            $0.countedOn = Date()
        }
        return long ? .longBreak : .shortBreak
    }

    /// Finishes whatever ended while the app was closed (a focus, then perhaps the break after it).
    private func catchUp() {
        while case .running(let endsAt) = state.status, endsAt <= Date() {
            finishPhase(endedAt: endsAt, live: false)
        }
    }

    private func tick() {
        now = Date()
        startOverOnNewDay()
        if case .running(let endsAt) = state.status, endsAt <= now {
            finishPhase(endedAt: endsAt, live: true)
            if !isRunning { stopTicking() }
        }
    }

    /// The run toward a long break belongs to one day.
    private func startOverOnNewDay() {
        if let day = state.countedOn, !Calendar.current.isDateInToday(day), state.inARow != 0 {
            update { $0.inARow = 0 }
        }
    }

    // MARK: Notifications

    /// Asks macOS to say the phase is over at the moment it ends, so it arrives even if the app is closed.
    /// The app plays its own gentle sound, so the notification is silent.
    private func scheduleNotification() {
        guard case .running(let endsAt) = state.status else { return }
        let title: String
        let body: String
        var actions: [String] = []
        if state.phase == .focus {
            let what = state.intent.trimmingCharacters(in: .whitespacesAndNewlines)
            let nextBreak = state.inARow + 1 >= settings.longBreakEvery ? settings.longBreakMinutes : settings.shortBreakMinutes
            title = what.isEmpty ? "Focus session done" : "Done: \(what)"
            body = "Nice work. Take \(nextBreak) minutes to stretch."
        } else {
            title = "Break's over"
            body = "Ready for another \(settings.focusMinutes) minutes?"
            actions = ["Start Focus"]
        }
        LampNotifications.send(title, body: body, sound: false, at: endsAt, id: Self.notificationID, actions: actions)
    }

    // MARK: Plumbing

    private func update(_ change: (inout TimerState) -> Void) {
        var next = state
        change(&next)
        guard next != state else { return }
        state = next
        LampStore.save(state, to: "timer")
    }

    private func reloadSessions() {
        sessions = store.all(orderBy: "end", descending: true)
    }

    private func startTicking() {
        guard ticker == nil else { return }
        now = Date()
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { FocusTimer.shared.tick() }
        }
        timer.tolerance = 0.1
        // .common keeps it counting while a menu is open or the panel is being dragged.
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
        now = Date()
    }
}
