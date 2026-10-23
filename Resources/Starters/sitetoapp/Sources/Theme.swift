import SwiftUI

/// Site-to-App's look: a sky of soft blues and violets behind the catalog, the color a website turns as it
/// becomes an app.
enum Theme {
    static let sky = Color(light: 0x5AA9FF, dark: 0x3D7BD9)
    static let violet = Color(light: 0x9B7BFF, dark: 0x7458D6)
    static let peach = Color(light: 0xFFB38A, dark: 0xC9785A)

    static var gradient: LinearGradient {
        LinearGradient(colors: [sky, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// The catalog's backdrop: soft glows of the palette over the window's own background.
struct SkyBackdrop: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            Circle()
                .fill(Theme.sky.opacity(0.22))
                .frame(width: 520, height: 520)
                .blur(radius: 120)
                .offset(x: -260, y: -200)
            Circle()
                .fill(Theme.violet.opacity(0.18))
                .frame(width: 480, height: 480)
                .blur(radius: 120)
                .offset(x: 280, y: 160)
            Circle()
                .fill(Theme.peach.opacity(0.14))
                .frame(width: 360, height: 360)
                .blur(radius: 110)
                .offset(x: 180, y: -240)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        func rgb(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? rgb(dark) : rgb(light)
        })
    }
}

/// A site's real logo, from Google's favicon service, for the suggestions.
struct FaviconView: View {
    let url: String
    var size: CGFloat = 18
    /// A site from the person's own browsing, whose logo is asked of the site alone.
    var fromHistory = false
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: "globe").resizable().foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .task(id: url) { image = await FaviconCache.image(for: url, askingGoogle: !fromHistory) }
    }
}

/// Logos fetched once per run.
@MainActor
enum FaviconCache {
    static var images: [String: NSImage] = [:]

    /// Google's favicon service draws the well-known sites Lamp suggests. A site found in the person's browsing
    /// is asked for its own icon instead: sending its name to anyone else would tell them where the person goes.
    static func image(for site: String, askingGoogle: Bool = true) async -> NSImage? {
        if let cached = images[site] { return cached }
        guard let host = Site.normalized(site)?.host() else { return nil }
        let sources = askingGoogle
            ? ["https://www.google.com/s2/favicons?domain=\(host)&sz=64"]
            : ["https://\(host)/apple-touch-icon.png", "https://\(host)/favicon.ico"]
        for source in sources {
            guard let url = URL(string: source) else { continue }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = NSImage(data: data) else {
                    print("Favicon: not an image for \(host) (\(data.count) bytes)")
                    continue
                }
                images[site] = image
                return image
            } catch {
                print("Favicon: \(host) failed: \(error.localizedDescription)")
            }
        }
        return nil
    }
}
