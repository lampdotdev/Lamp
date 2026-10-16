import SwiftUI

/// Adds time by hand, or changes an entry: client, day, start and end, and a short note.
struct EntryEditor: View {
    @EnvironmentObject private var model: HoursModel
    @Environment(\.dismiss) private var dismiss

    private let original: TimeEntry?
    @State private var clientID: UUID?
    @State private var day: Date
    @State private var start: Date
    @State private var end: Date
    @State private var note: String

    init(entry: TimeEntry?, clientID: UUID?) {
        original = entry
        _clientID = State(initialValue: clientID)
        // A new entry is the last hour, on quarter hours.
        let now = Date.now
        let quarter: TimeInterval = 15 * 60
        let roundedNow = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / quarter).rounded(.down) * quarter)
        let start = entry?.start ?? roundedNow.addingTimeInterval(-3600)
        _day = State(initialValue: start)
        _start = State(initialValue: start)
        _end = State(initialValue: entry?.end ?? (entry == nil ? roundedNow : now))
        _note = State(initialValue: entry?.note ?? "")
    }

    private var isRunning: Bool { original?.isRunning == true }

    var body: some View {
        Form {
            Picker("Client", selection: $clientID) {
                ForEach(model.clients) { client in
                    Text(client.name).tag(Optional(client.id))
                }
            }
            TextField("Note", text: $note, prompt: Text("What did you work on?"))
            DatePicker("Day", selection: $day, displayedComponents: .date)
            DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute)
            if isRunning {
                LabeledContent("End", value: "Running")
            } else {
                DatePicker("End", selection: $end, displayedComponents: .hourAndMinute)
                LabeledContent("Length", value: Format.duration(span.end.timeIntervalSince(span.start)))
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .navigationTitle(original == nil ? "New Entry" : "Edit Entry")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(original == nil ? "Add" : "Save") { save() }.disabled(clientID == nil)
            }
        }
        .onAppear { if clientID == nil { clientID = model.lastClientID } }
    }

    /// The day with the start and end times put on it. An end earlier than the start is taken to be after
    /// midnight, so a late session doesn't come out negative.
    private var span: (start: Date, end: Date) {
        let start = onDay(start)
        var end = onDay(end)
        if end <= start { end = Calendar.current.date(byAdding: .day, value: 1, to: end) ?? end }
        return (start, end)
    }

    private func onDay(_ time: Date) -> Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day) ?? day
    }

    private func save() {
        guard let clientID else { return }
        var entry = original ?? TimeEntry(clientID: clientID, start: .now, note: "")
        entry.clientID = clientID
        entry.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.start = span.start
        if !isRunning { entry.end = span.end }
        model.save(entry)
        dismiss()
    }
}

/// Adds or changes a client: name, hourly rate, currency and color.
struct ClientEditor: View {
    @EnvironmentObject private var model: HoursModel
    @Environment(\.dismiss) private var dismiss

    private let original: Client?
    @State private var name: String
    @State private var rate: Double
    @State private var currency: String
    @State private var color: String

    init(client: Client?) {
        original = client
        _name = State(initialValue: client?.name ?? "")
        _rate = State(initialValue: client?.rate ?? 75)
        _currency = State(initialValue: client?.currency ?? Currencies.common[0])
        _color = State(initialValue: client?.color ?? ClientColor.allCases.randomElement()!.rawValue)
    }

    var body: some View {
        Form {
            TextField("Name", text: $name, prompt: Text("Who you work for"))
            TextField("Hourly rate", value: $rate, format: .number.precision(.fractionLength(0...2)))
            Picker("Currency", selection: $currency) {
                ForEach(currencyChoices, id: \.self) { Text($0).tag($0) }
            }
            LabeledContent("Color") {
                HStack(spacing: 6) {
                    ForEach(ClientColor.allCases) { choice in
                        Button { color = choice.rawValue } label: {
                            Circle().fill(choice.color).frame(width: 16, height: 16)
                                .overlay(Circle().strokeBorder(.primary, lineWidth: color == choice.rawValue ? 2 : 0))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(choice.rawValue.capitalized)
                        .accessibilityAddTraits(color == choice.rawValue ? .isSelected : [])
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .navigationTitle(original == nil ? "New Client" : "Edit Client")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(original == nil ? "Add" : "Save") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    /// A client's own currency stays on the list even when it isn't one of the common ones.
    private var currencyChoices: [String] {
        Currencies.common.contains(currency) ? Currencies.common : [currency] + Currencies.common
    }

    private func save() {
        var client = original ?? Client(name: "", rate: 0, currency: currency, color: color)
        client.name = name.trimmingCharacters(in: .whitespaces)
        client.rate = max(0, rate)
        client.currency = currency
        client.color = color
        model.save(client)
        dismiss()
    }
}
