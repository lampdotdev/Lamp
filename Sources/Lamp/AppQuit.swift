import AppKit

/// Asking one of the person's apps to quit, and taking its answer.
///
/// An app may ask about unsaved work before it quits, and the person may answer that it should stay open.
/// macOS carries the answer back on the quit request itself: the request is answered when the app has decided,
/// with "cancelled" when it stays open, and isn't answered at all while the question is still on screen. So
/// Lamp sends the request itself and reads the reply, where `NSRunningApplication.terminate()` throws it away.
/// Nothing here ends an app that hasn't agreed to go: it might be asking, or saving. One that doesn't answer
/// at all looks the same from outside whether it is stuck or in the middle of a long save, so Lamp says it
/// isn't responding and leaves ending it to the person, who can do it there with one click.
enum AppQuit {
    /// The app's answer to the request.
    enum Reply: Equatable { case agreed, refused }

    enum Step: Equatable {
        /// Nothing to do yet: the app is deciding, or the person is.
        case wait
        /// The app said it would quit and hasn't: end it.
        case force
        /// It has quit.
        case closed
        /// It stays open, by the person's choice.
        case kept
    }

    /// How long an app that agreed to quit gets to finish closing.
    static let closing: TimeInterval = 5
    /// How many of Lamp's "still there?", a second apart, an app that says it answers them may miss before
    /// Lamp says it isn't responding. Counted in questions, not seconds: a Mac that slept, or a Lamp that was
    /// held up, asked nothing meanwhile.
    static let patience = 10
    /// How long a request goes unanswered before Lamp takes it that the app is asking the person something.
    static let asking: TimeInterval = 2

    /// What to do about an app that was asked to quit. `sinceReply`: how long ago it answered.
    /// Without an answer there is only waiting, however long: no silence is taken for the app being stuck.
    static func step(terminated: Bool, reply: Reply?, sinceReply: TimeInterval) -> Step {
        if terminated { return .closed }
        switch reply {
        case .refused: return .kept
        case .agreed: return sinceReply > closing ? .force : .wait
        case nil: return .wait
        }
    }

    /// The reply an answered request carries: its error number, absent when there was no error.
    /// "Cancelled by the user" is the app staying open, no error is the app going, and any other error says
    /// nothing about what the app will do, so it's no answer.
    static func reply(errorNumber: Int32?) -> Reply? {
        switch errorNumber {
        case nil, 0: .agreed
        case Int32(userCanceledErr): .refused
        default: nil
        }
    }

    /// Whether this copy of the app answers "still there?": it leaves its process id in its runtime folder
    /// once it listens (LampRuntime in LampSupport.swift). An app built before that, or one that never got as
    /// far as listening, is never taken for stuck.
    static func listens(_ pid: pid_t, runtime: URL) -> Bool {
        let said = try? String(contentsOf: runtime.appendingPathComponent(listeningFile), encoding: .utf8)
        return said?.trimmingCharacters(in: .whitespacesAndNewlines) == String(pid)
    }

    static let listeningFile = "listening"

    /// One quit request to one app, sent on a thread of its own: the send returns only when the app answers,
    /// which may be as long as the person takes.
    final class Request: @unchecked Sendable {
        private let lock = NSLock()
        private var answer: (reply: Reply?, at: Date)?

        /// The app's answer and when it came; nil until there is one. A request that couldn't be sent, or
        /// came back without an answer, has no reply: the app is then asked the ordinary way, and waited for.
        var answered: (reply: Reply?, at: Date)? { lock.withLock { answer } }

        /// The request an app hasn't answered yet, by process: an app asked again while its question is up
        /// (a turn that was stopped, then the next build) isn't sent a second request on top of the first.
        @MainActor private static var waiting: [pid_t: Request] = [:]

        /// Whether the app has a request it hasn't answered: it was answering Lamp when that was sent.
        @MainActor static func isWaiting(_ pid: pid_t) -> Bool { waiting[pid].map { $0.answered == nil } ?? false }

        @MainActor static func to(_ app: NSRunningApplication) -> Request {
            let pid = app.processIdentifier
            if let request = waiting[pid], request.answered == nil { return request }
            let request = Request(app)
            waiting = waiting.filter { $0.value.answered == nil }
            waiting[pid] = request
            return request
        }

