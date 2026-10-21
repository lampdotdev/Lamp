import Foundation

// MARK: - What a game's ESPN page adds to the scoreboard

/// One point on the win probability line: the home team's chance after a play.
struct WinPoint: Hashable {
    var home: Double          // 0...1
    var at: Date?             // when the play happened, if ESPN says
}

/// A highlights clip.
struct Clip: Codable, Hashable {
    var title: String
    var url: URL
    var seconds: Int?
}

/// The extra facts from a game's summary page. Every part is optional: the page isn't an official API.
struct GameDetail {
    var winProbability: [WinPoint] = []
    var keyPlay: String?
    var highlights: Clip?
    var fetched = Date()

    /// The home team's chance now, if ESPN gives one.
    var homeChance: Double? { winProbability.last?.home }

    /// The largest change in the home team's chance over roughly the last few minutes of real time
    /// (or the last stretch of plays when there are no times), with the chance before and after.
    var recentSwing: (from: Double, to: Double, size: Double)? {
        guard winProbability.count >= 6, let now = winProbability.last else { return nil }
        let window: ArraySlice<WinPoint>
        if let end = now.at, winProbability.allSatisfy({ $0.at != nil }) {
            let start = end.addingTimeInterval(-8 * 60)
            window = winProbability.drop { ($0.at ?? .distantPast) < start }
        } else {
            window = winProbability.suffix(max(6, winProbability.count / 8))
        }
        guard let low = window.min(by: { $0.home < $1.home }), let high = window.max(by: { $0.home < $1.home }) else { return nil }
        let size = high.home - low.home
        // "From" is whichever extreme came first, so the swing reads in the order it happened.
        let lowFirst = (window.firstIndex(of: low) ?? 0) < (window.firstIndex(of: high) ?? 0)
        return lowFirst ? (low.home, now.home, size) : (high.home, now.home, size)
    }
}

/// A game Buzzer Beater showed as good, kept so it can offer highlights once it ends.
struct FlaggedGame: Codable, Hashable {
    var id: String
    var league: String
    var title: String
    var flaggedAt: Date
    var endedAt: Date?
    var finalScore: String?
    var highlights: Clip?
    var notified: Bool?
    /// The game as the scoreboard last had it once it ended, kept (and saved) for "Just ended" and its highlights after
    /// ESPN's scoreboard has moved on to the next day.
    var game: Game?
}

// MARK: - Fetching

enum SummaryFeed {
    static func detail(for game: Game) async -> GameDetail? {
        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(game.league.path)/summary?event=\(game.id)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let data = try? await URLSession.shared.data(for: request).0,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var detail = parse(root, game: game)
        // The game data can lag behind ESPN's own page, which often has the recap clip first.
        if game.state == .post, detail.highlights == nil {
            detail.highlights = await pageHighlights(for: game)
        }
        return detail
    }

