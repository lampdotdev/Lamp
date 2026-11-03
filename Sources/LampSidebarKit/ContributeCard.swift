import SwiftUI
import AppKit

/// Send Changes Back: a wish's changes offered to the repository it came from, as a pull request from the person's
/// own fork. Laid out as Put on GitHub's card is (`RepoCard`), to be read before anything leaves the Mac: where it
/// goes, through which fork, the credit it carries, what its licenses ask and how much; then the pull request and
/// what can be done with it. Drawn from plain values, so the chat (in its place) and the gallery show the same card.
public struct ContributeCard: View {
    public enum Stage: Codable, Equatable {
        /// Finding GitHub's tool and the sign-in, and checking what would go.
        case preparing
        /// What's needed before anything can go, with the one thing that fixes it.
        case needsGitHub(RepoCard.Need)
        /// It can't go, and why (a license, a key in the code, the person's own repository).
        case refused(String)
        case ready
        /// Going, with what it's doing now.
        case working(String)
        /// The pull request is open, at this address.
        case done(String)
        case failed(String)
    }

    let icon: NSImage?
    let name: String
    let stage: Stage
    /// "owner/name": where the changes go.
    let upstream: String?
    /// "login/name": the person's fork they go through, once known.
    let fork: String?
    let credit: String?
    let notes: [String]
    let size: String?
    let copied: Bool
    /// Send Changes Back can be pressed now (ready, or after a failed try).
    let canSend: Bool
    let send: () -> Void
    let fix: () -> Void
    let openRequest: () -> Void
    let copy: () -> Void
    let close: () -> Void
    let width: CGFloat?

    public init(icon: NSImage?, name: String, stage: Stage, upstream: String?, fork: String?, credit: String?, notes: [String], size: String?,
                copied: Bool, canSend: Bool, send: @escaping () -> Void, fix: @escaping () -> Void, openRequest: @escaping () -> Void,
                copy: @escaping () -> Void, close: @escaping () -> Void, width: CGFloat? = 480) {
        self.icon = icon
        self.name = name
        self.stage = stage
        self.upstream = upstream
        self.fork = fork
        self.credit = credit
        self.notes = notes
        self.size = size
        self.copied = copied
        self.canSend = canSend
        self.send = send
        self.fix = fix
        self.openRequest = openRequest
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

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: icon ?? NSWorkspace.shared.icon(for: .applicationBundle)).resizable()
                    .frame(width: 56, height: 56)
                    .padding(.top, -4)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Send \(name)'s changes back").font(.title3.bold())
                    // What the person accepts: what goes, and where.
                    Text("Your changes go to the repository this wish came from, as a pull request its owner can take: what a shared wish file holds, on your own GitHub account first. Never your chat or the app's data.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if stage != .preparing, !isBlocked {
                VStack(alignment: .leading, spacing: 8) {
                    if let upstream { row("Goes to", "github.com/" + upstream) }
                    if let fork { row("Through", "github.com/" + fork) }
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
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Checking what goes…").foregroundStyle(.secondary) }.font(.callout)
        case .working(let step):
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text(step).foregroundStyle(.secondary) }.font(.callout)
        case .needsGitHub(.install):
            problem("Sending changes back needs GitHub's command-line tool, gh.")
        case .needsGitHub(.signIn):
            problem("Sign in to GitHub with gh to send them from your account.")
        case .refused(let why), .failed(let why):
            problem(why)
        case .done:
            Label(copied ? "The pull request is open. Link copied." : "The pull request is open.", systemImage: "checkmark.circle.fill")
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
            Button("Open on GitHub", action: openRequest)
            Button("Done", action: close).keyboardShortcut(.defaultAction)
        case .needsGitHub(let need):
            Button("Cancel", role: .cancel, action: close).keyboardShortcut(.cancelAction)
            Button(need == .install ? "Get GitHub CLI…" : "Sign In to GitHub…", action: fix).keyboardShortcut(.defaultAction)
        case .refused:
            Button("Done", action: close).keyboardShortcut(.defaultAction)
        default:
            Button("Cancel", role: .cancel, action: close).keyboardShortcut(.cancelAction).disabled(busy && stage != .preparing)
            Button("Send Changes Back", action: send)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSend)
        }
    }
}
