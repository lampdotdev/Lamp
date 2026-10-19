import SwiftUI
import AppKit

/// The chat's rows around the transcript, shared by Lamp's window and the chat inside each app's window, from
/// plain values: what waits in line, what the agent asks to run, an app that won't quit.
extension ChatLook {
    /// An attachment's chip: its picture or icon, its name, and a button to take it off when it can be. What a
    /// click on it does is the label's: Lamp's window shows it in Quick Look.
    public struct Chip<Label: View>: View {
        let onRemove: (() -> Void)?
        let label: Label

        public init(onRemove: (() -> Void)? = nil, @ViewBuilder label: () -> Label) {
            self.onRemove = onRemove
            self.label = label()
        }

        public var body: some View {
            HStack(spacing: 6) {
                label
                if let onRemove {
                    Button(action: onRemove) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                        .help("Remove")
                }
            }
            .font(.caption)
            .padding(4)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
        }
    }

    /// A chip's label: a small picture and the file's name.
    public struct ChipLabel<Thumbnail: View>: View {
        let name: String
        let thumbnail: Thumbnail

        public init(name: String, @ViewBuilder thumbnail: () -> Thumbnail) {
            self.name = name
            self.thumbnail = thumbnail()
        }

        public var body: some View {
            HStack(spacing: 6) {
                thumbnail
                Text(name).lineLimit(1).truncationMode(.middle).frame(maxWidth: 160, alignment: .leading)
            }
        }
    }

    /// Where each waiting message sits in its group. Waiting messages go out together, so they're shown as one
    /// group: close together, with one caption under the latest saying how many there are and, where the agent can
    /// take them while it works, Send Now for all of them. Those already sent now (`sending`) are a group of their
    /// own, with its own caption.
    public struct QueuedPlace: Equatable {
        /// The latest of its group: the caption goes under it.
        public var last: Bool
        /// How many messages its group holds.
        public var count: Int
        /// It starts a group, so it stands apart from what's above it.
        public var first: Bool

        public init(last: Bool, count: Int, first: Bool) {
            self.last = last
            self.count = count
            self.first = first
        }

        public static func places(sending: [Bool]) -> [QueuedPlace] {
            sending.indices.map { index in
                let first = index == 0 || sending[index - 1] != sending[index]
                let last = index == sending.count - 1 || sending[index + 1] != sending[index]
                var start = index, end = index
                while start > 0, sending[start - 1] == sending[index] { start -= 1 }
                while end < sending.count - 1, sending[end + 1] == sending[index] { end += 1 }
                return QueuedPlace(last: last, count: end - start + 1, first: first)
            }
        }
    }

    /// A message waiting for the current change to finish. It can still be taken back. The latest of its group has
    /// the group's caption, and, where the agent can take them while it works, Send Now for the whole group
    /// (`sendNow`); once that's asked, the caption says they're on their way.
    public struct QueuedRow<Chips: View>: View {
        let text: String
        let waitingForSetup: Bool
        let sending: Bool
        let place: QueuedPlace
        let onRemove: () -> Void
        let sendNow: (() -> Void)?
        let chips: Chips

        public init(text: String, waitingForSetup: Bool, sending: Bool = false,
                    place: QueuedPlace = QueuedPlace(last: true, count: 1, first: true), onRemove: @escaping () -> Void,
                    sendNow: (() -> Void)? = nil, @ViewBuilder chips: () -> Chips) {
            self.text = text
            self.waitingForSetup = waitingForSetup
            self.sending = sending
            self.place = place
            self.onRemove = onRemove
            self.sendNow = sendNow
            self.chips = chips()
        }

        public var body: some View {
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 6) { chips }
                HStack(spacing: 6) {
                    Button(action: onRemove) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                        .help("Remove from the queue")
                        .accessibilityLabel("Remove from the queue")
                    UserBubble(text, waiting: true)
                }
                // The width limit goes around the button too, so it stays next to the bubble.
                .frame(maxWidth: 480 + 22 + ChatLook.tailRoom, alignment: .trailing)
                .padding(.leading, 40)
                if place.last { caption.padding(.trailing, ChatLook.tailRoom) }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }

