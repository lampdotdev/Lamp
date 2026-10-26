import SwiftUI
import AppKit

/// Share Link: what a wish's link will show anyone who has it, laid out to be read and changed before anything leaves
/// the Mac (the picture, which may show the person's own things, can be left out or taken again), then the link and
/// what can be done with it. Drawn from plain values, so Lamp's window (a sheet), the chat beside the app (in the
/// chat's place) and the gallery all show the same card.
public struct WishLinkCard: View {
    /// What the person can change on the card.
    public struct Values: Equatable {
        public var name: String
        public var line: String
        public var words: String
        public var includePicture: Bool
        /// The wish itself goes with the link, for anyone with Lamp to open that exact one.
        public var includeFile: Bool

        public init(name: String, line: String, words: String, includePicture: Bool, includeFile: Bool = false) {
            self.name = name
            self.line = line
            self.words = words
            self.includePicture = includePicture
            self.includeFile = includeFile
        }

        /// The card can share only a wish with a name and words.
        public var isComplete: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// The most each field holds, in characters (`WishLink.Limit`).
    public struct Limits: Equatable {
        public var name: Int
        public var line: Int
        public var words: Int
        public init(name: Int, line: Int, words: Int) {
            self.name = name
            self.line = line
            self.words = words
        }
    }

    public enum Stage: Equatable {
        case editing
        /// Sharing, changing or taking the link down.
        case sending
        case failed(String)
    }

    let icon: NSImage?
    let picture: NSImage?
    @Binding var values: Values
    let limits: Limits
    /// The link that's out, if there is one.
    let link: String?
    /// What's on the card isn't what the link shows yet.
    let changed: Bool
    let stage: Stage
    /// The link was copied a moment ago.
    let copied: Bool
    /// Takes the picture again, while the app is open on this Mac; nil otherwise.
    let retake: (() -> Void)?
    let retaking: Bool
    /// The wish can go with its link as a file (its kind can be shared as one): the card offers it.
    let canIncludeFile: Bool
    /// Copy Link the first time, Update Link after a change: shares what's on the card and copies the link.
    let share: () -> Void
    let copy: () -> Void
    let stop: () -> Void
    let close: () -> Void
    /// The sheet's width; nil fills the room it's given (the chat beside the app).
    let width: CGFloat?

    public init(icon: NSImage?, picture: NSImage?, values: Binding<Values>, limits: Limits, link: String?, changed: Bool,
                stage: Stage, copied: Bool, retake: (() -> Void)?, retaking: Bool, canIncludeFile: Bool = false, share: @escaping () -> Void,
                copy: @escaping () -> Void, stop: @escaping () -> Void, close: @escaping () -> Void, width: CGFloat? = 480) {
        self.icon = icon
        self.picture = picture
        self._values = values
        self.limits = limits
        self.link = link
        self.changed = changed
        self.stage = stage
        self.copied = copied
        self.retake = retake
        self.retaking = retaking
        self.canIncludeFile = canIncludeFile
        self.share = share
        self.copy = copy
        self.stop = stop
        self.close = close
        self.width = width
    }

    private var sending: Bool { stage == .sending }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: icon ?? NSWorkspace.shared.icon(for: .applicationBundle)).resizable()
                    .frame(width: 56, height: 56)
                    .padding(.top, -4)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Share a Link to This Wish").font(.title3.bold())
                    // What the person accepts by sharing: who sees it, and that nothing else goes.
                    Text(values.includeFile && canIncludeFile
                         ? "Anyone with the link sees what's here, and anyone with Lamp can open this exact wish: its code and files go too."
                         : "Anyone with the link sees what's here, and can make the wish with Lamp. Nothing else leaves your Mac.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let picture { pictureRow(picture) }
            field("Name") {
                TextField("Name", text: clipped(\.name, limits.name), prompt: Text("The wish's name"))
                    .textFieldStyle(.roundedBorder)
            }
            field("What it does") {
                TextField("What it does", text: clipped(\.line, limits.line), prompt: Text("One line, optional"))
                    .textFieldStyle(.roundedBorder)
            }
            field("The wish") {
                TextEditor(text: clipped(\.words, limits.words))
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 110)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                    .accessibilityLabel("The wish")
            }
            .disabled(sending)
            if canIncludeFile {
                Toggle("Include the wish itself, so people with Lamp get this exact one", isOn: $values.includeFile)
                    .toggleStyle(.checkbox)
                    .help("Its code and files go with the link, as when you share the wish as a file. Lamp checks them for keys first. Never your chat or the app's data.")
            }
            if let link { linkRow(link) }
            if case .failed(let message) = stage {
                Label {
                    Text(message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .font(.callout)
            }
            buttons.cardButtons()
        }
        .disabled(sending)
        .padding(24)
        .frame(width: width)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    private func pictureRow(_ picture: NSImage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(nsImage: picture).resizable().scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                .opacity(values.includePicture ? 1 : 0.3)
                .overlay { if retaking { ProgressView().controlSize(.small) } }
                .accessibilityLabel("Picture of the wish")
            HStack {
                Toggle("Include this picture", isOn: $values.includePicture).toggleStyle(.checkbox)
                Spacer(minLength: 8)
                if let retake {
                    Button("Take Again", action: retake).disabled(retaking)
                        .help("Take a new picture of the app as it is now")
                }
            }
        }
    }

    private func linkRow(_ link: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: copied ? "checkmark.circle.fill" : "link")
                .foregroundStyle(copied ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                .accessibilityHidden(true)
            Text(link).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
            if copied { Text("Copied").foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var buttons: some View {
        // Where the buttons don't fit on one line (the narrow chat beside the app), they go one under another.
        ViewThatFits(in: .horizontal) {
            HStack { buttonRow }
            VStack(alignment: .trailing, spacing: 8) { buttonRow }.frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder private var buttonRow: some View {
        if link != nil {
            Button("Stop Sharing", role: .destructive, action: stop)
                .help("Take the link down: it stops showing this wish")
        }
        Spacer(minLength: 0)
        if sending { ProgressView().controlSize(.small) }
        if link != nil && !changed {
            Button("Copy Link", action: copy)
            Button("Done", action: close).keyboardShortcut(.defaultAction)
        } else {
            Button("Cancel", role: .cancel, action: close).keyboardShortcut(.cancelAction)
            Button(link == nil ? "Copy Link" : "Update Link", action: share)
                .keyboardShortcut(.defaultAction)
                .disabled(!values.isComplete)
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.callout.weight(.medium)).foregroundStyle(.secondary).accessibilityHidden(true)
            content()
        }
    }

    /// A field that never holds more than the site takes.
    private func clipped(_ key: WritableKeyPath<Values, String>, _ limit: Int) -> Binding<String> {
        Binding(get: { values[keyPath: key] }, set: { values[keyPath: key] = String($0.prefix(limit)) })
    }
}
