import SwiftUI

/// Make Invoice: pick a client and a month, see the page, then save it as a PDF or print it.
struct InvoiceSheet: View {
    @EnvironmentObject private var model: HoursModel
    @Environment(\.dismiss) private var dismiss

    @State private var clientID: UUID?
    @State private var monthStart: Date?
    @AppStorage("invoiceGrouping") private var grouping: InvoiceGrouping = .byDay
    /// Line descriptions rewritten by Tidy, by line id. Cleared whenever the lines themselves change.
    @State private var tidied: [String: String] = [:]
    @State private var tidying = false
    @State private var aiAvailable = true
    @State private var message: String?

    init(clientID: UUID?) {
        _clientID = State(initialValue: clientID)
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            ScrollView {
                if let invoice {
                    InvoicePage(invoice: invoice)
                        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                        .padding(24)
                }
            }
            .background(.background.secondary)
            Divider()
            buttons
        }
        .frame(width: 700, height: 640)
        .onAppear {
            if clientID == nil { clientID = model.lastClientID }
            pickMonth()
        }
        .onChange(of: clientID) { pickMonth() }
        .onChange(of: linesKey) { tidied = [:]; message = nil }
        .task { aiAvailable = await LampAI.isAvailable(.text) }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Picker("Client", selection: $clientID) {
                ForEach(model.clients) { Text($0.name).tag(Optional($0.id)) }
            }
            .frame(maxWidth: 240)
            Picker("Month", selection: $monthStart) {
                ForEach(months, id: \.start) { Text(Format.month($0)).tag(Optional($0.start)) }
            }
            .frame(maxWidth: 200)
            Picker("Lines", selection: $grouping) {
                ForEach(InvoiceGrouping.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("One line per day worked, or one per note")
        }
        .padding(12)
    }

    private var buttons: some View {
        HStack {
            tidyButton
            if let message {
                Text(message).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            } else if model.profile.isEmpty {
                Text("Add your name and payment details in Settings.").font(.callout).foregroundStyle(.secondary)
                SettingsLink { Text("Settings…") }.buttonStyle(.link)
            }
            Spacer()
            Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Print…") { if let invoice { InvoiceExport.print(invoice) } }
                .keyboardShortcut("p")
                .disabled(invoice?.lines.isEmpty ?? true)
            Button("Save as PDF…") { savePDF() }
                .keyboardShortcut(.defaultAction)
                .disabled(invoice?.lines.isEmpty ?? true)
        }
        .padding(12)
    }

    // MARK: Tidy line items (optional AI)

    @ViewBuilder private var tidyButton: some View {
        if tidying {
            ProgressView().controlSize(.small)
            Text("Tidying…").font(.callout).foregroundStyle(.secondary)
        } else if !tidied.isEmpty {
            Button("Undo Tidy", systemImage: "arrow.uturn.backward") { tidied = [:] }
        } else {
            Button("Tidy Line Items", systemImage: "sparkles") { Task { await tidy() } }
                .disabled(!aiAvailable || (invoice?.lines.isEmpty ?? true))
                .help(aiAvailable ? "Rewrite your notes as clear invoice lines" : "Tidying needs AI set up in Lamp")
        }
    }

    /// Asks the AI to turn quick working notes into clear line descriptions, one for one. Anything going wrong
    /// leaves the notes as they were, with a quiet message.
    private func tidy() async {
        guard let lines = rawInvoice?.lines, !lines.isEmpty else { return }
        struct Reply: Decodable { let lines: [String] }
        tidying = true
        message = nil
        defer { tidying = false }
        let numbered = lines.enumerated().map { "\($0.offset + 1). \($0.element.description)" }.joined(separator: "\n")
        do {
            let reply = try await LampAI.ask("""
                These are an invoice's line items, written as quick notes while working. Rewrite each as a clear, \
                professional line description a client will understand: short, specific, in the notes' language, \
                without hours, dates or prices. Keep the same order and the same number of lines. \
                Reply as JSON: {"lines": ["..."]}
                """, data: numbered, as: Reply.self)
            guard reply.lines.count == lines.count else {
                message = "Couldn't tidy these lines. They're unchanged."
                return
            }
            tidied = Dictionary(uniqueKeysWithValues: zip(lines.map(\.id), reply.lines))
        } catch {
            message = "Couldn't tidy the lines just now. They're unchanged."
        }
    }

    // MARK: The invoice

    private var months: [DateInterval] {
        guard let clientID else { return [] }
        return Invoice.months(for: clientID, in: model.entries)
    }

    /// The month to start on: this one once it has work in it, else the last month that does (on the first
    /// of the month, last month's invoice is the one to send).
    private func pickMonth() {
        let available = months
        if let monthStart, available.contains(where: { $0.start == monthStart }) { return }
        guard let clientID else { return }
        let current = available.first
        let hasWork = current.map { !model.entries(in: $0, for: clientID).filter { !$0.isRunning }.isEmpty } ?? false
        monthStart = (hasWork ? current : available.dropFirst().first ?? current)?.start
    }

    private var rawInvoice: Invoice? {
        guard let clientID, let client = model.client(clientID), let monthStart,
              let month = months.first(where: { $0.start == monthStart }) else { return nil }
        return Invoice.make(client: client, month: month, entries: model.entries, grouping: grouping,
                            profile: model.profile)
    }

    private var invoice: Invoice? {
        guard var invoice = rawInvoice else { return nil }
        for index in invoice.lines.indices {
            if let text = tidied[invoice.lines[index].id] { invoice.lines[index].description = text }
        }
        return invoice
    }

    /// Changes whenever the lines would, so tidied text never lands on the wrong line.
    private var linesKey: String {
        "\(clientID?.uuidString ?? "")|\(monthStart?.timeIntervalSince1970 ?? 0)|\(grouping.rawValue)"
    }

    private func savePDF() {
        guard let invoice, InvoiceExport.save(invoice) else { return }
        model.invoiceIssued()
        dismiss()
    }
}
