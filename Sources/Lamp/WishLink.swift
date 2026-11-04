import AppKit
import SwiftUI
import CryptoKit
import LampSidebarKit

/// A wish shared as a link (lamp.dev/w/<id>): the idea leaves the Mac, as the person confirmed it on the Share Link card
/// (`WishLinkCard`): the wish's name, its line, its words and, if they keep them, a picture of it and its icon. Whoever
/// opens the link makes their own version from the words, through the site's hand-off (`Wish`). If the person ticks it,
/// the wish itself goes too, as the file Share… makes (`Sharing.export`, with its checks), so someone with Lamp can open
/// that exact one, reviewed as any shared file is (`uploadFile`). Never the chat or the app's data. The site's side is
/// site/lib/shared-wishes.js; the two must agree on the limits.
///
/// The link can be changed or taken down later only with the secret the site gave when it was made, which Lamp keeps
/// in its own folder, never in the app's, where the agent's commands read.
enum WishLink {
    /// The most each piece may hold, in characters. The card holds the sharer to them, so the site never refuses.
    enum Limit {
        static let name = 60
        static let by = 60
        static let line = 140
        static let words = 2000
        /// The changes Lamp suggests for the wish (`RemixSuggestions`), which the page offers to remix with.
        static let ideas = 3
        static let idea = 100
        /// What's new in each release (`WishReleases`): the most releases a link keeps, the lines in one, and a line's
        /// characters.
        static let releases = 30
        static let releaseLines = 5
        static let releaseLine = 120
        /// The wish's file goes in parts of at most this many bytes (a request to the site's function holds 4.5 MB), and
        /// is at most `fileTotal`.
        static let filePart = 3_000_000
        static let fileTotal = 48_000_000
        /// The page the link plays may unpack to this much (`PAGE_LIMITS` on the site): a big 3D game's data packs small.
        static let pageUnpacked = 128_000_000
    }
    /// The picture is sent as a JPEG this many pixels on its long side at most, the icon as a PNG of this side.
    static let pictureSide: CGFloat = 1600
    static let iconSide = 256

    static var endpoint: URL {
        // A development build can share to the site's dev server (`npm run dev`), which keeps shared wishes in memory.
        if Edition.isDev, let value = ProcessInfo.processInfo.environment["LAMP_WISH_LINK_ENDPOINT"],
           let url = URL(string: value), url.scheme == "http",
           ["127.0.0.1", "localhost", "[::1]"].contains(url.host ?? "") { return url }
        return URL(string: "https://lamp.dev/api/wishes")!
    }

    /// What the link shows, as the sharer left it on the card.
    struct Words: Codable, Equatable {
        var name: String
        /// Who shared it, as the page names them under the wish's name; empty for nobody. Nil in links from before.
        var by: String? = nil
        var line: String
        var words: String
        /// The changes Lamp suggests for it, the page's to offer. Nil in links from before.
        var ideas: [String]? = nil
        /// The shape its page plays in (`Publish.pageShape`): "fill", or its width over its height. Nil for a wish with no
        /// page, and in links from before.
        var shape: String? = nil
        /// Which picture goes with it (a digest of it), or none.
        var picture: String?
        /// The wish's file goes with it. Nil in links from before files could go.
        var file: Bool?
    }

    /// A link that's out, with what it shows and the secret that changes it.
    struct Shared: Codable, Equatable {
        var id: String
        var url: URL
        var secret: String
        var shown: Words
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: What Lamp keeps

    /// Each wish's link, by its instance (so a rename keeps it), in Lamp's own folder, readable only by this user.
    private static var keptURL: URL { Edition.supportFolder.appendingPathComponent("Wish Links.json") }

    static func kept(for project: LampProject) -> Shared? { readKept()[key(project)] }

    static func keep(_ shared: Shared?, for project: LampProject) {
        var all = readKept()
        all[key(project)] = shared
        guard let data = try? JSONEncoder().encode(all) else { return }
        try? FileManager.default.createDirectory(at: keptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: keptURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keptURL.path)
    }

