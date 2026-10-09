import AppKit
import SwiftUI

/// The question before an app clicks, types or presses keys in another app, asked beside the spot it's
/// about rather than in Lamp's window: Lamp is usually behind, and a sheet there is easy to miss and reads
/// as Lamp's own business.
///
/// It floats over every app and Space without bringing Lamp forward, and doesn't take the keyboard, so a
/// Return meant for the app the person is typing in can't approve anything. For the same reason it never
/// opens under the pointer, and its buttons wait a moment before they take a click.
@MainActor
enum ApprovalPanel {
    /// `stop` ends the whole task, not just this step.
    enum Answer { case allow, allowAll, deny, stop }

    /// What's asked, and where on screen it's about (the drivers' space: points, top-left origin).
    struct Request {
        let asker: String
        let askerIcon: NSImage
        let target: String
        let targetIcon: NSImage?
        let details: String
        let intent: String?
        let point: CGPoint?
        let window: CGRect?
        /// The task asking, so stopping it elsewhere (the stop control on the glow) closes its question.
        var owner: ObjectIdentifier? = nil

        var title: String { "\(asker) wants to use \(target)" }
    }

    /// Questions still waiting, by the task that asked, each with the way to answer it.
    private static var waiting: [ObjectIdentifier: [UUID: (Answer) -> Void]] = [:]

    /// The task was stopped some other way: its open questions close, answered Stop.
    static func dismiss(owner: ObjectIdentifier) {
        for finish in (waiting.removeValue(forKey: owner) ?? [:]).values { finish(.stop) }
    }

    static func ask(_ request: Request) async -> Answer {
        await withCheckedContinuation { continuation in
            let panel = NonKeyPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
            var answered = false
            let id = UUID()
            let finish: (Answer) -> Void = { answer in
                guard !answered else { return }
                answered = true
                if let owner = request.owner { waiting[owner]?[id] = nil }
                NSAnimationContext.runAnimationGroup({ $0.duration = 0.15; panel.animator().alphaValue = 0 },
                                                     completionHandler: { panel.orderOut(nil) })
                continuation.resume(returning: answer)
            }
            if let owner = request.owner { waiting[owner, default: [:]][id] = finish }
            let view = ApprovalView(request: request, answer: finish)
            let host = FirstClickHost(rootView: view)
            host.frame.size = host.fittingSize
            panel.contentView = host
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .statusBar + 1   // above Lamp's own cursor
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.setFrame(frame(for: host.fittingSize, near: request), display: true)
            panel.alphaValue = 0
            // A dialog to VoiceOver, named by its question, and said aloud as it appears: it doesn't take
            // the keyboard, so VoiceOver wouldn't otherwise move to it.
            panel.setAccessibilityRole(.window)
            panel.setAccessibilitySubrole(.dialog)
            panel.setAccessibilityTitle(request.title)
            panel.orderFrontRegardless()
            NSAccessibility.post(element: panel, notification: .announcementRequested, userInfo: [
                .announcement: "\(request.title). \(request.details)",
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
            NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 1 }
        }
    }

    /// Beside the spot (right of it, else left), else beside the window, else at the top of the screen;
    /// always on screen, never over the spot itself or under the pointer.
    private static func frame(for size: CGSize, near request: Request) -> CGRect {
        let gap: CGFloat = 28
        let screen = (NSScreen.screens.first { screen in
            request.point.map { screen.frame.contains(ComputerOverlay.cocoa($0)) }
                ?? request.window.map { screen.frame.intersects(ComputerOverlay.cocoa($0)) } ?? false
        } ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        var candidates: [CGRect] = []
        if let point = request.point.map(ComputerOverlay.cocoa) {
            candidates.append(CGRect(x: point.x + gap, y: point.y - size.height / 2, width: size.width, height: size.height))
            candidates.append(CGRect(x: point.x - gap - size.width, y: point.y - size.height / 2, width: size.width, height: size.height))
            candidates.append(CGRect(x: point.x - size.width / 2, y: point.y - gap - size.height, width: size.width, height: size.height))
            candidates.append(CGRect(x: point.x - size.width / 2, y: point.y + gap, width: size.width, height: size.height))
        }
        if let window = request.window.map(ComputerOverlay.cocoa) {
            candidates.append(CGRect(x: window.maxX + gap, y: window.maxY - size.height, width: size.width, height: size.height))
            candidates.append(CGRect(x: window.minX - gap - size.width, y: window.maxY - size.height, width: size.width, height: size.height))
            candidates.append(CGRect(x: window.maxX - size.width - gap, y: window.maxY - size.height - 52, width: size.width, height: size.height))
        }
        candidates.append(CGRect(x: screen.midX - size.width / 2, y: screen.maxY - size.height - 40, width: size.width, height: size.height))
        let mouse = NSEvent.mouseLocation
        let spot = request.point.map { ComputerOverlay.cocoa($0) }
        func clamped(_ rect: CGRect) -> CGRect {
            var rect = rect
            rect.origin.x = min(max(rect.minX, screen.minX + 8), screen.maxX - rect.width - 8)
            rect.origin.y = min(max(rect.minY, screen.minY + 8), screen.maxY - rect.height - 8)
            return rect
        }
        let fits = candidates.first { rect in
            screen.contains(rect) && !rect.insetBy(dx: -8, dy: -8).contains(mouse) && !(spot.map { rect.insetBy(dx: -12, dy: -12).contains($0) } ?? false)
        }
        if let fits { return fits }
        // Nothing fits as is: the first choice pulled onto the screen, moved off the pointer if it's there.
        var rect = clamped(candidates[0])
        if rect.insetBy(dx: -8, dy: -8).contains(mouse) {
            rect.origin.y = mouse.y - rect.height - 24 >= screen.minY ? mouse.y - rect.height - 24 : mouse.y + 24
            rect = clamped(rect)
        }
        return rect
    }

}

/// Takes the click that lands on it even though its panel never becomes key: otherwise the first click
/// would only try to focus it, and nothing would happen.
final class FirstClickHost<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A borderless panel that can be clicked without making Lamp the active app or taking the keyboard.
final class NonKeyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct ApprovalView: View {
    let request: ApprovalPanel.Request
    let answer: (ApprovalPanel.Answer) -> Void
    /// Buttons take clicks only after this, so a click already on its way to another app can't land here.
    @State private var ready = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                // The icons repeat the title's two names, so VoiceOver skips them.
                HStack(spacing: 10) {
                    Image(nsImage: request.askerIcon).resizable().frame(width: 32, height: 32)
                    if let icon = request.targetIcon {
                        Image(systemName: "arrow.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Image(nsImage: icon).resizable().frame(width: 32, height: 32)
                    }
                }
                .accessibilityHidden(true)
                Text(request.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                    .accessibilityAddTraits(.isHeader)
                Button("Stop Task") { answer(.stop) }
                    .controlSize(.small)
                    .disabled(!ready)
                    .accessibilityHint("Ends the whole task. Nothing more is done in \(request.target).")
            }
            Text(request.details)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let intent = request.intent, !intent.isEmpty {
                Text("The AI says it's doing this to: \(intent)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Don't Allow") { answer(.deny) }
                Spacer()
                Button("Allow All for This Task") { answer(.allowAll) }
                Button("Allow") { answer(.allow) }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(nsColor: ComputerOverlay.tint))
            }
            .disabled(!ready)
            .controlSize(.large)
        }
        .padding(16)
        .frame(width: 420, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(request.title)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color(nsColor: ComputerOverlay.tint).opacity(0.6), lineWidth: 1))
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            ready = true
        }
    }
}
