import Foundation

/// Why a game is worth watching right now, and how much.
struct Buzz: Codable, Hashable {
    var score: Int          // 0–100
    var headline: String
    var details: String
    var symbol: String
    var key: String         // what kind of moment, so each one notifies once per game
}

/// Works out from the score, clock, line and stat sheet whether a live game has gotten good.
enum Excitement {
    private struct Moment {
        var score: Int
        var headline: String
        var symbol: String
        var key: String
    }

    /// The biggest lead each team has had in a game, to spot comebacks. Kept while the app runs.
    @MainActor private static var biggestLead: [String: (abbr: String, lead: Int)] = [:]

    @MainActor
    static func evaluate(_ game: Game, favorites: [String], detail: GameDetail? = nil) -> Buzz? {
        guard game.state == .live else {
            if game.state == .post { biggestLead[game.id] = nil }
            return nil
        }
        trackLead(game)

        var moments: [Moment] = []
        // Win probability, when ESPN has it, decides how tense the game is; the score rules are the fallback.
        if let odds = detail.flatMap({ winMoments(game, $0) }) {
            moments += odds
            if game.isOvertime, let m = closeAndLate(game) { moments.append(m) }
        } else if let m = closeAndLate(game) {
            moments.append(m)
        }
        if let m = upset(game) { moments.append(m) }
        if let m = comeback(game) { moments.append(m) }
        moments += bigGames(game)
        if let m = noHitter(game) { moments.append(m) }

        let favorite = isFavorite(game, favorites)
        if moments.isEmpty && !favorite { return nil }

        moments.sort { $0.score > $1.score }
        var top = moments.first ?? Moment(score: 0, headline: "", symbol: "star.fill", key: "favorite")
        let others = moments.dropFirst()

        // Several things going on at once make it better still.
        var score = top.score + others.prefix(2).reduce(0) { $0 + $1.score / 6 }
        if favorite {
            score += 20
            if top.headline.isEmpty {
                top.headline = "Your team is on: \(game.away.name) \(game.away.score), \(game.home.name) \(game.home.score)"
                top.symbol = "star.fill"
            }
        }
        var details = others.map(\.headline)
        if let note = lineNote(game) { details.append(note) }

        return Buzz(score: min(100, score),
                    headline: top.headline,
                    details: details.joined(separator: " · "),
                    symbol: top.symbol,
                    key: top.key)
    }

    // MARK: Close and late

