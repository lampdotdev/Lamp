import SwiftUI
import AppKit

/// Put on GitHub: what will go up and where, laid out to be read before anything leaves the Mac (the account and
/// repository, the credit it carries, what its licenses ask, how much, and the two choices made the first time), then
/// the repository and what can be done with it. Drawn from plain values, so the chat (in its place) and the gallery
/// show the same card.
public struct RepoCard: View {
    public enum Stage: Codable, Equatable {
        /// Finding GitHub's tool and the sign-in, and checking what would go up.
        case preparing
        /// What's needed before anything can go up, with the one thing that fixes it.
        case needsGitHub(PublishCard.Need)
        /// It can't go up, and why (a license, a key in the code).
        case refused(String)
        case ready
        /// Going up, with what it's doing now.
        case working(String)
        /// Up; `unchanged` when GitHub already had the wish as it is.
        case done(unchanged: Bool)
        case failed(String)
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
    let size: String?
    let copied: Bool
    /// It's up already: Put on GitHub adds the wish as it is now as a new commit.
    let update: Bool
    /// Put on GitHub can be pressed now (ready, or after a failed try).
    let canPut: Bool
    let isPrivate: Bool
    let license: Bool
    /// An MIT license can be offered: nothing in it is share-alike.
    let canChooseLicense: Bool
    let put: () -> Void
    let fix: () -> Void
    /// Opens Share Link's card, to make the link Remix it with Lamp goes to.
    let makeLink: () -> Void
    let setPrivate: (Bool) -> Void
    let setLicense: (Bool) -> Void
    let openRepo: () -> Void
    let copy: () -> Void
    let close: () -> Void
    let width: CGFloat?

    public init(icon: NSImage?, name: String, stage: Stage, repo: String?, url: String?, credit: String?, openInLamp: String?, notes: [String], size: String?,
                copied: Bool, update: Bool, canPut: Bool, isPrivate: Bool, license: Bool, canChooseLicense: Bool,
                put: @escaping () -> Void, fix: @escaping () -> Void, makeLink: @escaping () -> Void = {}, setPrivate: @escaping (Bool) -> Void, setLicense: @escaping (Bool) -> Void,
                openRepo: @escaping () -> Void, copy: @escaping () -> Void, close: @escaping () -> Void, width: CGFloat? = 480) {
        self.icon = icon
        self.name = name
        self.stage = stage
        self.repo = repo
        self.url = url
        self.credit = credit
        self.openInLamp = openInLamp
        self.notes = notes
        self.size = size
        self.copied = copied
        self.update = update
        self.canPut = canPut
        self.isPrivate = isPrivate
        self.license = license
        self.canChooseLicense = canChooseLicense
        self.put = put
        self.fix = fix
        self.makeLink = makeLink
        self.setPrivate = setPrivate
        self.setLicense = setLicense
        self.openRepo = openRepo
        self.copy = copy
        self.close = close
        self.width = width
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: icon ?? NSWorkspace.shared.icon(for: .applicationBundle)).resizable()
                    .frame(width: 56, height: 56)
                    .padding(.top, -4)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Put \(name) on GitHub").font(.title3.bold())
                    // What the person accepts: what goes, and where.
                    Text("Its code goes up as a repository on your GitHub account: what a shared wish file holds, with the files that build it. Never your chat or the app's data.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if stage != .preparing, !isBlocked {
                VStack(alignment: .leading, spacing: 8) {
                    if let repo { row("Goes to", "github.com/" + repo) }
                    if let credit { row("Credit", credit) }
                    if let openInLamp {
                        row("Remix link", openInLamp)
                    } else if stage == .ready {
                        // Without a Share Link the README offers the shared file and Lamp's site; the link is what lets someone without Lamp make it.
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("Remix link").foregroundStyle(.secondary).frame(width: 92, alignment: .leading)
                            Button("Make Share Link…", action: makeLink).controlSize(.small)
                            Spacer(minLength: 0)
                        }
                        .font(.callout)
                    }
                    if let size { row("Files", size) }
                }
                ForEach(notes, id: \.self) { note in
                    Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                // The choices GitHub takes once, when the repository is made.
                if !update, !isDone {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Public, so anyone can see it and remix it", isOn: Binding(get: { !isPrivate }, set: { setPrivate(!$0) }))
                            .toggleStyle(.checkbox)
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
            buttons.cardButtons()
        }
        .padding(24)
        .frame(width: width)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
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
            problem("Putting a wish on GitHub needs GitHub's command-line tool, gh.")
        case .needsGitHub(.signIn):
            problem("Sign in to GitHub with gh to put it on your account.")
        case .refused(let why), .failed(let why):
            problem(why)
        case .done(let unchanged):
            Label(unchanged ? "It's up, unchanged since last time." : copied ? "It's up. Link copied." : "It's up.", systemImage: "checkmark.circle.fill")
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
            Button("Copy Link", action: copy)
            Button("Open on GitHub", action: openRepo)
            Button("Done", action: close).keyboardShortcut(.defaultAction)
        case .needsGitHub(let need):
            Button("Cancel", role: .cancel, action: close).keyboardShortcut(.cancelAction)
            Button(need == .install ? "Get GitHub CLI…" : "Sign In to GitHub…", action: fix).keyboardShortcut(.defaultAction)
        case .refused:
            Button("Done", action: close).keyboardShortcut(.defaultAction)
        default:
            Button("Cancel", role: .cancel, action: close).keyboardShortcut(.cancelAction).disabled(busy && stage != .preparing)
            Button(update ? "Update on GitHub" : "Put on GitHub", action: put)
                .keyboardShortcut(.defaultAction)
                .disabled(!canPut)
        }
    }
}
