import AppKit
import LampSidebarKit
import SwiftUI

/// Ideas people sent from a wish's link: someone playing it typed what they'd change in the box under it, and the site
/// kept it for the wish's maker (`/api/wish-ideas`). Lamp asks for them with the link's secret now and every few
/// minutes, and the desk says quietly how many are new; nothing goes in the chat until the person picks one. The panel
/// shows them in the desk's window in place of its list, newest first: Build It asks the wish's chat for it, saying
/// where it came from; It's In lets it go, and the site writes to whoever asked to hear back (Lamp never sees where);
/// Dismiss lets it go quietly.
enum WishIdeas {
    /// The highest numbered idea seen of each wish's link, kept between launches: numbers only go up on one link, and a
    /// link made again (after one taken down) counts from one, so it's kept by the link as well as the wish.
    private static let seenKey = "LampIdeasSeen"
    private static func seenID(_ project: LampProject) -> String? { WishLink.kept(for: project).map { "\(project.id) \($0.id)" } }
    static func seen(_ project: LampProject) -> Int {
        guard let id = seenID(project) else { return 0 }
        return (UserDefaults.standard.dictionary(forKey: seenKey)?[id] as? Int) ?? 0
    }
    static func markSeen(_ number: Int, in project: LampProject) {
        guard let id = seenID(project) else { return }
        var all = UserDefaults.standard.dictionary(forKey: seenKey) ?? [:]
        guard number > (all[id] as? Int ?? 0) else { return }
        all[id] = number
        UserDefaults.standard.set(all, forKey: seenKey)
    }

    /// When it came, in words ("5 minutes ago"): the site writes the time with its milliseconds.
    static func when(_ at: String) -> String? {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = precise.date(from: at) ?? ISO8601DateFormatter().date(from: at) else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// What Build It asks the chat for: the idea in the sender's own words, marked as theirs.
    static func request(_ idea: WishLink.Idea, for project: LampProject, withPicture: Bool = false) -> String {
        let picture = withPicture ? ", with a picture of the app as they saw it" : ""
        return "Someone playing \(project.name) sent this idea from its link\(picture):\n\n\(idea.text)"
    }

    /// The bytes written into a `data:` address (the gallery's made-up ideas, and the site's own when it runs locally).
    static func inlineData(_ address: String) -> Data? {
        guard address.hasPrefix("data:"), let comma = address.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(address[address.index(after: comma)...]))
    }

    /// The idea's picture as bytes: from the site's store, or written into its address.
    static func pictureData(_ address: String) async -> Data? {
        if address.hasPrefix("data:") { return inlineData(address) }
        guard let url = URL(string: address), url.scheme == "https" else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200, NSImage(data: data) != nil else { return nil }
        return data
    }

}

extension Store {
    /// Every wish with a link, now and every five minutes while Lamp runs.
    func startCheckingIdeas() {
        guard ideasTimer == nil else { return }
        let check = { [weak self] in
            guard let self else { return }
            for project in self.projects where !project.isPart && WishLink.kept(for: project) != nil { self.checkIdeas(project) }
        }
        ideasTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { _ in Task { @MainActor in check() } }
        check()
    }

    func checkIdeas(_ project: LampProject) {
        guard let shared = WishLink.kept(for: project) else { return }
        Task {
            guard let found = try? await WishLink.ideas(for: shared) else { return }
            // A link taken down (or made again) while this was on its way: its ideas are gone with it, so an answer
            // about it mustn't bring them back.
            guard WishLink.kept(for: project)?.id == shared.id else { return }
            if ideas[project.id] != found { ideas[project.id] = found.isEmpty ? nil : found }
        }
    }

    /// Wishes with ideas sent, most new first.
    var wishesWithIdeas: [LampProject] {
        projects.filter { !(ideas[$0.id] ?? []).isEmpty }.sorted { newIdeas($0) > newIdeas($1) }
    }

    func newIdeas(_ project: LampProject) -> Int {
        let seen = WishIdeas.seen(project)
        return (ideas[project.id] ?? []).filter { $0.n > seen }.count
    }

    var newIdeasInAll: Int { projects.reduce(0) { $0 + newIdeas($1) } }

    /// The panel showed these: every idea up to the newest shown counts as seen.
    func sawIdeas(_ project: LampProject) {
        guard let newest = ideas[project.id]?.map(\.n).max(), newest > WishIdeas.seen(project) else { return }
        WishIdeas.markSeen(newest, in: project)
        objectWillChange.send()
    }

