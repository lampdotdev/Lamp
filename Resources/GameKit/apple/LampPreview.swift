// Lamp's TV preview as an app of its own: a TV app's page, or a game for a TV or the Xbox, on this Mac's screen at the
// TV's size, in a copy of Lamp's player (LampPlayer.swift) made for that one app. It runs the app's phones itself (its
// phone page and relay, LampControllerKit.swift, from the Phone/ folder in its bundle), so a game in the preview goes
// on playing, and new phones join it, whether Lamp is open or not. Lamp opens it, and while Lamp is open it looks at
// the preview and uses it for the agent through a channel of its own on this Mac (`LampPreviewControl`); without Lamp
// the preview is just the app, until its window is closed.
//
// Its folder, which Lamp keeps for it, holds the copy itself (the bundle), the versions of the page Lamp has handed it
// (Pages/<version>, each as it was when handed over, never changed after), which one to open (`current`), and what
// Lamp needs to reach it (control.json, readable only by this Mac's user). What the page saves is kept by WebKit for
// this app alone, under its own store.
import AppKit
import CryptoKit
import Network
import ScreenCaptureKit
import WebKit

/// What Lamp wrote in the copy's Info.plist about the preview (`LampPlayer` in it).
enum LampPreviewInfo {
    private static let info = Bundle.main.object(forInfoDictionaryKey: "LampPlayer") as? [String: Any] ?? [:]

    /// The window's title: "Clock on TV", "Racer on Xbox".
    static var title: String { info["title"] as? String ?? LampPlayer.name }
    /// Whether the preview stands in for a TV, whose Back is a key of its own, or another device (Escape).
    static var isTV: Bool { info["tv"] as? Bool ?? true }
    /// The store what the page saves is kept in, the same at every opening.
    static var store: UUID? { (info["store"] as? String).flatMap(UUID.init(uuidString:)) }
    /// The preview's folder: the one the copy is in.
    static var folder: URL { Bundle.main.bundleURL.deletingLastPathComponent() }
}

@MainActor final class LampPreviewApp: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate {
    private static var shared: LampPreviewApp?

    static func run() -> Never {
        let app = NSApplication.shared
        let delegate = LampPreviewApp()
        shared = delegate
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        exit(0)
    }

