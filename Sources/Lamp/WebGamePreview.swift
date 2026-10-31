import AppKit
import CryptoKit
import WebKit
import LampRelayKit

/// The preview a web game is played in for the agent (`GameKit.Engine.web`): its page from a copy in Lamp's own
/// folder, in a web view no one sees, playing the script the agent's looks and uses make (`GameKit.plays`). Lamp's game
/// runtime (`lamp-game.js`) reads the script itself and runs the game's frames at exactly 1/60 s, its clock and random
/// numbers the same every play, so the same script gives the same pictures; at each `shot` it waits while Lamp takes a
/// picture of the whole page as drawn, the canvas and whatever's over it.
///
/// After a play that ends cleanly the preview is kept open for a while, one a game: the next look hands it the new
/// script and the files changed since, and the game's code runs again in place there with what it keeps (lamp-game.js,
/// "Lamp's preview kept warm"), so only the first look of a while waits for the whole game to be built and its shaders
/// compiled. Anything that can't go that way (Lamp's own files changed, the page can't run its code again, a play that
/// fails or runs too long) closes it, and the look starts a new one. It's kept while the agent goes on working on the
/// game (`keepWarm`: each look, and every two seconds of a turn on it), and for ten minutes after.
///
/// How long a play may take goes by how long this game took to be built last time (`play`'s `limit`): a city takes
/// a minute and a half out of sight, which a fixed two minutes cut short. One that runs out says how far it got
/// (whether the game had started, what it logged last) rather than nothing.
@MainActor
final class WebGamePreview: NSObject, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
    private var webView: WKWebView?
    /// The previews kept open, by game, and how long one waits for its next look.
    private static var warm: [String: WebGamePreview] = [:]
    private static let keptFor: Duration = .seconds(600)
    private var staged: URL?
    private var hashes: [String: String] = [:]
    private var lastPlayed = Date()
    /// When this play began (the page loading, or a new play handed to the page kept open), and how long after it the
    /// game's init was done and its frames began (`playing` from lamp-game.js), which a play that runs out says.
    private var began = Date()
    private var builtIn: TimeInterval?
    private var playing = false
    private var stopped = false
    /// Each play's number, so a play's timeout never ends the next one.
    private var round = 0
    private let files = StagedFiles()
    private var pictures: [String: Data] = [:]
    /// The order they were taken in: only the latest are kept, which are the ones a look or a use asks for.
    private var taken: [String] = []
    private var finished: CheckedContinuation<[String: Any]?, Never>?
    /// The game's phone page, once a play's first step on it opens it (`PhonePreview`), from the copy in `phoneFolder`.
    private var phone: PhonePreview?
    private var phoneFolder: URL?

    /// The preview playing for each game now, which `stop` ends.
    private static var underWay: [String: WebGamePreview] = [:]
    /// Ends the play under way for a game (the person sent a message): it answers nil, and isn't kept warm.
    static func stop(for id: String) {
        guard let preview = underWay[id] else { return }
        preview.stopped = true
        preview.end(nil)
    }

    /// Plays the script and hands back what it drew and said, or nil when it was stopped. A play that runs past `limit`
    /// ends with `timedOut` (the seconds it ran), `started` and `logs` in its result: how far it got. A play in a new
    /// page has `cold` and `took`, its seconds from loading the page to the end: the whole build, its first frames'
    /// shaders included (most of a city's), and the short play, which the next play's limit goes by.
    /// A shared game (`policy`) is held to what it's held to as an app (`SharedNetwork`), and is never kept warm: its
    /// policy is set up afresh with each play. Nor is a play with the phone page (`phone`, its copy): a game's phones
    /// join from a fresh start, which a page played again in place doesn't give them.
    static func play(_ staged: URL, script: [String], for id: String, policy: NetworkPolicy? = nil, phone: URL? = nil,
                     limit: Duration = .seconds(120)) async -> (pictures: [String: Data], result: [String: Any])? {
        defer { underWay[id] = nil }
        let phoned = script.contains { $0.hasPrefix("phone ") }
        if let kept = warm[id] {
            warm[id] = nil
            underWay[id] = kept
            if policy == nil, !phoned, let played = await kept.again(staged, script: script, limit: limit) {
                keep(kept, for: id, after: played.result)
                return played
            }
            kept.close()
        }
        if underWay[id]?.stopped == true { return nil }
        let preview = WebGamePreview()
        underWay[id] = preview
        preview.files.policy = policy
        preview.files.own = "lamp-game://app"
        preview.phoneFolder = phoneFolder(phone, if: phoned)
        guard let result = await preview.run(staged, script: script, limit: limit) else { preview.close(); return nil }
        if policy == nil, !phoned { keep(preview, for: id, after: result) } else { preview.close() }
        return (preview.pictures, result)
    }

    private static func phoneFolder(_ folder: URL?, if phoned: Bool) -> URL? { phoned ? folder : nil }

    /// Kept open after a play that ended cleanly, closed once it has waited `keptFor` with no look and no work on the game.
    private static func keep(_ preview: WebGamePreview, for id: String, after result: [String: Any]) {
        guard result["failed"] == nil, result["timedOut"] == nil, result["again"] as? Bool != false, preview.webView != nil, !preview.stopped
        else { return preview.close() }
        warm[id]?.close()
        warm[id] = preview
        preview.lastPlayed = Date()
        Task { [weak preview] in
            while let kept = preview, warm[id] === kept {
                let left = keptFor - .seconds(Date().timeIntervalSince(kept.lastPlayed))
                if left <= .zero { break }
                try? await Task.sleep(for: left)
            }
            guard let preview, warm[id] === preview else { return }
            warm[id] = nil
            preview.close()
        }
    }

    /// The game's preview, if one is kept open, waits `keptFor` from now: the agent is still at work on the game (a look
    /// at its open window, a step it saved), and its next look in the preview shouldn't wait for the world to be built
    /// again because the last one was a while ago.
    static func keepWarm(for id: String) {
        warm[id]?.lastPlayed = Date()
    }

    /// Whether the game's next play goes into a preview kept open, which builds only what changed.
    static func isWarm(for id: String) -> Bool { warm[id] != nil }

    /// The next play in the page kept open: nil when it can't go there.
    private func again(_ staged: URL, script: [String], limit: Duration) async -> (pictures: [String: Data], result: [String: Any])? {
        guard !playing, staged == self.staged, let webView else { return nil }
        let now = Self.hashes(of: staged)
        // A copy of the page names its build, which changes with every staging and says nothing of the game.
        let changed = Set(now.keys).union(hashes.keys).filter { now[$0] != hashes[$0] && $0 != "lamp-build.js" }
        // Lamp's own files run the page: a change to them starts it afresh.
        if changed.contains(where: { $0.hasPrefix("lamp") && !$0.contains("/") }) { return nil }
        playing = true
        defer { playing = false }
        round += 1
        let mine = round
        pictures = [:]
        taken = []
        hashes = now
        began = Date()
        builtIn = nil
        let json = (try? JSONSerialization.data(withJSONObject: ["script": script, "changed": changed.sorted()])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        let result = await withCheckedContinuation { (done: CheckedContinuation<[String: Any]?, Never>) in
            finished = done
            webView.evaluateJavaScript("window.__lampPreviewAgain ? window.__lampPreviewAgain(\(json)) : false") { [weak self] answer, _ in
                MainActor.assumeIsolated { if answer as? Bool != true { self?.end(nil) } }
            }
            Task { [weak self] in
                try? await Task.sleep(for: limit)
                if self?.round == mine, self?.finished != nil { await self?.ranOut() }
            }
        }
        guard var result, result["again"] as? Bool != false else { return nil }
        if let builtIn { result["built"] = builtIn }
        return (pictures, result)
    }

    private func close() {
        webView?.stopLoading()
        webView = nil
        phone?.close()
        phone = nil
    }

    /// The staged page's files by their path in it, each by a hash of its contents, to tell what a look changed.
    private static func hashes(of folder: URL) -> [String: String] {
        let base = folder.standardizedFileURL.path + "/"
        var found: [String: String] = [:]
        for case let url as URL in FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) ?? FileManager.DirectoryEnumerator() {
            guard let data = try? Data(contentsOf: url) else { continue }
            found[String(url.standardizedFileURL.path.dropFirst(base.count))] = SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined()
        }
        return found
    }

    private func run(_ staged: URL, script: [String], limit: Duration) async -> [String: Any]? {
        began = Date()
        builtIn = nil
        files.folder = staged
        self.staged = staged
        hashes = Self.hashes(of: staged)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        // In no window, a page is one WebKit soon suspends, and a big one (a whole city) takes longer to build than that.
        configuration.preferences.inactiveSchedulingPolicy = .none
        configuration.setURLSchemeHandler(files, forURLScheme: "lamp-game")
        if files.policy != nil { NetworkPolicy.holdBack(configuration.preferences) }
        configuration.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "lampPreview")
        let json = (try? JSONSerialization.data(withJSONObject: ["script": script, "warm": true] as [String: Any])).map { String(decoding: $0, as: UTF8.self) } ?? "{\"script\":[]}"
        configuration.userContentController.addUserScript(WKUserScript(source: "window.lampPreview = \(json);", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: GameKit.width, height: GameKit.height), configuration: configuration)
        webView = view
        view.navigationDelegate = self
        view.load(URLRequest(url: URL(string: "lamp-game://app/index.html")!))
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: limit)
            await self?.ranOut()
        }
        var result = await withCheckedContinuation { finished = $0 }
        timeout.cancel()
        if let builtIn { result?["built"] = builtIn }
        result?["cold"] = true
        result?["took"] = Date().timeIntervalSince(began)
        return result
    }

    /// A play past its limit ends with how far it got, read from the page: whether game() had been called, and the
    /// last lines it logged. A page that doesn't answer within a few seconds is said to have answered nothing.
    private func ranOut() async {
        guard finished != nil else { return }
        var result: [String: Any] = ["timedOut": Date().timeIntervalSince(began)]
        if let builtIn { result["built"] = builtIn }
        if let webView {
            // Nil: no answer at all, the page busy in code that never lets go; an empty answer, no lamp-game.js in the page.
            let state: [String: Any]? = await withCheckedContinuation { (done: CheckedContinuation<[String: Any]?, Never>) in
                var answered = false
                webView.evaluateJavaScript("window.__lampPreviewState ? window.__lampPreviewState() : {}") { answer, _ in
                    MainActor.assumeIsolated {
                        guard !answered else { return }
                        answered = true
                        done.resume(returning: answer as? [String: Any] ?? [:])
                    }
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(3))
                    guard !answered else { return }
                    answered = true
                    done.resume(returning: nil)
                }
            }
            if let state {
                result["answered"] = true
                result["started"] = state["started"] as? Bool
                result["logs"] = state["logs"] as? [String] ?? []
            }
        }
        end(result)
    }

    /// A shared game never leaves its own address, in its window or a frame.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, let policy = files.policy, !policy.allowsFrame(url, own: files.own) else { return decisionHandler(.allow) }
        decisionHandler(.cancel)
    }

    private func end(_ result: [String: Any]?) {
        finished?.resume(returning: result)
        finished = nil
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any] else { return replyHandler(nil, nil) }
        if let name = body["shot"] as? String {
            // One picture a name, named as the script names it: letters, digits and dashes.
            guard name.count <= 40, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }), let webView else {
                return replyHandler(false, nil)
            }
            let configuration = WKSnapshotConfiguration()
            configuration.afterScreenUpdates = true
            webView.takeSnapshot(with: configuration) { [weak self] image, _ in
                MainActor.assumeIsolated {
                    if let self, let image, let png = Self.png(image, width: GameKit.width, height: GameKit.height) { self.keep(png, as: name) }
                    guard let self, let phone = self.phone else { return replyHandler(true, nil) }
                    Task { @MainActor in
                        if let png = await phone.picture() { self.keep(png, as: GameKit.phonePicture + name) }
                        replyHandler(true, nil)
                    }
                }
            }
            return
        }
        if let step = body["phone"] as? [String: Any] {
            Task { @MainActor in
                replyHandler(await self.phoneStep(step, inbox: body["inbox"] as? String ?? "[]", hosted: body["hosted"] as? Bool ?? false,
                                                  elapsed: (body["elapsed"] as? NSNumber)?.doubleValue ?? 0), nil)
            }
            return
        }
        replyHandler(true, nil)
        if body["playing"] as? Bool == true, builtIn == nil { builtIn = Date().timeIntervalSince(began) }
        guard body["done"] as? Bool == true else { return }
        guard let phone else { return end(body) }
        Task { @MainActor in
            var result = body
            result["phone"] = await phone.report()
            end(result)
        }
    }

    /// One step on the phone page, from the game's play: the first opens it. Nil tells the play there's no phone.
    private func phoneStep(_ step: [String: Any], inbox: String, hosted: Bool, elapsed: Double) async -> String? {
        if phone == nil {
            guard let phoneFolder else { return nil }
            let opening = PhonePreview()
            guard await opening.open(phoneFolder) else { return nil }
            phone = opening
        }
        return await phone?.step(step, inbox: inbox, hosted: hosted, elapsed: elapsed)
    }

    private func keep(_ png: Data, as name: String) {
        pictures[name] = png
        taken.append(name)
        // A long play's earliest pictures go: every use plays it all again, and asks only for its own.
        while taken.count > 16 { pictures[taken.removeFirst()] = nil }
    }

    /// The picture at the size given, whatever the screen's scale: the game's own, 1920x1080, or the phone page's.
    static func png(_ image: NSImage, width: Int, height: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