    private static func key(_ project: LampProject) -> String { project.instance.isEmpty ? project.id : project.instance }

    private static func readKept() -> [String: Shared] {
        guard let data = try? Data(contentsOf: keptURL) else { return [:] }
        return (try? JSONDecoder().decode([String: Shared].self, from: data)) ?? [:]
    }

    // MARK: What the card starts from

    /// The words a link starts with: the wish's first request, as the person asked for it, or for a wish nobody asked
    /// for in words (one of Lamp's starters) its line.
    @MainActor static func firstRequest(of project: LampProject, store: Store) -> String {
        let lines = store.logs[project.id]
            ?? LogLine.readChat(project.dir.appendingPathComponent(".lamp/chat.json"))?.lines ?? []
        let request = lines.first { $0.kind == .user && $0.fromCard != true && $0.byLamp != true && !$0.text.trimmed.isEmpty }
        return clip(request?.text.trimmed ?? line(of: project), Limit.words)
    }

    /// The picture the desk shows of the wish, read as the app's own file, or else its one app's when that's in a part
    /// of its own (a game in its folder): nil when there's none.
    static func picture(of project: LampProject) -> Data? {
        for app in [project] + [Publish.pageApp(project)].compactMap({ $0 }).filter({ $0.dir != project.dir }) {
            if let data = AppFile.read(Runtime.previewURL(app), in: project), NSImage(data: data) != nil { return data }
        }
        return Starters.shippedPreview(of: project).flatMap { try? Data(contentsOf: $0) }
    }

    static func line(of project: LampProject) -> String { clip(AppDescription.description(of: project) ?? "", Limit.line) }

    static func clip(_ text: String, _ limit: Int) -> String { String(text.prefix(limit)) }

    // MARK: Sending

    /// The picture as it's sent: a JPEG no larger than it needs to be, which also leaves behind whatever the file
    /// carried besides its pixels.
    static func jpeg(_ image: NSImage) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1, pictureSide / CGFloat(max(cg.width, cg.height)))
        let width = max(1, Int((CGFloat(cg.width) * scale).rounded())), height = max(1, Int((CGFloat(cg.height) * scale).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(.white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let small = context.makeImage() else { return nil }
        for quality in [0.82, 0.7, 0.55] {
            if let data = NSBitmapImageRep(cgImage: small).representation(using: .jpeg, properties: [.compressionFactor: quality]),
               data.count <= 1_400_000 { return data }
        }
        return nil
    }

    /// The icon as it's sent: a square PNG of `iconSide`.
    static func iconPNG(_ data: Data?) -> Data? {
        guard let data, let cg = NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: iconSide, height: iconSide, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(cg, in: CGRect(x: 0, y: 0, width: iconSide, height: iconSide))
        return context.makeImage().flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
    }

    // A redirect must not hand the wish, or the secret, to another address.
    private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }()

    /// Shares the wish, or changes what its link shows, and answers the link as it is now. `releases` is what's new in
    /// each version released, as `WishReleases.shown` gives it.
    static func publish(_ words: Words, picture: Data?, icon: Data?, releases: [[String: Any]] = [], replacing earlier: Shared?) async throws -> Shared {
        var body: [String: Any] = ["name": words.name.trimmed, "line": words.line.trimmed, "words": words.words.trimmed, "releases": releases]
        if let by = words.by?.trimmed, !by.isEmpty { body["by"] = by }
        if let ideas = words.ideas, !ideas.isEmpty { body["ideas"] = ideas }
        if let shape = words.shape { body["shape"] = shape == "fill" ? shape : Double(shape) ?? NSNull() }
        body["picture"] = picture?.base64EncodedString() ?? NSNull()
        body["icon"] = icon?.base64EncodedString() ?? NSNull()
        var request = URLRequest(url: earlier.map { address(for: $0.id) } ?? endpoint)
        request.httpMethod = earlier == nil ? "POST" : "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let earlier { request.setValue("Bearer \(earlier.secret)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, status) = try await send(request)
        // A change keeps the link; its address follows the wish's name, so a rename shows in it (the old one still works).
        if let earlier, status == 200 {
            let answer = (try? JSONSerialization.jsonObject(with: data)) as? [String: String]
            let link = answer?["url"].flatMap(URL.init(string:)).flatMap { $0.scheme == endpoint.scheme && $0.host == endpoint.host ? $0 : nil }
            return Shared(id: earlier.id, url: link ?? earlier.url, secret: earlier.secret, shown: words)
        }
        // The link is gone from the site (taken down there): a new one takes its place.
        if earlier != nil, status == 404 { return try await publish(words, picture: picture, icon: icon, releases: releases, replacing: nil) }
        guard status == 201, let answer = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let id = answer["id"], let link = answer["url"].flatMap(URL.init(string:)), let secret = answer["secret"],
              link.scheme == endpoint.scheme, link.host == endpoint.host else { throw failure(status) }
        return Shared(id: id, url: link, secret: secret, shown: words)
    }