    /// The full game highlights clip as linked from the game's web page, if it's there yet.
    static func pageHighlights(for game: Game) async -> Clip? {
        var request = URLRequest(url: game.gamePage)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 (Macintosh)", forHTTPHeaderField: "User-Agent")
        guard let data = try? await URLSession.shared.data(for: request).0,
              let html = String(data: data, encoding: .utf8) else { return nil }
        let pattern = #"/video/clip/_/id/(\d+)/[a-z0-9-]*game-highlights"#
        guard let match = html.range(of: pattern, options: .regularExpression) else { return nil }
        let path = String(html[match])
        guard let url = URL(string: "https://www.espn.com" + path) else { return nil }
        return Clip(title: "\(game.away.name) vs. \(game.home.name): Game Highlights", url: url, seconds: nil)
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func date(_ s: Any?) -> Date? {
        guard let s = s as? String else { return nil }
        return iso.date(from: s) ?? iso.date(from: s.replacingOccurrences(of: "Z", with: ":00Z"))
    }

    private static func number(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s) }
        return nil
    }

    static func parse(_ root: [String: Any], game: Game) -> GameDetail {
        var detail = GameDetail()

        // Plays: basketball, hockey and baseball list them; football groups them into drives.
        var plays = root["plays"] as? [[String: Any]] ?? []
        if plays.isEmpty, let drives = root["drives"] as? [String: Any] {
            var all = (drives["previous"] as? [[String: Any]]) ?? []
            if let current = drives["current"] as? [String: Any] { all.append(current) }
            for drive in all { plays += drive["plays"] as? [[String: Any]] ?? [] }
        }
        var playTimes: [String: Date] = [:]
        for play in plays {
            if let id = play["id"] as? String, let t = date(play["wallclock"]) { playTimes[id] = t }
        }

        // Win probability, in play order.
        var chanceAfter: [String: Double] = [:]
        for point in root["winprobability"] as? [[String: Any]] ?? [] {
            guard let home = number(point["homeWinPercentage"]), (0...1).contains(home) else { continue }
            let playID = point["playId"] as? String
            if let playID { chanceAfter[playID] = home }
            detail.winProbability.append(WinPoint(home: home, at: playID.flatMap { playTimes[$0] }))
        }

        detail.keyPlay = keyPlay(plays, chanceAfter: chanceAfter, game: game)
        detail.highlights = highlights(root["videos"] as? [[String: Any]] ?? [], game: game)
        return detail
    }

    /// The latest play that mattered: a score or a big jump in the odds, among the last few; else the latest play.
    private static func keyPlay(_ plays: [[String: Any]], chanceAfter: [String: Double], game: Game) -> String? {
        let recent = plays.suffix(15).filter {
            let text = ($0["text"] as? String ?? "").lowercased()
            return !text.isEmpty && !text.hasPrefix("end") && !text.contains("timeout") && !text.hasPrefix("start")
        }
        guard !recent.isEmpty else { return nil }

        var chosen: [String: Any]?
        var previous: Double?
        for play in recent {
            let id = play["id"] as? String
            let chance = id.flatMap { chanceAfter[$0] }
            let jump = (chance != nil && previous != nil) ? abs(chance! - previous!) : 0
            if play["scoringPlay"] as? Bool == true || jump >= 0.08 { chosen = play }
            if let chance { previous = chance }
        }
        let play = chosen ?? recent.last!
        guard var text = play["text"] as? String else { return nil }
        // Football's play text starts with the clock and formation: "(00:49) No Huddle-Shotgun #7 J.Hollins pass…"
        for pattern in [#"^\(\d+:\d+\)\s*"#, #"^(No Huddle-)?Shotgun\s*"#, #"^\((No Huddle|Shotgun)\)\s*"#, #"^No Huddle\s*"#] {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: #"#\d+ "#, with: "", options: .regularExpression)
        if text.count > 110 { text = String(text.prefix(107)) + "…" }

        let clock = (play["clock"] as? [String: Any])?["displayValue"] as? String
        let period = (play["period"] as? [String: Any])?["number"] as? Int
        var when = ""
        if game.league.sport == .baseball {
            when = period.map { Excitement.ordinal($0) } ?? ""
        } else if let clock, let period {
            let p = period > game.league.periods ? "OT" : (game.league.sport == .soccer ? "" : "Q\(period)")
            when = game.league.sport == .hockey && period <= 3 ? "P\(period) \(clock)" : "\(p) \(clock)"
            if game.league.sport == .soccer { when = clock }
        }
        when = when.trimmingCharacters(in: .whitespaces)
        return when.isEmpty ? text : "\(when) · \(text)"
    }

    /// The full game highlights clip, not the single-play ones.
    private static func highlights(_ videos: [[String: Any]], game: Game) -> Clip? {
        // A "Game Highlights" clip first; anything else called highlights after.
        let ordered = videos.filter { ($0["headline"] as? String ?? "").lowercased().contains("game highlights") }
            + videos.filter { !($0["headline"] as? String ?? "").lowercased().contains("game highlights") }
        for video in ordered {
            guard let title = video["headline"] as? String,
                  title.lowercased().contains("highlights") else { continue }
            let links = video["links"] as? [String: Any]
            let web = (links?["web"] as? [String: Any])?["href"] as? String
            guard let web, let url = URL(string: web) else { continue }
            return Clip(title: title, url: url, seconds: video["duration"] as? Int)
        }
        return nil
    }
}

// MARK: - Keeping details current

extension Watcher {
    /// Live games worth a closer look: anything the scoreboard already likes, and any game late enough
    /// that the odds could tell a different story than the score.
    func detailCandidates() -> [Game] {
        games
            .filter { $0.state == .live }
            .filter { ($0.buzz?.score ?? 0) >= 30 || Excitement.gameProgress($0) >= 0.7 }
            .sorted { ($0.buzz?.score ?? 0) > ($1.buzz?.score ?? 0) }
            .prefix(15)
            .map { $0 }
    }

