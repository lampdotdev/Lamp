import WidgetKit
import SwiftUI
import AppIntents

/// Today's priorities on the desktop, with how many are done. The circles check a priority off through the
/// app (`TogglePriority`), which saves it and shares the list again.
@main
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: Provider()) { entry in
            TodayWidgetView(entry: entry)
                .lampWand()
                .containerBackground(for: .widget) { Color.paper }
        }
        .configurationDisplayName("Today")
        .description("Your priorities for today and how many are done.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let summary: TodaySummary?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), summary: TodaySummary(day: TodaySummary.key(for: Date()), items: [
            .init(id: "1", title: "Send the proposal", done: false),
            .init(id: "2", title: "A walk at lunch", done: true),
            .init(id: "3", title: "Water the plants", done: false),
        ]))
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        LampWidget.read(TodaySummary.self, from: "today") { summary in
            completion(summary.map { Entry(date: Date(), summary: $0) } ?? placeholder(in: context))
        }
    }

    /// Now, and again at midnight, when yesterday's list gives way to a prompt to plan the new day.
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        LampWidget.read(TodaySummary.self, from: "today") { summary in
            let now = Date()
            let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86_400))
            completion(Timeline(entries: [Entry(date: now, summary: summary), Entry(date: midnight, summary: summary)],
                                policy: .atEnd))
        }
    }
}

/// Asks the app to check off one priority, or uncheck it.
struct TogglePriority: AppIntent {
    static let title: LocalizedStringResource = "Check Off Priority"
    static let isDiscoverable = false

    @Parameter(title: "Priority")
    var id: String

    init() {}
    init(id: String) { self.id = id }

    func perform() async throws -> some IntentResult {
        await LampWidget.perform("toggle", id)
        return .result()
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        if let summary = entry.summary, summary.isFor(entry.date), !summary.items.isEmpty {
            switch family {
            case .systemSmall: SmallView(summary: summary, date: entry.date)
            default: MediumView(summary: summary, date: entry.date)
            }
        } else {
            EmptyDayView(date: entry.date, hasOpened: entry.summary != nil)
        }
    }
}

private struct DayHeading: View {
    let date: Date

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sun.max.fill").foregroundStyle(Color.sun)
            Text(date.formatted(.dateTime.weekday(.wide)))
                .font(.system(.subheadline, design: .serif).weight(.semibold))
        }
    }
}

/// The count, large, and the next thing to do.
private struct SmallView: View {
    let summary: TodaySummary
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            DayHeading(date: date)
            Spacer(minLength: 0)
            Text("\(summary.doneCount) of \(summary.items.count)")
                .font(.system(.largeTitle, design: .serif).weight(.semibold))
                .minimumScaleFactor(0.7)
            if let next = summary.items.first(where: { !$0.done }) {
                Text(next.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("All done")
                    .font(.callout)
                    .foregroundStyle(Color.sun)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Every priority, each with its own circle to check it off.
private struct MediumView: View {
    let summary: TodaySummary
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                DayHeading(date: date)
                Spacer()
                Text("\(summary.doneCount) of \(summary.items.count) done")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 14)   // the wand's corner
            }
            ForEach(summary.items, id: \.id) { item in
                HStack(spacing: 8) {
                    Button(intent: TogglePriority(id: item.id)) {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(item.done ? Color.sun : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    Text(item.title)
                        .font(.system(.body, design: .serif))
                        .strikethrough(item.done, color: .secondary)
                        .foregroundStyle(item.done ? .secondary : .primary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Before the app has shared anything, or once the day has turned over.
private struct EmptyDayView: View {
    let date: Date
    let hasOpened: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DayHeading(date: date)
            Spacer(minLength: 0)
            Text(hasOpened ? "A new day." : "Plan your day.")
                .font(.system(.title3, design: .serif).weight(.semibold))
            Text("Open Today to choose what matters.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// The app's paper and sun colors, written again here since the widget can't see the app's.
extension Color {
    static let paper = Color(light: 0xFAF6EE, dark: 0x1D1B18)
    static let sun = Color(light: 0xD9731A, dark: 0xF0953F)

    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}