    /// What a followed link has now (`latest` in lib/shared-wishes.js): its name, who it's by (nil for nobody, and from
    /// a site from before it said), its file's version (0 with no file), and the file's address. Nil when it can't be
    /// asked, or is gone. Asked with nothing of the person's.
    struct Latest: Equatable {
        let name: String?
        var by: String? = nil
        let version: Int
        let file: URL?
    }

    static func latest(_ id: String) async -> Latest? {
        guard let answered = try? await send(URLRequest(url: address(for: id))), answered.1 == 200,
              let answer = try? JSONSerialization.jsonObject(with: answered.0) as? [String: Any],
              (answer["format"] as? Int) == 1, let version = answer["version"] as? Int else { return nil }
        // The file only from where the site keeps them: https, never this Mac or an address the answer could pick.
        let file = (answer["file"] as? String).flatMap(URL.init(string:)).flatMap { url in
            url.scheme == "https" || (url.scheme == "data" && endpoint.scheme == "http") ? url : nil
        }
        let by = (answer["by"] as? String).map { clip($0.trimmed, Limit.by) }?.nilIfEmpty
        return Latest(name: answer["name"] as? String, by: by, version: version, file: file)
    }

    /// Where the wish's file goes: beside the link's API (`site/api/wish-file.js`). `page` is its playable page instead.
    private static func fileAddress(for id: String, part: Int? = nil, of count: Int? = nil, page: Bool = false) -> URL {
        var parts = URLComponents(url: endpoint.deletingLastPathComponent().appendingPathComponent("wish-file"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "id", value: id)]
            + (part.map { [URLQueryItem(name: "part", value: String($0)), URLQueryItem(name: "of", value: String(count ?? 1))] } ?? [])
            + (page ? [URLQueryItem(name: "what", value: "page")] : [])
        return parts.url!
    }

