import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// The game is a web page (three.js, in Assets/Web), drawn by WebKit in the window. Its files are served at an
/// address of the app's own (`newyork://game/`) rather than opened as files: WebKit refuses ES modules, the import
/// map and fetch to a page opened from a file, and a page at its own address also keeps its saved game
/// (localStorage) between launches.
struct GameScreen: NSViewRepresentable {
    func makeNSView(context: Context) -> KeyCatcher {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(GameFiles(), forURLScheme: GameFiles.scheme)
        // The engine, the horns and the city hum start as the game opens, not at the first click.
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(context.coordinator, name: "console")
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.forwardConsole, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let view = GameWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.isInspectable = true
        view.uiDelegate = context.coordinator
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: URL(string: "\(GameFiles.scheme)://game/index.html")!))
        context.coordinator.reloadOnChange(view)
        return KeyCatcher(holding: view)
    }

    func updateNSView(_ view: KeyCatcher, context: Context) {}

    func makeCoordinator() -> Page { Page() }

    /// Looks after the page: what it logs goes to the app's own output, where Lamp reads it, and its links to other
    /// sites (GitHub) open in the browser.
    final class Page: NSObject, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {
        private var stream: FSEventStreamRef?
        private weak var view: WKWebView?

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            print("[game] \(message.body)")
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url { NSWorkspace.shared.open(url) }
            return nil
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, url.scheme != GameFiles.scheme else { return decisionHandler(.allow) }
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }

        /// A change to the page's files while the app is open loads the page again, so it shows at once; the game
        /// comes back where the player was, which it saves every few seconds. (An installed copy's files never change.)
        func reloadOnChange(_ view: WKWebView) {
            guard let folder = LampAssets.folder?.appendingPathComponent("Web").path else { return }
            self.view = view
            var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                               retain: nil, release: nil, copyDescription: nil)
            let changed: FSEventStreamCallback = { _, info, _, _, _, _ in
                guard let info else { return }
                Unmanaged<Page>.fromOpaque(info).takeUnretainedValue().view?.reload()
            }
            // Half a second gathers a save of several files into one reload.
            stream = FSEventStreamCreate(nil, changed, &context, [folder] as CFArray,
                                         FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5,
                                         FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer))
            guard let stream else { return }
            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)
        }

        deinit {
            guard let stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    private static let forwardConsole = """
    (() => {
      const send = (level, args) => {
        try {
          const text = args.map((a) => a instanceof Error ? a.stack || String(a)
            : typeof a === 'object' ? JSON.stringify(a) : String(a)).join(' ');
          window.webkit.messageHandlers.console.postMessage(level + ': ' + text);
        } catch {}
      };
      for (const level of ['log', 'info', 'warn', 'error']) {
        const original = console[level].bind(console);
        console[level] = (...args) => { original(...args); send(level, args); };
      }
      window.addEventListener('error', (e) => send('error', [e.message + ' at ' + e.filename + ':' + e.lineno]));
      window.addEventListener('unhandledrejection', (e) => send('error', ['unhandled: ' + (e.reason?.stack || e.reason)]));
    })();
    """
}

/// Holds the web view and takes the keys the page hands back. WebKit gives back every key the page doesn't cancel,
/// and the game reads its keys without cancelling them, so each one would reach the window, which beeps for a key
/// nothing took. Shortcuts with ⌘ are menus' and never come here.
final class KeyCatcher: NSView {
    init(holding view: NSView) {
        super.init(frame: .zero)
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
    }

    required init?(coder: NSCoder) { nil }

    override func keyDown(with event: NSEvent) {}
    override func keyUp(with event: NSEvent) {}
    override func doCommand(by selector: Selector) {}
}

/// Takes the keyboard as soon as it's in a window, so the game hears the keys without a click first.
final class GameWebView: WKWebView {
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
}

/// Serves Assets/Web at `newyork://game/`, only files inside that folder.
final class GameFiles: NSObject, WKURLSchemeHandler {
    static let scheme = "newyork"

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, let root = LampAssets.folder?.appendingPathComponent("Web").standardizedFileURL else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        let path = url.path.removingPercentEncoding ?? url.path
        let file = root.appendingPathComponent(path).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file) else {
            task.didReceive(HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!)
            task.didFinish()
            return
        }
        let type = UTType(filenameExtension: file.pathExtension)
        let mime = file.pathExtension == "js" ? "text/javascript" : type?.preferredMIMEType ?? "application/octet-stream"
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": mime,
            "Content-Length": String(data.count),
            "Cache-Control": "no-cache"
        ])!)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}
