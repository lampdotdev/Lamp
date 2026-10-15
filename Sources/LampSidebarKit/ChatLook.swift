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

    /// The Stop and Send buttons beside the message box.
    public struct StopButton: View {
        let action: () -> Void
        public init(action: @escaping () -> Void) { self.action = action }

        public var body: some View {
            Button(action: action) { Image(systemName: "stop.circle.fill").font(.title2) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Stop")
                .accessibilityLabel("Stop")
                .frame(height: Composer.lineHeight)
        }
    }

    public struct SendButton: View {
        let busy: Bool
        let action: () -> Void
        public init(busy: Bool, action: @escaping () -> Void) {
            self.busy = busy
            self.action = action
        }

        public var body: some View {
            Button(action: action) { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                .buttonStyle(.plain)
                .help(busy ? "Queue this change. It's sent when the current one is done." : "Send")
                .frame(height: Composer.lineHeight)
        }
    }

    /// What the message box says while empty.
    public static func placeholder(busy: Bool, empty: Bool) -> String {
        busy ? "Working… describe the next change" : empty ? "Describe what you wish was easier…" : "Describe a change…"
    }

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
