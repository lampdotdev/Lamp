import SwiftUI

/// The window: watched folders in the sidebar, the selected one's rules, preview and activity beside them.
struct ContentView: View {
    @EnvironmentObject private var model: TidyModel
    // Kept per window, so the app reopens on the folder the person was looking at.
    @SceneStorage("selectedFolder") private var selectedID = ""

    private var selection: Binding<UUID?> {
        Binding(get: { UUID(uuidString: selectedID) }, set: { selectedID = $0?.uuidString ?? "" })
    }

    var body: some View {
        NavigationSplitView {
            FolderSidebar(selection: selection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 280)
        } detail: {
            if let folder = model.folder(selection.wrappedValue) {
                FolderDetailView(folderID: folder.id)
                    .id(folder.id)
            } else {
                ContentUnavailableView("No Folder Selected", systemImage: "folder",
                                       description: Text("Choose a folder on the left, or add one to tidy."))
            }
        }
        .focusedSceneValue(\.selectedFolder, selection.wrappedValue)
        .onAppear {
            if model.folder(selection.wrappedValue) == nil { selection.wrappedValue = model.folders.first?.id }
        }
        .onChange(of: model.folders.map(\.id)) { _, ids in
            if let id = selection.wrappedValue, !ids.contains(id) { selection.wrappedValue = ids.first }
        }
    }
}

struct FolderSidebar: View {
    @EnvironmentObject private var model: TidyModel
    @Binding var selection: UUID?

    var body: some View {
        List(selection: $selection) {
            Section("Folders") {
                ForEach(model.folders) { folder in
                    Label(folder.name, systemImage: folder.symbol)
                        .badge(model.plans[folder.id]?.changes.count ?? 0)
                        .tag(folder.id)
                        .contextMenu {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder.url]) }
                            Divider()
                            Button("Stop Tidying") { model.remove(folder.id) }
                        }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                if let id = addFolder() { selection = id }
            } label: {
                Label("Add Folder…", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("Choose another folder to tidy")
        }
    }

    private func addFolder() -> UUID? {
        let before = Set(model.folders.map(\.id))
        model.addFolder()
        return model.folders.first { !before.contains($0.id) }?.id
    }
}