        private init(_ app: NSRunningApplication) {
            let pid = app.processIdentifier
            Thread.detachNewThread { [self] in
                let event = NSAppleEventDescriptor(
                    eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEQuitApplication),
                    targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
                    returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
                var reply: Reply?
                do {
                    let answer = try event.sendEvent(options: [.waitForReply], timeout: TimeInterval(kNoTimeOut))
                    reply = AppQuit.reply(errorNumber: answer.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value)
                } catch {
                    if (error as NSError).code == userCanceledErr { reply = .refused }
                }
                lock.withLock { answer = (reply, Date()) }
            }
        }
    }

    /// Asks the app "still there?" and keeps when it last answered.
    final class Pulse: @unchecked Sendable {
        private final class Heard: @unchecked Sendable {
            private let lock = NSLock()
            private var ever = false, missed = 0
            var state: (ever: Bool, missed: Int) { lock.withLock { (ever, missed) } }
            func answered() { lock.withLock { ever = true; missed = 0 } }
            func asked() { lock.withLock { missed += 1 } }
        }

        private let heard = Heard()
        private let observer: NSObjectProtocol
        private let question: Notification.Name

        init(app id: String, pid: pid_t) {
            question = Notification.Name(Edition.notificationPrefix + "stillThere.\(id)")
            observer = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(Edition.notificationPrefix + "here.\(id)"), object: String(pid), queue: nil) { [heard] _ in heard.answered() }
        }

        deinit { DistributedNotificationCenter.default().removeObserver(observer) }

        /// Whether it has answered at all, and how many questions in a row it hasn't, the one just asked aside.
        var state: (heard: Bool, missed: Int) {
            let state = heard.state
            return (state.ever, max(0, state.missed - 1))
        }

        func ask() {
            heard.asked()
            DistributedNotificationCenter.default().postNotificationName(question, object: nil, userInfo: nil, deliverImmediately: true)
        }
    }

    /// Asks the app to quit and waits for it to go, however long the person takes over its question. False
    /// when it stays open: the person cancelled, or `stopped` says nobody is waiting any more.
    /// `asking` is called once, when the app seems to have a question up. `silent(true)` is called instead
    /// when a copy that answers Lamp (`listens`) didn't, before it was asked to quit: it's stuck, or busy with
    /// something long. It is asked all the same, and waited for; `silent(false)` follows if it answers after
    /// all, and whenever the wait ends.
    @MainActor
    static func close(_ app: NSRunningApplication, id: String, runtime: URL, stopped: () -> Bool = { false },
                      asking: () -> Void = {}, silent: (Bool) -> Void = { _ in }) async -> Bool {
        guard !app.isTerminated else { return true }
        let pid = app.processIdentifier
        var quiet = false, pulse: Pulse?, lastPulse = Date.distantPast
        defer { if quiet { silent(false) } }
        // Asked "still there?" before it's asked to quit: afterwards an app with a question up, or saving
        // on the answer, is quiet too, and that says nothing.
        if listens(pid, runtime: runtime), !Request.isWaiting(pid) {
            let asked = Pulse(app: id, pid: pid)
            pulse = asked
            while !asked.state.heard, !quiet {
                if app.isTerminated { return true }
                if stopped() { return false }
                if asked.state.missed > patience {
                    quiet = true
                    silent(true)
                } else if Date().timeIntervalSince(lastPulse) >= 1 {
                    lastPulse = Date()
                    asked.ask()
                }
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        let request = Request.to(app)
        let began = Date()
        var askedPlainly = false, told = false
        while true {
            let answered = request.answered
            // The request never reached the app as sent: asked the ordinary way, its answer can't be read,
            // so it's waited for like one that is still asking.
            if let answered, answered.reply == nil, !askedPlainly {
                askedPlainly = true
                app.terminate()
            }
            switch step(terminated: app.isTerminated, reply: answered?.reply,
                        sinceReply: answered.map { Date().timeIntervalSince($0.at) } ?? 0) {
            case .closed: return true
            case .kept: return false
            case .force: return await end(app)
            case .wait: break
            }
            if stopped() { return false }
            // Still asked while it's quiet, so Lamp stops saying it isn't responding once it is.
            if quiet, let pulse {
                if pulse.state.heard {
                    quiet = false
                    silent(false)
                } else if Date().timeIntervalSince(lastPulse) >= 1 {
                    lastPulse = Date()
                    pulse.ask()
                }
            }
            if !told, !quiet, answered?.reply == nil, Date().timeIntervalSince(began) > Self.asking {
                told = true
                asking()
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    @MainActor private static func end(_ app: NSRunningApplication) async -> Bool {
        app.forceTerminate()
        for _ in 0..<30 where !app.isTerminated { try? await Task.sleep(for: .milliseconds(100)) }
        return app.isTerminated
    }
}
