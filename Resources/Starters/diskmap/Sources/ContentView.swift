import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: DiskModel
    @State private var pendingTrash: [Node] = []

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } detail: {
            detail
        }
        .frame(minWidth: 820, minHeight: 520)
        .toolbar { toolbar }
        .navigationTitle(model.current?.title ?? model.location?.name ?? "Disk Map")
        .onReceive(NotificationCenter.default.publisher(for: .requestTrash)) { note in
            pendingTrash = note.object as? [Node] ?? []
        }
        .confirmationDialog(trashTitle, isPresented: Binding(get: { !pendingTrash.isEmpty }, set: { if !$0 { pendingTrash = [] } }),
                            titleVisibility: .visible, presenting: pendingTrash) { nodes in
            Button("Move to Trash", role: .destructive) { model.trash(nodes) }
        } message: { nodes in
            Text("\(nodes.count == 1 ? "It takes" : "They take") up \(formatBytes(nodes.reduce(0) { $0 + $1.size })). You can put \(nodes.count == 1 ? "it" : "them") back from the Trash until you empty it.")
        }
        .alert("Couldn't move to the Trash", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var trashTitle: String {
        pendingTrash.count == 1 ? "Move “\(pendingTrash[0].title)” to the Trash?" : "Move \(pendingTrash.count) items to the Trash?"
    }

    @ViewBuilder private var detail: some View {
        if let current = model.current {
            BrowserView(folder: current)
        } else {
            ContentUnavailableView {
                Label("Choose a Location", systemImage: "internaldrive")
            } description: {
                Text("Pick your disk, your home folder, or any folder to see what's using space.")
            } actions: {
                Button("Add Folder…") { model.addFolder() }
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { model.goUp() } label: { Label("Enclosing Folder", systemImage: "chevron.up") }
                .help("Go to the enclosing folder (⌘↑)")
                .disabled(!model.canGoUp)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.scan() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                .help("Measure this location again (⌘R)")
                .disabled(model.location == nil || model.scanning)
            Button {
                if model.selectedNodes.isEmpty { if let current = model.current { model.reveal(current) } } else { model.reveal(model.selectedNodes) }
            } label: { Label("Show in Finder", systemImage: "folder") }
                .help("Show the selected item in Finder")
                .disabled(model.current == nil)
            Button {
                requestTrash(model.selectedNodes)
            } label: { Label("Move to Trash", systemImage: "trash") }
                .help("Move the selected item to the Trash (⌘⌫)")
                .disabled(!model.canTrashSelection)
        }
    }
}

extension Notification.Name {
    static let requestTrash = Notification.Name("DiskMapRequestTrash")
}

func requestTrash(_ nodes: [Node]) {
    let nodes = nodes.filter(\.canTrash)
    guard !nodes.isEmpty else { return }
    NotificationCenter.default.post(name: .requestTrash, object: nodes)
}

struct SidebarView: View {
    @EnvironmentObject var model: DiskModel

    var body: some View {
        List(selection: $model.selectedLocation) {
            Section("Locations") {
                ForEach(model.places) { row($0) }
            }
            if !model.volumes.isEmpty {
                Section("Volumes") {
                    ForEach(model.volumes) { row($0) }
                }
            }
            Section("Folders") {
                ForEach(model.folders) { loc in
                    row(loc).contextMenu {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: loc.path)]) }
                        Divider()
                        Button("Remove from Sidebar") { model.removeFolder(loc) }
                    }
                }
                Button { model.addFolder() } label: {
                    Label("Add Folder…", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .lampDropFiles { urls in
            for url in urls where (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                model.addFolder(url)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let usage = model.diskUsage {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: Double(usage.used), total: Double(max(usage.total, 1)))
                        .tint(Double(usage.free) / Double(max(usage.total, 1)) < 0.1 ? .red : .accentColor)
                    Text("\(formatBytes(usage.free)) free of \(formatBytes(usage.total))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
            }
        }
        .onAppear { model.refreshVolumes() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in model.refreshVolumes() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in model.refreshVolumes() }
    }

    private func row(_ loc: Location) -> some View {
        Label(loc.name, systemImage: loc.symbol).tag(loc.id)
    }
}