    /// Fetches summaries for interesting live games, and for ended flagged games still waiting on highlights,
    /// then re-rates the live ones with their win probability.
    func refreshDetails() async {
        var wanted = detailCandidates()
        let now = Date()
        for game in flaggedEnded {
            guard let flag = flagged[game.id], flag.highlights == nil else { continue }
            let ended = flag.endedAt ?? now
            let last = details[game.id]?.fetched ?? .distantPast
            if now.timeIntervalSince(ended) < 24 * 3600, now.timeIntervalSince(last) > 4 * 60 { wanted.append(game) }
        }
        // The other live games too, less often: a swing in win probability (`Excitement.winMoments`, from 40% of
        // the way through) makes a game tense before the score or clock does.
        let picked = Set(wanted.map(\.id))
        let others = games.filter { game in
            guard game.state == .live, !picked.contains(game.id), Excitement.gameProgress(game) >= 0.4,
                  [.basketball, .football, .baseball].contains(game.league.sport) else { return false }
            guard let last = details[game.id] else { return true }
            let wait: TimeInterval = last.winProbability.isEmpty ? 10 * 60 : 3 * 60
            return now.timeIntervalSince(last.fetched) > wait
        }
        wanted += others.prefix(20)
        guard !wanted.isEmpty else { return }

        let fetched: [(String, GameDetail)] = await withTaskGroup(of: (String, GameDetail)?.self) { group in
            for game in wanted {
                group.addTask { await SummaryFeed.detail(for: game).map { (game.id, $0) } }
            }
            var all: [(String, GameDetail)] = []
            for await item in group { if let item { all.append(item) } }
            return all
        }
        for (id, detail) in fetched { details[id] = detail }

        let favorites = favoriteTeamNames
        games = games.map { game in
            guard game.state == .live, let detail = details[game.id] else { return game }
            var game = game
            game.buzz = Excitement.evaluate(game, favorites: favorites, detail: detail)
            return game
        }
    }

    /// Remembers games shown as good, notes when they end, and announces highlights once.
    func trackFlaggedGames() {
        let now = Date()
        var changed = false
        for game in hotGames where flagged[game.id] == nil {
            flagged[game.id] = FlaggedGame(id: game.id, league: game.league.rawValue, title: game.title, flaggedAt: now)
            changed = true
        }
        for game in games where game.state == .post {
            guard var flag = flagged[game.id], flag.game != game else { continue }
            flag.game = game
            flagged[game.id] = flag
            changed = true
        }
        for game in flaggedEnded {
            guard var flag = flagged[game.id] else { continue }
            if flag.endedAt == nil {
                flag.endedAt = now
                flag.finalScore = "\(game.away.abbr) \(game.away.score) – \(game.home.score) \(game.home.abbr)"
                changed = true
            }
            if flag.highlights == nil, let clip = details[game.id]?.highlights {
                flag.highlights = clip
                changed = true
            }
            if flag.highlights != nil, flag.notified != true {
                flag.notified = true
                changed = true
                if settings.notify {
                    LampNotifications.send("Missed it? Highlights are up",
                                           body: "\(game.away.name) \(game.away.score), \(game.home.name) \(game.home.score) · \(game.league.short)",
                                           id: "hl-\(game.id)", actions: ["Watch Highlights"])
                }
            }
            flagged[game.id] = flag
        }
        let cutoff = now.addingTimeInterval(-2 * 86_400)
        let old = flagged.filter { $0.value.flaggedAt < cutoff }.map(\.key)
        for id in old { flagged[id] = nil; changed = true }
        if changed { LampStore.save(flagged, to: "flagged") }
    }

    /// Flagged games that have ended: those on today's scoreboard, and those kept from an earlier one.
    var flaggedEnded: [Game] {
        let here = games.filter { $0.state == .post && flagged[$0.id] != nil }
        let ids = Set(here.map(\.id))
        return here + flagged.values.compactMap(\.game).filter { !ids.contains($0.id) }
    }

    /// Flagged games that ended in the last twelve hours, newest first.
    var endedFlagged: [Game] {
        let cutoff = Date().addingTimeInterval(-12 * 3600)
        return flaggedEnded
            .filter { (flagged[$0.id]?.endedAt ?? .distantPast) > cutoff }
            .sorted { (flagged[$0.id]?.endedAt ?? .distantPast) > (flagged[$1.id]?.endedAt ?? .distantPast) }
    }

    static func loadFlagged() -> [String: FlaggedGame] {
        LampStore.load([String: FlaggedGame].self, from: "flagged") ?? [:]
    }
}