        @ViewBuilder private var caption: some View {
            let several = place.count > 1
            HStack(spacing: 10) {
                if sending {
                    Label(several ? "Sending \(place.count) now" : "Sending now", systemImage: "arrow.up.circle")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Label(waitingForSetup ? "Starts when Apple's app-building tools finish installing"
                              : several ? "\(place.count) queued" : "Queued",
                          systemImage: "clock").font(.caption).foregroundStyle(.secondary)
                    if let sendNow {
                        Button(several ? "Send All Now" : "Send Now", action: sendNow)
                            .buttonStyle(.link).font(.caption)
                            .help(several ? "Send these to the agent while it works" : "Send this to the agent while it works")
                    }
                }
            }
        }
    }

    /// Under the chat while Lamp waits for an app that was asked to quit and isn't responding: it may be stuck,
    /// or busy with something long, and only the person can say which. One click ends it, at the cost the line
    /// names, and what was waiting goes on.
    public struct UnresponsiveNotice: View {
        let text: String
        let forceQuit: () -> Void

        public init(text: String, forceQuit: @escaping () -> Void) {
            self.text = text
            self.forceQuit = forceQuit
        }

        public var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label {
                    Text(text).lineSpacing(2)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
                Button("Force Quit", action: forceQuit)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    /// What a command does and how risky it is, in plain words for people who don't read shell commands.
    public struct Explanation: Codable, Equatable {
        public var summary: String
        /// "low", "medium" or "high"; empty when nothing rated it.
        public var risk: String
        public var why: String

        public init(summary: String, risk: String, why: String) {
            self.summary = summary
            self.risk = risk
            self.why = why
        }
    }

    /// A shell command the agent wants to run, explained in plain words. Nothing runs until the person allows it.
    public struct ApprovalCard: View {
        let title: String
        let command: String
        let explanation: Explanation?
        let onAllow: () -> Void
        let onAllowAll: () -> Void
        let onDeny: () -> Void
        @State private var showCommand = false

        public init(title: String, command: String, explanation: Explanation?, onAllow: @escaping () -> Void,
                    onAllowAll: @escaping () -> Void, onDeny: @escaping () -> Void) {
            self.title = title
            self.command = command
            self.explanation = explanation
            self.onAllow = onAllow
            self.onAllowAll = onAllowAll
            self.onDeny = onDeny
        }

        private var highRisk: Bool { explanation?.risk == "high" }

        /// The same green, yellow and red as app icons' backgrounds (Lamp's `Icons.backgrounds`). The icon
        /// yellow is too pale to read on a light background, so light mode gets a darker shade of it.
        private var riskColor: Color {
            switch explanation?.risk {
            case "low": return Color(nsColor: NSColor(srgbRed: 0x28 / 255, green: 0xA7 / 255, blue: 0x45 / 255, alpha: 1))
            case "high": return Color(nsColor: NSColor(srgbRed: 0xE0 / 255, green: 0x30 / 255, blue: 0x2A / 255, alpha: 1))
            default:
                let yellow = NSColor(srgbRed: 1, green: 0xC4 / 255, blue: 0, alpha: 1)
                return Color(nsColor: NSColor(name: nil) { appearance in
                    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? yellow : yellow.blended(withFraction: 0.3, of: .black) ?? yellow
                })
            }
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                if let explanation {
                    // No fixedSize here: it makes SwiftUI size the text for its narrowest possible width, and that
                    // height became the whole window's minimum, growing the window past the screen.
                    Text(explanation.summary).font(.headline)
                } else {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Working out what this does…").foregroundStyle(.secondary)
                    }
                }
                // Not a DisclosureGroup: on the Mac only its chevron toggles it, so clicking the words did nothing.
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showCommand.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .rotationEffect(.degrees(showCommand ? 90 : 0))
                        Text(showCommand ? "Hide command" : "Show command").font(.caption)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHand()
                .foregroundStyle(.secondary)
                if showCommand {
                    // A short command takes only the room it needs; a long one scrolls rather than pushing the chat
                    // out of the window. The limit goes on a scroll view sized to what's in it: a frame with only
                    // a maximum takes all the height it's offered, which made a one-line command a five-line box.
                    ScrollView { commandText }
                        .scrollBounceBehavior(.basedOnSize)
                        .frame(maxHeight: 120)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(8)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                }
                HStack {
                    // Nothing rated it: no level to show, so nothing here.
                    if let explanation, !explanation.risk.isEmpty {
                        (Text("\(explanation.risk.capitalized) risk").bold() + Text(explanation.why.isEmpty ? "" : ": \(explanation.why)"))
                            .font(.callout)
                            .foregroundStyle(riskColor)
                    }
                    Spacer()
                    if highRisk {
                        // Risky: denying is the default, on Escape as well, and there's no blanket "allow all".
                        Button("Allow", action: onAllow)
                        Button("Deny", role: .cancel, action: onDeny)
                            .keyboardShortcut(.cancelAction)
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Deny", role: .cancel, action: onDeny)
                            .keyboardShortcut(.escape, modifiers: [])
                        Button("Allow All This Turn", action: onAllowAll)
                        Button("Allow", action: onAllow)
                            .keyboardShortcut(.return, modifiers: .command)
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }

        private var commandText: some View {
            Text(command)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
