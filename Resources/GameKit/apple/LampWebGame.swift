// Lamp's game kit: the app around a game drawn with three.js, on the Mac, the iPhone and the iPad. Lamp writes this
// file before every build; the game itself is the page in Web/, which this shows in a web view of its own.
//
// On the Mac it's one window with the game filling it, under a title bar with nothing in it, so Lamp's wand floats at
// its top right and the chat opens beside it like any app's. On an iPhone or iPad it's the whole screen, on its side.
// The page is served from the app's bundle at an address of its own (lamp-game://app/), never as a file, so it reads its
// own files with fetch and loads its modules; what it logs goes to the app's log. Its sound plays without a tap first.
// Its saves are kept in a file of the app's (LampGameSaves). Its LampAI calls and its calls of this device go through
// LampPage.swift.
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

/// The page that is the game: its sound and pictures without a tap first, nothing to scroll, zoom or select.
@MainActor enum LampGamePage {
    static let files = LampGameFiles()

    static func make() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(files, forURLScheme: LampGameFiles.scheme)
        // LampAI and the page's calls of this device (LampPage.swift), and its console into the app's log.
        LampPage.attach(to: configuration, scheme: LampGameFiles.scheme, catchErrors: false)
        LampGameSaves.shared.attach(to: configuration)
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

/// The game's saves (`save` and `load` in lamp-game.js), kept in a file in the app's data folder rather than in the web
/// view's own storage, which WebKit keeps by the app's bundle id: a game whose id changes keeps its saves. The page is
/// given them as it opens and hands back each change; saves an earlier build kept in the web view's storage are handed
/// over once, the first time the page opens with this file missing.
@MainActor final class LampGameSaves: NSObject, WKScriptMessageHandler {
    static let shared = LampGameSaves()
    static var file: URL { LampStore.folder.appendingPathComponent("Game Saves.json") }

    private var saves: [String: String]
    private var moved: Bool

    override init() {
        let data = try? Data(contentsOf: Self.file)
        saves = data.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        // A file that's there but can't be read is never handed over again: its saves would be overwritten by older ones.
        moved = data != nil
    }

    func attach(to configuration: WKWebViewConfiguration) {
        configuration.userContentController.add(self, contentWorld: .page, name: "lampSaves")
        let given = (try? JSONSerialization.data(withJSONObject: ["saves": saves, "moved": moved])).map { String(decoding: $0, as: UTF8.self) } ?? "null"
        configuration.userContentController.addUserScript(WKUserScript(source: "window.lampSaves = \(given);",
                                                                       injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard LampPage.isOwnPage(message, scheme: LampGameFiles.scheme), let call = message.body as? [String: Any] else { return }
        switch call["op"] as? String {
        case "set":
            guard let name = call["name"] as? String else { return }
            saves[name] = call["text"] as? String
        case "move":
            // What an earlier build saved, under what this file doesn't have yet.
            for (name, text) in call["saves"] as? [String: String] ?? [:] where saves[name] == nil { saves[name] = text }
            moved = true
        default:
            return
        }
        do {
            try JSONEncoder().encode(saves).write(to: Self.file, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("The game's saves couldn't be kept: \(error.localizedDescription)\n".utf8))
        }
    }
}

#if os(macOS)
struct LampGameSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> LampKeyCatcher { LampKeyCatcher(holding: LampGamePage.make()) }
    func updateNSView(_ view: LampKeyCatcher, context: Context) {
        DispatchQueue.main.async { view.window?.makeFirstResponder(view.page) }
    }
}

/// Holds the page and takes the keys it hands back. WebKit gives back every key the page doesn't cancel, and a game
/// reads its keys without cancelling most of them, so each would reach the window, which beeps for a key nothing took.
/// Shortcuts with ⌘ are the menus' and never come here.
final class LampKeyCatcher: NSView {
    let page: WKWebView

    init(holding page: WKWebView) {
        self.page = page
        super.init(frame: .zero)
        page.frame = bounds
        page.autoresizingMask = [.width, .height]
        addSubview(page)
    }

    required init?(coder: NSCoder) { nil }

    override func keyDown(with event: NSEvent) {}
    override func keyUp(with event: NSEvent) {}
    override func doCommand(by selector: Selector) {}
}
#else
struct LampGameSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { LampGamePage.make() }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
#endif
