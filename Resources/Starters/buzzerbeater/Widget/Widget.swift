import WidgetKit
import SwiftUI
import AppIntents

// MARK: - What the app shares (declared the same way in the app)

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
        var odds: [Double]?
        var played: Double?
    }

    var updated: Date
    var tense: Bool
    var liveCount: Int
    var rows: [Row]
}

// MARK: - Timeline

struct BoardEntry: TimelineEntry {
    let date: Date
    let board: WidgetBoard?
}

struct BoardProvider: TimelineProvider {
    func placeholder(in context: Context) -> BoardEntry {
        BoardEntry(date: Date(), board: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (BoardEntry) -> Void) {
        if context.isPreview {
            completion(BoardEntry(date: Date(), board: .sample))
            return
        }
        LampWidget.read(WidgetBoard.self, from: "board") { board in
            completion(BoardEntry(date: Date(), board: board))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BoardEntry>) -> Void) {
        LampWidget.read(WidgetBoard.self, from: "board") { board in
            // The app redraws the widget after every score check; this is only a fallback.
            completion(Timeline(entries: [BoardEntry(date: Date(), board: board)],
                                policy: .after(Date().addingTimeInterval(5 * 60))))
        }
    }
}

// MARK: - Clicking a row

struct OpenGameIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Game"
    static let openAppWhenRun = false

    @Parameter(title: "Game") var gameID: String

    init() {}
    init(gameID: String) { self.gameID = gameID }

    func perform() async throws -> some IntentResult {
        await LampWidget.perform("open", gameID)
        return .result()
    }
}

// MARK: - Views

struct BoardView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BoardEntry

    var body: some View {
        Group {
            if let board = entry.board {
                content(board)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    header("Buzzer Beater")
                    Spacer()
                    Text("Open Buzzer Beater to see tonight's games.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .containerBackground(for: .widget) { Color(nsColor: .windowBackgroundColor) }
        .lampWand()
    }

    private var maxRows: Int {
        switch family {
        case .systemSmall: 3
        case .systemLarge: 7
        default: 4
        }
    }

    @ViewBuilder
    private func content(_ board: WidgetBoard) -> some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 7 : 5) {
            if board.tense {
                header("Worth watching")
            } else if board.rows.isEmpty {
                header("No games on right now")
            } else {
                header(family == .systemSmall ? "Nothing tense" : "Nothing tense right now · \(board.liveCount) live")
            }
            ForEach(board.rows.prefix(maxRows), id: \.self) { row in
                Button(intent: OpenGameIntent(gameID: row.id)) {
                    if family == .systemSmall {
                        SmallRow(row: row)
                    } else {
                        BoardRow(row: row, showHeadline: family == .systemLarge && board.tense)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            if family == .systemLarge {
                Text("Updated \(board.updated, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(_ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: entry.board?.tense == true ? "flame.fill" : "sportscourt")
                .foregroundStyle(entry.board?.tense == true ? Color.orange : Color.secondary)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.trailing, 28)   // the top right corner is the wand's
    }
}

private struct BoardRow: View {
    let row: WidgetBoard.Row
    let showHeadline: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(row.league)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: 40, alignment: .leading)
                ScoreText(row: row)
                    .font(.callout.monospacedDigit())
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    if let odds = row.odds, odds.count >= 2 {
                        OddsLine(points: odds, played: row.played ?? 1)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 50, height: 14)
                Text(row.clock)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 74, alignment: .trailing)
            }
            if showHeadline, let headline = row.headline {
                Text(headline)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .padding(.leading, 48)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct SmallRow: View {
    let row: WidgetBoard.Row

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ScoreText(row: row)
                .font(.caption.monospacedDigit().weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(row.clock)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// "OKC 65 – 44 SA", with the leading side in bold.
private struct ScoreText: View {
    let row: WidgetBoard.Row

    var body: some View {
        let awayAhead = row.awayScore > row.homeScore
        let homeAhead = row.homeScore > row.awayScore
        HStack(spacing: 4) {
            Text("\(row.away) \(row.awayScore)").fontWeight(awayAhead ? .bold : .regular)
            Text("–").foregroundStyle(.secondary)
            Text("\(row.homeScore) \(row.home)").fontWeight(homeAhead ? .bold : .regular)
        }
    }
}

/// The panel's win odds line: away team on top as on ESPN, the even line dashed across the whole game,
/// and the line reaching only as far as the game has been played.
private struct OddsLine: View {
    let points: [Double]
    let played: Double

    var body: some View {
        let reach = CGFloat(min(1, max(0.02, played)))
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            let x = { (i: Int) in points.count > 1 ? w * reach * CGFloat(i) / CGFloat(points.count - 1) : w * reach }
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h / 2))
                    p.addLine(to: CGPoint(x: w, y: h / 2))
                }
                .stroke(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 0.75, dash: [2, 2]))
                Path { p in
                    for (i, v) in points.enumerated() {
                        let pt = CGPoint(x: x(i), y: h * CGFloat(v))
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
                .stroke(Color.primary, style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: - Widget

@main
struct BuzzerbeaterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Scoreboard", provider: BoardProvider()) { entry in
            BoardView(entry: entry)
        }
        .configurationDisplayName("Games worth watching")
        .description("Tense games right now, tensest first. Click one to watch.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

extension WidgetBoard {
    static let sample = WidgetBoard(updated: Date(), tense: true, liveCount: 5, rows: [
        Row(id: "1", league: "NBA", away: "OKC", home: "SA", awayScore: 101, homeScore: 99, clock: "1:12 - 4th",
            headline: "Coin flip: 52–48, 1:12 left",
            odds: [0.5, 0.45, 0.4, 0.42, 0.35, 0.3, 0.38, 0.45, 0.5, 0.48], played: 0.97),
        Row(id: "2", league: "NCAAF", away: "USA", home: "MRSH", awayScore: 20, homeScore: 23, clock: "3:40 - 4th",
            headline: "Big swing: South Alabama from 20% to 55% to win",
            odds: [0.5, 0.6, 0.7, 0.75, 0.8, 0.6, 0.45], played: 0.93),
        Row(id: "3", league: "NHL", away: "CAR", home: "VAN", awayScore: 2, homeScore: 2, clock: "OT",
            headline: "Overtime! Tied", odds: nil, played: 1),
    ])
}
