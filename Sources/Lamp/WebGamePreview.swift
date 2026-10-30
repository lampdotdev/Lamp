import AppKit
import WebKit
import LampRelayKit

/// The preview a web game is played in for the agent (`GameKit.Engine.web`): its page from a copy in Lamp's own
/// folder, in a web view no one sees, playing the script the agent's looks and uses make (`GameKit.plays`). Lamp's game
/// runtime (`lamp-game.js`) reads the script itself and runs the game's frames at exactly 1/60 s, its clock and random
/// numbers the same every play, so the same script gives the same pictures; at each `shot` it waits while Lamp takes a
/// picture of the whole page as drawn, the canvas and whatever's over it.
@MainActor
final class WebGamePreview: NSObject, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
    private var webView: WKWebView?
    private let files = StagedFiles()
    private var pictures: [String: Data] = [:]
    /// The order they were taken in: only the latest are kept, which are the ones a look or a use asks for.
    private var taken: [String] = []
    private var finished: CheckedContinuation<[String: Any]?, Never>?

    /// Plays the script and hands back what it drew and said, or nil when the page never got to the end of it (it
    /// didn't start, or ran for more than two minutes: a whole city takes about half a minute to build out of sight).
    /// A shared game (`policy`) is held to what it's held to as an app (`SharedNetwork`).
    static func play(_ staged: URL, script: [String], policy: NetworkPolicy? = nil) async -> (pictures: [String: Data], result: [String: Any])? {
        let preview = WebGamePreview()
        preview.files.policy = policy
        preview.files.own = "lamp-game://app"
        guard let result = await preview.run(staged, script: script) else { return nil }
        return (preview.pictures, result)
    }

    private func run(_ staged: URL, script: [String]) async -> [String: Any]? {
        files.folder = staged
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        // In no window, a page is one WebKit soon suspends, and a big one (a whole city) takes longer to build than that.
        configuration.preferences.inactiveSchedulingPolicy = .none
        configuration.setURLSchemeHandler(files, forURLScheme: "lamp-game")
        if files.policy != nil { NetworkPolicy.holdBack(configuration.preferences) }
        configuration.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "lampPreview")
        let json = (try? JSONSerialization.data(withJSONObject: ["script": script])).map { String(decoding: $0, as: UTF8.self) } ?? "{\"script\":[]}"
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
        view.stopLoading()
        webView = nil
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
                    if let self, let image, let png = Self.png(image) {
                        self.pictures[name] = png
                        self.taken.append(name)
                        // A long play's earliest pictures go: every use plays it all again, and asks only for its own.
                        while self.taken.count > 16 { self.pictures[self.taken.removeFirst()] = nil }
                    }
                    replyHandler(true, nil)
                }
            }
            return
        }
        replyHandler(true, nil)
        if body["done"] as? Bool == true { end(body) }
    }

    /// The picture at the game's own size, 1920x1080, whatever the screen's scale.
    private static func png(_ image: NSImage) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: GameKit.width, pixelsHigh: GameKit.height, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: GameKit.width, height: GameKit.height))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
