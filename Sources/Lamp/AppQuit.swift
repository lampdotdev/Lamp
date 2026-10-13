import AppKit

/// Asking one of the person's apps to quit, and taking its answer.
///
/// An app may ask about unsaved work before it quits, and the person may answer that it should stay open.
/// macOS carries the answer back on the quit request itself: the request is answered when the app has decided,
/// with "cancelled" when it stays open, and isn't answered at all while the question is still on screen. So
/// Lamp sends the request itself and reads the reply, where `NSRunningApplication.terminate()` throws it away.
/// Nothing here ends an app that might still be asking, or saving because of the answer: only one that agreed
/// to quit and then didn't, or one whose main thread is stuck, which is found out before it is asked to quit
/// at all, so it has no question up and no answer to act on.
enum AppQuit {
    /// The app's answer to the request.
    enum Reply: Equatable { case agreed, refused }

    enum Step: Equatable {
        /// Nothing to do yet: the app is deciding, or the person is.
        case wait
        /// The app won't close by itself and isn't waiting on anyone: end it.
        case force
        /// It has quit.
        case closed
        /// It stays open, by the person's choice.
        case kept
    }

    /// How long an app that agreed to quit gets to finish closing.
    static let closing: TimeInterval = 5
    /// How many of Lamp's "still there?", a second apart, an app that says it answers them may miss before it's
    /// taken for stuck. Counted in questions, not seconds: a Mac that slept, or a Lamp that was held up, asked
    /// nothing meanwhile. More than macOS takes to call an app unresponsive, when it can't be saved from either.
    static let patience = 10
    /// How long a request goes unanswered before Lamp takes it that the app is asking the person something.
    static let asking: TimeInterval = 2

    /// What to do about an app that is to quit.
    /// `sinceReply`: how long ago it answered the request. `missed`: how many "still there?" in a row it left
    /// unanswered before it was asked to quit; none once it has been asked, since the questions stop there.
    ///
    /// An app that says it answers Lamp (`listens`) is asked to quit only once it has answered: from then on
    /// it has the request, and if it goes quiet it may be saving, on the person's answer or before it asks,
    /// for as long as that takes. So after the request nothing but the app's own reply ends the wait.
    static func step(terminated: Bool, reply: Reply?, sinceReply: TimeInterval, missed: Int) -> Step {
        if terminated { return .closed }
        switch reply {
        case .refused: return .kept
        case .agreed: return sinceReply > closing ? .force : .wait
        case nil: return missed > patience ? .force : .wait
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
    /// `asking` is called once, when the app seems to have a question up.
    @MainActor
    static func close(_ app: NSRunningApplication, id: String, runtime: URL,
                      stopped: () -> Bool = { false }, asking: () -> Void = {}) async -> Bool {
        guard !app.isTerminated else { return true }
        let pid = app.processIdentifier
        // A copy that answers Lamp is asked to quit only after it has answered. One that doesn't answer was
        // stuck before anything was asked of it; one that does is never ended for going quiet afterwards.
        if listens(pid, runtime: runtime), !Request.isWaiting(pid) {
            let pulse = Pulse(app: id, pid: pid)
            var lastPulse = Date.distantPast
            while !pulse.state.heard {
                switch step(terminated: app.isTerminated, reply: nil, sinceReply: 0, missed: pulse.state.missed) {
                case .closed: return true
                case .force: return await end(app)
                case .kept, .wait: break
                }
                if stopped() { return false }
                if Date().timeIntervalSince(lastPulse) >= 1 {
                    lastPulse = Date()
                    pulse.ask()
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
                        sinceReply: answered.map { Date().timeIntervalSince($0.at) } ?? 0, missed: 0) {
            case .closed: return true
            case .kept: return false
            case .force: return await end(app)
            case .wait: break
            }
            if stopped() { return false }
            if !told, answered?.reply == nil, Date().timeIntervalSince(began) > Self.asking {
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
