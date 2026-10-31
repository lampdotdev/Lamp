import AppKit
import CryptoKit
import ScreenCaptureKit
import UniformTypeIdentifiers
import WebKit
import LampRelayKit

/// The TV on this Mac's screen: a TV app opened at the TVs' own size (1920×1080, shown at half that), from the copy of
/// its files in Lamp's folder (`TVs.stage`). A screen that fills whatever it's shown on is opened at any shape the
/// agent asks for (`shape`: a TV, a frame, an iPad either way up, a phone), each pictured with its long side 960 pixels. The agent looks at it and presses the remote's keys on it, as it does on a
/// simulator; the person can use it with the keyboard's arrows, Return and Escape. What the page prints goes to the
/// app's log.
@MainActor
final class TVPreview: NSObject, WKScriptMessageHandler, WKScriptMessageHandlerWithReply, WKNavigationDelegate, NSWindowDelegate {
    private static var open: [String: TVPreview] = [:]

    /// Where the app's page is opened. A TV opens an app's files straight from its package, and the page reads its own
    /// files (a game's data, a program in WebAssembly) with fetch and XMLHttpRequest, as text or as bytes. WebKit
    /// refuses both to a page opened from a file, so the preview serves the staged copy at an address of its own.
    private static let scheme = "lamp-tv"
    private static let home = URL(string: "\(scheme)://app/index.html")!

    private let project: LampProject
    /// What the preview stands in for, as the person calls it: "TV", a device app's device ("Xbox"), or nil for a page
    /// that stands in for no device (a web app at home on the Mac), which is just the preview. Back on a TV's remote is
    /// its own key, as it is on such a page (it has the TV's remote keys); on a device it's Escape, as an Xbox's B button sends.
    private var device: String? = "TV"
    private var isTV: Bool { device == nil || device == "TV" }
    private let window: Window
    private let webView: WKWebView
    private let files = StagedFiles()
    private var loaded: CheckedContinuation<Void, Never>?
    /// When the open page was last pictured, so each picture can say how long after the one before it was taken.
    private var lastPictured: Date?
    private var log: FileHandle?
    /// The page's size in CSS pixels: a TV's, or the shape a screen is looked at in.
    private var shape = CGSize(width: 1920, height: 1080)
    /// Opened with a copy of what the app's copy on this Mac saved (`isSeeded`).
    private var seeded = false
    /// Pixels in a picture (and points for `use_app`) per pixel of the page: half for a TV, as it always was.
    private var scale: CGFloat { 960 / max(shape.width, shape.height) }

    static func isOpen(_ project: LampProject) -> Bool { open[project.id]?.window.isVisible == true }
    static var openIDs: [String] { open.filter { $0.value.window.isVisible }.map(\.key) }
    static func window(_ project: LampProject) -> NSWindow? { open[project.id]?.window }

    static func close(_ project: LampProject) {
        open[project.id]?.window.close()
        open[project.id] = nil
    }

    /// What an app's page saved in its preview (`store(for:)`), gone with the app: a part's store is named after its
    /// instance, so it would otherwise outlive its wish for good, values the wish's apps shared included. Removed in the
    /// background (`PreviewStores`), since a page that has just closed holds its store a few seconds longer, rather than
    /// holding up what deletes the app.
    @discardableResult
    static func forget(_ project: LampProject) -> Task<Void, Never> {
        close(project)
        return forget(instance: project.instance)
    }

    /// What an app saved in the preview, by its instance: one already closed, or gone from Lamp's lists.
    @discardableResult
    static func forget(instance: String) -> Task<Void, Never> {
        let store = store(for: instance)
        return Task { @MainActor in
            guard let store else { return }
            if await !PreviewStores.remove(store) { print("TV preview: what \(instance) saved couldn't be removed") }
        }
    }

    /// Opens the staged app (again, from the start), in front or behind what the person is doing. Nil once it has loaded.
    /// `seed`, what the app's copy on this Mac has saved, replaces everything the preview kept: it starts from the person's
    /// own data, and what's done in it stays in it.
    @discardableResult
    static func show(_ project: LampProject, staged: URL, inFront: Bool, device: String? = "TV", seed: [String: String]? = nil) async -> String? {
        let preview = open[project.id] ?? TVPreview(project: project)
        open[project.id] = preview
        preview.device = device
        preview.window.title = title(of: project.name, device: device)
        return await preview.load(staged: staged, inFront: inFront, seed: seed)
    }

    /// Whether the open preview started from a copy of what the app's copy on this Mac saved (`show`'s `seed`): it's a
    /// copy, so it never joins the wish's apps, where it would pass on what's done in it as the person's.
    static func isSeeded(_ project: LampProject) -> Bool { open[project.id]?.seeded == true }

    /// The window's title: the app on its device ("Clock on TV"), or the app's preview when it stands in for none.
    static func title(of name: String, device: String?) -> String { device.map { "\(name) on \($0)" } ?? "\(name) Preview" }