    /// The wish's page, to play or use right on its link's page (a web app's, a web game's, a screen's: `Publish.hasPage`),
    /// zipped: the page Put on GitHub puts on GitHub Pages (`Publish.copyPage`), what it saves kept under the link
    /// (`LAMP_PAGE_SCOPE`), searched for keys and secrets as that one is. Nil for a wish with no such page.
    static func playablePage(of project: LampProject, id: String) throws -> Data? {
        guard Publish.hasPage(project) else { return nil }
        let fm = FileManager.default
        let work = Sharing.workFolder.appendingPathComponent("lamp-link-page-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: work) }
        let site = work.appendingPathComponent("page")
        _ = try Publish.copyPage(of: project, into: site, scope: "w-\(id)")
        try? fm.removeItem(at: site.appendingPathComponent(".nojekyll"))
        if let leak = ShareCheck.secrets(in: site, known: Sharing.knownSecrets(project)).first {
            throw Failure(message: "\(project.name)'s page can't go with its link: it holds a key or a password, in \(leak). Ask Lamp to take it out.")
        }
        // Counted as the site counts it, unpacked and without hidden files, so a page it would turn down isn't sent.
        if unpackedSize(of: site) > Limit.pageUnpacked {
            throw Failure(message: "\(project.name) is too big to play on its link (over \(Limit.pageUnpacked / 1_000_000) MB), so the link shows its picture.")
        }
        let zip = work.appendingPathComponent("page.zip")
        let made = Process()
        made.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        made.arguments = ["-c", "-k", "--norsrc", site.path, zip.path]
        try made.run()
        made.waitUntilExit()
        guard made.terminationStatus == 0 else { throw Failure(message: "Lamp couldn't prepare \(project.name)'s page.") }
        return try Data(contentsOf: zip)
    }

    /// What a folder's files come to, leaving out hidden ones as the site does.
    private static func unpackedSize(of folder: URL) -> Int {
        let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles])
        var total = 0
        while let file = walk?.nextObject() as? URL {
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true else { continue }
            total += values.fileSize ?? 0
        }
        return total
    }

    /// Sends the wish's file with its link, in parts, and has the site put them together in place of any file it had.
    /// `page` sends its playable page (`playablePage`), which the site unpacks and serves on the link's page.
    static func uploadFile(_ data: Data, for shared: Shared, page: Bool = false) async throws {
        guard data.count <= Limit.fileTotal else {
            throw Failure(message: page ? "This app's page is too big to play on its link (over \(Limit.fileTotal / 1_000_000) MB)."
                          : "This app is too big to go with its link (over \(Limit.fileTotal / 1_000_000) MB).")
        }
        let count = max(1, (data.count + Limit.filePart - 1) / Limit.filePart)
        for n in 0..<count {
            var request = URLRequest(url: fileAddress(for: shared.id, part: n, of: count, page: page))
            request.httpMethod = "PUT"
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(shared.secret)", forHTTPHeaderField: "Authorization")
            request.httpBody = data.subdata(in: (n * Limit.filePart)..<min(data.count, (n + 1) * Limit.filePart))
            let (_, status) = try await send(request)
            guard status == 204 else { throw fileFailure(status, page: page) }
        }
        var finish = URLRequest(url: fileAddress(for: shared.id, page: page))
        finish.httpMethod = "POST"
        finish.setValue("Bearer \(shared.secret)", forHTTPHeaderField: "Authorization")
        let (_, status) = try await send(finish)
        guard status == 200 else { throw fileFailure(status, page: page) }
    }

    private static func fileFailure(_ status: Int, page: Bool) -> Failure {
        guard [400, 409, 413].contains(status) else { return failure(status) }
        return Failure(message: page ? "lamp.dev couldn't take this app's page to play, so its link shows its picture. Try again in a moment."
                       : "lamp.dev couldn't take this app's file. Try again in a moment.")
    }

    /// Takes the wish's file away from its link, which keeps showing the idea, and its page with it. `page` takes only
    /// the page away.
    static func removeFile(for shared: Shared, page: Bool = false) async throws {
        var request = URLRequest(url: fileAddress(for: shared.id, page: page))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(shared.secret)", forHTTPHeaderField: "Authorization")
        let (_, status) = try await send(request)
        guard status == 204 || status == 404 else { throw failure(status) }
    }

    /// Takes the link down: the page says the wish isn't shared any more. A link the site no longer has is down already.
    static func remove(_ shared: Shared) async throws {
        var request = URLRequest(url: address(for: shared.id))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(shared.secret)", forHTTPHeaderField: "Authorization")
        let (_, status) = try await send(request)
        guard status == 204 || status == 404 else { throw failure(status) }
    }

    private static func address(for id: String) -> URL {
        var parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "id", value: id)]
        return parts.url!
    }

    private static func send(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw Failure(message: (error as? URLError)?.code == .notConnectedToInternet
                          ? "You're offline. Try again when you're connected." : "Lamp couldn't reach lamp.dev. Try again in a moment.")
        }
    }

    private static func failure(_ status: Int) -> Failure {
        switch status {
        case 429: Failure(message: "Too many apps were shared from here just now. Try again later.")
        case 400, 413: Failure(message: "lamp.dev couldn't take this app. Try a shorter one, or leave out the picture.")
        default: Failure(message: "lamp.dev couldn't share this app right now. Try again in a moment.")
        }
    }
}

