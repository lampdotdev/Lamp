import Foundation

/// The sites a web app shared with the person may reach, as Lamp read them from the app's code when it was imported
/// (`WebReach`, the review's "Connects to …"): exact origins ("https://api.open-meteo.com"), kept by Lamp outside the
/// app's folder, so nothing the app's code does later widens them. Nil for an app the person made, which nothing guards.
///
/// The Xbox's host reads them from its package (`WebHost.policy`). Lamp doesn't keep them for an import yet, so until it
/// does every app reads as the person's own here.
enum SharedReach {
    static func allowedOrigins(for project: LampProject) -> [String]? {
        nil
    }

    /// An origin as the Xbox's host compares them (`lampg::origin_of`): http, https, ws or wss, the host lowercased, the
    /// port only when it isn't the scheme's own. Nil for anything else, which no policy lists.
    static func canonical(_ text: String) -> String? {
        guard let parts = URLComponents(string: text), let scheme = parts.scheme?.lowercased(),
              let standard = ["http": 80, "ws": 80, "https": 443, "wss": 443][scheme],
              let host = parts.host?.lowercased(), !host.isEmpty, parts.user == nil, parts.password == nil else { return nil }
        let shown = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        return scheme + "://" + shown + (parts.port.map { $0 == standard ? "" : ":\($0)" } ?? "")
    }
}
