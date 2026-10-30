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
/// fails or runs too long) closes it, and the look starts a new one.
@MainActor
final class WebGamePreview: NSObject, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
    private var webView: WKWebView?
    /// The previews kept open, by game, and how long one waits for its next look.
    private static var warm: [String: WebGamePreview] = [:]
    private static let keptFor: Duration = .seconds(600)
    private var staged: URL?
    private var hashes: [String: String] = [:]
    private var lastPlayed = Date()
    private var playing = false
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

    /// Plays the script and hands back what it drew and said, or nil when the page never got to the end of it (it
    /// didn't start, or ran for more than two minutes: a whole city takes about half a minute to build out of sight).
    /// A shared game (`policy`) is held to what it's held to as an app (`SharedNetwork`), and is never kept warm: its
    /// policy is set up afresh with each play. Nor is a play with the phone page (`phone`, its copy): a game's phones
    /// join from a fresh start, which a page played again in place doesn't give them.
    static func play(_ staged: URL, script: [String], for id: String, policy: NetworkPolicy? = nil, phone: URL? = nil) async -> (pictures: [String: Data], result: [String: Any])? {
        let phoned = script.contains { $0.hasPrefix("phone ") }
        if let kept = warm[id] {
            warm[id] = nil
            if policy == nil, !phoned, let played = await kept.again(staged, script: script) {
                keep(kept, for: id, after: played.result)
                return played
            }
            kept.close()
        }
        let preview = WebGamePreview()
        preview.files.policy = policy
        preview.files.own = "lamp-game://app"
        preview.phoneFolder = phoneFolder(phone, if: phoned)
        guard let result = await preview.run(staged, script: script) else { preview.close(); return nil }
        if policy == nil, !phoned { keep(preview, for: id, after: result) } else { preview.close() }
        return (preview.pictures, result)
    }

    private static func phoneFolder(_ folder: URL?, if phoned: Bool) -> URL? { phoned ? folder : nil }

    /// Kept open after a play that ended cleanly, closed once it has waited `keptFor` with no look.
    private static func keep(_ preview: WebGamePreview, for id: String, after result: [String: Any]) {
        guard result["failed"] == nil, result["again"] as? Bool != false, preview.webView != nil else { return preview.close() }
        warm[id]?.close()
        warm[id] = preview
        preview.lastPlayed = Date()
        Task { [weak preview] in
            try? await Task.sleep(for: keptFor)
            guard let preview, warm[id] === preview, Date().timeIntervalSince(preview.lastPlayed) >= 600 - 1 else { return }
            warm[id] = nil
            preview.close()
        }
    }

    /// The next play in the page kept open: nil when it can't go there.
    private func again(_ staged: URL, script: [String]) async -> (pictures: [String: Data], result: [String: Any])? {
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
        let json = (try? JSONSerialization.data(withJSONObject: ["script": script, "changed": changed.sorted()])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        let result = await withCheckedContinuation { (done: CheckedContinuation<[String: Any]?, Never>) in
            finished = done
            webView.evaluateJavaScript("window.__lampPreviewAgain ? window.__lampPreviewAgain(\(json)) : false") { [weak self] answer, _ in
                MainActor.assumeIsolated { if answer as? Bool != true { self?.end(nil) } }
            }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(120))
                if self?.round == mine, self?.finished != nil { self?.end(nil) }
            }
        }
        guard let result, result["again"] as? Bool != false else { return nil }
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

    private func run(_ staged: URL, script: [String]) async -> [String: Any]? {
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
            try? await Task.sleep(for: .seconds(120))
            self?.end(nil)
        }
        let result = await withCheckedContinuation { finished = $0 }
        timeout.cancel()
        return result
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
                replyHandler(await self.phoneStep(step, inbox: body["inbox"] as? String ?? "[]", hosted: body["hosted"] as? Bool ?? false), nil)
            }
            return
        }
        replyHandler(true, nil)
        guard body["done"] as? Bool == true else { return }
        guard let phone else { return end(body) }
        Task { @MainActor in
            var result = body
            result["phone"] = await phone.report()
            end(result)
        }
    }

    /// One step on the phone page, from the game's play: the first opens it. Nil tells the play there's no phone.
    private func phoneStep(_ step: [String: Any], inbox: String, hosted: Bool) async -> String? {
        if phone == nil {
            guard let phoneFolder else { return nil }
            let opening = PhonePreview()
            guard await opening.open(phoneFolder) else { return nil }
            phone = opening
        }
        return await phone?.step(step, inbox: inbox, hosted: hosted)
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
