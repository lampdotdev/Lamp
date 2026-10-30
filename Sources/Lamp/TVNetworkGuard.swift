import Foundation

/// A shared TV app held to its own files and the exact sites its safety sheet named, by rules that go inside the
/// package, so they hold on the TV with Lamp closed. Neither TV gives a packaged web app a network filter of its own
/// beyond Samsung's manifest, so the rule is the page's own Content Security Policy: a meta tag Lamp puts first in every
/// page of the package, and on a Samsung TV the same policy in its manifest, with the manifest's `<access>` and
/// navigation lists cut to those sites. It is weaker than a filter outside the page: a CSP can't stop a page leaving
/// for another address, WebRTC's own connections or a DNS lookup a hint asks for, and an older TV's browser lets a page
/// open a document the policy doesn't cover. So only a TV whose browser closes those documents (`holds`) counts as
/// guarding the app.
///
/// Lamp's own ways out stay open: its gateway on this Mac (AI, the token, the phone page's address) and the controllers'
/// relay there, by this Mac's names at the time of the build, and on an LG TV the game's own phone service on the TV.
enum TVNetworkGuard {
    /// The origins a shared app may reach, as Lamp read them when the app was imported and keeps them outside the app's
    /// code; nil for an app that isn't held to any (one made here). The one place the TV packages ask, so the shared
    /// policy is plugged in here and nowhere else. Tests stand in their own.
    static var allowedOrigins: (LampProject) -> [String]? = { _ in nil }

    struct Policy: Equatable {
        /// The app's sites, each a checked origin ("https://api.example.com", "wss://live.example.com:8443").
        var origins: [String]
        /// This Mac's names and addresses, where Lamp's gateway and relay answer.
        var lampHosts: [String]
        var gatewayPort: UInt16
    }

    /// The policy for a shared app, with Lamp where it is now; nil when the app isn't held to its sites.
    static func policy(for project: LampProject) -> Policy? {
        guard let origins = allowedOrigins(project) else { return nil }
        let hosts = ([Devices.macHost] + Devices.localAddresses).compactMap(host)
        return Policy(origins: origins.compactMap(origin), lampHosts: hosts, gatewayPort: Gateway.port)
    }

    // MARK: Origins

    /// An origin as a policy may name it: http, https, ws or wss, a host of letters, digits, dots and dashes (or an
    /// IPv6 address in brackets) and an optional port, nothing else. Anything more is dropped, never passed on into a
    /// manifest or a page.
    static func origin(_ text: String) -> String? {
        guard let parts = URLComponents(string: text.trimmingCharacters(in: .whitespaces)),
              let scheme = parts.scheme?.lowercased(), ["http", "https", "ws", "wss"].contains(scheme),
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.percentEncodedPath.isEmpty || parts.percentEncodedPath == "/",
              let name = parts.percentEncodedHost, let host = host(name) else { return nil }
        if let port = parts.port {
            guard (1...65535).contains(port) else { return nil }
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    /// A host name or address in the form a policy writes it, nil when it has anything else in it.
    static func host(_ text: String) -> String? {
        let name = text.lowercased()
        if name.hasPrefix("["), name.hasSuffix("]") {
            return name.dropFirst().dropLast().allSatisfy({ $0.isHexDigit || $0 == ":" || $0 == "." }) && name.count > 2 ? name : nil
        }
        if name.contains(":") { return host("[" + name + "]") }
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        guard !name.isEmpty, name.count <= 253, labels.allSatisfy({ !$0.isEmpty && !$0.hasPrefix("-") && !$0.hasSuffix("-") }),
              name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }) else { return nil }
        return name
    }

    // MARK: The policy

    /// What Lamp's own script reaches on the TV: the gateway at its port by each of this Mac's names, the relay there at
    /// whichever port it has (it picks one as it starts), and on an LG TV the game's phone service at the TV's loopback.
    static func lampSources(_ policy: Policy) -> [String] {
        policy.lampHosts.flatMap { ["http://\($0):\(policy.gatewayPort)", "ws://\($0):*"] } + ["ws://127.0.0.1:*"]
    }

    /// The TV page's policy. Its own files are 'self' and file: (a TV opens the package from its disk), pictures and
    /// sounds may be data and blobs it makes, and scripts may be inline and eval'd: this rule is about where the page
    /// connects, not what code it runs. Frames and workers come only from the app's sites: any of its own files (a script,
    /// a picture) opened as a frame or a worker is a document of its own that no meta tag reaches, and a data or blob one
    /// has no policy in older browsers.
    static func tvPage(_ policy: Policy) -> String {
        directives(own: ["'self'", "file:"], sites: policy.origins, connect: lampSources(policy))
    }