    /// Keeps each open preview's name with where Try On points: a page shown on the Mac and on a TV, its preview open, is
    /// "on TV" while Try On points at the TV and just the preview once it points at the Mac, with no reload (a look reuses
    /// a preview that's up to date). What it stands in for decides Back too, as `show` would.
    static func follow(_ projects: [LampProject]) {
        for (id, preview) in open {
            guard let project = projects.first(where: { $0.id == id }) else { continue }
            let device = Store.previewDevice(project)
            guard device != preview.device else { continue }
            preview.device = device
            preview.window.title = title(of: project.name, device: device)
        }
    }

    /// The shape the page is shown at now, in CSS pixels.
    static func shape(of project: LampProject) -> CGSize { open[project.id]?.shape ?? CGSize(width: 1920, height: 1080) }

    /// Shows a screen's page at another shape, the window turned to it and the page laid out again at that size.
    static func reshape(_ project: LampProject, to size: CGSize) async {
        guard let preview = open[project.id], size.width >= 200, size.height >= 200, size != preview.shape else { return }
        preview.shape = size
        let top = preview.window.frame.maxY
        preview.window.contentAspectRatio = size
        preview.window.setContentSize(NSSize(width: size.width * preview.scale, height: size.height * preview.scale))
        var frame = preview.window.frame
        frame.origin.y = top - frame.height
        preview.window.setFrame(frame, display: true)
        preview.webView.pageZoom = preview.webView.bounds.width / size.width
        // A moment for the page to hear the resize and lay itself out again.
        try? await Task.sleep(for: .milliseconds(500))
    }

