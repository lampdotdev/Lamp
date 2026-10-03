import Foundation

/// What the agent may see beyond the code it's writing (Settings → Building → Privacy).
enum Privacy {
    /// Ask before the agent reads or changes a file outside the app's folder.
    static var asksOutsideFolder: Bool { UserDefaults.standard.object(forKey: "askOutsideFolder") as? Bool ?? true }
    /// Show the agent what the app prints while it runs.
    static var sharesLog: Bool { UserDefaults.standard.object(forKey: "shareAppLog") as? Bool ?? true }
    /// Show the agent pictures of the app's windows.
    static var sharesPictures: Bool { UserDefaults.standard.object(forKey: "shareAppPictures") as? Bool ?? true }

    static let picturesOff = "The user has turned off sharing pictures of the app with you (Forge → Settings → Building)."
    static let logOff = "The user has turned off sharing what the app prints with you (Forge → Settings → Building)."

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
    static func verdict(tool: String, path raw: String, project: ForgeProject) -> Verdict {
        let path = resolved(raw, in: project.dir)
        let home = resolved(project.dir.path, in: project.dir)
        if path == home || path.hasPrefix(home + "/") {
            let inside = String(path.dropFirst(home.count))
            if inside.hasPrefix("/.forge/runtime/") {
                let name = (inside as NSString).lastPathComponent
                if name.hasSuffix(".png"), !sharesPictures { return .deny(picturesOff) }
                if name.hasSuffix("log.txt"), !sharesLog { return .deny(logOff) }
            }
            return .allow
        }
        // Forge's keys, its agent's sign-ins and the user's other apps: never, whatever the settings say.
        let forge = resolved(Agent.configDir, in: project.dir).deletingLastComponent
        if path == forge || path.hasPrefix(forge + "/") {
            return .deny("That belongs to Forge or to another of the user's apps, and isn't yours to open.")
        }
        guard asksOutsideFolder else { return .allow }
        if scratchRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return .allow }
        if readers.contains(tool), publicRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return .allow }
        return .ask
    }

    /// What the approval card says for a file request.
    static func explanation(tool: String, path raw: String, project: ForgeProject) -> (command: String, explanation: Store.CommandExplanation) {
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
                                         why: reads ? "It's outside this app's folder, and what's read goes to the AI model."
                                                    : "It's outside this app's folder."))
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
