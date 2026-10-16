import SwiftUI

/// Everything the app knows: clients, time entries, the running timer and the person's details. One model is
/// shared by the window, the menu bar panel and Settings, and every change is saved to LampStore at once.
@MainActor
final class HoursModel: ObservableObject {
    @Published private(set) var clients: [Client] = []
    /// Newest first.
    @Published private(set) var entries: [TimeEntry] = []
    @Published var profile: Profile {
        didSet { if profile != oldValue { LampStore.save(profile, to: "profile") } }
    }
    /// The sheet the window shows: an editor or the invoice. Set from the toolbar, menus and panel alike.
    @Published var sheet: Sheet?

    /// Ticks once a second while a timer runs, for the menu bar's elapsed time. It's separate from the model
    /// so the window isn't redrawn every second.
    let ticker = Ticker()

    private let clientStore = LampStore.collection("clients", of: Client.self)
    private let entryStore = LampStore.collection("entries", of: TimeEntry.self)

    enum Sheet: Identifiable {
        case newEntry(clientID: UUID?)
        case editEntry(TimeEntry)
        case newClient
        case editClient(Client)
        case invoice(clientID: UUID?)

        var id: String {
            switch self {
            case .newEntry: "newEntry"
            case .editEntry(let entry): "entry-\(entry.id)"
            case .newClient: "newClient"
            case .editClient(let client): "client-\(client.id)"
            case .invoice: "invoice"
            }
        }
    }

    init() {
        profile = LampStore.load(Profile.self, from: "profile") ?? Profile()
        SampleData.addOnce(clients: clientStore, entries: entryStore)
        reload()
    }

    private func reload() {
        clients = clientStore.all().sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        entries = entryStore.all().sorted { $0.start > $1.start }
        ticker.isRunning = running != nil
    }

    // MARK: Looking things up

    var running: TimeEntry? { entries.first(where: \.isRunning) }

    func client(_ id: UUID) -> Client? { clients.first { $0.id == id } }

    func entries(in interval: DateInterval, for clientID: UUID? = nil) -> [TimeEntry] {
        entries.filter { interval.contains($0.start) && (clientID == nil || $0.clientID == clientID) }
    }

    /// Time worked for a client in a stretch of days, counting the running timer up to now.
    func seconds(for clientID: UUID, in interval: DateInterval, now: Date = .now) -> TimeInterval {
        entries(in: interval, for: clientID).reduce(0) { $0 + $1.duration(now: now) }
    }

    func amount(for client: Client, in interval: DateInterval, now: Date = .now) -> Double {
        seconds(for: client.id, in: interval, now: now) / 3600 * client.rate
    }

    /// The client last worked for, so a new entry starts with the likeliest one.
    var lastClientID: UUID? { entries.first?.clientID ?? clients.first?.id }

    var hasExamples: Bool {
        clients.contains { $0.isExample == true } || entries.contains { $0.isExample == true }
    }

    // MARK: The timer

    /// Starts a timer for the client, stopping whichever one was running: only one runs at a time.
    func startTimer(for clientID: UUID, note: String = "") {
        stopTimer()
        save(TimeEntry(clientID: clientID, start: .now, end: nil, note: note))
    }

    func stopTimer() {
        guard var entry = running else { return }
        entry.end = .now
        save(entry)
    }

    // MARK: Changing things

    /// A sample entry or client the person has changed is theirs from then on: Clear Examples leaves it.
    func save(_ entry: TimeEntry) {
        var entry = entry
        if let old = entries.first(where: { $0.id == entry.id }), old != entry { entry.isExample = nil }
        entryStore.put(entry)
        reload()
    }

    func delete(_ entryIDs: Set<UUID>) {
        entryIDs.forEach(entryStore.delete)
        reload()
    }

    func save(_ client: Client) {
        var client = client
        if let old = clients.first(where: { $0.id == client.id }), old != client { client.isExample = nil }
        clientStore.put(client)
        reload()
    }

    /// Removes the client and all the time tracked for it.
    func delete(_ client: Client) {
        LampStore.transaction {
            for entry in entries where entry.clientID == client.id { entryStore.delete(entry.id) }
            clientStore.delete(client.id)
        }
        reload()
    }

    /// Removes the sample clients and entries, and nothing the person added. They don't come back. A sample
    /// client the person has tracked their own time for is kept, as theirs now, with that time.
    func clearExamples() {
        let theirs = Set(entries.filter { $0.isExample != true }.map(\.clientID))
        LampStore.transaction {
            for entry in entries where entry.isExample == true { entryStore.delete(entry.id) }
            for client in clients where client.isExample == true {
                if theirs.contains(client.id) {
                    var kept = client
                    kept.isExample = nil
                    clientStore.put(kept)
                } else {
                    clientStore.delete(client.id)
                }
            }
        }
        reload()
    }

    /// Called once an invoice has been saved, so the next one gets the next number.
    func invoiceIssued() {
        profile.nextInvoiceNumber += 1
    }
}

/// A clock that ticks once a second, only while it's needed.
@MainActor
final class Ticker: ObservableObject {
    @Published private(set) var now = Date()
    private var timer: Timer?

    var isRunning = false {
        didSet {
            guard isRunning != oldValue else { return }
            timer?.invalidate()
            timer = nil
            now = .now
            guard isRunning else { return }
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.now = .now }
            }
        }
    }
}
