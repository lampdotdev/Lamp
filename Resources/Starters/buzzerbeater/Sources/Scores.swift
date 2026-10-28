import SwiftUI

// MARK: - Leagues

enum Sport: String, Codable { case football, basketball, hockey, baseball, soccer }

enum League: String, Codable, CaseIterable, Identifiable {
    case nfl, cfb, nba, wnba, mcbb, wcbb, nhl, mlb, epl, mls, ucl, laliga

    var id: String { rawValue }

    var name: String {
        switch self {
        case .nfl: "NFL"
        case .cfb: "College Football"
        case .nba: "NBA"
        case .wnba: "WNBA"
        case .mcbb: "Men's College Basketball"
        case .wcbb: "Women's College Basketball"
        case .nhl: "NHL"
        case .mlb: "MLB"
        case .epl: "Premier League"
        case .mls: "MLS"
        case .ucl: "Champions League"
        case .laliga: "La Liga"
        }
    }

    var short: String {
        switch self {
        case .cfb: "NCAAF"
        case .mcbb: "NCAAM"
        case .wcbb: "NCAAW"
        case .epl: "EPL"
        case .ucl: "UCL"
        case .laliga: "LIGA"
        default: rawValue.uppercased()
        }
    }

    var sport: Sport {
        switch self {
        case .nfl, .cfb: .football
        case .nba, .wnba, .mcbb, .wcbb: .basketball
        case .nhl: .hockey
        case .mlb: .baseball
        case .epl, .mls, .ucl, .laliga: .soccer
        }
    }

    /// Regulation periods and their length in minutes (innings for baseball).
    var periods: Int {
        switch self {
        case .mcbb: 2
        case .nhl: 3
        case .mlb: 9
        case .epl, .mls, .ucl, .laliga: 2
        default: 4
        }
    }

    var periodMinutes: Double {
        switch self {
        case .nfl, .cfb: 15
        case .nba: 12
        case .wnba, .wcbb: 10
        case .mcbb, .nhl: 20
        case .mlb: 0
        case .epl, .mls, .ucl, .laliga: 45
        }
    }

    var path: String {
        switch self {
        case .nfl: "football/nfl"
        case .cfb: "football/college-football"
        case .nba: "basketball/nba"
        case .wnba: "basketball/wnba"
        case .mcbb: "basketball/mens-college-basketball"
        case .wcbb: "basketball/womens-college-basketball"
        case .nhl: "hockey/nhl"
        case .mlb: "baseball/mlb"
        case .epl: "soccer/eng.1"
        case .mls: "soccer/usa.1"
        case .ucl: "soccer/uefa.champions"
        case .laliga: "soccer/esp.1"
        }
    }

    var scoreboardURL: URL {
        var query = "limit=400"
        switch self {
        case .cfb: query += "&groups=80"
        case .mcbb: query += "&groups=50"
        case .wcbb: query += "&groups=50"
        default: break
        }
        return URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(path)/scoreboard?\(query)")!
    }

    static let defaults: Set<League> = [.nfl, .cfb, .nba, .wnba, .mcbb, .nhl, .mlb, .epl, .mls, .ucl]
}

// MARK: - Games

struct Team: Codable, Hashable {
    var abbr: String
    var name: String
    var score: Int
    var logo: URL?
    var rank: Int?
    var record: String?
    var hits: Int?
    var city: String? = nil
    var color: String? = nil
}

struct Broadcast: Codable, Hashable {
    enum Market: String, Codable { case national, home, away }
    var name: String
    var market: Market
}

struct Leader: Codable, Hashable {
    var stat: String       // e.g. "points", "goals", "passingYards"
    var player: String
    var value: Double
    var display: String
}

/// The pregame line, kept from before kickoff since the scoreboard can drop it once play starts.
struct Line: Codable, Hashable {
    var favorite: String   // team abbreviation
    var spread: Double?    // points, always positive
    var moneyline: Int?    // favorite's moneyline, e.g. -250
}

struct Game: Identifiable, Codable, Hashable {
    enum State: String, Codable { case pre, live, post }

