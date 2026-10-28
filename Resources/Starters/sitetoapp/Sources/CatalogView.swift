import SwiftUI

/// The catalog: every site as an app icon, opened in a window of its own.
struct CatalogView: View {
    @ObservedObject private var library = Library.shared
    @Environment(\.openWindow) private var openWindow
    @State private var adding = false
    @State private var editing: Site?
    @State private var removing: Site?

    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 14)]

    var body: some View {
        ZStack {
            SkyBackdrop()
            if library.sites.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Your Apps")
                                .font(.system(.title, design: .rounded).weight(.bold))
                            Text(summary)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        LazyVGrid(columns: columns, spacing: 22) {
                            ForEach(library.sites) { site in
                                SiteTile(site: site) { open(site) }
                                    .contextMenu { menu(for: site) }
                            }
                        }
                        if !suggestions.isEmpty {
                            sectionTitle("Add another", symbol: "sparkles")
                                .padding(.top, 22)
                            suggestionChips(suggestions)
                        }
                    }
                    .padding(28)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { adding = true } label: { Label("Add Site", systemImage: "plus") }
                    .help("Add a website as an app")
            }
        }
        .sheet(isPresented: $adding) { AddSiteView(editing: nil) }
        .sheet(item: $editing) { site in AddSiteView(editing: site) }
        .confirmationDialog("Remove \(removing?.name ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove", role: .destructive) {
                if let removing { library.remove(removing) }
                removing = nil
            }
        } message: {
            Text("It leaves the catalog. Its Dock app, if you made one, stays in Applications.")
        }
        .alert("\(library.made?.name ?? "") is ready", isPresented: Binding(get: { library.made != nil }, set: { if !$0 { library.made = nil } })) {
            Button("Show in Finder") {
                if let made = library.made { library.revealApp(for: made) }
                library.made = nil
            }
            Button("OK", role: .cancel) { library.made = nil }
        } message: {
            Text("It's in the Applications folder in your home folder, and open now. To keep it in the Dock, right-click its icon there and choose Options › Keep in Dock.")
        }
        .alert("Couldn't Make the App", isPresented: Binding(get: { library.makeError != nil }, set: { if !$0 { library.makeError = nil } })) {
            Button("OK", role: .cancel) { library.makeError = nil }
        } message: {
            Text(library.makeError ?? "")
        }
        .task {
            for site in library.sites where library.icon(for: site) == nil { library.fetchIcon(for: site) }
            await library.loadRecent()
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let hero = LampAssets.image("hero.png") {
                    Image(nsImage: hero)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 170)
                        .shadow(color: Theme.violet.opacity(0.25), radius: 24, y: 12)
                }
                VStack(spacing: 6) {
                    Text("Every site deserves a Dock icon.")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .multilineTextAlignment(.center)
                    Text("Pick a site and it becomes a calm little app: no tabs, no title bar, just the page.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                }
                Button { adding = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                        Text("Add Any Site")
                    }
                }
                .buttonStyle(GlowButtonStyle())
                .focusEffectDisabled()
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Or tap one to start")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    suggestionChips(suggestions)
                }
                .frame(maxWidth: 640)
                .padding(.top, 22)
            }
            .padding(36)
            .frame(maxWidth: .infinity)
        }
    }

    private var summary: String {
        let docked = library.sites.filter(library.hasApp).count
        let count = library.sites.count == 1 ? "1 site" : "\(library.sites.count) sites"
        return docked == 0 ? count : "\(count) · \(docked) in the Dock"
    }

    private func notAdded(_ suggestions: [SiteSuggestion]) -> [SiteSuggestion] {
        let hosts = Set(library.sites.map(\.host))
        return suggestions.filter { Site.normalized($0.url).map { !hosts.contains($0.host() ?? "") } ?? false }
    }

    /// Nine sites to add: the ones visited most in the person's browsers, topped up with good picks.
    private var suggestions: [SiteSuggestion] {
        let recent = notAdded(library.recent)
        let recentHosts = Set(recent.compactMap { Site.normalized($0.url)?.host() })
        let picks = notAdded(SiteSuggestion.all).filter { !recentHosts.contains(Site.normalized($0.url)?.host() ?? "") }
        return Array((recent + picks).prefix(9))
    }

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(.secondary)
    }

    private func suggestionChips(_ suggestions: [SiteSuggestion]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 178), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(suggestions) { suggestion in
                SuggestionChip(suggestion: suggestion) {
                    let site = Site(name: suggestion.name, url: suggestion.url)
                    withAnimation(.spring(duration: 0.35)) { library.save(site) }
                    library.fetchIcon(for: site)
                }
            }
        }
    }

    @ViewBuilder
    private func menu(for site: Site) -> some View {
        Button("Open") { open(site) }
        Divider()
        Button(library.hasApp(site) ? "Update Dock App" : "Make Dock App") { library.makeApp(for: site) }
            .disabled(library.making.contains(site.id))
        if library.hasApp(site) {
            Button("Show App in Finder") { library.revealApp(for: site) }
        }
        Divider()
        Button("Edit…") { editing = site }
        Divider()
        Button("Remove…", role: .destructive) { removing = site }
    }

    private func open(_ site: Site) {
        openWindow(id: "site", value: site.id)
    }
}

