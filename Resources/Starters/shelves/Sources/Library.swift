import SwiftUI

/// Everything on the shelves, kept in LampStore: the shelves in "shelves", the items in "items", each saved
/// as soon as it changes. Covers are files of their own (`Covers`), fetched in the background.
@MainActor
final class Library: ObservableObject {
    @Published private(set) var shelves: [Shelf] = []
    @Published private(set) var items: [ShelfItem] = []
    @Published private(set) var covers: [UUID: NSImage] = [:]

    private let shelfStore = LampStore.collection("shelves", of: Shelf.self)
    private let itemStore = LampStore.collection("items", of: ShelfItem.self)
    /// Covers already asked for this launch, so one that isn't there isn't asked for again and again.
    private var coversTried: Set<UUID> = []

    init() {
        shelves = shelfStore.all(orderBy: "order")
        if shelves.isEmpty {
            let first = Shelf(name: ItemKind.firstShelf, order: 0)
            shelfStore.put(first)
            shelves = [first]
        }
        // The examples are written once, on the very first launch, and never again after they're cleared.
        if LampStore.load(Bool.self, from: "examplesWritten") == nil {
            itemStore.put(Examples.items(on: shelves[0].id))
            LampStore.save(true, to: "examplesWritten")
        }
        items = itemStore.all(orderBy: "added")
        for item in items {
            if let image = Covers.cached(item.id) { covers[item.id] = image }
        }
        Task { await fetchMissingCovers() }
    }

    // MARK: Items

    func items(on shelf: Shelf.ID?) -> [ShelfItem] { items.filter { $0.shelfID == shelf } }

    func item(_ id: ShelfItem.ID) -> ShelfItem? { items.first { $0.id == id } }

    @discardableResult
    func add(_ details: ItemDetails, to shelf: Shelf.ID) -> ShelfItem {
        let isWish = shelves.first { $0.id == shelf }?.name == ItemKind.wishShelf
        let item = ShelfItem(title: details.title, creator: details.creator, year: details.year, code: details.code,
                             coverURL: details.coverURL, status: isWish ? .want : .read, shelfID: shelf,
                             look: .random(pages: details.pages))
        items.append(item)
        itemStore.put(item)
        Task { await fetchCover(for: item) }
        return item
    }

    func update(_ item: ShelfItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }), items[index] != item else { return }
        items[index] = item
        itemStore.put(item)
    }

    func delete(_ id: ShelfItem.ID) {
        items.removeAll { $0.id == id }
        itemStore.delete(id)
        covers[id] = nil
        Covers.remove(id)
    }

    func move(_ id: ShelfItem.ID, to shelf: Shelf.ID) {
        guard var item = item(id) else { return }
        item.shelfID = shelf
        update(item)
    }

    var hasExamples: Bool { items.contains { $0.isExample } }

    func clearExamples() {
        for item in items where item.isExample { delete(item.id) }
    }

    // MARK: Shelves

    @discardableResult
    func addShelf(named name: String) -> Shelf {
        let shelf = Shelf(name: name, order: (shelves.map(\.order).max() ?? 0) + 1)
        shelves.append(shelf)
        shelfStore.put(shelf)
        return shelf
    }

    func rename(_ shelf: Shelf, to name: String) {
        guard let index = shelves.firstIndex(of: shelf), !name.isEmpty else { return }
        shelves[index].name = name
        shelfStore.put(shelves[index])
    }

    /// Takes a shelf down. What stood on it moves to the first shelf left, so nothing is lost with it.
    func remove(_ shelf: Shelf) {
        guard shelves.count > 1 else { return }
        shelves.removeAll { $0.id == shelf.id }
        shelfStore.delete(shelf.id)
        for item in items(on: shelf.id) { move(item.id, to: shelves[0].id) }
    }

    // MARK: Covers

    private func fetchMissingCovers() async {
        for item in items where covers[item.id] == nil {
            await fetchCover(for: item)
        }
    }

    /// Downloads an item's cover once, and the first time one arrives, colours its spine to match.
    func fetchCover(for item: ShelfItem) async {
        guard let url = item.coverURL, !coversTried.contains(item.id) else { return }
        coversTried.insert(item.id)
        guard let image = await Covers.download(url, for: item.id) else { return }
        // Removed while its cover was on the way: the file it left goes too.
        guard var current = self.item(item.id) else { return Covers.remove(item.id) }
        covers[item.id] = image
        if !current.look.fromCover, let colour = Covers.spineColor(of: image) {
            current.look = current.look.tinted(from: colour)
            update(current)
        }
    }
}
