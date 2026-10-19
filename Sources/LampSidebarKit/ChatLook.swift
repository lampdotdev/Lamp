import SwiftUI
import AppKit

/// The chat's pieces as they look, shared by Lamp's window and the chat inside each app's window (the LampSidebar
/// extension), so the two are drawn by the same code and can't drift apart. Each takes plain values: what a line
/// says and how it stands, never Lamp's own state.
public enum ChatLook {
    /// A request's bubble, on the right, as Messages draws what you sent: white words on the accent colour.
    /// A request still waiting its turn is the same bubble, faded.
    public struct UserBubble: View {
        let text: String
        let waiting: Bool
        public init(_ text: String, waiting: Bool = false) {
            self.text = text
            self.waiting = waiting
        }

        public var body: some View {
            Text(text)
                .textSelection(.enabled)
                .lineSpacing(2)
                .foregroundStyle(.white)
                .tint(.white)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Bubble(.trailing).fill(Color.accentColor))
                .opacity(waiting ? 0.7 : 1)
                .padding(.trailing, ChatLook.tailRoom)
        }
    }

    /// What the agent says, as prose with its inline markdown.
    public struct AgentText: View {
        let text: String
        let keep: Bool
        /// `keep` is false while the message may still be growing, so each step isn't kept parsed.
        public init(_ text: String, keep: Bool = true) {
            self.text = text
            self.keep = keep
        }

        /// In a grey bubble on the left, as Messages draws the other person's. Answers run longer than a text
        /// message, so the bubble may take most of the width, leaving room on the right to tell it from a request.
        public var body: some View {
            Text(ChatLook.prose(text, keep: keep))
                .lineSpacing(3)
                .textSelection(.enabled)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Bubble(.leading).fill(ChatLook.agentBubble))
                .padding(.leading, ChatLook.tailRoom)
                .padding(.trailing, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The line above a fix Lamp started on its own after the app crashed: the request it sent isn't shown, so this
    /// says why the agent is at work with nobody having asked.
    public static let fixingCrash = "The app crashed, so Lamp is fixing it"

    /// One status line: a check, or a small spinner for a step still going.
    public struct StatusLine: View {
        let text: String
        let running: Bool
        public init(_ text: String, running: Bool) {
            self.text = text
            self.running = running
        }

        public var body: some View {
            HStack(spacing: 6) {
                Group {
                    if running { ProgressView().controlSize(.mini) } else { Image(systemName: "checkmark.circle") }
                }
                .frame(width: 16)
                Text(text)
            }
            .font(ChatLook.stepFont)
            .foregroundStyle(.secondary)
            .padding(.leading, ChatLook.stepIndent)
        }
    }

    /// What the agent said about how the work was going ("The layout's in. Now the timer."), once its turn is over
    /// and the line is among the turn's steps: grey like them. While the turn goes on it's a message like any other
    /// (`AgentText`).
    public struct ProgressLine: View {
        let text: String
        public init(_ text: String) { self.text = text }

        public var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: ChatLook.progressSymbol).frame(width: 16)
                Text(text).fixedSize(horizontal: false, vertical: true)
            }
            .font(ChatLook.stepFont)
            .foregroundStyle(.secondary)
            .padding(.leading, ChatLook.stepIndent)
            .padding(.trailing, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    /// The progress line's mark, which also tells the sidebar a status line is one (`SidebarLine.symbol`).
    public static let progressSymbol = "ellipsis.bubble"

    /// The agent's steps (what it ran, read, checked) are told in small grey words under its bubbles, as Messages
    /// says a message was delivered: there, but quieter than what's said.
    public static let stepFont = Font.subheadline
    /// Steps line up with the words in the agent's bubbles.
    public static let stepIndent: CGFloat = tailRoom + 4

    /// A finished turn's steps under one line, "Worked for 2 min 3 s", opened with a click to show each of them.
    /// The steps draw themselves, set in as the agent's steps are.
    public struct Worked<Steps: View>: View {
        let title: String
        let steps: Steps
        @State private var expanded = false

        public init(_ title: String, @ViewBuilder steps: () -> Steps) {
            self.title = title
            self.steps = steps()
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(title)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHand()
                .font(ChatLook.stepFont)
                .foregroundStyle(.secondary)
                .padding(.leading, ChatLook.stepIndent)
                .help(expanded ? "Hide the steps" : "Show the steps")
                .accessibilityHint(expanded ? "Hides the steps" : "Shows the steps")
                if expanded {
                    VStack(alignment: .leading, spacing: 4) { steps }
                        .transition(.opacity)
                }
            }
        }
    }

    /// A command the agent ran ("Ran: git clone …"). The chat says that it happened; the command
    /// itself is a click away, for anyone who wants to see it.
    public struct RanCommand: View {
        let command: String
        @State private var expanded = false
        public init(_ command: String) { self.command = command }

        public var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle").frame(width: 16)
                        Text("Ran a command")
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHand()
                .help("Show the command")
                if expanded {
                    Text(command)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                        .padding(.leading, 22)
                }
            }
            .font(ChatLook.stepFont)
            .foregroundStyle(.secondary)
            .padding(.leading, ChatLook.stepIndent)
        }
    }

    /// The command in a status line that says one was run.
    public static func ranCommand(in status: String) -> String? {
        status.hasPrefix("Ran: ") ? String(status.dropFirst(5)) : nil
    }

    /// A turn's progress: what the agent is doing and for how long.
    public struct ActivityLine: View {
        let activity: String
        let started: Date
        public init(_ activity: String, started: Date) {
            self.activity = activity
            self.started = started
        }

        public var body: some View {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini).frame(width: 16)
                Text(activity).lineLimit(1)
                Text("·")
                Elapsed(from: started, to: nil)
            }
            .font(ChatLook.stepFont)
            .foregroundStyle(.secondary)
            .padding(.leading, ChatLook.stepIndent)
        }
    }

    /// The line that ends a turn ("Worked for 8s"), small and centred, the way Messages marks the time between
    /// messages.
    public struct SummaryLine: View {
        let text: String
        public init(_ text: String) { self.text = text }

        public var body: some View {
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    /// Something that went wrong, set off in orange.
    public struct ErrorNote<Extra: View>: View {
        let text: String
        let extra: Extra
        public init(_ text: String, @ViewBuilder extra: () -> Extra = { EmptyView() }) {
            self.text = text
            self.extra = extra()
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text(text).textSelection(.enabled).lineSpacing(2)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                extra
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.leading, ChatLook.tailRoom)
        }
    }

    /// The message box as a row of controls with nothing behind them, in Lamp's window and beside an app alike: a round attach button,
    /// the rounded field with the text (what's attached above it, and small buttons such as dictation at its end, so
    /// the text keeps the width), and a round button that sends, or stops the turn while one runs.
    public struct MessageBar<Field: View, Above: View, Inside: View>: View {
        let busy: Bool
        let canSend: Bool
        let attachHelp: String
        let attach: () -> Void
        /// Pointing at part of the app, offered beside Add Files in the + menu while the app is open on this Mac.
        let point: (() -> Void)?
        let send: () -> Void
        let stop: () -> Void
        let focus: () -> Void
        let field: Field
        let above: Above
        let inside: Inside

        public init(busy: Bool, canSend: Bool, attachHelp: String, attach: @escaping () -> Void, point: (() -> Void)? = nil,
                    send: @escaping () -> Void, stop: @escaping () -> Void, focus: @escaping () -> Void,
                    @ViewBuilder field: () -> Field,
                    @ViewBuilder above: () -> Above = { EmptyView() }, @ViewBuilder inside: () -> Inside = { EmptyView() }) {
            self.busy = busy
            self.canSend = canSend
            self.attachHelp = attachHelp
            self.attach = attach
            self.point = point
            self.send = send
            self.stop = stop
            self.focus = focus
            self.field = field()
            self.above = above()
            self.inside = inside()
        }

        /// How tall a one-line field is. The round buttons are a little smaller, level with its middle.
        public static var height: CGFloat { Composer.lineHeight + 2 * padding }
        static var padding: CGFloat { 6 }
        public static var buttonSide: CGFloat { 30 }
        /// Under each round button, so it sits level with a one-line field and stays at the bottom of a taller one.
        static var buttonLift: CGFloat { (height - buttonSide) / 2 }

        public var body: some View {
            HStack(alignment: .bottom, spacing: 8) {
                Button(action: plus) { Image(systemName: "plus") }
                    .buttonStyle(Round(prominent: false))
                    .help(point == nil ? attachHelp : "Point at part of the app, or attach a file")
                    .accessibilityLabel(point == nil ? "Attach files" : "Add")
                    .padding(.bottom, Self.buttonLift)
                HStack(alignment: .bottom, spacing: 4) {
                    VStack(alignment: .leading, spacing: 6) {
                        above
                        field
                    }
                    inside
                }
                .padding(.vertical, Self.padding).padding(.leading, 10).padding(.trailing, 8)
                .frame(minHeight: Self.height)
                // Pressing anywhere in the field, not only on the text, is for typing: the field's padding hands
                // focus to the text. Behind the text and what's attached, so clicks on those stay theirs.
                .background {
                    Self.fieldShape.fill(Color(nsColor: .textBackgroundColor))
                        .onTapGesture(perform: focus)
                }
                .overlay(Self.fieldShape.strokeBorder(Color(nsColor: .separatorColor)))
                // While a turn runs the round button stops it; Return still sends what's typed, which waits its turn,
                // so the row needs no second button for that.
                if busy {
                    Button(action: stop) { Image(systemName: "stop.fill") }
                        .buttonStyle(Round(prominent: true))
                        .help("Stop. Press Return to send what you've typed after this change.")
                        .accessibilityLabel("Stop")
                        .padding(.bottom, Self.buttonLift)
                } else {
                    Button(action: send) { Image(systemName: "arrow.up") }
                        .buttonStyle(Round(prominent: true))
                        .disabled(!canSend)
                        .help("Send")
                        .accessibilityLabel("Send")
                        .padding(.bottom, Self.buttonLift)
                }
            }
        }

        /// Straight to the files when that's all there is; else a menu under the button, as the system's own +
        /// buttons have.
        private func plus() {
            guard let point else { return attach() }
            PlusMenu.show([("Point at the Screen", "scope", point), ("Attach a File…", "paperclip", attach)])
        }

        static var fieldShape: RoundedRectangle { RoundedRectangle(cornerRadius: height / 2, style: .continuous) }
    }

    /// A round button beside the message box: the accent colour for Send and Stop, plain for the rest.
    public struct Round: ButtonStyle {
        let prominent: Bool
        @Environment(\.isEnabled) private var isEnabled

        public init(prominent: Bool) { self.prominent = prominent }

        public func makeBody(configuration: Configuration) -> some View {
            let size = MessageBar<EmptyView, EmptyView, EmptyView>.buttonSide
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(prominent ? (isEnabled ? AnyShapeStyle(.white) : AnyShapeStyle(.tertiary))
                                           : AnyShapeStyle(.secondary))
                .frame(width: size, height: size)
                .background {
                    if prominent {
                        Circle().fill(isEnabled ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                    } else {
                        Circle().fill(Color(nsColor: .textBackgroundColor))
                            .overlay(Circle().strokeBorder(Color(nsColor: .separatorColor)))
                    }
                }
                .contentShape(Circle())
                .opacity(configuration.isPressed ? 0.7 : 1)
        }
    }

    /// Dictation, as a small button at the end of the message box: red and pulsing while it listens.
    public struct MicButton: View {
        let listening: Bool
        let action: () -> Void
        public init(listening: Bool, action: @escaping () -> Void) {
            self.listening = listening
            self.action = action
        }

        public var body: some View {
            Button(action: action) {
                Image(systemName: listening ? "mic.fill" : "mic")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(listening ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .symbolEffect(.pulse, isActive: listening)
                    .frame(width: 22, height: Composer.lineHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(listening ? "Stop dictation" : "Dictate a change")
            .accessibilityLabel(listening ? "Stop dictation" : "Dictate a change")
        }
    }

    /// What the message box says while empty.
    public static func placeholder(busy: Bool, empty: Bool) -> String {
        busy ? "Working… describe the next change" : empty ? "Describe what you'd like…" : "Describe a change…"
    }

    /// What the chat sits on: an off-white a touch warm, calmer than a text view's white, so the cards and the
    /// answers to choose from (still white) stand a little above it. A warm near-black in dark mode.
    public static let paper = Color(nsColor: NSColor(name: "LampChatPaper") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0x1F / 255, green: 0x1E / 255, blue: 0x1C / 255, alpha: 1)
            : NSColor(srgbRed: 0xF7 / 255, green: 0xF5 / 255, blue: 0xF1 / 255, alpha: 1)
    })

    /// Parsed once per message: parsing markdown on every redraw adds up while an agent is streaming.
    @MainActor private static var proseCache: [String: AttributedString] = [:]

    /// Inline markdown, with code spans set off by a faint background.
    @MainActor public static func prose(_ text: String, keep: Bool = true) -> AttributedString {
        if let cached = proseCache[text] { return cached }
        if proseCache.count > 2000 { proseCache.removeAll() }
        var string = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        let code = string.runs.filter { $0.inlinePresentationIntent?.contains(.code) == true }.map(\.range)
        for range in code { string[range].backgroundColor = Color.primary.opacity(0.07) }
        if keep { proseCache[text] = string }
        return string
    }
}

extension View {
    /// The pointing hand over something that opens or closes when clicked (a line of steps, a command to show):
    /// it says the line is a control, which text alone doesn't.
    public func pointingHand() -> some View { modifier(PointingHand()) }
}

private struct PointingHand: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.pointerStyle(.link)
        } else {
            content.onHover { inside in inside ? NSCursor.pointingHand.push() : NSCursor.pop() }
        }
    }
}

