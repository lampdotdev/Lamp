import AppKit
import LampSidebarKit

/// The wishes Lamp comes with: working apps on a new person's desk from the start, to use as they are and to
/// change into their own, which shows what Lamp does better than a question about what to make. Each is made in a
/// repository of its own on GitHub (`StarterRepos`), and is a folder in Resources/Starters holding starter.md, which
/// is Lamp's (the wish's name, what the sidebar offers to change first, and where the starter lives: `repository:`
/// and the `commit:` of it this Lamp ships, moved on by `scripts/pull-starters.sh`), and `tree/`, that repository at
/// that commit, fetched by `scripts/fetch-starters.sh` before a build and never committed here: the app's code and
/// files, APP.md, lamp-app.json (what it is), credits.json, and in `.github/` the pictures (`preview.png`, the picture
/// the desk shows on hover, and `icon/`, the icon drawn once). A starter goes onto the desk as a repository opens
/// (`copy`: read as the import reads one, installed as the import installs one), once, on the first launch, and from
/// then on it's the person's like any other wish; a later Lamp with other starters gives those only to new people.
/// `scripts/check-starters.sh` type-checks them against this checkout's LampSupport.swift.
/// A release ships each one built as well (`PrebuiltStarters`), so it's ready before Apple's build tools are.
enum Starters {
    static let installedKey = "startersInstalled"

    struct Starter: Equatable {
        /// Resources/Starters/<folder>: starter.md, and the fetched tree.
        let folder: URL
        /// The repository as fetched at `commit`, laid out as Put on GitHub lays a wish out: what's copied to the desk.
        var tree: URL
        let name: String
        /// The first thing the app's chat offers: a line inviting a change, and three changes to choose from: a new look,
        /// a new thing it does and a new subject, to show how far the app can go.
        let offer: String
        let tweaks: [Tweak]
        /// What kind of wish it is (`kind:` in starter.md): a Mac app unless it says otherwise, as a game does.
        var kind: Platform = .mac
        /// Where the starter lives on GitHub (`repository:`), laid out as Put on GitHub lays a wish out
        /// (`StarterRepos`), and the commit there this Lamp ships (`commit:`).
        var repository: String? = nil
        var commit: String? = nil
    }

    /// Where Lamp's own starters live: a repository each, named as the starter's folder is, in the Lamp team's
    /// account on GitHub for them.
    static let account = "lampdotdev"
    static func repositoryName(of folder: String) -> String { folder }

    /// A starter's link on a copy's chain, with where the starter lives filled in from the starter this Lamp ships
    /// when the copy was made before starters named one: the address only, since the commit the copy came from isn't
    /// known (an update then merges against the version the copy began with).
    static func located(_ link: Credits.Remix) -> Credits.Remix {
        guard link.url == nil, let folder = link.starter,
              let shipped = bundled.first(where: { $0.folder.lastPathComponent == folder }), let url = shipped.repository else { return link }
        var link = link
        link.url = url
        return link
    }

    /// A change the chat offers, with the symbol on its tile (`- drop.fill: Add a water counter` in starter.md;
    /// the symbol may be left out).
    struct Tweak: Equatable {
        let title: String
        var symbol: String?
    }

    static var folder: URL? { Bundle.main.resourceURL?.appendingPathComponent("Starters") }

    static let treeFolder = "tree"
    /// Where a starter's repository keeps the pictures Lamp shows for it: the desk's preview and the drawn icon.
    static let picturesFolder = ".github"

    /// The starters this Lamp ships: those whose tree is here (one not fetched before the build isn't, and says so).
    static var bundled: [Starter] {
        guard let folder else { return [] }
        let folders = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return folders.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap(read).filter { runsHere($0.tree) }
    }

    /// Whether a starter runs on this Mac. One with a 3D scene needs macOS 15 (RealityView begins there), so on an
    /// older Mac it isn't put on the desk or offered, rather than greeting someone with a game that won't open; it's
    /// offered once the Mac is updated (`missing`).
    static func runsHere(_ tree: URL) -> Bool {
        Agent.Rules.scenes || !Template.importsRealityKit(tree.appendingPathComponent("Sources"))
    }

