import Foundation

extension Watcher {
    /// When nothing's live, looks up today's and tomorrow's schedules (ESPN's default scoreboard can still
    /// be showing last night's games), at most every 15 minutes.
    func refreshUpcoming() async {
        guard liveCount == 0 else { return }
        guard Date().timeIntervalSince(upcomingFetched ?? .distantPast) > 15 * 60 else { return }
        upcomingFetched = Date()

        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        let today = f.string(from: Date())
        let tomorrow = f.string(from: Date().addingTimeInterval(86_400))
        let range = "\(today)-\(tomorrow)"

        var found: [Game] = []
        await withTaskGroup(of: [Game].self) { group in
            for league in settings.enabledLeagues {
                group.addTask { (try? await ScoreFeed.games(for: league, dates: range)) ?? [] }
            }
            for await games in group { found += games }
        }
        let horizon = Date().addingTimeInterval(36 * 3600)
        var seen = Set<String>()
        upcoming = (found + games)
            .filter { $0.state == .pre && $0.start > Date().addingTimeInterval(-15 * 60) && $0.start < horizon }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.start < $1.start }
    }

    /// The few upcoming games worth listing, best first by `previewScore`, shown in start order.
    var comingUp: [Game] {
        let ranked = upcoming.sorted { $0.previewScore > $1.previewScore }
        let good = ranked.filter { $0.previewScore >= 1.2 }
        let best = good.isEmpty ? Array(ranked.prefix(3)) : Array(good.prefix(5))
        return best.sorted { $0.start < $1.start }
    }

}

extension Game {
    /// How evenly matched the line says it is: 1 for a pick'em, 0 for a lopsided game; nil with no line.
    var closeness: Double? {
        guard let line else { return nil }
        switch league.sport {
        case .football, .basketball:
            return line.spread.map { max(0, 1 - $0 / 10) }
        default:
            return line.moneyline.map { max(0, 1 - (Double(abs($0)) - 100) / 150) }
        }
    }

    /// How good the two teams are, from their records: the average share of games won.
    var quality: Double? {
        func pct(_ record: String?) -> Double? {
            guard let parts = record?.split(separator: "-").compactMap({ Double($0) }), parts.count >= 2 else { return nil }
            let played = parts.reduce(0, +)
            return played > 0 ? parts[0] / played : nil
        }
        let both = [pct(away.record), pct(home.record)].compactMap { $0 }
        return both.count == 2 ? both.reduce(0, +) / 2 : nil
    }

    /// How good an upcoming game should be, without AI: a close line, two good teams, rankings, national TV.
    var previewScore: Double {
        var score = (closeness ?? 0.4) + (quality ?? 0.45)
        if away.rank != nil && home.rank != nil { score += 0.5 }
        else if (away.rank ?? 99) <= 10 || (home.rank ?? 99) <= 10 { score += 0.2 }
        let national = ["ABC", "NBC", "CBS", "FOX", "ESPN", "TNT", "Prime Video", "Peacock", "Paramount+", "Apple TV"]
        if networks.contains(where: { n in national.contains { n.hasPrefix($0) } }) { score += 0.2 }
        return score
    }

    /// "Today 8:15 PM", "Tomorrow 1:00 PM" or "Thu 8:15 PM".
    var startText: String {
        let cal = Calendar.current
        let time = start.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(start) { return "Today \(time)" }
        if cal.isDateInTomorrow(start) { return "Tomorrow \(time)" }
        return start.formatted(.dateTime.weekday(.abbreviated)) + " " + time
    }
}
