import SwiftUI

/// One week of time entries, by day, with each client's totals for the week and the month above them.
struct WeekView: View {
    @EnvironmentObject private var model: HoursModel
    /// Weeks back from this one; kept so the window reopens on the same week.
    @SceneStorage("weeksBack") private var weeksBack = 0
    @State private var selection = Set<UUID>()
    @State private var confirmingDelete = false

    private var week: DateInterval {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .weekOfYear, value: -weeksBack, to: .now) ?? .now
        return calendar.week(containing: day)
    }

    var body: some View {
        Group {
            if model.clients.isEmpty {
                ContentUnavailableView {
                    Label("No Clients Yet", systemImage: "person.2")
                } description: {
                    Text("Add someone you work for, then start a timer from here or the menu bar.")
                } actions: {
                    Button("New Client…") { model.sheet = .newClient }
                }
            } else {
                list
            }
        }
        .navigationTitle(weeksBack == 0 ? "This Week" : "Week of " + week.start.formatted(.dateTime.day().month(.abbreviated)))
        .navigationSubtitle(weekRange)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { weeksBack += 1 } label: { Label("Previous Week", systemImage: "chevron.left") }
                    .help("Previous week")
                Button { weeksBack = max(0, weeksBack - 1) } label: { Label("Next Week", systemImage: "chevron.right") }
                    .help("Next week")
                    .disabled(weeksBack == 0)
            }
        }
        .confirmationDialog(selection.count == 1 ? "Delete this entry?" : "Delete \(selection.count) entries?",
                            isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                model.delete(selection)
                selection = []
            }
        }
    }

    private var list: some View {
        let days = byDay(model.entries(in: week))
        return List(selection: $selection) {
            Section {
                TotalsGrid(week: week)
            }
            if days.isEmpty {
                Text(weeksBack == 0 ? "Nothing tracked this week yet." : "Nothing tracked this week.")
                    .foregroundStyle(.secondary)
            }
            ForEach(days, id: \.day) { day in
                Section {
                    ForEach(day.entries) { entry in
                        EntryRow(entry: entry).tag(entry.id)
                    }
                } header: {
                    HStack {
                        Text(day.day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        Spacer()
                        Text(Format.duration(day.entries.reduce(0) { $0 + $1.duration() })).monospacedDigit()
                    }
                }
            }
            if model.hasExamples {
                Button("Clear Examples") { model.clearExamples() }
                    .buttonStyle(.link)
                    .font(.callout)
                    .help("Remove the sample clients and their time")
                    .selectionDisabled()
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if ids.count == 1, let id = ids.first, let entry = model.entries.first(where: { $0.id == id }) {
                Button("Edit Entry…") { model.sheet = .editEntry(entry) }
            }
            if !ids.isEmpty {
                Button("Delete", role: .destructive) { selection = ids; confirmingDelete = true }
            }
        } primaryAction: { ids in
            if let id = ids.first, let entry = model.entries.first(where: { $0.id == id }) {
                model.sheet = .editEntry(entry)
            }
        }
        .onDeleteCommand { if !selection.isEmpty { confirmingDelete = true } }
    }

    private var weekRange: String {
        let last = week.end.addingTimeInterval(-1)
        return "\(week.start.formatted(.dateTime.day().month(.abbreviated))) – \(last.formatted(.dateTime.day().month(.abbreviated).year()))"
    }

    private func byDay(_ entries: [TimeEntry]) -> [(day: Date, entries: [TimeEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.start) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }
}

/// One entry in the list: client, note, times and length. A running one counts up.
struct EntryRow: View {
    @EnvironmentObject private var model: HoursModel
    let entry: TimeEntry

    var body: some View {
        let client = model.client(entry.clientID)
        HStack(spacing: 10) {
            Circle().fill(client?.tint ?? .gray).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.note.isEmpty ? "No note" : entry.note)
                    .foregroundStyle(entry.note.isEmpty ? .secondary : .primary)
                Text(client?.name ?? "Deleted client").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(times).font(.callout).foregroundStyle(.secondary).monospacedDigit()
            Group {
                if entry.isRunning {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(Format.clock(entry.duration(now: context.date), withSeconds: true))
                            .foregroundStyle(client?.tint ?? .accentColor)
                    }
                } else {
                    Text(Format.duration(entry.duration()))
                }
            }
            .monospacedDigit()
            .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var times: String {
        let start = entry.start.formatted(date: .omitted, time: .shortened)
        guard let end = entry.end else { return "\(start) – now" }
        return "\(start) – \(end.formatted(date: .omitted, time: .shortened))"
    }
}

/// Each client's hours and earnings this week and this month, side by side.
struct TotalsGrid: View {
    @EnvironmentObject private var model: HoursModel
    let week: DateInterval

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let month = Calendar.current.month(containing: week.start)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                GridRow {
                    Text("Client")
                    Text("Week").gridColumnAlignment(.trailing)
                    Text(month.start.formatted(.dateTime.month(.wide))).gridColumnAlignment(.trailing)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                ForEach(model.clients) { client in
                    GridRow {
                        HStack(spacing: 6) {
                            Circle().fill(client.tint).frame(width: 8, height: 8)
                            Text(client.name).lineLimit(1)
                        }
                        total(client, week, context.date)
                        total(client, month, context.date)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func total(_ client: Client, _ interval: DateInterval, _ now: Date) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(Format.hours(model.seconds(for: client.id, in: interval, now: now))).monospacedDigit()
            Text(Format.money(model.amount(for: client, in: interval, now: now), client.currency))
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}
