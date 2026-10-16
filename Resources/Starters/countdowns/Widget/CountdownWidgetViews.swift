import WidgetKit
import SwiftUI

/// Small shows the next countdown on its own color, medium the next three as tiles, large up to six as rows.
/// Margins are drawn here (the widget turns the system's off) so the small size's color reaches the edges.
struct CountdownWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CountdownEntry

    var body: some View {
        let upcoming = entry.upcoming
        Group {
            if entry.countdowns == nil {
                Message(symbol: "calendar.badge.clock", text: "Open Countdowns to see your days here.")
            } else if upcoming.isEmpty {
                Message(symbol: "calendar.badge.plus", text: "Nothing to count down to. Add one from the menu bar.")
            } else {
                switch family {
                case .systemSmall: SmallView(item: upcoming[0])
                case .systemLarge: LargeView(items: Array(upcoming.prefix(6)), today: entry.date)
                default: MediumView(items: Array(upcoming.prefix(3)))
                }
            }
        }
        .containerBackground(for: .widget) {
            if family == .systemSmall, let first = upcoming.first {
                colorGradient(first.countdown.tint)
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        }
    }
}

/// The countdown's color as a soft diagonal gradient, darker at the bottom so white text stays readable.
private func colorGradient(_ tint: Color) -> LinearGradient {
    LinearGradient(colors: [tint, tint.darkened(by: 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

private extension Color {
    /// Mixed toward black. `Color.mix` is macOS 15; before that, a little transparency over the dark
    /// background does nearly the same.
    func darkened(by amount: Double) -> Color {
        if #available(macOS 15.0, *) {
            return mix(with: .black, by: amount, in: .perceptual)
        }
        return opacity(1 - amount * 0.5)
    }
}

/// The big number: "Today!" on the day, else the days with "day" or "days" under it.
private struct DaysNumber: View {
    let days: Int
    let size: CGFloat

    var body: some View {
        if days == 0 {
            Text("Today!")
                .font(.system(size: size * 0.6, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        } else {
            VStack(alignment: .leading, spacing: -2) {
                Text("\(days)")
                    .font(.system(size: size, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                Text(days == 1 ? "day" : "days")
                    .font(.system(size: max(11, size * 0.22), weight: .semibold, design: .rounded))
                    .opacity(0.85)
            }
        }
    }
}

private struct SmallView: View {
    let item: (countdown: WidgetCountdown, days: Int)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: item.countdown.symbol)
                .font(.system(size: 22, weight: .semibold))
            Spacer(minLength: 4)
            DaysNumber(days: item.days, size: 56)
            Text(item.countdown.name)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .lineLimit(2)
                .padding(.top, 2)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(item))
    }
}

private struct MediumView: View {
    let items: [(countdown: WidgetCountdown, days: Int)]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items, id: \.countdown.id) { item in
                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: item.countdown.symbol)
                        .font(.system(size: 17, weight: .semibold))
                    Spacer(minLength: 2)
                    DaysNumber(days: item.days, size: 40)
                    Text(item.countdown.name)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(12)
                .background(colorGradient(item.countdown.tint), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken(item))
            }
        }
        .padding(10)
    }
}

private struct LargeView: View {
    let items: [(countdown: WidgetCountdown, days: Int)]
    let today: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Countdowns")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            ForEach(Array(items.enumerated()), id: \.element.countdown.id) { index, item in
                if index > 0 { Divider() }
                HStack(spacing: 12) {
                    Image(systemName: item.countdown.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(colorGradient(item.countdown.tint), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.countdown.name)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .lineLimit(1)
                        Text(dayText(item))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 6)
                    if item.days == 0 {
                        Text("Today!")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(item.countdown.tint)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(item.days)")
                                .font(.system(size: 30, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(item.countdown.tint)
                            Text(item.days == 1 ? "day" : "days")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken(item))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
    }

    private func dayText(_ item: (countdown: WidgetCountdown, days: Int)) -> String {
        let day = item.countdown.nextDay(from: today) ?? item.countdown.date
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

/// A short line when there's nothing to count: before the app has run, or with no countdowns ahead.
private struct Message: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title).foregroundStyle(.tint)
            Text(text)
                .font(.system(.callout, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private func spoken(_ item: (countdown: WidgetCountdown, days: Int)) -> String {
    switch item.days {
    case 0: "\(item.countdown.name), today"
    case 1: "\(item.countdown.name), tomorrow"
    default: "\(item.countdown.name), in \(item.days) days"
    }
}
