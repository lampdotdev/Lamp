import SwiftUI
import AppKit

/// Share Link: what a wish's link will show anyone who has it (its name, its picture, what it does and who it's by),
/// laid out to be read and changed before anything leaves the Mac (the picture, which may show the person's own things,
/// can be taken again), then the link and what can be done with it. Drawn from plain values, so its window
/// (`WishLinkWindows`) and the gallery show the same card.
public struct WishLinkCard: View {
    /// What the person can change on the card.
    public struct Values: Equatable {
        public var name: String
        /// Who it's by, under its name on the page: the person's name, or nothing.
        public var by: String
        public var line: String
        public var words: String
        /// The wish itself goes with the link, for anyone with Lamp to open that exact one: always, when it can.
        public var includeFile: Bool
        /// What's new in this release, a line each, for the link's page and the app's What's New: written by Lamp, the
        /// person's to change or clear. Only for a link that's out.
        public var notes: String

        public init(name: String, by: String = "", line: String, words: String, includeFile: Bool = false, notes: String = "") {
            self.name = name
            self.by = by
            self.line = line
            self.words = words
            self.includeFile = includeFile
            self.notes = notes
        }

        /// The card can share only a wish with a name, and something to make one's own version from: what it does,
        /// or else its first request (`words`, which the card doesn't show).
        public var isComplete: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !(line + words).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// The most each field holds, in characters (`WishLink.Limit`).
    public struct Limits: Equatable {
        public var name: Int
        public var line: Int
        public var words: Int
        public var by: Int
        /// What's new: the lines a release holds, and a line's characters.
        public var notes: Int
        public var note: Int
        public init(name: Int, line: Int, words: Int, by: Int = 60, notes: Int = 5, note: Int = 120) {
            self.name = name
            self.line = line
            self.words = words
            self.by = by
            self.notes = notes
            self.note = note
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
    /// The wish goes with its link as a file (its kind can be shared as one).
    let canIncludeFile: Bool
    /// Said while the wish goes with its link: the work in the wish that came with no license.
    let noLicense: String?
    /// Lamp is writing what's new for the release.
    let writingNotes: Bool
    /// Copy Link the first time, Release Update after: shares what's on the card and copies the link.
    let share: () -> Void
    let copy: () -> Void
    let stop: () -> Void
    let close: () -> Void
    /// The card's width; nil fills the room it's given.
    let width: CGFloat?

    public init(icon: NSImage?, picture: NSImage?, values: Binding<Values>, limits: Limits, link: String?, changed: Bool,
                stage: Stage, copied: Bool, retake: (() -> Void)?, retaking: Bool, canIncludeFile: Bool = false, noLicense: String? = nil,
                writingNotes: Bool = false,
                share: @escaping () -> Void, copy: @escaping () -> Void, stop: @escaping () -> Void, close: @escaping () -> Void,
                width: CGFloat? = 480) {
        self.noLicense = noLicense
        self.writingNotes = writingNotes
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

    /// Where the title starts, right of the icon: what's under the title lines up with it.
    private static let indent: CGFloat = 56 + 12

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: icon ?? NSWorkspace.shared.icon(for: .applicationBundle)).resizable()
                    .frame(width: 56, height: 56)
                    .padding(.top, -4)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Share a Link to \(values.name)").font(.title3.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Let others use it and make their own version.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 16) {
                if let picture { pictureRow(picture) }
                // A release says what's new in it: Lamp's lines, the person's to change. Only once there's a link.
                if link != nil { notesField }
                field("What it does") {
                    TextField("What it does", text: clipped(\.line, limits.line), prompt: Text("A line or two, optional"), axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(Paper.card, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                }
                field("By") {
                    TextField("By", text: clipped(\.by, limits.by), prompt: Text("Your name, optional"))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(Paper.card, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                        .help("Shown under the wish's name on its page")
                }
                // The wish always goes with its link when it can: what the person must know before it does.
                if canIncludeFile, let noLicense {
                    Text(noLicense).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
            }
            .padding(.leading, Self.indent)
            buttons.cardButtons()
        }
        .disabled(sending)
        .padding(24)
        .frame(width: width)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    private func pictureRow(_ picture: NSImage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // The picture always goes with the link; the person can take it again if it shows something of theirs.
            HStack {
                Text("Picture").font(.callout.weight(.medium)).foregroundStyle(.secondary).accessibilityHidden(true)
                Spacer(minLength: 8)
                if let retake {
                    Button("Take Again", action: retake).disabled(retaking)
                        .help("Take a new picture of the app as it is now")
                }
            }
            // As big as the picture is, up to its box's height: the box hugs it rather than leaving bands either side.
            Image(nsImage: picture).resizable().interpolation(.high).scaledToFit()
                .frame(maxHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                .overlay { if retaking { ProgressView().controlSize(.small) } }
                .accessibilityLabel("Picture of the wish")
        }
    }

    /// The link that's out, and a button beside it that copies it, a tick for a moment once it has.
    private func linkRow(_ link: String) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "link").foregroundStyle(.secondary).accessibilityHidden(true)
                Text(link).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Paper.card, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Paper.rule))
            Button(action: copy) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PaperButtonStyle(.outline, height: 34, square: true))
            .help(copied ? "Copied" : "Copy the link")
            .accessibilityLabel(copied ? "Copied" : "Copy Link")
        }
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
            Button(link == nil ? "Copy Link" : "Release Update", action: share)
                .keyboardShortcut(.defaultAction)
                .disabled(!values.isComplete)
        }
    }

    private var notesField: some View {
        field("What's New") {
            TextField("What's New", text: notesBinding, prompt: Text(writingNotes ? "Writing what's new…" : "A line for each change, optional"), axis: .vertical)
                .lineLimit(3, reservesSpace: true)
                .textFieldStyle(.plain)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(Paper.card, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                .overlay(alignment: .topTrailing) { if writingNotes { ProgressView().controlSize(.small).padding(6) } }
                .help("Shown on the link's page and in the app's menu")
        }
    }

    /// What's new holds at most `notes` lines of `note` characters.
    private var notesBinding: Binding<String> {
        Binding(get: { values.notes }, set: { text in
            values.notes = text.split(separator: "\n", omittingEmptySubsequences: false).prefix(limits.notes)
                .map { String($0.prefix(limits.note)) }.joined(separator: "\n")
        })
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
