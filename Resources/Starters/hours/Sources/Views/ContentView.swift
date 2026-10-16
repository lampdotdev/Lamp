import SwiftUI

/// What the sidebar can show: the week's time entries, or one client.
enum SidebarItem: Hashable {
    case week
    case client(UUID)

    /// Kept in SceneStorage as text, so the window reopens where the person left it.
    var key: String {
        switch self {
        case .week: "week"
        case .client(let id): id.uuidString
        }
    }

    init(key: String) {
        self = UUID(uuidString: key).map(SidebarItem.client) ?? .week
    }
}

/// The main window: time entries and clients in the sidebar, the selected one beside it.
struct ContentView: View {
    @EnvironmentObject private var model: HoursModel
    @SceneStorage("selection") private var selectionKey = "week"
    @State private var clientToDelete: Client?

    private var selection: Binding<SidebarItem?> {
        Binding(get: { SidebarItem(key: selectionKey) }, set: { selectionKey = ($0 ?? .week).key })
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            switch selection.wrappedValue {
            case .client(let id) where model.client(id) != nil:
                ClientDetailView(clientID: id)
            default:
                WeekView()
            }
        }
        .toolbar { toolbar }
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .newEntry(let clientID): EntryEditor(entry: nil, clientID: clientID)
            case .editEntry(let entry): EntryEditor(entry: entry, clientID: entry.clientID)
            case .newClient: ClientEditor(client: nil)
            case .editClient(let client): ClientEditor(client: client)
            case .invoice(let clientID): InvoiceSheet(clientID: clientID)
            }
        }
        .confirmationDialog("Delete \(clientToDelete?.name ?? "this client")?", isPresented: deleteBinding,
                            presenting: clientToDelete) { client in
            Button("Delete Client and Its Time", role: .destructive) {
                if selectionKey == client.id.uuidString { selectionKey = "week" }
                model.delete(client)
            }
        } message: { _ in
            Text("All the time tracked for this client is deleted too.")
        }
    }

    private var sidebar: some View {
        List(selection: selection) {
            Label("Time Entries", systemImage: "clock")
                .tag(SidebarItem.week)
            Section("Clients") {
                ForEach(model.clients) { client in
                    ClientRow(client: client)
                        .tag(SidebarItem.client(client.id))
                        .contextMenu {
                            Button("Start Timer") { model.startTimer(for: client.id) }
                            Button("Edit Client…") { model.sheet = .editClient(client) }
                            Button("Make Invoice…") { model.sheet = .invoice(clientID: client.id) }
                            Divider()
                            Button("Delete Client…", role: .destructive) { clientToDelete = client }
                        }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        .safeAreaInset(edge: .bottom) {
            Button { model.sheet = .newClient } label: {
                Label("New Client", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            TimerToolbarButton()
            Button { model.sheet = .newEntry(clientID: nil) } label: {
                Label("New Entry", systemImage: "plus")
            }
            .help("Add time by hand (⇧⌘N)")
            .disabled(model.clients.isEmpty)
            Button { model.sheet = .invoice(clientID: nil) } label: {
                Label("Make Invoice", systemImage: "doc.text")
            }
            .help("Make an invoice for a client and month (⇧⌘I)")
            .disabled(model.clients.isEmpty)
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { clientToDelete != nil }, set: { if !$0 { clientToDelete = nil } })
    }
}

/// A client in the sidebar: its color, its name and this week's hours.
struct ClientRow: View {
    @EnvironmentObject private var model: HoursModel
    let client: Client

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let week = Calendar.current.week(containing: context.date)
            HStack {
                Circle().fill(client.tint).frame(width: 9, height: 9)
                Text(client.name).lineLimit(1)
                Spacer()
                if model.running?.clientID == client.id {
                    Image(systemName: "timer").foregroundStyle(client.tint)
                        .accessibilityLabel("Timer running")
                }
                Text(Format.hours(model.seconds(for: client.id, in: week, now: context.date)))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Start a timer for a client, or stop the running one.
struct TimerToolbarButton: View {
    @EnvironmentObject private var model: HoursModel

    var body: some View {
        if let running = model.running {
            Button { model.stopTimer() } label: {
                Label("Stop Timer", systemImage: "stop.circle.fill")
            }
            .help("Stop the timer for \(model.client(running.clientID)?.name ?? "this client") (⇧⌘T)")
        } else {
            Menu {
                ForEach(model.clients) { client in
                    Button(client.name) { model.startTimer(for: client.id) }
                }
            } label: {
                Label("Start Timer", systemImage: "play.circle")
            }
            .help("Start a timer for a client")
            .disabled(model.clients.isEmpty)
        }
    }
}