    static func bringForward(_ project: LampProject) {
        guard let preview = open[project.id] else { return }
        preview.window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// The store an app's page keeps what it saves in, by its instance, which outlasts renames: an app's own instance is a
    /// UUID; a part of a wish's ("<the wish's>.TV", `Parts.instance`) isn't one, so it gets a UUID made from it, the same
    /// at every opening and apart from the wish's other apps', since a TV app of a wish keeps the values the wish's apps
    /// share there. Nil only for an app with no instance yet.
    static func store(for instance: String) -> UUID? {
        if let own = UUID(uuidString: instance) { return own }
        guard !instance.isEmpty else { return nil }
        var bytes = Array(SHA256.hash(data: Data(("lamp-tv-preview " + instance).utf8)).prefix(16))
        bytes[6] = bytes[6] & 0x0f | 0x50   // a name-based UUID (version 5's bits)
        bytes[8] = bytes[8] & 0x3f | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private init(project: LampProject) {
        self.project = project
        let configuration = WKWebViewConfiguration()
        // What the app saves stays from one opening to the next, as on a TV: a store of its own for each app.
        configuration.websiteDataStore = Self.store(for: project.instance).map { WKWebsiteDataStore(forIdentifier: $0) } ?? .nonPersistent()
        let controller = WKUserContentController()
        // What the page prints, and what it throws, reach the log.
        controller.addUserScript(WKUserScript(source: Self.consoleScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController = controller
        configuration.setURLSchemeHandler(files, forURLScheme: Self.scheme)
        // A shared page is held back as it is in its app (`NetworkPolicy.holdBack`).
        if SharedNetwork.policy(for: project) != nil { NetworkPolicy.holdBack(configuration.preferences) }
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 960, height: 540), configuration: configuration)
        webView.pageZoom = 0.5
        webView.autoresizingMask = [.width, .height]
        window = Window(contentRect: NSRect(x: 0, y: 0, width: 960, height: 540), styleMask: [.titled, .closable, .miniaturizable, .resizable],
                        backing: .buffered, defer: false)
        super.init()
        controller.add(self, name: "lampConsole")
        controller.addScriptMessageHandler(self, contentWorld: .page, name: "lampGateway")
        webView.navigationDelegate = self
        window.title = "\(project.name) on TV"
        window.contentView = webView
        window.contentAspectRatio = NSSize(width: 16, height: 9)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("LampTVPreview")
        if window.frame.origin == .zero { window.center() }
    }

    /// The preview's window, told apart from the desk: closing it stops the app, never Lamp (`AppDelegate`).
    final class Window: NSWindow {}

    func windowDidResize(_ notification: Notification) { webView.pageZoom = webView.bounds.width / shape.width }

    func windowWillClose(_ notification: Notification) {
        // The wish's chat is attached to the preview (`ChatPanel`), and AppKit hides a window's children with it: let go
        // of it first, so Stop leaves the chat on screen, on its own, rather than nowhere.
        for child in window.childWindows ?? [] { window.removeChildWindow(child) }
        // Closing the window doesn't end the page: WebKit runs it, its sound and timers included, for as long as the web
        // view lives, and the web view's script handlers hold on to this preview, which holds the web view. So the app's
        // page is swapped for an empty one and the handlers let go, and the web view goes with the window.
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        webView.configuration.userContentController.removeAllUserScripts()
        webView.loadHTMLString("", baseURL: nil)
        window.contentView = nil
        finishLoading()
        try? log?.close()
        log = nil
        Self.open[project.id] = nil
        Store.shared.refreshOpenApps()
        Store.shared.syncLocalNetwork()   // its phone page isn't handed out any more
    }

    private func load(staged: URL, inFront: Bool, seed: [String: String]?) async -> String? {
        Runtime.startLog(project)
        try? log?.close()
        log = try? AppFolder.appendHandle(Runtime.logURL(project), in: project.dir)
        files.folder = staged
        // A shared page is held in its preview to what it's held to as an app (`SharedNetwork`).
        files.policy = SharedNetwork.policy(for: project)
        files.own = "\(Self.scheme)://app"
        files.connect = files.policy?.restricts == true ? await Self.relaySites(project) : []
        lastPictured = nil
        // WebKit keeps the scripts and styles a page loaded and serves them again for the same address, so an
        // opening after a change would run the app's code as it first was. Its saved data stays: only the caches go.
        await webView.configuration.websiteDataStore.removeData(ofTypes: [WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeDiskCache],
                                                                modifiedSince: .distantPast)
        // Closed while the caches went: loading now would start the app again in a preview nobody can see or close.
        guard Self.open[project.id] === self else { return "The TV preview was closed before the app opened." }
        // The person's own data, copied from the Mac's copy: in place of everything the preview kept, so nothing of an
        // earlier opening (the scaffold's example content, the agent's tries) is mixed in.
        var seedJSON: String?
        if let seed, let json = try? JSONSerialization.data(withJSONObject: seed) {
            seedJSON = String(decoding: json, as: UTF8.self)
            await webView.configuration.websiteDataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        }
        seeded = seedJSON != nil
        let carried = seedJSON == nil ? await savedFromFileAddress(staged) : nil
        guard Self.open[project.id] === self else { return "The TV preview was closed before the app opened." }
        if let seedJSON { webView.configuration.userContentController.addUserScript(Self.restoreScript(seedJSON, replacing: true)) }
        if let carried { webView.configuration.userContentController.addUserScript(Self.restoreScript(carried)) }
        await navigate { $0.load(URLRequest(url: Self.home)) }
        if seedJSON != nil {
            webView.configuration.userContentController.removeAllUserScripts()
            webView.configuration.userContentController.addUserScript(WKUserScript(source: Self.consoleScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        } else if carried != nil {
            // Marked done only once the app's page says it has the saves: a load that failed, timed out or was closed
            // ran no script, and the next opening tries again.
            if Self.open[project.id] === self, (try? await webView.evaluateJavaScript("window.lampRestored === true", in: nil, contentWorld: Self.restoreWorld)) as? Bool == true {
                UserDefaults.standard.set(true, forKey: Self.carriedKey(project))
            }
            webView.configuration.userContentController.removeAllUserScripts()
            webView.configuration.userContentController.addUserScript(WKUserScript(source: Self.consoleScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        // Closed while it loaded: showing the window again would bring back a preview with no page in it.
        guard Self.open[project.id] === self else { return "The TV preview was closed before the app opened." }
        if inFront { window.makeKeyAndOrderFront(nil); NSApp.activate() } else { window.orderFront(nil) }
        webView.pageZoom = webView.bounds.width / shape.width
        // Its scripts start on load; a moment more lets a first screen draw and take focus.
        try? await Task.sleep(for: .milliseconds(600))
        return nil
    }

    /// The controllers relay a shared game's page opens its own socket to here (`controllerSession`, which hands it out
    /// at the address the preview reaches Lamp at), once the relay listens: the one site on this Mac the page may connect
    /// to beyond its own, and only at the relay's port now, so every other port stays closed to it. None for a page that
    /// takes no players. Asked before the page loads, since a page's rules are the ones its files came with.
    static func relaySites(_ project: LampProject) async -> [String] {
        guard Store.servesPhonePage(project) else { return [] }
        ControllerRelay.open(project.id)
        guard let port = await ControllerRelay.ready() else { return [] }
        return ["ws://127.0.0.1:\(port)"]
    }

    /// Starts a navigation and waits for it to finish, fail, or ten seconds to pass.
    private func navigate(_ start: (WKWebView) -> Void) async {
        await withCheckedContinuation { continuation in
            loaded = continuation
            start(webView)
            Task {
                try? await Task.sleep(for: .seconds(10))
                self.finishLoading()
            }
        }
    }

    /// WebKit keeps what a page saves by the page's address, and an earlier Lamp opened the app from its file, so what
    /// the app saved then is read from that address once and handed to the app's first page at its own. Nil when
    /// there's nothing to hand over.
    private func savedFromFileAddress(_ staged: URL) async -> String? {
        guard webView.configuration.websiteDataStore.isPersistent, !UserDefaults.standard.bool(forKey: Self.carriedKey(project)) else { return nil }
        await navigate { $0.loadHTMLString("", baseURL: staged.appendingPathComponent("index.html")) }
        let read = "(function () { var o = {}; for (var i = 0; i < localStorage.length; i++) { var k = localStorage.key(i); o[k] = localStorage.getItem(k); } return JSON.stringify(o); })()"
        guard let saved = try? await webView.evaluateJavaScript(read) as? String else { return nil }
        if saved == "{}" { UserDefaults.standard.set(true, forKey: Self.carriedKey(project)) }
        return saved == "{}" ? nil : saved
    }

    private static func carriedKey(_ project: LampProject) -> String { "tvPreviewCarriedSaves." + project.id }

    /// Puts back what was handed over, before the app's own scripts run, leaving alone anything already saved here (or,
    /// `replacing`, in place of it), and says it did in a world of its own, which the app's scripts can't see or set.
    private static let restoreWorld = WKContentWorld.world(name: "lampRestore")
    private static func restoreScript(_ saved: String, replacing: Bool = false) -> WKUserScript {
        WKUserScript(source: """
            (function () {
              if (location.protocol !== '\(scheme):') return;
              var s = \(saved);
              for (var k in s) if (\(replacing) || localStorage.getItem(k) === null) localStorage.setItem(k, s[k]);
              window.lampRestored = true;
            })();
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: restoreWorld)
    }

    private func finishLoading() {
        loaded?.resume()
        loaded = nil
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finishLoading() }

    /// A shared page never leaves its own address, in its window or a frame (`NetworkPolicy.allowsFrame`).
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, let policy = files.policy, !policy.allowsFrame(url, own: files.own) else { return decisionHandler(.allow) }
        log?.write(Data("Lamp kept this shared app from opening \(url.absoluteString.prefix(300))\n".utf8))
        decisionHandler(.cancel)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        write("error: the page didn't load: \(error.localizedDescription)")
        finishLoading()
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        write("error: the page didn't load: \(error.localizedDescription)")
        finishLoading()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let text = message.body as? String else { return }
        write(String(text.prefix(4000)))
    }

    private func write(_ line: String) { log?.write(Data((line + "\n").utf8)) }

    /// The app's phone page has moved to another port: the page's `Lamp.phonePage` is told at once.
    static func phonePageMoved(_ app: String, to address: String) {
        guard let preview = open[app], let quoted = try? JSONSerialization.data(withJSONObject: [address], options: [.withoutEscapingSlashes]) else { return }
        let value = String(decoding: quoted, as: UTF8.self).dropFirst().dropLast()
        preview.webView.evaluateJavaScript("window.__lampPhonePage && window.__lampPhonePage(\(value));", completionHandler: nil)
    }

    /// Whether a message came from the app's own page, at the address the preview opens it at: never a frame inside it
    /// or a page it went on to, which could be anyone's.
    private func isOwnPage(_ message: WKScriptMessage) -> Bool {
        Self.isOwnPage(message.frameInfo.request.url, mainFrame: message.frameInfo.isMainFrame)
    }

    static func isOwnPage(_ page: URL?, mainFrame: Bool) -> Bool {
        guard mainFrame, let page else { return false }
        return page.scheme == scheme && page.host == home.host
    }

    /// LampAI in the preview (`DeviceSupport.webJS`): its calls are answered by Lamp in this process, as the app, with
    /// no token for the page to hold and no network between them. Only the AI routes an app uses, and where its phone page is.
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        // Only the app's own page, from its staged copy: never a frame inside it or a page it went on to, which could be
        // anyone's and would use AI as the app.
        guard isOwnPage(message), let call = message.body as? [String: Any], let path = call["path"] as? String,
              ["/ai", "/ai/status", "/ai/image", "/ai/decide", "/ai/act", "/ai/hear", "/app/phone-page", "/app/controller", "/app/wish"].contains(path),
              let current = Store.shared.projects.first(where: { $0.id == project.id }) else {
            replyHandler(["status": 404, "body": #"{"error":"Not found"}"#], nil)
            return
        }
        var request = Gateway.Request(method: "POST", path: path,
                                      headers: ["authorization": "Bearer " + Template.token(for: current), "host": "127.0.0.1:\(Gateway.port)"],
                                      body: Data((call["body"] as? String ?? "{}").utf8))
        // Phones as controllers: the page opens its own sockets to its players (`PhoneControllers`), as it does on a TV,
        // and only asks Lamp here who they are.
        request.fromPreview = true
        Task { @MainActor in
            let (status, json) = await Store.shared.handleAI(request)
            let body = (try? JSONSerialization.data(withJSONObject: json)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
            replyHandler(["status": status, "body": body], nil)
        }
    }

    private static let consoleScript = """
        (function () {
          function send(level, args) {
            try {
              var text = Array.prototype.map.call(args, function (a) {
                if (a instanceof Error) return a.message + (a.stack ? '\\n' + a.stack : '');
                if (typeof a === 'object') { try { return JSON.stringify(a); } catch (e) { return String(a); } }
                return String(a);
              }).join(' ');
              window.webkit.messageHandlers.lampConsole.postMessage(level + ': ' + text);
            } catch (e) {}
          }
          ['log', 'info', 'warn', 'error', 'debug'].forEach(function (level) {
            var original = console[level];
            console[level] = function () { send(level, arguments); if (original) original.apply(console, arguments); };
          });
          window.addEventListener('error', function (e) {
            send('error', [(e.message || 'Error') + ' (' + (e.filename || '').split('/').pop() + ':' + e.lineno + ')']);
          });
          window.addEventListener('unhandledrejection', function (e) { send('error', ['Unhandled rejection: ' + (e.reason && e.reason.message || e.reason)]); });
        })();
        """

    // MARK: Looking

    /// A picture of the screen at half the TV's size: a pixel in it is two of the page's. `moving` says whether it shows
    /// what's moving where it is now: WebKit's own snapshot draws the page again in software, where CSS animations and
    /// transitions sit at their start, so a square sliding across the screen is at the same place in every picture.
    struct Picture {
        let png: Data
        let moving: Bool
        let at: Date
        /// Seconds since the previous picture of this page; nil for the first since it opened.
        let since: TimeInterval?
    }

    /// Taken from the window itself, as the screen shows it, where macOS lets Lamp do that for its own windows without
    /// asking the person (14.4 on); WebKit's snapshot otherwise, or when the window can't be captured (minimized, say).
    static func picture(_ project: LampProject) async -> Picture? {
        guard let preview = open[project.id] else { return nil }
        var taken: (png: Data, moving: Bool)?
        if #available(macOS 14.4, *), let png = await preview.captured() { taken = (png, true) }
        if taken == nil {
            let configuration = WKSnapshotConfiguration()
            configuration.snapshotWidth = NSNumber(value: Double(preview.shape.width * preview.scale))
            if let image = try? await preview.webView.takeSnapshot(configuration: configuration),
               let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), let png = preview.sized(cg) { taken = (png, false) }
        }
        guard let taken else { return nil }
        let now = Date()
        defer { preview.lastPictured = now }
        return Picture(png: taken.png, moving: taken.moving, at: now, since: preview.lastPictured.map { now.timeIntervalSince($0) })
    }

    /// Said with each picture: the time between two pictures includes the agent's own thinking between its calls, so a
    /// `use_app` wait of one second can be several seconds of animation, and only the times say how many.
    static func takenNote(_ picture: Picture, timeZone: TimeZone = .current) -> String {
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.timeZone = timeZone
        clock.dateFormat = "HH:mm:ss.S"
        let when = "This picture was taken at \(clock.string(from: picture.at)) by this Mac's clock"
        guard let since = picture.since else { return when + ", the first since the app was opened in the preview." }
        return when + ", \(String(format: "%.1f", since)) s after the previous one."
    }

    /// The page drawn at `scale` (a TV's 960 pixels across), the size `use_app`'s points are measured in, whatever the
    /// screen's own scale.
    private func sized(_ page: CGImage) -> Data? {
        let width = Int((shape.width * scale).rounded()), height = Int((CGFloat(width) * CGFloat(page.height) / CGFloat(page.width)).rounded())
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                                            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        context.cgContext.interpolationQuality = .high
        // A window's capture has its rounded corners clear; black is a TV's edge.
        context.cgContext.setFillColor(.black)
        context.cgContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.cgContext.draw(page, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bitmap.representation(using: .png, properties: [:])
    }

    /// Said with a picture that doesn't show movement, so the agent doesn't take a still animation for a broken one.
    static let stillNote = "On this Mac the picture can't show movement: anything animated with CSS appears where its animation starts. "
        + "Read where things are from the screen as text instead."

    /// The window as the screen shows it, cut to the page. Nil when macOS doesn't offer the window or the capture fails.
    @available(macOS 14.4, *)
    private func captured() async -> Data? {
        guard window.isVisible, !window.isMiniaturized, webView.bounds.width > 0,
              let content = try? await SCShareableContent.currentProcess,
              let shared = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: shared)
        let scale = CGFloat(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        configuration.width = Int((filter.contentRect.width * scale).rounded())
        configuration.height = Int((filter.contentRect.height * scale).rounded())
        configuration.showsCursor = false
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) else { return nil }
        // The capture is the whole window, title bar included, with its origin at the top left; the page is the web
        // view's part of it.
        let page = webView.convert(webView.bounds, to: nil)
        let crop = CGRect(x: page.minX * scale, y: (filter.contentRect.height - page.maxY) * scale,
                          width: page.width * scale, height: page.height * scale).integral
        return image.cropping(to: crop).flatMap(sized)
    }

    struct Item {
        let id: String
        let kind: String
        let name: String
        let value: String
        let focused: Bool
        let frame: CGRect   // in the picture's pixels
    }

    /// What's on the screen, focusable things and text, in reading order.
    static func items(_ project: LampProject) async -> [Item] {
        guard let preview = open[project.id],
              let json = try? await preview.webView.evaluateJavaScript(PageScreen.script) as? String,
              let list = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]] else { return [] }
        var counts: [String: Int] = [:]
        let scale = preview.scale
        return list.compactMap { entry in
            guard let kind = entry["kind"] as? String else { return nil }
            let letter = String(kind.prefix(1))
            counts[letter, default: 0] += 1
            func n(_ key: String) -> CGFloat { CGFloat((entry[key] as? NSNumber)?.doubleValue ?? 0) * scale }
            return Item(id: letter + String(counts[letter]!), kind: kind, name: entry["name"] as? String ?? "", value: entry["value"] as? String ?? "",
                        focused: entry["focused"] as? Bool ?? false, frame: CGRect(x: n("x"), y: n("y"), width: n("w"), height: n("h")))
        }
    }

    static func text(_ items: [Item]) -> String {
        guard !items.isEmpty else { return "The preview's screen as text: nothing on it can be read." }
        let lines = items.prefix(150).map { item -> String in
            var line = "\(item.id) \(item.kind)"
            if !item.name.isEmpty { line += " \"\(item.name.prefix(80))\"" }
            if !item.value.isEmpty { line += " = \(item.value.prefix(60))" }
            if item.focused { line += ", has focus" }
            return line + " @\(Int(item.frame.midX.rounded())),\(Int(item.frame.midY.rounded())) \(Int(item.frame.width.rounded()))x\(Int(item.frame.height.rounded()))"
        }
        return "The preview's screen as text, in reading order. Each line is a thing's id, what it is, its name, \"= \" what it holds, whether it "
            + "has the remote's focus, then @x,y (its middle in the picture) and its size. Act on a thing with `target` set to its id "
            + "or exact name; x and y are for what isn't listed:\n" + lines.joined(separator: "\n")
            + (items.count > 150 ? "\n… and \(items.count - 150) more" : "")
    }


    // MARK: Using

    private static let keyCodes: [String: Int] = [
        "left": 37, "up": 38, "right": 39, "down": 40, "enter": 13, "return": 13, "ok": 13, "back": 10009, "escape": 10009, "space": 32,
        "play": 415, "pause": 19, "playpause": 10252, "stop": 413, "fastforward": 417, "rewind": 412,
        "red": 403, "green": 404, "yellow": 405, "blue": 406, "channelup": 427, "channeldown": 428, "info": 457,
    ]

    /// Carries out `use_app`'s actions on the preview, one after another, with the screen read again after each. The
    /// report says what each landed on and what has focus after it.
    static func perform(_ actions: [Simulator.Driver.Action], on project: LampProject, stillMine: @escaping @MainActor () -> Bool) async -> String {
        guard let preview = open[project.id] else { return "The app isn't open in the preview." }
        var screen = await items(project)
        var report: [String] = []
        func find(_ target: String) -> Item? {
            screen.first { $0.id == target } ?? screen.first { $0.name == target } ?? screen.first { $0.name.caseInsensitiveCompare(target) == .orderedSame }
        }
        func js(_ source: String) async -> String? { (try? await preview.webView.evaluateJavaScript(source)) as? String }
        for (index, action) in actions.enumerated() {
            guard stillMine() else { report.append("Stopped before action \(index + 1)."); break }
            let n = index + 1
            switch action.action {
            case "key":
                let name = (action.key ?? "").lowercased()
                // A digit, and on a device that isn't a TV a letter too (a game's WASD), as the keyboard sends them.
                let single = name.count == 1 ? name.unicodeScalars.first : nil
                let digit = single.flatMap { CharacterSet.decimalDigits.contains($0) ? Int($0.value) : nil }
                let letter = preview.isTV ? nil : single.flatMap { CharacterSet.lowercaseLetters.contains($0) && $0.isASCII ? Int($0.value) - 32 : nil }
                let back = !preview.isTV && (name == "back" || name == "escape")
                guard let code = back ? 27 : keyCodes[name] ?? digit ?? letter else {
                    let more = preview.isTV ? " and 0-9" : ", 0-9 and a-z"
                    report.append("\(n). Unknown key \"\(action.key ?? "")\"; the keys are \(keyCodes.keys.sorted().joined(separator: ", "))\(more).")
                    continue
                }
                // The key's name as the page reads it in `e.key`, which a game or the Xbox's arrow focus goes by.
                let keyName: String = switch code {
                case 37: "ArrowLeft"
                case 38: "ArrowUp"
                case 39: "ArrowRight"
                case 40: "ArrowDown"
                case 13: "Enter"
                case 27: "Escape"
                case 32: " "
                default: single.map { String($0) } ?? ""
                }
                // Held for `amount` seconds when given (a game's move forward), else a press.
                let hold = min(max(action.amount ?? 0, 0), 10)
                let source = """
                    (function () {
                      var target = document.activeElement || document.body;
                      function fire(type) {
                        var e = new KeyboardEvent(type, { bubbles: true, cancelable: true, key: \(String(reflecting: keyName)) });
                        Object.defineProperty(e, 'keyCode', { get: function () { return \(code); } });
                        Object.defineProperty(e, 'which', { get: function () { return \(code); } });
                        return target.dispatchEvent(e);
                      }
                      window.__lampHeldKey = fire;
                      var allowed = fire('keydown');
                      if (allowed && \(code) === 13 && /^(BUTTON|A)$/.test(target.tagName)) target.click();
                      if (\(hold > 0 ? "false" : "true")) fire('keyup');
                      return '';
                    })();
                    """
                _ = await js(source)
                if hold > 0 {
                    // Let go the moment the person takes the app back or presses Stop, not when the hold would have ended.
                    let until = Date().addingTimeInterval(hold)
                    while Date() < until, stillMine() { try? await Task.sleep(for: .milliseconds(100)) }
                    let held = hold - max(0, until.timeIntervalSinceNow)
                    _ = await js("(function () { if (window.__lampHeldKey) window.__lampHeldKey('keyup'); window.__lampHeldKey = null; return ''; })();")
                    guard stillMine() else { report.append("\(n). Held \(name) for \(held.formatted(.number.precision(.fractionLength(1)))) s, then stopped."); break }
                    report.append("\(n). Held \(name) for \(hold.formatted()) s.")
                } else {
                    report.append("\(n). Pressed \(name).")
                }
            case "click", "tap", "left_click", "double_click":
                let point: CGPoint
                var what = ""
                if let target = action.target {
                    guard let item = find(target) else { report.append("\(n). Nothing on screen matches \"\(target)\"."); continue }
                    point = CGPoint(x: item.frame.midX, y: item.frame.midY)
                    what = "\(item.kind) \"\(item.name)\""
                } else if let x = action.x, let y = action.y {
                    point = CGPoint(x: x, y: y)
                    what = "the point \(Int(x)),\(Int(y))"
                } else { report.append("\(n). click needs a target or x and y."); continue }
                _ = await js("""
                    (function () {
                      var el = document.elementFromPoint(\(point.x / preview.scale), \(point.y / preview.scale));
                      if (!el) return '';
                      var focusable = el.closest('[data-focus], button, a[href], input, select, textarea, [tabindex]') || el;
                      if (focusable.focus) focusable.focus();
                      if (focusable.click) focusable.click();
                      return '';
                    })();
                    """)
                report.append("\(n). Clicked \(what).")
            case "type":
                guard let text = action.text else { report.append("\(n). type needs text."); continue }
                let target = action.target.flatMap(find)
                let quoted = String(decoding: (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8), as: UTF8.self)
                let point = target.map { "document.elementFromPoint(\($0.frame.midX / preview.scale), \($0.frame.midY / preview.scale))" } ?? "document.activeElement"
                _ = await js("""
                    (function () {
                      var el = \(point);
                      if (!el || !('value' in el)) return '';
                      el.focus();
                      el.value = \(quoted)[0];
                      el.dispatchEvent(new Event('input', { bubbles: true }));
                      el.dispatchEvent(new Event('change', { bubbles: true }));
                      return '';
                    })();
                    """)
                report.append("\(n). Typed \"\(text)\".")
            case "wait":
                try? await Task.sleep(for: .seconds(min(action.amount ?? 1, 10)))
                report.append("\(n). Waited.")
            default:
                report.append("\(n). Unknown action \"\(action.action)\"; on a TV there are key, click, type and wait.")
                continue
            }
            try? await Task.sleep(for: .milliseconds(350))
            screen = await items(project)
            if let focused = screen.first(where: \.focused) { report[report.count - 1] += " Focus is on \(focused.kind) \"\(focused.name)\"." }
        }
        return report.joined(separator: "\n")
    }
}

/// What's on a page's screen, focusable things and text in reading order, as JSON (each thing's kind, name, value, whether it
/// has focus and its box in CSS pixels): read in the preview (`TVPreview.items`) and, by the same script, in the app around a
/// page on the Mac (`LampPageScreen` in LampPage.swift, where `GameKit.page` writes it in), so the agent reads one list
/// wherever it looks.
enum PageScreen {
    static let script = """
        (function () {
          var FOCUSABLE = '[data-focus], button, a[href], input, select, textarea, [tabindex]';
          var focused = document.activeElement, out = [];
          function box(el) {
            var r = el.getBoundingClientRect();
            if (r.width <= 0 || r.height <= 0 || r.right < 0 || r.bottom < 0 || r.left > window.innerWidth || r.top > window.innerHeight) return null;
            var s = window.getComputedStyle(el);
            if (s.visibility === 'hidden' || s.display === 'none' || parseFloat(s.opacity) === 0) return null;
            return r;
          }
          function words(t) { return (t || '').replace(/\\s+/g, ' ').trim(); }
          var all = document.body ? document.body.querySelectorAll('*') : [];
          for (var i = 0; i < all.length; i++) {
            var el = all[i], r = box(el);
            if (!r || el.tagName === 'SCRIPT' || el.tagName === 'STYLE') continue;
            var takes = el === focused || (el.matches(FOCUSABLE) && !(el.getAttribute('tabindex') === '-1' && !el.hasAttribute('data-focus')));
            if (takes) {
              var field = el.tagName === 'INPUT' || el.tagName === 'TEXTAREA';
              out.push({ kind: field ? 'field' : el.tagName === 'SELECT' ? 'choice' : 'button',
                name: words(el.getAttribute('aria-label') || el.getAttribute('alt') || (field ? el.getAttribute('placeholder') : el.innerText)).slice(0, 120),
                value: field ? String(el.value || '') : '', focused: el === focused, x: r.left, y: r.top, w: r.width, h: r.height });
              continue;
            }
            if (el.closest && el.parentElement && el.parentElement.closest(FOCUSABLE)) continue;
            var own = '';
            for (var c = el.firstChild; c; c = c.nextSibling) if (c.nodeType === 3) own += c.nodeValue;
            own = words(own);
            if (own) out.push({ kind: 'text', name: own.slice(0, 160), value: '', focused: false, x: r.left, y: r.top, w: r.width, h: r.height });
            else if (el.tagName === 'IMG' && el.getAttribute('alt')) out.push({ kind: 'image', name: words(el.getAttribute('alt')), value: '', focused: false, x: r.left, y: r.top, w: r.width, h: r.height });
          }
          return JSON.stringify(out);
        })();
        """
}

/// The staged copy of a TV app, served to its preview: only plain files inside the copy, each with its type (WebAssembly
/// is compiled as it arrives only when it says it's WebAssembly) and a part of one when asked (sound and video ask for
/// theirs in parts). Not kept in WebKit's cache, so an opening after a change has the files as they are now.
@MainActor
final class StagedFiles: NSObject, WKURLSchemeHandler {
    var folder: URL?
    /// What a shared page may reach (`SharedNetwork`), and the address it's served at: every file then carries the rules
    /// the app around it serves it with (`LampPageGuard`).
    var policy: NetworkPolicy?
    var own = "lamp-tv://app"
    /// Where the page may connect beyond its sites while it's open here, and load nothing from: Lamp's controllers relay,
    /// at the port it listens on now (`TVPreview.relaySites`). Never kept with its sites.
    var connect: [String] = []

    private static let types = ["html": "text/html", "htm": "text/html", "js": "text/javascript", "mjs": "text/javascript",
                                "css": "text/css", "json": "application/json", "wasm": "application/wasm", "svg": "image/svg+xml"]

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return task.didFailWithError(URLError(.badURL)) }
        guard let data = file(at: url) else {
            task.didReceive(HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: ["Cache-Control": "no-store"].merging(rules) { $1 })!)
            task.didFinish()
            return
        }
        let ext = url.pathExtension.lowercased()
        var headers = ["Content-Type": Self.types[ext] ?? UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream",
                       "Accept-Ranges": "bytes", "Cache-Control": "no-store"]
        var status = 200, body = data
        if let range = task.request.value(forHTTPHeaderField: "Range"), let part = Self.part(range, of: data.count) {
            status = 206
            body = data.subdata(in: part)
            headers["Content-Range"] = "bytes \(part.lowerBound)-\(part.upperBound - 1)/\(data.count)"
        }
        headers["Content-Length"] = String(body.count)
        headers.merge(rules) { $1 }
        task.didReceive(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!)
        task.didReceive(body)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    /// The rules every response of a shared page carries, a missing file's too.
    private var rules: [String: String] {
        guard let csp = policy?.contentSecurityPolicy(own: own, connect: connect) else { return [:] }
        return ["Content-Security-Policy": csp, "X-DNS-Prefetch-Control": "off"]
    }

    /// The file a page address names, when it's a plain file inside the staged copy (which never holds links).
    private func file(at url: URL) -> Data? {
        guard let folder, url.host == "app" else { return nil }
        let root = folder.standardizedFileURL.path + "/"
        let path = url.path.isEmpty || url.path.hasSuffix("/") ? url.path + "index.html" : url.path
        let file = folder.appendingPathComponent(path).standardizedFileURL
        guard file.path.hasPrefix(root),
              let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
        return try? Data(contentsOf: file, options: .alwaysMapped)
    }

    /// The bytes one `Range: bytes=…` asks for (a start and an end, a start alone, or the last n), within the file.
    static func part(_ header: String, of size: Int) -> Range<Int>? {
        guard header.hasPrefix("bytes="), !header.contains(","), size > 0 else { return nil }
        let bounds = header.dropFirst(6).split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard bounds.count == 2 else { return nil }
        switch (bounds[0], bounds[1]) {
        case let (start?, end?) where start <= end && start < size: return start..<(min(end, size - 1) + 1)
        case let (start?, nil) where start < size: return start..<size
        case let (nil, last?) where last > 0: return max(0, size - last)..<size
        default: return nil
        }
    }
}
