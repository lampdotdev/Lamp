import AppKit
import CryptoKit
import SwiftUI

/// Smoke curls up from the bottom of the open app's windows while Lamp builds a change for it, and a band of white
/// whooshes up across them as it goes in (`LampTransition` in LampSupport.swift, which draws it). Lamp is the only one who asks: each
/// request is signed with the app's token, over its phase, an id and the time, so no other process can start it
/// or play one again, and the app's own code has no way to.
///
/// An app built before the effect existed doesn't have the marker in its binary and is sent nothing. It catches up
/// at its next change: a change to Lamp's own building blocks can't go into an open app, so it reopens with them.
@MainActor
enum AppTransition {
    enum Phase: String { case begin, land, end }

    /// A line every app that understands the request has in its binary.
    static let marker = "lampTransitionSignature"

    /// The apps glowing now, each with the task that renews its glow while Lamp still has work for it: the app
    /// lets the glow go by itself if it isn't renewed, so it never outlives a Lamp that quit or a turn that ended.
    private static var glowing: [String: Task<Void, Never>] = [:]
    private static let renewEvery: Duration = .seconds(30)

    static func signature(phase: String, id: String, at: String, token: String) -> String {
        HMAC<SHA256>.authenticationCode(for: Data("transition\n\(id)\n\(phase)\n\(at)".utf8), using: SymmetricKey(data: Data(token.utf8)))
            .map { String(format: "%02x", $0) }.joined()
    }

    /// Whether the app is open on this Mac, with a window to show it on, and understands the request.
    static func canShow(_ project: LampProject) -> Bool {
        project.hasMac && !project.onIOS && !Template.isWidgetOnly(project)
            && !Store.shared.macCopies(of: project).isEmpty && Store.binary(of: project, contains: marker)
    }

    /// A build for the open app begins. Not while it holds a change for Reload: what it shows isn't getting this one.
    /// True when the app was asked to glow.
    @discardableResult
    static func begin(_ project: LampProject) -> Bool {
        guard !Runtime.holdsBuild(project), canShow(project) else { return false }
        send(.begin, to: project)
        glowing[project.id]?.cancel()
        let id = project.id
        glowing[id] = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: renewEvery)
                guard !Task.isCancelled, glowing[id] != nil,
                      let current = Store.shared.projects.first(where: { $0.id == id }) else { return }
                guard Store.shared.busy.contains(id) else { return end(current) }
                send(.begin, to: current)
            }
        }
        return true
    }

    /// The change is in the open app: the light crosses it. Also for a copy just opened with the change, which
    /// never saw the glow begin (`always`).
    static func land(_ project: LampProject, always: Bool = false) {
        guard stop(project) || always, canShow(project) else { return }
        send(.land, to: project)
    }

    /// The app glowed and was reopened with the change: the new copy shows the light crossing it once its first
    /// window is on screen, whether or not Lamp's cover stood in for it (there's none for a window in full screen
    /// or in the Dock). The window server is asked rather than the app, which doesn't say for every window.
    static func landWhenShown(_ project: LampProject, app: NSRunningApplication) {
        let pid = app.processIdentifier
        Task { @MainActor in
            for _ in 0..<60 {
                guard !app.isTerminated else { return }
                let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
                if windows.contains(where: { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
                    && ($0[kCGWindowIsOnscreen as String] as? Bool) == true }) {
                    // A moment for the window to settle, and for Lamp's cover over it to start fading.
                    try? await Task.sleep(for: .milliseconds(600))
                    guard !app.isTerminated, let current = Store.shared.projects.first(where: { $0.id == project.id }) else { return }
                    return land(current, always: true)
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    static func isGlowing(_ id: String) -> Bool { glowing[id] != nil }

    /// The build failed, was stopped, or its change waits for the person: the glow fades with nothing crossing.
    static func end(_ project: LampProject) {
        guard stop(project) else { return }
        send(.end, to: project)
    }

    @discardableResult
    private static func stop(_ project: LampProject) -> Bool {
        guard let task = glowing.removeValue(forKey: project.id) else { return false }
        task.cancel()
        return true
    }

    /// Distributed notifications reach every process, so the token never travels: only its signature does.
    static func send(_ phase: Phase, to project: LampProject) {
        let id = UUID().uuidString
        let at = String(Int(Date().timeIntervalSince1970))
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(Edition.notificationPrefix + "transition.\(project.id)"), object: nil,
            userInfo: ["phase": phase.rawValue, "id": id, "at": at,
                       marker: signature(phase: phase.rawValue, id: id, at: at, token: Template.token(for: project))],
            deliverImmediately: true)
    }
}

/// The same light around a wish's icon on the desk while it's built: just outside the icon, its colours travelling
/// round it, bright enough to see at a glance across the desk, since a wish that looks still looks stuck. Where the
/// person asked for less motion it stays still. The desk fades it out when the build is done.
struct BuildingGlow: View {
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let lap = 3.0

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let light = Self.light(at: timeline.date, still: reduceMotion)
            // The icon's own tile, an 824pt square on its 1024pt canvas, so the light hugs its edge.
            let side = size * 824 / 1024
            let shape = RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
            ZStack {
                shape.stroke(light, lineWidth: side * 0.24).blur(radius: side * 0.15)
                shape.stroke(light, lineWidth: side * 0.09).blur(radius: side * 0.05)
                // A crisp rim at the icon's edge, which is what the eye catches from across the window.
                shape.stroke(light, lineWidth: 2.5).blur(radius: 0.6)
            }
            .frame(width: side, height: side)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The light where it is at a moment.
    private static func light(at date: Date, still: Bool) -> AngularGradient {
        let turn = still ? 0 : (date.timeIntervalSinceReferenceDate / lap).truncatingRemainder(dividingBy: 1)
        let colors = [NSColor.systemBlue, .systemPurple, .systemOrange].map(Color.init(nsColor:))
        return AngularGradient(colors: colors + [colors[0]], center: .center, angle: .degrees(turn * 360))
    }
}