    /// Where a starter's drawn icon is in its tree (`iconFolder` under the pictures), and its preview.
    static func iconFolder(of starter: Starter) -> URL { starter.tree.appendingPathComponent(picturesFolder).appendingPathComponent(iconFolder) }
    static func preview(of starter: Starter) -> URL { starter.tree.appendingPathComponent(picturesFolder).appendingPathComponent("preview.png") }
    /// Its reel, when one's been recorded (scripts/showcase-starters.sh): reel.mp4, loop.webp and poster.png. Only its
    /// repository has it; Lamp's bundle leaves it out (build.sh).
    static func showcase(of starter: Starter) -> URL { starter.tree.appendingPathComponent(picturesFolder).appendingPathComponent(showcaseFolder) }
    static let showcaseFolder = "showcase"

    /// The icon a starter ships with, drawn from its icon.json (`StarterIconsTests`).
    static func icon(of starter: Starter) -> NSImage? {
        NSImage(contentsOf: iconFolder(of: starter).appendingPathComponent("icon.png"))
    }

    /// The starter's line saying what it is, from its manifest (the description a shared file carries).
    static func about(_ starter: Starter) -> String? {
        AppDescription.description(at: starter.tree.appendingPathComponent("lamp-app.json"))
    }

    /// Where an app keeps its starter.md once copied: Lamp's, beside meta.json, out of the agent's way.
    static func file(of project: LampProject) -> URL { project.dir.appendingPathComponent(".lamp/starter.md") }

    /// An app that came with Lamp. Its icon stays the one it came with, artwork and all: painting one would put an
    /// offer to set up pictures in the chat of an app the person hasn't asked anything of yet.
    static func isStarter(_ project: LampProject) -> Bool {
        FileManager.default.fileExists(atPath: file(of: project).path)
    }

    /// The picture a starter shipped with, for one copied before starters had pictures, or whose own was lost: found
    /// by the name in its starter.md, which stays the starter's even when the app is renamed.
    static func shippedPreview(of project: LampProject) -> URL? {
        guard let name = starter(of: project)?.name,
              let shipped = bundled.first(where: { $0.name == name }).map(preview(of:)),
              FileManager.default.fileExists(atPath: shipped.path) else { return nil }
        return shipped
    }

    /// The first time a starter is used, once: true then and never again. A starter that opens no window (the
    /// menu bar, a widget) has no sidebar to open its chat in, so its chat opens in Lamp then instead.
    static func isFirstUse(_ project: LampProject) -> Bool {
        let key = "startersUsed"
        var used = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        guard isStarter(project), used.insert(project.instance).inserted else { return false }
        UserDefaults.standard.set(Array(used).sorted(), forKey: key)
        return true
    }

    static func starter(of project: LampProject) -> Starter? {
        guard let text = try? String(contentsOf: file(of: project), encoding: .utf8) else { return nil }
        return parse(text, folder: project.dir)
    }

    /// Where a remix keeps the starter.md of the starter it was made from, when it was remixed with no change asked:
    /// its chat offers the same changes to try. Kept apart from starter.md, which says the app came with Lamp.
    static func suggestionsFile(of project: LampProject) -> URL { project.dir.appendingPathComponent(".lamp/starter-suggestions.md") }

    /// What an app's chat offers to change first: its starter's, or the one of the starter it was remixed from.
    static func suggestions(of project: LampProject) -> Starter? {
        if let starter = starter(of: project) { return starter }
        guard let text = try? String(contentsOf: suggestionsFile(of: project), encoding: .utf8) else { return nil }
        return parse(text, folder: project.dir)
    }

