import SwiftUI

/// The window: shelves in the sidebar, the chosen one drawn as a bookcase, with adding, sorting and search
/// in the toolbar. The chosen shelf, the order and the search are kept per window across launches.
struct ContentView: View {
    @EnvironmentObject private var library: Library
    @SceneStorage("shelf") private var shelfKey = ""
    @SceneStorage("order") private var order = ShelfOrder.creator
    @State private var search = ""
    @State private var adding = false
    @State private var naming: Shelf?
    @State private var newName = ""
    @State private var removing: Shelf?

    private var shelf: Shelf? {
        library.shelves.first { $0.id.uuidString == shelfKey } ?? library.shelves.first
    }

    private var shown: [ShelfItem] {
        let onShelf = library.items(on: shelf?.id)
        let words = search.trimmingCharacters(in: .whitespaces)
        let matching = words.isEmpty ? onShelf : onShelf.filter { item in
            ([item.title, item.creator, item.lentTo] + item.tags).contains { $0.localizedCaseInsensitiveContains(words) }
        }
        return order.sorted(matching)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            ShelfView(items: shown)
                .overlay { emptyState }
                .safeAreaInset(edge: .bottom) { examplesNote }
                .navigationTitle(shelf?.name ?? ItemKind.plural)
                .navigationSubtitle(count)
        }
        .searchable(text: $search, prompt: "Search \(shelf?.name ?? ItemKind.plural)")
        .toolbar { toolbar }
        .sheet(isPresented: $adding) {
            if let shelf { AddItemSheet(shelfID: shelf.id) }
        }
        .alert(naming?.name.isEmpty == false ? "Rename Shelf" : "New Shelf", isPresented: Binding(
            get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button(naming?.name.isEmpty == false ? "Rename" : "Add", action: saveName)
        }
        .confirmationDialog("Take down “\(removing?.name ?? "")”?", isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } }), presenting: removing) { shelf in
            Button("Take Down Shelf", role: .destructive) { library.remove(shelf) }
        } message: { _ in
            Text("Everything on it moves to \(library.shelves.first { $0.id != removing?.id }?.name ?? "the first shelf").")
        }
        .focusedSceneValue(\.shelfActions, ShelfActions(addItem: { adding = true }, newShelf: startNewShelf))
    }

    private var sidebar: some View {
        List(selection: Binding(get: { shelf?.id.uuidString }, set: { shelfKey = $0 ?? "" })) {
            Section("Shelves") {
                ForEach(library.shelves) { shelf in
                    Label(shelf.name, systemImage: "books.vertical")
                        .badge(library.items(on: shelf.id).count)
                        .tag(shelf.id.uuidString)
                        .dropDestination(for: String.self) { ids, _ in
                            ids.compactMap(UUID.init(uuidString:)).forEach { library.move($0, to: shelf.id) }
                            return true
                        }
                        .contextMenu {
                            Button("Rename…") { newName = shelf.name; naming = shelf }
                            Button("Take Down…", role: .destructive) { removing = shelf }
                                .disabled(library.shelves.count < 2)
                        }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        .safeAreaInset(edge: .bottom) {
            Button(action: startNewShelf) {
                Label("New Shelf", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Menu {
                Picker("Sort", selection: $order) {
                    ForEach(ShelfOrder.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .help("Change the order on the shelf")
        }
        ToolbarItem {
            Button { adding = true } label: {
                Label("Add \(ItemKind.singular)", systemImage: "plus")
            }
            .help("Add a \(ItemKind.singular.lowercased()) by its barcode, number or title (⇧⌘N)")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if shown.isEmpty {
            if search.isEmpty {
                ContentUnavailableView {
                    Label("An Empty Shelf", systemImage: "books.vertical")
                } description: {
                    Text("Scan a barcode, type an \(ItemKind.code) or search by title.")
                } actions: {
                    Button("Add \(ItemKind.singular)…") { adding = true }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .fixedSize()
            } else {
                ContentUnavailableView.search(text: search)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .fixedSize()
            }
        }
    }

    /// A quiet line under the examples, until they're cleared.
    @ViewBuilder
    private var examplesNote: some View {
        if shown.contains(where: \.isExample) {
            HStack(spacing: 8) {
                Text("These are examples.")
                Button("Clear Examples") { library.clearExamples() }
                    .buttonStyle(.link)
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 10)
        }
    }

    private var count: String {
        let n = library.items(on: shelf?.id).count
        return n == 1 ? "1 \(ItemKind.singular.lowercased())" : "\(n) \(ItemKind.plural.lowercased())"
    }

    private func startNewShelf() {
        // The first new shelf is offered as the wish list; after that, the name is the person's.
        let hasWishShelf = library.shelves.contains { $0.name == ItemKind.wishShelf }
        newName = hasWishShelf ? "" : ItemKind.wishShelf
        naming = Shelf(name: "", order: 0)
    }

    private func saveName() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard let target = naming, !name.isEmpty else { return }
        if library.shelves.contains(target) {
            library.rename(target, to: name)
        } else {
            shelfKey = library.addShelf(named: name).id.uuidString
        }
        naming = nil
    }
}

