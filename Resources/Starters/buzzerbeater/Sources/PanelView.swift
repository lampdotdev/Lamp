import SwiftUI

struct PanelView: View {
    @EnvironmentObject var watcher: Watcher
    @AppStorage("showAlsoLive") private var showAlsoLive = false
    @State private var contentHeight: CGFloat = 200
    @State private var showAllUpcoming = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(watcher.hotGames) { game in
                        HotGameCard(game: game)
                    }
                    if nothingToShow {
                        quiet
                    }
                    if watcher.liveCount == 0 && !watcher.comingUp.isEmpty {
                        let shown = showAllUpcoming ? watcher.upcoming : watcher.comingUp
                        SectionHeader(title: "Coming up") {
                            if watcher.upcoming.count > watcher.comingUp.count {
                                Button {
                                    withAnimation(.snappy) { showAllUpcoming.toggle() }
                                } label: {
                                    Image(systemName: showAllUpcoming ? "chevron.up" : "chevron.down")
                                        .font(.caption.weight(.semibold))
                                        .frame(width: 20, height: 16)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                                .help(showAllUpcoming ? "Show fewer" : "Show all \(watcher.upcoming.count)")
                                .accessibilityLabel(showAllUpcoming ? "Show fewer" : "Show all \(watcher.upcoming.count)")
                            }
                        }
                        ForEach(UpcomingDay.group(shown)) { day in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(day.title)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                ForEach(day.games) { game in
                                    UpcomingRow(game: game)
                                }
                            }
                        }
                    }
                    if !watcher.endedFlagged.isEmpty {
                        SectionHeader(title: "Just ended") { EmptyView() }
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
                                Text("Also live")
                                    .font(.caption.weight(.semibold))
                                    .textCase(.uppercase)
                                    .tracking(0.5)
                                Text("\(watcher.otherLive.count)")
                                    .font(.caption2.weight(.bold).monospacedDigit())
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(.quaternary, in: Capsule())
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

    private var nothingToShow: Bool {
        watcher.hotGames.isEmpty && watcher.otherLive.isEmpty && watcher.endedFlagged.isEmpty
            && (watcher.liveCount > 0 || watcher.comingUp.isEmpty)
    }

    /// Only when there's nothing at all to list.
    private var quiet: some View {
        VStack(spacing: 4) {
            Text(watcher.isLoading && watcher.lastUpdated == nil ? "Checking scores…" : "Nothing on for now")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let error = watcher.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var footer: some View {
        HStack {
            Button { LampMenuBar.openSettings() } label: { Image(systemName: "gearshape") }
                .help("Settings")
                .accessibilityLabel("Settings")
            Button {
                Task { await watcher.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Check scores now")
            .accessibilityLabel("Check scores now")
            .disabled(watcher.isLoading)
            Group {
                if watcher.isLoading {
                    ProgressView().controlSize(.mini)
                } else if let error = watcher.error {
                    // Before the time of the last check: the games listed may be from then, and are no longer updating.
                    Group {
                        if let updated = watcher.lastUpdated {
                            Text("Offline · \(updated, style: .relative) ago")
                        } else {
                            Text("Offline")
                        }
                    }
                    .monospacedDigit()
                    .foregroundStyle(.red)
                    .help(error)
                } else if let updated = watcher.lastUpdated {
                    Text("\(updated, style: .relative) ago")
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
            LampPanelWand()
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .help("Quit Buzzer Beater")
                .accessibilityLabel("Quit")
        }
        .buttonStyle(.borderless)
        .font(.body)
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
                    LeagueBadge(league: game.league)
                        .frame(width: 42, alignment: .trailing)
                }
                .frame(width: 74, alignment: .trailing)
            }
            if !ended, let chance = detail?.homeChance {
                WinBar(game: game, homeChance: chance)
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
                HStack(spacing: 8) {
                    ForEach(game.networks.prefix(2), id: \.self) { network in
                        NetworkBadge(name: network, size: 15)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
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
            TeamLogo(team: team, size: 22)
            if let rank = team.rank {
                Text("\(rank)").font(.caption2.weight(.semibold).monospacedDigit()).foregroundStyle(.tertiary)
            }
            Text(team.name)
                .font(.callout.weight(leading ? .semibold : .regular))
                .foregroundStyle(leading ? .primary : .secondary)
                .lineLimit(1)
            if let record = team.record {
                Text(record).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("\(team.score)")
                .font(.system(.title2, design: .rounded).weight(leading ? .bold : .medium).monospacedDigit())
                .foregroundStyle(leading ? .primary : .secondary)
        }
    }
}

/// Each side's chance to win as one bar in the teams' colors, away on the left.
private struct WinBar: View {
    let game: Game
    let homeChance: Double

    var body: some View {
        let away = 1 - homeChance
        VStack(spacing: 3) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    Capsule().fill(game.away.tint.gradient).frame(width: max(3, proxy.size.width * away - 1))
                    Capsule().fill(game.home.tint.gradient)
                }
            }
            .frame(height: 5)
            HStack {
                Text("\(game.away.abbr) \(Int((away * 100).rounded()))%")
                Spacer()
                Text("Win chance").foregroundStyle(.tertiary)
                Spacer()
                Text("\(Int((homeChance * 100).rounded()))% \(game.home.abbr)")
            }
            .font(.caption2.weight(.medium).monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Win chance: \(game.away.name) \(Int((away * 100).rounded())) percent, \(game.home.name) \(Int((homeChance * 100).rounded())) percent")
    }
}

/// The league as a small tag, the same width in every row so the columns line up. `stretch` lets it grow to
/// the width of what's stacked with it.
struct LeagueBadge: View {
    let league: League
    var stretch = false

    var body: some View {
        Text(league.short)
            .font(.system(size: 9, weight: .bold).width(.condensed))
            .tracking(0.4)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            .frame(minWidth: 32, maxWidth: stretch ? .infinity : nil)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 3))
            .frame(width: stretch ? nil : 42, alignment: .leading)
    }
}

/// How close a live game is to getting good, as three small bars.
private struct HeatBars: View {
    let score: Int

    var body: some View {
        let lit = score >= 45 ? 3 : score >= 30 ? 2 : score >= 15 ? 1 : 0
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(0..<3) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < lit ? Color.orange : Color.secondary.opacity(0.25))
                    .frame(width: 3, height: CGFloat(5 + i * 3))
            }
        }
        .frame(width: 14, height: 12, alignment: .bottom)
        .help("How tense it is")
        .accessibilityLabel("Tension \(lit) of 3")
    }
}

private struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Spacer()
            trailing()
        }
        .padding(.top, 6)
    }
}