    private static func closeAndLate(_ g: Game) -> Moment? {
        let margin = g.margin
        let lead = g.leader.map { "\($0.name) up \(margin)" } ?? "Tied"

        if g.league.sport == .baseball {
            let inning = g.period
            let half = g.statusText.split(separator: " ").first.map(String.init) ?? ""
            let where_ = "\(half) \(ordinal(inning))".trimmingCharacters(in: .whitespaces)
            if inning > 9 { return Moment(score: 85, headline: "Extra innings, \(lead.lowercasedFirst) in the \(where_)", symbol: "clock.badge.exclamationmark", key: "extras") }
            if inning == 9 && margin <= 1 { return Moment(score: margin == 0 ? 90 : 85, headline: "\(lead) in the \(where_)", symbol: "flame.fill", key: "close") }
            if inning == 9 && margin <= 3 && (g.runnersOn ?? 0) >= 1 { return Moment(score: 70, headline: "Tying run on base: \(lead.lowercasedFirst), \(where_)", symbol: "flame.fill", key: "close") }
            if inning >= 8 && margin <= 2 { return Moment(score: 62, headline: "\(lead) in the \(where_)", symbol: "flame", key: "close") }
            if inning >= 7 && margin <= 1 { return Moment(score: 50, headline: "\(lead) in the \(where_)", symbol: "flame", key: "close") }
            return nil
        }

        guard let left = g.minutesLeft else { return nil }
        let clock = clockText(g)

        if g.isOvertime {
            let label: String
            switch g.league.sport {
            case .soccer: label = g.period >= 5 ? "Penalty shootout" : "Extra time"
            case .hockey: label = g.period >= 5 ? "Shootout" : "Overtime"
            default: label = g.period - g.league.periods > 1 ? "\(ordinal(g.period - g.league.periods)) overtime" : "Overtime"
            }
            return Moment(score: g.period >= 5 && g.league.sport != .basketball && g.league.sport != .football ? 95 : 88,
                          headline: "\(label)! \(lead)", symbol: "clock.badge.exclamationmark", key: "ot\(g.period)")
        }

        switch g.league.sport {
        case .basketball:
            let lateGame = g.league == .nba ? 1.0 : 0.85
            if margin == 0 && left <= 2 * lateGame { return Moment(score: 95, headline: "Tied with \(clock) left", symbol: "flame.fill", key: "clutch") }
            if margin <= 3 && left <= 2 * lateGame { return Moment(score: 88, headline: "\(lead) with \(clock) left", symbol: "flame.fill", key: "clutch") }
            if margin <= 3 && left <= 5 { return Moment(score: 75, headline: "\(lead) with \(clock) left", symbol: "flame.fill", key: "close") }
            if margin <= 6 && left <= 3 { return Moment(score: 66, headline: "Two-possession game, \(clock) left", symbol: "flame", key: "close") }
            if margin <= 6 && left <= 6 { return Moment(score: 52, headline: "\(lead) with \(clock) left", symbol: "flame", key: "tight") }
            if margin <= 10 && left <= 8 { return Moment(score: 35, headline: "Within \(margin) late", symbol: "flame", key: "tight") }
        case .football:
            if margin == 0 && left <= 5 { return Moment(score: 92, headline: "Tied with \(clock) left", symbol: "flame.fill", key: "clutch") }
            if margin <= 3 && left <= 2 { return Moment(score: 92, headline: "\(lead) with \(clock) left: a field goal flips it", symbol: "flame.fill", key: "clutch") }
            if margin <= 8 && left <= 2 { return Moment(score: 86, headline: "One-score game, \(clock) left", symbol: "flame.fill", key: "clutch") }
            if margin <= 8 && left <= 5 { return Moment(score: 74, headline: "\(lead) with \(clock) left", symbol: "flame.fill", key: "close") }
            if margin <= 8 && left <= 10 { return Moment(score: 56, headline: "One-score game in the 4th", symbol: "flame", key: "tight") }
            if margin <= 3 && left <= 15 { return Moment(score: 50, headline: "\(lead) heading into the 4th", symbol: "flame", key: "tight") }
        case .hockey:
            if margin == 0 && left <= 5 { return Moment(score: 85, headline: "Tied with \(clock) left", symbol: "flame.fill", key: "clutch") }
            if margin == 1 && left <= 3 { return Moment(score: 80, headline: "One-goal game, \(clock) left: goalie could get pulled", symbol: "flame.fill", key: "clutch") }
            if margin <= 1 && left <= 10 { return Moment(score: 62, headline: "\(lead) with \(clock) left", symbol: "flame", key: "close") }
            if margin == 0 && left <= 20 { return Moment(score: 48, headline: "Tied in the 3rd", symbol: "flame", key: "tight") }
        case .soccer:
            if margin == 1 && left <= 10 { return Moment(score: 75, headline: "\(lead), \(clock)': holding on", symbol: "flame.fill", key: "clutch") }
            if margin == 0 && left <= 10 && g.away.score + g.home.score >= 2 { return Moment(score: 72, headline: "\(g.away.score)–\(g.home.score) and still level at \(clock)'", symbol: "flame.fill", key: "clutch") }
            if margin == 0 && left <= 10 { return Moment(score: 55, headline: "Level at \(clock)'", symbol: "flame", key: "close") }
            if margin == 1 && left <= 25 { return Moment(score: 50, headline: "\(lead) at \(clock)'", symbol: "flame", key: "tight") }
        case .baseball:
            break
        }
        return nil
    }

    // MARK: Win probability

    /// Moments read from the win probability line: nil when there isn't one, empty when it says the game is decided.
    private static func winMoments(_ g: Game, _ d: GameDetail) -> [Moment]? {
        guard d.winProbability.count >= 6, let home = d.homeChance else { return nil }
        let progress = gameProgress(g)
        var moments: [Moment] = []

        // Near 50/50 late: closeness is 1 at a coin flip, 0 when one side is certain.
        let closeness = 1 - abs(home - 0.5) * 2
        if progress >= 0.6 && closeness >= 0.5 {
            let score = Int(100 * closeness * pow(progress, 1.5))
            if score >= 35 {
                let favored = home >= 0.5 ? g.home : g.away
                let pct = Int((max(home, 1 - home) * 100).rounded())
                let late = progress >= 0.85 && g.league.sport != .baseball ? ", \(clockText(g)) left" : ""
                let headline = pct <= 55
                    ? "Coin flip: \(pct)–\(100 - pct)\(late)"
                    : "\(favored.name) only \(pct)% to win\(late)"
                moments.append(Moment(score: min(95, score), headline: headline, symbol: "flame.fill",
                                      key: closeness >= 0.8 && progress >= 0.85 ? "clutch" : "close"))
            }
        }

        // A hard swing in the last few minutes, whatever the score says.
        if let swing = d.recentSwing, swing.size >= 0.3, progress >= 0.4 {
            let rising = swing.to >= swing.from ? g.home : g.away
            let from = Int(((rising.abbr == g.home.abbr ? swing.from : 1 - swing.from) * 100).rounded())
            let to = Int(((rising.abbr == g.home.abbr ? swing.to : 1 - swing.to) * 100).rounded())
            if to > from {
                let score = min(92, 50 + Int(swing.size * 60) + (progress >= 0.8 ? 8 : 0))
                moments.append(Moment(score: score, headline: "Big swing: \(rising.name) from \(from)% to \(to)% to win",
                                      symbol: "waveform.path.ecg", key: "swing"))
            }
        }
        return moments
    }

