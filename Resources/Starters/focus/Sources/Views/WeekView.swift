import Charts
import SwiftUI

/// The last seven days: sessions per day as bars, and what the time went to.
struct WeekView: View {
    @ObservedObject var timer: FocusTimer

    var body: some View {
        let week = WeekSummary(sessions: timer.sessions)
        if week.sessionCount == 0 {
            ContentUnavailableView("No Sessions This Week", systemImage: "timer",
                                   description: Text("Finished focus sessions show up here."))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(week)
                    chart(week)
                    topics(week)
                    if timer.hasExamples { examplesNote }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
        }
    }

    private func header(_ week: WeekSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(week.totalMinutes.focusDuration)
                .font(.system(.title, design: .rounded, weight: .semibold))
            Text(week.sessionCount == 1 ? "1 session in the last 7 days" : "\(week.sessionCount) sessions in the last 7 days")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func chart(_ week: WeekSummary) -> some View {
        Chart(week.days) { day in
            BarMark(x: .value("Day", day.date, unit: .day), y: .value("Sessions", day.count))
                .foregroundStyle(Calendar.current.isDateInToday(day.date) ? Color.focus : Color.focus.opacity(0.45))
                .cornerRadius(4)
                .annotation(position: .top, spacing: 2) {
                    if day.count > 0 {
                        Text("\(day.count)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
            }
        }
        .chartYAxis(.hidden)
        .frame(height: 110)
        .accessibilityLabel("Sessions per day this week")
    }

    private func topics(_ week: WeekSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What it went to")
                .font(.headline)
            ForEach(week.topics.prefix(6), id: \.intent) { topic in
                HStack {
                    Circle().fill(Color.focus.opacity(0.8)).frame(width: 6, height: 6)
                    Text(topic.intent.isEmpty ? "Unnamed" : topic.intent)
                        .foregroundStyle(topic.intent.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer()
                    Text(topic.minutes.focusDuration)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
    }

    private var examplesNote: some View {
        HStack {
            Text("Some of these are examples.")
            Spacer()
            Button("Clear Examples") { withAnimation { timer.clearExamples() } }
                .buttonStyle(.link)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }
}

/// The numbers the week page shows, worked out from the finished sessions.
struct WeekSummary {
    struct Day: Identifiable {
        var date: Date
        var count: Int
        var id: Date { date }
    }

    struct Topic {
        var intent: String
        var minutes: Int
    }

    let days: [Day]
    let topics: [Topic]
    let sessionCount: Int
    let totalMinutes: Int

    init(sessions: [FocusSession], now: Date = Date()) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let first = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let recent = sessions.filter { $0.end >= first }

        days = (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: first) else { return nil }
            return Day(date: date, count: recent.filter { calendar.isDate($0.end, inSameDayAs: date) }.count)
        }
        // Grouped regardless of capitals, under the spelling used most recently.
        var minutes: [String: Int] = [:]
        var spelling: [String: String] = [:]
        for session in recent {
            let key = session.intent.lowercased()
            minutes[key, default: 0] += session.minutes
            if spelling[key] == nil { spelling[key] = session.intent }
        }
        topics = minutes.map { Topic(intent: spelling[$0.key] ?? $0.key, minutes: $0.value) }
            .sorted { $0.minutes > $1.minutes }
        sessionCount = recent.count
        totalMinutes = recent.reduce(0) { $0 + $1.minutes }
    }
}

extension Int {
    /// Minutes as "2 h 5 min", "45 min".
    var focusDuration: String {
        let hours = self / 60, minutes = self % 60
        if hours == 0 { return "\(minutes) min" }
        return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) min"
    }
}
