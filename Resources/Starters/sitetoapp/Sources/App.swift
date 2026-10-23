import SwiftUI

@main
struct MainApp: SwiftUI.App {
    var body: some SwiftUI.Scene {
        // In the catalog, its window; in a site's own Dock app, that site, edge to edge.
        WindowGroup(SiteMode.site?.name ?? "Site-to-App") {
            if let site = SiteMode.site {
                SiteWindowView(site: site, standalone: true)
            } else {
                CatalogView()
            }
        }
        .defaultSize(SiteMode.site == nil ? CGSize(width: 760, height: 680) : CGSize(width: 1200, height: 800))
        .commands {
            LampCommands()
            PageCommands()
        }

        // The catalog's sites, each in a window of its own.
        WindowGroup("Site", id: "site", for: UUID.self) { $id in
            SiteWindowLoader(id: id)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
    }
}
