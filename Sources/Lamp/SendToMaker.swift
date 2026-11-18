import AppKit
import LampSidebarKit
import SwiftUI

/// Send to <maker>…: an idea for the maker of the lamp.dev link a wish came from, with the person's changes. The words
/// are drafted from what changed since the wish arrived (as Release Update drafts What's New), a picture of the app goes
/// with them, and the wish itself goes as a copy shared privately on lamp.dev (the shared file with its versions, so the
/// maker can mix it in), which only the maker sees, through the idea. Sending again moves the same idea on to the wish as
/// it is now. For a wish from someone's repository on GitHub with no such link, the same Send to… opens a pull request there instead (`Contribute`); the site's side is "Ideas that carry a
/// change" in site/SHARED_WISHES.md, and the sending itself is lamp's (`sendToMaker` in cli/send.mjs).
@MainActor final class SendToMaker: ObservableObject {
    static let shared = SendToMaker()

    struct Card {
        var values: SendIdeaCard.Values
        var picture: Data?
        /// The maker's link this goes to, and the version of their file the wish starts from.
        var source: String
        var base: Int
        /// This opening of the card: what a preparation for an earlier one brings back is dropped.
        var token = UUID()
    }

    @Published private(set) var cards: [String: Card] = [:]
    /// Who each maker's link says it's by, by the link's id, asked as the share menu opens.
    @Published private(set) var makers: [String: String] = [:]

    /// The share menu's "Send to Sam…": for a wish that came from a lamp.dev link, its maker; else, for one from someone's
    /// repository on GitHub, the repository's owner, whose card opens a pull request there (`Contribute`); nil for any other.
    static func menuTitle(_ project: LampProject) -> String? {
        if let id = source(of: project)?.place.link { return title(shared.makers[id]) }
        if let repository = Contribute.origin(of: project) { return title(repository.owner) }
        return nil
    }

    func refreshMaker(_ project: LampProject) {
        guard let id = Self.source(of: project)?.place.link else { return }
        Task {
            guard let by = await WishLink.latest(id)?.by, makers[id] != by else { return }
            makers[id] = by
        }
    }

    /// The link a wish came from on lamp.dev, which Send to… sends to: the copy it started from, as it follows it.
    static func source(of project: LampProject) -> Following.Followed? {
        Following.followed(by: project).first { $0.startedFrom == true && $0.place.link != nil }
    }

    /// Who Send to… names: the link's maker as it last said, else nobody in particular.
    static func title(_ maker: String?) -> String {
        guard let maker = maker?.trimmed.nilIfEmpty else { return "Send to the Maker…" }
        return "Send to \(maker)…"
    }

    /// Send to…: an idea for the maker of the lamp.dev link the wish came from, or, for a wish from someone's repository on
    /// GitHub with no such link, the pull-request card (`ContributeCards`, in the chat's place).
    func open(_ project: LampProject) {
        guard let source = Self.source(of: project), let id = source.place.link else {
            if Contribute.canContribute(project) { Store.shared.sendChangesBack(project) }
            return
        }
        if cards[project.id] != nil { refreshAccount(project) }
        if cards[project.id] == nil {
            let earlier = Self.sent(for: project)
            cards[project.id] = Card(values: .init(name: project.name, maker: nil, words: "", stage: .drafting, includePicture: true,
                                                   includeChanges: true, account: nil, again: earlier?.source == id ? earlier?.n : nil,
                                                   noLicense: ShareCheck.warningLine(Credits.load(project))),
                                     picture: WishLink.picture(of: project), source: id, base: Int(source.brought ?? "") ?? 0)
            let token = cards[project.id]!.token
            Task { await prepare(project, id: id, token: token) }
        }
        SendToMakerWindows.shared.show(project)
    }

    /// Who the maker is (as their link says), the person's account, and the words Lamp drafts from what changed.
    private func prepare(_ project: LampProject, id: String, token: UUID) async {
        async let latest = WishLink.latest(id)
        async let account = try? WishLink.account()
        async let drafted = Self.draft(for: project)
        let (maker, signedIn, words) = await (latest, account, drafted)
        guard cards[project.id]?.token == token, cards[project.id]?.values.stage == .drafting else { return }
        cards[project.id]?.values.maker = maker?.by
        if let by = maker?.by { makers[id] = by }
        cards[project.id]?.values.account = signedIn.flatMap { $0 ?? nil }.flatMap { $0.confirmed == true ? $0.username : nil }
        if cards[project.id]?.values.words.isEmpty == true { cards[project.id]?.values.words = words }
        if cards[project.id]?.values.account == nil { cards[project.id]?.values.includeChanges = false }
        cards[project.id]?.values.stage = .ready
    }

