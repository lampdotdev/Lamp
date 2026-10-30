import Foundation

/// What a page shared with this person may reach: its own files, and the exact sites (scheme, host and port) the safety
/// sheet named when it arrived, read from its code (`WebReach`, `SharedNetwork` in Lamp). Lamp keeps it in its own folder,
/// outside the app's, and writes it into every build of the app (Info.plist's `LampNetwork`), so it holds with Lamp
/// closed and neither the page's code, a rebuild nor a live change can widen it. Swift of the sender's in the app
/// (`ownSwift`) can: it runs in the app's own process, where it can reach the network itself and switch the page's
/// guard off (the person's choices are kept in the app's defaults), so such an app isn't held at all, its page
/// included, and its sheet says "Has Swift that can reach any site". An app the person made has none and reaches what
/// it likes.
///
/// One rule for every host of a shared page, each reading this type rather than a copy of it: the app around it on the
/// Mac, the iPhone and the iPad (LampPage.swift, as Content-Security-Policy headers and its navigation) and Lamp's
/// previews (`StagedFiles`) do; a host elsewhere (a TV, an Xbox, Android, a phone's controller page) holds a shared page
/// only once it reads it too. It's in LampRelayKit because that's the Swift Lamp and every page's app compile alike
/// (the controller kit).
public struct NetworkPolicy: Codable, Equatable, Sendable {
    /// Exact origins, as `origin(_:)` writes them: "https://api.open-meteo.com", "wss://relay.example:8443".
    public var origins: [String]
    /// The sheet said the app may connect outside itself (a request whose address Lamp couldn't work out): a request it
    /// blocks is shown to the person, who can allow that one site.
    public var mayConnect: Bool
    /// The app carries Swift of the sender's beside the page (any of Sources/ but Lamp's own Native.swift): it runs in
    /// the app's process, where it can reach the network itself and turn the page's guard off, so the app isn't held to
    /// these sites, its page included.
    public var ownSwift: Bool
    /// The person chose to let it reach any site, for good.
    public var unrestricted: Bool

    public init(origins: [String] = [], mayConnect: Bool = false, ownSwift: Bool = false, unrestricted: Bool = false) {
        self.origins = Array(Set(origins.compactMap(Self.origin))).sorted()
        self.mayConnect = mayConnect
        self.ownSwift = ownSwift
        self.unrestricted = unrestricted
    }

    /// Whether the page is held to its sites: a shared app the person hasn't let reach every site.
    public var restricts: Bool { !unrestricted }

    /// The site an address is on, as a policy names it: the scheme, the host lowercased, and the port when it isn't the
    /// scheme's own. Only the web's schemes (http, https, ws, wss) are sites; anything else is nil.
    public static func origin(_ text: String) -> String? {
        guard let parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parts.scheme?.lowercased(), let host = parts.host?.lowercased(), !host.isEmpty,
              let standard = ["http": 80, "https": 443, "ws": 80, "wss": 443][scheme] else { return nil }
        // A host is letters, digits, dots and dashes (or an IPv6 address in brackets): nothing that could end a policy's
        // source list early.
        let bare = host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
        guard bare.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || ".-:".contains($0)) }) else { return nil }
        let shown = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        return scheme + "://" + shown + (parts.port.map { $0 == standard ? "" : ":\($0)" } ?? "")
    }

    public static func origin(of url: URL) -> String? { origin(url.absoluteString) }

    /// Whether a request to `url` may go: a page's own address (`own`, its scheme and host), a page's own data (data:,
    /// blob:, about:), or one of its sites. `extra` are sites the person allowed on this device.
    public func allows(_ url: URL, own: String, extra: [String] = []) -> Bool {
        if unrestricted { return true }
        let scheme = url.scheme?.lowercased() ?? ""
        if ["data", "blob", "about"].contains(scheme) { return true }
        if let ownURL = URL(string: own), scheme == ownURL.scheme?.lowercased(), url.host?.lowercased() == ownURL.host?.lowercased() { return true }
        guard let site = Self.origin(of: url) else { return false }
        return (origins + extra.compactMap(Self.origin)).contains(site)
    }

    /// Whether a page may be shown in a frame of the page, or the page itself go there: only the page's own address and
    /// what it makes for itself (blob: and about:). A site the page may fetch from is still never a frame of it, since
    /// a page from there would run with none of these rules.
    public func allowsFrame(_ url: URL, own: String) -> Bool {
        if unrestricted { return true }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "blob" || scheme == "about" { return true }
        guard let ownURL = URL(string: own) else { return false }
        return scheme == ownURL.scheme?.lowercased() && url.host?.lowercased() == ownURL.host?.lowercased()
    }

    /// The Content-Security-Policy every document and worker of the page is served with, for a page at `own`
    /// ("lamp-web-app://app"), nil when it isn't restricted. Nothing is allowed that isn't named: the page's own files and
    /// its sites for what it loads and connects to; its inline code and eval (Lamp's review reads those, and they're held
    /// to the same sites); data: and blob: for what it makes itself; frames and workers only from itself. Forms post only
    /// to itself, and plugins never run. A site's scheme is as exact as CSP makes it: a ws: site lets that host and port's
    /// http: through too, and an http: site its https: (CSP's own matching), never another host or port.
    public func contentSecurityPolicy(own: String, extra: [String] = []) -> String? {
        guard restricts else { return nil }
        let sites = Array(Set(origins + extra.compactMap(Self.origin))).sorted()
        let me = "'self' " + own
        let reach = ([me] + sites).joined(separator: " ")
        return [
            "default-src \(me)",
            "script-src \(reach) 'unsafe-inline' 'unsafe-eval' 'wasm-unsafe-eval' blob:",
            "style-src \(reach) 'unsafe-inline' data: blob:",
            "img-src \(reach) data: blob:",
            "media-src \(reach) data: blob:",
            "font-src \(reach) data: blob:",
            "connect-src \(reach) data: blob:",
            "worker-src \(me) blob:",
            "child-src \(me) blob:",
            "frame-src \(me) blob:",
            "manifest-src \(me)",
            "object-src 'none'",
            "base-uri \(me)",
            "form-action \(me)",
        ].joined(separator: "; ")
    }

    // MARK: In the app's Info.plist

    /// The policy as the app's Info.plist carries it under `LampNetwork`.
    public static let plistKey = "LampNetwork"

    /// The policy's lines in an Info.plist (`<key>LampNetwork</key><dict>…</dict>`).
    public var plistLines: String {
        func flag(_ value: Bool) -> String { value ? "<true/>" : "<false/>" }
        let sites = origins.map { "<string>\(Self.escaped($0))</string>" }.joined()
        return "  <key>\(Self.plistKey)</key><dict><key>origins</key><array>\(sites)</array>"
            + "<key>mayConnect</key>\(flag(mayConnect))<key>ownSwift</key>\(flag(ownSwift))<key>unrestricted</key>\(flag(unrestricted))</dict>"
    }

    /// The policy an app's Info.plist carries, or nil when it has none (an app the person made).
    public init?(plist value: Any?) {
        guard let dict = value as? [String: Any] else { return nil }
        self.init(origins: dict["origins"] as? [String] ?? [], mayConnect: dict["mayConnect"] as? Bool ?? false,
                  ownSwift: dict["ownSwift"] as? Bool ?? false, unrestricted: dict["unrestricted"] as? Bool ?? false)
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}
