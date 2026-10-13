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
                // The screen as text says what the pictures show, so it goes with them.
                if name.hasSuffix(".png") || name == "screen.txt", !sharesPictures { return .deny(picturesOff) }
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

    /// Claude Code keeps a command's output too long to show the model in a file of the conversation's own,
    /// `projects/<the app's folder>/<session>/tool-results/` in its folder (~/.claude for the person's copy, or
    /// Lamp's copy's, inside Lamp's own),
    /// and reads it back with its Read tool. That's the agent's own output, so reading it doesn't ask: only
    /// reading, only this app's folder and only the conversation Lamp is running (`session`, from Claude Code's
    /// own output, not from the hook's request), with links worked out so one there can't lead anywhere else.
    /// With Lamp's copy, it's the one place in Lamp's folder the agent may read. pi's and Codex's equivalents need nothing: pi
    /// writes its to the temporary folder (`pi-bash-….log`), and Codex keeps none for the model to read.
    static func isOwnOutput(tool: String, path raw: String, session: String, project: LampProject,
                            claudeFolder: URL = EngineInstall.configFolder(.claude)) -> Bool {
        guard readers.contains(tool), !session.isEmpty,
              session.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-") })
        else { return false }
        // The person's own folder opens nothing the rule never opens, wherever it leads. Lamp's copy's folder
        // is inside Lamp's own, which the rule closes, so this is for the person's only.
        if !claudeFolder.standardizedFileURL.path.hasPrefix(EngineInstall.folder.standardizedFileURL.path + "/"),
           case .deny = verdict(tool: tool, path: raw, project: project) { return false }
        // Every link worked out, so the path is where the read really lands: a link among the results can't
        // lead to the sign-in beside them, or anywhere else in Lamp's folder.
        let path = resolved(raw, in: project.dir)
        // The folder itself may be a link (someone's ~/.claude kept with their dotfiles, say), so it's worked
        // out; nothing below it may be one: a link there would make wherever it leads the folder that doesn't ask.
        let projects = resolved(claudeFolder.appendingPathComponent("projects").path, in: project.dir)
        // Claude Code names the folder after the working directory, every character but ASCII letters and
        // digits made "-" (per UTF-16 unit, as JavaScript counts them). A name past 200 gets a hash Lamp
        // can't work out, so such an app's output asks like any other file.
        let folders = Set([project.dir.standardizedFileURL.path, resolved(project.dir.path, in: project.dir)])
        return folders.contains { folder in
            let slug = String(decoding: folder.utf16.map { unit -> UInt16 in
                switch unit { case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: unit; default: 0x2D }
            }, as: UTF16.self)
            guard slug.utf16.count <= 200 else { return false }
            let results = projects + "/" + slug + "/" + session + "/tool-results"
            guard resolved(results, in: project.dir) == results else { return false }
            return path == results || path.hasPrefix(results + "/")
        }
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
