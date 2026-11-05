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
        /// The release goes to the app's repository on GitHub too, with the same version and what's new: ticked unless
        /// the person unticks it, and only for an app that's on GitHub.
        public var alsoGitHub: Bool
        /// The release puts the app on GitHub too, the first time, as a repository on the person's account: unticked
        /// unless the person ticks it, since it makes the code public by default, and only for an app that isn't there yet.
        public var putOnGitHub: Bool

        public init(name: String, by: String = "", line: String, words: String, includeFile: Bool = false, notes: String = "",
                    alsoGitHub: Bool = true, putOnGitHub: Bool = false) {
            self.name = name
            self.by = by
            self.line = line
            self.words = words
            self.includeFile = includeFile
            self.notes = notes
            self.alsoGitHub = alsoGitHub
            self.putOnGitHub = putOnGitHub
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

    /// How the release's GitHub half went, said apart from the link's, so one failing never hides the other.
    public enum GitHubStage: Equatable {
        /// What it's doing now ("Uploading to GitHub…", "Waiting for GitHub to put the page up…").
        case working(String)
        /// Up, as this release's version ("v3").
        case done(String)
        /// Put on GitHub the first time: the repository ("owner/name") and this release's version.
        case put(String, String)
        case failed(String)
    }

    /// Putting the app on GitHub the first time, with its release: what will go up and where, checked before anything
    /// goes, and the choices GitHub takes once, shown under Also put on GitHub while it's ticked. Nil for an app that's
    /// on GitHub already (`gitHub`), or one that can't be updated from here (`gitHubNote`).
    public struct GitHubSetup: Equatable {
        public enum Stage: Equatable {
            /// GitHub's command-line tool, or a sign-in to it, is missing: said in the box's place, with what fixes it.
            case needsGitHub(GitHubNeed)
            /// The box is ticked and what would go up is being checked.
            case preparing
            /// It can't go up, and why (a license, a key in the code).
            case refused(String)
            case ready
        }

        public var stage: Stage
        /// "owner/name", once known.
        public var repo: String?
        /// The repository was made by a first try that failed before anything went up: its choices are settled.
        public var settled: Bool
        /// A web game's or a web app's page, where it will play ("someone.github.io/disk-map/"); nil for any other app,
        /// and in a private repository, which gets none (`privatePage`). `plays` is whether it's played or used.
        public var page: String?
        public var plays: Bool
        public var privatePage: Bool
        public var credit: String?
        /// Where the README's Open in Lamp goes.
        public var remix: String?
        public var size: String?
        public var notes: [String]
        /// Lines of sources only credited under their own terms, folded (`TermsFold`).
        public var terms: [String]
        public var isPrivate: Bool
        public var license: Bool
        /// An MIT license can be offered: nothing in it is share-alike.
        public var canChooseLicense: Bool
        /// The README shows the picture on the card.
        public var showsPicture: Bool

        public init(stage: Stage, repo: String? = nil, settled: Bool = false, page: String? = nil, plays: Bool = true,
                    privatePage: Bool = false, credit: String? = nil, remix: String? = nil, size: String? = nil, notes: [String] = [],
                    terms: [String] = [], isPrivate: Bool = false, license: Bool = true, canChooseLicense: Bool = true,
                    showsPicture: Bool = true) {
            self.stage = stage
            self.repo = repo
            self.settled = settled
            self.page = page
            self.plays = plays
            self.privatePage = privatePage
            self.credit = credit
            self.remix = remix
            self.size = size
            self.notes = notes
            self.terms = terms
            self.isPrivate = isPrivate
            self.license = license
            self.canChooseLicense = canChooseLicense
            self.showsPicture = showsPicture
        }
    }

    /// What the first push's choices do: get GitHub's tool or sign in to it, and the choices themselves.
    public struct GitHubSetupActions {
        let fix: () -> Void
        let setPrivate: (Bool) -> Void
        let setLicense: (Bool) -> Void
        let setPicture: (Bool) -> Void

        public init(fix: @escaping () -> Void, setPrivate: @escaping (Bool) -> Void, setLicense: @escaping (Bool) -> Void,
                    setPicture: @escaping (Bool) -> Void) {
            self.fix = fix
            self.setPrivate = setPrivate
            self.setLicense = setLicense
            self.setPicture = setPicture
        }

        public static let none = GitHubSetupActions(fix: {}, setPrivate: { _ in }, setLicense: { _ in }, setPicture: { _ in })
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
    /// The wish goes with its link as a file (its kind can be shared as one), or to GitHub: what it carries is passed on.
    let canIncludeFile: Bool
    /// Said while the wish goes with its link: the work in the wish that came with no license.
    let noLicense: String?
    /// Lamp is writing what's new for the release.
    let writingNotes: Bool
    /// The app's repository ("owner/name") when it's on GitHub and can be updated from here: the card offers to release
    /// there too. Nil otherwise.
    let gitHub: String?
    /// Why the app's repository can't be updated from here (no sign-in to GitHub), in place of the box; or, beside the
    /// box, what the commits show on GitHub (an address the person's git signs with).
    let gitHubNote: String?
    let gitHubStage: GitHubStage?
    /// Tries the GitHub half of the last release again, after it failed; nil when it can't be (the app changed since).
    let retryGitHub: (() -> Void)?
    let gitHubSetup: GitHubSetup?
    let setUpGitHub: GitHubSetupActions
    @State private var termsOpen = false
    /// Copy Link the first time, Release Update after: shares what's on the card and copies the link.
    let share: () -> Void
    let copy: () -> Void
    let stop: () -> Void
    let close: () -> Void
    /// The card's width; nil fills the room it's given.
    let width: CGFloat?

    public init(icon: NSImage?, picture: NSImage?, values: Binding<Values>, limits: Limits, link: String?, changed: Bool,
                stage: Stage, copied: Bool, retake: (() -> Void)?, retaking: Bool, canIncludeFile: Bool = false, noLicense: String? = nil,
                writingNotes: Bool = false, gitHub: String? = nil, gitHubNote: String? = nil, gitHubStage: GitHubStage? = nil,
                retryGitHub: (() -> Void)? = nil, gitHubSetup: GitHubSetup? = nil, setUpGitHub: GitHubSetupActions = .none,
                share: @escaping () -> Void, copy: @escaping () -> Void, stop: @escaping () -> Void, close: @escaping () -> Void,
                width: CGFloat? = 480) {
        self.noLicense = noLicense
        self.writingNotes = writingNotes
        self.gitHub = gitHub
        self.gitHubNote = gitHubNote
        self.gitHubStage = gitHubStage
        self.retryGitHub = retryGitHub
        self.gitHubSetup = gitHubSetup
        self.setUpGitHub = setUpGitHub
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
                        .help("Shown under the app's name on its page")
                }
                // The wish always goes with its link when it can: what the person must know before it does.
                if canIncludeFile, let noLicense {
                    Text(noLicense).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                // Shown where it's chosen: the release goes to the app's repository too while it's ticked.
                if let gitHub {
                    Toggle("Also update GitHub (\(gitHub))", isOn: $values.alsoGitHub)
                        .toggleStyle(.checkbox)
                        .font(.callout)
                        .help("Puts this version on GitHub too, as a commit and a release with what's new")
                    if values.alsoGitHub, let gitHubNote {
                        Text(gitHubNote).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                } else if let gitHubNote {
                    Text(gitHubNote).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else if let gitHubSetup {
                    firstPush(gitHubSetup)
                }
                if let link { linkRow(link) }
                if case .failed(let message) = stage { problem(message) }
                gitHubStatus
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
                .accessibilityLabel("Picture of the app")
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
                .help("Take the link down: it stops showing this app")
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
                .disabled(!values.isComplete || !canPutOnGitHub)
        }
    }

    /// Nothing waits on the first push's choices: it's unticked, or what goes up is checked and can go.
    private var canPutOnGitHub: Bool {
        guard values.putOnGitHub, let gitHubSetup else { return true }
        return gitHubSetup.stage == .ready
    }

    /// Also put on GitHub, and while it's ticked, what goes up and where and the choices GitHub takes once, as the
    /// person reads them before anything leaves the Mac. Without GitHub's tool or a sign-in, the box says so with what
    /// fixes it, rather than going away.
    @ViewBuilder private func firstPush(_ setup: GitHubSetup) -> some View {
        if case .needsGitHub(let need) = setup.stage {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Also put on GitHub", isOn: .constant(false)).toggleStyle(.checkbox).disabled(true)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(need == .install ? "It needs GitHub's command-line tool, gh." : "Sign in to GitHub with gh first.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(need == .install ? "Get GitHub CLI…" : "Sign In to GitHub…", action: setUpGitHub.fix).controlSize(.small)
                }
                .padding(.leading, 20)
            }
            .font(.callout)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(setup.settled ? "Also put on GitHub (\(setup.repo ?? ""))" : "Also put on GitHub", isOn: $values.putOnGitHub)
                    .toggleStyle(.checkbox)
                    .font(.callout)
                    .help("Puts its code on your GitHub account too, as a repository, with this release")
                if values.putOnGitHub {
                    firstPushDetails(setup).padding(.leading, 20)
                }
            }
        }
    }

    @ViewBuilder private func firstPushDetails(_ setup: GitHubSetup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // What the person accepts: what goes, and where.
            Text("Its code goes up as a repository on your GitHub account: what a shared app file holds, with the files that build it."
                 + (setup.page == nil ? "" : " Its page goes up too, for anyone to \(setup.plays ? "play" : "use") in a browser.")
                 + (picture == nil ? " Never your chat or the app's data." : " Your chat stays on this Mac. If you include the picture, anything visible in it goes on GitHub too."))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            switch setup.stage {
            case .preparing:
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Checking what goes up…").foregroundStyle(.secondary) }.font(.callout)
            case .refused(let why):
                problem(why)
            case .ready, .needsGitHub:
                VStack(alignment: .leading, spacing: 6) {
                    if let repo = setup.repo { row("Goes to", "github.com/" + repo) }
                    if let page = setup.page { row(setup.plays ? "Play at" : "Open at", page) }
                    if let credit = setup.credit { row("Credit", credit) }
                    if let remix = setup.remix { row("Remix link", remix) }
                    if let size = setup.size { row("Files", size) }
                }
                if picture != nil {
                    Toggle("Show the picture in its README", isOn: Binding(get: { setup.showsPicture }, set: setUpGitHub.setPicture))
                        .toggleStyle(.checkbox).font(.callout)
                }
                TermsFold(terms: setup.terms, open: $termsOpen)
                ForEach(setup.notes, id: \.self) { note in
                    Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                // The choices GitHub takes once, when the repository is made.
                if !setup.settled {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Public, so anyone can see it and remix it", isOn: Binding(get: { !setup.isPrivate }, set: { setUpGitHub.setPrivate(!$0) }))
                            .toggleStyle(.checkbox)
                        // GitHub serves a private repository's page only on a paid plan.
                        if setup.privatePage {
                            Text(setup.plays ? "A private repository gets no page to play." : "A private repository gets no page to open in a browser.")
                                .foregroundStyle(.secondary).padding(.leading, 20)
                        }
                        if setup.canChooseLicense {
                            Toggle("MIT license, so anyone may use the code", isOn: Binding(get: { setup.license }, set: setUpGitHub.setLicense))
                                .toggleStyle(.checkbox)
                                .help("Adds a LICENSE file in your name. Without one, the code is yours alone to use, even in public.")
                        }
                    }
                    .font(.callout)
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).foregroundStyle(.secondary).frame(width: 84, alignment: .leading)
            Text(value).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .font(.callout)
    }

    /// The GitHub half of a release, under the link's own: what it's doing, that it's up, or why not with a way to try again.
    @ViewBuilder private var gitHubStatus: some View {
        switch gitHubStage {
        case .working(let step):
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text(step).foregroundStyle(.secondary) }.font(.callout)
        case .done(let version):
            Label("Released on GitHub too, as \(version).", systemImage: "checkmark.circle.fill")
                .font(.callout).foregroundStyle(.secondary)
        case .put(let repo, let version):
            Label("Put on GitHub too, at github.com/\(repo), as \(version).", systemImage: "checkmark.circle.fill")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                problem(message)
                if let retryGitHub { Button("Try GitHub Again", action: retryGitHub).disabled(sending) }
            }
        case nil:
            EmptyView()
        }
    }

    private func problem(_ message: String) -> some View {
        Label {
            Text(message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .font(.callout)
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