    /// Build It: the wish's chat opens and is asked for the idea, as the person's own request, with the app's picture
    /// the sender kept in, attached as a picture of the person's own would be.
    func buildIdea(_ idea: WishLink.Idea, in project: LampProject) {
        showChat(project.id)
        guard let address = idea.picture else { return send(WishIdeas.request(idea, for: project), to: project) }
        Task {
            var attached: [URL] = []
            if let data = await WishIdeas.pictureData(address) {
                // A folder of its own: another wish's idea of the same number, built before this one goes, keeps its own.
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                let file = folder.appendingPathComponent("Idea \(idea.n).jpg")
                if (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil,
                   (try? data.write(to: file)) != nil { attached = [file] }
            }
            send(WishIdeas.request(idea, for: project, withPicture: !attached.isEmpty), attachments: attached, to: project)
        }
    }

    /// It's In, or Dismiss: the idea goes from the link (built, the site first tells whoever asked), and from the panel
    /// once the site says so.
    func finishIdea(_ idea: WishLink.Idea, built: Bool, in project: LampProject) async -> Bool {
        guard let shared = WishLink.kept(for: project) else { return false }
        do { try await WishLink.removeIdea(idea.n, built: built, for: shared) } catch { return false }
        ideas[project.id]?.removeAll { $0.n == idea.n }
        if ideas[project.id]?.isEmpty == true { ideas[project.id] = nil }
        return true
    }
}

/// The ideas sent to one wish, in the desk's window in place of its list, with Back and a menu of the wishes that have
/// some. Each is its sender's words, when it came, and Build It, It's In and Dismiss.
struct IdeasPanel: View {
    @EnvironmentObject private var store: Store
    let wish: String
    let back: () -> Void
    /// The gallery's made-up app and ideas, in place of the store's.
    var preview: (project: LampProject, ideas: [WishLink.Idea], new: Set<Int>)? = nil

    /// Those new when the panel opened, which stay marked while it's open.
    @State private var newHere: Set<Int> = []
    /// Asked of the chat, or being let go, by number: for the line's buttons.
    @State private var built: Set<Int> = []
    @State private var finishing: Set<Int> = []
    @State private var failed: Int?

    private var project: LampProject? { preview?.project ?? store.projects.first { $0.id == wish } }
    private var shown: [WishLink.Idea] { (preview?.ideas ?? store.ideas[wish] ?? []).sorted { $0.n > $1.n } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Paper.rule)
            if shown.isEmpty {
                Spacer()
                Text("No ideas here right now.").foregroundStyle(Paper.muted)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(shown) { line($0) }
                    }
                    .padding(18)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Paper.panel)
        .onAppear {
            if let preview { newHere = preview.new; return }
            guard let project else { return }
            let seen = WishIdeas.seen(project)
            newHere = Set(shown.filter { $0.n > seen }.map(\.n))
            store.sawIdeas(project)
            store.checkIdeas(project)
        }
        .onChange(of: shown.map(\.n)) { if preview == nil, let project { store.sawIdeas(project) } }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: back) { Label("Back", systemImage: "chevron.left") }
                .buttonStyle(PaperButtonStyle(.outline, height: 28))
                .keyboardShortcut(.cancelAction)
            if let project { AppIcon(project: project, size: 30) }
            Menu {
                ForEach(store.wishesWithIdeas, id: \.id) { other in
                    let count = store.newIdeas(other)
                    Button(count > 0 ? "\(other.name) · \(count) new" : other.name) { store.ideasOpen = other.id }
                }
            } label: {
                Text(project?.name ?? "Ideas").font(.system(size: 17, weight: .bold)).foregroundStyle(Paper.ink)
            }
            .menuStyle(.borderlessButton).fixedSize()
            Text("\(shown.count) \(shown.count == 1 ? "idea" : "ideas") from people playing it")
                .font(.system(size: 13)).foregroundStyle(Paper.muted)
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private func finish(_ idea: WishLink.Idea, built: Bool) {
        guard preview == nil, let project, !finishing.contains(idea.n) else { return }
        finishing.insert(idea.n)
        failed = nil
        Task {
            if !(await store.finishIdea(idea, built: built, in: project)) { failed = idea.n }
            finishing.remove(idea.n)
        }
    }

    private func line(_ idea: WishLink.Idea) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if newHere.contains(idea.n) {
                    Text("NEW").font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(Paper.ink)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Paper.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                }
                Text(verbatim: [WishIdeas.when(idea.at), idea.wantsNews == true ? "wants to hear when it's in" : nil].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11.5)).foregroundStyle(Paper.muted).lineLimit(1).truncationMode(.middle)
            }
            Text(verbatim: idea.text).font(.system(size: 14)).foregroundStyle(Paper.ink).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let picture = idea.picture { IdeaPicture(address: picture) }
            HStack(spacing: 8) {
                if built.contains(idea.n) {
                    Label("Asked in the chat", systemImage: "checkmark").font(.system(size: 12.5)).foregroundStyle(Paper.muted)
                } else {
                    Button("Build It") {
                        guard preview == nil, let project else { return }
                        built.insert(idea.n)
                        store.buildIdea(idea, in: project)
                    }
                    .buttonStyle(PaperButtonStyle(.ink, height: 28))
                }
                Button("It's In") { finish(idea, built: true) }
                    .buttonStyle(PaperButtonStyle(.outline, height: 28))
                    .disabled(finishing.contains(idea.n))
                    .help(idea.wantsNews == true ? "Takes it off the list, emails them that it's in, and tells them on the link's page" : "Takes it off the list, and tells them on the link's page")
                Button("Dismiss") { finish(idea, built: false) }
                    .buttonStyle(PaperButtonStyle(.outline, height: 28))
                    .disabled(finishing.contains(idea.n))
                    .help("Takes it off the list. They aren't told.")
                if failed == idea.n {
                    Text("Couldn't reach lamp.dev. Try again.").font(.system(size: 12)).foregroundStyle(Paper.muted)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Paper.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Paper.rule))
    }
}