    /// The person's username asked again, when the card comes forward: one set up from Set Up… since it opened turns
    /// Include my changes on, without the note being lost.
    func refreshAccount(_ project: LampProject) {
        guard let card = cards[project.id], card.values.account == nil, card.values.stage != .drafting else { return }
        Task {
            guard let found = (try? await WishLink.account()) ?? nil, found.confirmed == true, cards[project.id]?.values.account == nil else { return }
            let username = found.username
            cards[project.id]?.values.account = username
            cards[project.id]?.values.includeChanges = true
        }
    }

    /// The words Lamp offers: what the person changed since the wish arrived, said to the maker in a few plain lines.
    /// Empty when nothing changed or the helper can't answer; the person writes their own then.
    static func draft(for project: LampProject) async -> String {
        let changes = await WishReleases.changes(in: project)
        guard !changes.isEmpty else { return "" }
        let prompt = """
        Someone changed their copy of an app called \(project.name) and is sending the changes to the app's maker. \
        Write their note to the maker from what they asked for, oldest first below: one to four short sentences in the \
        first person, plain and friendly, about what a person using the app will notice ("I added rain that makes the \
        boats rock"). Never mention files, code, AI or Lamp.
        Reply as JSON: {"note": "…"}

        What they asked for:
        \(changes.map { "- \($0)" }.joined(separator: "\n"))
        """
        guard let (text, _) = try? await AppAI.complete(prompt: prompt, images: [], system: "", json: true, model: await AppAI.helperModel()),
              let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
              let note = (object["note"] as? String)?.trimmed else { return "" }
        return String(note.prefix(WishIdeasLimit.text))
    }

    func edit(_ project: LampProject, _ change: (inout SendIdeaCard.Values) -> Void) {
        guard cards[project.id]?.values.stage.isBusy == false else { return }
        change(&cards[project.id]!.values)
        if case .sent = cards[project.id]?.values.stage { cards[project.id]?.values.stage = .ready }
        if case .failed = cards[project.id]?.values.stage { cards[project.id]?.values.stage = .ready }
    }

    /// Not while sending; while the note is being drafted it closes, and what comes back is dropped (`prepare`).
    func close(_ project: LampProject) {
        guard cards[project.id]?.values.stage.isSending != true else { return }
        cards[project.id] = nil
        SendToMakerWindows.shared.close(project)
    }

    /// Send: the wish's shared file made (with its versions) when its changes go, the picture as a JPEG, and both handed
    /// to lamp with the words. What lamp.dev answered is kept, so the next send moves the same idea on.
    func send(_ project: LampProject) {
        guard var card = cards[project.id], !card.values.stage.isBusy, !card.values.words.trimmed.isEmpty else { return }
        card.values.stage = .sending("Sending…")
        cards[project.id] = card
        let values = card.values, picture = values.includePicture ? card.picture.flatMap(NSImage.init(data:)).flatMap(WishLink.ideaJPEG) : nil
        let earlier = Self.sent(for: project)
        Task {
            let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: work) }
            do {
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                var pictureFile: URL?
                if let picture {
                    pictureFile = work.appendingPathComponent("picture.jpg")
                    try picture.write(to: pictureFile!)
                }
                // The wish as it is now, as Share… makes it: with its versions for mixing (`MixHistory`) while that's on.
                let file = values.includeChanges ? try await Store.offMain { Result { try Sharing.export(project) } }.get() : nil
                defer { if let file { try? FileManager.default.removeItem(at: file) } }
                let source = card.source
                let sent = try await WishLink.sendIdea(source: source, text: values.words.trimmed, picture: pictureFile, file: file, base: card.base,
                                                       name: project.name, by: WishLink.sharer, earlier: values.includeChanges ? earlier : nil,
                                                       said: { line in
                    Task { @MainActor in if case .sending = self.cards[project.id]?.values.stage { self.cards[project.id]?.values.stage = .sending(line) } }
                }, madeCopy: { copy in
                    // Kept as soon as it's up, without an idea yet, so a send that fails after it sends to it again.
                    Task { @MainActor in Self.keep(WishLink.SentIdea(source: source, copy: copy, n: nil), for: project) }
                })
                if sent.copy != nil { Self.keep(sent, for: project) }
                cards[project.id]?.values.stage = .sent(again: values.includeChanges && earlier?.n == sent.n && earlier?.source == card.source)
                cards[project.id]?.values.again = sent.copy != nil ? sent.n : cards[project.id]?.values.again
            } catch {
                cards[project.id]?.values.stage = .failed((error as? LocalizedError)?.errorDescription ?? "Lamp couldn't send it. Try again.")
            }
        }
    }

    // MARK: What Lamp keeps

    /// Each wish's last send with its changes, by its instance, in Lamp's own folder, readable only by this user: the
    /// copy's secret stays out of the wish's folder.
    private static var keptURL: URL { Edition.supportFolder.appendingPathComponent("Sent Ideas.json") }
    private static func key(_ project: LampProject) -> String { project.instance.isEmpty ? project.id : project.instance }
    private static func readKept() -> [String: WishLink.SentIdea] {
        (try? Data(contentsOf: keptURL)).flatMap { try? JSONDecoder().decode([String: WishLink.SentIdea].self, from: $0) } ?? [:]
    }
    static func sent(for project: LampProject) -> WishLink.SentIdea? { readKept()[key(project)] }
    static func keep(_ sent: WishLink.SentIdea?, for project: LampProject) {
        var all = readKept()
        all[key(project)] = sent
        guard let data = try? JSONEncoder().encode(all) else { return }
        try? FileManager.default.createDirectory(at: keptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: keptURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keptURL.path)
    }
}