    // MARK: Upsets

    private static func upset(_ g: Game) -> Moment? {
        guard let leader = g.leader, let trailer = g.trailer else { return nil }
        let progress = gameProgress(g)
        guard progress >= 0.5 else { return nil }

        // Betting line: the underdog is ahead.
        if let line = g.line, line.favorite == trailer.abbr {
            let big: Bool
            var size = ""
            switch g.league.sport {
            case .football:
                big = (line.spread ?? 0) >= 7
                size = line.spread.map { "\(formatSpread($0))-point" } ?? ""
            case .basketball:
                big = (line.spread ?? 0) >= 6
                size = line.spread.map { "\(formatSpread($0))-point" } ?? ""
            default:
                big = (line.moneyline ?? 0) <= -200
            }
            if big {
                let score = progress >= 0.85 ? 82 : (progress >= 0.7 ? 70 : 58)
                let dog = size.isEmpty ? "big underdog" : "\(size) underdog"
                return Moment(score: score, headline: "Upset brewing: \(leader.name), a \(dog), lead \(trailer.name)",
                              symbol: "exclamationmark.triangle.fill", key: "upset")
            }
        }

        // College rankings: a ranked team losing to an unranked or much lower one.
        if let trailerRank = trailer.rank {
            let leaderRank = leader.rank ?? 40
            if leaderRank - trailerRank >= 10 {
                let score = (progress >= 0.85 ? 80 : (progress >= 0.7 ? 68 : 55)) + (trailerRank <= 5 ? 8 : 0)
                let them = leader.rank.map { "No. \($0) \(leader.name)" } ?? "Unranked \(leader.name)"
                return Moment(score: score, headline: "Upset alert: \(them) leads No. \(trailerRank) \(trailer.name)",
                              symbol: "exclamationmark.triangle.fill", key: "upset")
            }
        }
        return nil
    }

    // MARK: Comebacks

    @MainActor private static func trackLead(_ g: Game) {
        guard let leader = g.leader else { return }
        if let old = biggestLead[g.id], old.lead >= g.margin { return }
        biggestLead[g.id] = (leader.abbr, g.margin)
    }

    @MainActor private static func comeback(_ g: Game) -> Moment? {
        guard let old = biggestLead[g.id] else { return nil }
        let big: Int
        switch g.league.sport {
        case .basketball: big = 15
        case .football: big = 17
        case .hockey, .soccer: big = 2
        case .baseball: big = 4
        }
        guard old.lead >= big else { return nil }
        let other = old.abbr == g.away.abbr ? g.home : g.away
        if g.margin == 0 || g.leader?.abbr == other.abbr {
            let status = g.margin == 0 ? "and it's tied" : "and now lead"
            return Moment(score: 70 + Int(gameProgress(g) * 15),
                          headline: "Comeback: \(other.name) were down \(old.lead) \(status)",
                          symbol: "arrow.uturn.up", key: "comeback")
        }
        if g.margin <= big / 3 && gameProgress(g) >= 0.6 {
            let unit = [.basketball, .football].contains(g.league.sport) ? "point" : (g.league.sport == .baseball ? "run" : "goal")
            return Moment(score: 55, headline: "\(other.name) have cut a \(old.lead)-\(unit) lead to \(g.margin)",
                          symbol: "arrow.uturn.up", key: "comeback-on")
        }
        return nil
    }

    // MARK: Big individual games (record watch)

