import SwiftUI
import AppKit

/// Publish as a Web Page: what will go up and where, laid out to be read before anything leaves the Mac (the account and
/// repository, the credit the page carries, what its licences ask, how much), then the page and what can be done with it.
/// Drawn from plain values, so the chat (in its place) and the gallery show the same card.
public struct PublishCard: View {
    public enum Stage: Codable, Equatable {
        /// Finding GitHub's tool and the sign-in, and checking what would go up.
        case preparing
        /// What's needed before anything can go up, with the one thing that fixes it.
        case needsGitHub(Need)
        /// It can't be published, and why (a licence, a key in the code).
        case refused(String)
        case ready
        /// Going up, with what it's doing now.
        case publishing(String)
        case published
        case failed(String)
    }

    public enum Need: String, Codable, Equatable {
        case install, signIn
    }

    let icon: NSImage?
    let name: String
    let stage: Stage
    /// "owner/name", once known.
    let repo: String?
    /// The page's address, once it's up (from now or before).
    let page: String?
    let credit: String?
    let notes: [String]
    let size: String?
    let copied: Bool
    /// It's up already: Publish puts the wish as it is now in its place.
    let republish: Bool
    let publish: () -> Void
    let fix: () -> Void
    let openPage: () -> Void
    let copy: () -> Void
    let close: () -> Void
    let width: CGFloat?

    public init(icon: NSImage?, name: String, stage: Stage, repo: String?, page: String?, credit: String?, notes: [String],
                size: String?, copied: Bool, republish: Bool, publish: @escaping () -> Void, fix: @escaping () -> Void,
                openPage: @escaping () -> Void, copy: @escaping () -> Void, close: @escaping () -> Void, width: CGFloat? = 480) {
        self.icon = icon
        self.name = name
        self.stage = stage
        self.repo = repo
        self.page = page
        self.credit = credit
        self.notes = notes
        self.size = size
        self.copied = copied
        self.republish = republish
        self.publish = publish
        self.fix = fix
        self.openPage = openPage
        self.copy = copy
        self.close = close
        self.width = width
    }

    private var busy: Bool {
        switch stage {
        case .preparing, .publishing: true
        default: false
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: icon ?? NSWorkspace.shared.icon(for: .applicationBundle)).resizable()
                    .frame(width: 56, height: 56)
                    .padding(.top, -4)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Publish \(name) as a Web Page").font(.title3.bold())
                    // What the person accepts by publishing: who sees it, and where it goes.
                    Text("Anyone can play it in a browser and open it in Lamp. It goes up as a public repository on your GitHub account.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if stage != .preparing, !isBlocked {
                VStack(alignment: .leading, spacing: 8) {
                    if let repo { row("Goes to", "github.com/" + repo) }
                    if let page { row("Page", page) }
                    if let credit { row("Credit", credit) }
                    if let size { row("Files", size) }
                }
                ForEach(notes, id: \.self) { note in
                    Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            status
            buttons.cardButtons()
        }
        .padding(24)
        .frame(width: width)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    private var isBlocked: Bool {
        switch stage {
        case .needsGitHub, .refused: true
        default: false
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
            Text(value).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .font(.callout)
    }

    @ViewBuilder private var status: some View {
        switch stage {
        case .preparing:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Checking what goes up…").foregroundStyle(.secondary) }.font(.callout)
        case .publishing(let step):
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text(step).foregroundStyle(.secondary) }.font(.callout)
        case .needsGitHub(.install):
            problem("Publishing needs GitHub's command-line tool, gh.")
        case .needsGitHub(.signIn):
            problem("Sign in to GitHub with gh to publish from your account.")
        case .refused(let why), .failed(let why):
            problem(why)
        case .published:
            Label(copied ? "It's up. Link copied." : "It's up.", systemImage: "checkmark.circle.fill")
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
        case .published:
            Button("Copy Link", action: copy)
            Button("Open Page", action: openPage)
            Button("Done", action: close).keyboardShortcut(.defaultAction)
        case .needsGitHub(let need):
            Button("Cancel", role: .cancel, action: close).keyboardShortcut(.cancelAction)
            Button(need == .install ? "Get GitHub CLI…" : "Sign In to GitHub…", action: fix).keyboardShortcut(.defaultAction)
        case .refused:
            Button("Done", action: close).keyboardShortcut(.defaultAction)
        default:
            Button("Cancel", role: .cancel, action: close).keyboardShortcut(.cancelAction).disabled(busy && stage != .preparing)
            Button(republish ? "Update Page" : "Publish", action: publish)
                .keyboardShortcut(.defaultAction)
                .disabled(stage != .ready)
        }
    }
}
