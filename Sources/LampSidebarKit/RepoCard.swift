import SwiftUI
import AppKit

/// Put on GitHub: what will go up and where, laid out to be read before anything leaves the Mac (the account and
/// repository, a web game's page to play, the credit it carries, what its licenses ask, how much, and the two choices
/// made the first time), then the repository and its page and what can be done with them. Drawn from plain values, so the chat (in its place) and the gallery
/// show the same card.
public struct RepoCard: View {
    public enum Stage: Codable, Equatable {
        /// Finding GitHub's tool and the sign-in, and checking what would go up.
        case preparing
        /// What's needed before anything can go up, with the one thing that fixes it.
        case needsGitHub(Need)
        /// It can't go up, and why (a license, a key in the code).
        case refused(String)
        case ready
        /// Going up, with what it's doing now.
        case working(String)
        /// Up; `unchanged` when GitHub already had the wish as it is.
        case done(unchanged: Bool)
        case failed(String)
    }

    /// What's missing before anything goes to GitHub: its command-line tool, or a sign-in to it.
    public enum Need: String, Codable, Equatable {
        case install, signIn
    }

    let icon: NSImage?
    let name: String
    let stage: Stage
    /// "owner/name", once known.
    let repo: String?
    /// The repository's address, once it's up (from now or before).
    let url: String?
    let credit: String?
    /// Where the README's Remix it with Lamp goes.
    let openInLamp: String?
    let notes: [String]
    /// Lines of sources only credited under their own terms, folded (`TermsFold`).
    let terms: [String]
    let size: String?
    let copied: Bool
    /// The repository is made already (a first try that failed after making it): its one-time choices are settled. Once
    /// the wish is up, a release on its link updates it (Release Update), not this card.
    let update: Bool
    /// Put on GitHub can be pressed now (ready, or after a failed try).
    let canPut: Bool
    let isPrivate: Bool
    let license: Bool
    /// An MIT license can be offered: nothing in it is share-alike.
    let canChooseLicense: Bool
    /// A web game's or a web app's page: where it plays ("someone.github.io/new-york"), and whether it's up now. Nil for
    /// any other wish, and for a private repository, which gets none (`privateGame`, a page of any kind). `plays` is
    /// whether it's played (a game) or used (an app), for what the card calls it.
    let page: String?
    let pageUp: Bool
    let privateGame: Bool
    let plays: Bool
    /// The picture of the wish the desk shows, which the README can show too, and whether it will.
    let picture: NSImage?
    let showsPicture: Bool
    let put: () -> Void
    let fix: () -> Void
    /// Opens Share Link's card, to make the link Remix it with Lamp goes to.
    let makeLink: () -> Void
    let setPrivate: (Bool) -> Void
    let setLicense: (Bool) -> Void
    let setPicture: (Bool) -> Void
    let openRepo: () -> Void
    /// Opens the page in the browser.
    let play: () -> Void
    let copy: () -> Void
    let close: () -> Void
    let width: CGFloat?
    /// Drawn in the chat's place: its words scroll when they don't fit, its buttons stay (`GitHubCardLayout`).
    let scrolls: Bool
    @State private var termsOpen = false

    public init(icon: NSImage?, name: String, stage: Stage, repo: String?, url: String?, credit: String?, openInLamp: String?, notes: [String], terms: [String] = [], size: String?,
                copied: Bool, update: Bool, canPut: Bool, isPrivate: Bool, license: Bool, canChooseLicense: Bool,
                page: String? = nil, pageUp: Bool = false, privateGame: Bool = false, plays: Bool = true, picture: NSImage? = nil, showsPicture: Bool = false,
                put: @escaping () -> Void, fix: @escaping () -> Void, makeLink: @escaping () -> Void = {}, setPrivate: @escaping (Bool) -> Void, setLicense: @escaping (Bool) -> Void,
                setPicture: @escaping (Bool) -> Void = { _ in }, openRepo: @escaping () -> Void, play: @escaping () -> Void = {}, copy: @escaping () -> Void, close: @escaping () -> Void, width: CGFloat? = 480,
                scrolls: Bool = false) {
        self.icon = icon
        self.name = name
        self.stage = stage
        self.repo = repo
        self.url = url
        self.credit = credit
        self.openInLamp = openInLamp
        self.notes = notes
        self.terms = terms
        self.size = size
        self.copied = copied
        self.update = update
        self.canPut = canPut
        self.isPrivate = isPrivate
        self.license = license
        self.canChooseLicense = canChooseLicense
        self.page = page
        self.pageUp = pageUp
        self.privateGame = privateGame
        self.plays = plays
        self.picture = picture
        self.showsPicture = showsPicture
        self.put = put
        self.fix = fix
        self.makeLink = makeLink
        self.setPrivate = setPrivate
        self.setLicense = setLicense
        self.setPicture = setPicture
        self.openRepo = openRepo
        self.play = play
        self.copy = copy
        self.close = close
        self.width = width
        self.scrolls = scrolls
    }

    private var busy: Bool {
        switch stage {
        case .preparing, .working: true
        default: false
        }
    }

    private var isBlocked: Bool {
        switch stage {
        case .needsGitHub, .refused: true
        default: false
        }
    }

    private var isDone: Bool {
        if case .done = stage { return true } else { return false }
    }

