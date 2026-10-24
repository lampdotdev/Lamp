// Lamp's screen kit: the app around a screen (a page shown full screen and glanced at from across a room) on the Mac,
// the iPhone and the iPad. Lamp writes this file before every build; the screen itself is the page in Web/, the same
// page a TV shows, which this shows in a web view of its own.
//
// The page is laid out at 1920x1080, as on a TV, and zoomed to fill the window or screen. It's served from the app's
// bundle at an address of its own (lamp-screen://app/), so it reads its own files with fetch; its LampAI and LampStore
// calls reach Lamp through this app (the `lampGateway` bridge that Web/lamp.js looks for), with the app's own token,
// never the page's, and its `LampNative` calls reach Sources/Native.swift (both in LampPage.swift); what it logs goes
// to the app's log.
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

@MainActor enum LampScreenPage {
    static let files = LampScreenFiles()

    static func make() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(files, forURLScheme: LampScreenFiles.scheme)
        // LampAI and the page's calls of this device (LampPage.swift), and its console into the app's log.
        LampPage.attach(to: configuration, scheme: LampScreenFiles.scheme)
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
