import CoreGraphics

/// What Lamp has done about Reloads while the person is away (`Store.reloadIfAway`): which it pressed and are still
/// on their way in, which it pressed and didn't go in, and which apps wait on the person (a Stop, an unanswered question). Kept apart from Store so
/// each path through it can be tried on its own.
struct AwayReloads {
    /// How long the Mac has had no keyboard, mouse or trackpad input before Lamp takes it that the person has stepped
    /// away. Long enough that someone reading the chat or watching the app isn't reloaded under, short enough that an
    /// agent waiting on Reload doesn't sit there all afternoon.
    static let after: Double = 180

    /// Seconds since the person last typed, clicked or moved the pointer anywhere on this Mac, from the window server's
    /// own count: no permission is needed, and a locked screen or a sleeping display counts as no input.
    static var secondsSinceInput: Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    /// Pressed by Lamp and not in yet: a Reload put off until the agent is between steps or its turn is over is
    /// still Lamp's when it lands, and is decided on then.
    private(set) var pressing: Set<String> = []
    /// Of those, the ones whose install has begun: it clears the wait before the app has opened again and the Reload
    /// has landed, so a missing wait says nothing about these until it has.
    private(set) var installing: Set<String> = []
    /// Pressed by Lamp and still waiting after: not pressed again until the person has been back, so a Reload that
    /// can't go in isn't tried every few seconds. A later change waiting for Reload after one that went in isn't this.
    private(set) var failed: Set<String> = []
    /// The person pressed Stop, or the agent asked them a question they haven't answered: nothing of Lamp's starts
    /// the agent again, or reloads for it, until they send a request (an answer to the card is one).
    private(set) var held: Set<String> = []

    /// The apps waiting for Reload that Lamp presses it for now, marked as pressed.
    mutating func toPress(waiting: [String], idle: Double) -> [String] {
        // A press whose wait went some other way (a live change, the app closing, a crash set aside) before its
        // install began has nothing left to land: it mustn't keep the app's later held changes from being pressed.
        pressing = pressing.filter { waiting.contains($0) || installing.contains($0) }
        guard idle >= Self.after else { failed = []; return [] }
        let ids = waiting.filter { !pressing.contains($0) && !failed.contains($0) && !held.contains($0) }
        pressing.formUnion(ids)
        return ids
    }

    /// A Reload is over, whoever pressed it. True when it was Lamp's and the change went in, so the agent may be
    /// sent on (`carriesOn`).
    mutating func landed(_ id: String, stillWaits: Bool) -> Bool {
        installing.remove(id)
        guard pressing.remove(id) != nil else { return false }
        if stillWaits { failed.insert(id); return false }
        return true
    }

    /// The install of a Reload begins; it lands (`landed`) once the app has opened again.
    mutating func installs(_ id: String) { if pressing.contains(id) { installing.insert(id) } }

    /// A Reload of Lamp's put off until later is given up without landing, its wait gone another way.
    mutating func dropped(_ id: String) { pressing.remove(id); installing.remove(id) }

    /// Whether Lamp's own request to carry on may go to the agent: not once the person has stopped it, nor while a
    /// question of the agent's waits for their answer.
    func carriesOn(_ id: String) -> Bool { !held.contains(id) }

    /// The person pressed Stop. True when a Reload of Lamp's was still on its way, which is then given up: they're
    /// at the Mac, and the Reload is theirs again.
    mutating func personStopped(_ id: String) -> Bool {
        held.insert(id)
        installing.remove(id)
        return pressing.remove(id) != nil
    }

    /// The agent put a question to the person: until they answer, the turn is theirs to carry on.
    mutating func questionAsked(_ id: String) { held.insert(id) }

    /// The person sent a request: what they stopped, or what waited for their answer, may be carried on again.
    mutating func personAsked(_ id: String) { held.remove(id) }
}