    /// The file holding what an app's chat offers to change first, for a remix of it to offer too.
    static func suggestionsSource(of project: LampProject) -> URL? {
        [file(of: project), suggestionsFile(of: project)].first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The starter in a folder: its starter.md, with its tree beside it. Nil without a tree (not fetched), which is
    /// said once, since a build without it ships a starter short.
    static func read(_ folder: URL) -> Starter? {
        guard let text = try? String(contentsOf: folder.appendingPathComponent("starter.md"), encoding: .utf8),
              let starter = parse(text, folder: folder) else { return nil }
        guard FileManager.default.fileExists(atPath: starter.tree.appendingPathComponent("lamp-app.json").path) else {
            NSLog("Lamp: the starter in %@ has no tree: run scripts/fetch-starters.sh", folder.lastPathComponent)
            return nil
        }
        return starter
    }

    /// starter.md's front matter: `name:`, `offer:`, and `tweaks:` followed by `  - ` lines. That's all it holds,
    /// so a few lines read it; anything else in the file is ignored.
    static func parse(_ text: String, folder: URL) -> Starter? {
        var lines = text.components(separatedBy: .newlines)[...]
        guard lines.first?.trimmed == "---" else { return nil }
        lines = lines.dropFirst()
        var name = "", offer = "", tweaks: [Tweak] = [], kind = Platform.mac, repository: String? = nil, commit: String? = nil
        for line in lines {
            let trimmed = line.trimmed
            if trimmed == "---" { break }
            if trimmed.hasPrefix("- ") {
                tweaks.append(tweak(unquoted(String(trimmed.dropFirst(2)))))
            } else if let colon = trimmed.firstIndex(of: ":") {
                let value = unquoted(String(trimmed[trimmed.index(after: colon)...]))
                switch trimmed[..<colon] {
                case "name": name = value
                case "offer": offer = value
                case "kind": kind = Targets.all.first { $0.platform.rawValue == value }?.platform ?? .mac
                case "repository": repository = Credits.validURL(value)
                case "commit": commit = Credits.validCommit(value)
                default: break
                }
            }
        }
        guard !name.isEmpty else { return nil }
        return Starter(folder: folder, tree: folder.appendingPathComponent(treeFolder), name: name, offer: offer, tweaks: tweaks, kind: kind,
                       repository: repository, commit: commit)
    }

    /// A symbol's name is lowercase words joined by dots, so `Group: by client` stays words.
    private static func tweak(_ text: String) -> Tweak {
        guard let colon = text.firstIndex(of: ":") else { return Tweak(title: text) }
        let symbol = String(text[..<colon])
        guard !symbol.isEmpty, symbol.allSatisfy({ $0.isLowercase || $0.isNumber || $0 == "." }) else { return Tweak(title: text) }
        return Tweak(title: unquoted(String(text[text.index(after: colon)...])), symbol: symbol)
    }

    /// The card a starter's chat opens with: its line, and its changes to click, each sent as the person's first
    /// request (`Store.answer`). Typing something else answers it as well.
    static func card(for starter: Starter) -> LogLine? {
        guard !starter.offer.isEmpty, !starter.tweaks.isEmpty else { return nil }
        let options = starter.tweaks.map { tweak in
            TalkCard.Option(title: tweak.title, symbol: tweak.symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil ? nil : $0 })
        }
        // Just the offer and its changes: in the wand's narrow panel a line under the offer saying what the wish is
        // pushed the changes down, and the offer already says it's theirs to change.
        let question = TalkCard.Question(question: starter.offer, options: options)
        let ask = TalkCard.Ask(layout: .steps, questions: [question], offer: true)
        return LogLine(kind: .ask, text: ask.text, ask: ask)
    }

    private static func unquoted(_ value: String) -> String {
        var value = value.trimmed
        if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }

    /// A starter's icon, drawn once from its icon.json (`StarterIconsTests`) and kept in its repository, so it's on the
    /// desk as soon as the starter is: the files `Icons.write` makes, which go into the app's .lamp folder, the
    /// icon.json they were drawn from, and the artwork (`artFile`).
    static let iconFolder = "icon"