/// One site as an app icon with its name under it.
struct SiteTile: View {
    let site: Site
    @ObservedObject private var library = Library.shared
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                SiteIconView(site: site, size: 84)
                    .overlay {
                        if Library.shared.making.contains(site.id) {
                            ProgressView().controlSize(.small)
                                .padding(10)
                                .background(.regularMaterial, in: Circle())
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if Library.shared.hasApp(site) {
                            Image(systemName: "dock.rectangle")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(Color.accentColor, in: Circle())
                                .help("Has its own Dock app")
                        }
                    }
                    .scaleEffect(hovering ? 1.06 : 1)
                    .shadow(color: .black.opacity(hovering ? 0.18 : 0.08), radius: hovering ? 8 : 3, y: hovering ? 4 : 1)
                Text(site.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(site.host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25), value: hovering)
        .help("Open \(site.name)")
    }
}

/// The site's icon, or its first letter on a colored tile until it has one.
struct SiteIconView: View {
    let site: Site
    let size: CGFloat

    var body: some View {
        if let image = Library.shared.icon(for: site) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(color.gradient)
                .frame(width: size * 0.82, height: size * 0.82)
                .overlay {
                    Text(String(site.name.prefix(1)).uppercased())
                        .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(width: size, height: size)
        }
    }

    private var color: Color {
        let palette: [Color] = [.blue, .indigo, .purple, .pink, .red, .orange, .teal, .green, .mint, .cyan]
        let sum = site.host.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }
}

/// A popular site to add in one click: its real logo and name on a frosted chip.
struct SuggestionChip: View {
    let suggestion: SiteSuggestion
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                FaviconView(url: suggestion.url, size: 18, fromHistory: suggestion.fromHistory)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white))
                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                Text(suggestion.name)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(hovering ? AnyShapeStyle(.white) : AnyShapeStyle(Theme.violet))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(hovering ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.violet.opacity(0.12))))
                    .rotationEffect(.degrees(hovering ? 90 : 0))
            }
            .padding(.leading, 6)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(scheme == .dark ? Color.white.opacity(hovering ? 0.12 : 0.07) : Color.white.opacity(hovering ? 0.95 : 0.7))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(hovering ? AnyShapeStyle(Theme.gradient.opacity(0.6)) : AnyShapeStyle(Color.primary.opacity(0.06)), lineWidth: 1)
            }
            .shadow(color: Theme.violet.opacity(hovering ? 0.18 : 0.05), radius: hovering ? 12 : 4, y: hovering ? 5 : 2)
            .offset(y: hovering ? -2 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.3, bounce: 0.35), value: hovering)
        .help("Add \(suggestion.name)")
    }
}

/// Presses in a touch, for buttons that draw their own look.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.18), value: configuration.isPressed)
    }
}