    let files = LampPageFiles(scheme: "lamp-tv")
    private(set) var window: NSWindow!
    private(set) var webView: WKWebView!
    /// The page's size in CSS pixels: a TV's, or the shape a screen is looked at in.
    private(set) var shape = CGSize(width: 1920, height: 1080)
    /// Which of the page's versions is open.
    private(set) var version = ""
    /// This opening of the preview: a new one is a new session for phones too.
    let run = UUID().uuidString
    private var loaded: CheckedContinuation<Void, Never>?
    private var control: LampPreviewControl?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LampPageLog.file = Self.openLog()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = LampPreviewInfo.store.map { WKWebsiteDataStore(forIdentifier: $0) } ?? .nonPersistent()
        configuration.setURLSchemeHandler(files, forURLScheme: files.scheme)
        LampPage.attach(to: configuration, scheme: files.scheme)
        configuration.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 960, height: 540), configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.pageZoom = 0.5
        webView.navigationDelegate = self
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 540), styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = LampPreviewInfo.title
        window.contentView = LampKeyCatcher(holding: webView)
        window.contentAspectRatio = NSSize(width: 16, height: 9)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("LampTVPreview")
        if window.frame.origin == .zero { window.center() }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(webView)
        NSApp.activate()
        Task {
            await carrySaved()
            if let current = try? String(contentsOf: LampPreviewInfo.folder.appendingPathComponent("current"), encoding: .utf8) {
                _ = await load(current.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            // Only once the page is open: Lamp, reaching it, finds it as it is.
            do { control = try LampPreviewControl(app: self) } catch { LampPageLog.write("Error: Lamp can't reach the preview: \(error)") }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) { control?.stop() }

    func windowDidResize(_ notification: Notification) { webView.pageZoom = webView.bounds.width / shape.width }

    func windowWillClose(_ notification: Notification) {
        // The page goes with the window, its sound and timers included, and with it the app's phones.
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        control?.stop()
    }

    // MARK: Opening the page

    /// Opens a version of the page Lamp handed over (Pages/<version>), from its start. A name that isn't one of them is
    /// refused: the preview serves only what's in its own folder.
    func load(_ version: String) async -> String? {
        guard Self.isVersion(version) else { return "No such version of the app." }
        let folder = LampPreviewInfo.folder.appendingPathComponent("Pages").appendingPathComponent(version)
        guard (try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])).map({ $0.isDirectory == true && $0.isSymbolicLink != true }) == true,
              FileManager.default.fileExists(atPath: folder.appendingPathComponent("index.html").path) else { return "No such version of the app." }
        files.folder = folder
        self.version = version
        // WebKit keeps the scripts and styles a page loaded and serves them again for the same address: only the caches go.
        await webView.configuration.websiteDataStore.removeData(ofTypes: [WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeDiskCache], modifiedSince: .distantPast)
        await navigate { $0.load(URLRequest(url: URL(string: "lamp-tv://app/index.html")!)) }
        webView.pageZoom = webView.bounds.width / shape.width
        return nil
    }

    static func isVersion(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 64 && name.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "-" || $0 == "_" }
    }

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

    private func finishLoading() {
        loaded?.resume()
        loaded = nil
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finishLoading() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        LampPageLog.write("Error: the page didn't load: \(error.localizedDescription)")
        finishLoading()
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        LampPageLog.write("Error: the page didn't load: \(error.localizedDescription)")
        finishLoading()
    }

    // MARK: What the page saved in Lamp's own preview

    /// What the app's page saved while the preview was a window of Lamp's own, handed over once (carry.json, which Lamp
    /// wrote from that store and keeps as the copy it was): put in this preview's store before the app's page first
    /// opens, never over anything saved here since, and read back before it's marked done (carry.done), so a handover
    /// that didn't finish is tried again at the next opening. Lamp's own store is left as it was.
    private func carrySaved() async {
        let folder = LampPreviewInfo.folder
        let done = folder.appendingPathComponent("carry.done")
        guard !FileManager.default.fileExists(atPath: done.path),
              let data = try? Data(contentsOf: folder.appendingPathComponent("carry.json")),
              let carried = try? JSONSerialization.jsonObject(with: data) as? [String: Any], carried["version"] as? Int == 1,
              let saved = carried["saved"] as? [String: String], !saved.isEmpty,
              let json = try? JSONSerialization.data(withJSONObject: saved), let text = String(data: json, encoding: .utf8) else { return }
        // An empty page at the app's own address, which is what its saves are kept under, with nothing of the app's run.
        await navigate { $0.loadHTMLString("", baseURL: URL(string: "lamp-tv://app/")!) }
        let put = """
            (function () {
              var s = \(text), same = true;
              for (var k in s) if (localStorage.getItem(k) === null) localStorage.setItem(k, s[k]);
              for (var k in s) if (localStorage.getItem(k) === null) same = false;
              return same;
            })();
            """
        if (try? await webView.evaluateJavaScript(put)) as? Bool == true {
            FileManager.default.createFile(atPath: done.path, contents: Data(), attributes: [.posixPermissions: 0o600])
        } else {
            LampPageLog.write("Warning: what the app saved in Lamp's preview couldn't be brought over yet; it's tried again at the next opening.")
        }
    }

    // MARK: For Lamp

    func reshape(to size: CGSize) async {
        guard size.width >= 200, size.height >= 200, size != shape else { return }
        shape = size
        let top = window.frame.maxY
        window.contentAspectRatio = size
        let scale = 960 / max(size.width, size.height)
        window.setContentSize(NSSize(width: size.width * scale, height: size.height * scale))
        var frame = window.frame
        frame.origin.y = top - frame.height
        window.setFrame(frame, display: true)
        webView.pageZoom = webView.bounds.width / size.width
        try? await Task.sleep(for: .milliseconds(500))
    }

    func bringForward() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// The window as the screen shows it, cut to the page (an app may capture its own windows without asking, 14.4 on),
    /// or WebKit's own drawing of the page, which can't show what CSS animates. At `width` pixels across.
    func picture(width: CGFloat) async -> (png: Data, moving: Bool)? {
        if #available(macOS 14.4, *), let png = await captured(width: width) { return (png, true) }
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = NSNumber(value: Double(width))
        guard let image = try? await webView.takeSnapshot(configuration: configuration),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), let png = sized(cg, width: width) else { return nil }
        return (png, false)
    }

    @available(macOS 14.4, *)
    private func captured(width: CGFloat) async -> Data? {
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
        let page = webView.convert(webView.bounds, to: nil)
        let crop = CGRect(x: page.minX * scale, y: (filter.contentRect.height - page.maxY) * scale,
                          width: page.width * scale, height: page.height * scale).integral
        return image.cropping(to: crop).flatMap { sized($0, width: width) }
    }

    private func sized(_ page: CGImage, width pixels: CGFloat) -> Data? {
        let width = Int(pixels.rounded()), height = Int((CGFloat(width) * CGFloat(page.height) / CGFloat(page.width)).rounded())
        guard width > 0, height > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                                            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        context.cgContext.interpolationQuality = .high
        context.cgContext.setFillColor(.black)
        context.cgContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.cgContext.draw(page, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bitmap.representation(using: .png, properties: [:])
    }

    // MARK: The log

    /// What the page prints, in the preview's folder (console.log), where Lamp reads it into the app's log as it looks.
    /// Started afresh past a few megabytes, so a page that prints all the time while nobody looks can't fill the disk.
    private static func openLog() -> FileHandle? {
        let url = LampPreviewInfo.folder.appendingPathComponent("console.log")
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 4 << 20 { try? FileManager.default.removeItem(at: url) }
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        return fd < 0 ? nil : FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }
}

