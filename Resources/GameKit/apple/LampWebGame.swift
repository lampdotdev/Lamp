// Lamp's game kit: the app around a game drawn with three.js, on the Mac, the iPhone and the iPad. Lamp writes this
// file before every build; the game itself is the page in Web/, which this shows in a web view of its own.
//
// On the Mac it's one window with the game filling it, under a title bar with nothing in it, so Lamp's wand floats at
// its top right and the chat opens beside it like any app's. On an iPhone or iPad it's the whole screen, on its side.
// The page is served from the app's bundle at an address of its own (lamp-game://app/), never as a file, so it reads its
// own files with fetch and loads its modules; what it logs goes to the app's log. Its sound plays without a tap first.
import SwiftUI
import UniformTypeIdentifiers
import WebKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@main
struct LampGameApp: SwiftUI.App {
    var body: some SwiftUI.Scene {
        WindowGroup("{{NAME}}") {
            LampGameScreen()
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 720)
        .commands { LampCommands() }
        #endif
    }
}

struct LampGameScreen: View {
    #if os(macOS)
    @State private var showsKeys = true
    #endif

    var body: some View {
        ZStack {
            Color.black
            LampGameSurface()
            #if os(macOS)
            if showsKeys {
                // How to play, over the game for its first seconds: there may be no controller connected to the Mac.
                Text("WASD or arrows to move · IJKL to look · Space A · Esc B · F X · R Y · Q E bumpers · Z C triggers · P Menu\nA controller connected to this Mac works too.")
                    .font(.system(size: 12, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(16)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(for: .seconds(8))
                        withAnimation(.easeOut(duration: 1)) { showsKeys = false }
                    }
            }
            #endif
        }
        .ignoresSafeArea()
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 270)
        #else
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #endif
    }
}

/// The page's files, from the app's bundle (Web/), each a plain file inside it.
final class LampGameFiles: NSObject, WKURLSchemeHandler {
    static let scheme = "lamp-game"
    private let folder = Bundle.main.resourceURL?.appendingPathComponent("Web")

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

/// What the page logs, into the app's log.
final class LampGameLog: NSObject, WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let line = message.body as? String else { return }
        FileHandle.standardError.write(Data((line.prefix(2000) + "\n").utf8))
    }
}

/// The page that is the game: its sound and pictures without a tap first, nothing to scroll, zoom or select.
@MainActor enum LampGamePage {
    static let files = LampGameFiles()
    static let logger = LampGameLog()

    static func make() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(files, forURLScheme: LampGameFiles.scheme)
        configuration.userContentController.add(logger, name: "lampLog")
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
        view.load(URLRequest(url: URL(string: "\(LampGameFiles.scheme)://app/index.html")!))
        return view
    }
}

#if os(macOS)
struct LampGameSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { LampGamePage.make() }
    func updateNSView(_ view: WKWebView, context: Context) {
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
    }
}
#else
struct LampGameSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { LampGamePage.make() }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
#endif
