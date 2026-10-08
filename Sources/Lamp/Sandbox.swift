import Foundation

/// Where a shell command may go, enforced by macOS rather than guessed from the command's text: the
/// agent's commands run under `sandbox-exec` with a profile that opens the app's own folder, the system,
/// the developer tools, caches and temporary folders, and the network, and closes the rest of the Mac. A
/// command that reaches for Documents or a key gets "Operation not permitted" and nothing leaves; the agent
/// is told to use its file tools for anything outside, which ask the user. So nothing has to read a
/// command to know what it touches, and the approval card is about what a command does, not where it looks.
///
/// Claude Code's and pi's commands are wrapped (their hooks can hand back a changed command). Codex runs in
/// its own sandbox, which keeps writes to the app's folder but lets reads go anywhere, so its commands are
/// still read for paths outside (Privacy.reachesOutside).
enum Sandbox {
    /// The engines whose shell commands run confined.
    static func confines(_ engine: Engine) -> Bool { engine != .codex }

    static let executable = "/usr/bin/sandbox-exec"

    /// The command, confined to the app. Nil when the sandbox tool isn't there (then the text check stands in).
    static func wrap(_ command: String, for project: LampProject) -> String? {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }
        let file = project.dir.appendingPathComponent(".lamp/sandbox.sb")
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? profile(for: project).write(to: file, atomically: true, encoding: .utf8)) != nil else { return nil }
        return "\(executable) -f \(quoted(file.path)) /bin/bash -c \(quoted(command))"
    }

    /// The profile: everything allowed, then the home folder closed, then the places under it a build needs
    /// opened again, Lamp's own folders closed, and the app's folder opened last (it sits inside Lamp's).
    /// Later rules win, so the order is the meaning.
    static func profile(for project: LampProject) -> String {
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
