import AppKit

/// Lamp trying the app it's working on (`use_app`), in plain sight, and the person's way to take it back.
///
/// While the agent's actions run, the window in use glows, Lamp's cursor (a fingertip over an iPhone's screen)
/// goes to each spot before anything happens there, with a word on what it's doing, and a pill above the window
/// says Lamp is trying it, with Stop and Esc. The person takes the app back with either, or just by clicking or
/// typing in it themselves: the rest of the actions are dropped, and the agent is told they took over and
/// doesn't try the app again until their next message (`Store.Turn.tookOver`). A Mac app notices the person's
/// own clicks and keys itself (`LampDriver.Handover` in LampSupport.swift); the simulator's are watched for here.
@MainActor
final class Handover {
    /// Set on the events Lamp posts to the simulator itself, so its own taps and keys aren't taken for the person's.
    nonisolated static let mark: Int64 = 0x4C41_4D50

    private(set) var tookOver = false
    /// The actions are over: a step heard late doesn't bring the cursor back.
    private var ended = false
    private let label: String
    private let finger: Bool
    /// The Simulator's process, whose window the person's own clicks and keys are watched in. Nil for a Mac app.
    private let simulator: pid_t?
    /// A window of Lamp's own the app is shown in (the TV preview): every click and key in it is the person's, since
    /// Lamp acts on the page inside without posting events.
    private weak var lampWindow: NSWindow?
    /// What else taking over does: a Mac app is told to drop the rest of its actions.
    private let halt: () -> Void
    private var window: CGWindowID?
    private var monitors: [Any] = []
    private var overlay: ComputerOverlay { .shared }
    private var owner: ObjectIdentifier { ObjectIdentifier(self) }

    /// From now on the person's Esc, or their own press in the simulator, takes the app back: even before any
    /// window is known (a batch that waits before opening a menu bar icon's panel), so that Esc isn't ignored.
    init(label: String, finger: Bool = false, simulator: pid_t? = nil, lampWindow: NSWindow? = nil, halt: @escaping () -> Void = {}) {
        self.label = label
        self.finger = finger
        self.simulator = simulator
        self.lampWindow = lampWindow
        self.halt = halt
        listen()
    }

    /// The glow and the pill on the window being used, with Stop on it.
    func show(window id: CGWindowID) {
        guard !tookOver, !ended, id != window else { return }
        window = id
        overlay.focus(window: id, label: label, owner: owner, escape: true) { [weak self] in self?.take() }
    }

    /// Lamp's cursor goes to where the next action happens, and presses there when it's a click or a tap. `due`
    /// is how long until the action happens there (a Mac app says, having sent the spot ahead during the pause
    /// before it): the glide is paced to arrive a hair before, and the press shows then, not on arrival.
    func aim(at point: CGPoint, doing: String?, press: Bool, due: Double? = nil) async {
        guard !tookOver, !ended else { return }
        let start = ContinuousClock.now
        let arrival = due.map { max(0.1, $0 - 0.05) }
        await overlay.move(to: point, app: nil, owner: owner, caption: doing.map { "Lamp · " + $0 }, finger: finger, within: arrival)
        if let arrival { try? await Task.sleep(until: start + .seconds(arrival), clock: .continuous) }
        if press, !tookOver, !ended { overlay.click(at: point, owner: owner) }
    }

    /// The person took the app back.
    func take() {
        guard !tookOver, !ended else { return }
        tookOver = true
        stopListening()
        halt()
        overlay.handBack(owner: owner, saying: "You have the app. Lamp stopped trying it.")
    }

    /// The actions are over: the glow, the cursor and the pill fade, unless the person took over (they're gone already).
    func end() {
        guard !ended else { return }
        ended = true
        stopListening()
        if !tookOver { overlay.end(owner: owner) }
    }

    private func listen() {
        guard monitors.isEmpty else { return }
        // Esc while Lamp is in front: the person may be watching from the chat.
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return event }
            let taken = MainActor.assumeIsolated { () -> Bool in
                guard let self, !self.tookOver else { return false }
                self.take()
                return true
            }
            return taken ? nil : event
        }) { monitors.append(local) }
        if lampWindow != nil, let own = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let window = self.lampWindow, event.window === window, !self.tookOver else { return }
                self.take()
            }
            return event
        }) { monitors.append(own) }
        guard let simulator else { return }
        // A click or a key of the person's own in the simulator's window. Seeing other apps' events takes the
        // permission to control the computer, which driving the simulator needs anyway.
        let watched: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: watched, handler: { [weak self] event in
            let mark = event.cgEvent?.getIntegerValueField(.eventSourceUserData) ?? 0
            let key = event.type == .keyDown
            let pointer = NSEvent.mouseLocation
            let location = ComputerOverlay.drivers(pointer)
            MainActor.assumeIsolated {
                guard let self, let window = self.window, !self.tookOver else { return }
                let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
                let under = key ? nil : Self.owner(at: pointer)
                if Self.isPersons(key: key, mark: mark, at: location, frontmost: front, window: ComputerOverlay.frame(of: window), under: under, of: simulator) {
                    self.take()
                }
            }
        }) { monitors.append(global) }
    }

    private func stopListening() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    /// Whether a press seen in another app is the person's own in the simulator: not one Lamp posted, and a click
    /// inside its window that landed on it (`under`, the app whose window is on top there: another app's window
    /// over the simulator takes the click itself), or a key while it's the app in front (keys go to the front app
    /// wherever the pointer is).
    nonisolated static func isPersons(key: Bool, mark: Int64, at location: CGPoint, frontmost: pid_t?, window: CGRect?, under: pid_t?, of simulator: pid_t) -> Bool {
        guard mark != Self.mark else { return false }
        if key { return frontmost == simulator }
        return under == simulator && window?.contains(location) == true
    }

    /// The app whose window a click at a point (AppKit's coordinates) reaches: the window server's own answer,
    /// which passes over windows that take no clicks (Lamp's glow and cursor over the simulator, other apps'
    /// overlays), where the window list would give the first window there, seen or not.
    static func owner(at point: CGPoint) -> pid_t? {
        let id = NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
        guard id > 0, let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(id)) as? [[String: Any]])?.first else { return nil }
        return info[kCGWindowOwnerPID as String] as? pid_t
    }

    /// The front window of an app on screen, in the order the window server stacks them: the first with a title,
    /// since the app's chat beside its window is a panel of the app's own, in front of it and with none.
    nonisolated static func frontWindow(of pid: pid_t, containing point: CGPoint? = nil) -> CGWindowID? {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var untitled: CGWindowID?
        for info in windows where (info[kCGWindowOwnerPID as String] as? pid_t) == pid && (info[kCGWindowLayer as String] as? Int) == 0 {
            guard let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary), rect.width > 40, rect.height > 40,
                  point.map(rect.contains) ?? true,
                  let id = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            if (info[kCGWindowName as String] as? String)?.isEmpty == false { return id }
            untitled = untitled ?? id
        }
        return untitled
    }
}