/// The Share Link card of each wish while it's open, in a window of its own (`WishLinkWindows`). One card per wish:
/// opened from either chat or the desk, it's the same card, so what's typed on it and the link it makes are the same.
@MainActor final class WishLinkCards: ObservableObject {
    static let shared = WishLinkCards()

    struct Card {
        var values: WishLinkCard.Values
        /// The picture as read from the app's folder, and its digest, which says whether the link shows this one.
        var picture: Data? { didSet { image = picture.flatMap(NSImage.init(data:)) } }
        var pictureDigest: String?
        var icon: Data? { didSet { iconImage = icon.flatMap(NSImage.init(data:)) } }
        /// Both as drawn, made once rather than at every keystroke.
        private(set) var image: NSImage?
        private(set) var iconImage: NSImage?
        var shared: WishLink.Shared?
        /// The changes Lamp suggests for the wish, as it has them now: they go with the link, not shown on the card.
        var ideas: [String] = []
        /// The shape the wish's page plays in, as `Words.shape` keeps it; nil for a wish with no page.
        var shape: String?
        var stage: WishLinkCard.Stage = .editing
        var copied = false
        var retaking = false
        /// Lamp is writing what's new for the release (`WishReleases.write`).
        var writingNotes = false
        /// The app's repository on GitHub, which a release goes to too while its box is ticked (`GitHubRelease`), or why
        /// it can't from here.
        var gitHub: GitHubRelease.Target?
        var gitHubNote: String?
        var gitHubStage: WishLinkCard.GitHubStage?
        /// The release whose GitHub half failed, for Try GitHub Again.
        var gitHubRetry: GitHubRelease.Version?

        /// What the link would show with what's on the card.
        var words: WishLink.Words {
            // What the page offers to make their own version from: what it does, as the card says it, and the wish's
            // first request only when that's empty. The card no longer shows the words themselves: the link shares the
            // wish, not a message.
            WishLink.Words(name: values.name.trimmed, by: values.by.trimmed, line: values.line.trimmed,
                           words: values.line.trimmed.isEmpty ? values.words.trimmed : values.line.trimmed,
                           ideas: ideas.isEmpty ? nil : ideas, shape: shape,
                           picture: pictureDigest, file: values.includeFile ? true : nil)
        }
        /// A link that carries the wish is always worth sending again: the file is the wish as it is now. So is one with
        /// something to say about what's new.
        var changed: Bool { shared?.shown != words || values.includeFile || !values.notes.trimmed.isEmpty }
    }

    @Published private(set) var cards: [String: Card] = [:]

    func card(for project: LampProject) -> Card? { cards[project.id] }

    /// Opens the card in its own window, or brings that window forward.
    func open(_ project: LampProject) {
        defer { WishLinkWindows.shared.show(project) }
        guard cards[project.id] == nil else { return }
        let shared = WishLink.kept(for: project)
        let picture = WishLink.picture(of: project)
        let digest = picture.map(Self.digest)
        // The link is called what the wish is called, now: it isn't asked on the card.
        let name = WishLink.clip(project.title, WishLink.Limit.name)
        // The wish itself always goes with its link when its kind can go as a file: the link shares the wish.
        let values = shared.map { WishLinkCard.Values(name: name, by: $0.shown.by ?? WishLink.sharer, line: $0.shown.line, words: $0.shown.words,
                                                      includeFile: Self.canIncludeFile(project)) }
            ?? WishLinkCard.Values(name: name, by: WishLink.sharer, line: WishLink.line(of: project), words: WishLink.firstRequest(of: project, store: Store.shared),
                                   includeFile: Self.canIncludeFile(project))
        var card = Card(values: values, pictureDigest: digest, shared: shared)
        card.shape = Publish.pageShape(project).map { if case .ratio(let ratio) = $0 { String(format: "%.4f", ratio) } else { "fill" } }
        card.ideas = (RemixSuggestions.load(project) ?? []).prefix(WishLink.Limit.ideas).map(\.text)
            .map { $0.trimmed }.filter { !$0.isEmpty && $0.count <= WishLink.Limit.idea }
        card.picture = picture
        // A link that's out is released again: Lamp writes what's new since the last release, for the person to change.
        card.writingNotes = shared != nil
        cards[project.id] = card
        Task {
            let icon = await Sharing.sharedIcon(of: project)
            cards[project.id]?.icon = icon
        }
        Task {
            switch await GitHubRelease.find(project) {
            case .ready(let target): cards[project.id]?.gitHub = target
            case .note(let note): cards[project.id]?.gitHubNote = note
            case nil: break
            }
        }
        if shared != nil {
            Task {
                let lines = await WishReleases.write(for: project)
                guard cards[project.id]?.writingNotes == true else { return }
                cards[project.id]?.writingNotes = false
                // Only into a field nobody has started typing in.
                if cards[project.id]?.values.notes.trimmed.isEmpty == true { cards[project.id]?.values.notes = lines.joined(separator: "\n") }
            }
        }
    }

