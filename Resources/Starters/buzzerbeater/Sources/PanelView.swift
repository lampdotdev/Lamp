import SwiftUI

struct PanelView: View {
    @EnvironmentObject var watcher: Watcher
    @AppStorage("showAlsoLive") private var showAlsoLive = false
    @State private var contentHeight: CGFloat = 200
    @State private var showAllUpcoming = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if watcher.hotGames.isEmpty {
                        quiet
                    } else {
                        ForEach(watcher.hotGames) { game in
                            HotGameCard(game: game)
                        }
                    }
                    if watcher.liveCount == 0 && !watcher.comingUp.isEmpty {
                        let shown = showAllUpcoming ? watcher.upcoming : watcher.comingUp
                        HStack {
                            Text("Coming up")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if watcher.upcoming.count > watcher.comingUp.count {
                                Button(showAllUpcoming ? "Show fewer" : "See all \(watcher.upcoming.count)") {
                                    withAnimation(.snappy) { showAllUpcoming.toggle() }
                                }
                                .buttonStyle(.link)
                                .font(.caption)
                            }
                        }
                        .padding(.top, 4)
                        VStack(spacing: 0) {
                            ForEach(shown) { game in
                                UpcomingRow(game: game)
                                if game.id != shown.last?.id { Divider() }
                            }
                        }
                    }
                    if !watcher.endedFlagged.isEmpty {
                        Text("Just ended")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        ForEach(watcher.endedFlagged) { game in
                            HotGameCard(game: game)
                        }
                    }
                    if !watcher.otherLive.isEmpty {
                        Button {
                            withAnimation(.snappy) { showAlsoLive.toggle() }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .rotationEffect(.degrees(showAlsoLive ? 90 : 0))
                                Text("Also live · \(watcher.otherLive.count)")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                            }
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                        if showAlsoLive {
                            VStack(spacing: 0) {
                                ForEach(watcher.otherLive) { game in
                                    LiveRow(game: game)
                                    if game.id != watcher.otherLive.last?.id { Divider() }
                                }
                            }
                        }
                    }
                }
                .padding(12)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ContentHeight.self, value: proxy.size.height)
                })
            }
            .frame(height: min(max(contentHeight, 80), 520))
            .onPreferenceChange(ContentHeight.self) { contentHeight = $0 }
            Divider()
            footer
        }
        .frame(width: 380)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Buzzer Beater").font(.headline)
                Group {
                    if watcher.isLoading && watcher.lastUpdated == nil {
                        Text("Checking scores…")
                    } else if let updated = watcher.lastUpdated {
                        Text("Updated \(updated, style: .relative) ago")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if watcher.isLoading {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await watcher.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Check scores now")
            .accessibilityLabel("Check scores now")
            .disabled(watcher.isLoading)
            LampPanelWand()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var quiet: some View {
        VStack(spacing: 6) {
            Image(systemName: "sportscourt")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(watcher.liveCount == 0 ? "No games on right now" : "Nothing close yet")
                .font(.headline)
            Text(watcher.liveCount == 0
                 ? (watcher.comingUp.isEmpty ? "You'll get a heads-up when something's worth watching."
                    : "Here's what's next. You'll get a heads-up if one gets good.")
                 : "\(watcher.liveCount) live, none of them tense. You'll hear when one gets good.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let error = watcher.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var footer: some View {
        HStack {
            Button("Settings…") { LampMenuBar.openSettings() }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct ContentHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct HotGameCard: View {
    let game: Game

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: ended ? "flag.checkered" : (game.buzz?.symbol ?? "flame.fill"))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(ended ? Color.secondary : Color.orange)
                Text(ended ? "Final\(game.statusText.contains("OT") ? " in overtime" : "")" : (game.buzz?.headline ?? ""))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            if !ended, let play = detail?.keyPlay {
                Label {
                    Text(play).lineLimit(1).truncationMode(.tail)
                } icon: {
                    Image(systemName: "bolt.fill").foregroundStyle(Color.orange)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(play)
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(spacing: 4) {
                    TeamLine(team: game.away, leading: game.away.score > game.home.score)
                    TeamLine(team: game.home, leading: game.home.score > game.away.score)
                }
                VStack(alignment: .trailing, spacing: 2) {
                    Text(game.statusText)
                        .font(.caption.weight(.semibold).monospacedDigit())
                    Text(game.league.short)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 74, alignment: .trailing)
            }
            if !ended, let points = detail?.winProbability, points.count >= 2 {
                Button {
                    NSWorkspace.shared.open(game.gamePage)
                } label: {
                    CardOddsChart(away: game.away, home: game.home, points: points.map(\.home),
                                  played: game.state == .post ? 1 : Excitement.gameProgress(game))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open the game on ESPN")
            }
            if !ended, let more = game.buzz?.details, !more.isEmpty {
                Text(more)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if ended {
                    HighlightsButton(clip: Watcher.shared.flagged[game.id]?.highlights ?? detail?.highlights)
                } else {
                    WatchButton(game: game)
                }
                Spacer()
                if !game.networks.isEmpty {
                    Text(game.networks.prefix(2).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(10)
        .background((ended ? Color.secondary : Color.orange).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder((ended ? Color.secondary : Color.orange).opacity(0.25)))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            // The card opens the game's page on ESPN; its buttons still do their own thing.
            NSWorkspace.shared.open(game.gamePage)
        }
        .help("Open the game on ESPN")
    }

    private var ended: Bool { game.state == .post }
    private var detail: GameDetail? { Watcher.shared.details[game.id] }
}

/// The win odds so far, drawn as ESPN does: the away team on top, the home team below,
/// with the even line dashed across the whole game and the latest reading dotted.
private struct CardOddsChart: View {
    let away: Team
    let home: Team
    let points: [Double]
    let played: Double

    var body: some View {
        let now = points.last ?? 0.5
        let homeAhead = now >= 0.5
        let pct = Int((max(now, 1 - now) * 100).rounded())
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(away.abbr)
                Spacer(minLength: 0)
                Text(home.abbr)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(width: 34, height: 30, alignment: .leading)

            OddsLine(points: points, played: played, limit: 160, lineWidth: 1.5, dot: true)
                .frame(height: 30)

            Text("\((homeAhead ? home : away).abbr) \(pct)%")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Win chance so far: \((homeAhead ? home : away).name) now \(pct) percent")
    }
}

/// The win odds line itself. The game runs left to right across the full width, so the line
/// only reaches as far as the game has: halfway at halftime.
private struct OddsLine: View {
    let points: [Double]
    let played: Double
    var limit = 60
    var lineWidth: CGFloat = 1.25
    var dot = false

    var body: some View {
        let shown = Self.thinned(points, to: limit)
        let reach = CGFloat(min(1, max(0.02, played)))
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            let x = { (i: Int) in shown.count > 1 ? w * reach * CGFloat(i) / CGFloat(shown.count - 1) : w * reach }
            let y = { (v: Double) in h * CGFloat(v) }
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h / 2))
                    p.addLine(to: CGPoint(x: w, y: h / 2))
                }
                .stroke(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 0.75, dash: [2, 2]))
                Path { p in
                    for (i, v) in shown.enumerated() {
                        let pt = CGPoint(x: x(i), y: y(v))
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
                .stroke(Color.primary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                if dot {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 5, height: 5)
                        .position(x: x(shown.count - 1), y: y(shown.last ?? 0.5))
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Every point when there are few, else an even spread that always keeps the latest.
    static func thinned(_ values: [Double], to limit: Int) -> [Double] {
        guard values.count > limit, limit > 1 else { return values }
        let step = Double(values.count - 1) / Double(limit - 1)
        return (0..<limit).map { values[min(values.count - 1, Int((Double($0) * step).rounded()))] }
    }
}

/// The chance each side wins, as one thin bar: away on the left, home on the right.
private struct WinBar: View {
    let away: Team
    let home: Team
    let homeChance: Double

    var body: some View {
        let awayPct = Int(((1 - homeChance) * 100).rounded())
        HStack(spacing: 6) {
            Text("\(away.abbr) \(awayPct)%")
                .frame(width: 64, alignment: .leading)
            GeometryReader { proxy in
                HStack(spacing: 1) {
                    Capsule().fill(Color.orange)
                        .frame(width: max(2, proxy.size.width * (1 - homeChance)))
                    Capsule().fill(Color.secondary.opacity(0.35))
                }
            }
            .frame(height: 5)
            Text("\(100 - awayPct)% \(home.abbr)")
                .frame(width: 64, alignment: .trailing)
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Win chance: \(away.name) \(awayPct) percent, \(home.name) \(100 - awayPct) percent")
    }
}

/// Opens the full game highlights once ESPN posts them.
private struct HighlightsButton: View {
    let clip: Clip?

    var body: some View {
        if let clip {
            Button {
                NSWorkspace.shared.open(clip.url)
            } label: {
                Label("Highlights", systemImage: "play.rectangle.fill")
            }
            .buttonStyle(QuietCapsuleStyle())
            .help(clip.title)
        } else {
            Label("Highlights soon", systemImage: "clock")
                .font(.callout)
                .foregroundStyle(.secondary)
                .help("You'll get a notification when the highlights are up.")
        }
    }
}

struct WatchButton: View {
    let game: Game

    var body: some View {
        let watch = game.watchLink
        Button {
            NSWorkspace.shared.open(watch.url)
        } label: {
            Label(watch.label, systemImage: watch.isAvailable ? "play.tv.fill" : "tv.slash")
        }
        .buttonStyle(WatchStyle(available: watch.isAvailable))
        .help("Open \(watch.label.replacingOccurrences(of: "Watch on ", with: ""))")
    }
}

private struct WatchStyle: ButtonStyle {
    var available = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background((available ? Color.orange : Color.gray).opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
    }
}

private struct TeamLine: View {
    let team: Team
    let leading: Bool

    var body: some View {
        HStack(spacing: 8) {
            TeamLogo(url: team.logo)
            if let rank = team.rank {
                Text("\(rank)").font(.caption2).foregroundStyle(.secondary)
            }
            Text(team.name)
                .font(.callout.weight(leading ? .semibold : .regular))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(team.score)")
                .font(.title3.weight(leading ? .bold : .regular).monospacedDigit())
                .foregroundStyle(leading ? .primary : .secondary)
        }
    }
}

private struct TeamLogo: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Circle().fill(.quaternary)
        }
        .frame(width: 20, height: 20)
    }
}

private struct LiveRow: View {
    let game: Game

    var body: some View {
        HStack(spacing: 8) {
            Text(game.league.short)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .frame(width: 44, alignment: .leading)
            Text("\(game.away.abbr) \(game.away.score) – \(game.home.score) \(game.home.abbr)")
                .font(.callout.monospacedDigit())
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                if let points = Watcher.shared.details[game.id]?.winProbability, points.count >= 2 {
                    Button {
                        NSWorkspace.shared.open(game.gamePage)
                    } label: {
                        OddsLine(points: points.map(\.home), played: Excitement.gameProgress(game))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("\(Self.chanceText(game, points.last?.home ?? 0.5)). Click for the game on ESPN.")
                    .accessibilityLabel("Open \(game.title) on ESPN")
                } else {
                    Color.clear
                }
            }
            .frame(width: 64, height: 16)
            Text(game.statusText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 84, alignment: .trailing)
            Button {
                NSWorkspace.shared.open(game.watchLink.url)
            } label: {
                Image(systemName: "play.tv")
            }
            .buttonStyle(.borderless)
            .help(game.watchLink.label)
            .accessibilityLabel(game.watchLink.label)
        }
        .padding(.vertical, 5)
    }

    static func chanceText(_ game: Game, _ home: Double) -> String {
        let team = home >= 0.5 ? game.home : game.away
        return "\(team.name) \(Int((max(home, 1 - home) * 100).rounded()))% to win"
    }
}

/// A neutral capsule for buttons that shouldn't compete with Watch.
private struct QuietCapsuleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(configuration.isPressed ? 0.35 : 0.2), in: Capsule())
    }
}

/// A game that hasn't started: when, who, and where it's on. Clicking opens its ESPN page.
private struct UpcomingRow: View {
    let game: Game

    var body: some View {
        HStack(spacing: 8) {
            Text(game.league.short)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(game.away.name) at \(game.home.name)")
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 1) {
                Text(game.startText)
                    .font(.caption.monospacedDigit())
                if let network = game.networks.first {
                    Text(network)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture { NSWorkspace.shared.open(game.gamePage) }
        .help("\(game.title): open on ESPN")
    }
}
