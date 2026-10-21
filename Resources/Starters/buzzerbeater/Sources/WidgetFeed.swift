import AppKit

/// What the desktop widget shows: the games worth watching, tensest first, or a few live ones when none are.
/// The widget declares the same types.
struct WidgetBoard: Codable {
    struct Row: Codable, Hashable {
        var id: String
        var league: String
        var away: String
        var home: String
        var awayScore: Int
        var homeScore: Int
        var clock: String
        var headline: String?
        var odds: [Double]?       // the home team's chance after each play, thinned
        var played: Double?       // how much of the game is done, 0...1
    }

    var updated: Date
    var tense: Bool
    var liveCount: Int
    var rows: [Row]
}

extension Watcher {
    /// Hands the widget the current board. Called after every score check.
    func shareWidget() {
        let hot = hotGames
        let games = hot.isEmpty ? Array(otherLive.prefix(6)) : Array(hot.prefix(6))
        let rows = games.map { game -> WidgetBoard.Row in
            let odds = details[game.id]?.winProbability.map(\.home) ?? []
            return WidgetBoard.Row(
                id: game.id,
                league: game.league.short,
                away: game.away.abbr,
                home: game.home.abbr,
                awayScore: game.away.score,
                homeScore: game.home.score,
                clock: game.statusText,
                headline: hot.isEmpty ? nil : game.buzz?.headline,
                odds: odds.count >= 2 ? Self.thin(odds, to: 40) : nil,
                played: Excitement.gameProgress(game))
        }
        LampWidget.share(WidgetBoard(updated: Date(), tense: !hot.isEmpty, liveCount: liveCount, rows: rows),
                         as: "board")
    }

    /// A row clicked on the widget: open where the game streams, as Watch does in the panel.
    func openFromWidget(_ id: String) {
        guard let game = games.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.open(game.state == .post ? (flagged[id]?.highlights?.url ?? game.gamePage) : game.watchLink.url)
    }

    static func thin(_ values: [Double], to limit: Int) -> [Double] {
        guard values.count > limit, limit > 1 else { return values }
        let step = Double(values.count - 1) / Double(limit - 1)
        return (0..<limit).map { values[min(values.count - 1, Int((Double($0) * step).rounded()))] }
    }
}