/// A soft highlight under a row while the pointer is over it, instead of lines between rows.
private struct RowHover: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 6)
            .background(hovering ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, -6)
            .onHover { hovering = $0 }
    }
}

private struct LiveRow: View {
    let game: Game

    var body: some View {
        HStack(spacing: 8) {
            LeagueBadge(league: game.league)
            VStack(spacing: 2) {
                side(game.away, leading: game.away.score > game.home.score)
                side(game.home, leading: game.home.score > game.away.score)
            }
            .frame(maxWidth: .infinity)
            Text(game.statusText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .frame(width: 76, alignment: .trailing)
            HeatBars(score: game.buzz?.score ?? 0)
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
        .modifier(RowHover())
        .contentShape(Rectangle())
        .onTapGesture { NSWorkspace.shared.open(game.gamePage) }
    }

    private func side(_ team: Team, leading: Bool) -> some View {
        HStack(spacing: 6) {
            TeamLogo(team: team, size: 15)
            Text(team.abbr)
                .font(.callout.weight(leading ? .semibold : .regular).monospaced())
                .foregroundStyle(leading ? .primary : .secondary)
            Spacer(minLength: 2)
            Text("\(team.score)")
                .font(.callout.weight(leading ? .bold : .regular).monospacedDigit())
                .foregroundStyle(leading ? .primary : .secondary)
        }
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

/// Upcoming games under a heading for each day.
private struct UpcomingDay: Identifiable {
    let id: Date
    let games: [Game]

    var title: String {
        let cal = Calendar.current
        if cal.isDateInToday(id) { return "Today" }
        if cal.isDateInTomorrow(id) { return "Tomorrow · " + id.formatted(.dateTime.weekday(.wide)) }
        return id.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    static func group(_ games: [Game]) -> [UpcomingDay] {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: games) { cal.startOfDay(for: $0.start) }
        return byDay.keys.sorted().map { UpcomingDay(id: $0, games: byDay[$0]!.sorted { $0.start < $1.start }) }
    }
}

/// A game that hasn't started: when, who, and where it's on. Clicking opens its ESPN page.
private struct UpcomingRow: View {
    let game: Game

    var body: some View {
        HStack(spacing: 10) {
            Text(game.start.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 16, weight: .bold).width(.condensed).monospacedDigit())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(width: 62, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                side(game.away)
                side(game.home)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .center, spacing: 3) {
                LeagueBadge(league: game.league, stretch: true)
                if let network = game.networks.first {
                    NetworkBadge(name: network)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize()
            .frame(width: 76, alignment: .trailing)
        }
        .padding(.vertical, 5)
        .modifier(RowHover())
        .contentShape(Rectangle())
        .onTapGesture { NSWorkspace.shared.open(game.gamePage) }
        .help("\(game.title): open on ESPN")
    }

    private func side(_ team: Team) -> some View {
        HStack(spacing: 6) {
            TeamLogo(team: team, size: 16)
            if game.away.rank != nil || game.home.rank != nil {
                Text(team.rank.map { "\($0)" } ?? "")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 14, alignment: .trailing)
            }
            Text(team.name).font(.callout).lineLimit(1)
            if let record = team.record {
                Text(record).font(.caption2.monospacedDigit()).foregroundStyle(.primary).lineLimit(1)
            }
        }
    }
}
