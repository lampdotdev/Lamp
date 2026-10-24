// Lamp's screen kit: the app around a screen (a page shown full screen and glanced at from across a room) on the Mac,
// the iPhone and the iPad. Lamp writes this file before every build; the screen itself is the page in Web/, the same
// page a TV shows, which this shows in a web view of its own.
//
// The page is laid out at 1920x1080, as on a TV, and zoomed to fill the window or screen. It's served from the app's
// bundle at an address of its own (lamp-screen://app/), so it reads its own files with fetch; its LampAI and LampStore
// calls reach Lamp through this app (the `lampGateway` bridge that Web/lamp.js looks for), with the app's own token,
// never the page's; what it logs goes to the app's log.
import SwiftUI
import UniformTypeIdentifiers
import WebKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@main
struct LampScreenApp: SwiftUI.App {
    var body: some SwiftUI.Scene {
        WindowGroup("{{NAME}}") {
            LampScreenView()
                .ignoresSafeArea()
                #if os(macOS)
                .frame(minWidth: 480, minHeight: 270)
                #else
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 720)
        .commands { LampCommands() }
        #endif
    }
}

/// The page's files, from the app's bundle (Web/), each a plain file inside it.
final class LampScreenFiles: NSObject, WKURLSchemeHandler {
    static let scheme = "lamp-screen"
    private let folder = Bundle.main.resourceURL?.appendingPathComponent("Web")

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return task.didFailWithError(URLError(.badURL)) }
        guard let data = file(at: url) else {
            task.didReceive(HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!)
            task.didFinish()
            return
        }
        let ext = url.pathExtension.lowercased()
        let type = ["js": "text/javascript", "mjs": "text/javascript", "html": "text/html", "css": "text/css", "json": "application/json"][ext]
            ?? UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
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

/// The page's way to Lamp: only the routes a screen uses, with the app's own token, answered to the app's own page.
final class LampScreenGateway: NSObject, WKScriptMessageHandlerWithReply, WKScriptMessageHandler {
    private static let routes: Set<String> = ["/ai", "/ai/status", "/ai/image", "/ai/decide"]

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.protocol == LampScreenFiles.scheme,
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

    /// What the page logs, into the app's log.
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let line = message.body as? String else { return }
        FileHandle.standardError.write(Data((line.prefix(2000) + "\n").utf8))
    }
}

@MainActor enum LampScreenPage {
    static let files = LampScreenFiles()
    static let gateway = LampScreenGateway()

    static func make() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(files, forURLScheme: LampScreenFiles.scheme)
        configuration.userContentController.addScriptMessageHandler(gateway, contentWorld: .page, name: "lampGateway")
        configuration.userContentController.add(gateway, name: "lampLog")
        // The page's console, into the app's log.
        configuration.userContentController.addUserScript(WKUserScript(source: """
            (function () {
              var send = function (kind) { return function () { try { window.webkit.messageHandlers.lampLog.postMessage(kind + Array.prototype.join.call(arguments, ' ')); } catch (e) {} }; };
              console.log = send(''); console.warn = send('Warning: '); console.error = send('Error: ');
              window.addEventListener('error', function (e) { send('Error: ')(e.message + ' (' + (e.filename || '').split('/').pop() + ':' + e.lineno + ')'); });
            })();
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
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
        view.load(URLRequest(url: URL(string: "\(LampScreenFiles.scheme)://app/index.html")!))
        return view
    }

    /// The page laid out at a TV's 1920x1080 and zoomed to the space it has.
    static func fit(_ view: WKWebView, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let zoom = min(size.width / 1920, size.height / 1080)
        if abs(view.pageZoom - zoom) > 0.001 { view.pageZoom = zoom }
    }
}

struct LampScreenView: View {
    var body: some View {
        GeometryReader { space in
            ZStack {
                Color.black
                LampScreenSurface(size: space.size)
            }
        }
    }
}

#if os(macOS)
struct LampScreenSurface: NSViewRepresentable {
    let size: CGSize
    func makeNSView(context: Context) -> WKWebView { LampScreenPage.make() }
    func updateNSView(_ view: WKWebView, context: Context) {
        LampScreenPage.fit(view, in: size)
        DispatchQueue.main.async { if view.window?.firstResponder !== view { view.window?.makeFirstResponder(view) } }
    }
}
#else
struct LampScreenSurface: UIViewRepresentable {
    let size: CGSize
    func makeUIView(context: Context) -> WKWebView { LampScreenPage.make() }
    func updateUIView(_ view: WKWebView, context: Context) { LampScreenPage.fit(view, in: size) }
}
#endif
