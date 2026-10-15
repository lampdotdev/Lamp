import SwiftUI
import AppKit

/// The chat's pieces as they look, shared by Lamp's window and the chat inside each app's window (the LampSidebar
/// extension), so the two are drawn by the same code and can't drift apart. Each takes plain values: what a line
/// says and how it stands, never Lamp's own state.
public enum ChatLook {
    /// A request's bubble, on the right.
    public struct UserBubble: View {
        let text: String
        public init(_ text: String) { self.text = text }

        public var body: some View {
            Text(text)
                .textSelection(.enabled)
                .lineSpacing(2)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
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

        public var body: some View {
            Text(ChatLook.prose(text, keep: keep))
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

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
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    /// A command the agent ran without asking ("Ran: git clone …"). The chat says that it happened; the command
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
                .help("Show the command")
                if expanded {
                    Text(command)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                        .padding(.leading, 22)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
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
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    /// The line that ends a turn ("Worked for 8s"), between rules.
    public struct SummaryLine: View {
        let text: String
        public init(_ text: String) { self.text = text }

        public var body: some View {
            HStack(spacing: 10) {
                Rectangle().fill(.separator).frame(height: 1)
                Text(text).font(.caption).foregroundStyle(.tertiary).fixedSize()
                Rectangle().fill(.separator).frame(height: 1)
            }
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
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    /// The message box as a row of controls with nothing behind them, in Lamp's window and beside an app alike: a round attach button,
    /// the rounded field with the text (and what's attached above it), any other round buttons beside it (such
    /// as dictation), and one round button that sends, or stops the turn while there's nothing to send.
    public struct MessageBar<Field: View, Above: View, Beside: View>: View {
        let busy: Bool
        let canSend: Bool
        let attachHelp: String
        let attach: () -> Void
        let send: () -> Void
        let stop: () -> Void
        let focus: () -> Void
        let field: Field
        let above: Above
        let beside: Beside

        public init(busy: Bool, canSend: Bool, attachHelp: String, attach: @escaping () -> Void,
                    send: @escaping () -> Void, stop: @escaping () -> Void, focus: @escaping () -> Void,
                    @ViewBuilder field: () -> Field,
                    @ViewBuilder above: () -> Above = { EmptyView() }, @ViewBuilder beside: () -> Beside = { EmptyView() }) {
            self.busy = busy
            self.canSend = canSend
            self.attachHelp = attachHelp
            self.attach = attach
            self.send = send
            self.stop = stop
            self.focus = focus
            self.field = field()
            self.above = above()
            self.beside = beside()
        }

        /// A one-line field is as tall as the round buttons, so the three line up.
        public static var height: CGFloat { Composer.lineHeight + 2 * padding }
        static var padding: CGFloat { 6 }

        public var body: some View {
            HStack(alignment: .bottom, spacing: 8) {
                Button(action: attach) { Image(systemName: "plus") }
                    .buttonStyle(Round(prominent: false))
                    .help(attachHelp)
                    .accessibilityLabel("Attach files")
                VStack(alignment: .leading, spacing: 6) {
                    above
                    field
                }
                .padding(.vertical, Self.padding).padding(.leading, 10).padding(.trailing, 12)
                .frame(minHeight: Self.height)
                // Pressing anywhere in the field, not only on the text, is for typing: the field's padding hands
                // focus to the text. Behind the text and what's attached, so clicks on those stay theirs.
                .background {
                    Self.fieldShape.fill(Color(nsColor: .textBackgroundColor))
                        .onTapGesture(perform: focus)
                }
                .overlay(Self.fieldShape.strokeBorder(Color(nsColor: .separatorColor)))
                beside
                // Stop while there's nothing to send; with something written, it waits for the turn instead.
                if busy && !canSend {
                    Button(action: stop) { Image(systemName: "stop.fill") }
                        .buttonStyle(Round(prominent: false))
                        .help("Stop")
                        .accessibilityLabel("Stop")
                } else {
                    Button(action: send) { Image(systemName: "arrow.up") }
                        .buttonStyle(Round(prominent: true))
                        .disabled(!canSend)
                        .help(busy ? "Queue this change. It's sent when the current one is done." : "Send")
                        .accessibilityLabel("Send")
                }
            }
        }

        static var fieldShape: RoundedRectangle { RoundedRectangle(cornerRadius: height / 2, style: .continuous) }
    }

    /// A round button beside the message box: the accent colour for Send, plain for the rest.
    public struct Round: ButtonStyle {
        let prominent: Bool
        @Environment(\.isEnabled) private var isEnabled

        public init(prominent: Bool) { self.prominent = prominent }

        public func makeBody(configuration: Configuration) -> some View {
            let size = MessageBar<EmptyView, EmptyView, EmptyView>.height
            configuration.label
                .font(.system(size: 14, weight: .semibold))
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
