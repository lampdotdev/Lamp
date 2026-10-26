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
        static let line = 140
        static let words = 2000
        /// The wish's file goes in parts of at most this many bytes (a request to the site's function holds 4.5 MB), and
        /// is at most `fileTotal`.
        static let filePart = 3_000_000
        static let fileTotal = 16_000_000
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
        var line: String
        var words: String
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

    /// The picture the desk shows of the wish, read as the app's own file: nil when there's none.
    static func picture(of project: LampProject) -> Data? {
        if let data = AppFile.read(Runtime.previewURL(project), in: project), NSImage(data: data) != nil { return data }
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

    /// Shares the wish, or changes what its link shows, and answers the link as it is now.
    static func publish(_ words: Words, picture: Data?, icon: Data?, replacing earlier: Shared?) async throws -> Shared {
        var body: [String: Any] = ["name": words.name.trimmed, "line": words.line.trimmed, "words": words.words.trimmed]
        body["picture"] = picture?.base64EncodedString() ?? NSNull()
        body["icon"] = icon?.base64EncodedString() ?? NSNull()
        var request = URLRequest(url: earlier.map { address(for: $0.id) } ?? endpoint)
        request.httpMethod = earlier == nil ? "POST" : "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let earlier { request.setValue("Bearer \(earlier.secret)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, status) = try await send(request)
        if let earlier, status == 200 { return Shared(id: earlier.id, url: earlier.url, secret: earlier.secret, shown: words) }
        // The link is gone from the site (taken down there): a new one takes its place.
        if earlier != nil, status == 404 { return try await publish(words, picture: picture, icon: icon, replacing: nil) }
        guard status == 201, let answer = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let id = answer["id"], let link = answer["url"].flatMap(URL.init(string:)), let secret = answer["secret"],
              link.scheme == endpoint.scheme, link.host == endpoint.host else { throw failure(status) }
        return Shared(id: id, url: link, secret: secret, shown: words)
    }

    /// Where the wish's file goes: beside the link's API (`site/api/wish-file.js`).
    private static func fileAddress(for id: String, part: Int? = nil, of count: Int? = nil) -> URL {
        var parts = URLComponents(url: endpoint.deletingLastPathComponent().appendingPathComponent("wish-file"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "id", value: id)]
            + (part.map { [URLQueryItem(name: "part", value: String($0)), URLQueryItem(name: "of", value: String(count ?? 1))] } ?? [])
        return parts.url!
    }

    /// Sends the wish's file with its link, in parts, and has the site put them together in place of any file it had.
    static func uploadFile(_ data: Data, for shared: Shared) async throws {
        guard data.count <= Limit.fileTotal else {
            throw Failure(message: "This wish is too big to go with its link (over \(Limit.fileTotal / 1_000_000) MB). Share the link without it.")
        }
        let count = max(1, (data.count + Limit.filePart - 1) / Limit.filePart)
        for n in 0..<count {
            var request = URLRequest(url: fileAddress(for: shared.id, part: n, of: count))
            request.httpMethod = "PUT"
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(shared.secret)", forHTTPHeaderField: "Authorization")
            request.httpBody = data.subdata(in: (n * Limit.filePart)..<min(data.count, (n + 1) * Limit.filePart))
            let (_, status) = try await send(request)
            guard status == 204 else { throw fileFailure(status) }
        }
        var finish = URLRequest(url: fileAddress(for: shared.id))
        finish.httpMethod = "POST"
        finish.setValue("Bearer \(shared.secret)", forHTTPHeaderField: "Authorization")
        let (_, status) = try await send(finish)
        guard status == 200 else { throw fileFailure(status) }
    }

    private static func fileFailure(_ status: Int) -> Failure {
        [400, 409, 413].contains(status) ? Failure(message: "lamp.dev couldn't take this wish's file. Share the link without it, or try again.") : failure(status)
    }

    /// Takes the wish's file away from its link, which keeps showing the idea.
    static func removeFile(for shared: Shared) async throws {
        var request = URLRequest(url: fileAddress(for: shared.id))
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
        case 429: Failure(message: "Too many wishes were shared from here just now. Try again later.")
        case 400, 413: Failure(message: "lamp.dev couldn't take this wish. Try a shorter one, or leave out the picture.")
        default: Failure(message: "lamp.dev couldn't share this wish right now. Try again in a moment.")
        }
    }
}

