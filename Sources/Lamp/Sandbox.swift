import Foundation

/// Where a shell command may go, enforced by macOS rather than guessed from the command's text: the
/// agent's commands run under `sandbox-exec` with a profile that opens the app's own folder, the system,
/// the developer tools, caches and temporary folders, and the network, and closes the rest of the Mac. A
/// command that reaches for Documents or a key gets "Operation not permitted" and nothing leaves; the agent
/// is told to use its file tools for anything outside, which ask the user. So nothing has to read a
/// command to know what it touches, and the approval card is about what a command does, not where it looks.
///
/// Claude Code's and pi's commands are wrapped one by one (their hooks can hand back a changed command).
/// Codex's hook can't, and a sandbox can't be nested, so Codex itself runs inside the profile (with its own
/// sandbox off, and its own folder opened), and its commands with it.
enum Sandbox {
    /// Every engine's shell commands run confined, when the sandbox tool is there.
    static func confines(_ engine: Engine) -> Bool { FileManager.default.isExecutableFile(atPath: executable) }

    static let executable = "/usr/bin/sandbox-exec"

    /// The command, confined to the app. Nil when the sandbox tool isn't there (then the text check stands in).
    static func wrap(_ command: String, for project: LampProject) -> String? {
        guard let file = writeProfile(for: project, name: "sandbox.sb") else { return nil }
        return "\(executable) -f \(quoted(file.path)) /bin/bash -c \(quoted(command))"
    }

    /// A whole engine run, confined to the app with the engine's own folder opened as well (Codex's
    /// ~/.codex: its sign-in, sessions and caches). Nil when the sandbox tool isn't there.
    static func wrapEngine(_ command: String, for project: LampProject, opening folders: [String], reading: [String] = []) -> String? {
        guard let file = writeProfile(for: project, name: "sandbox-engine.sb", opening: folders, reading: reading) else { return nil }
        return "\(executable) -f \(quoted(file.path)) /bin/bash -c \(quoted(command))"
    }

    /// Where an engine's program lives when that's under the home folder (a Node install, say): the install
    /// it belongs to (the parent of its `bin`), as given and as the link resolves (a package under
    /// node_modules), must be readable for it to start.
    static func installFolders(of tool: String) -> [String] {
        let home = real(FileManager.default.homeDirectoryForCurrentUser.path)
        func root(_ path: String) -> String? {
            guard path.hasPrefix(home + "/") else { return nil }
            let bin = (path as NSString).deletingLastPathComponent
            return (bin as NSString).lastPathComponent == "bin" ? (bin as NSString).deletingLastPathComponent : bin
        }
        var folders: [String] = []
        for candidate in [URL(fileURLWithPath: tool).standardizedFileURL.path, real(tool)] {
            if let folder = root(candidate), !folders.contains(folder) { folders.append(folder) }
        }
        return folders
    }

    private static func writeProfile(for project: LampProject, name: String, opening folders: [String] = [], reading: [String] = []) -> URL? {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }
        let file = project.dir.appendingPathComponent(".lamp/\(name)")
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? profile(for: project, opening: folders, reading: reading).write(to: file, atomically: true, encoding: .utf8)) != nil else { return nil }
        return file
    }

    /// The profile: everything allowed, then the home folder closed, then the places under it a build needs
    /// opened again, Lamp's own folders closed, and the app's folder opened last (it sits inside Lamp's).
    /// Later rules win, so the order is the meaning. `folders` are opened too, for reading and writing.
    static func profile(for project: LampProject, opening folders: [String] = [], reading: [String] = []) -> String {
        let fm = FileManager.default
        let home = real(fm.homeDirectoryForCurrentUser.path)
        let app = real(project.dir.path)
        let support = real(home + "/Library/Application Support")
        var lines = [
            "(version 1)",
            "(allow default)",
            "(deny file-read* file-write* (subpath \(quotedPath(home))))",
            // What a build or a script needs from the home folder: the toolchain, package caches, git's
            // settings. Read only, apart from the caches.
            "(allow file-read* (subpath \(quotedPath(home + "/Library/Developer"))) (subpath \(quotedPath(home + "/.swiftpm"))) (literal \(quotedPath(home + "/.gitconfig"))) (subpath \(quotedPath(home + "/.config/git"))))",
            "(allow file-read* file-write* (subpath \(quotedPath(home + "/Library/Caches"))) (subpath \"/private/tmp\") (subpath \"/tmp\"))",
        ]
        if let tmp = ProcessInfo.processInfo.environment["TMPDIR"], !tmp.isEmpty {
            lines.append("(allow file-read* file-write* (subpath \(quotedPath(real(tmp)))))")
        }
        // Both Lamps' folders (keys, sign-ins, every other app) stay closed; the app's own folder opens.
        for name in ["Lamp", "Lamp Dev"] {
            lines.append("(deny file-read* file-write* (subpath \(quotedPath(support + "/" + name))))")
        }
        lines.append("(allow file-read* file-write* (subpath \(quotedPath(app))))")
        for folder in folders {
            lines.append("(allow file-read* file-write* (subpath \(quotedPath(real(folder)))))")
        }
        for folder in reading {
            lines.append("(allow file-read* (subpath \(quotedPath(real(folder)))))")
        }
        // The folders on the way to each opened one, the home folder included, can be looked at (not read):
        // a program resolving a path stats every step of it, and Node refuses to start otherwise.
        var ancestors: [String] = []
        for opened in [app] + folders.map(real) + reading.map(real) {
            var path = (opened as NSString).deletingLastPathComponent
            while path.hasPrefix(home), path.count >= home.count {
                if !ancestors.contains(path) { ancestors.append(path) }
                if path == home { break }
                path = (path as NSString).deletingLastPathComponent
            }
        }
        for path in ancestors { lines.append("(allow file-read-metadata (literal \(quotedPath(path))))") }
        // What the app shows and prints is shared with the agent only when the settings say so.
        if !Privacy.sharesPictures || !Privacy.sharesLog {
            lines.append("(deny file-read* (subpath \(quotedPath(app + "/.lamp/runtime"))))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// A path inside a profile rule: double-quoted, with backslashes and quotes escaped.
    private static func quotedPath(_ path: String) -> String {
        "\"" + path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// The path as the kernel sees it (/private/var for /var), since the sandbox matches real paths.
    private static func real(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// For a shell: single quotes, with any inside them closed, escaped and reopened. For a profile, the
    /// same text works inside double quotes once backslashes and quotes are escaped.
    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
