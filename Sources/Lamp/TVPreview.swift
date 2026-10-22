import AppKit
import WebKit

/// The TV on this Mac's screen: a TV app opened at the TVs' own size (1920×1080, shown at half that), from the copy of
/// its files in Lamp's folder (`TVs.stage`). The agent looks at it and presses the remote's keys on it, as it does on a
/// simulator; the person can use it with the keyboard's arrows, Return and Escape. What the page prints goes to the
/// app's log.
@MainActor
final class TVPreview: NSObject, WKScriptMessageHandler, WKScriptMessageHandlerWithReply, WKNavigationDelegate, NSWindowDelegate {
    private static var open: [String: TVPreview] = [:]

    private let project: LampProject
    private let window: NSWindow
    private let webView: WKWebView
    private var loaded: CheckedContinuation<Void, Never>?
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
    static func show(_ project: LampProject, staged: URL, inFront: Bool) async -> String? {
        let preview = open[project.id] ?? TVPreview(project: project)
        open[project.id] = preview
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
        try? log?.close()
        log = nil
        Self.open[project.id] = nil
        Store.shared.refreshOpenApps()
    }

    private func load(staged: URL, inFront: Bool) async -> String? {
        Runtime.startLog(project)
        try? log?.close()
        log = try? AppFolder.appendHandle(Runtime.logURL(project), in: project.dir)
        let index = staged.appendingPathComponent("index.html")
        // WebKit keeps the scripts and styles a page loaded and serves them again for the same file's address, so an
        // opening after a change would run the app's code as it first was. Its saved data stays: only the caches go.
        await webView.configuration.websiteDataStore.removeData(ofTypes: [WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeDiskCache],
                                                                modifiedSince: .distantPast)
        await withCheckedContinuation { continuation in
            loaded = continuation
            webView.loadFileURL(index, allowingReadAccessTo: staged)
            Task {
                try? await Task.sleep(for: .seconds(10))
                self.finishLoading()
            }
        }
        if inFront { window.makeKeyAndOrderFront(nil); NSApp.activate() } else { window.orderFront(nil) }
        webView.pageZoom = webView.bounds.width / 1920
        // Its scripts start on load; a moment more lets a first screen draw and take focus.
        try? await Task.sleep(for: .milliseconds(600))
        return nil
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
        let staged = TVs.stagingFolder(for: project).appendingPathComponent("web").standardizedFileURL.path + "/"
        guard message.frameInfo.isMainFrame, let page = message.frameInfo.request.url, page.isFileURL,
              page.standardizedFileURL.path.hasPrefix(staged),
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

    /// A picture of the screen at half the TV's size: a pixel in it is two of the page's.
    static func picture(_ project: LampProject) async -> Data? {
        guard let preview = open[project.id] else { return nil }
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = 960
        guard let image = try? await preview.webView.takeSnapshot(configuration: configuration),
              let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
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
        guard !items.isEmpty else { return "The screen as text: nothing on it can be read." }
        let lines = items.prefix(150).map { item -> String in
            var line = "\(item.id) \(item.kind)"
            if !item.name.isEmpty { line += " \"\(item.name.prefix(80))\"" }
            if !item.value.isEmpty { line += " = \(item.value.prefix(60))" }
            if item.focused { line += ", has focus" }
            return line + " @\(Int(item.frame.midX.rounded())),\(Int(item.frame.midY.rounded())) \(Int(item.frame.width.rounded()))x\(Int(item.frame.height.rounded()))"
        }
        return "The screen as text, in reading order. Each line is a thing's id, what it is, its name, \"= \" what it holds, whether it "
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
        "left": 37, "up": 38, "right": 39, "down": 40, "enter": 13, "return": 13, "ok": 13, "back": 10009, "escape": 10009,
        "play": 415, "pause": 19, "playpause": 10252, "stop": 413, "fastforward": 417, "rewind": 412,
        "red": 403, "green": 404, "yellow": 405, "blue": 406, "channelup": 427, "channeldown": 428, "info": 457,
    ]

    /// Carries out `use_app`'s actions on the preview, one after another, with the screen read again after each. The
    /// report says what each landed on and what has focus after it.
    static func perform(_ actions: [Simulator.Driver.Action], on project: LampProject, stillMine: @escaping @MainActor () -> Bool) async -> String {
        guard let preview = open[project.id] else { return "The app isn't open in the TV preview." }
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
                let digit = name.count == 1 && name.first!.isNumber ? 48 + Int(String(name))! : nil
                guard let code = keyCodes[name] ?? digit else {
                    report.append("\(n). Unknown key \"\(action.key ?? "")\"; the remote's keys are \(keyCodes.keys.sorted().joined(separator: ", ")) and 0-9.")
                    continue
                }
                let source = """
                    (function () {
                      var target = document.activeElement || document.body;
                      function fire(type) {
                        var e = new KeyboardEvent(type, { bubbles: true, cancelable: true });
                        Object.defineProperty(e, 'keyCode', { get: function () { return \(code); } });
                        Object.defineProperty(e, 'which', { get: function () { return \(code); } });
                        return target.dispatchEvent(e);
                      }
                      var allowed = fire('keydown');
                      if (allowed && \(code) === 13 && /^(BUTTON|A)$/.test(target.tagName)) target.click();
                      fire('keyup');
                      return '';
                    })();
                    """
                _ = await js(source)
                report.append("\(n). Pressed \(name).")
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