    private static func directives(own: [String], sites: [String], connect: [String]) -> String {
        func list(_ parts: [String]) -> String { parts.joined(separator: " ") }
        let mine = own + sites
        let documents = sites.isEmpty ? "'none'" : list(sites)
        return [
            "default-src " + list(mine),
            "script-src " + list(mine + ["'unsafe-inline'", "'unsafe-eval'"]),
            "style-src " + list(mine + ["'unsafe-inline'"]),
            "img-src " + list(mine + ["data:", "blob:"]),
            "media-src " + list(mine + ["data:", "blob:"]),
            "font-src " + list(mine + ["data:"]),
            "connect-src " + list(mine + ["data:", "blob:"] + connect),
            "frame-src " + documents,
            "child-src " + documents,
            "worker-src " + documents,
            "object-src 'none'",
            "base-uri 'self'",
            "form-action " + list(mine),
        ].joined(separator: "; ")
    }

    // MARK: Pages

    static func isPage(_ path: String) -> Bool {
        ["html", "htm", "shtml", "shtm"].contains((path as NSString).pathExtension.lowercased())
    }

    /// A page with the policy first: straight after its doctype (before it would put the page in quirks mode; only HTML's
    /// own spaces may come before one, since any other character opens the body, where a policy counts for nothing), ahead of
    /// anything the page says, so no comment, script or tag of its own comes before it. A page that declares UTF-8 has
    /// that said first, since a browser looks for it only in a page's first kilobyte.
    static func guarded(_ page: Data, policy: String) -> Data {
        var text = String(decoding: page, as: UTF8.self)
        var head = ""
        if text.hasPrefix("\u{FEFF}") { text.removeFirst(); head = "\u{FEFF}" }
        let doctype = try? NSRegularExpression(pattern: #"^[\t\n\f\r ]*<!doctype[^>]*>"#, options: [.caseInsensitive])
        if let match = doctype?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range, in: text) {
            head += text[range]
            text = String(text[range.upperBound...])
        }
        let utf8 = text.range(of: #"charset\s*=\s*["']?\s*utf-?8"#, options: [.regularExpression, .caseInsensitive]) != nil
        head += (utf8 ? "<meta charset=\"utf-8\">" : "")
            + "<meta http-equiv=\"Content-Security-Policy\" content=\"\(policy)\">"
        return Data((head + text).utf8)
    }

    /// Every page of a package with the policy put in.
    static func guarded(_ files: [(path: String, data: Data)], policy: String) -> [(path: String, data: Data)] {
        files.map { isPage($0.path) ? ($0.path, guarded($0.data, policy: policy)) : $0 }
    }

    // MARK: Samsung's manifest

    /// What a Samsung manifest says about the network: everything for an app made here, as before; for a shared app,
    /// `<access>` for its sites and Lamp's, the same policy as its pages, and navigation only to its sites' hosts.
    static func tizenManifest(_ policy: Policy?) -> String {
        guard let policy else { return "<access origin=\"*\" subdomains=\"true\"/>" }
        let lamp = policy.lampHosts.flatMap { ["http://\($0):\(policy.gatewayPort)", "ws://\($0)"] } + ["ws://127.0.0.1"]
        var lines = (policy.origins + lamp).map { "<access origin=\"\($0)\" subdomains=\"false\"/>" }
        lines.append("<tizen:content-security-policy>\(tvPage(policy))</tizen:content-security-policy>")
        let hosts = Array(Set(policy.origins.compactMap { URLComponents(string: $0)?.percentEncodedHost })).sorted()
        if !hosts.isEmpty { lines.append("<tizen:allow-navigation>\(hosts.joined(separator: " "))</tizen:allow-navigation>") }
        return lines.joined(separator: "\n    ")
    }

    // MARK: Which TVs hold it

    /// The oldest systems whose browsers hold a page to its policy: Chromium 60 and later never open a data: document
    /// as a whole page, which earlier ones do with no policy at all. Tizen 5.0 (2019 TVs) has Chromium 63; webOS TV 5
    /// (2020, `webos_release` 5) has Chromium 68.
    static let oldestTizen = 5
    static let oldestWebOS = 5

    /// Whether the TV holds a guarded app to its sites; a TV whose version Lamp hasn't read doesn't count.
    static func holds(on record: TVs.Record) -> Bool {
        guard let major = Int(record.osVersion.split(separator: ".").first ?? "") else { return false }
        return major >= (record.isSamsung ? oldestTizen : oldestWebOS)
    }
}
