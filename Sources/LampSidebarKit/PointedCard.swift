import SwiftUI
import AppKit

extension ChatLook {
    /// What the person pointed at in the app, as one small card: inside the message box while it waits to go with
    /// the message, with a way to point again or let it go, and above the request once sent. The app itself is left
    /// as it is: the card is the one place the choice shows, so it can't be read as something floating over the app.
    public struct PointedCard: View {
        let app: String
        let title: String
        let detail: String?
        let picture: NSImage?
        let preview: (() -> Void)?
        let chooseAgain: (() -> Void)?
        let remove: (() -> Void)?

        /// In the message box `remove` is there, and `chooseAgain` too while the app is open to point at; in a
        /// sent request neither is, and the card is the smaller one beside the bubble.
        public init(app: String, title: String, detail: String?, picture: NSImage?, preview: (() -> Void)? = nil,
                    chooseAgain: (() -> Void)? = nil, remove: (() -> Void)? = nil) {
            self.app = app
            self.title = title
            self.detail = detail
            self.picture = picture
            self.preview = preview
            self.chooseAgain = chooseAgain
            self.remove = remove
        }

        private var inDraft: Bool { remove != nil }

        public var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                if inDraft {
                    Text("Selected from \(app)".uppercased())
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 10) {
                    thumbnail
                    // The name may take a second line beside a narrow chat rather than be cut short.
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        if let detail, !detail.isEmpty {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    if !inDraft { Spacer(minLength: 0) }
                }
                if inDraft {
                    HStack(spacing: 14) {
                        if let chooseAgain {
                            Button("Choose Something Else", action: chooseAgain)
                                .help("Point at something else in \(app)")
                        }
                        if let remove {
                            Button("Remove", action: remove)
                                .help("Send your message without it")
                        }
                    }
                    .buttonStyle(Link())
                }
            }
            .padding(inDraft ? 10 : 8)
            .frame(maxWidth: inDraft ? .infinity : 260, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: Self.shape(inDraft))
            .overlay(Self.shape(inDraft).strokeBorder(Color(nsColor: .separatorColor)))
            .fixedSize(horizontal: !inDraft, vertical: true)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(detail.map { "Selected: \(title), \($0)" } ?? "Selected: \(title)")
        }

        /// Concentric with the message box around it, which is rounded by half its one-line height.
        private static func shape(_ inDraft: Bool) -> RoundedRectangle {
            RoundedRectangle(cornerRadius: inDraft ? 11 : 10, style: .continuous)
        }

        /// The thing as it looked when pointed at, near its own size: a button is wider than it's tall, so its tile
        /// is too, up to nearly twice its height. On the page's own white, so a light control keeps its edge.
        private var thumbnail: some View {
            let height: CGFloat = inDraft ? 44 : 36
            let aspect = picture.map { $0.size.width / max($0.size.height, 1) } ?? 1
            let width = min(max(height * aspect, height), height * 1.75)
            let picture = Group {
                if let picture {
                    Image(nsImage: picture).resizable().interpolation(.high).scaledToFit().padding(4)
                } else {
                    Image(systemName: "scope").foregroundStyle(.secondary)
                }
            }
            .frame(width: width, height: height)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
            return Group {
                if let preview {
                    Button(action: preview) { picture.contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .help("Show it larger")
                } else {
                    picture
                }
            }
        }

        /// A button that reads as words in the accent colour, for the card's two small actions.
        struct Link: ButtonStyle {
            func makeBody(configuration: Configuration) -> some View {
                configuration.label
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentColor)
                    .opacity(configuration.isPressed ? 0.6 : 1)
                    .contentShape(Rectangle())
            }
        }
    }
}
