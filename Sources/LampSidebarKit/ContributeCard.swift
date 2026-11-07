import SwiftUI
import AppKit

/// Send Changes Back: a wish's changes offered to the repository it came from, as a pull request from the person's
/// own fork. Laid out to be read before anything leaves the Mac: where it
/// goes, through which fork, the credit it carries, what its licenses ask and how many files it changes; then the pull request and
/// what can be done with it. Drawn from plain values, so the chat (in its place) and the gallery show the same card.
public struct ContributeCard: View {
    public enum Stage: Codable, Equatable {
        /// Finding GitHub's tool and the sign-in, and checking what would go.
        case preparing
        /// What's needed before anything can go, with the one thing that fixes it.
        case needsGitHub(GitHubNeed)
        /// It can't go, and why (a license, a key in the code, the person's own repository).
        case refused(String)
        case ready
        /// Going, with what it's doing now.
        case working(String)
        /// The pull request is open, at this address.
        case done(String)
        case failed(String)
        /// Nothing can go until something is settled, for the reason Lamp could establish, with the one thing that
        /// settles it.
        case blocked(ContributeBlock)
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
    /// Lines of sources only credited under their own terms, folded (`TermsFold`).
    let terms: [String]
    let size: String?
    let copied: Bool
    /// Send Changes Back can be pressed now (ready, or after a failed try).
    let canSend: Bool
    let send: () -> Void
    let fix: () -> Void
    /// What a blocked card's first button does (`ContributeBlock.Reason`): review the update, check the update
    /// history, or prepare the changes again.
    let settle: () -> Void
    let openRequest: () -> Void
    let copy: () -> Void
    let close: () -> Void
    let width: CGFloat?
    /// Drawn in the chat's place: its words scroll when they don't fit, its buttons stay (`GitHubCardLayout`).
    let scrolls: Bool
    @State private var termsOpen = false

    public init(icon: NSImage?, name: String, stage: Stage, upstream: String?, fork: String?, credit: String?, notes: [String], terms: [String] = [],
                size: String?, copied: Bool, canSend: Bool, send: @escaping () -> Void, fix: @escaping () -> Void,
                settle: @escaping () -> Void = {}, openRequest: @escaping () -> Void,
                copy: @escaping () -> Void, close: @escaping () -> Void, width: CGFloat? = 480, scrolls: Bool = false) {
        self.icon = icon
        self.name = name
        self.stage = stage
        self.upstream = upstream
        self.fork = fork
        self.credit = credit
        self.notes = notes
        self.terms = terms
        self.size = size
        self.copied = copied
        self.canSend = canSend
        self.send = send
        self.fix = fix
        self.settle = settle
        self.openRequest = openRequest
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
        case .needsGitHub, .refused, .blocked: true
        default: false
        }
    }

    private var block: ContributeBlock? {
        if case .blocked(let block) = stage { block } else { nil }
    }

    public var body: some View {
        GitHubCardLayout(scrolls: scrolls, width: width) {
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: icon ?? NSWorkspace.shared.icon(for: .applicationBundle)).resizable()
                    .frame(width: 56, height: 56)
                    .padding(.top, -4)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    if let block {
                        // Why nothing went, as far as Lamp could tell, in the card's own words.
                        Text(block.title).font(.title3.bold())
                        Text(block.text).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Send \(name)'s changes back").font(.title3.bold())
                        // What the person accepts: what goes, and where.
                        Text("Your changes go to the repository this app came from, as a pull request its owner can take: what a shared app file holds, on your own GitHub account first. Never your chat or the app's data.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if stage != .preparing, !isBlocked {
                VStack(alignment: .leading, spacing: 8) {
                    if let upstream { row("Goes to", "github.com/" + upstream) }
                    if let fork { row("Through", "github.com/" + fork) }
                    if let credit { row("Credit", credit) }
                    if let size { row("Files", size) }
                }
                TermsFold(terms: terms, open: $termsOpen)
                ForEach(notes, id: \.self) { note in
                    Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
        case .ready, .blocked:
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
        case .blocked(let block):
            switch block.reason {
            case .theyChanged:
                Button("Not Now", role: .cancel, action: close).keyboardShortcut(.cancelAction)
                Button("Review Update…", action: settle).keyboardShortcut(.defaultAction)
            case .unverified, .notRecovered:
                Button("Not Now", role: .cancel, action: close).keyboardShortcut(.cancelAction)
                Button("Check Update History", action: settle).keyboardShortcut(.defaultAction)
            case .couldNotCombine:
                Button("Try Again", action: settle)
                Button("Done", action: close).keyboardShortcut(.defaultAction)
            }
        default:
            Button("Cancel", role: .cancel, action: close).keyboardShortcut(.cancelAction).disabled(busy && stage != .preparing)
            Button("Send Changes Back", action: send)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSend)
        }
    }
}

/// Why a Send Changes Back card can't go on, as far as Lamp could establish it (`Contribute.Blocked`): the repository
/// changed the same parts since the last update the app took in; Lamp can't tell which version of theirs the app is
/// based on (or couldn't put that right); or the repository hasn't moved and the changes still don't combine with it.
public struct ContributeBlock: Codable, Equatable {
    public enum Reason: String, Codable, Equatable {
        case theyChanged, unverified, notRecovered, couldNotCombine
    }

    public var reason: Reason
    /// The files both changed, by their paths in the repository, when that's the reason.
    public var files: [String]

    public init(_ reason: Reason, files: [String] = []) {
        self.reason = reason
        self.files = files
    }

    public var title: String {
        switch reason {
        case .theyChanged: "Review their changes first"
        case .unverified, .notRecovered: "Lamp couldn't verify your last update"
        case .couldNotCombine: "Lamp couldn't prepare your changes"
        }
    }

    public var text: String {
        switch reason {
        case .theyChanged:
            "Their repository has newer changes that overlap with yours in \(Self.list(files)). Review the update, then try sending your changes again."
        case .unverified:
            "Lamp can't tell which version of their app your changes are based on. Nothing was sent. Check the update history before trying again."
        case .notRecovered:
            "Lamp couldn't recover the update history. Nothing was sent."
        case .couldNotCombine:
            "Their repository hasn't changed since your last update, but Lamp couldn't combine your changes with it. Nothing was sent."
        }
    }

    /// The files, three at most by name: "a", "a and b", "a, b and c", "a, b, c and 2 more".
    static func list(_ files: [String]) -> String {
        let named = Array(files.prefix(3))
        let more = files.count - named.count
        if more > 0 { return named.joined(separator: ", ") + " and \(more) more" }
        guard named.count > 1 else { return named.first ?? "" }
        return named.dropLast().joined(separator: ", ") + " and " + named.last!
    }
}
