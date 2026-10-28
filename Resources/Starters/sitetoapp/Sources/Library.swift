import SwiftUI

/// The catalog's sites, kept with LampStore.
@MainActor
final class Library: ObservableObject {
    static let shared = Library()

    @Published private(set) var sites: [Site] = []
    /// Sites whose Dock app is being made right now.
    @Published var making: Set<UUID> = []
    /// The site whose Dock app was just made, to say where it went.
    @Published var made: Site?
    @Published var makeError: String?
    /// Web apps from the person's own browsing, most visited first.
    @Published var recent: [SiteSuggestion] = []
    private let store = LampStore.collection("sites", of: Site.self)

    init() {
        sites = store.all(orderBy: "added")
    }

    func site(_ id: UUID) -> Site? { sites.first { $0.id == id } }

    func save(_ site: Site) {
        store.put(site)
        if let index = sites.firstIndex(where: { $0.id == site.id }) {
            sites[index] = site
        } else {
            sites.append(site)
        }
    }

    func remove(_ site: Site) {
        store.delete(site.id)
        sites.removeAll { $0.id == site.id }
        if let file = site.iconFile {
            try? FileManager.default.removeItem(at: Library.iconsFolder.appendingPathComponent(file))
        }
    }

    static var iconsFolder: URL {
        let url = LampStore.folder.appendingPathComponent("Icons")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func icon(for site: Site) -> NSImage? {
        guard let file = site.iconFile else { return nil }
        return NSImage(contentsOf: Library.iconsFolder.appendingPathComponent(file))
    }
}
