import Foundation

/// A plain site on GitHub: `index.html` at a repository's root with its scripts, styles and pictures beside it and no
/// build step, often served by GitHub Pages from that root. Opened from GitHub it's a web app (`ScreenKit.isSite`) whose
/// page is the repository's root as it is, so put back on GitHub it's laid out the same way and its Pages address keeps
/// working.
///
/// Inside, the wish is laid out as every web app is (the page in Web/, beside APP.md and Sources/), so building, live
/// changes, Reload and the agent's rules are a web app's, and a page with no Lamp runtime of its own is opened again
/// for a change rather than swapped in place (`LampPageLive`). The repository's layout is worked out where the wish
/// meets GitHub:
/// - Put on GitHub (`GitHubRepo.stage`, `layOut`) puts Web/ at the tree's root and everything else in one folder of
///   Lamp's, `.lamp-wish/`, hidden so it neither clutters the site's root nor is served by GitHub Pages' own build. Of
///   Lamp's own files only lamp.js goes up, and only when the page loads it.
/// - Open from GitHub (`RepoImport.open`, `unpack`) reads such a tree back as a shared file's contents, and a plain
///   site with no folder of Lamp's as a new web app named after its page.
enum StaticSite {
    /// Lamp's folder in a site's repository: the shared file's contents but the page, with Lamp's README.
    static let folder = ".lamp-wish"

    /// A tree laid out by Put on GitHub for a site.
    static func holdsWish(_ tree: URL) -> Bool {
        FileManager.default.fileExists(atPath: tree.appendingPathComponent("\(folder)/lamp-app.json").path)
    }

    /// Whether a tree is a plain site Lamp can open as it is: index.html at its root, and nothing that builds it first
    /// (a package.json, Jekyll's _config.yml or Gemfile), which a page in Lamp's app would never run.
    static func isPlain(_ tree: URL) -> Bool {
        let fm = FileManager.default
        func regular(_ name: String) -> Bool {
            let values = try? tree.appendingPathComponent(name).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            return values?.isRegularFile == true && values?.isSymbolicLink != true
        }
        guard regular("index.html") else { return false }
        return !["package.json", "_config.yml", "Gemfile"].contains { fm.fileExists(atPath: tree.appendingPathComponent($0).path) }
    }

    /// Reads a site's tree into `copy` as a shared file's contents: Lamp's folder at its top, the rest in Web/. A plain
    /// site with no folder of Lamp's gets a manifest of a new web app, named after the page, and an APP.md saying what
    /// it is; `repository` is where it came from.
    static func unpack(_ tree: URL, into copy: URL, repository: String?) throws {
        let fm = FileManager.default
        let web = copy.appendingPathComponent(TVTemplate.webFolder)
        try RepoImport.copyTree(tree, to: web, skipped: [".git"])
        let lamps = web.appendingPathComponent(folder)
        if fm.fileExists(atPath: lamps.path) {
            for item in try fm.contentsOfDirectory(at: lamps, includingPropertiesForKeys: nil) {
                try fm.moveItem(at: item, to: copy.appendingPathComponent(item.lastPathComponent))
            }
            try fm.removeItem(at: lamps)
            // Lamp's runtime and its license are written again for the page when it loads it (`layOut`).
            try? fm.removeItem(at: web.appendingPathComponent(Publish.runtimeLicense))
            return
        }
        let name = title(of: web.appendingPathComponent("index.html")) ?? named(repository) ?? "Site"
        let manifest = Sharing.Manifest(format: Sharing.formatVersion, name: name, exportedAt: Date(), platform: .webApp, site: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: copy.appendingPathComponent("lamp-app.json"))
        let from = repository.map { " from \($0)" } ?? ""
        try Data("""
            # \(name)

            A site opened\(from) as it is: Web/ is the repository's root, laid out as the repository has it (index.html with \
            its scripts, styles and pictures beside it, and no build step). Put on GitHub puts it back the same way, so \
            its GitHub Pages address keeps working. Its own README.md, in Web/, says what it is.

            """.utf8).write(to: copy.appendingPathComponent("APP.md"))
    }

    /// The page's own name, from its `<title>`, when it's a short one.
    static func title(of page: URL) -> String? {
        guard let html = try? String(contentsOf: page, encoding: .utf8),
              let range = html.range(of: #"<title[^>]*>([^<]{1,200})</title>"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let inner = html[range].replacingOccurrences(of: #"</?title[^>]*>"#, with: "", options: [.regularExpression, .caseInsensitive])
        let words = inner.replacingOccurrences(of: "&amp;", with: "&").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return (1...40).contains(words.count) ? words : nil
    }

    /// "fll-practice" as a name: "Fll Practice".
    private static func named(_ repository: String?) -> String? {
        guard let last = repository?.split(separator: "/").last else { return nil }
        let words = last.split { $0 == "-" || $0 == "_" || $0 == "." }.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    /// Whether the page loads Lamp's runtime (lamp.js) from any of its pages or scripts, so it must go up beside them.
    static func loadsRuntime(_ web: URL) -> Bool {
        let fm = FileManager.default
        guard let items = fm.enumerator(at: web, includingPropertiesForKeys: [.isRegularFileKey]) else { return false }
        for case let file as URL in items where ["html", "htm", "js", "mjs"].contains(file.pathExtension.lowercased()) {
            if file.lastPathComponent.hasPrefix(".") || Sharing.relativePath(of: file, in: web) == "lamp.js" { continue }
            if let text = try? String(contentsOf: file, encoding: .utf8), text.contains("lamp.js") { return true }
        }
        return false
    }

    /// Lays a staged tree out as the site's repository: Web/ at its root, and everything else but the license in
    /// Lamp's folder.
    static func layOut(_ tree: URL) throws {
        let fm = FileManager.default
        let lamps = tree.appendingPathComponent(folder)
        try fm.createDirectory(at: lamps, withIntermediateDirectories: true)
        for item in try fm.contentsOfDirectory(at: tree, includingPropertiesForKeys: nil)
        where ![TVTemplate.webFolder, folder, "LICENSE"].contains(item.lastPathComponent) {
            try fm.moveItem(at: item, to: lamps.appendingPathComponent(item.lastPathComponent))
        }
        // Moved aside first, so a folder of the page's own called Web takes its place.
        let web = tree.appendingPathComponent(".lamp-page-\(UUID().uuidString)")
        try fm.moveItem(at: tree.appendingPathComponent(TVTemplate.webFolder), to: web)
        for item in try fm.contentsOfDirectory(at: web, includingPropertiesForKeys: nil) {
            let to = tree.appendingPathComponent(item.lastPathComponent)
            try? fm.removeItem(at: to)
            try fm.moveItem(at: item, to: to)
        }
        try fm.removeItem(at: web)
    }
}
