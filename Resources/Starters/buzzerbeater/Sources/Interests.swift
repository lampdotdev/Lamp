/// One moment the person wants to hear about, in their words, for one league or for any (nil).
/// A league's moment is its criteria, edited from `League.defaultCriteria`; it's only saved once it differs.
struct Moment: Codable, Hashable, Identifiable {
    var text: String
    var league: String?
    var id: String { "\(league ?? "any")|\(text)" }
    var leagueName: String { league.flatMap(League.init(rawValue:))?.name ?? "Any league" }
}

extension League {
    /// What the built-in rules look for, in plain words: the starting point for the person's own criteria.
    var defaultCriteria: String {
        switch sport {
        case .basketball:
            let points = self == .nba ? 48 : 38
            return "Tied or within 3 in the last 5 minutes, a two-possession game in the last 3, overtime, a big underdog or much lower-ranked team leading in the second half, a comeback from 15 or more down, or someone having a huge night (\(points)+ points, 25 rebounds or 18 assists)."
        case .football:
            return "A one-score game in the 4th quarter, tied or within 3 in the last 5 minutes, overtime, a 7-point-plus underdog or much lower-ranked team leading in the second half, a comeback from 17 or more down, or a huge individual game (450+ passing or 220+ rushing or receiving yards)."
        case .hockey:
            return "Tied or a one-goal game late in the 3rd, a goalie about to be pulled, overtime or a shootout, a big underdog leading late, a comeback from 2 or more goals down, or a hat trick."
        case .baseball:
            return "Within a run or two in the 8th or 9th, the tying run on base in the 9th, extra innings, a no-hitter in the 6th or later, a big underdog leading late, a comeback from 4 or more runs down, or someone with 3 home runs."
        case .soccer:
            return "Level or a one-goal game in the last 10 to 25 minutes, extra time or penalties, a big underdog leading in the second half, a comeback from 2 goals down, or a hat trick."
        }
    }
}

extension Watcher {
    /// Moments saved per league; the first ones, made before leagues, count for any league.
    static func loadMoments() -> [Moment] {
        if let saved = LampStore.load([Moment].self, from: "moments") { return saved }
        return (LampStore.load([String].self, from: "interests") ?? []).map { Moment(text: $0, league: nil) }
    }

    func addMoment(_ text: String, league: League?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let moment = Moment(text: trimmed, league: league?.rawValue)
        guard !trimmed.isEmpty, !moments.contains(moment) else { return }
        moments.append(moment)
        LampStore.save(moments, to: "moments")
        Task { await refresh() }
    }

    /// The person's criteria for a league, or nil while it's the built-in one.
    func customCriteria(for league: League) -> String? {
        moments.first { $0.league == league.rawValue }?.text
    }

