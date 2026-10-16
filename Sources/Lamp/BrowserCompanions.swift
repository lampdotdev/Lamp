import AppKit
import CryptoKit

/// Each app's sidebar in Chrome. An app's sidebar is a page the app serves itself (`LampBrowser.startPage`), and
/// Lamp only lists where it is (`surface-list`). An app built before pages publishes its sidebar as data instead
/// (`LampBrowser.start`), which this keeps and passes to the extension, and the clicks back. Every Chrome tab has a
/// sidebar of its own, so what one page prepared never shows on another: the app is told which tabs are open on it
/// and publishes a surface for each. Lamp's own preview of a sidebar (`BrowserPreview`) is one more tab, so the
/// builder tries what the person will use.
@MainActor
final class BrowserCompanions {
    static let shared = BrowserCompanions()

    struct Surface: Codable, Equatable {
        struct Section: Codable, Equatable { var title: String; var text: String; var items: [String]? }
        struct Field: Codable, Equatable { var id: String; var label: String; var value: String; var lines: Int? }
        struct Action: Codable, Equatable { var id: String; var label: String; var readsPage: Bool; var readsSelection: Bool? }
        var title: String
        var detail: String
        var sections: [Section]
        var fields: [Field]
        var actions: [Action]
        var busy: Bool
        var valid: Bool {
            title.count <= 120 && detail.count <= 1000 && sections.count <= 20 && fields.count <= 12 && actions.count <= 8
            && sections.allSatisfy { $0.title.count <= 120 && $0.text.count <= 16000 && ($0.items ?? []).count <= 60 && ($0.items ?? []).allSatisfy { $0.count <= 1000 } }
            && fields.allSatisfy { !$0.id.isEmpty && $0.id.count <= 60 && $0.label.count <= 120 && $0.value.count <= 4000 && (1...12).contains($0.lines ?? 1) }
            && actions.allSatisfy { !$0.id.isEmpty && $0.id.count <= 60 && $0.label.count <= 120 && !($0.readsPage && $0.readsSelection == true) }
            && Set(actions.map(\.id)).count == actions.count && Set(fields.map(\.id)).count == fields.count
        }
    }

    /// What an app says about its sidebar in `browser.json` at its root, written by the builder: the sentence shown
    /// on a page that fits it, what fits, and the words of its right-click item if the builder gave it one. Lamp reads
    /// it to list the app in the sidebar before it's running and hands the fits to Chrome, which lights Lamp's icon on
    /// a matching page without the extension reading it.
    struct Declaration: Codable, Equatable {
        struct Fit: Codable, Equatable {
            var site: String?; var path: String?; var selector: String?
            /// Whether a page at this address can fit, before its selector (if any) is looked for. The path is
            /// compared as Chrome compares it, still percent-encoded and with its last slash.
            func fitsAddress(_ url: URL) -> Bool {
                guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
                if let site, host != site && !host.hasSuffix("." + site) { return false }
                if let path, !url.path(percentEncoded: true).hasPrefix(path) { return false }
                return true
            }
        }
        var offer: String
        var fits: [Fit]
        var menu: String?

        /// The fits Chrome can show the right-click item on: it decides from the page's address alone before the
        /// menu opens, so a fit that needs a selector can't be checked there, and a `*` in a path would be a wildcard
        /// to Chrome where the fit means it literally.
        var menuFits: [Fit] { fits.filter { $0.site != nil && $0.selector == nil && !($0.path ?? "").contains("*") } }

        static let file = "browser.json"
        static func url(_ project: LampProject) -> URL { project.dir.appendingPathComponent(file) }

        /// A declaration from a file elsewhere (a shared app being opened), through the same checks; nil when it fails.
        static func load(_ file: URL) -> Declaration? {
            guard let data = try? Data(contentsOf: file), let value = try? JSONDecoder().decode(Declaration.self, from: data),
                  value.problem == nil else { return nil }
            return value
        }
        /// As Lamp writes it: only the fields it reads, whatever else the file it came from held.
        static func encoded(_ declaration: Declaration) throws -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return try encoder.encode(declaration)
        }

