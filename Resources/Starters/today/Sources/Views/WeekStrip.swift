import SwiftUI

/// The last seven days at a glance: a dot for each priority (filled when done) and the day's weather. A click
/// on an earlier day shows what was on it.
struct WeekStrip: View {
    @EnvironmentObject private var model: TodayModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(model.recentDays) { day in
                DayCell(day: day, isToday: day.id == model.todayKey)
            }
        }
    }
}

private struct DayCell: View {
    let day: Day
    let isToday: Bool
    @State private var showsDetail = false

    var body: some View {
        Button { showsDetail = canOpen } label: {
            VStack(spacing: 5) {
                Text(isToday ? "Today" : day.date.formatted(.dateTime.weekday(.abbreviated)))
                    .font(.caption.weight(isToday ? .semibold : .regular))
                    .foregroundStyle(isToday ? Color.sun : Color.secondary)
                Text(day.date.formatted(.dateTime.day()))
                    .font(.planner(.title3, weight: .medium))
                DoneDots(day: day)
                Image(systemName: day.mood?.symbol ?? "circle.dotted")
                    .symbolRenderingMode(day.mood == nil ? .monochrome : .multicolor)
                    .foregroundStyle(day.mood == nil ? Color.secondary.opacity(0.4) : Color.primary)
                    .font(.callout)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isToday ? Color.sheet : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.sun.opacity(0.5))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(canOpen ? "See this day" : "")
        .popover(isPresented: $showsDetail, arrowEdge: .top) { DayDetail(day: day) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    /// Today is already on screen, and an empty day has nothing to show.
    private var canOpen: Bool { !isToday && !day.isBlank }

    private var accessibilityText: String {
        var parts = [day.date.formatted(date: .complete, time: .omitted)]
        if !day.written.isEmpty { parts.append("\(day.doneCount) of \(day.written.count) done") }
        if let mood = day.mood { parts.append(mood.label) }
        return parts.joined(separator: ", ")
    }
}

/// One dot per written priority, filled when done; a faint line when nothing was planned.
private struct DoneDots: View {
    let day: Day

    var body: some View {
        HStack(spacing: 3) {
            if day.written.isEmpty {
                Capsule().fill(.quaternary).frame(width: 14, height: 2)
            } else {
                ForEach(day.written) { priority in
                    Circle()
                        .fill(priority.done ? Color.sun : Color.clear)
                        .overlay(Circle().strokeBorder(priority.done ? Color.sun : Color.secondary.opacity(0.5), lineWidth: 1))
                        .frame(width: 6, height: 6)
                }
            }
        }
        .frame(height: 6)
    }
}

/// What an earlier day held, to look back at without changing it.
private struct DayDetail: View {
    let day: Day

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(day.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.planner(.headline, weight: .semibold))
                Spacer()
                if let mood = day.mood {
                    Label(mood.label, systemImage: mood.symbol)
                        .symbolRenderingMode(.multicolor)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(day.written) { priority in
                Label {
                    Text(priority.title).strikethrough(priority.done, color: .secondary)
                } icon: {
                    Image(systemName: priority.done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(priority.done ? Color.sun : Color.secondary)
                }
            }
            if !day.notes.isEmpty {
                Divider()
                Text(day.notes)
                    .font(.planner(.callout))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}
