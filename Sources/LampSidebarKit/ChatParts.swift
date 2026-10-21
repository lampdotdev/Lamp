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

    /// Under what waits for setup before it's sent.
    public static let waitingForSetup = "Starts when Apple's app-building tools finish installing"
    /// Under what waits for the person to press Reload before it's sent (`Store.pause`).
    public static let waitingForReload = "Sent once you press Reload"

    /// A message waiting for the current change to finish. It can still be taken back. The latest of its group has
    /// the group's caption, and, where the agent can take them while it works, Send Now for the whole group
    /// (`sendNow`); once that's asked, the caption says they're on their way.
    public struct QueuedRow<Chips: View>: View {
        let text: String
        let waitingForSetup: Bool
        let waitingForReload: Bool
        let sending: Bool
        let place: QueuedPlace
        let onRemove: () -> Void
        let sendNow: (() -> Void)?
        let chips: Chips

        public init(text: String, waitingForSetup: Bool, waitingForReload: Bool = false, sending: Bool = false,
                    place: QueuedPlace = QueuedPlace(last: true, count: 1, first: true), onRemove: @escaping () -> Void,
                    sendNow: (() -> Void)? = nil, @ViewBuilder chips: () -> Chips) {
            self.text = text
            self.waitingForSetup = waitingForSetup
            self.waitingForReload = waitingForReload
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
                        .help("Unsend")
                        .accessibilityLabel("Unsend")
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
                    if waitingForSetup || waitingForReload {
                        Label(waitingForSetup ? ChatLook.waitingForSetup : ChatLook.waitingForReload, systemImage: "clock")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        // Worded like a text the other side hasn't read yet, with no icon, as Messages shows it.
                        Text(several ? "\(place.count) unread" : "Unread").font(.caption).foregroundStyle(.secondary)
                    }
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
}
