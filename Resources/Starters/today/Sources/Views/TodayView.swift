import SwiftUI
import AppKit

/// The one window: the date, anything left from yesterday, today's priorities and mood beside the notes, and
/// the week underneath.
struct TodayView: View {
    @EnvironmentObject private var model: TodayModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DateHeader(date: model.today.date)

            if let offer = model.carryOverOffer {
                CarryOverBanner(offer: offer)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    PrioritiesSection()
                    MoodSection()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                NotesSection()
                    .frame(maxWidth: .infinity)
            }

            WeekStrip()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.paper)
        .animation(.spring(duration: 0.35), value: model.carryOverOffer == nil)
        .toolbar {
            if model.hasExamples {
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear Examples", systemImage: "sparkles") { model.clearExamples() }
                        .labelStyle(.titleAndIcon)
                        .help("Remove the sample days and keep everything you wrote")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            model.refreshDay()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshDay()
        }
    }
}

/// "Thursday" large, the date beside it, as at the top of a planner page.
private struct DateHeader: View {
    let date: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(date.formatted(.dateTime.weekday(.wide)))
                .font(.planner(.largeTitle, weight: .semibold))
            Text(date.formatted(.dateTime.day().month(.wide).year()))
                .font(.planner(.title3))
                .foregroundStyle(.secondary)
            Spacer()
            Image(systemName: "sun.max.fill")
                .font(.title2)
                .foregroundStyle(Color.sun)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "2 left from yesterday", with Carry Over to put them on today's list.
private struct CarryOverBanner: View {
    @EnvironmentObject private var model: TodayModel
    let offer: TodayModel.CarryOver

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.uturn.forward.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.sun)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(offer.priorities.count) left from \(offer.when)")
                    .font(.headline)
                Text(offer.priorities.map(\.title).joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Not Now") { model.dismissCarryOver() }
            Button("Carry Over") { model.carryOver() }
                .buttonStyle(.borderedProminent)
                .tint(Color.sun)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.sun.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
