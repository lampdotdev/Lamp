import AppKit
import SwiftUI
import LampSidebarKit

/// Lamp's device card (`device_permission`) on its own, for a wish Claude Code works on from a terminal: the chat that
/// would hold it is closed while the session has the wish, so the card floats by itself and goes once it's answered.
///
/// It doesn't bring Lamp forward or take the keyboard, and no option is the default, so a Return typed in the terminal
/// can't allow a device: only a click on the card answers it.
@MainActor
final class DeviceCardPanel: NSObject, NSWindowDelegate {
    static let shared = DeviceCardPanel()

    private var window: NSPanel?
    private var wish: String?
    private var answered: ((String?) -> Void)?

    /// Shows the card and returns the option clicked, or nil when it was closed unanswered or the session ended.
    func ask(_ ask: Talk.Ask, for wish: LampProject) async -> String? {
        dismiss()
        return await withCheckedContinuation { continuation in
            self.wish = wish.id
            answered = { continuation.resume(returning: $0) }
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
                                styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.delegate = self
            panel.contentView = NSHostingView(rootView: DeviceCardView(ask: ask, app: wish.name) { [weak self] in self?.finish($0) })
            window = panel
            panel.center()
            panel.orderFrontRegardless()
        }
    }

    /// The session of `wish` ended (or any, when nil): its card goes, unanswered.
    func dismiss(wish id: String? = nil) {
        guard id == nil || id == wish else { return }
        finish(nil)
    }

    private func finish(_ choice: String?) {
        let answer = answered
        answered = nil
        wish = nil
        if let window {
            self.window = nil
            window.delegate = nil
            window.close()
        }
        answer?(choice)
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === window { finish(nil) }
    }
}

private struct DeviceCardView: View {
    let ask: Talk.Ask
    let app: String
    let choose: (String) -> Void

    var body: some View {
        let question = ask.questions.first
        VStack(alignment: .leading, spacing: 14) {
            Text(app).font(.caption).foregroundStyle(.secondary)
            Text(question?.question ?? "").font(.headline)
            VStack(spacing: 8) {
                ForEach(question?.options ?? [], id: \.title) { option in
                    Button { choose(option.title) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: option.symbol ?? "circle").frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title)
                                if let detail = option.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(20)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