    /// Whether the wish can go with its link as a file: each of its apps' kinds can be shared as one (a Roku app can't yet).
    static func canIncludeFile(_ project: LampProject) -> Bool {
        var wish = project
        wish.partFolders = Parts.folders(in: project.dir)
        return ((wish.holdsApp ? [wish] : []) + Parts.load(wish)).allSatisfy { app in
            app.platform.target.recipe.shareRefusal == nil && !(app.platform == .game && GameKit.engine(app) != .web)
        }
    }

    func update(_ project: LampProject, values: WishLinkCard.Values) {
        guard cards[project.id]?.values != values else { return }
        cards[project.id]?.values = values
        cards[project.id]?.copied = false
        if case .failed = cards[project.id]?.stage { cards[project.id]?.stage = .editing }
    }

    func close(_ project: LampProject) {
        cards[project.id] = nil
        WishLinkWindows.shared.close(project)
    }

    /// Shares what's on the card, or releases what the wish is now with what's new in it, and copies the link.
    func share(_ project: LampProject) {
        guard let card = cards[project.id], card.stage != .sending, card.values.isComplete else { return }
        cards[project.id]?.stage = .sending
        cards[project.id]?.writingNotes = false
        let words = card.words
        // GitHub follows the link, with the same version and what's new, while its box is ticked.
        let toGitHub = card.values.alsoGitHub ? card.gitHub : nil
        cards[project.id]?.gitHubStage = nil
        cards[project.id]?.gitHubRetry = nil
        // A link's first share is where the first release's changes start, and says nothing itself.
        let notes = card.shared == nil ? [] : WishReleases.lines(from: card.values.notes)
        // A name changed on the card is the one the next link starts with.
        if let by = words.by, by != WishLink.sharer { WishLink.sharer = by }
        let source = card.picture
        let iconSource = card.icon
        Task {
            do {
                let (picture, icon) = await Task.detached(priority: .userInitiated) {
                    (source.flatMap(NSImage.init(data:)).flatMap(WishLink.jpeg), WishLink.iconPNG(iconSource))
                }.value
                var pageProblem: String?
                let release = WishReleases.Release(version: await Versions.head(project) ?? "", date: Date(), lines: notes)
                var shared = try await WishLink.publish(words, picture: picture, icon: icon,
                                                        releases: WishReleases.shown([release] + WishReleases.load(project)), replacing: card.shared)
                // Kept at once, with the file as the link had it so far: its secret is the only way to change it or take it
                // down, so a file that fails after this leaves a link the card can still stop.
                shared.shown.file = card.shared?.shown.file
                WishLink.keep(shared, for: project)
                // The link goes into the installed app too, for a Mac without Lamp (`RemixPanel`).
                Store.shared.refreshInstalled(project)
                cards[project.id]?.shared = shared
                // The wish itself, made as Share… makes it (with its checks), sent with the link; or taken away from a link
                // that carried it and shouldn't now.
                if words.file == true {
                    // Counted as carrying the file from the first part on: an upload cut short may have left parts, or a
                    // whole file whose answer was lost, so unticking later takes it away (`removeFile` clears both).
                    shared.shown.file = true
                    WishLink.keep(shared, for: project)
                // The link goes into the installed app too, for a Mac without Lamp (`RemixPanel`).
                Store.shared.refreshInstalled(project)
                    cards[project.id]?.shared = shared
                    let data = try await Task.detached(priority: .userInitiated) { () throws -> Data in
                        // With this release's lines, which are kept only once the file is up.
                        let file = try Sharing.export(project, releasing: WishReleases.Entry(date: release.date, lines: release.lines))
                        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
                        return try Data(contentsOf: file)
                    }.value
                    try await WishLink.uploadFile(data, for: shared)
                    // Its page, so whoever opens the link plays or uses it right there, before anything else. A page that
                    // can't go (too big, say) leaves the link working with its picture, and the card says why.
                    let id = shared.id
                    do {
                        if let page = try await Task.detached(priority: .userInitiated, operation: { try WishLink.playablePage(of: project, id: id) }).value {
                            try await WishLink.uploadFile(page, for: shared, page: true)
                        } else {
                            // No page now (an app added to the wish, say): the link goes back to its card.
                            try await WishLink.removeFile(for: shared, page: true)
                        }
                    } catch {
                        // The old page goes, so the link shows the picture as the card says; if it can't be taken away,
                        // the link still plays the earlier version, and the card says that instead.
                        do {
                            try await WishLink.removeFile(for: shared, page: true)
                            pageProblem = Self.problem(error)
                        } catch {
                            pageProblem = "\(project.name)'s page couldn't be updated on its link, so the link still plays its earlier version. Try again in a moment."
                        }
                    }
                } else if card.shared?.shown.file == true {
                    try await WishLink.removeFile(for: shared)
                }
                shared.shown = words
                WishLink.keep(shared, for: project)
                // The release is kept only once the wish itself went with it, so one that failed is tried again with its
                // lines, and the next release's changes start here. What's new goes into each of the wish's installed
                // apps, a Mac app in a part of the wish too.
                WishReleases.record(release, in: project)
                cards[project.id]?.values.notes = ""
                // The link goes into the installed app too, for a Mac without Lamp (`RemixPanel`).
                for app in [project] + Store.shared.apps(of: project).filter({ $0.id != project.id }) { Store.shared.refreshInstalled(app) }
                guard cards[project.id] != nil else { return }
                cards[project.id]?.shared = shared
                copy(project)
                if let toGitHub {
                    let version = GitHubRelease.Version(count: WishReleases.load(project).count, lines: notes)
                    await releaseOnGitHub(project, to: toGitHub, version: version, picture: source, then: pageProblem)
                } else {
                    cards[project.id]?.stage = pageProblem.map { .failed($0) } ?? .editing
                }
            } catch {
                // Nothing went to GitHub: it follows the link, so the card says so with the link's own problem.
                cards[project.id]?.stage = .failed(Self.problem(error) + (toGitHub == nil ? "" : " GitHub wasn't updated either."))
            }
        }
    }

