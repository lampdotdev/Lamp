import AppKit

// MARK: - Where to watch

struct WatchLink: Hashable {
    var label: String
    var url: URL
    /// False when none of the person's services carry the game.
    var isAvailable = true
}

extension Game {
    var followLive: URL { gamePage }

    /// The game's own page on ESPN, from the scoreboard's link or else built from the game number.
    var gamePage: URL {
        if let gamecast { return gamecast }
        let slug = league.path.split(separator: "/").last.map(String.init) ?? ""
        let path = league.sport == .soccer ? "soccer/match" : "\(slug)/game"
        return URL(string: "https://www.espn.com/\(path)/_/gameId/\(id)")!
    }

    /// The best place to watch: on one of the person's services when they've said which, else from the TV listing.
    @MainActor var watchLink: WatchLink {
        let settings = Watcher.shared.settings
        if !settings.myServices.isEmpty {
            return Streaming.bestLink(for: self, services: settings.myServices)
        }
        for network in networks {
            if var link = WatchLink.forNetwork(network, league: league) {
                if link.label == "Watch on ESPN" || link.label == "Watch on ESPN+", let game = deepLink(for: .espn) { link.url = game }
                return link
            }
        }
        return WatchLink(label: "Follow live", url: followLive)
    }
}

extension WatchLink {
    static func forNetwork(_ raw: String, league: League) -> WatchLink? {
        let n = raw.lowercased()
        func link(_ name: String, _ url: String) -> WatchLink { WatchLink(label: "Watch on \(name)", url: URL(string: url)!) }

        if n.contains("espn") || n == "abc" || n.contains("secn") || n.contains("sec network") || n.contains("accn") || n.contains("acc network") || n.contains("longhorn") {
            return link("ESPN", "https://www.espn.com/watch/")
        }
        if n.contains("peacock") || n == "nbc" || n.contains("nbcsn") || n.contains("usa net") || n == "usa" {
            return link("Peacock", "https://www.peacocktv.com/sports")
        }
        if n.contains("paramount") || n.hasPrefix("cbs") {
            return link("Paramount+", "https://www.paramountplus.com/live-tv/")
        }
        if n.hasPrefix("fox") || n.hasPrefix("fs1") || n.hasPrefix("fs2") || n == "btn" || n.contains("big ten") {
            return link("Fox Sports", "https://www.foxsports.com/live")
        }
        if n == "tnt" || n == "tbs" || n.contains("trutv") || n.contains("max") {
            return link("HBO Max", "https://play.hbomax.com/sports")
        }
        if n.contains("prime") || n.contains("amazon") {
            return link("Prime Video", "https://www.amazon.com/gp/video/storefront/sports")
        }
        if n.contains("apple") || n.contains("mls season pass") {
            return link("Apple TV", "https://tv.apple.com/")
        }
        if n.contains("netflix") {
            return link("Netflix", "https://www.netflix.com/")
        }
        if n.contains("youtube") {
            return link("YouTube TV", "https://tv.youtube.com/live")
        }
        if n.contains("nba tv") || n.contains("league pass") {
            return link("NBA", "https://www.nba.com/watch")
        }
        if n.contains("nfl") {
            return link("NFL+", "https://www.nfl.com/plus/")
        }
        if n.contains("mlb") {
            return link("MLB.TV", "https://www.mlb.com/tv")
        }
        if n.contains("nhl") {
            return link("ESPN+", "https://www.espn.com/watch/")
        }
        return nil
    }
}

// MARK: - Notifications

private struct AlertMemory: Codable {
    /// "gameID|moment" for every moment already announced, with when.
    var sent: [String: Date] = [:]
    /// The excitement each game had when it was last announced.
    var lastScore: [String: Int] = [:]
    /// Where each announced game can be watched, so tapping an old notification still works.
    var links: [String: URL] = [:]
}

@MainActor
enum Alerts {
    private static var memory = LampStore.load(AlertMemory.self, from: "alerts") ?? AlertMemory()

    static func setUp() {
        LampNotifications.onAction { _, id in
            Alerts.open(id)
        }
    }

    static func open(_ id: String) {
        if id.hasPrefix("hl-") {
            let gameID = String(id.dropFirst(3))
            if let url = Watcher.shared.flagged[gameID]?.highlights?.url { NSWorkspace.shared.open(url) }
            return
        }
        if let url = Watcher.shared.games.first(where: { $0.id == id })?.watchLink.url ?? memory.links[id] {
            NSWorkspace.shared.open(url)
        }
    }

    static func consider(_ games: [Game]) {
        var changed = false
        for game in games {
            guard let buzz = game.buzz else { continue }
            let key = "\(game.id)|\(buzz.key)"
            guard memory.sent[key] == nil else { continue }
            if let previous = memory.lastScore[game.id], buzz.score < previous + 8 { continue }

            let watch = game.watchLink
            var body = "\(game.away.abbr) \(game.away.score) – \(game.home.score) \(game.home.abbr) · \(game.statusText)"
            if watch.label != "Follow live" {
                body += " · \(watch.label.replacingOccurrences(of: "Watch on ", with: "on "))"
            }
            LampNotifications.send(buzz.headline, body: body, id: game.id, actions: ["Watch"])

            memory.sent[key] = Date()
            memory.lastScore[game.id] = buzz.score
            memory.links[game.id] = watch.url
            changed = true
        }

        // Forget games from more than two days ago.
        let cutoff = Date().addingTimeInterval(-2 * 86_400)
        let stale = memory.sent.filter { $0.value < cutoff }.map(\.key)
        if !stale.isEmpty {
            for key in stale { memory.sent[key] = nil }
            let liveIDs = Set(memory.sent.keys.compactMap { $0.split(separator: "|").first.map(String.init) })
            memory.lastScore = memory.lastScore.filter { liveIDs.contains($0.key) }
            memory.links = memory.links.filter { liveIDs.contains($0.key) }
            changed = true
        }
        if changed { LampStore.save(memory, to: "alerts") }
    }
}