        /// The declaration, or why it can't be used: said to the builder when it looks at the sidebar.
        static func read(_ project: LampProject) -> Result<Declaration, Problem> {
            guard let data = try? Data(contentsOf: url(project)) else { return .failure(Problem("There's no browser.json at the app's root.")) }
            guard let value = try? JSONDecoder().decode(Declaration.self, from: data) else {
                return .failure(Problem("browser.json isn't {\"offer\": \"…\", \"fits\": [{\"site\": \"…\", \"path\": \"…\", \"selector\": \"…\"}]}."))
            }
            return value.problem.map { .failure(Problem($0)) } ?? .success(value)
        }
        static func load(_ project: LampProject) -> Declaration? { try? read(project).get() }

        var problem: String? {
            let offer = offer.trimmingCharacters(in: .whitespacesAndNewlines)
            if offer.isEmpty || offer.count > 80 { return "browser.json's offer must be one short sentence (up to 80 characters)." }
            if fits.isEmpty || fits.count > 30 { return "browser.json needs between 1 and 30 fits." }
            for fit in fits {
                if fit.site == nil && fit.selector == nil { return "Each fit in browser.json needs a site, a selector or both: one with neither would fit every page." }
                if let site = fit.site, !Self.isSite(site) { return "\"\(site)\" in browser.json isn't a site: give a host name like example.com, without https:// or a path." }
                if let path = fit.path, !path.hasPrefix("/") || path.count > 200 || path.contains(where: \.isWhitespace) { return "A fit's path in browser.json starts with / and has no spaces." }
                if let selector = fit.selector, let trouble = Self.selectorProblem(selector) { return trouble }
            }
            if let menu {
                let words = menu.trimmingCharacters(in: .whitespacesAndNewlines)
                if words.isEmpty || words.count > 40 || words.contains(where: \.isNewline) { return "browser.json's menu is a few words on one line (up to 40 characters)." }
                if menuFits.isEmpty { return "browser.json's menu shows only on pages a fit names by site (and a path without *) and no selector, and there's none: add one, or leave the menu out." }
            }
            return nil
        }
        static func isSite(_ site: String) -> Bool {
            site.count <= 253 && site.range(of: #"^[a-z0-9-]+(\.[a-z0-9-]+)+$"#, options: .regularExpression) != nil
        }
        /// Chrome matches only one compound selector per fit (no spaces, `>`, `+`, `~` or commas between parts).
        static func selectorProblem(_ selector: String) -> String? {
            if selector.isEmpty || selector.count > 200 { return "A selector in browser.json must be under 200 characters." }
            var bracket = 0, quote: Character?
            for c in selector {
                if let q = quote { if c == q { quote = nil }; continue }
                switch c {
                case "\"", "'": quote = c
                case "[", "(": bracket += 1
                case "]", ")": bracket -= 1
                case _ where c.isWhitespace || ">+~,".contains(c):
                    return "\"\(selector)\" in browser.json combines selectors; Chrome only takes one compound selector per fit, like div.recipe-card or [itemtype*=\"schema.org/Recipe\"]. Give each its own fit."
                default: break
                }
            }
            return bracket == 0 && quote == nil ? nil : "\"\(selector)\" in browser.json isn't a complete selector."
        }
    }
    struct Problem: Error { let message: String; init(_ message: String) { self.message = message } }