    /// The icon's artwork, drawn once for the starter and kept so it's drawn again the same: a glass design, or a
    /// game's painting. In the app it goes where Lamp keeps an icon's artwork (`Icons.glassURL`, `Icons.artURL`), so a
    /// recolor or a redraw of the icon keeps it.
    static let glassFile = "art.json"
    static let artFile = "art.png"

    static func iconFiles(of project: LampProject) -> [URL] {
        [Icons.icnsURL(project), Icons.carURL(project), Icons.documentURL(project), Icons.previewURL(project), Icons.squareURL(project)]
    }

    /// Where the app keeps the icon.json its shipped icon was drawn from.
    private static func drawnFrom(_ project: LampProject) -> URL { project.dir.appendingPathComponent(".lamp/starter-icon.json") }

    /// Whether the icon the starter shipped with is still the one its icon.json describes: then it isn't drawn again.
    /// Once the agent or the person changes the design, it's drawn like any app's.
    static func hasShippedIcon(_ project: LampProject) -> Bool {
        guard let drawn = try? Data(contentsOf: drawnFrom(project)),
              let current = try? Data(contentsOf: Icons.specURL(project)),
              FileManager.default.fileExists(atPath: Icons.icnsURL(project).path) else { return false }
        return (try? JSONDecoder().decode(IconSpec.self, from: drawn)) == (try? JSONDecoder().decode(IconSpec.self, from: current))
    }

    /// Puts a starter into a scaffolded app the way a repository opens: its tree read as the import reads one
    /// (`RepoImport.open`: the code the review would read, never Lamp's own files) and installed as the import installs
    /// one (`Sharing.install`: code, files, notes, description, credits, licenses, the icon's design and artwork), with
    /// the starter named where it lives and at the commit this Lamp ships on the chain's link (what Update from GitHub…
    /// merges against and Send Changes Back… goes on top of). starter.md goes into .lamp; the drawn icon and the
    /// preview come from the tree's pictures. `package` stands in for the tree when given (a wish on this Mac being
    /// made a starter, `StarterRepos`).
    /// `replacing` puts the starter in place of a copy's own files (`Store.bringUp`), as an update replaces a wish's.
    static func copy(_ starter: Starter, into project: LampProject, package given: Sharing.Package? = nil, replacing: Bool = false) throws {
        let fm = FileManager.default
        let package = try given.map { given in
            var package = given
            package.credits = linked(RepoImport.naming(given.credits, repository: starter.repository, commit: starter.commit,
                                                       name: starter.name, identity: given.identity), to: starter)
            return package
        } ?? self.package(of: starter)
        defer { if given == nil { try? fm.removeItem(at: package.folder) } }
        try Sharing.install(package, into: project, replacing: replacing)
        try keepFile(of: starter, in: project)
        try Credits.arrive(linked(Credits.load(project), to: starter), in: project)
        let icon = iconFolder(of: starter)
        for made in iconFiles(of: project) {
            let shipped = icon.appendingPathComponent(made.lastPathComponent)
            guard fm.fileExists(atPath: shipped.path) else { continue }
            try? fm.removeItem(at: made)
            try fm.copyItem(at: shipped, to: made)
        }
        let spec = icon.appendingPathComponent("icon.json")
        if fm.fileExists(atPath: spec.path) {
            try? fm.removeItem(at: drawnFrom(project))
            try fm.copyItem(at: spec, to: drawnFrom(project))
        }
        if let drawn = Icons.load(project) {
            if let glass = GlassArt.load(from: icon.appendingPathComponent(glassFile)) {
                try Icons.save(glass, for: project, spec: drawn)
            } else if fm.fileExists(atPath: icon.appendingPathComponent(artFile).path) {
                let to = Icons.artURL(project, spec: drawn)
                try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.removeItem(at: to)
                try fm.copyItem(at: icon.appendingPathComponent(artFile), to: to)
            }
        }
        // A picture of it for the desk, since it's built out of sight and nobody has opened it yet: its first
        // launch replaces it.
        let preview = preview(of: starter)
        if fm.fileExists(atPath: preview.path) {
            try? fm.createDirectory(at: Runtime.macFolder(project), withIntermediateDirectories: true)
            if replacing { try? fm.removeItem(at: Runtime.previewURL(project)) }
            try? fm.copyItem(at: preview, to: Runtime.previewURL(project))
        }
    }