    public var body: some View {
        GitHubCardLayout(scrolls: scrolls, width: width) {
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: icon ?? NSWorkspace.shared.icon(for: .applicationBundle)).resizable()
                    .frame(width: 56, height: 56)
                    .padding(.top, -4)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Put \(name) on GitHub").font(.title3.bold())
                    // What the person accepts: what goes, and where.
                    Text("Its code goes up as a repository on your GitHub account: what a shared app file holds, with the files that build it."
                         + (page == nil ? "" : " Its page goes up too, for anyone to \(plays ? "play" : "use") in a browser.")
                         + (picture == nil ? " Never your chat or the app's data." : " Your chat stays on this Mac. If you include the picture, anything visible in it goes on GitHub too."))
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if stage != .preparing, !isBlocked {
                VStack(alignment: .leading, spacing: 8) {
                    if let repo { row("Goes to", "github.com/" + repo) }
                    if let page { row(plays ? "Play at" : "Open at", page) }
                    if let credit { row("Credit", credit) }
                    if let openInLamp {
                        row("Remix link", openInLamp)
                    } else if stage == .ready {
                        // Without a Share Link the README offers the shared file and Lamp's site; the link is what lets someone without Lamp make it.
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("Remix link").foregroundStyle(.secondary).frame(width: 92, alignment: .leading)
                            Button("Make a Link…", action: makeLink).controlSize(.small)
                            Spacer(minLength: 0)
                        }
                        .font(.callout)
                    }
                    if let size { row("Files", size) }
                }
                // The picture is shown where it's chosen, as Share Link's card shows it, so the person sees what goes up:
                // it can show what's in the app.
                if let picture, !isDone {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(nsImage: picture).resizable().scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                            .opacity(showsPicture ? 1 : 0.3)
                            .accessibilityLabel("Picture of the app")
                        Toggle("Include this picture", isOn: Binding(get: { showsPicture }, set: setPicture))
                            .toggleStyle(.checkbox)
                            .font(.callout)
                    }
                    .disabled(busy)
                }
                TermsFold(terms: terms, open: $termsOpen)
                ForEach(notes, id: \.self) { note in
                    Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                // The choices GitHub takes once, when the repository is made.
                if !update, !isDone {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Public, so anyone can see it and remix it", isOn: Binding(get: { !isPrivate }, set: { setPrivate(!$0) }))
                            .toggleStyle(.checkbox)
                        // GitHub serves a private repository's page only on a paid plan.
                        if privateGame { Text(plays ? "A private repository gets no page to play." : "A private repository gets no page to open in a browser.").foregroundStyle(.secondary).padding(.leading, 20) }
                        if canChooseLicense {
                            Toggle("MIT license, so anyone may use the code", isOn: Binding(get: { license }, set: setLicense))
                                .toggleStyle(.checkbox)
                                .help("Adds a LICENSE file in your name. Without one, the code is yours alone to use, even in public.")
                        }
                    }
                    .font(.callout)
                    .disabled(busy)
                }
            }
            status
        } buttons: {
            buttons.cardButtons()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).foregroundStyle(.secondary).frame(width: 92, alignment: .leading)
            Text(value).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .font(.callout)
    }

    @ViewBuilder private var status: some View {
        switch stage {
        case .preparing:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Checking what goes up…").foregroundStyle(.secondary) }.font(.callout)
        case .working(let step):
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text(step).foregroundStyle(.secondary) }.font(.callout)
        case .needsGitHub(.install):
            problem("Putting an app on GitHub needs GitHub's command-line tool, gh.")
        case .needsGitHub(.signIn):
            problem("Sign in to GitHub with gh to put it on your account.")
        case .refused(let why), .failed(let why):
            problem(why)
        case .done(let unchanged):
            Label(unchanged ? "It's up, unchanged since last time." : copied ? (pageUp ? "It's up. Page link copied." : "It's up. Link copied.") : "It's up.",
                  systemImage: "checkmark.circle.fill")
                .font(.callout).foregroundStyle(.secondary)
        case .ready:
            EmptyView()
        }
    }

    private func problem(_ text: String) -> some View {
        Label {
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .font(.callout)
    }

    @ViewBuilder private var buttons: some View {
        ViewThatFits(in: .horizontal) {
            HStack { buttonRow }
            VStack(alignment: .trailing, spacing: 8) { buttonRow }.frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder private var buttonRow: some View {
        Spacer(minLength: 0)
        switch stage {
        case .done:
            Button(pageUp ? "Copy Page Link" : "Copy Link", action: copy)
            Button("Open on GitHub", action: openRepo)
            if pageUp { Button(plays ? "Play" : "Open Page", action: play) }
            Button("Done", action: close).keyboardShortcut(.defaultAction)
        case .needsGitHub(let need):
            Button("Cancel", role: .cancel, action: close).keyboardShortcut(.cancelAction)
            Button(need == .install ? "Get GitHub CLI…" : "Sign In to GitHub…", action: fix).keyboardShortcut(.defaultAction)
        case .refused:
            Button("Done", action: close).keyboardShortcut(.defaultAction)
        default:
            Button("Cancel", role: .cancel, action: close).keyboardShortcut(.cancelAction).disabled(busy && stage != .preparing)
            Button("Put on GitHub", action: put)
                .keyboardShortcut(.defaultAction)
                .disabled(!canPut)
        }
    }
}