    var id: String
    var league: League
    var away: Team
    var home: Team
    var state: State
    var statusText: String
    var period: Int
    var clockSeconds: Double
    var start: Date
    var gamecast: URL?
    var networks: [String]
    var leaders: [Leader]
    var line: Line?
    var outs: Int?
    var runnersOn: Int?
    var buzz: Buzz?
    var broadcasts: [Broadcast] = []

    var margin: Int { abs(away.score - home.score) }
    var title: String { "\(away.name) at \(home.name)" }
    var leader: Team? { away.score == home.score ? nil : (away.score > home.score ? away : home) }
    var trailer: Team? { away.score == home.score ? nil : (away.score > home.score ? home : away) }

    /// Minutes of regulation left (nil for baseball, which has no clock). Zero or less means overtime.
    var minutesLeft: Double? {
        guard league.sport != .baseball else { return nil }
        if league.sport == .soccer {
            // The soccer clock counts up: 78:00 means 12 minutes left.
            let played = clockSeconds / 60
            return max(0, 90 - played)
        }
        let remainingPeriods = Double(max(0, league.periods - period))
        return remainingPeriods * league.periodMinutes + clockSeconds / 60
    }

    var isOvertime: Bool { period > league.periods }
}

// MARK: - Settings

enum Pickiness: String, Codable, CaseIterable, Identifiable {
    case onlyClassics, goodOnes, anythingTense
    var id: String { rawValue }
    var label: String {
        switch self {
        case .onlyClassics: "Only instant classics"
        case .goodOnes: "Good games"
        case .anythingTense: "Anything tense"
        }
    }
    var threshold: Int {
        switch self {
        case .onlyClassics: 80
        case .goodOnes: 60
        case .anythingTense: 40
        }
    }
}

struct WatchSettings: Codable, Equatable {
    var leagues: [String] = League.defaults.map(\.rawValue)
    var pickiness: Pickiness = .goodOnes
    var notify: Bool = true
    var favoriteTeams: String? = nil
    var services: [String]? = nil
    var homeName: String? = nil
    var homeLatitude: Double? = nil
    var homeLongitude: Double? = nil
    var onlyWatchable: Bool? = nil

    var myServices: [Service] { Service.allCases.filter { (services ?? []).contains($0.rawValue) } }

    var enabledLeagues: [League] { League.allCases.filter { leagues.contains($0.rawValue) } }
}

// MARK: - Watcher

@MainActor
final class Watcher: ObservableObject {
    static let shared = Watcher()

    @Published var games: [Game] = []
    @Published var lastUpdated: Date?
    @Published var isLoading = false
    @Published var error: String?
    @Published var settings: WatchSettings {
        didSet {
            LampStore.save(settings, to: "settings")
            Task { await refresh() }
        }
    }

    /// Moments the person described in their own words, checked against every live game.
    @Published var interests: [String] = LampStore.load([String].self, from: "interests") ?? []
    @Published var moments: [Moment] = Watcher.loadMoments()
    @Published var interestError: String?
    @Published var isJudging = false
    /// ESPN's player link for each live game streaming there, by game.
    @Published var espnStreams: [String: URL] = [:]
    var espnFetched: Date?
    /// Games starting in the next day and a half, for when nothing's on.
    @Published var upcoming: [Game] = []
    var upcomingFetched: Date?
    /// Win probability, key play and highlights from each game's ESPN page, by game.
    @Published var details: [String: GameDetail] = [:]
    /// Games shown as good, kept to offer highlights when they end.
    @Published var flagged: [String: FlaggedGame] = Watcher.loadFlagged()

    private var lines: [String: Line]
    private var schedule: LampSchedule?

    var liveGames: [Game] { games.filter { $0.state == .live } }
    var liveCount: Int { liveGames.count }

    var hotGames: [Game] {
        liveGames
            .filter { ($0.buzz?.score ?? 0) >= settings.pickiness.threshold }
            .sorted { ($0.buzz?.score ?? 0) > ($1.buzz?.score ?? 0) }
    }

    var otherLive: [Game] {
        let hot = Set(hotGames.map(\.id))
        return liveGames
            .filter { !hot.contains($0.id) }
            .sorted {
                let a = $0.buzz?.score ?? 0, b = $1.buzz?.score ?? 0
                if a != b { return a > b }
                if $0.league != $1.league {
                    return (League.allCases.firstIndex(of: $0.league) ?? 0) < (League.allCases.firstIndex(of: $1.league) ?? 0)
                }
                return $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start
            }
    }