    /// Sets a league's criteria; empty, or the same as the built-in one, goes back to the built-in rules.
    func setMoment(_ text: String, league: League) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let custom = !trimmed.isEmpty && trimmed != league.defaultCriteria
        if customCriteria(for: league) == (custom ? text : nil) { return }
        moments.removeAll { $0.league == league.rawValue }
        if custom { moments.append(Moment(text: text, league: league.rawValue)) }
        LampStore.save(moments, to: "moments")
    }

    func removeMoment(_ moment: Moment) {
        moments.removeAll { $0 == moment }
        LampStore.save(moments, to: "moments")
        games = games.map { game in
            var game = game
            if game.buzz?.key == "want:\(moment.text)" { game.buzz = Excitement.evaluate(game, favorites: favoriteTeamNames) }
            return game
        }
    }

    /// For leagues with the person's own criteria, the decision model decides which live games are good
    /// (instead of the built-in rules); moments for any league lift matching games on top of that.
    func judgeInterests() async {
        let all = moments
        let live = games.filter { $0.state == .live }
        guard !all.isEmpty, !live.isEmpty else { interestError = nil; return }
        guard await LampAI.isAvailable(.decisions) else {
            interestError = "AI isn't set up yet, so the built-in rules are used for now."
            return
        }

        isJudging = true
        defer { isJudging = false }
        var matched: [String: [String]] = [:]
        var judged: Set<String> = []          // games judged against their league's own criteria
        var firstError: String?

        for (league, games) in Dictionary(grouping: live, by: \.league) {
            let own = customCriteria(for: league)
            let wishes = (own.map { [$0] } ?? []) + all.filter { $0.league == nil }.map(\.text)
            guard !wishes.isEmpty else { continue }
            var questions: [String: LampQuestion] = [:]
            for (i, wish) in wishes.enumerated() {
                let ask = i == 0 && own != nil
                    ? "The person wants to hear about \(league.name) games like this: \"\(wish)\". Does this live game fit that right now?"
                    : "The person asked to be told about: \"\(wish)\". Does this live game match that right now?"
                questions["w\(i)"] = .yesNo(ask,
                    yes: "it clearly fits what they described, as of the current score and situation",
                    no: "it doesn't fit, or only might later")
            }
            do {
                // Unchanged games (same score and clock) aren't judged again.
                let verdicts = try await LampAI.decideEach(games, questions, remember: 15 * 60) { Self.describe($0) }
                for verdict in verdicts {
                    if let error = verdict.error {
                        if firstError == nil { firstError = error }
                        continue
                    }
                    if own != nil { judged.insert(verdict.item.id) }
                    let hits = wishes.enumerated()
                        .filter { (verdict["w\($0.offset)"]?.probability ?? 0) >= 0.7 }
                        .map(\.element)
                    if !hits.isEmpty { matched[verdict.item.id] = hits }
                }
            } catch {
                if firstError == nil { firstError = error.localizedDescription }
            }
        }
        interestError = firstError

        games = games.map { game in
            var game = game
            guard let hits = matched[game.id], let first = hits.first else {
                // Their own criteria said no: not one to watch, whatever the built-in rules thought.
                if judged.contains(game.id) { game.buzz = nil }
                return game
            }
            let own = customCriteria(for: game.league)
            let reason = hits.filter { $0 != own }
            if var buzz = game.buzz {
                if !reason.isEmpty {
                    let asked = "You asked for: \(reason.joined(separator: "; "))"
                    buzz.details = buzz.details.isEmpty ? asked : "\(asked) · \(buzz.details)"
                }
                if buzz.score < 90 {
                    buzz.score = 90
                    buzz.key = "want:\(first)"
                }
                game.buzz = buzz
            } else {
                let headline = first == own ? "Fits what you're watching for in \(game.league.short)" : first.prefix(1).uppercased() + first.dropFirst()
                game.buzz = Buzz(score: 90, headline: headline,
                                 details: "\(game.away.name) \(game.away.score) – \(game.home.score) \(game.home.name)",
                                 symbol: "sparkles", key: "want:\(first)")
            }
            return game
        }
    }

    /// Everything known about a game, as plain facts for the decision model.
    nonisolated static func describe(_ g: Game) -> [String: Any] {
        func team(_ t: Team) -> [String: Any] {
            var d: [String: Any] = ["name": t.name, "abbreviation": t.abbr, "score": t.score]
            if let city = t.city { d["city"] = city }
            if let rank = t.rank { d["ranking"] = rank }
            if let record = t.record { d["record"] = record }
            if let hits = t.hits { d["hits"] = hits }
            return d
        }
        var d: [String: Any] = [
            "league": g.league.name,
            "sport": g.league.sport.rawValue,
            "away": team(g.away),
            "home": team(g.home),
            "status": g.statusText,
            "period": g.period,
            "overtime": g.isOvertime,
            "percentOfGamePlayed": Int(Excitement.gameProgress(g) * 100),
        ]
        if let left = g.minutesLeft { d["minutesLeftInRegulation"] = (left * 10).rounded() / 10 }
        if let line = g.line {
            d["pregameFavorite"] = line.favorite
            if let spread = line.spread { d["pregameSpread"] = spread }
        }
        if !g.leaders.isEmpty {
            d["statLeaders"] = g.leaders.map { "\($0.player): \($0.display) (\($0.stat))" }
        }
        if !g.networks.isEmpty { d["onTV"] = g.networks }
        if let buzz = g.buzz, !buzz.headline.isEmpty { d["whatsHappening"] = buzz.headline }
        return d
    }
}