/// The most an idea's words hold (`IDEA_LIMITS.text` on the site).
enum WishIdeasLimit { static let text = 1000 }

extension WishLink {
    /// An idea's picture as it's sent: a JPEG within the site's `IDEA_LIMITS.picture`, smaller than a link's.
    static func ideaJPEG(_ image: NSImage) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        for side in [1600.0, 1200, 900] {
            let scale = min(1, side / Double(max(cg.width, cg.height)))
            let width = max(1, Int(Double(cg.width) * scale)), height = max(1, Int(Double(cg.height) * scale))
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            context.setFillColor(.white)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.interpolationQuality = .high
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let small = context.makeImage() else { return nil }
            for quality in [0.8, 0.65] {
                if let data = NSBitmapImageRep(cgImage: small).representation(using: .jpeg, properties: [.compressionFactor: quality]), data.count <= 390_000 { return data }
            }
        }
        return nil
    }
}

/// The Send to… card's own window, one per wish, as the Share Link card has (`WishLinkWindows`): opened from the chat's
/// Share button beside an app or in Lamp's panel, never in the chat's place.
@MainActor final class SendToMakerWindows: NSObject, NSWindowDelegate {
    static let shared = SendToMakerWindows()
    private var windows: [String: NSWindow] = [:]
    private var closingInternally = false

    func show(_ project: LampProject) {
        if windows[project.id] == nil {
            let content = NSHostingController(rootView: SendToMakerContent(project: project))
            content.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: content)
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = "Send \(project.title) to Its Maker"
            window.isMovableByWindowBackground = true
            window.backgroundColor = NSColor(Paper.page)
            window.delegate = self
            window.isReleasedWhenClosed = false
            window.center()
            windows[project.id] = window
        }
        NSApp.activate(ignoringOtherApps: true)
        windows[project.id]?.makeKeyAndOrderFront(nil)
    }

    func close(_ project: LampProject) {
        guard let window = windows.removeValue(forKey: project.id) else { return }
        closingInternally = true
        window.close()
        closingInternally = false
    }

    func windowShouldClose(_ window: NSWindow) -> Bool {
        guard let id = windows.first(where: { $0.value === window })?.key else { return true }
        return SendToMaker.shared.cards[id]?.values.stage.isSending != true
    }

    /// Back from Set Up… (or anywhere), the card asks again whether there's a username now.
    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, let id = windows.first(where: { $0.value === window })?.key,
              let project = Store.shared.projects.first(where: { $0.id == id }) else { return }
        SendToMaker.shared.refreshAccount(project)
    }

    func windowWillClose(_ notification: Notification) {
        guard !closingInternally, let window = notification.object as? NSWindow,
              let id = windows.first(where: { $0.value === window })?.key else { return }
        windows[id] = nil
        if let project = Store.shared.projects.first(where: { $0.id == id }) { SendToMaker.shared.close(project) }
    }
}

private struct SendToMakerContent: View {
    @ObservedObject private var model = SendToMaker.shared
    let project: LampProject

    var body: some View {
        if let card = model.cards[project.id] {
            SendIdeaCard(values: card.values, picture: card.picture.flatMap(NSImage.init(data:)),
                         edit: { change in model.edit(project, change) },
                         send: { model.send(project) },
                         setUp: { WishLinkCards.shared.open(project) },
                         close: { model.close(project) })
                .frame(width: 440)
        }
    }
}

