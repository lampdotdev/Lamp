import Foundation

/// What the agent may see beyond the code it's writing (Settings → Building → Privacy).
enum Privacy {
    /// Ask before the agent reads or changes a file outside the app's folder.
    static var asksOutsideFolder: Bool { UserDefaults.standard.object(forKey: "askOutsideFolder") as? Bool ?? true }
    /// Show the agent what the app prints while it runs.
    static var sharesLog: Bool { UserDefaults.standard.object(forKey: "shareAppLog") as? Bool ?? true }
    /// Show the agent pictures of the app's windows.
    static var sharesPictures: Bool { UserDefaults.standard.object(forKey: "shareAppPictures") as? Bool ?? true }

    static let picturesOff = "The user has turned off sharing pictures of the app with you (Lamp → Settings → Building)."
    static let logOff = "The user has turned off sharing what the app prints with you (Lamp → Settings → Building)."

    enum Verdict: Equatable {
        case allow
        case deny(String)
        case ask
    }

    /// Tools that only read.
    private static let readers: Set<String> = ["read", "grep", "find", "ls"]

    /// Places that hold nothing personal: the system, developer tools and installed packages.
    private static let publicRoots = ["/System", "/usr", "/Library/Developer", "/Applications/Xcode.app", "/opt/homebrew"]
    private static let scratchRoots = ["/tmp", "/private/tmp", "/var/folders", "/private/var/folders"]

    /// Whether one of the agent's file tools may touch `path` (as the agent gave it, relative to the app's folder).
    static func verdict(tool: String, path raw: String, project: LampProject) -> Verdict {
        let path = resolved(raw, in: project.dir)
        let home = resolved(project.dir.path, in: project.dir)
        if path == home || path.hasPrefix(home + "/") {
            let inside = String(path.dropFirst(home.count))
            if inside.hasPrefix("/.lamp/runtime/") {
                let name = (inside as NSString).lastPathComponent
                if name.hasSuffix(".png"), !sharesPictures { return .deny(picturesOff) }
                if name.hasSuffix("log.txt"), !sharesLog { return .deny(logOff) }
            }
            return .allow
        }
        // Lamp's keys, its agent's sign-ins and the user's other apps: never, whatever the settings say.
        let forge = resolved(Agent.configDir, in: project.dir).deletingLastComponent
        if path == forge || path.hasPrefix(forge + "/") {
            return .deny("That belongs to Lamp or to another of the user's apps, and isn't yours to open.")
        }
        guard asksOutsideFolder else { return .allow }
        if scratchRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return .allow }
        if readers.contains(tool), publicRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return .allow }
        return .ask
    }

    /// Whether a search that started somewhere the agent may look should still pass over `path` further down:
    /// the places the rule above never opens.
    static func hides(_ path: String, project: LampProject) -> Bool {
        if case .deny = verdict(tool: "read", path: path, project: project) { return true }
        return false
    }

    /// Why reading outside the app's folder is the user's call, on a file tool's card and a command's alike.
    static let outsideRead = "It's outside this app's folder, and what's read goes to the AI model."

    /// Whether a shell command names something the rule above would ask about: a file or folder outside the
    /// app's folder that isn't a system, developer or temporary one. Such a command always goes to the user
    /// (Store.commandLooksSafe) and is never rated low risk (Store.explain), whatever the models make of it,
    /// so it errs towards yes. It reads the words of the command and can't see what a script or a variable
    /// would open: the models still judge those.
    static func reachesOutside(_ command: String, project: LampProject) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return words(in: command).contains { word in
            // `--from=/path` and `VAR=/path` carry a path after the sign.
            var path = word.split(separator: "=", maxSplits: 1).last.map(String.init) ?? word
            for name in ["${HOME}", "$HOME"] where path.hasPrefix(name) { path = home + path.dropFirst(name.count) }
            if path.hasPrefix("/") {
                // A search pattern like /api/ looks like a path: only something whose top folder exists is one.
                guard let top = path.split(separator: "/").first,
                      FileManager.default.fileExists(atPath: "/" + top) else { return false }
            } else if !path.hasPrefix("~"), !path.contains("..") {
                // Any other word is a path only if something by that name is in the app's folder. That includes
                // a bare name: it can be a link that leads out, which the rule works out below.
                guard FileManager.default.fileExists(atPath: project.dir.appendingPathComponent(path).path) else { return false }
            }
            return verdict(tool: "read", path: path, project: project) == .ask
        }
    }

    /// The words of a shell line, with quotes and escapes worked out, so a quoted path with a space in it
    /// (the app's own folder has one) stays whole.
    static func words(in command: String) -> [String] {
        var words: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        for character in command {
            if escaped { current.append(character); escaped = false; continue }
            if character == "\\", quote != "'" { escaped = true; continue }
            if let open = quote {
                if character == open { quote = nil } else { current.append(character) }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if character.isWhitespace || ";|&<>()".contains(character) {
                if !current.isEmpty { words.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    /// What the approval card says for a file request.
    static func explanation(tool: String, path raw: String, project: LampProject) -> (command: String, explanation: Store.CommandExplanation) {
        let shown = (resolved(raw, in: project.dir) as NSString).abbreviatingWithTildeInPath
        let reads = readers.contains(tool)
        let verb: String
        switch tool {
        case "read": verb = "Read"
        case "ls": verb = "List what's in"
        case "grep", "find": verb = "Search"
        case "write": verb = "Create or replace"
        default: verb = "Change"
        }
        return ("\(tool) \(shown)",
                Store.CommandExplanation(summary: "\(verb) \(shown)", risk: reads ? "medium" : "high",
                                         why: reads ? outsideRead : "It's outside this app's folder."))
    }

    /// The path with `~`, `..` and links worked out, so a link inside the app's folder can't lead out of it.
    static func resolved(_ raw: String, in folder: URL) -> String {
        let expanded = (raw as NSString).expandingTildeInPath
        var existing = (expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : folder.appendingPathComponent(expanded))
            .standardizedFileURL
        // A file about to be created doesn't exist yet: links are resolved up to the nearest folder that does.
        var rest: [String] = []
        while existing.path != "/" {
            if let real = realpath(existing.path, nil) {
                defer { free(real) }
                return rest.reduce(URL(fileURLWithPath: String(cString: real))) { $0.appendingPathComponent($1) }.path
            }
            rest.insert(existing.lastPathComponent, at: 0)
            existing.deleteLastPathComponent()
        }
        return "/" + rest.joined(separator: "/")
    }
}

private extension String {
    var deletingLastComponent: String { (self as NSString).deletingLastPathComponent }
}
