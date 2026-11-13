import Foundation

/// An app folder's `.lampignore`: what it keeps out of what it shares (its file, its page on its link or on GitHub). The
/// format and what each pattern means are lamp's command line's (`cli/ignore.mjs`), which shares from the same folders,
/// so this follows it pattern for pattern: a folder shared from Lamp leaves out what the same folder shared from a
/// terminal does. A change to the format is made there first, then here.
///
/// It's asked of Lamp itself rather than of lamp's command line, which is never pointed at an app's folder (`LampCLI`).
enum LampIgnore {
    static let file = ".lampignore"

    /// Whether a file, by its path from the app's folder ("Web/ldraw/parts/3001.dat"), is one the app's `.lampignore`
    /// leaves out, or, for a file in its page's folder (Web/), the page's own (whose patterns count from Web/, as
    /// `ignoredFor` counts them for a page in Web/). Never, with neither. A file under a folder a pattern names matches it
    /// too, so asking of each file is the same as leaving out the folder.
    static func rules(for folder: URL) -> (String) -> Bool {
        let app = patterns(in: folder.appendingPathComponent(file), of: folder)
        let page = patterns(in: folder.appendingPathComponent(TVTemplate.webFolder).appendingPathComponent(file), of: folder)
        if app.isEmpty && page.isEmpty { return { _ in false } }
        let web = TVTemplate.webFolder + "/"
        return { path in
            if app.contains(where: { matches($0, path) }) { return true }
            guard path.hasPrefix(web) else { return false }
            let inPage = String(path.dropFirst(web.count))
            return page.contains { matches($0, inPage) }
        }
    }

    /// The same for a file by its path from the page's own folder (Web/), as a copy of the page names it.
    static func pageRules(for folder: URL) -> (String) -> Bool {
        let rules = rules(for: folder), web = TVTemplate.webFolder + "/"
        return { rules(web + $0) }
    }

    /// The same for a file by its path from a wish's folder, as the wish's history names it, so what a shared file
    /// carries of its history leaves out what its apps do (`MixHistory`). Each app in a folder of its own is asked by
    /// its own rules with its folder taken off, as its files are when it's shared, the one a shared file puts at its root
    /// (`Sharing.layout`) included; every other path is asked by the wish folder's own, as the icon beside its apps is.
    static func rules(ofWish project: LampProject) -> (String) -> Bool {
        let (root, parts) = Sharing.layout(of: project)
        let wish = rules(for: project.dir), top = project.dir.standardizedFileURL
        var apps: [String: (String) -> Bool] = [:]
        for app in [root] + parts where app.dir.standardizedFileURL != top {
            apps[app.dir.lastPathComponent] = rules(for: app.dir)
        }
        return { path in
            if let slash = path.firstIndex(of: "/"), let app = apps[String(path[..<slash])] {
                return app(String(path[path.index(after: slash)...]))
            }
            return wish(path)
        }
    }

    /// The patterns of one `.lampignore`, read as any of the app's files Lamp reads (`AppFile`: no link followed).
    private static func patterns(in url: URL, of folder: URL) -> [NSRegularExpression] {
        guard let text = AppFile.text(url, inFolder: folder) else { return [] }
        return patterns(text)
    }

    static func patterns(_ text: String) -> [NSRegularExpression] {
        text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("!") }
            .compactMap(compile)
    }

    static func matches(_ pattern: NSRegularExpression, _ path: String) -> Bool {
        pattern.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil
    }

    /// A pattern as a regular expression over a path from the folder's top, as `compile` in cli/ignore.mjs makes it.
    private static func compile(_ line: String) -> NSRegularExpression? {
        var pattern = Substring(line.trimmingCharacters(in: .whitespaces))
        let folder = pattern.hasSuffix("/")
        while pattern.hasSuffix("/") { pattern = pattern.dropLast() }
        let anchored = pattern.hasPrefix("/") || pattern.contains("/")
        while pattern.hasPrefix("/") { pattern = pattern.dropFirst() }
        guard !pattern.isEmpty else { return nil }
        let characters = Array(pattern)
        var source = "", i = 0
        while i < characters.count {
            let c = characters[i]
            if c == "*", i + 1 < characters.count, characters[i + 1] == "*" {
                // `**/` matches any folders, none included; a lone `**` anything at all.
                if i + 2 < characters.count, characters[i + 2] == "/" { source += "(?:.*/)?"; i += 2 } else { source += ".*"; i += 1 }
            } else if c == "*" {
                source += "[^/]*"
            } else if c == "?" {
                source += "[^/]"
            } else {
                source += NSRegularExpression.escapedPattern(for: String(c))
            }
            i += 1
        }
        // What it names is left out with everything under it; a folder pattern names folders only, so it must have more after it.
        return try? NSRegularExpression(pattern: "^\(anchored ? "" : "(?:.*/)?")\(source)\(folder ? "/" : "(?:/|$)")")
    }
}
