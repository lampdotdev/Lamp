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
    /// (Store.commandVerdict) and is never rated low risk (Store.explain), whatever the models make of it,
    /// so it errs towards yes. It reads the words of the command and can't see what a script or a variable
    /// would open: the models still judge those. The one thing it follows is a `cd` into the app's own
    /// folders and back (`stepsBack`).
    static func reachesOutside(_ command: String, project: LampProject) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // `cd Sources; …; cd ..` comes back to the app's folder: that `..` leads nowhere outside it.
        var returns = stepsBack(in: command, project: project)
        for word in words(in: command) {
            if word == "..", returns > 0 { returns -= 1; continue }
            // `--from=/path` and `VAR=/path` carry a path after the sign.
            var path = word.split(separator: "=", maxSplits: 1).last.map(String.init) ?? word
            for name in ["${HOME}", "$HOME"] where path.hasPrefix(name) { path = home + path.dropFirst(name.count) }
            if path.hasPrefix("/") {
                // A search pattern like /api/ looks like a path: only something whose top folder exists is one.
                guard let top = path.split(separator: "/").first,
                      FileManager.default.fileExists(atPath: "/" + top) else { continue }
            } else if isHomePath(path) || path == ".." || path.hasPrefix("../") || path.contains("/../") {
                // A home folder (the user's or a named user's), or a step up out of the app's folder: a path
                // wherever it leads.
            } else {
                // Any other word is a path only if something by that name is in the app's folder. That includes
                // a bare name: it can be a link that leads out, which the rule works out below. Code written
                // through the shell is full of words that only look like paths (`0..<n`, `~=`, `...`): they
                // aren't, so they're judged by whether they exist like everything else.
                guard FileManager.default.fileExists(atPath: project.dir.appendingPathComponent(path).path) else { continue }
            }
            // Outside the app's folder, whether that means asking (another folder) or never (sign-ins and keys):
            // either way the command isn't routine and needs the user's say-so.
            if verdict(tool: "read", path: path, project: project) != .allow { return true }
        }
        return false
    }

    /// How many `cd ..` in a command only undo a `cd` into one of the app's own folders, so never leave it:
    /// `cd Sources; sed …; cd ..`. Counted only where that can be told for certain from the words: the `cd`
    /// going in comes first in the command, names a folder that exists inside the app's folder, and stands
    /// on its own (not after `&&`, in a pipe, a subshell or a condition, where it might not happen); and
    /// nothing in between could move the shell some other way (`eval`, `source`, another `cd`). Anything
    /// else counts none, and every `..` is then a step out of the app's folder, as before.
    static func stepsBack(in command: String, project: LampProject) -> Int {
        guard let steps = steps(of: command) else { return 0 }
        let home = resolved(project.dir.path, in: project.dir)
        let moves: Set<String> = ["eval", "source", ".", "builtin", "command", "exec", "pushd", "popd", "alias", "set", "setopt", "trap"]
        var folder = home
        var onlyGoneIn = true   // every step so far was a `cd` into the app's folder
        var count = 0
        for step in steps {
            guard let first = step.words.first else { continue }
            guard first.text == "cd" else {
                // Something that can change folder without saying so, or a `cd` that isn't the command itself.
                if moves.contains(first.text) || first.text.contains("=") || step.words.contains(where: { $0.text == "cd" }) { return count }
                onlyGoneIn = false
                continue
            }
            guard step.words.count == 2 else { return count }
            let target = step.words[1]
            if target.text == ".." {
                // Back up one, when that's still inside the app's folder. If the shell skips this `cd`
                // (after `&&`), it's deeper inside than counted, which leaves nothing.
                guard folder != home else { return count }
                folder = (folder as NSString).deletingLastPathComponent
                count += 1
                continue
            }
            var isFolder: ObjCBool = false
            let path = resolved(target.text, in: URL(fileURLWithPath: folder))
            guard onlyGoneIn, target.literal, step.alone, path.hasPrefix(home + "/"),
                  FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), isFolder.boolValue else { return count }
            folder = path
        }
        return count
    }

    /// The commands of a shell line in the order they run, each with its words, or nil when the line is more
    /// than commands one after another: a subshell, a group, a substitution, a background job, a loop or a
    /// condition. A heredoc's text is left out (it's input, not commands). `alone`: the command always runs,
    /// by itself (it follows the start, `;` or a new line, and isn't piped). `literal`: the word is exactly
    /// what's written, with nothing the shell would fill in (`$x`, `*`, `~`).
    static func steps(of command: String) -> [(words: [(text: String, literal: Bool)], alone: Bool)]? {
        let characters = Array(command)
        var steps: [(words: [(text: String, literal: Bool)], alone: Bool)] = []
        var words: [(text: String, literal: Bool)] = []
        var current = "", started = false, literal = true
        var quote: Character?
        var alone = true          // for the step being read
        var heredocs: [(mark: String, tabs: Bool)] = []
        var index = 0
        func endWord() {
            if started { words.append((current, literal)) }
            (current, started, literal) = ("", false, true)
        }
        func endStep(piped: Bool = false, nextAlone: Bool) {
            endWord()
            if !words.isEmpty { steps.append((words, alone && !piped)) }
            words = []
            alone = nextAlone
        }
        while index < characters.count {
            let character = characters[index]
            index += 1
            if let open = quote {
                if character == open { quote = nil; continue }
                if character == "\\", open == "\"", index < characters.count { current.append(characters[index]); index += 1; continue }
                if open == "\"", character == "$" || character == "`" { literal = false }
                current.append(character)
                continue
            }
            switch character {
            case "\\":
                guard index < characters.count else { return nil }
                if characters[index] != "\n" { current.append(characters[index]); started = true }
                index += 1
            case "'", "\"":
                quote = character
                started = true
            case "\n":
                endStep(nextAlone: true)
                // The text of each heredoc opened on this line: up to a line that is its mark.
                for heredoc in heredocs {
                    var closed = false
                    while index < characters.count, !closed {
                        let end = characters[index...].firstIndex(of: "\n") ?? characters.count
                        var line = String(characters[index..<end])
                        if heredoc.tabs { line = String(line.drop { $0 == "\t" }) }
                        closed = line == heredoc.mark
                        index = min(end + 1, characters.count)
                    }
                    guard closed else { return nil }
                }
                heredocs = []
            case ";":
                endStep(nextAlone: true)
            case "&":
                guard index < characters.count, characters[index] == "&" else { return nil }
                index += 1
                endStep(nextAlone: false)
            case "|":
                if index < characters.count, characters[index] == "|" { index += 1 }
                endStep(piped: true, nextAlone: false)
            case "(", ")", "`", "{", "}":
                return nil
            case "<":
                endWord()
                guard index < characters.count, characters[index] == "<" else { continue }
                index += 1
                if index < characters.count, characters[index] == "<" { index += 1; continue }   // <<< "text"
                var tabs = false
                if index < characters.count, characters[index] == "-" { tabs = true; index += 1 }
                while index < characters.count, characters[index] == " " { index += 1 }
                var mark = ""
                while index < characters.count, !characters[index].isWhitespace, !";|&<>()".contains(characters[index]) {
                    if !"'\"\\".contains(characters[index]) { mark.append(characters[index]) }
                    index += 1
                }
                guard !mark.isEmpty else { return nil }
                heredocs.append((mark, tabs))
            case ">":
                endWord()
                // `2>&1`, `>&2`: one stream into another, not a job in the background.
                if index < characters.count, characters[index] == "&" {
                    index += 1
                    while index < characters.count, characters[index].isNumber || characters[index] == "-" { index += 1 }
                }
            case "#" where !started:
                while index < characters.count, characters[index] != "\n" { index += 1 }
            case _ where character.isWhitespace:
                endWord()
            default:
                if "$*?[~".contains(character) { literal = false }
                current.append(character)
                started = true
            }
        }
        guard quote == nil, heredocs.isEmpty else { return nil }
        endStep(nextAlone: true)
        let syntax: Set<String> = ["if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac",
                                   "function", "select", "time", "!", "[["]
        return steps.contains(where: { syntax.contains($0.words[0].text) }) ? nil : steps
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
