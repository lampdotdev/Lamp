import SwiftUI

/// Team logos, fetched from ESPN only when a team is first shown, shrunk to a small size and kept on disk
/// so each logo is downloaded once.
@MainActor
final class LogoCache {
    static let shared = LogoCache()

    private var images: [URL: NSImage] = [:]
    private var loading: [URL: Task<NSImage?, Never>] = [:]
    private let folder: URL = {
        let url = LampStore.folder.appendingPathComponent("logos", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    func cached(_ url: URL) -> NSImage? { images[url] }

    func image(for url: URL) async -> NSImage? {
        if let image = images[url] { return image }
        if let task = loading[url] { return await task.value }
        let file = folder.appendingPathComponent(fileName(url))
        let task = Task<NSImage?, Never> {
            if let image = NSImage(contentsOf: file) { return image }
            // ESPN's image service hands back a small copy; the full logo is the fallback.
            for source in [small(url), url].compactMap({ $0 }) {
                guard let (data, response) = try? await URLSession.shared.data(from: source),
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      let image = NSImage(data: data) else { continue }
                try? data.write(to: file)
                return image
            }
            return nil
        }
        loading[url] = task
        let image = await task.value
        loading[url] = nil
        if let image { images[url] = image }
        return image
    }

    private func small(_ url: URL) -> URL? {
        guard url.host?.contains("espncdn.com") == true, !url.path.hasPrefix("/combiner") else { return nil }
        return URL(string: "https://a.espncdn.com/combiner/i?img=\(url.path)&w=80&h=80")
    }

    private func fileName(_ url: URL) -> String {
        if let query = url.query, !query.isEmpty {
            return query.map { $0.isLetter || $0.isNumber || $0 == "." ? String($0) : "-" }.joined() + ".png"
        }
        return url.path.split(separator: "/").suffix(3).joined(separator: "-")
    }
}

/// A team's logo, or its abbreviation in a soft circle until (or unless) the logo arrives.
struct TeamLogo: View {
    let team: Team
    var size: CGFloat = 18

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image = image ?? team.logo.flatMap({ LogoCache.shared.cached($0) }) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                Circle()
                    .fill(team.tint.opacity(0.22))
                    .overlay(
                        Text(team.abbr.prefix(3))
                            .font(.system(size: size * 0.32, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: team.logo) {
            guard let url = team.logo else { return }
            image = await LogoCache.shared.image(for: url)
        }
    }
}

extension Team {
    /// The team's own color from ESPN, or a neutral gray.
    var tint: Color {
        guard let hex = color, hex.count == 6, let value = Int(hex, radix: 16) else { return .gray }
        return Color(red: Double((value >> 16) & 0xFF) / 255,
                     green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }
}

/// Where a TV channel's or streaming service's logo comes from: the icon of its website, through Google's
/// icon service, fetched the first time it's shown.
enum NetworkLogos {
    static func domain(for name: String) -> String? {
        let n = name.lowercased()
        let table: [(String, String)] = [
            ("espn", "espn.com"), ("abc", "abc.com"), ("peacock", "peacocktv.com"), ("nbc", "nbc.com"),
            ("cbs sports", "cbssports.com"), ("cbssn", "cbssports.com"), ("paramount", "paramountplus.com"),
            ("cbs", "cbs.com"), ("fs1", "foxsports.com"), ("fs2", "foxsports.com"), ("fox one", "foxone.com"),
            ("fox", "fox.com"), ("tnt", "tntsports.com"), ("tbs", "tntsports.com"), ("trutv", "tntsports.com"),
            ("hbo", "max.com"), ("max", "max.com"), ("usa", "usanetwork.com"), ("btn", "btn.com"),
            ("big ten", "btn.com"), ("secn", "secnetwork.com"), ("sec network", "secnetwork.com"),
            ("accn", "theacc.com"), ("acc network", "theacc.com"), ("prime", "primevideo.com"),
            ("amazon", "primevideo.com"), ("apple", "tv.apple.com"), ("mls season pass", "tv.apple.com"),
            ("netflix", "netflix.com"), ("youtube", "youtube.com"), ("hulu", "hulu.com"), ("sling", "sling.com"),
            ("fubo", "fubo.tv"), ("directv", "directv.com"), ("nba", "nba.com"), ("league pass", "nba.com"),
            ("nfl", "nfl.com"), ("mlb", "mlb.com"), ("nhl", "nhl.com"), ("the cw", "cwtv.com"), ("cw", "cwtv.com"),
            ("ion", "iontelevision.com"), ("golf", "golfchannel.com"), ("tennis channel", "tennischannel.com"),
        ]
        return table.first { key, _ in
            key.count <= 3 ? n.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { $0.hasPrefix(key) } || n == key
                           : n.contains(key)
        }?.1
    }

    static func url(for name: String) -> URL? {
        domain(for: name).flatMap { URL(string: "https://www.google.com/s2/favicons?domain=\($0)&sz=64") }
    }
}

/// A channel or service: its logo, and its name when `showName` (always when there's no logo).
struct NetworkBadge: View {
    let name: String
    var size: CGFloat = 13
    var showName = true

    @State private var image: NSImage?

    var body: some View {
        let url = NetworkLogos.url(for: name)
        HStack(spacing: 4) {
            if let image = image ?? url.flatMap({ LogoCache.shared.cached($0) }) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
            }
            if showName || url == nil {
                Text(name).lineLimit(1)
            }
        }
        .help(name)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .task(id: name) {
            guard let url else { return }
            image = await LogoCache.shared.image(for: url)
        }
    }
}

extension League {
    /// The league's logo on ESPN (college leagues share the NCAA's).
    var logoURL: URL? {
        let path: String
        switch self {
        case .nfl, .nba, .wnba, .nhl, .mlb: path = "i/teamlogos/leagues/500/\(rawValue).png"
        case .cfb, .mcbb, .wcbb: path = "i/espn/misc_logos/500/ncaa.png"
        case .epl: path = "i/leaguelogos/soccer/500/23.png"
        case .mls: path = "i/leaguelogos/soccer/500/19.png"
        case .ucl: path = "i/leaguelogos/soccer/500/2.png"
        case .laliga: path = "i/leaguelogos/soccer/500/15.png"
        }
        return URL(string: "https://a.espncdn.com/\(path)")
    }
}

/// A league's logo on a light rounded tile, like an app icon in System Settings.
struct LeagueLogo: View {
    let league: League
    var size: CGFloat = 26

    @State private var image: NSImage?

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24)
            .fill(Color.white)
            .overlay(RoundedRectangle(cornerRadius: size * 0.24).strokeBorder(.black.opacity(0.08)))
            .overlay {
                if let image = image ?? league.logoURL.flatMap({ LogoCache.shared.cached($0) }) {
                    Image(nsImage: image).resizable().interpolation(.high).scaledToFit().padding(size * 0.14)
                } else {
                    Text(league.short)
                        .font(.system(size: size * 0.24, weight: .bold).width(.condensed))
                        .foregroundStyle(.gray)
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
            .task(id: league) {
                guard let url = league.logoURL else { return }
                image = await LogoCache.shared.image(for: url)
            }
    }
}