/// The card: the words to the maker, a picture of the app and whether the person's changes go, then Send. Plain values, so the gallery draws it as people see it.
struct SendIdeaCard: View {
    struct Values: Equatable {
        var name: String
        /// Who the link says it's by, once asked.
        var maker: String?
        var words: String
        var stage: Stage
        var includePicture: Bool
        var includeChanges: Bool
        /// The person's lamp.dev username, confirmed; nil without one, and changes can't go then.
        var account: String?
        /// The idea an earlier send made, which this one moves on.
        var again: Int?
        /// Work in it that came with no license, said as a line among the card's facts as Share Link says it.
        var noLicense: String? = nil
    }

    enum Stage: Equatable {
        case drafting, ready, sending(String), sent(again: Bool), failed(String)
        var isBusy: Bool { isSending || self == .drafting }
        var isSending: Bool { if case .sending = self { true } else { false } }
    }

    let values: Values
    let picture: NSImage?
    let edit: ((inout Values) -> Void) -> Void
    let send: () -> Void
    let setUp: () -> Void
    let close: () -> Void

    private var maker: String { values.maker?.trimmed.nilIfEmpty ?? "its maker" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(values.maker?.trimmed.nilIfEmpty.map { "Send to \($0)" } ?? "Send to the Maker")
                .font(.system(size: 18, weight: .bold))
            Text("Only \(maker) sees your changes. They can try them and take what they like.")
                .font(.system(size: 13)).foregroundStyle(Paper.muted).fixedSize(horizontal: false, vertical: true)
            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(get: { values.words }, set: { text in edit { $0.words = String(text.prefix(WishIdeasLimit.text)) } }))
                    .font(.system(size: 13.5)).scrollContentBackground(.hidden)
                    .padding(6).frame(height: 110)
                    .background(Paper.card, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Paper.rule))
                    .disabled(values.stage.isBusy)
                if values.stage == .drafting {
                    Text("Writing it from what you changed…").font(.system(size: 13)).foregroundStyle(Paper.muted).padding(12)
                } else if values.words.isEmpty {
                    Text("What did you change, and why?").font(.system(size: 13.5)).foregroundStyle(Paper.muted).padding(12).allowsHitTesting(false)
                }
            }
            if let picture {
                HStack(alignment: .top, spacing: 10) {
                    Image(nsImage: picture).resizable().scaledToFit().frame(maxWidth: 120, maxHeight: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 6)).opacity(values.includePicture ? 1 : 0.4)
                    Toggle("Include this picture", isOn: Binding(get: { values.includePicture }, set: { on in edit { $0.includePicture = on } }))
                        .toggleStyle(.checkbox).font(.system(size: 13))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Include my changes", isOn: Binding(get: { values.includeChanges }, set: { on in edit { $0.includeChanges = on } }))
                    .toggleStyle(.checkbox).font(.system(size: 13)).disabled(values.account == nil)
                if values.account == nil, values.stage != .drafting {
                    HStack(spacing: 6) {
                        Text("Sending your changes needs a lamp.dev username.").font(.system(size: 12)).foregroundStyle(Paper.muted)
                        Button("Set Up…", action: setUp).buttonStyle(.link).font(.system(size: 12))
                    }
                }
                if values.includeChanges {
                    if let noLicense = values.noLicense {
                        Text(noLicense).font(.system(size: 12)).foregroundStyle(Paper.muted).fixedSize(horizontal: false, vertical: true).padding(.leading, 20)
                    }
                    if let again = values.again {
                        Text("Goes to your idea \(again) as a new version.").font(.system(size: 12)).foregroundStyle(Paper.muted).padding(.leading, 20)
                    }
                }
            }
            HStack(spacing: 8) {
                switch values.stage {
                case .sending(let line): ProgressView().controlSize(.small); Text(line).font(.system(size: 12.5)).foregroundStyle(Paper.muted).lineLimit(1)
                case .sent(let again): Label(again ? "Sent as a new version" : "Sent", systemImage: "checkmark").font(.system(size: 12.5)).foregroundStyle(Paper.muted)
                case .failed(let why): Text(why).font(.system(size: 12.5)).foregroundStyle(Paper.muted).fixedSize(horizontal: false, vertical: true)
                default: EmptyView()
                }
                Spacer()
                Button(isSent ? "Done" : "Cancel", action: close).buttonStyle(PaperButtonStyle(.outline)).disabled(values.stage.isSending)
                    .keyboardShortcut(.cancelAction)
                if !isSent {
                    Button("Send", action: send).buttonStyle(PaperButtonStyle(.ink))
                        .disabled(values.stage.isBusy || values.words.trimmed.isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .foregroundStyle(Paper.ink)
        .background(Paper.page)
    }

    private var isSent: Bool { if case .sent = values.stage { true } else { false } }
}
