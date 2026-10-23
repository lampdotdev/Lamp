import SwiftUI
import WebKit

/// The site's page, filling its window.
struct WebView: NSViewRepresentable {
    let web: WebModel

    func makeNSView(context: Context) -> WKWebView { web.webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}

/// What a site's page asks of the app: where links go, sign-in windows, the camera and microphone, files and
/// downloads.
@MainActor
final class WebDelegate: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    weak var model: WebModel?
    private var popups: [NSWindow] = []

    // MARK: Where links go

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        guard let url = action.request.url else { return (.allow, preferences) }
        let scheme = url.scheme?.lowercased() ?? ""
        // Other apps' links (mailto:, zoommtg:, slack:) go to those apps.
        if !["http", "https", "about", "blob", "data", "file"].contains(scheme) {
            NSWorkspace.shared.open(url)
            return (.cancel, preferences)
        }
        // ⌘-click opens in the browser, as it would open a new tab there.
        if action.navigationType == .linkActivated, action.modifierFlags.contains(.command) {
            NSWorkspace.shared.open(url)
            return (.cancel, preferences)
        }
        if action.shouldPerformDownload { return (.download, preferences) }
        return (.allow, preferences)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        response.canShowMIMEType ? .allow : .download
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    // MARK: New windows

    /// A link meant for a new tab: the site's own pages open in place, the rest of the web in the browser. A
    /// window a script opens (signing in with Google, Microsoft or Apple) gets a small window of its own, so the
    /// sign-in can hand its answer back to the page.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let url = action.request.url
        let isBlank = url == nil || url?.absoluteString.isEmpty == true || url?.scheme == "about"
        let own = model?.isOwn(url) ?? false

        if action.navigationType == .linkActivated || action.modifierFlags.contains(.command) {
            if let url {
                if own, url.host() == model?.site.host, !action.modifierFlags.contains(.command) {
                    webView.load(action.request)
                } else {
                    NSWorkspace.shared.open(url)
                }
            }
            return nil
        }
        if !isBlank, !own, let url, !WebDelegate.looksLikeSignIn(url) {
            NSWorkspace.shared.open(url)
            return nil
        }
        return popup(configuration, features: windowFeatures, over: webView.window)
    }

    static func looksLikeSignIn(_ url: URL) -> Bool {
        let text = url.absoluteString.lowercased()
        return ["accounts.", "login.", "auth", "oauth", "sso", "signin", "sign-in", "appleid.apple.com", "saml"]
            .contains { text.contains($0) }
    }

    private func popup(_ configuration: WKWebViewConfiguration, features: WKWindowFeatures, over parent: NSWindow?) -> WKWebView {
        let size = CGSize(width: features.width?.doubleValue ?? 520, height: features.height?.doubleValue ?? 680)
        let view = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: configuration)
        view.customUserAgent = WebModel.userAgent
        view.uiDelegate = self
        view.navigationDelegate = self
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.title = model?.site.name ?? ""
        if let parent {
            window.setFrameOrigin(CGPoint(x: parent.frame.midX - size.width / 2, y: parent.frame.midY - size.height / 2))
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        popups.append(window)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] note in
            MainActor.assumeIsolated { self?.popups.removeAll { $0 === note.object as? NSWindow } }
        }
        return view
    }

    func webViewDidClose(_ webView: WKWebView) {
        if webView !== model?.webView { webView.window?.close() }
    }

    // MARK: Camera, microphone and the page's own dialogs

    /// Calls (Meet and the like) get the camera and microphone without a second question from the page; macOS
    /// still asks once for the app itself. Only the site's own origin (its scheme, host and port) is trusted that
    /// way: a page the window was led to elsewhere, even under the same domain, is asked about as in a browser.
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType) async -> WKPermissionDecision {
        guard let address = model?.site.address, let host = address.host(), let scheme = address.scheme else { return .prompt }
        let same = origin.protocol.lowercased() == scheme.lowercased()
            && origin.host.lowercased() == host.lowercased()
            && origin.port == (address.port ?? 0)
        return same ? .grant : .prompt
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo) async -> String? {
        let alert = NSAlert()
        alert.messageText = prompt
        let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    /// Attaching files to a message or upload.
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        return panel.runModal() == .OK ? panel.urls : nil
    }

    // MARK: Downloads

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let name = suggestedFilename as NSString
        var url = folder.appendingPathComponent(suggestedFilename)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            let base = name.deletingPathExtension + " \(n)"
            url = folder.appendingPathComponent(name.pathExtension.isEmpty ? base : base + "." + name.pathExtension)
            n += 1
        }
        return url
    }

    func downloadDidFinish(_ download: WKDownload) {
        // The Downloads stack in the Dock bounces, as it does for Safari.
        if let path = download.progress.fileURL?.path {
            DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"), object: path)
        }
    }
}
