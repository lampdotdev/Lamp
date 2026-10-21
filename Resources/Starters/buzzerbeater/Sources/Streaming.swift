import Foundation

// MARK: - Services

enum Service: String, Codable, CaseIterable, Identifiable {
    case espn, espnPlus, peacock, paramount, foxOne, hboMax, prime, appleTV, netflix
    case youtubeTV, huluLive, sling, fubo, directv, cable, antenna
    case nbaLeaguePass, nflPlus, mlbTV

    var id: String { rawValue }

    var name: String {
        switch self {
        case .espn: "ESPN Unlimited"
        case .espnPlus: "ESPN+ (ESPN Select)"
        case .peacock: "Peacock"
        case .paramount: "Paramount+"
        case .foxOne: "Fox One"
        case .hboMax: "HBO Max"
        case .prime: "Prime Video"
        case .appleTV: "Apple TV"
        case .netflix: "Netflix"
        case .youtubeTV: "YouTube TV"
        case .huluLive: "Hulu + Live TV"
        case .sling: "Sling TV"
        case .fubo: "Fubo"
        case .directv: "DIRECTV"
        case .cable: "Cable or satellite"
        case .antenna: "Antenna (local channels)"
        case .nbaLeaguePass: "NBA League Pass"
        case .nflPlus: "NFL+"
        case .mlbTV: "MLB.TV"
        }
    }

    /// The name on the Watch button.
    var short: String {
        switch self {
        case .espn, .espnPlus: "ESPN"
        case .cable: "TV"
        case .antenna: "antenna"
        case .nbaLeaguePass: "League Pass"
        default: name
        }
    }

    var group: String {
        switch self {
        case .youtubeTV, .huluLive, .sling, .fubo, .directv, .cable, .antenna: "Live TV"
        case .nbaLeaguePass, .nflPlus, .mlbTV: "League passes"
        default: "Streaming"
        }
    }

    var url: URL? {
        let s: String? = switch self {
        case .espn, .espnPlus: "https://www.espn.com/watch/"
        case .peacock: "https://www.peacocktv.com/sports"
        case .paramount: "https://www.paramountplus.com/live-tv/"
        case .foxOne: "https://www.foxone.com/"
        case .hboMax: "https://play.hbomax.com/sports"
        case .prime: "https://www.amazon.com/gp/video/storefront/sports"
        case .appleTV: "https://tv.apple.com/"
        case .netflix: "https://www.netflix.com/"
        case .youtubeTV: "https://tv.youtube.com/live"
        case .huluLive: "https://www.hulu.com/live"
        case .sling: "https://watch.sling.com/"
        case .fubo: "https://www.fubo.tv/"
        case .directv: "https://stream.directv.com/"
        case .nbaLeaguePass: "https://www.nba.com/watch/league-pass-stream"
        case .nflPlus: "https://www.nfl.com/plus/"
        case .mlbTV: "https://www.mlb.com/tv"
        case .cable, .antenna: nil
        }
        return s.flatMap(URL.init(string:))
    }

    /// The channels it carries. Regional sports networks are only for local games.
    var channels: Set<Channel> {
        switch self {
        case .espn: [.espn, .espnPlus, .abc, .conference]
        case .espnPlus: [.espnPlus]
        case .peacock: [.nbc, .peacock]
        case .paramount: [.cbs, .paramount]
        case .foxOne: [.fox, .fs1, .bigTen]
        case .hboMax: [.tnt]
        case .prime: [.prime]
        case .appleTV: [.apple]
        case .netflix: [.netflix]
        case .youtubeTV: [.espn, .abc, .nbc, .cbs, .fox, .fs1, .tnt, .usa, .bigTen, .conference, .nbaTV, .nflNetwork, .mlbNetwork, .nhlNetwork, .youtube]
        case .huluLive: [.espn, .espnPlus, .abc, .nbc, .cbs, .fox, .fs1, .tnt, .usa, .bigTen, .conference, .nflNetwork]
        case .sling: [.espn, .tnt, .fs1, .usa, .nbc, .fox, .bigTen, .conference, .nbaTV, .nflNetwork, .mlbNetwork, .nhlNetwork]
        case .fubo: [.espn, .abc, .nbc, .cbs, .fox, .fs1, .usa, .bigTen, .conference, .nbaTV, .nflNetwork, .mlbNetwork, .nhlNetwork, .regional]
        case .directv, .cable: Set(Channel.allCases).subtracting([.espnPlus, .peacock, .paramount, .prime, .apple, .netflix, .youtube, .other])
        case .antenna: [.abc, .nbc, .cbs, .fox]
        case .nbaLeaguePass: [.nbaTV]
        case .nflPlus: [.nflNetwork]
        case .mlbTV: [.mlbNetwork]
        }
    }

