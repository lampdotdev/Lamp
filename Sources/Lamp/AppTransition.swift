import AppKit
import CryptoKit
import SwiftUI

/// The open app's windows glow at their edges while Lamp builds a change for it, and a band of light crosses them
/// as it goes in (`LampTransition` in LampSupport.swift, which draws it). Lamp is the only one who asks: each
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
        project.platform.hasMac && !project.onIOS && !Template.isWidgetOnly(project)
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

/// Lamp's own copy of the glow, on the picture it shows where the window was while the app reopens for a change
/// (`CoverView`), so the glow carries on across the reopen: only blur coming in from the edge, its colour going
/// round blue, purple and orange as the app's does. It doesn't breathe where the person asked for less motion.
struct TransitionGlow: View {
    var cornerRadius: CGFloat = 12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let hues: [NSColor] = [.systemBlue, .systemPurple, .systemOrange]
    private static let cycle = 6.0

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let color = Self.color(at: time)
            // As faint as the app's own (`LampTransition.Glass.strength`), so it never stands in the way.
            let breath = 0.3 * (reduceMotion ? 0.8 : 0.725 + 0.275 * cos(time * .pi / 1.2))
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            ZStack {
                shape.stroke(color.opacity(0.9), lineWidth: 60).blur(radius: 50)
                shape.stroke(color, lineWidth: 30).blur(radius: 24)
            }
            .clipShape(shape)
            .opacity(breath)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Where in the round of colours the glow is at a moment, blended between the two either side.
    private static func color(at time: TimeInterval) -> Color {
        let position = (time / cycle).truncatingRemainder(dividingBy: 1) * Double(hues.count)
        let index = Int(position) % hues.count
        let next = hues[(index + 1) % hues.count]
        return Color(nsColor: hues[index].blended(withFraction: position - Double(Int(position)), of: next) ?? hues[index])
    }
}