/// How Lamp reaches the preview while both are open: a socket on this Mac's loopback only, at a port the system gives,
/// written with a key made for this opening into control.json in the preview's folder, which only this Mac's user can
/// read. Every request carries the key; one without it closes the connection. What Lamp may ask is the preview's own
/// business and nothing more: open a version of the page Lamp handed over, change the window's shape or title, bring it
/// forward, picture it, run script in the app's page (what reads the screen and presses the remote's keys for the
/// agent), and close it. Nothing here runs a command or reads a file. Lamp going away takes only this channel: the
/// app, its saves and its phones stay.
@MainActor final class LampPreviewControl {
    private let listener: NWListener
    private let key: String
    private let file = LampPreviewInfo.folder.appendingPathComponent("control.json")
    private weak var app: LampPreviewApp?
    /// The most a request may be: a page's script, never a picture's worth.
    static let requestLimit = 1 << 20

    init(app: LampPreviewApp) throws {
        self.app = app
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw CocoaError(.featureUnsupported) }
        key = Data(bytes).base64EncodedString()
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        params.allowLocalEndpointReuse = false
        listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard case .ready = state else { return }
            MainActor.assumeIsolated { self?.publish() }
        }
        listener.start(queue: .main)
    }

    func stop() {
        listener.cancel()
        try? FileManager.default.removeItem(at: file)
    }

    /// control.json, written whole (made beside it and moved into place) and readable by this Mac's user alone.
    private func publish() {
        guard let port = listener.port?.rawValue, let app else { return }
        let said: [String: Any] = ["port": Int(port), "key": key, "pid": Int(getpid()), "run": app.run]
        guard let data = try? JSONSerialization.data(withJSONObject: said) else { return }
        let partial = file.deletingLastPathComponent().appendingPathComponent(".control-" + UUID().uuidString)
        guard FileManager.default.createFile(atPath: partial.path, contents: data, attributes: [.posixPermissions: 0o600]) else { return }
        if rename(partial.path, file.path) != 0 { try? FileManager.default.removeItem(at: partial) }
    }

    private func accept(_ connection: NWConnection) {
        // Only from this Mac's loopback, which is all the listener is on; anything else is let go.
        guard case .hostPort(let host, _) = connection.endpoint, "\(host)" == "127.0.0.1" else { return connection.cancel() }
        connection.start(queue: .main)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, done, error in
            MainActor.assumeIsolated {
                guard let self else { return connection.cancel() }
                var buffer = buffer
                if let data { buffer.append(data) }
                guard buffer.count <= Self.requestLimit else { return connection.cancel() }
                if let end = buffer.firstIndex(of: 0x0A) {
                    let line = buffer[..<end]
                    Task { @MainActor in
                        guard let answer = await self.answer(Data(line)) else { return connection.cancel() }
                        var out = (try? JSONSerialization.data(withJSONObject: answer)) ?? Data("{}".utf8)
                        out.append(0x0A)
                        connection.send(content: out, completion: .contentProcessed { _ in connection.cancel() })
                    }
                } else if done || error != nil {
                    connection.cancel()
                } else {
                    self.receive(connection, buffer: buffer)
                }
            }
        }
    }

    /// Nil: the request isn't Lamp's (no key, or the wrong one), and the connection is closed without an answer.
    private func answer(_ line: Data) async -> [String: Any]? {
        guard let request = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let given = request["key"] as? String, Self.same(given, key) else { return nil }
        guard let app else { return ["error": "The preview is closing."] }
        switch request["op"] as? String {
        case "hello":
            return ["run": app.run, "pid": Int(getpid()), "version": app.version, "window": app.window.windowNumber,
                    "shape": [app.shape.width, app.shape.height], "title": app.window.title]
        case "load":
            if let problem = await app.load(request["version"] as? String ?? "") { return ["error": problem] }
            if request["front"] as? Bool == true { app.bringForward() } else { app.window.orderFront(nil) }
            // A moment more lets a first screen draw and take focus.
            try? await Task.sleep(for: .milliseconds(600))
            return ["ok": true]
        case "title":
            if let title = request["title"] as? String { app.window.title = String(title.prefix(200)) }
            return ["ok": true]
        case "shape":
            let w = (request["width"] as? NSNumber)?.doubleValue ?? 0, h = (request["height"] as? NSNumber)?.doubleValue ?? 0
            await app.reshape(to: CGSize(width: min(w, 4000), height: min(h, 4000)))
            return ["shape": [app.shape.width, app.shape.height]]
        case "front":
            app.bringForward()
            return ["ok": true]
        case "picture":
            let width = min(max((request["width"] as? NSNumber)?.doubleValue ?? 960, 100), 1920)
            guard let taken = await app.picture(width: width) else { return ["error": "No picture could be taken."] }
            return ["png": taken.png.base64EncodedString(), "moving": taken.moving]
        case "script":
            guard let source = request["source"] as? String else { return ["error": "No script."] }
            let value = try? await app.webView.evaluateJavaScript(source)
            return ["value": value as? String ?? ""]
        case "close":
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { app.window.close() }
            return ["ok": true]
        default:
            return ["error": "Unknown request."]
        }
    }

    /// The key compared in time that doesn't depend on where it differs.
    static func same(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in x.indices { diff |= x[i] ^ y[i] }
        return diff == 0
    }
}
