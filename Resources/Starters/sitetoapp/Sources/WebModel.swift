import SwiftUI
import WebKit

/// One site window's page: its web view, where it is, and what the hover bar shows.
@MainActor
final class WebModel: ObservableObject {
    let site: Site
    let standalone: Bool
    let webView: WKWebView

    @Published var title = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var progress = 0.0
    @Published var barShown = false
    @Published var linkPrompt = false
    /// A link on the clipboard that belongs to this site, offered in a pill at the top.
    @Published var offeredLink: URL?

    weak var window: NSWindow?
    private let delegate = WebDelegate()
    private var observers: [NSKeyValueObservation] = []
    var monitor: Any?
    var windowObservers: [NSObjectProtocol] = []
    var lastOffered: String?
    var lightsShown = false
    var lightsTimer: DispatchWorkItem?

    /// Safari's own, so sites that only welcome real browsers (Google's sign-in, Meet) treat this as one.
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    init(site: Site, standalone: Bool) {
        self.site = site
        self.standalone = standalone

        let config = WKWebViewConfiguration()
        // Each site keeps its own sign-in and cookies, apart from every other.
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: site.id)
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.preferences.isElementFullscreenEnabled = true
        config.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = WebModel.userAgent
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.isInspectable = true
        webView.setValue(false, forKey: "drawsBackground")

        delegate.model = self
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate

        func watch<V>(_ path: KeyPath<WKWebView, V>) -> NSKeyValueObservation {
            webView.observe(path, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.sync() }
            }
        }
        observers = [watch(\.title), watch(\.canGoBack), watch(\.canGoForward), watch(\.isLoading),
                     watch(\.estimatedProgress), watch(\.url)]

        if let zoom = UserDefaults.standard.object(forKey: zoomKey) as? Double { webView.pageZoom = zoom }
        goHome()
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        windowObservers.forEach(NotificationCenter.default.removeObserver)
    }

    func sync() {
        title = webView.title ?? ""
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        progress = webView.estimatedProgress
        if standalone { NSApp.dockTile.badgeLabel = WebModel.badge(in: title) }
    }

    /// "(3) Inbox" or "Inbox (3)" → "3", for the Dock icon's badge.
    static func badge(in title: String) -> String? {
        guard let match = title.firstMatch(of: try! Regex(#"\((\d+\+?)\)"#)),
              let count = match[1].substring.map(String.init) else { return nil }
        return count == "0" ? nil : count
    }

    // MARK: Moving around

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }

    func goHome() {
        if let url = site.address { webView.load(URLRequest(url: url)) }
    }

    func open(_ url: URL) {
        offeredLink = nil
        webView.load(URLRequest(url: url))
    }

    private var zoomKey: String { "zoom.\(site.id.uuidString)" }

    func zoom(_ step: Int) {
        let levels: [Double] = [0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]
        let current = webView.pageZoom
        switch step {
        case 0: webView.pageZoom = 1
        case 1: webView.pageZoom = levels.first { $0 > current + 0.01 } ?? current
        default: webView.pageZoom = levels.last { $0 < current - 0.01 } ?? current
        }
        UserDefaults.standard.set(Double(webView.pageZoom), forKey: zoomKey)
    }

    func copyLink() {
        guard let url = webView.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    func openInBrowser() {
        if let url = webView.url { NSWorkspace.shared.open(url) }
    }

    func promptForLink() { linkPrompt = true }

    /// Whether a link is one of this site's own pages rather than somewhere else on the web.
    func isOwn(_ url: URL?) -> Bool {
        guard let host = url?.host() else { return false }
        return Site.baseDomain(host) == Site.baseDomain(site.host)
    }
}
