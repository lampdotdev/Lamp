import SwiftUI

/// The panel under the menu bar icon: the countdowns soonest first, and the editor in their place while one
/// is being added or changed (a sheet would open apart from a menu bar panel and get lost).
struct PanelView: View {
    @EnvironmentObject private var store: CountdownStore
    @State private var editing: Countdown?
    @State private var isNew = false
    @State private var showsPast = false

    static let width: CGFloat = 340
    /// Past this many rows the list scrolls, so the panel never grows taller than the screen allows.
    private let rowsBeforeScrolling = 6

    var body: some View {
        Group {
            if let countdown = editing {
                CountdownEditor(countdown: countdown, isNew: isNew) { editing = nil }
            } else {
                list
            }
        }
        .frame(width: Self.width)
    }

    private var list: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.countdowns.isEmpty {
                ContentUnavailableView {
                    Label("No Countdowns", systemImage: "calendar.badge.clock")
                } description: {
                    Text("Add a day you're looking forward to.")
                } actions: {
                    Button("New Countdown", action: startNew)
                }
                .padding(.vertical, 24)
            } else if visibleRowCount > rowsBeforeScrolling {
                ScrollView { rows }.frame(height: 420)
            } else {
                rows
            }
            Divider()
            footer
        }
    }

    private var visibleRowCount: Int {
        store.upcoming.count + (showsPast ? store.past.count : 0)
    }

    private var header: some View {
        HStack {
            Text("Countdowns").font(.headline)
            Spacer()
            Button(action: startNew) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("n")
            .help("New Countdown (⌘N)")
            .accessibilityLabel("New Countdown")
            LampPanelWand()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var rows: some View {
        VStack(spacing: 2) {
            ForEach(store.upcoming) { countdown in
                CountdownRow(countdown: countdown, today: store.today) { edit(countdown) }
            }
            if !store.past.isEmpty {
                DisclosureGroup(isExpanded: $showsPast) {
                    ForEach(store.past) { countdown in
                        CountdownRow(countdown: countdown, today: store.today) { edit(countdown) }
                            .opacity(0.6)
                    }
                } label: {
                    Text("Past").font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
            }
        }
        .padding(6)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if store.hasExamples {
                Button("Clear Examples") { store.clearExamples() }
                    .buttonStyle(.link)
                    .font(.callout)
                    .help("Remove the sample countdowns, keeping your own")
            }
            Spacer()
            Button {
                LampMenuBar.openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(",")
            .help("Settings")
            .accessibilityLabel("Settings")
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("q")
            .help("Quit Countdowns")
            .accessibilityLabel("Quit Countdowns")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func startNew() {
        let inAMonth = Calendar.current.date(byAdding: .month, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        editing = Countdown(name: "", date: inAMonth, symbol: "star.fill", color: .blue)
        isNew = true
    }

    private func edit(_ countdown: Countdown) {
        editing = countdown
        isNew = false
    }
}

/// One countdown in the list: its symbol on its color, its name and day, and the days left, large.
struct CountdownRow: View {
    let countdown: Countdown
    let today: Date
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                SymbolBadge(symbol: countdown.symbol, color: countdown.color.color, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(countdown.name).font(.body.weight(.medium)).lineLimit(1)
                    Text(dayLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                days
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Color.primary.opacity(0.07) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            // Delete lives in the editor, where it asks first.
            Button("Edit…", action: open)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(countdown.name), \(countdown.daysText(from: today))")
        .accessibilityHint("Edit")
        .accessibilityAddTraits(.isButton)
    }

    /// The day it falls on, and "every year" for a yearly one.
    private var dayLine: String {
        let day = countdown.nextDay(from: today) ?? countdown.date
        let text = day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
        return countdown.repeatsYearly ? "\(text) · every year" : text
    }

    @ViewBuilder private var days: some View {
        switch countdown.daysLeft(from: today) {
        case 0?:
            Text("Today!")
                .font(.title3.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(countdown.color.color)
        case let left?:
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(left)").font(.title2.weight(.bold)).fontDesign(.rounded).monospacedDigit()
                Text(left == 1 ? "day" : "days").font(.caption).foregroundStyle(.secondary)
            }
        case nil:
            Text("Done").font(.callout).foregroundStyle(.secondary)
        }
    }
}

/// A symbol in white on a circle of the countdown's color, as in the widget.
struct SymbolBadge: View {
    let symbol: String
    let color: Color
    let size: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(color.gradient))
            .accessibilityHidden(true)
    }
}