    private init() {
        settings = LampStore.load(WatchSettings.self, from: "settings") ?? WatchSettings()
        lines = LampStore.load([String: Line].self, from: "lines") ?? [:]
        Alerts.setUp()
        schedule = LampSchedule.every("scores", minutes: 1) {
            await Watcher.shared.refresh()
        }
        Task { await refresh() }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let leagues = settings.enabledLeagues
        var fetched: [Game] = []
        var failures = 0
        await withTaskGroup(of: [Game]?.self) { group in
            for league in leagues {
                group.addTask { try? await ScoreFeed.games(for: league) }
            }
            for await result in group {
                if let result { fetched += result } else { failures += 1 }
            }
        }

        if failures == leagues.count, !leagues.isEmpty {
            error = "Couldn't reach the scores. Will try again in a minute."
            return
        }
        error = nil

        // Keep pregame lines so upsets can still be spotted once play starts.
        var linesChanged = false
        for game in fetched where game.line != nil && lines[game.id] == nil {
            lines[game.id] = game.line
            linesChanged = true
        }
        let current = Set(fetched.map(\.id))
        if lines.count > 2000 { lines = lines.filter { current.contains($0.key) }; linesChanged = true }
        if linesChanged { LampStore.save(lines, to: "lines") }

        await Markets.prepare(fetched, settings: settings)

        let favorites = favoriteTeamNames
        games = fetched.map { game in
            var game = game
            if game.line == nil { game.line = lines[game.id] }
            game.buzz = Excitement.evaluate(game, favorites: favorites, detail: details[game.id])
            return game
        }
        lastUpdated = Date()
        await refreshUpcoming()
        await refreshDetails()
        await refreshESPNStreams()
        await judgeInterests()

        if settings.notify {
            let watchable = settings.onlyWatchable == true && !settings.myServices.isEmpty
            Alerts.consider(watchable ? hotGames.filter { $0.watchLink.isAvailable } : hotGames)
        }
        trackFlaggedGames()
    }

    var favoriteTeamNames: [String] {
        (settings.favoriteTeams ?? "")
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }
}

// MARK: - ESPN scoreboard