    private struct Registration {
        var instance: String
        var boot: String
        var name: String
        /// By tab; "" is what a tab the app hasn't drawn for yet shows.
        var surfaces: [String: Surface]
        var revisions: [String: String]
        var seen: Date
        var event: [String: Any]?
        var eventDate: Date?
        var accepted: [String] = []
        /// The tabs the app drew for in its last heartbeat, as against ones shown the shared surface.
        var drawn: Set<String> = []
        /// Revisions a click was handled under, with the tab it came from ("tab revision"). Never valid again on that
        /// tab, even once the app stops drawing for it; another tab that was shown the same revision keeps it.
        var spent: [String] = []
    }
    private var apps: [String: Registration] = [:]
    /// The tabs each app's sidebar is open in, by when each was last drawn.
    private var viewed: [String: [String: Date]] = [:]
    /// How long a tab counts as open after its sidebar last asked what to show (shorter in tests).
    var tabLifetime: TimeInterval = 10

    /// An app's heartbeat (`/browser/surface`): what its sidebar shows, by tab. Answered with the next click for
    /// it, if any, and the tabs it should draw for.
    func exchange(_ body: [String: Any], app: LampProject) -> (Int, [String: Any]) {
        let decoder = JSONDecoder()
        func surface(_ raw: Any?) -> Surface? {
            guard let raw, let data = try? JSONSerialization.data(withJSONObject: raw), data.count <= 100_000,
                  let surface = try? decoder.decode(Surface.self, from: data), surface.valid else { return nil }
            return surface
        }
        guard app.platform.hasMac, let boot = body["boot"] as? String, UUID(uuidString: boot) != nil,
              let main = surface(body["surface"]) else {
            return (400, ["error": "This sidebar couldn't be drawn."])
        }
        var surfaces = ["": main]
        let tabbed = body["surfaces"] as? [String: Any] ?? [:]
        guard tabbed.count <= 16 else { return (400, ["error": "This sidebar couldn't be drawn."]) }
        for (tab, raw) in tabbed {
            guard tab.count <= 40, !tab.isEmpty, let one = surface(raw) else { return (400, ["error": "This sidebar couldn't be drawn."]) }
            surfaces[tab] = one
        }
        var entry = apps[app.id]
        if entry?.instance != app.instance || entry?.boot != boot {
            entry = Registration(instance: app.instance, boot: boot, name: app.name, surfaces: [:], revisions: [:], seen: Date())
        }
        var next = entry!
        // A tab's revision changes with what it shows, so a button drawn before can't act on what's there now.
        // A tab drawn for the first time keeps the revision it was shown under, when it shows the same thing.
        var revisions: [String: String] = [:]
        for (tab, shown) in surfaces {
            let before = next.surfaces[tab] ?? (tab.isEmpty ? nil : next.surfaces[""])
            let kept = next.revisions[tab] ?? (tab.isEmpty ? nil : next.revisions[""])
            revisions[tab] = before == shown ? (kept ?? UUID().uuidString) : UUID().uuidString
        }
        next.surfaces = surfaces; next.revisions = revisions; next.seen = Date(); next.name = app.name
        next.drawn = Set(tabbed.keys)
        if let ack = body["ack"] as? String, ack == next.event?["id"] as? String { finish(&next) }
        if let date = next.eventDate, Date().timeIntervalSince(date) > 240 { finish(&next) }
        apps[app.id] = next
        var reply: [String: Any] = ["tabs": liveTabs(app.id)]
        if let event = next.event { reply["event"] = event }
        return (200, reply)
    }

    /// A handled or expired click: its tab gets a new revision, so the buttons it was pressed on are spent.
    private func finish(_ entry: inout Registration) {
        let tab = entry.event?["tab"] as? String ?? ""
        if let used = entry.event?["revision"] as? String {
            entry.spent = Array((entry.spent + [tab + " " + used]).suffix(256))
            // A tab the app hadn't drawn for was shown the shared surface's revision: that one is spent too.
            if entry.revisions[""] == used { entry.revisions[""] = UUID().uuidString }
        }
        entry.event = nil; entry.eventDate = nil
        entry.revisions[tab] = UUID().uuidString
        if tab != "" && entry.surfaces[tab] == nil { entry.surfaces[tab] = entry.surfaces[""] }
    }

