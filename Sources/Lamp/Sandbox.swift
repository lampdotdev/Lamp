import CryptoKit
import Foundation

/// Where a shell command may go, enforced by macOS rather than guessed from the command's text: the
/// agent's commands run under `sandbox-exec` with a profile that opens the app's own folder, the system,
/// the developer tools, caches and temporary folders, and the network, and closes the rest of the Mac. A
/// command that reaches for Documents or a key gets "Operation not permitted" and nothing leaves; the agent
/// is told to use its file tools for anything outside, which ask the user. So nothing has to read a
/// command to know what it touches, and the approval card is about what a command does, not where it looks.
///
/// Claude Code's and pi's commands are wrapped one by one (their hooks can hand back a changed command).
/// Codex's commands run in Codex's own sandbox instead (`codexPermissions`), which its reviewer works with.
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
    static func run(_ command: String, for project: LampProject, cwd: URL? = nil, env: [String: String] = [:], opening folders: [String] = [],
                    reading: [String] = [], offline: Bool = false,
                    started: (@MainActor (Process) -> Void)? = nil,
                    onLine: @escaping @MainActor (String) -> Void) async -> Int32 {
        guard let confined = wrapEngine("/bin/zsh -c " + quoted(command), for: project, opening: folders, reading: reading, offline: offline) else {
            await onLine("Lamp couldn't set up the sandbox for \(project.name), so nothing was run.")
            return unconfined
        }
        return await Shell.run(confined, cwd: cwd ?? project.dir, env: env, login: false, started: started, onLine: onLine)
    }

    /// `run` for a command whose standard output is read as a whole (`Shell.output`): kept in one buffer off the
    /// main actor, its standard error dropped. Confined the same way.
    static func output(_ command: String, for project: LampProject, cwd: URL? = nil) async -> (status: Int32, output: Data) {
        guard let confined = wrap("/bin/zsh -c " + quoted(command), for: project) else { return (unconfined, Data()) }
        return await Shell.output(confined, cwd: cwd ?? project.dir, login: false)
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

    /// Codex's own sandbox for its commands, as one of Codex's permission profiles (`-c permissions.lamp=…` with
    /// `default_permissions="lamp"`): Codex can't run inside Lamp's profile and keep its own reviewer, since its
    /// commands' sandbox can't be started inside another. The profile closes everything (`:root`), then opens what
    /// the profile above opens for a build: the app's folder (whose `.git` Codex keeps read-only), the platform's runtime (`:minimal`), the developer tools, Homebrew's and the applications for
    /// reading, caches and temporary folders for writing, Lamp's shims, and the network. Unlike Lamp's, which
    /// allows by default, it lists what is open, so the person's files, Lamp's folders and the apps Lamp installs
    /// (which can't be run without being read) stay closed by not being named. What the app shows and prints is
    /// closed as in the profile above when the settings say so. A command that needs more asks Codex's reviewer.
    /// Codex's profile has no rule for a port on this Mac (its network settings only steer a proxy of its own that
    /// is off), nor for running a program it can read, so Lamp's adb server and emulator aren't refused here as
    /// they are above: a Codex command that names their ports reaches them. What keeps an ordinary `adb` from
    /// coming across them is only that they're on ports of their own (`Edition.androidPorts`).
    static func codexPermissions(for project: LampProject, env: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let home = real(FileManager.default.homeDirectoryForCurrentUser.path)
        var paths: [(String, String)] = [(":root", "deny"), (":minimal", "read")]
        for path in ["/Volumes", "/Network", "/private/var/root", "/Library/Application Support", "/Library/Keychains"] {
            paths.append((path, "deny"))
        }
        let reading = [home + "/Library/Developer", home + "/.swiftpm", home + "/.gitconfig", home + "/.config/git",
                       "/Library/Developer", "/System/Library/Sandbox/Profiles", "/Applications", "/opt/homebrew", "/usr/local",
                       bin.path, zdot.path] + developerFolders(env: env)
        for path in reading where !paths.contains(where: { $0.0 == real(path) }) { paths.append((real(path), "read")) }
        // The per-user cache and temporary folders (the compiler's module cache is in the first), and the shared ones.
        let user = [confstr(_CS_DARWIN_USER_CACHE_DIR), confstr(_CS_DARWIN_USER_TEMP_DIR), env["TMPDIR"]].compactMap { $0 }
        for path in [home + "/Library/Caches", home + "/Library/org.swift.swiftpm", "/private/tmp"] + user where !path.isEmpty {
            let folder = kernelPath(path)
            if !paths.contains(where: { $0.0 == folder }) { paths.append((folder, "write")) }
        }
        // The app's folder by its own name, not Codex's workspace: Codex makes that of wherever the folder it starts
        // in leads, which a command could change between Lamp's look and Codex's start. A folder named here that is a
        // link, or leads through one, Codex refuses to start with or to run a command in.
        paths.append((project.realDir.path, "write"))
        if !Privacy.sharesPictures || !Privacy.sharesLog {
            paths.append((project.realDir.path + "/.lamp/runtime", "deny"))
        }
        let filesystem = paths.map { "\(Agent.tomlString($0.0))=\(Agent.tomlString($0.1))" }
        return "permissions.lamp={filesystem={" + filesystem.joined(separator: ",") + "},network={enabled=true}}"
    }

    /// One of the system's configuration strings (`getconf`), without its trailing slash; nil when it has none.
    private static func confstr(_ name: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard Darwin.confstr(name, &buffer, buffer.count) > 0 else { return nil }
        let path = String(cString: buffer)
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// Lamp's `swift` and shell startup files (above), written for an engine whose commands run in a sandbox of
    /// its own (Codex): false when they can't be.
    static func prepareShims() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return writeShims()
    }

    /// The environment that puts Lamp's programs first on the path of the commands an engine runs itself, as
    /// `launch` does for a confined one.
    static var shimEnvironment: String {
        "PATH=\(quoted(bin.path))':'\"$PATH\" ZDOTDIR=\(quoted(zdot.path))"
    }

    /// A whole run of a program, confined to the app with what it needs opened as well: `opening` for reading
    /// and writing, `reading` for reading. `offline`: with no network at all, for a command that has no need of one. Nil
    /// when the profile can't be written.
    static func wrapEngine(_ command: String, for project: LampProject, opening folders: [String], reading: [String] = [], offline: Bool = false) -> String? {
        guard let file = writeProfile(for: project, opening: folders, reading: reading, offline: offline) else { return nil }
        return launch(command, profile: file)
    }

    /// Where the profiles live: in Lamp's own folder, which every profile closes, so what sandbox-exec reads
    /// is what Lamp wrote and not something the agent could change. One file for each profile's text, named by
    /// it, so the commands of a turn share one; each use renews it, and one unused for an hour (a command may
    /// wait that long for the user) is cleared.
    static let folder = Edition.supportFolder.appendingPathComponent("Sandbox")

    /// When old profiles were last cleared: listing the folder for every command cost more than the command.
    nonisolated(unsafe) private static var cleared = Date.distantPast
    private static let lock = NSLock()

    private static func writeProfile(for project: LampProject, opening folders: [String] = [], reading: [String] = [], offline: Bool = false) -> URL? {
        let fm = FileManager.default
        let text = profile(for: project, opening: folders, reading: reading) + (offline ? "\n(deny network*)\n" : "")
        let digest = SHA256.hash(data: Data(text.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        let file = folder.appendingPathComponent("\(project.id)-\(digest).sb")
        lock.lock()
        defer { lock.unlock() }
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard writeShims() else { return nil }
        if Date().timeIntervalSince(cleared) > 60 {
            cleared = Date()
            let cutoff = Date().addingTimeInterval(-3600)
            for old in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            where old.pathExtension == "sb"
                && ((try? old.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantFuture) < cutoff {
                try? fm.removeItem(at: old)
            }
        }
        // Read back rather than trusted by name: the file is used only when it holds exactly this text.
        if (try? String(contentsOf: file, encoding: .utf8)) == text {
            try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            return file
        }
        try? fm.removeItem(at: file)
        guard fm.createFile(atPath: file.path, contents: Data(text.utf8),
                            attributes: [.posixPermissions: 0o600]) else { return nil }
        return file
    }

    /// The profile: everything allowed, then every person's files closed (all of /Users, the shared folder
    /// included, and anything mounted), then the places under this home a build needs opened again, Lamp's
    /// own folders closed, and the app's folder opened last (it sits inside Lamp's). Later rules win, so the
    /// order is the meaning. `folders` are opened too, for reading and writing; `reading` for reading.
    static func profile(for project: LampProject, opening folders: [String] = [], reading: [String] = []) -> String {
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
        // The Xcode in use, read only, wherever it is: one kept on another disk (under /Volumes, or a link from
        // /Applications into one) is closed above, and every compile would find no SDK.
        // The folders on the way to it can be looked at (not read): a tool reached through a link from /Applications
        // finds its own place with realpath, which stats every step (/Volumes, the disk), and the Swift driver that
        // can't says swift-build doesn't exist.
        for folder in developerFolders() {
            lines.append("(allow file-read* (subpath \(quotedPath(folder))))")
            var path = (folder as NSString).deletingLastPathComponent
            while path != "/" {
                lines.append("(allow file-read-metadata (literal \(quotedPath(path))))")
                path = (path as NSString).deletingLastPathComponent
            }
        }
        // Both Lamps' folders (keys, sign-ins, every other app) stay closed; the app's own folder opens.
        for name in Edition.lampFolderNames {
            lines.append("(deny file-read* file-write* (subpath \(quotedPath(support + "/" + name))))")
            // And the apps Lamp installs are for the person to run, not the command: running one needs no
            // read the profile closes (exec maps it), so it's refused by name. A command could otherwise
            // start another app with a library of its own inside (DYLD_INSERT_LIBRARIES) and read that
            // app's secrets out of Lamp through it (PeerProcess). The app's own build is unaffected: it's
            // built in its folder, not here.
            lines.append("(deny process-exec* (subpath \(quotedPath(real(home + "/Applications/" + name + " Apps")))))")
            // Nor what Xcode makes there for the phone (`Devices.buildsFolder`), for the same reason: closed to
            // reading, but a program in it could still be started.
            lines.append("(deny process-exec* (subpath \(quotedPath(support + "/" + name + "/Phone Builds"))))")
            // Each Lamp's adb server and emulator (`Edition.androidPorts`): through them a command could install,
            // remove or drive apps on the emulator and on the person's phone, which only Lamp does. At any address,
            // since the emulator's control interface listens on the network too. Nor may a command listen there in
            // their place, for Lamp to take it for its own server or emulator.
            if let ports = Edition.androidPorts(folder: name) {
                let numbers = ports.all
                lines.append("(deny network-outbound " + numbers.map { "(remote tcp \"*:\($0)\")" }.joined(separator: " ") + ")")
                lines.append("(deny network-bind " + numbers.map { "(local tcp \"*:\($0)\")" }.joined(separator: " ") + ")")
            }
            // The caller check (PeerProcess.isApp) would also accept a whole bundle replaced at the installed
            // path, signature valid by that copy's own requirement. That's safe only while this folder stays
            // unwritable from the command's sandbox (the file denies above), so nothing the builder makes can
            // be put there: keep it that way, or the check needs the replacement refused too.
        }
        // Nor may a command run adb or the emulator from the tools Lamp downloaded, which a build never needs: an adb
        // of its own would start a server that reaches the person's phone. One fetched from elsewhere still could,
        // with the person's say-so on the phone, since that server would have a key the phone has never allowed.
        lines.append("(deny process-exec* (subpath \(quotedPath(real(AndroidTools.sdkFolder.appendingPathComponent("platform-tools").path)))) "
            + "(subpath \(quotedPath(real(AndroidTools.sdkFolder.appendingPathComponent("emulator").path)))))")
        // Xcode's interface and asset compilers hand their work to helpers that stay running and are found through
        // shared memory named "ib…", whoever started them. A helper started outside the sandbox (by Lamp drawing an
        // icon, or by the person's own Xcode) would read and write for a command wherever it asked; one started in
        // another app's sandbox would see nothing of this app. Without that memory each command starts its own,
        // confined as it is. Other shared memory (Python's, say) stays open.
        lines.append(#"(deny ipc-posix-shm* (ipc-posix-name-regex #"^/?ib"))"#)
        // Lamp's shims and shell startup files may be read and run, and not changed.
        lines.append("(allow file-read* (subpath \(quotedPath(real(bin.path)))) (subpath \(quotedPath(real(zdot.path)))))")
        lines.append("(allow file-read* file-write* (subpath \(quotedPath(app))))")
        for folder in folders {
            lines.append("(allow file-read* file-write* (subpath \(quotedPath(real(folder)))))")
        }
        for folder in reading {
            lines.append("(allow file-read* (subpath \(quotedPath(real(folder)))))")
        }
        // Homebrew's folders belong to the person, so without this a command could put a program there (a
        // `codesign`, a `git`) that something running outside the sandbox later finds on its path and runs
        // unconfined. Reading and running what's there stays open; installing with brew doesn't. Last, so no
        // folder opened above reopens them.
        lines.append("(deny file-write* (subpath \(quotedPath(real("/opt/homebrew")))) (subpath \(quotedPath(real("/usr/local")))))")
        // The same goes for /Applications, which an admin can write: an Xcode dragged there is the person's,
        // so a command could swap its xcodebuild or simctl for Lamp to run as itself at the next simulator or
        // phone step, or change Lamp itself, or leave an app there that Lamp takes for Xcode. And the developer
        // folder in use wherever it lives, for the same reason. Running and reading what's there stays open.
        lines.append("(deny file-write* " + ([kernelPath("/Applications")] + developerFolders()).map { "(subpath \(quotedPath($0)))" }
            .joined(separator: " ") + ")")
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

    /// Where the developer tools Lamp runs as itself come from (`DeveloperTools.folder`): the one Lamp was
    /// given and the one chosen with xcode-select, read off its link rather than by running a program for each
    /// command. For an Xcode that's the whole app, not just its developer folder.
    static func developerFolders(env: [String: String] = ProcessInfo.processInfo.environment,
                                 selectLink: String = "/var/db/xcode_select_link") -> [String] {
        let given = [env["DEVELOPER_DIR"], try? FileManager.default.destinationOfSymbolicLink(atPath: selectLink)]
        var folders: [String] = []
        let needed = ["/tmp", NSTemporaryDirectory(), FileManager.default.homeDirectoryForCurrentUser.path].map(kernelPath)
        for case let folder? in given where folder.hasPrefix("/") {
            let path = kernelPath(folder)
            let bundle = path.range(of: ".app/").map { String(path[..<$0.lowerBound]) + ".app" } ?? path
            // Never a folder holding ones a command must write (a DEVELOPER_DIR of /tmp, say).
            guard bundle != "/", !needed.contains(where: { ($0 + "/").hasPrefix(bundle + "/") }), !folders.contains(bundle) else { continue }
            folders.append(bundle)
        }
        return folders
    }

    /// The path the kernel reports, through every link: `real` leaves /tmp as it is (resolving a link drops
    /// /private again), which a rule that must hold can't afford.
    private static func kernelPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return real(path) }
        defer { free(resolved) }
        return String(cString: resolved)
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