enum ScoreFeed {
    static func games(for league: League, dates: String? = nil) async throws -> [Game] {
        var url = league.scoreboardURL
        if let dates, let withDates = URL(string: url.absoluteString + "&dates=\(dates)") { url = withDates }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = root["events"] as? [[String: Any]] else { return [] }
        return events.compactMap { parse($0, league: league) }
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func date(_ string: String?) -> Date {
        guard let string else { return Date() }
        if let d = isoFormatter.date(from: string) { return d }
        // ESPN often leaves off seconds: 2026-10-20T19:00Z
        let fixed = string.replacingOccurrences(of: "Z", with: ":00Z")
        return isoFormatter.date(from: fixed) ?? Date()
    }

    private static func parse(_ event: [String: Any], league: League) -> Game? {
        guard let id = event["id"] as? String,
              let competition = (event["competitions"] as? [[String: Any]])?.first,
              let competitors = competition["competitors"] as? [[String: Any]],
              let homeRaw = competitors.first(where: { $0["homeAway"] as? String == "home" }),
              let awayRaw = competitors.first(where: { $0["homeAway"] as? String == "away" })
        else { return nil }

        let status = (competition["status"] as? [String: Any]) ?? (event["status"] as? [String: Any]) ?? [:]
        let type = status["type"] as? [String: Any] ?? [:]
        let stateRaw = type["state"] as? String ?? "pre"
        let state: Game.State = stateRaw == "in" ? .live : (stateRaw == "post" ? .post : .pre)

        let home = team(homeRaw)
        let away = team(awayRaw)

        let links = event["links"] as? [[String: Any]] ?? []
        // The game page is "summary" before and after a game and "live" during it.
        let gamecast = (links.first(where: { ($0["rel"] as? [String])?.contains("summary") == true })
            ?? links.first(where: { ($0["rel"] as? [String])?.contains("live") == true }))
            .flatMap { $0["href"] as? String }
            .flatMap(URL.init(string:))

        var broadcasts: [Broadcast] = []
        for g in competition["geoBroadcasts"] as? [[String: Any]] ?? [] {
            let kind = ((g["type"] as? [String: Any])?["shortName"] as? String ?? "TV").lowercased()
            guard kind != "radio", let name = (g["media"] as? [String: Any])?["shortName"] as? String else { continue }
            let market = ((g["market"] as? [String: Any])?["type"] as? String ?? "National").lowercased()
            broadcasts.append(Broadcast(name: name, market: Broadcast.Market(rawValue: market) ?? .national))
        }
        for b in competition["broadcasts"] as? [[String: Any]] ?? [] {
            let market = Broadcast.Market(rawValue: (b["market"] as? String ?? "national").lowercased()) ?? .national
            for name in b["names"] as? [String] ?? [] where !broadcasts.contains(where: { $0.name == name }) {
                broadcasts.append(Broadcast(name: name, market: market))
            }
        }
        var seen = Set<String>()
        broadcasts = broadcasts.filter { seen.insert($0.name).inserted }
        let networks = broadcasts.map(\.name)

        var leaders: [Leader] = []
        for c in [homeRaw, awayRaw] {
            for category in c["leaders"] as? [[String: Any]] ?? [] {
                guard let stat = category["name"] as? String,
                      let top = (category["leaders"] as? [[String: Any]])?.first else { continue }
                let athlete = top["athlete"] as? [String: Any]
                leaders.append(Leader(
                    stat: stat,
                    player: athlete?["displayName"] as? String ?? athlete?["fullName"] as? String ?? "",
                    value: top["value"] as? Double ?? 0,
                    display: top["displayValue"] as? String ?? ""))
            }
        }

        var line: Line?
        if let odds = (competition["odds"] as? [[String: Any]])?.first {
            let homeOdds = odds["homeTeamOdds"] as? [String: Any]
            let awayOdds = odds["awayTeamOdds"] as? [String: Any]
            let favorite: String?
            if homeOdds?["favorite"] as? Bool == true { favorite = home.abbr }
            else if awayOdds?["favorite"] as? Bool == true { favorite = away.abbr }
            else { favorite = nil }
            if let favorite {
                let favOdds = favorite == home.abbr ? homeOdds : awayOdds
                let spread = (odds["spread"] as? Double).map(abs)
                let ml = favOdds?["moneyLine"] as? Int
                line = Line(favorite: favorite, spread: spread, moneyline: ml)
            }
        }

        let situation = competition["situation"] as? [String: Any]
        var runners: Int?
        if league.sport == .baseball, let situation {
            runners = ["onFirst", "onSecond", "onThird"].filter { situation[$0] as? Bool == true }.count
        }

        return Game(
            id: id,
            league: league,
            away: away,
            home: home,
            state: state,
            statusText: type["shortDetail"] as? String ?? "",
            period: status["period"] as? Int ?? 0,
            clockSeconds: status["clock"] as? Double ?? 0,
            start: date(competition["date"] as? String ?? event["date"] as? String),
            gamecast: gamecast,
            networks: networks,
            leaders: leaders,
            line: line,
            outs: situation?["outs"] as? Int,
            runnersOn: runners,
            broadcasts: broadcasts)
    }

    private static func team(_ raw: [String: Any]) -> Team {
        let t = raw["team"] as? [String: Any] ?? [:]
        let rank = (raw["curatedRank"] as? [String: Any])?["current"] as? Int
        let record = (raw["records"] as? [[String: Any]])?.first?["summary"] as? String
        let score: Int
        if let s = raw["score"] as? String { score = Int(s) ?? 0 }
        else { score = raw["score"] as? Int ?? 0 }
        return Team(
            abbr: t["abbreviation"] as? String ?? "",
            name: t["shortDisplayName"] as? String ?? t["displayName"] as? String ?? "",
            score: score,
            logo: (t["logo"] as? String).flatMap(URL.init(string:)),
            rank: (rank ?? 99) <= 25 ? rank : nil,
            record: record,
            hits: raw["hits"] as? Int,
            city: t["location"] as? String,
            color: t["color"] as? String)
    }
}