/// The app as the sender saw it when they opened the box, small under their idea; a click shows it full size.
private struct IdeaPicture: View {
    let address: String
    @State private var image: NSImage?
    @State private var large = false

    init(address: String) {
        self.address = address
        // One written into its address is there at once, the gallery's drawn without waiting.
        _image = State(initialValue: WishIdeas.inlineData(address).flatMap(NSImage.init(data:)))
    }

    var body: some View {
        Group {
            if let image {
                Button { large = true } label: {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 240, maxHeight: 150, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Paper.rule))
                }
                .buttonStyle(.plain)
                .help("The app as they saw it")
                .popover(isPresented: $large) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: 900, maxHeight: 600)
                }
            }
        }
        .task(id: address) { if image == nil { image = await WishIdeas.pictureData(address).flatMap(NSImage.init(data:)) } }
    }
}

extension Gallery {
    /// The desk's panel of ideas sent from a link, from made-up ideas to a made-up app.
    static let ideaEntries: [Entry] = [
        ideas("Ideas from people playing it"),
        ideas("Ideas, the narrowest window", width: 540),
        ideas("No ideas left", ideas: []),
    ]

    private static func ideas(_ name: String, ideas: [WishLink.Idea]? = nil, width: CGFloat = 940) -> Entry {
        Entry(group: "Sent to you", name: name) {
            let project = LampProject(id: "gallery-harbor-racer", name: "Harbor Racer", exe: "HarborRacer", dir: URL(fileURLWithPath: "/nonexistent"))
            let now = Date()
            let at = { (hours: Double) in ISO8601DateFormatter().string(from: now.addingTimeInterval(-hours * 3600)) }
            let made = ideas ?? [
                WishLink.Idea(n: 3, text: "Rain that makes the roads slippery", wantsNews: true, at: at(0.3), picture: madeUpPicture()),
                WishLink.Idea(n: 2, text: "Let me paint my car any color I want, with stripes and a number on the doors like a real race car.", wantsNews: nil, at: at(5)),
                WishLink.Idea(n: 1, text: "More boats in the harbor", wantsNews: nil, at: at(30)),
            ]
            return AnyView(IdeasPanel(wish: project.id, back: {}, preview: (project, made, [3]))
                .frame(width: width, height: 600)
                .background(Paper.page)
                .environmentObject(Store.shared))
        }
    }

    /// A made-up picture of a game, as a `data:` address: a dusk sky over a harbor road.
    private static func madeUpPicture() -> String? {
        let image = NSImage(size: NSSize(width: 480, height: 300), flipped: false) { rect in
            NSGradient(starting: NSColor(red: 0.98, green: 0.62, blue: 0.36, alpha: 1), ending: NSColor(red: 0.22, green: 0.27, blue: 0.52, alpha: 1))?
                .draw(in: rect, angle: 90)
            NSColor(red: 0.12, green: 0.30, blue: 0.42, alpha: 1).setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: rect.width, height: 110)).fill()
            NSColor(white: 0.18, alpha: 1).setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 40, width: rect.width, height: 40)).fill()
            NSColor(red: 0.95, green: 0.78, blue: 0.20, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 190, y: 52, width: 90, height: 28), xRadius: 8, yRadius: 8).fill()
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return nil }
        return "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
    }
}