    /// Out-of-market games this pass carries (from the teams' regional networks).
    func carriesOutOfMarket(_ league: League) -> Bool {
        switch self {
        case .nbaLeaguePass: league == .nba
        case .mlbTV: league == .mlb
        case .espnPlus, .espn: league == .nhl
        default: false
        }
    }
}

// MARK: - Channels

enum Channel: CaseIterable {
    case espn, espnPlus, abc, nbc, peacock, cbs, paramount, fox, fs1, tnt, usa, bigTen, conference
    case prime, apple, netflix, youtube, nbaTV, nflNetwork, mlbNetwork, nhlNetwork, regional
    /// A national name the list doesn't know (Roku, a new streamer): no service is assumed to carry it.
    case other

    static func of(_ raw: String) -> Channel {
        let n = raw.lowercased()
        if n.contains("espn+") || n == "espn plus" { return .espnPlus }
        if n.contains("espn") { return .espn }
        if n == "abc" { return .abc }
        if n.contains("peacock") { return .peacock }
        if n == "nbc" { return .nbc }
        if n.contains("paramount") { return .paramount }
        if n == "cbs" { return .cbs }
        if n.hasPrefix("fs1") || n.hasPrefix("fs2") { return .fs1 }
        if n == "fox" { return .fox }
        if n == "tnt" || n == "tbs" || n.contains("trutv") || n.contains("max") { return .tnt }
        if n == "usa net" || n == "usa" || n.contains("usa network") { return .usa }
        if n == "btn" || n.contains("big ten") { return .bigTen }
        if n.contains("secn") || n.contains("sec network") || n.contains("accn") || n.contains("acc network") { return .conference }
        if n.contains("prime") || n.contains("amazon") { return .prime }
        if n.contains("apple") || n.contains("mls season pass") { return .apple }
        if n.contains("netflix") { return .netflix }
        if n.contains("youtube") { return .youtube }
        if n.contains("nba tv") { return .nbaTV }
        if n.contains("nfl net") || n.contains("nfl+") { return .nflNetwork }
        if n.contains("mlb net") || n.contains("mlb.tv") { return .mlbNetwork }
        if n.contains("nhl net") { return .nhlNetwork }
        return .other
    }
}

// MARK: - Picking the link

@MainActor
enum Streaming {
    static func bestLink(for game: Game, services: [Service]) -> WatchLink {
        // A league pass's blackout is the game's, not the broadcast's: it carries a game only when neither team is local.
        let outOfMarket = Markets.isLocal(game, market: .national) == false
        for broadcast in game.broadcasts {
            let channel = Channel.of(broadcast.name)
            let local = Markets.isLocal(game, market: broadcast.market)

            for service in services {
                let carries: Bool
                if broadcast.market != .national {
                    // A team's own channel: local viewers watch it on TV; everyone else on a league pass.
                    if local == false {
                        carries = outOfMarket && service.carriesOutOfMarket(game.league)
                    } else {
                        carries = service.channels.contains(.regional)
                            || service.channels.contains(channel) && channel != .regional && channel != .other
                    }
                } else {
                    carries = service.channels.contains(channel)
                }
                guard carries else { continue }
                return link(service, broadcast: broadcast.name, game: game)
            }
        }
        return WatchLink(label: "Not on your services", url: game.followLive, isAvailable: false)
    }

    private static func link(_ service: Service, broadcast: String, game: Game) -> WatchLink {
        switch service {
        case .espn, .espnPlus:
            return WatchLink(label: "Watch on ESPN", url: game.deepLink(for: service) ?? service.url ?? game.followLive)
        case .youtubeTV, .huluLive, .sling, .fubo, .directv:
            // Live TV services sign in to ESPN's own player, which goes straight into the game.
            if [.espn, .espnPlus, .abc, .conference].contains(Channel.of(broadcast)), let espn = game.deepLink(for: .espn) {
                return WatchLink(label: "Watch on ESPN", url: espn)
            }
            return WatchLink(label: "Watch on \(service.short)", url: service.url ?? game.followLive)
        case .prime, .appleTV:
            return WatchLink(label: "Watch on \(service.short)", url: game.deepLink(for: service) ?? service.url ?? game.followLive)
        case .cable:
            let espn = [.espn, .espnPlus, .abc, .conference].contains(Channel.of(broadcast))
            let url = (espn ? game.deepLink(for: .espn) : nil)
                ?? WatchLink.forNetwork(broadcast, league: game.league)?.url ?? game.followLive
            return WatchLink(label: "Watch on \(broadcast)", url: url)
        case .antenna:
            return WatchLink(label: "On \(broadcast) (antenna)", url: game.followLive)
        default:
            return WatchLink(label: "Watch on \(service.short)", url: service.url ?? game.followLive)
        }
    }
}

// MARK: - Local markets

