import CoreGraphics

/// What Lamp has done about Reloads while the person is away (`Store.reloadIfAway`): which it pressed and are still
/// on their way in, which it pressed and didn't go in, and which apps the person stopped. Kept apart from Store so
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
    /// Pressed by Lamp and still waiting after: not pressed again until the person has been back, so a Reload that
    /// can't go in isn't tried every few seconds. A later change waiting for Reload after one that went in isn't this.
    private(set) var failed: Set<String> = []
    /// The person pressed Stop: nothing of Lamp's starts the agent again, or reloads for it, until they send a request.
    private(set) var stopped: Set<String> = []

    /// The apps waiting for Reload that Lamp presses it for now, marked as pressed.
    mutating func toPress(waiting: [String], idle: Double) -> [String] {
        guard idle >= Self.after else { failed = []; return [] }
        let ids = waiting.filter { !pressing.contains($0) && !failed.contains($0) && !stopped.contains($0) }
        pressing.formUnion(ids)
        return ids
    }

    /// A Reload is over, whoever pressed it. True when it was Lamp's and the change went in, so the agent may be
    /// sent on (`carriesOn`).
    mutating func landed(_ id: String, stillWaits: Bool) -> Bool {
        guard pressing.remove(id) != nil else { return false }
        if stillWaits { failed.insert(id); return false }
        return true
    }

    /// Whether Lamp's own request to carry on may go to the agent: not once the person has stopped it.
    func carriesOn(_ id: String) -> Bool { !stopped.contains(id) }

    /// The person pressed Stop. True when a Reload of Lamp's was still on its way, which is then given up: they're
    /// at the Mac, and the Reload is theirs again.
    mutating func personStopped(_ id: String) -> Bool {
        stopped.insert(id)
        return pressing.remove(id) != nil
    }

    /// The person sent a request: what they stopped may be carried on again.
    mutating func personAsked(_ id: String) { stopped.remove(id) }
}
