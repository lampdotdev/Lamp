import SwiftUI

/// A site on its own, edge to edge: no title bar, just the page.
struct SiteWindowView: View {
    @StateObject private var web: WebModel

    init(site: Site, standalone: Bool) {
        _web = StateObject(wrappedValue: WebModel(site: site, standalone: standalone))
    }

    var body: some View {
        ZStack(alignment: .top) {
            WebView(web: web)
            if web.isLoading, !web.barShown {
                LoadingLine(progress: web.progress)
            }
            if web.barShown {
                HoverBar(web: web)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let link = web.offeredLink, !web.barShown {
                LinkPill(web: web, url: link)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $web.linkPrompt) { OpenLinkSheet(web: web) }
        .background(WindowAccessor { web.attach($0) })
        .frame(minWidth: 420, minHeight: 300)
        .navigationTitle(web.site.name)
        .focusedSceneObject(web)
    }
}

/// A catalog window for one site, found by its id.
struct SiteWindowLoader: View {
    let id: UUID?

    var body: some View {
        if let id, let site = Library.shared.site(id) {
            SiteWindowView(site: site, standalone: false)
        } else {
            ContentUnavailableView("Site Not Found", systemImage: "globe", description: Text("It may have been removed from the catalog."))
                .frame(minWidth: 420, minHeight: 300)
        }
    }
}
