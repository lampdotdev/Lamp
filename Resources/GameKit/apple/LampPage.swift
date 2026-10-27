// Lamp's common host for a page, on the Mac, the iPhone and the iPad: whatever the page is (a game drawn with three.js,
// an app), the app around it serves it, shows it and answers it here. Lamp writes this file before every build.
//
// The page is Web/ in a web view of the app's own, served from the app's bundle at an address of its own
// (<scheme>://app/, `LampPageFiles`), never as a file, so it reads its own files with fetch and loads its modules; the
// address is the app's for good, since what the page saves (localStorage, IndexedDB) is kept under it. What it asks of Lamp (LampAI in Web/lamp.js) goes through this
// app with the app's own token, never the page's; what it asks of this device (`LampNative.call` in lamp.js: the
// person's mail, calendar, reminders, photos…) is answered by Swift in Sources/Native.swift, the app's own code, with
// Lamp's building blocks in LampSupport.swift. Only the app's own page, in its main frame, is answered.
import Combine
import Foundation
import UniformTypeIdentifiers
import WebKit
#if os(iOS)
import UIKit
#endif

/// Calls the page can make of this device, by name. Register each in `Native.register()` (Sources/Native.swift):
///
///     LampNative.on("unanswered") { args in
///         let limit = args["limit"] as? Int ?? 20
///         return try await LampMail.inbox(limit: limit).filter { !$0.isRead }.map { ["subject": $0.subject, "from": $0.sender] }
///     }
///
/// The page calls it with `LampNative.call("unanswered", { limit: 30 })`, a Promise of what the handler returned as JSON
/// (dates as ISO 8601 strings). A thrown error rejects the Promise with its message, which the page shows in its own
/// words. Return only what the page needs: everything returned is the page's.
@MainActor enum LampNative {
    typealias Handler = @MainActor ([String: Any]) async throws -> Data

    private(set) static var handlers: [String: Handler] = [:]

    /// A call the page may make, answering with anything Encodable (a struct, an array, a dictionary of strings…).
    static func on<Answer: Encodable>(_ name: String, _ handler: @escaping @MainActor ([String: Any]) async throws -> Answer) {
        handlers[name] = { args in
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(try await handler(args))
        }
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
        init(_ message: String) { self.message = message }
    }
}

@MainActor enum LampPage {
    private static var registered = false