/// Whether a team's regional broadcast reaches the person, from how far they are from the team's city.
@MainActor
enum Markets {
    private struct Spot: Codable { var latitude: Double; var longitude: Double }
    private static var spots = LampStore.load([String: Spot].self, from: "teamCities") ?? [:]
    private static var failed: Set<String> = []

    /// Regional networks reach roughly this far from a team's city.
    static let reachKm = 250.0

    /// True when local, false when out of market, nil when it isn't known (no location set yet).
    static func isLocal(_ game: Game, market: Broadcast.Market) -> Bool? {
        let s = Watcher.shared.settings
        guard let lat = s.homeLatitude, let lon = s.homeLongitude else { return nil }
        let teams: [Team] = switch market {
        case .home: [game.home]
        case .away: [game.away]
        case .national: [game.home, game.away]
        }
        var known = false
        for team in teams {
            guard let key = key(for: team, game), let spot = spots[key] else { continue }
            known = true
            if distanceKm(lat, lon, spot.latitude, spot.longitude) <= reachKm { return true }
        }
        return known ? false : nil
    }

    /// Looks up the cities of teams on regional broadcasts, a few each time so the map service isn't flooded.
    static func prepare(_ games: [Game], settings: WatchSettings) async {
        guard settings.homeLatitude != nil, !settings.myServices.isEmpty else { return }
        var wanted: [String] = []
        for game in games where game.state != .post && game.broadcasts.contains(where: { $0.market != .national }) {
            for team in [game.home, game.away] {
                if let key = key(for: team, game), spots[key] == nil, !failed.contains(key), !wanted.contains(key) {
                    wanted.append(key)
                }
            }
        }
        var changed = false
        for key in wanted.prefix(8) {
            if let place = try? await LampLocation.find(key) {
                spots[key] = Spot(latitude: place.latitude, longitude: place.longitude)
                changed = true
            } else {
                failed.insert(key)
            }
        }
        if changed { LampStore.save(spots, to: "teamCities") }
    }

    private static func key(for team: Team, _ game: Game) -> String? {
        guard let city = team.city, !city.isEmpty else { return nil }
        return game.league == .epl || game.league == .laliga || game.league == .ucl ? nil : city
    }

    private static func distanceKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180, dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(a)))
    }
}

// MARK: - Deep links

extension Game {
    /// A link into the game itself where the service allows one: ESPN's player for this game,
    /// or a search for the matchup on services that don't link to single games.
    @MainActor func deepLink(for service: Service) -> URL? {
        let matchup = "\(away.name) \(home.name)"
        switch service {
        case .espn, .espnPlus:
            return Watcher.shared.espnStreams[id]
        case .appleTV:
            var c = URLComponents(string: "https://tv.apple.com/search")!
            c.queryItems = [URLQueryItem(name: "term", value: matchup)]
            return c.url
        case .prime:
            var c = URLComponents(string: "https://www.amazon.com/s")!
            c.queryItems = [URLQueryItem(name: "k", value: "\(away.name) vs \(home.name)"), URLQueryItem(name: "i", value: "instant-video")]
            return c.url
        default:
            return nil
        }
    }
}

extension Watcher {
    /// Reads ESPN's live listings for the player link of each game streaming there.
    /// Only when a live game is on an ESPN channel, and at most every three minutes.
    func refreshESPNStreams() async {
        let onESPN = games.contains { game in
            game.state == .live && espnStreams[game.id] == nil &&
                game.broadcasts.contains { [.espn, .espnPlus, .abc, .conference].contains(Channel.of($0.name)) }
        }
        guard onESPN, Date().timeIntervalSince(espnFetched ?? .distantPast) > 180 else { return }
        espnFetched = Date()

        let url = URL(string: "https://watch.product.api.espn.com/api/product/v3/watchespn/web/home?lang=en&features=pbov7&countryCode=US&entitlements=ESPN_PLUS&tz=America/New_York")!
        guard let data = try? await URLSession.shared.data(from: url).0,
              let root = try? JSONSerialization.jsonObject(with: data) else { return }

        var found: [String: URL] = [:]
        func walk(_ value: Any) {
            if let dict = value as? [String: Any] {
                if let eventID = dict["eventId"], let streams = dict["streams"] as? [[String: Any]] {
                    let live = streams.filter { $0["status"] as? String == "live" }
                    let pick = live.first { $0["tier"] as? String == "primary" } ?? live.first ?? streams.first
                    if let web = (pick?["links"] as? [String: Any])?["web"] as? String, let link = URL(string: web) {
                        let key = "\(eventID)"
                        if found[key] == nil { found[key] = link }
                    }
                }
                dict.values.forEach(walk)
            } else if let list = value as? [Any] {
                list.forEach(walk)
            }
        }
        walk(root)
        let current = Set(games.map(\.id))
        espnStreams = espnStreams.filter { current.contains($0.key) }.merging(found) { _, new in new }
    }
}
