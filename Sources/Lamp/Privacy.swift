import Foundation

/// What the agent may see beyond the code it's writing (Settings → Building → Permissions and Privacy).
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
    /// `2>/dev/null` in a command names the one device with nothing in it. Other devices (terminals, disks)
    /// are files like any other to this rule.
    private static let nothing = "/dev/null"

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
        // Both Lamps' folders (the installed one and the development build, Edition), whichever this is.
        if lampFolders.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            return .deny("That belongs to Lamp or to another of the user's apps, and isn't yours to open.")
        }
        guard asksOutsideFolder else { return .allow }
        if path == nothing { return .allow }
        if scratchRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return .allow }
        if readers.contains(tool), publicRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return .allow }
        return .ask
    }

    /// Whether a search of everything under `root` would pass over something the rule above never opens:
    /// Lamp's own folder. Lamp's file tools skip such places as they go (`hides`); a search the agent's own
    /// tool runs can't, so it isn't allowed to start above them.
    static func wouldUncover(root raw: String, project: LampProject) -> Bool {
        let root = resolved(raw, in: project.dir)
        return lampFolders.contains { $0 == root || $0.hasPrefix(root.hasSuffix("/") ? root : root + "/") }
    }

    /// The support folders of both Lamps on this Mac, the installed one's and the development build's,
    /// as real paths: neither is the agent's to open, whichever Lamp it runs under.
    private static let lampFolders: [String] = {
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return ["Lamp", "Lamp Dev"].map { support.appendingPathComponent($0).resolvingSymlinksInPath().standardizedFileURL.path }
    }()

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
            } else if isHomePath(path) || path == ".." || path.hasPrefix("../") || path.contains("/../") {
                // A home folder (the user's or a named user's), or a step up out of the app's folder: a path
                // wherever it leads.
            } else {
                // Any other word is a path only if something by that name is in the app's folder. That includes
                // a bare name: it can be a link that leads out, which the rule works out below. Code written
                // through the shell is full of words that only look like paths (`0..<n`, `~=`, `...`): they
                // aren't, so they're judged by whether they exist like everything else.
                guard FileManager.default.fileExists(atPath: project.dir.appendingPathComponent(path).path) else { return false }
            }
            // Outside the app's folder, whether that means asking (another folder) or never (sign-ins and keys):
            // either way the command isn't routine and needs the user's say-so.
            return verdict(tool: "read", path: path, project: project) != .allow
        }
    }

    /// `~`, `~/Documents`, `~matt` or `~matt/Documents`: the shell's home-folder shorthand. Not `~=` or other
    /// code that happens to start with a tilde.
    private static func isHomePath(_ word: String) -> Bool {
        guard word.hasPrefix("~") else { return false }
        let user = word.dropFirst().prefix { $0 != "/" }
        return user.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." }
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