    /// Gives the page in `configuration` its ways to Lamp and to this device, for pages served at `scheme`. A page that
    /// logs its own errors (a game's runtime does) leaves `catchErrors` off, or each would be logged twice.
    static func attach(to configuration: WKWebViewConfiguration, scheme: String, catchErrors: Bool = true) {
        if !registered { registered = true; Native.register() }
        let gateway = LampPageGateway(scheme: scheme)
        configuration.userContentController.addScriptMessageHandler(gateway, contentWorld: .page, name: "lampGateway")
        configuration.userContentController.addScriptMessageHandler(LampPageNative(scheme: scheme), contentWorld: .page, name: "lampNative")
        configuration.userContentController.add(LampPageWish(scheme: scheme), contentWorld: .page, name: "lampWish") // the wish's other apps
        configuration.userContentController.add(LampPageLog(), name: "lampLog")
        // The page's console, into the app's log.
        configuration.userContentController.addUserScript(WKUserScript(source: """
            (function () {
              var send = function (kind) { return function () { try { window.webkit.messageHandlers.lampLog.postMessage(kind + Array.prototype.join.call(arguments, ' ')); } catch (e) {} }; };
              console.log = send(''); console.warn = send('Warning: '); console.error = send('Error: ');
              if (\(catchErrors)) {
                window.addEventListener('error', function (e) { send('Error: ')(e.message + ' (' + (e.filename || '').split('/').pop() + ':' + e.lineno + ')'); });
                window.addEventListener('unhandledrejection', function (e) { send('Error: ')(String(e.reason && e.reason.message || e.reason)); });
              }
            })();
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    static func isOwnPage(_ message: WKScriptMessage, scheme: String) -> Bool {
        message.frameInfo.isMainFrame && message.frameInfo.securityOrigin.protocol == scheme
    }
}

/// The page's way to Lamp: only the routes LampAI uses, with the app's own token.
final class LampPageGateway: NSObject, WKScriptMessageHandlerWithReply {
    private static let routes: Set<String> = ["/ai", "/ai/status", "/ai/image", "/ai/decide"]
    private let scheme: String
    init(scheme: String) { self.scheme = scheme }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard LampPage.isOwnPage(message, scheme: scheme),
              let call = message.body as? [String: Any], let path = call["path"] as? String, Self.routes.contains(path),
              let url = URL(string: lampGateway + path) else {
            return replyHandler(["status": 404, "body": #"{"error":"Not found"}"#], nil)
        }
        var request = URLRequest(url: url, timeoutInterval: 240)
        request.httpMethod = "POST"
        request.setValue("Bearer " + LampInstall.token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data((call["body"] as? String ?? "{}").utf8)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 502
            let body = data.map { String(decoding: $0, as: UTF8.self) } ?? #"{"error":"Couldn't reach Lamp on your Mac. Open Lamp and try again."}"#
            DispatchQueue.main.async { replyHandler(["status": status, "body": body], nil) }
        }.resume()
    }
}

/// The page's calls of this device, answered by the handlers `Native.register()` gave.
final class LampPageNative: NSObject, WKScriptMessageHandlerWithReply {
    private let scheme: String
    init(scheme: String) { self.scheme = scheme }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard LampPage.isOwnPage(message, scheme: scheme), let call = message.body as? [String: Any],
              let name = call["name"] as? String else { return replyHandler(nil, "Not found") }
        let args = (call["args"] as? String).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } as? [String: Any] ?? [:]
        Task { @MainActor in
            guard let handler = LampNative.handlers[name] else {
                return replyHandler(nil, "This app has no call named \(name).")
            }
            do {
                replyHandler(String(decoding: try await handler(args), as: UTF8.self), nil)
            } catch {
                FileHandle.standardError.write(Data("LampNative \(name) failed: \(error.localizedDescription)\n".utf8))
                replyHandler(nil, error.localizedDescription)
            }
        }
    }
}

// MARK: - The wish's other apps

/// The page's `Lamp.wish` (Web/lamp.js), answered by this app's own `LampWish` (LampSupport.swift): the app is the wish's
/// peer, as every Swift app of a wish is (it listens, is found on the network and keeps the values on this device, so
/// it goes on with Lamp closed), and the page mirrors it. What the app hears goes to the page's `window.__lampWish`.
/// Only an app whose wish has other apps has this, as only it has `LampWish`.
@MainActor final class LampPageWish: NSObject, WKScriptMessageHandler {
    private let scheme: String
    private weak var page: WKWebView?
    private var listening = false
    private var filesHeard = false
    private var watching: AnyCancellable?
    private var transfers: [Int: LampTransfer] = [:]
    private var watchingTransfers: [Int: AnyCancellable] = [:]
    /// The shared collections the page uses (`LampStore.shared` in lamp.js), which this app keeps: told whole once, then
    /// as they change.
    private var collections: Set<String> = []
    init(scheme: String) { self.scheme = scheme }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard LampPage.isOwnPage(message, scheme: scheme), let call = message.body as? [String: Any], let op = call["op"] as? String else { return }
        let wish = LampWish.shared
        switch op {
        case "start":
            page = message.webView
            listen(to: wish)
            wish.start()
            tellState()
            tellValues([])
        case "stop":
            wish.stop()
        case "send":
            guard let data = Self.json(call["data"]) else { return }
            wish.send(data, to: call["to"] as? String)
        case "set":
            guard let key = call["key"] as? String else { return }
            let value = Self.json(call["value"])
            wish.set(key, value is NSNull ? nil : value)
        case "files":
            guard !filesHeard else { return }
            filesHeard = true
            wish.onFile { [weak self] from, file in
                self?.tell(["t": "file", "from": from, "copy": file.copy, "name": file.name, "type": file.type, "data": file.data.base64EncodedString()])
            }
        case "sendFile":
            guard let id = call["id"] as? Int, let to = call["to"] as? String,
                  let data = (call["data"] as? String).flatMap({ Data(base64Encoded: $0) }) else { return }
            let transfer = wish.sendFile(data, name: call["name"] as? String ?? "file", type: call["type"] as? String ?? "application/octet-stream", to: to)
            transfers[id] = transfer
            watchingTransfers[id] = transfer.objectWillChange.sink { [weak self] _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.tellTransfer(id) } }
            }
            tellTransfer(id)
        case "cancel":
            guard let id = call["id"] as? Int else { return }
            transfers[id]?.cancel()
        case "shared":
            guard let name = call["s"] as? String, LampWish.isCollection(name) else { return }
            page = message.webView
            // Heard once; told whole each time the page asks, a page loaded again included.
            if collections.insert(name).inserted {
                wish.onItems(in: name) { [weak self] changed, from in self?.tellItems(name, changed.map { ($0.0, $0.1) }, whole: false, from: from) }
            }
            tellItems(name, wish.items(in: name).map { ($0.id, $0.value as Any?) }, whole: true, from: wish.me)
        case "put", "publish":
            guard let name = call["s"] as? String, let list = Self.json(call["items"]) as? [[Any]] else { return }
            let given = list.compactMap { pair -> (String, Any?)? in
                guard pair.count == 2, let id = pair[0] as? String else { return nil }
                return (id, pair[1] is NSNull ? nil : pair[1])
            }
            let kept = op == "put" ? wish.putItems(in: name, given) : wish.publishItems(in: name, given.compactMap { id, value in value.map { (id, $0) } })
            // Turned down (past a limit): the page, which showed it at once, is told the collection as it really is.
            if !kept { tellItems(name, wish.items(in: name).map { ($0.id, $0.value as Any?) }, whole: true, from: wish.me) }
        case "putFile":
            guard let name = call["s"] as? String, let id = call["id"] as? String,
                  let data = (call["data"] as? String).flatMap({ Data(base64Encoded: $0) }) else { return }
            let kept = wish.putFile(in: name, id: id, data: data, type: call["type"] as? String ?? "")
            if let ask = call["ask"] as? Int { tell(["t": "fileDone", "ask": ask, "ok": kept]) }
        case "fileBytes":
            guard let name = call["s"] as? String, let id = call["id"] as? String, let ask = call["ask"] as? Int else { return }
            let data = wish.fileURL(in: name, id: id).flatMap { try? Data(contentsOf: $0) }
            tell(["t": "fileBytes", "ask": ask, "data": data.map { $0.base64EncodedString() } ?? NSNull()])
        default:
            break
        }
    }

    private func listen(to wish: LampWish) {
        guard !listening else { return }
        listening = true
        // Who is open and how this app's link stands, once each change has been made.
        watching = wish.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.tellState() } }
        }
        wish.onMessage { [weak self] from, data, copy in self?.tell(["t": "message", "from": from, "copy": copy, "data": data]) }
        // Who made each change; the page says to its onChange every value that differs from its copy.
        wish.onChange { [weak self] key, value, from in
            let said: Any = value ?? NSNull()
            self?.tellValues([["key": key, "value": said, "from": from]])
        }
    }

    private func tellState() {
        let wish = LampWish.shared
        let apps: [[String: Any]] = wish.apps.map { peer in
            let lastSeen: Any = peer.status.lastSeen.map { ($0.timeIntervalSince1970 * 1000).rounded() } ?? NSNull()
            let copies: [[String: Any]] = peer.copies.map { ["id": $0.id, "device": $0.device, "since": ($0.since.timeIntervalSince1970 * 1000).rounded()] }
            return ["peer": peer.id, "kind": peer.kind, "name": peer.name, "device": peer.device, "open": peer.isOpen, "copies": copies,
                    "status": ["state": peer.status.state.rawValue, "reason": peer.status.reason, "lastSeen": lastSeen]]
        }
        tell(["t": "state", "me": wish.me, "copy": wish.copy, "apps": apps, "status": ["state": wish.status.state.rawValue, "reason": wish.status.reason]])
    }

    private func tellItems(_ name: String, _ items: [(String, Any?)], whole: Bool, from: String) {
        let wish = LampWish.shared
        var said: [String: Any] = [:], here: [String: Bool] = [:]
        for (id, value) in items {
            said[id] = value ?? NSNull()
            if name.hasPrefix("files:") { here[id] = wish.fileURL(in: name, id: id) != nil }
        }
        tell(["t": "items", "s": name, "items": said, "whole": whole, "from": from, "here": here])
    }

    private func tellValues(_ changed: [[String: Any]]) {
        tell(["t": "values", "values": LampWish.shared.values, "changed": changed])
    }

    private func tellTransfer(_ id: Int) {
        guard let transfer = transfers[id] else { return }
        var said: [String: Any] = ["t": "transfer", "id": id, "sent": transfer.sent]
        switch transfer.state {
        case .sending: said["state"] = "sending"
        case .done: said["state"] = "done"
        case .failed(let why): said["state"] = "failed"; said["error"] = why
        }
        if transfer.state != .sending { transfers[id] = nil; watchingTransfers[id] = nil }
        tell(said)
    }

    private func tell(_ message: [String: Any]) {
        guard let page, JSONSerialization.isValidJSONObject(message),
              let data = try? JSONSerialization.data(withJSONObject: message, options: [.fragmentsAllowed]) else { return }
        page.evaluateJavaScript("window.__lampWish && window.__lampWish(\(String(decoding: data, as: UTF8.self)))", in: nil, in: .page) { _ in }
    }

    private static func json(_ text: Any?) -> Any? {
        guard let text = text as? String else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
    }
}

// MARK: - The page's log

/// What the page logs, into the app's log.
final class LampPageLog: NSObject, WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let line = message.body as? String else { return }
        FileHandle.standardError.write(Data((line.prefix(2000) + "\n").utf8))
    }
}

// MARK: - Serving and showing the page

/// The page's files, from the app's bundle (Web/), each a plain file inside it, at <scheme>://app/.
final class LampPageFiles: NSObject, WKURLSchemeHandler {
    let scheme: String
    private let folder = Bundle.main.resourceURL?.appendingPathComponent("Web")

    init(scheme: String) { self.scheme = scheme }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return task.didFailWithError(URLError(.badURL)) }
        guard let data = file(at: url) else {
            task.didReceive(HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!)
            task.didFinish()
            return
        }
        let ext = url.pathExtension.lowercased()
        let type = ["js": "text/javascript", "mjs": "text/javascript", "html": "text/html", "css": "text/css", "json": "application/json",
                    "wasm": "application/wasm"][ext] ?? UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                        headerFields: ["Content-Type": type, "Content-Length": String(data.count), "Cache-Control": "no-store"])!)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    private func file(at url: URL) -> Data? {
        guard let folder, url.host == "app" else { return nil }
        let root = folder.standardizedFileURL.path + "/"
        let path = url.path.isEmpty || url.path.hasSuffix("/") ? url.path + "index.html" : url.path
        let file = folder.appendingPathComponent(path).standardizedFileURL
        guard file.path.hasPrefix(root), let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
        return try? Data(contentsOf: file)
    }
}

/// The web view the page is shown in: its sound and pictures without a tap first, nothing to scroll or bounce.
@MainActor enum LampPageView {
    /// A page that logs its own errors (a game's runtime does) leaves `catchErrors` off, or each would be logged twice.
    static func make(_ files: LampPageFiles, catchErrors: Bool = true) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(files, forURLScheme: files.scheme)
        // LampAI and the page's calls of this device, and its console into the app's log.
        LampPage.attach(to: configuration, scheme: files.scheme, catchErrors: catchErrors)
        configuration.mediaTypesRequiringUserActionForPlayback = []
        #if os(iOS)
        configuration.allowsInlineMediaPlayback = true
        #endif
        let view = WKWebView(frame: .zero, configuration: configuration)
        #if os(macOS)
        view.setValue(false, forKey: "drawsBackground")
        #else
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.scrollView.bounces = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        #endif
        view.load(URLRequest(url: URL(string: "\(files.scheme)://app/index.html")!))
        return view
    }

    /// A page laid out at a fixed size of its own (`canvas`), zoomed to the space it has; nil leaves it at the window's.
    static func fit(_ view: WKWebView, in size: CGSize, canvas: CGSize?) {
        guard let canvas, size.width > 0, size.height > 0 else { return }
        let zoom = min(size.width / canvas.width, size.height / canvas.height)
        if abs(view.pageZoom - zoom) > 0.001 { view.pageZoom = zoom }
    }
}