    private static func bigGames(_ g: Game) -> [Moment] {
        var moments: [Moment] = []
        for leader in g.leaders where !leader.player.isEmpty {
            let stat = leader.stat.lowercased()
            let v = leader.value
            switch g.league.sport {
            case .basketball where stat == "points" || stat == "pointsleader":
                guard v < 120 else { continue }
                let pro = g.league == .nba
                if v >= (pro ? 60 : 45) {
                    moments.append(Moment(score: 92, headline: "\(leader.player) has \(Int(v)) points: a historic night", symbol: "trophy.fill", key: "big-\(leader.player)-\(pro ? 60 : 45)"))
                } else if v >= (pro ? 48 : 38) {
                    moments.append(Moment(score: 72, headline: "\(leader.player) has \(Int(v)) points and counting", symbol: "trophy.fill", key: "big-\(leader.player)"))
                }
            case .basketball where stat == "rebounds":
                if v >= 25 && v < 60 { moments.append(Moment(score: 62, headline: "\(leader.player) has \(Int(v)) rebounds", symbol: "trophy", key: "big-reb-\(leader.player)")) }
            case .basketball where stat == "assists":
                if v >= 18 && v < 40 { moments.append(Moment(score: 62, headline: "\(leader.player) has \(Int(v)) assists", symbol: "trophy", key: "big-ast-\(leader.player)")) }
            case .football where stat.hasPrefix("passing"):
                if v >= 450 && v < 750 { moments.append(Moment(score: v >= 525 ? 85 : 66, headline: "\(leader.player) has thrown for \(Int(v)) yards", symbol: "trophy.fill", key: "big-pass-\(leader.player)")) }
            case .football where stat.hasPrefix("rushing"):
                if v >= 220 && v < 450 { moments.append(Moment(score: v >= 275 ? 85 : 66, headline: "\(leader.player) has run for \(Int(v)) yards", symbol: "trophy.fill", key: "big-rush-\(leader.player)")) }
            case .football where stat.hasPrefix("receiving"):
                if v >= 220 && v < 450 { moments.append(Moment(score: v >= 275 ? 85 : 66, headline: "\(leader.player) has \(Int(v)) receiving yards", symbol: "trophy.fill", key: "big-rec-\(leader.player)")) }
            case .hockey where stat == "goals", .soccer where stat == "goals" || stat == "goalsleader":
                if v >= 4 && v < 10 { moments.append(Moment(score: 85, headline: "\(leader.player) has \(Int(v)) goals", symbol: "trophy.fill", key: "big-\(leader.player)-4")) }
                else if v >= 3 && v < 10 { moments.append(Moment(score: 70, headline: "Hat trick for \(leader.player)", symbol: "trophy.fill", key: "big-\(leader.player)")) }
            case .baseball where stat == "homeruns":
                if v >= 3 && v < 6 { moments.append(Moment(score: 72, headline: "\(leader.player) has hit \(Int(v)) home runs", symbol: "trophy.fill", key: "big-\(leader.player)")) }
            default:
                break
            }
        }
        return moments
    }

    private static func noHitter(_ g: Game) -> Moment? {
        guard g.league.sport == .baseball, g.period >= 6 else { return nil }
        for (batting, pitching) in [(g.away, g.home), (g.home, g.away)] where batting.hits == 0 {
            let through = max(5, g.period - 1)
            let score = min(95, 66 + (g.period - 6) * 9)
            return Moment(score: score, headline: "\(pitching.name) have a no-hitter going in the \(ordinal(g.period))",
                          symbol: "trophy.fill", key: "nohit\(through >= 8 ? "-late" : "")")
        }
        return nil
    }

    // MARK: Helpers

    private static func isFavorite(_ g: Game, _ favorites: [String]) -> Bool {
        guard !favorites.isEmpty else { return false }
        return [g.away, g.home].contains { team in
            favorites.contains { f in team.name.lowercased().contains(f) || team.abbr.lowercased() == f }
        }
    }

    private static func lineNote(_ g: Game) -> String? {
        guard let line = g.line, let spread = line.spread, spread >= 3,
              [.football, .basketball].contains(g.league.sport) else { return nil }
        let fav = line.favorite == g.home.abbr ? g.home.name : (line.favorite == g.away.abbr ? g.away.name : line.favorite)
        return "\(fav) were favored by \(formatSpread(spread))"
    }

    /// How far through regulation, 0 to 1.
    static func gameProgress(_ g: Game) -> Double {
        if g.league.sport == .baseball { return min(1, Double(max(0, g.period - 1)) / 9) }
        let total = Double(g.league.periods) * g.league.periodMinutes
        guard let left = g.minutesLeft, total > 0 else { return 0 }
        return min(1, max(0, 1 - left / total))
    }

    private static func clockText(_ g: Game) -> String {
        if g.league.sport == .soccer { return "\(Int(g.clockSeconds / 60))" }
        let seconds = g.isOvertime ? g.clockSeconds : (g.minutesLeft ?? 0) * 60
        let s = Int(seconds.rounded(.down))
        return s < 60 ? String(format: "%.1f sec", seconds) : String(format: "%d:%02d", s / 60, s % 60)
    }

    private static func formatSpread(_ s: Double) -> String {
        s.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(s))" : String(format: "%.1f", s)
    }

    static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 100, n % 10) {
        case (11...13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }
}

private extension String {
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