/// The Share Link card of each wish while it's open, in Lamp's window or in the chat beside the app. One card per wish:
/// opened from either chat, it's the same card, so what's typed on it and the link it makes are the same.
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
        var stage: WishLinkCard.Stage = .editing
        var copied = false
        var retaking = false
        /// Where it's shown: the chat beside the app, or Lamp's window.
        var inSidebar: Bool
        /// Bumped when Lamp changes the values itself (a new picture), so the chat beside the app takes them.
        var revision = 0

        /// What the link would show with what's on the card.
        var words: WishLink.Words {
            WishLink.Words(name: values.name.trimmed, line: values.line.trimmed, words: values.words.trimmed,
                           picture: values.includePicture ? pictureDigest : nil, file: values.includeFile ? true : nil)
        }
        /// A link that carries the wish is always worth sending again: the file is the wish as it is now.
        var changed: Bool { shared?.shown != words || values.includeFile }
    }

    @Published private(set) var cards: [String: Card] = [:]

    func card(for project: LampProject) -> Card? { cards[project.id] }

    func open(_ project: LampProject, inSidebar: Bool) {
        if cards[project.id] != nil {
            cards[project.id]?.inSidebar = inSidebar
            return
        }
        let shared = WishLink.kept(for: project)
        let picture = WishLink.picture(of: project)
        let digest = picture.map(Self.digest)
        let values = shared.map { WishLinkCard.Values(name: $0.shown.name, line: $0.shown.line, words: $0.shown.words,
                                                      includePicture: $0.shown.picture != nil && picture != nil,
                                                      includeFile: $0.shown.file == true && Self.canIncludeFile(project)) }
            ?? WishLinkCard.Values(name: WishLink.clip(project.untitled ? "" : project.name, WishLink.Limit.name),
                                   line: WishLink.line(of: project), words: WishLink.firstRequest(of: project, store: Store.shared),
                                   includePicture: picture != nil)
        var card = Card(values: values, pictureDigest: digest, shared: shared, inSidebar: inSidebar)
        card.picture = picture
        // The picture the link shows is the one it was made with, as long as the app's own hasn't changed since.
        if let shown = shared?.shown.picture, shown != digest { card.values.includePicture = picture != nil }
        cards[project.id] = card
        Task {
            let icon = await Sharing.sharedIcon(of: project)
            cards[project.id]?.icon = icon
        }
    }

    /// Whether the wish can go with its link as a file: its kind can be shared as one.
    static func canIncludeFile(_ project: LampProject) -> Bool {
        project.platform.target.recipe.shareRefusal == nil && !(project.platform == .game && GameKit.engine(project) != .web)
    }

    func update(_ project: LampProject, values: WishLinkCard.Values) {
        guard cards[project.id]?.values != values else { return }
        cards[project.id]?.values = values
        cards[project.id]?.copied = false
        if case .failed = cards[project.id]?.stage { cards[project.id]?.stage = .editing }
    }

    func close(_ project: LampProject) { cards[project.id] = nil }

    /// Shares what's on the card, or changes what the link shows, and copies the link.
    func share(_ project: LampProject) {
        guard let card = cards[project.id], card.stage != .sending, card.values.isComplete else { return }
        cards[project.id]?.stage = .sending
        let words = card.words
        let source = card.values.includePicture ? card.picture : nil
        let iconSource = card.icon
        Task {
            do {
                let (picture, icon) = await Task.detached(priority: .userInitiated) {
                    (source.flatMap(NSImage.init(data:)).flatMap(WishLink.jpeg), WishLink.iconPNG(iconSource))
                }.value
                var shared = try await WishLink.publish(words, picture: picture, icon: icon, replacing: card.shared)
                // Kept at once, with the file as the link had it so far: its secret is the only way to change it or take it
                // down, so a file that fails after this leaves a link the card can still stop.
                shared.shown.file = card.shared?.shown.file
                WishLink.keep(shared, for: project)
                cards[project.id]?.shared = shared
                // The wish itself, made as Share… makes it (with its checks), sent with the link; or taken away from a link
                // that carried it and shouldn't now.
                if words.file == true {
                    let data = try await Task.detached(priority: .userInitiated) { () throws -> Data in
                        let file = try Sharing.export(project)
                        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
                        return try Data(contentsOf: file)
                    }.value
                    try await WishLink.uploadFile(data, for: shared)
                } else if card.shared?.shown.file == true {
                    try await WishLink.removeFile(for: shared)
                }
                shared.shown = words
                WishLink.keep(shared, for: project)
                guard cards[project.id] != nil else { return }
                cards[project.id]?.shared = shared
                cards[project.id]?.stage = .editing
                copy(project)
            } catch {
                cards[project.id]?.stage = .failed(error.localizedDescription)
            }
        }
    }

    func copy(_ project: LampProject) {
        guard let url = cards[project.id]?.shared?.url else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.declareTypes([.URL, .string], owner: nil)
        (url as NSURL).write(to: board)
        board.setString(url.absoluteString, forType: .string)
        cards[project.id]?.copied = true
    }

    /// Takes the link down, and the card with it.
    func stop(_ project: LampProject) {
        guard let shared = cards[project.id]?.shared else { return }
        cards[project.id]?.stage = .sending
        Task {
            do {
                try await WishLink.remove(shared)
                WishLink.keep(nil, for: project)
                cards[project.id] = nil
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
            cards[project.id]?.values.includePicture = true
            cards[project.id]?.copied = false
            cards[project.id]?.revision += 1
        }
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

extension WishLink {
    static let cardLimits = WishLinkCard.Limits(name: Limit.name, line: Limit.line, words: Limit.words)
}
