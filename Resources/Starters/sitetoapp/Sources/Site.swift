import SwiftUI

/// A website kept as an app of its own.
struct Site: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var url: String
    /// File name of its icon in LampStore.folder/Icons.
    var iconFile: String?
    /// Where its own Dock app was made, once it has one.
    var appPath: String?
    var added: Date?

    init(id: UUID = UUID(), name: String, url: String, iconFile: String? = nil, appPath: String? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.iconFile = iconFile
        self.appPath = appPath
        self.added = Date()
    }

    var address: URL? { Site.normalized(url) }
    var host: String { address?.host() ?? url }

    /// "meet.google.com" or "https://…" as a URL that loads.
    static func normalized(_ text: String) -> URL? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), let host = url.host(), host.contains(".") else { return nil }
        return url
    }

    /// The last two labels of a host ("google.com" for "meet.google.com"), to tell the site's own pages from others.
    static func baseDomain(_ host: String?) -> String {
        guard let host else { return "" }
        let parts = host.lowercased().split(separator: ".")
        let short: Set<String> = ["co", "com", "org", "net", "ac", "gov"]
        if parts.count >= 3, short.contains(String(parts[parts.count - 2])), parts.last!.count == 2 {
            return parts.suffix(3).joined(separator: ".")
        }
        return parts.suffix(2).joined(separator: ".")
    }
}

/// Sites people often want as apps, offered when adding one.
struct SiteSuggestion: Identifiable {
    let name: String
    let url: String
    /// Found in the person's own browsing: its address stays between this Mac and the site itself.
    var fromHistory = false
    var id: String { url }

    /// Good sites to start with: ones people keep open all day that have no Mac app of their own.
    static let all: [SiteSuggestion] = [
        .init(name: "Google Meet", url: "https://meet.google.com"),
        .init(name: "Gmail", url: "https://mail.google.com"),
        .init(name: "Google Calendar", url: "https://calendar.google.com"),
        .init(name: "Intercom", url: "https://app.intercom.com"),
        .init(name: "X", url: "https://x.com"),
        .init(name: "Facebook", url: "https://www.facebook.com"),
        .init(name: "Instagram", url: "https://www.instagram.com"),
        .init(name: "LinkedIn", url: "https://www.linkedin.com"),
        .init(name: "Amazon", url: "https://www.amazon.com"),
        .init(name: "YouTube", url: "https://www.youtube.com"),
        .init(name: "Google Docs", url: "https://docs.google.com"),
        .init(name: "Reddit", url: "https://www.reddit.com"),
    ]

    /// Sites whose makers already have a Mac app, so a site app would only be second best.
    static func hasDesktopApp(_ host: String) -> Bool {
        let base = Site.baseDomain(host)
        let apps: Set<String> = ["whatsapp.com", "chatgpt.com", "openai.com", "claude.ai", "anthropic.com", "slack.com",
                                 "notion.so", "notion.com", "figma.com", "linear.app", "zoom.us", "discord.com",
                                 "spotify.com", "telegram.org", "signal.org", "dropbox.com", "1password.com",
                                 "todoist.com", "trello.com", "microsoft.com", "office.com", "live.com", "skype.com",
                                 "github.com", "messenger.com", "evernote.com", "obsidian.md", "cursor.com", "perplexity.ai",
                                 "apple.com", "icloud.com"]
        return apps.contains(base)
    }
}

/// When this copy of the app was made as one site's own app, that site; nil in the catalog itself.
enum SiteMode {
    static let site: Site? = {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let url = info["LampSiteURL"] as? String,
              let id = (info["LampSiteID"] as? String).flatMap(UUID.init(uuidString:)) else { return nil }
        return Site(id: id, name: info["LampSiteName"] as? String ?? "Site", url: url)
    }()
}