    /// The starter as a repository opens (`RepoImport.open`), its credits naming it where it lives and at the commit this
    /// Lamp ships. Its folder is the caller's to remove.
    static func package(of starter: Starter) throws -> Sharing.Package {
        var package = try RepoImport.open(folder: starter.tree)
        package.credits = linked(RepoImport.naming(package.credits, repository: starter.repository, commit: starter.commit,
                                                   name: starter.name, identity: package.identity), to: starter)
        return package
    }

    /// Credits with the starter as the chain's last link, where it lives and at the commit this Lamp ships. The link names
    /// the starter (`starter`), which is how a copy is known as one wherever its name goes.
    static func linked(_ credits: Credits?, to starter: Starter) -> Credits {
        var credits = credits ?? Credits()
        let link = Credits.Remix(name: starter.name, starter: starter.folder.lastPathComponent, url: starter.repository, commit: starter.commit)
        if let last = credits.remixOf.indices.last, credits.remixOf[last].sameLink(as: link) || credits.remixOf[last].url == nil {
            credits.remixOf[last] = link
        } else {
            credits = credits.remixed(from: link)
        }
        return credits
    }

    /// The starter's starter.md, as this Lamp ships it, into the copy's .lamp: its changes to offer, and its commit.
    static func keepFile(of starter: Starter, in project: LampProject) throws {
        try? FileManager.default.removeItem(at: file(of: project))
        try FileManager.default.copyItem(at: starter.folder.appendingPathComponent("starter.md"), to: file(of: project))
    }

    // MARK: Keeping copies current

    /// The starter a copy was made from, as this Lamp ships it: found by the name in its starter.md, which stays the
    /// starter's when the wish is renamed, else by the folder its link names. Nil for one this Lamp doesn't ship.
    static func shipped(of project: LampProject) -> Starter? {
        let bundled = self.bundled
        if let name = starter(of: project)?.name, let found = bundled.first(where: { $0.name == name }) { return found }
        guard let folder = Credits.load(project).remixOf.last(where: { $0.starter != nil })?.starter else { return nil }
        return bundled.first { $0.folder.lastPathComponent == folder }
    }

    /// The commit of its starter a copy has: its link's, else the one its starter.md came with. Nil for a copy made
    /// before starters named one.
    static func commit(of project: LampProject) -> String? {
        Credits.load(project).remixOf.last { $0.starter != nil }?.commit ?? starter(of: project)?.commit
    }

    /// The starter this Lamp ships, when it's newer than what a copy of it has, and the copy can take it: the same kind
    /// of wish. A copy that names no commit is behind; a starter not put on GitHub yet has no commit to be behind.
    /// "The original" is always this: the starter as this Lamp ships it.
    static func newer(for project: LampProject) -> Starter? {
        guard !project.isPart, isStarter(project), let shipped = shipped(of: project), let pin = shipped.commit,
              shipped.kind == project.platform, commit(of: project)?.lowercased() != pin.lowercased() else { return nil }
        return shipped
    }
}

/// The chat's card for a copy of a starter changed here, when this Lamp ships a newer one: Update brings it in, keeping
/// the person's changes (`Store.updateFromOriginal`). Said once for each newer starter; its text is the starter's commit,
/// with `done` before it once it's in.
enum NewerOriginalLine {
    static let done = "updated:"
    static func isDone(_ text: String) -> Bool { text.hasPrefix(done) }
    static func title(done: Bool) -> String { done ? "Updated from the original" : "A newer original is available" }
    static let button = "Update"
    static let symbol = "arrow.down.circle"
}
