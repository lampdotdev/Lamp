import Foundation

/// How an invoice's lines are made from the month's entries.
enum InvoiceGrouping: String, CaseIterable, Identifiable {
    /// One line per day worked, its notes joined.
    case byDay = "By Day"
    /// One line per distinct note, its time added up across the month.
    case byNote = "By Note"

    var id: String { rawValue }
}

struct InvoiceLine: Identifiable, Equatable {
    let id: String
    /// The day, for a line per day; nil for a line per note.
    let date: Date?
    var description: String
    let hours: Double
    let amount: Double
}

/// One client's work for one month, ready to be shown, saved as a PDF or printed. Made fresh whenever the
/// choices change; nothing about an invoice is stored except the next number (in `Profile`).
struct Invoice {
    let number: String
    let issued: Date
    let due: Date
    let month: DateInterval
    let client: Client
    let profile: Profile
    var lines: [InvoiceLine]

    var totalHours: Double { lines.reduce(0) { $0 + $1.hours } }
    var total: Double { lines.reduce(0) { $0 + $1.amount } }

    /// Finished entries only: a running timer isn't billed until it's stopped.
    static func make(client: Client, month: DateInterval, entries: [TimeEntry], grouping: InvoiceGrouping,
                     profile: Profile) -> Invoice {
        let worked = entries
            .filter { $0.clientID == client.id && !$0.isRunning && month.contains($0.start) }
            .sorted { $0.start < $1.start }
        let issued = Date.now
        let due = Calendar.current.date(byAdding: .day, value: profile.paymentTermsDays, to: issued) ?? issued
        return Invoice(number: profile.invoiceNumber, issued: issued, due: due, month: month, client: client,
                       profile: profile, lines: lines(for: worked, grouping: grouping, rate: client.rate))
    }

    private static func lines(for entries: [TimeEntry], grouping: InvoiceGrouping, rate: Double) -> [InvoiceLine] {
        let calendar = Calendar.current
        // Groups keep the order they first appear in, so lines read in date order either way.
        var order: [String] = []
        var groups: [String: [TimeEntry]] = [:]
        for entry in entries {
            let key: String
            switch grouping {
            case .byDay: key = String(calendar.startOfDay(for: entry.start).timeIntervalSince1970)
            case .byNote: key = entry.note.trimmingCharacters(in: .whitespaces).lowercased()
            }
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(entry)
        }
        return order.map { key in
            let group = groups[key] ?? []
            let hours = group.reduce(0) { $0 + $1.duration() } / 3600
            var notes: [String] = []
            for entry in group {
                let note = entry.note.trimmingCharacters(in: .whitespaces)
                if !note.isEmpty, !notes.contains(note) { notes.append(note) }
            }
            let description = notes.isEmpty ? "Work" : notes.joined(separator: "; ")
            let date = grouping == .byDay ? group.first.map { calendar.startOfDay(for: $0.start) } : nil
            return InvoiceLine(id: key, date: date, description: description, hours: hours, amount: hours * rate)
        }
    }

    /// The months a client has finished work in, newest first, and always the current month.
    static func months(for clientID: UUID, in entries: [TimeEntry]) -> [DateInterval] {
        let calendar = Calendar.current
        var starts = Set(entries.filter { $0.clientID == clientID && !$0.isRunning }
            .compactMap { calendar.dateInterval(of: .month, for: $0.start)?.start })
        if let now = calendar.dateInterval(of: .month, for: .now)?.start { starts.insert(now) }
        return starts.sorted(by: >).compactMap { calendar.dateInterval(of: .month, for: $0) }
    }
}