    private func liveTabs(_ app: String) -> [String] {
        let now = Date()
        viewed[app] = viewed[app]?.filter { now.timeIntervalSince($0.value) < tabLifetime }
        return Array((viewed[app] ?? [:]).sorted { $0.value > $1.value }.prefix(16).map(\.key)).sorted()
    }

    func isLive(_ project: LampProject) -> Bool { live(project) != nil }
    private func live(_ project: LampProject) -> Registration? {
        guard let entry = apps[project.id], entry.instance == project.instance, Date().timeIntervalSince(entry.seen) < 6 else { return nil }
        return entry
    }

    /// The apps with a sidebar: every installed Mac app that declares one, open or not.
    func listed(_ projects: [LampProject]) -> [(project: LampProject, declaration: Declaration)] {
        projects.compactMap { project in
            guard project.platform.hasMac, FileManager.default.fileExists(atPath: project.installedURL.path),
                  let declaration = Declaration.load(project) else { return nil }
            return (project, declaration)
        }.sorted { $0.project.name.localizedStandardCompare($1.project.name) == .orderedAscending }
    }

    /// Changes whenever an app's fits or right-click item do, so the extension knows when to give Chrome new ones.
    func fitsKey(_ projects: [LampProject]) -> String {
        let all = listed(projects).map { item in
            [item.project.id: item.declaration.fits.map { [$0.site ?? "", $0.path ?? "", $0.selector ?? ""] } + [["menu", item.declaration.menu ?? ""]]]
        }
        let data = (try? JSONSerialization.data(withJSONObject: all, options: [.sortedKeys])) ?? Data()
        return SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// The tab a request is about, as the app sees it: an opaque name, the same for one tab in one Chrome profile.
    /// `run` is Chrome's current run: tab ids start again after a restart, and a new tab must not get an old one's draft.
    static func tabKey(profile: String, run: String, tab: Any?) -> String? {
        guard let number = (tab as? Int) ?? (tab as? NSNumber)?.intValue ?? (tab as? String).flatMap(Int.init), number >= 0 else { return nil }
        return "t" + SHA256.hash(data: Data("\(profile):\(run):\(number)".utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    /// What a sidebar (the extension's or Lamp's preview) asks: the list of apps, one app's surface for a tab,
    /// opening an app, or a click. `tab` is already the opaque key.
    func native(_ body: [String: Any], tab: String?, projects: [LampProject]) -> [String: Any] {
        let op = body["op"] as? String
        if op == "surface-list" {
            return ["apps": listed(projects).map { item in
                var page: [String: Any] = [:]
                // An app with a page of its own serves it; Chrome's sidebar frames it, and keeps where for when Lamp is closed.
                if Template.hasSidebarPage(item.project) {
                    page = ["urls": Template.sidebarURLs(for: item.project), "key": Template.sidebarKey(for: item.project),
                            "reads": Template.sidebarReads(item.project)]
                }
                return ["id": item.project.id, "name": item.project.name, "offer": item.declaration.offer, "running": isLive(item.project), "page": page,
                 "menu": item.declaration.menu ?? "",
                 "fits": item.declaration.fits.map { fit in
                     var value: [String: String] = [:]
                     if let site = fit.site { value["site"] = site }
                     if let path = fit.path { value["path"] = path }
                     if let selector = fit.selector { value["selector"] = selector }
                     return value
                 }] as [String: Any]
            }]
        }
        guard let id = body["app"] as? String, let project = projects.first(where: { $0.id == id && $0.platform.hasMac }) else {
            return ["error": "That app isn't on this Mac any more."]
        }
        if op == "surface-open" {
            if !isLive(project), listed([project]).count == 1 { Store.shared.openForSidebar(project) }
            return ["opening": true]
        }
        guard let tab, !tab.isEmpty else { return ["error": "Click Lamp in Chrome’s toolbar, then try again."] }
        guard var entry = live(project) else { return ["running": false] }
        if op == "surface-view" {
            viewed[id, default: [:]][tab] = Date()
            let surface = entry.surfaces[tab] ?? entry.surfaces[""]!
            return ["surface": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(surface))) ?? [:],
                    "revision": revision(entry, tab), "busy": entry.event != nil, "running": true]
        }
        guard op == "surface-action", let eventID = body["id"] as? String, UUID(uuidString: eventID) != nil else {
            return ["error": "Unknown action."]
        }
        if entry.accepted.contains(eventID) { return ["accepted": true] }
        let surface = entry.surfaces[tab] ?? entry.surfaces[""]!
        guard let shown = body["revision"] as? String, shown == revision(entry, tab), !entry.spent.contains(tab + " " + shown), !surface.busy, entry.event == nil,
              let action = surface.actions.first(where: { $0.id == body["action"] as? String }),
              let fields = body["fields"] as? [String: String], fields.count <= 12,
              fields.allSatisfy({ key, value in surface.fields.contains { $0.id == key } && value.count <= 4000 }) else {
            return ["error": "The app changed. Wait a moment, then try again."]
        }
        var event: [String: Any] = ["id": eventID, "tab": tab, "action": action.id, "fields": fields, "revision": shown]
        if action.readsPage || action.readsSelection == true {
            guard let page = body["page"] as? [String: Any], let url = page["url"] as? String,
                  let u = URLComponents(string: url), u.user == nil, u.password == nil, u.scheme == "https",
                  url.count <= 4000, let text = page["text"] as? String, text.utf8.count <= 100_000,
                  let title = page["title"] as? String, title.count <= 1000,
                  action.readsSelection != true || (page["scope"] as? String == "selection" && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) else {
                return ["error": "That page couldn't be read. Try again on a website."]
            }
            event["page"] = ["url": url, "text": text, "title": title, "scope": action.readsSelection == true ? "selection" : "page",
                             "truncated": page["truncated"] as? Bool ?? false] as [String: Any]
        } else if body["page"] != nil { return ["error": "This button doesn't read the page."] }
        entry.event = event; entry.eventDate = Date(); entry.accepted.append(eventID)
        entry.accepted = Array(entry.accepted.suffix(64)); apps[id] = entry
        return ["accepted": true]
    }

    private func revision(_ entry: Registration, _ tab: String) -> String {
        entry.surfaces[tab] != nil ? entry.revisions[tab] ?? "" : entry.revisions[""] ?? ""
    }

    /// Waits for a click from `tab` to be handled (an AI answer can take a minute), keeping the tab open meanwhile so
    /// the app goes on drawing for it, then for the app to draw that tab once more, so what's shown next is what the
    /// click led to. False when the app hasn't finished within `limit` or went away.
    func awaitHandled(_ eventID: String, in project: LampProject, tab: String, limit: TimeInterval) async -> Bool {
        let asked = Date()
        func stillOpen() { if live(project) != nil { viewed[project.id, default: [:]][tab] = Date() } }
        while !isHandled(eventID, in: project) {
            guard Date().timeIntervalSince(asked) < limit else { return false }
            stillOpen()
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard live(project) != nil else { return false }
        // The next heartbeats bring the tab's own surface; a beat of grace for an app that draws one for every tab.
        let settled = Date()
        while Date().timeIntervalSince(settled) < 3, live(project).map({ !$0.drawn.contains(tab) }) ?? false {
            stillOpen()
            try? await Task.sleep(for: .milliseconds(250))
        }
        stillOpen()
        try? await Task.sleep(for: .milliseconds(600))
        return true
    }

    /// Whether the click with this id has been handled by the app (or dropped), for Lamp's preview to wait on.
    func isHandled(_ eventID: String, in project: LampProject) -> Bool {
        guard let entry = live(project) else { return true }
        return entry.event?["id"] as? String != eventID
    }
}
