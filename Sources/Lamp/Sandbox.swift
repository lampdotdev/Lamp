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
    static let executable = "/usr/bin/sandbox-exec"

    /// The command, confined to the app. Nil when the profile can't be written; the caller then refuses the
    /// command rather than run it loose (the sandbox tool itself is part of macOS).
    static func wrap(_ command: String, for project: LampProject) -> String? {
        guard let file = writeProfile(for: project) else { return nil }
        return launch(command, profile: file)
    }

    /// What a confined command returns when the sandbox couldn't be set up: it isn't run loose instead.
    static let unconfined: Int32 = 126

    /// Runs one of Lamp's own commands over an app's folder (its build, the compiler's look at its code, the
    /// finishing of what the build made) under the profile the agent's commands get, in zsh. Everything in that
    /// folder is the agent's to write, build.sh included at any moment between Lamp writing it and running it, so
    /// whatever runs there runs as the agent's commands do, never as Lamp: with Lamp's keys, sign-ins and the
    /// other apps out of reach.
    static func run(_ command: String, for project: LampProject, cwd: URL? = nil, env: [String: String] = [:],
                    started: (@MainActor (Process) -> Void)? = nil,
                    onLine: @escaping @MainActor (String) -> Void) async -> Int32 {
        guard let confined = wrap("/bin/zsh -c " + quoted(command), for: project) else {
            await onLine("Lamp couldn't set up the sandbox for \(project.name), so nothing was run.")
            return unconfined
        }
        return await Shell.run(confined, cwd: cwd ?? project.dir, env: env, started: started, onLine: onLine)
    }

    /// The shell line that runs `command` under `profile`, with Lamp's `swift` first on the path (below). A
    /// login shell started inside (Codex runs its commands with `zsh -lc`) rebuilds the path with the system's
    /// folders first, so zsh is also given Lamp's startup files, which put the shims back in front; the
    /// person's own startup files are in the home folder, which the sandbox closes anyway.
    private static func launch(_ command: String, profile: URL) -> String {
        "\(executable) -f \(quoted(profile.path)) /usr/bin/env PATH=\(quoted(bin.path))':'\"$PATH\" ZDOTDIR=\(quoted(zdot.path)) /bin/bash -c \(quoted(command))"
    }

    /// Programs put before the agent's own on the path. SwiftPM runs its builds under a sandbox of its own,
    /// which macOS won't start inside Lamp's, so `swift build` would fail with "sandbox_apply: Operation not
    /// permitted": this `swift` hands its build, test, run and package commands `--disable-sandbox` (Lamp's
    /// sandbox already keeps the build inside the app) and passes everything else to the real one.
    static let bin = folder.appendingPathComponent("bin")
    static let zdot = folder.appendingPathComponent("zsh")

    private static let swiftShim = """
    #!/bin/bash
    # Written by Lamp. SwiftPM's own sandbox can't start inside Lamp's, which already confines the build.
    here="$(cd "$(dirname "$0")" && pwd)"
    rest="$(printf '%s' "$PATH" | tr ':' '\n' | grep -vx "$here" | paste -sd: -)"
    real="$(PATH="$rest" command -v swift)"
    case "$1" in
        build|test|run|package) exec "$real" "$1" --disable-sandbox "${@:2}" ;;
        *) exec "$real" "$@" ;;
    esac

    """

    private static func writeShims() -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(at: bin, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        try? fm.createDirectory(at: zdot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        let front = "# Written by Lamp: its programs stay first on the path.\npath=(\(quoted(bin.path)) $path)\n"
        let files = [(bin.appendingPathComponent("swift"), swiftShim, 0o755),
                     (zdot.appendingPathComponent(".zshenv"), front, 0o644), (zdot.appendingPathComponent(".zprofile"), front, 0o644)]
        for (file, text, mode) in files where (try? String(contentsOf: file, encoding: .utf8)) != text {
            guard fm.createFile(atPath: file.path, contents: Data(text.utf8), attributes: [.posixPermissions: mode]) else { return false }
        }
        return true
    }

    /// A whole engine run, confined to the app with what the engine itself needs opened as well: `opening`
    /// for reading and writing, `reading` for reading, `writing` the files directly inside a folder only
    /// read (Codex keeps its databases and sign-in beside its settings), and `keeping` single files that
    /// stay read-only whatever else was opened. Nil when the profile can't
    /// be written.
    static func wrapEngine(_ command: String, for project: LampProject, opening folders: [String], reading: [String] = [],
                           writing: [String] = [], keeping: [String] = []) -> String? {
        guard let file = writeProfile(for: project, opening: folders, reading: reading, writing: writing, keeping: keeping) else { return nil }
        return launch(command, profile: file)
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

    /// Where the profiles live: in Lamp's own folder, which every profile closes, so what sandbox-exec reads
    /// is what Lamp wrote and not something the agent could change. One file per command, kept for an hour
    /// (a command may wait that long for the user), then cleared.
    static let folder = Edition.supportFolder.appendingPathComponent("Sandbox")

    private static func writeProfile(for project: LampProject, opening folders: [String] = [], reading: [String] = [],
                                     writing: [String] = [], keeping: [String] = []) -> URL? {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard writeShims() else { return nil }
        let cutoff = Date().addingTimeInterval(-3600)
        for old in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        where old.pathExtension == "sb"
            && ((try? old.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantFuture) < cutoff {
            try? fm.removeItem(at: old)
        }
        let file = folder.appendingPathComponent("\(project.id)-\(UUID().uuidString).sb")
        let text = profile(for: project, opening: folders, reading: reading, writing: writing, keeping: keeping)
        guard fm.createFile(atPath: file.path, contents: Data(text.utf8),
                            attributes: [.posixPermissions: 0o600]) else { return nil }
        return file
    }

    /// The profile: everything allowed, then every person's files closed (all of /Users, the shared folder
    /// included, and anything mounted), then the places under this home a build needs opened again, Lamp's
    /// own folders closed, and the app's folder opened last (it sits inside Lamp's). Later rules win, so the
    /// order is the meaning. `folders` are opened too, for reading and writing; `reading` for reading.
    static func profile(for project: LampProject, opening folders: [String] = [], reading: [String] = [], writing: [String] = [],
                        keeping: [String] = []) -> String {
        let fm = FileManager.default
        let home = real(fm.homeDirectoryForCurrentUser.path)
        // The app's folder by its own name, never where it leads: a command may have swapped it for a link.
        let app = project.realDir.path
        let support = real(home + "/Library/Application Support")
        var lines = [
            "(version 1)",
            "(allow default)",
            "(deny file-read* file-write* (subpath \"/Users\") (subpath \"/Volumes\") (subpath \"/Network\") (subpath \"/private/var/root\"))",
            // The Mac's shared app data and keychains: not a person's files, but not a build's business either.
            "(deny file-read* file-write* (subpath \"/Library/Application Support\") (subpath \"/Library/Keychains\"))",
            "(deny file-read* file-write* (subpath \(quotedPath(home))))",
            // What a build or a script needs from the home folder: the toolchain, package caches, git's
            // settings. Read only, apart from the caches.
            "(allow file-read* (subpath \(quotedPath(home + "/Library/Developer"))) (subpath \(quotedPath(home + "/.swiftpm"))) (literal \(quotedPath(home + "/.gitconfig"))) (subpath \(quotedPath(home + "/.config/git"))))",
            "(allow file-read* file-write* (subpath \(quotedPath(home + "/Library/Caches"))) (subpath \(quotedPath(home + "/Library/org.swift.swiftpm"))) (subpath \"/private/tmp\") (subpath \"/tmp\"))",
        ]
        if let tmp = ProcessInfo.processInfo.environment["TMPDIR"], !tmp.isEmpty {
            lines.append("(allow file-read* file-write* (subpath \(quotedPath(real(tmp)))))")
        }
        // Both Lamps' folders (keys, sign-ins, every other app) stay closed; the app's own folder opens.
        for name in ["Lamp", "Lamp Dev"] {
            lines.append("(deny file-read* file-write* (subpath \(quotedPath(support + "/" + name))))")
            // And the apps Lamp installs are for the person to run, not the command: running one needs no
            // read the profile closes (exec maps it), so it's refused by name. A command could otherwise
            // start another app with a library of its own inside (DYLD_INSERT_LIBRARIES) and read that
            // app's secrets out of Lamp through it (PeerProcess). The app's own build is unaffected: it's
            // built in its folder, not here.
            lines.append("(deny process-exec* (subpath \(quotedPath(real(home + "/Applications/" + name + " Apps")))))")
            // The caller check (PeerProcess.isApp) would also accept a whole bundle replaced at the installed
            // path, signature valid by that copy's own requirement. That's safe only while this folder stays
            // unwritable from the command's sandbox (the file denies above), so nothing the builder makes can
            // be put there: keep it that way, or the check needs the replacement refused too.
        }
        // Lamp's shims and shell startup files may be read and run, and not changed.
        lines.append("(allow file-read* (subpath \(quotedPath(real(bin.path)))) (subpath \(quotedPath(real(zdot.path)))))")
        lines.append("(allow file-read* file-write* (subpath \(quotedPath(app))))")
        for folder in folders {
            lines.append("(allow file-read* file-write* (subpath \(quotedPath(real(folder)))))")
        }
        for folder in reading {
            lines.append("(allow file-read* (subpath \(quotedPath(real(folder)))))")
        }
        // The files directly in a folder, not what's in its subfolders.
        for folder in writing {
            lines.append("(allow file-write* (regex #\"^\(NSRegularExpression.escapedPattern(for: real(folder)))/[^/]*$\"))")
        }
        for path in keeping {
            lines.append("(deny file-write* (literal \(quotedPath(real(path)))))")
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
        // The folder of homes too: Node resolves a program's real path one component at a time.
        ancestors.append((home as NSString).deletingLastPathComponent)
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