    /// The release's GitHub half, after the link went up: the card stays busy until everything is on GitHub, then only
    /// GitHub's building of the page is waited for, with the card free again. `linkProblem` is what the card said of the
    /// link, kept beside whatever GitHub says.
    private func releaseOnGitHub(_ project: LampProject, to target: GitHubRelease.Target, version: GitHubRelease.Version, picture: Data?,
                                 then linkProblem: String?) async {
        let id = project.id
        let settled: @MainActor () -> Void = { [weak self] in
            guard self?.cards[id]?.stage == .sending else { return }
            self?.cards[id]?.stage = linkProblem.map { .failed($0) } ?? .editing
        }
        cards[id]?.gitHubStage = .working("Updating GitHub…")
        do {
            try await GitHubRelease.release(project, to: target, version: version, picture: picture,
                                            pushed: { Task { @MainActor in settled() } },
                                            step: { step in Task { @MainActor in WishLinkCards.shared.cards[id]?.gitHubStage = .working(step) } })
            settled()
            cards[id]?.gitHubStage = .done(version.tag)
        } catch {
            settled()
            cards[id]?.gitHubRetry = version
            // Said plainly, apart from the link, which works whatever happened here.
            cards[id]?.gitHubStage = .failed(error is GitHubRelease.TagFailure
                ? "The link and \(target.repo) are updated, but \(Self.problem(error))"
                : "The link is updated, but \(target.repo) on GitHub isn't: \(Self.problem(error))")
        }
    }

