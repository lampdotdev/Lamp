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
    /// The screenshot the pull request can show, and what's done with it; nil where there's none to offer.
    let screenshot: ContributeScreenshot?
    /// Include Screenshot ticked or cleared.
    let include: (Bool) -> Void
    let retake: () -> Void
    let remove: () -> Void
    /// Send without the screenshot, after it couldn't be uploaded.
    let sendWithout: () -> Void
    let width: CGFloat?
    /// Drawn in the chat's place: its words scroll when they don't fit, its buttons stay (`GitHubCardLayout`).
    let scrolls: Bool
    @State private var termsOpen = false
    @State private var shotOpen = false

    public init(icon: NSImage?, name: String, stage: Stage, upstream: String?, fork: String?, credit: String?, notes: [String], terms: [String] = [],
                size: String?, copied: Bool, canSend: Bool, send: @escaping () -> Void, fix: @escaping () -> Void,
                settle: @escaping () -> Void = {}, openRequest: @escaping () -> Void,
                copy: @escaping () -> Void, close: @escaping () -> Void, screenshot: ContributeScreenshot? = nil,
                include: @escaping (Bool) -> Void = { _ in }, retake: @escaping () -> Void = {}, remove: @escaping () -> Void = {},
                sendWithout: @escaping () -> Void = {}, width: CGFloat? = 480, scrolls: Bool = false) {
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
        self.screenshot = screenshot
        self.include = include
        self.retake = retake
        self.remove = remove
        self.sendWithout = sendWithout
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
                        Text("Your changes go to the repository this app came from, as a pull request its owner can take: what a shared app file holds, on your own GitHub account first. Never your chat, and none of the app's data unless a screenshot you include shows it.")
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
                if let screenshot, !isDone { screenshotSection(screenshot) }
            }
            status
        } buttons: {
            buttons.cardButtons()
        }
    }

    private var isDone: Bool {
        if case .done = stage { true } else { false }
    }

    /// The screenshot as it will go, left out until it's ticked; once a send has begun it stays as it is. Small beside
    /// its box so the card stays about what goes; clicked, it opens larger, and clicked again it folds back.
    private func screenshotSection(_ shot: ContributeScreenshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Screenshot").font(.callout.weight(.medium)).foregroundStyle(.secondary).accessibilityHidden(true)
                Spacer(minLength: 8)
                if !shot.locked {
                    Button("Retake", action: retake).disabled(shot.taking)
                    if shot.picture != nil { Button("Remove", action: remove).disabled(shot.taking) }
                }
            }
            if let picture = shot.picture.flatMap(NSImage.init(data:)) {
                if shotOpen { thumbnail(picture, shot: shot, height: 220) }
                HStack(alignment: .top, spacing: 12) {
                    if !shotOpen { thumbnail(picture, shot: shot, height: 64) }
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Include screenshot", isOn: Binding(get: { shot.include }, set: include))
                            .toggleStyle(.checkbox).font(.callout).disabled(shot.locked || shot.taking)
                        Text(shot.isPublic == false
                             ? "Includes everything visible in this screenshot. Visible to people with access to your fork."
                             : "Includes everything visible in this screenshot. It's public: anyone can see it.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else if shot.taking {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Taking a screenshot…").foregroundStyle(.secondary) }.font(.callout)
            } else if shot.failed {
                Text("Couldn't take a screenshot. Bring the app window into view and try again.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func thumbnail(_ picture: NSImage, shot: ContributeScreenshot, height: CGFloat) -> some View {
        Button { shotOpen.toggle() } label: {
            Image(nsImage: picture).resizable().interpolation(.high).scaledToFit()
                .frame(maxWidth: shotOpen ? .infinity : 96, maxHeight: height, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                .overlay { if shot.taking { ProgressView().controlSize(.small) } }
        }
        .buttonStyle(.plain)
        .help(shotOpen ? "Make the screenshot smaller" : "Show the screenshot larger")
        .accessibilityLabel(shotOpen ? "Screenshot of the app, shown large" : "Screenshot of the app")
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
        case .failed where screenshot?.uploadFailed == true:
            Button("Cancel", role: .cancel, action: close).keyboardShortcut(.cancelAction)
            Button("Send Without Screenshot", action: sendWithout)
            Button("Retry Upload", action: send).keyboardShortcut(.defaultAction).disabled(!canSend)
        default:
            Button("Cancel", role: .cancel, action: close).keyboardShortcut(.cancelAction).disabled(busy && stage != .preparing)
            Button("Send Changes Back", action: send)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSend)
        }
    }
}

/// The screenshot a Send Changes Back card offers to put in its pull request: the app's own window, taken when the card
/// opens or on Retake, never a picture from before. It goes only when ticked, and only the one the card showed.
public struct ContributeScreenshot: Codable, Equatable {
    /// The picture as the card shows it: the one that goes, made smaller for the chat. Nil when there's none.
    public var picture: Data?
    /// Which picture goes (a digest of it): what the chat names when it sends, so one it didn't show never goes.
    public var digest: String?
    public var include: Bool
    public var taking: Bool
    /// The last try to take one gave nothing.
    public var failed: Bool
    /// Whether anyone can see it once it's up: the fork is public. Nil until that's known.
    public var isPublic: Bool?
    /// It couldn't be uploaded: the card offers to try again, or to send without it.
    public var uploadFailed: Bool
    /// A send has begun: the screenshot stays as it is, so a retry sends the same one.
    public var locked: Bool

    public init(picture: Data?, digest: String?, include: Bool, taking: Bool = false, failed: Bool = false, isPublic: Bool? = nil,
                uploadFailed: Bool = false, locked: Bool = false) {
        self.picture = picture
        self.digest = digest
        self.include = include
        self.taking = taking
        self.failed = failed
        self.isPublic = isPublic
        self.uploadFailed = uploadFailed
        self.locked = locked
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
