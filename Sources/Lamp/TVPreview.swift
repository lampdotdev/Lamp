import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers
import WebKit

/// The TV on this Mac's screen: a TV app opened at the TVs' own size (1920×1080, shown at half that), from the copy of
/// its files in Lamp's folder (`TVs.stage`). The agent looks at it and presses the remote's keys on it, as it does on a
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
    /// What the preview stands in for, as the person calls it: "TV", or a device app's device ("Xbox"). Back on a TV's
    /// remote is its own key; on anything else it's Escape, as an Xbox's B button sends.
    private var device = "TV"
    private var isTV: Bool { device == "TV" }
    private let window: NSWindow
    private let webView: WKWebView
    private let files = StagedFiles()
    private var loaded: CheckedContinuation<Void, Never>?
    /// When the open page was last pictured, so each picture can say how long after the one before it was taken.
    private var lastPictured: Date?
    private var log: FileHandle?

    static func isOpen(_ project: LampProject) -> Bool { open[project.id]?.window.isVisible == true }
    static var openIDs: [String] { open.filter { $0.value.window.isVisible }.map(\.key) }
    static func window(_ project: LampProject) -> NSWindow? { open[project.id]?.window }

    static func close(_ project: LampProject) {
        open[project.id]?.window.close()
        open[project.id] = nil
    }

    /// Opens the staged app (again, from the start), in front or behind what the person is doing. Nil once it has loaded.
    @discardableResult
    static func show(_ project: LampProject, staged: URL, inFront: Bool, device: String = "TV") async -> String? {
        let preview = open[project.id] ?? TVPreview(project: project)
        open[project.id] = preview
        preview.device = device
        preview.window.title = "\(project.name) on \(device)"
        return await preview.load(staged: staged, inFront: inFront)
    }

    static func bringForward(_ project: LampProject) {
        guard let preview = open[project.id] else { return }
        preview.window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private init(project: LampProject) {
        self.project = project
        let configuration = WKWebViewConfiguration()
        // What the app saves stays from one opening to the next, as on a TV: a store of its own for each app.
        configuration.websiteDataStore = UUID(uuidString: project.instance).map { WKWebsiteDataStore(forIdentifier: $0) } ?? .nonPersistent()
        let controller = WKUserContentController()
        // What the page prints, and what it throws, reach the log.
        controller.addUserScript(WKUserScript(source: Self.consoleScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController = controller
        configuration.setURLSchemeHandler(files, forURLScheme: Self.scheme)
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 960, height: 540), configuration: configuration)
        webView.pageZoom = 0.5
        webView.autoresizingMask = [.width, .height]
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 540), styleMask: [.titled, .closable, .miniaturizable, .resizable],
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

    func windowDidResize(_ notification: Notification) { webView.pageZoom = webView.bounds.width / 1920 }

    func windowWillClose(_ notification: Notification) {
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
    }

    private func load(staged: URL, inFront: Bool) async -> String? {
        Runtime.startLog(project)
        try? log?.close()
        log = try? AppFolder.appendHandle(Runtime.logURL(project), in: project.dir)
        files.folder = staged
        lastPictured = nil
        // WebKit keeps the scripts and styles a page loaded and serves them again for the same address, so an
        // opening after a change would run the app's code as it first was. Its saved data stays: only the caches go.
        await webView.configuration.websiteDataStore.removeData(ofTypes: [WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeDiskCache],
                                                                modifiedSince: .distantPast)
        // Closed while the caches went: loading now would start the app again in a preview nobody can see or close.
        guard Self.open[project.id] === self else { return "The TV preview was closed before the app opened." }
        let carried = await savedFromFileAddress(staged)
        guard Self.open[project.id] === self else { return "The TV preview was closed before the app opened." }
        if let carried { webView.configuration.userContentController.addUserScript(Self.restoreScript(carried)) }
        await navigate { $0.load(URLRequest(url: Self.home)) }
        if carried != nil {
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
        webView.pageZoom = webView.bounds.width / 1920
        // Its scripts start on load; a moment more lets a first screen draw and take focus.
        try? await Task.sleep(for: .milliseconds(600))
        return nil
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

    /// Puts back what was handed over, before the app's own scripts run, leaving alone anything already saved here, and
    /// says it did in a world of its own, which the app's scripts can't see or set.
    private static let restoreWorld = WKContentWorld.world(name: "lampRestore")
    private static func restoreScript(_ saved: String) -> WKUserScript {
        WKUserScript(source: """
            (function () {
              if (location.protocol !== '\(scheme):') return;
              var s = \(saved);
              for (var k in s) if (localStorage.getItem(k) === null) localStorage.setItem(k, s[k]);
              window.lampRestored = true;
            })();
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: restoreWorld)
    }

    private func finishLoading() {
        loaded?.resume()
        loaded = nil
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finishLoading() }
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

    /// LampAI in the preview (`DeviceSupport.webJS`): its calls are answered by Lamp in this process, as the app, with
    /// no token for the page to hold and no network between them. Only the AI routes an app uses.
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        // Only the app's own page, from its staged copy: never a frame inside it or a page it went on to, which could be
        // anyone's and would use AI as the app.
        guard message.frameInfo.isMainFrame, let page = message.frameInfo.request.url, page.scheme == Self.scheme, page.host == Self.home.host,
              let call = message.body as? [String: Any], let path = call["path"] as? String,
              ["/ai", "/ai/status", "/ai/image", "/ai/decide"].contains(path),
              let current = Store.shared.projects.first(where: { $0.id == project.id }) else {
            replyHandler(["status": 404, "body": #"{"error":"Not found"}"#], nil)
            return
        }
        let request = Gateway.Request(method: "POST", path: path,
                                      headers: ["authorization": "Bearer " + Template.token(for: current), "host": "127.0.0.1:\(Gateway.port)"],
                                      body: Data((call["body"] as? String ?? "{}").utf8))
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
            configuration.snapshotWidth = 960
            if let image = try? await preview.webView.takeSnapshot(configuration: configuration),
               let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), let png = halfSize(cg) { taken = (png, false) }
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

    /// The page drawn 960 pixels across, the size `use_app`'s points are measured in, whatever the screen's scale.
    private static func halfSize(_ page: CGImage) -> Data? {
        let width = 960, height = Int((960 * CGFloat(page.height) / CGFloat(page.width)).rounded())
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
        return image.cropping(to: crop).flatMap(Self.halfSize)
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
              let json = try? await preview.webView.evaluateJavaScript(screenScript) as? String,
              let list = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]] else { return [] }
        var counts: [String: Int] = [:]
        return list.compactMap { entry in
            guard let kind = entry["kind"] as? String else { return nil }
            let letter = String(kind.prefix(1))
            counts[letter, default: 0] += 1
            func n(_ key: String) -> CGFloat { CGFloat((entry[key] as? NSNumber)?.doubleValue ?? 0) / 2 }
            return Item(id: letter + String(counts[letter]!), kind: kind, name: entry["name"] as? String ?? "", value: entry["value"] as? String ?? "",
                        focused: entry["focused"] as? Bool ?? false, frame: CGRect(x: n("x"), y: n("y"), width: n("w"), height: n("h")))
        }
    }

    static func text(_ items: [Item]) -> String {
        guard !items.isEmpty else { return "The TV preview's screen as text: nothing on it can be read." }
        let lines = items.prefix(150).map { item -> String in
            var line = "\(item.id) \(item.kind)"
            if !item.name.isEmpty { line += " \"\(item.name.prefix(80))\"" }
            if !item.value.isEmpty { line += " = \(item.value.prefix(60))" }
            if item.focused { line += ", has focus" }
            return line + " @\(Int(item.frame.midX.rounded())),\(Int(item.frame.midY.rounded())) \(Int(item.frame.width.rounded()))x\(Int(item.frame.height.rounded()))"
        }
        return "The TV preview's screen as text, in reading order. Each line is a thing's id, what it is, its name, \"= \" what it holds, whether it "
            + "has the remote's focus, then @x,y (its middle in the picture) and its size. Act on a thing with `target` set to its id "
            + "or exact name; x and y are for what isn't listed:\n" + lines.joined(separator: "\n")
            + (items.count > 150 ? "\n… and \(items.count - 150) more" : "")
    }

    private static let screenScript = """
        (function () {
          var FOCUSABLE = '[data-focus], button, a[href], input, select, textarea, [tabindex]';
          var focused = document.activeElement, out = [];
          function box(el) {
            var r = el.getBoundingClientRect();
            if (r.width <= 0 || r.height <= 0 || r.right < 0 || r.bottom < 0 || r.left > 1920 || r.top > 1080) return null;
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
                      var el = document.elementFromPoint(\(point.x * 2), \(point.y * 2));
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
                let point = target.map { "document.elementFromPoint(\($0.frame.midX * 2), \($0.frame.midY * 2))" } ?? "document.activeElement"
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

/// The staged copy of a TV app, served to its preview: only plain files inside the copy, each with its type (WebAssembly
/// is compiled as it arrives only when it says it's WebAssembly) and a part of one when asked (sound and video ask for
/// theirs in parts). Not kept in WebKit's cache, so an opening after a change has the files as they are now.
@MainActor
final class StagedFiles: NSObject, WKURLSchemeHandler {
    var folder: URL?

    private static let types = ["html": "text/html", "htm": "text/html", "js": "text/javascript", "mjs": "text/javascript",
                                "css": "text/css", "json": "application/json", "wasm": "application/wasm", "svg": "image/svg+xml"]

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return task.didFailWithError(URLError(.badURL)) }
        guard let data = file(at: url) else {
            task.didReceive(HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: ["Cache-Control": "no-store"])!)
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
        task.didReceive(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!)
        task.didReceive(body)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

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