    /// Tries the GitHub half of the last release again, with the same version and what's new.
    func retryGitHub(_ project: LampProject) {
        guard let card = cards[project.id], card.stage != .sending, let target = card.gitHub, let version = card.gitHubRetry else { return }
        cards[project.id]?.stage = .sending
        cards[project.id]?.gitHubRetry = nil
        let linkProblem: String? = if case .failed(let problem) = card.stage { problem } else { nil }
        Task { await releaseOnGitHub(project, to: target, version: version, picture: card.picture, then: linkProblem) }
    }

    /// What the card says went wrong: the headline, and the why and what to do when there is one (a wish Lamp won't let
    /// go with its link says which license is missing or where the key is, and what to ask Lamp).
    static func problem(_ error: Error) -> String {
        ((error as? LocalizedError)?.recoverySuggestion).map { "\(error.localizedDescription) \($0)" } ?? error.localizedDescription
    }

    func copy(_ project: LampProject) {
        guard let url = cards[project.id]?.shared?.url else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.declareTypes([.URL, .string], owner: nil)
        (url as NSURL).write(to: board)
        board.setString(url.absoluteString, forType: .string)
        cards[project.id]?.copied = true
        // The copy button's tick is for a moment, so a second copy shows too.
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            cards[project.id]?.copied = false
        }
    }

    /// Takes the link down, and the card with it.
    func stop(_ project: LampProject) {
        guard let shared = cards[project.id]?.shared else { return }
        cards[project.id]?.stage = .sending
        Task {
            do {
                try await WishLink.remove(shared)
                WishLink.keep(nil, for: project)
                Store.shared.refreshInstalled(project)
                // Its window goes with it, as Cancel takes it.
                close(project)
            } catch {
                cards[project.id]?.stage = .failed(error.localizedDescription)
            }
        }
    }

    /// The app can take a new picture of itself while it's open on this Mac.
    func canRetake(_ project: LampProject) -> Bool { Store.shared.openOnMac.contains(project.id) && project.destination == .mac }

    /// A new picture of the app as it is now, from its front window.
    func retake(_ project: LampProject) {
        guard canRetake(project), cards[project.id]?.retaking == false else { return }
        cards[project.id]?.retaking = true
        let asked = Date()
        Runtime.requestScreenshots(of: project)
        Task {
            let taken = await Runtime.screenshots(of: project, since: asked).first
            let data = taken.flatMap { AppFile.read($0, in: project) }.flatMap { NSImage(data: $0) == nil ? nil : $0 }
            guard cards[project.id] != nil else { return }
            cards[project.id]?.retaking = false
            guard let data else { return }
            cards[project.id]?.picture = data
            cards[project.id]?.pictureDigest = Self.digest(data)
            cards[project.id]?.copied = false
        }
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

extension WishLink {
    static let cardLimits = WishLinkCard.Limits(name: Limit.name, line: Limit.line, words: Limit.words, by: Limit.by,
                                                 notes: Limit.releaseLines, note: Limit.releaseLine)

    /// The name a link says it's by: what the person last gave on the card, kept in Lamp's own settings; until they have,
    /// their name on this Mac, which they see on the card before anything goes.
    static var sharer: String {
        get { UserDefaults.standard.string(forKey: sharerKey) ?? clip(NSFullUserName(), Limit.by) }
        set { UserDefaults.standard.set(newValue, forKey: sharerKey) }
    }
    private static let sharerKey = "wishLinkSharer"
}
