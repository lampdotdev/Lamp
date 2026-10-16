import SwiftUI

/// One client: rate, what this week and month come to, and this month's entries.
struct ClientDetailView: View {
    @EnvironmentObject private var model: HoursModel
    let clientID: UUID

    var body: some View {
        if let client = model.client(clientID) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                content(client, now: context.date)
            }
            .navigationTitle(client.name)
            .navigationSubtitle("\(Format.money(client.rate, client.currency)) an hour")
        }
    }

    private func content(_ client: Client, now: Date) -> some View {
        let calendar = Calendar.current
        let week = calendar.week(containing: now)
        let month = calendar.month(containing: now)
        let monthEntries = model.entries(in: month, for: client.id)
        return List {
            Section {
                HStack(spacing: 12) {
                    Stat(title: "This Week", seconds: model.seconds(for: client.id, in: week, now: now),
                         amount: model.amount(for: client, in: week, now: now), client: client)
                    Stat(title: "This Month", seconds: model.seconds(for: client.id, in: month, now: now),
                         amount: model.amount(for: client, in: month, now: now), client: client)
                }
                HStack {
                    if model.running?.clientID == client.id {
                        Button("Stop Timer", systemImage: "stop.circle.fill") { model.stopTimer() }
                    } else {
                        Button("Start Timer", systemImage: "play.circle") { model.startTimer(for: client.id) }
                    }
                    Button("Make Invoice…", systemImage: "doc.text") { model.sheet = .invoice(clientID: client.id) }
                    Button("Edit Client…", systemImage: "pencil") { model.sheet = .editClient(client) }
                }
                .buttonStyle(.bordered)
            }
            Section(month.start.formatted(.dateTime.month(.wide))) {
                if monthEntries.isEmpty {
                    Text("Nothing tracked this month yet.").foregroundStyle(.secondary)
                }
                ForEach(monthEntries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        EntryRow(entry: entry)
                        Text(entry.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                            .font(.caption2).foregroundStyle(.tertiary)
                            .padding(.leading, 19)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { model.sheet = .editEntry(entry) }
                    .contextMenu {
                        Button("Edit Entry…") { model.sheet = .editEntry(entry) }
                    }
                }
            }
        }
    }
}

/// A large number with its label: hours worked and what they come to.
private struct Stat: View {
    let title: String
    let seconds: TimeInterval
    let amount: Double
    let client: Client

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Format.hours(seconds)).font(.title.weight(.semibold)).monospacedDigit()
            Text(Format.money(amount, client.currency)).foregroundStyle(.secondary).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}