/// A running clock, "0:42", that stops at `end`.
public struct Elapsed: View {
    let start: Date
    let end: Date?

    public init(from start: Date, to end: Date?) {
        self.start = start
        self.end = end
    }

    public var body: some View {
        TimelineView(.periodic(from: start, by: 1)) { context in
            let seconds = max(0, Int((end ?? context.date).timeIntervalSince(start)))
            Text(String(format: "%d:%02d", seconds / 60, seconds % 60)).monospacedDigit()
        }
    }
}

/// The + button's menu, opened where the pointer is. That's on the screen itself rather than in the chat's window:
/// in an app's sidebar that window is one macOS keeps out of sight, and a press from VoiceOver or the keyboard
/// carries no click to place it by.
@MainActor
enum PlusMenu {
    private final class Target: NSObject {
        let actions: [() -> Void]
        init(_ actions: [() -> Void]) { self.actions = actions }
        @objc func run(_ item: NSMenuItem) { actions[item.tag]() }
    }

    /// Each item's title, its symbol and what it does.
    static func show(_ items: [(String, String, () -> Void)]) {
        let target = Target(items.map(\.2))
        let menu = NSMenu()
        for (index, entry) in items.enumerated() {
            let item = NSMenuItem(title: entry.0, action: #selector(Target.run(_:)), keyEquivalent: "")
            item.image = NSImage(systemSymbolName: entry.1, accessibilityDescription: nil)
            item.target = target
            item.tag = index
            menu.addItem(item)
        }
        // The target lives as long as the menu is up: popUp returns once it closes.
        withExtendedLifetime(target) { _ = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil) }
    }
}
