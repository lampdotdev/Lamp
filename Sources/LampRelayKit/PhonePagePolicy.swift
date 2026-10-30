import Foundation

/// The rules a phone's browser holds a shared app's phone page to (its Content-Security-Policy), sent with every answer by
/// each server of one: Lamp's (`Store.phonePage`), a game's own (`PhonePageServer`), an LG TV's (relay.js) and the Xbox
/// host's (lamp_controllers.h), which write the same words. An app the person made has none (`Reach.unrestricted`), and its
/// page is served as it always was. For a shared one nothing is allowed unless it's named: the page's own files; the
/// game's relay, on the machine the page came from (by the name the phone used) at the port it listens on as the page is
/// served, and nowhere else on the network; and the sites the app may reach (`Reach`). A relay that moved after the page
/// loaded is outside the page's rules, so lamp-controller.js loads the page again when its socket is refused.
public enum PhonePagePolicy {
    /// Sites beyond the page's own files and its relay.
    public enum Reach: Equatable, Sendable {
        /// No rules at all: an app the person made here (or a starter), or one they let reach every site.
        case unrestricted
        /// Only these: an app shared with the person, held to the sites its safety review named. Each is a host name
        /// ("api.example.com") or an origin ("https://api.example.com:8443"); anything else is dropped.
        case only([String])
    }

    /// Where a game's bundle, an LG TV's service and an Xbox package keep the page's `Reach` beside its files, written by
    /// Lamp in place of any file of the app's by that name (`json(_:)`); a server that finds none allows no sites.
    public static let reachFile = "lamp-reach.json"

    public static func json(_ reach: Reach) -> Data {
        let object: [String: Any]
        switch reach {
        case .unrestricted: object = ["unrestricted": true]
        case .only(let sites): object = ["only": sites]
        }
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }

    /// A reach file's `Reach`: no sites when it's missing or unreadable.
    public static func reach(json data: Data?) -> Reach {
        guard let data, let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .only([]) }
        if object["unrestricted"] as? Bool == true { return .unrestricted }
        return .only((object["only"] as? [Any])?.compactMap { $0 as? String } ?? [])
    }

    /// The header's value for a page asked for by `host` (the request's Host header), with the relay at `relayPort`; nil
    /// for an unrestricted page, which is sent with no header.
    public static func header(host: String?, relayPort: UInt16?, reach: Reach) -> String? {
        guard case .only(let named) = reach else { return nil }
        let sites = named.compactMap(source)
        var connect = ["'self'"]
        if let name = relayHost(host), let relayPort { connect.append("ws://\(name):\(relayPort)") }
        func list(_ base: [String]) -> String { (base + sites).joined(separator: " ") }
        return [
            "default-src 'none'",
            "script-src " + list(["'self'", "'unsafe-inline'"]),
            "style-src " + list(["'self'", "'unsafe-inline'"]),
            "img-src " + list(["'self'", "data:", "blob:"]),
            "media-src " + list(["'self'", "data:", "blob:"]),
            "font-src " + list(["'self'", "data:"]),
            "connect-src " + list(connect),
            "worker-src 'self' blob:",
            "manifest-src 'self'",
            "base-uri 'none'",
            "form-action 'none'",
        ].joined(separator: "; ")
    }

    /// The name in a Host header, without its port, when it's one a policy can name: a host name or an IPv4 address. An
    /// IPv6 address can't be written in a policy, so a page reached by one has no relay.
    static func relayHost(_ header: String?) -> String? {
        guard var host = header?.trimmingCharacters(in: .whitespaces).lowercased(), !host.isEmpty, !host.hasPrefix("[") else { return nil }
        if let colon = host.firstIndex(of: ":") { host = String(host[..<colon]) }
        return plainHost(host) ? host : nil
    }

    /// One named site as a policy source: a host name, or an http(s) or ws(s) origin with at most a port.
    static func source(_ text: String) -> String? {
        let site = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard let split = site.range(of: "://") else { return plainHost(site) ? site : nil }
        let scheme = site[..<split.lowerBound]
        guard ["http", "https", "ws", "wss"].contains(scheme) else { return nil }
        var rest = String(site[split.upperBound...])
        if rest.hasSuffix("/") { rest.removeLast() }
        var host = rest
        if let colon = rest.firstIndex(of: ":") {
            let port = rest[rest.index(after: colon)...]
            guard !port.isEmpty, port.count <= 5, port.allSatisfy(\.isASCII), port.allSatisfy(\.isNumber) else { return nil }
            host = String(rest[..<colon])
        }
        return plainHost(host) ? "\(scheme)://\(rest)" : nil
    }

    private static func plainHost(_ host: String) -> Bool {
        guard !host.isEmpty, host.count <= 253, !host.hasPrefix("."), !host.hasSuffix("."), !host.contains("..") else { return false }
        return host.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" || $0 == "." }
    }
}
