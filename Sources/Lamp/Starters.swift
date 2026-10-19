import AppKit
import LampSidebarKit

/// The wishes Lamp comes with: working apps on a new person's desk from the start, to use as they are and to
/// change into their own, which shows what Lamp does better than a question about what to make. Each is a
/// folder in Resources/Starters: the app's code (Sources/, Widget/, Share/), its pictures (Assets/), APP.md for the agent that changes it,
/// icon.json, about.json, capabilities.json when it needs one, preview.png (the picture the desk shows on hover),
/// and starter.md, which is Lamp's: the wish's name and what the sidebar offers to change first. They're copied once, on the first launch, and from then on
/// they're the person's like any other wish; a later Lamp with other starters gives those only to new people.
/// `scripts/check-starters.sh` type-checks them against this checkout's LampSupport.swift.
enum Starters {
    static let installedKey = "startersInstalled"

    struct Starter: Equatable {
        let folder: URL
        let name: String
        /// The first thing the app's chat offers: a line inviting a change, and three changes to choose from.
        let offer: String
        /// The line under it, saying what this is: one of the wishes Lamp came with, theirs to change.
        var intro = ""
        let tweaks: [Tweak]

        var introduction: String {
            intro.isEmpty ? "\(name) came with Lamp as an example, and it's yours to change. Try one of these, or describe your own." : intro
        }
    }

    /// A change the chat offers, with the symbol on its tile (`- drop.fill: Add a water counter` in starter.md;
    /// the symbol may be left out).
    struct Tweak: Equatable {
        let title: String
        var symbol: String?
    }

    static var folder: URL? { Bundle.main.resourceURL?.appendingPathComponent("Starters") }

    static var bundled: [Starter] {
        guard let folder else { return [] }
        let folders = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return folders.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap(read)
    }

    /// The starters this Lamp ships that aren't on the desk: never added, or deleted since. The desk offers them
    /// (`MoreFromLamp`).
    static func missing(from projects: [LampProject]) -> [Starter] {
        let here = Set(projects.compactMap { starter(of: $0)?.name })
        return bundled.filter { !here.contains($0.name) }
    }

    /// The icon a starter ships with, drawn from its icon.json (`StarterIconsTests`).
    static func icon(of starter: Starter) -> NSImage? {
        NSImage(contentsOf: starter.folder.appendingPathComponent(iconFolder).appendingPathComponent("icon.png"))
    }

    /// The starter's line saying what it is, from its about.json.
    static func about(_ starter: Starter) -> String? {
        AppDescription.description(at: starter.folder.appendingPathComponent(AppDescription.file))
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
              let shipped = bundled.first(where: { $0.name == name })?.folder.appendingPathComponent("preview.png"),
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

    private static func read(_ folder: URL) -> Starter? {
        guard let text = try? String(contentsOf: folder.appendingPathComponent("starter.md"), encoding: .utf8) else { return nil }
        return parse(text, folder: folder)
    }

    /// starter.md's front matter: `name:`, `offer:`, and `tweaks:` followed by `  - ` lines. That's all it holds,
    /// so a few lines read it; anything else in the file is ignored.
    static func parse(_ text: String, folder: URL) -> Starter? {
        var lines = text.components(separatedBy: .newlines)[...]
        guard lines.first?.trimmed == "---" else { return nil }
        lines = lines.dropFirst()
        var name = "", offer = "", intro = "", tweaks: [Tweak] = []
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
                case "intro": intro = value
                default: break
                }
            }
        }
        guard !name.isEmpty else { return nil }
        return Starter(folder: folder, name: name, offer: offer, intro: intro, tweaks: tweaks)
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
        let question = TalkCard.Question(question: starter.offer, options: options, detail: starter.introduction)
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

    /// What a starter's folder gives the app, beside its scaffold (which is replaced): the agent and the build
    /// read these where any app keeps them.
    private static let copied = ["Sources", "Widget", "Share", "Assets", "APP.md", "icon.json", "about.json", "capabilities.json"]

    /// A starter's icon, drawn once from its icon.json (`StarterIconsTests`) and shipped with Lamp, so it's on the desk
    /// as soon as the starter is: the files `Icons.write` makes, which go into the app's .lamp folder, the
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

    /// Puts a starter's files into a scaffolded app: its Sources replace the scaffold's (LampSupport.swift,
    /// which Lamp writes before every build, stays), and starter.md goes into .lamp.
    static func copy(_ starter: Starter, into project: LampProject) throws {
        let fm = FileManager.default
        let sources = project.dir.appendingPathComponent("Sources")
        for scaffold in ["App.swift", "ContentView.swift"] {
            try? fm.removeItem(at: sources.appendingPathComponent(scaffold))
        }
        for name in copied {
            let from = starter.folder.appendingPathComponent(name)
            guard fm.fileExists(atPath: from.path) else { continue }
            let to = project.dir.appendingPathComponent(name)
            if name == "Sources" {
                // Into the existing folder, file by file, around LampSupport.swift.
                for file in (try? fm.subpathsOfDirectory(atPath: from.path)) ?? [] {
                    let source = from.appendingPathComponent(file)
                    var isFolder: ObjCBool = false
                    fm.fileExists(atPath: source.path, isDirectory: &isFolder)
                    let target = to.appendingPathComponent(file)
                    if isFolder.boolValue {
                        try fm.createDirectory(at: target, withIntermediateDirectories: true)
                    } else {
                        try? fm.removeItem(at: target)
                        try fm.copyItem(at: source, to: target)
                    }
                }
            } else {
                try? fm.removeItem(at: to)
                try fm.copyItem(at: from, to: to)
            }
        }
        try fm.copyItem(at: starter.folder.appendingPathComponent("starter.md"), to: file(of: project))
        let icon = starter.folder.appendingPathComponent(iconFolder)
        for made in iconFiles(of: project) {
            let shipped = icon.appendingPathComponent(made.lastPathComponent)
            guard fm.fileExists(atPath: shipped.path) else { continue }
            try? fm.removeItem(at: made)
            try fm.copyItem(at: shipped, to: made)
        }
        let spec = icon.appendingPathComponent("icon.json")
        if fm.fileExists(atPath: spec.path) { try fm.copyItem(at: spec, to: drawnFrom(project)) }
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
        let preview = starter.folder.appendingPathComponent("preview.png")
        if fm.fileExists(atPath: preview.path) {
            try? fm.createDirectory(at: Runtime.macFolder(project), withIntermediateDirectories: true)
            try? fm.copyItem(at: preview, to: Runtime.previewURL(project))
        }
    }
}
