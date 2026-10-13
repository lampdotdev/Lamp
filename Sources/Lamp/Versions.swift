import Foundation
import os
import ImageIO
import UniformTypeIdentifiers

/// One saved state of an app. Every change Lamp commits is a version; people and the agent can name the
/// ones that matter. Restoring never discards anything: it adds a new version with the old files.
struct AppVersion: Identifiable, Hashable {
    let id: String          // the commit
    let parent: String?
    let date: Date
    let message: String     // the request that made it, or Lamp's own note ("Rename to …")
    var name: String?
    /// A short title a model wrote from what changed. Names people give win over it.
    var title: String?
    /// The version an Undo took back, so pressing Undo again keeps going back instead of redoing it.
    let undid: String?

    var label: String { name ?? title ?? message }

    /// Lamp wrote the message itself (Undo, Rename…), so it's already short and needs no title.
    var isLampNote: Bool {
        ["Undid “", "Restored to “", "Rename to "].contains { message.hasPrefix($0) }
            || ["Scaffold", "Imported from a shared file", "Updated from a shared file",
                "Before updating from a shared file", "Fix a crash on launch"].contains(message)
    }
    var shortID: String { String(id.prefix(8)) }
}

/// A version whose Name… alert is showing.
struct VersionNaming: Equatable {
    let project: LampProject
    let version: AppVersion
}

/// The app's git history, presented as versions. Git never shows in the interface.
enum Versions {
    static let commit = "git -c user.name=Lamp -c user.email=lamp@localhost commit"

    /// Lamp's own git. The app's folder is the agent's to write, its history included, and git runs the
    /// programs a repository names (hooks, filters, a signing program, and more with every release), so
    /// what the agent leaves there would run with whatever Lamp's git is allowed. So Lamp's git is allowed
    /// what the agent's own commands are: it runs under the same sandbox (`Sandbox`), confined to the app's
    /// folder. Nothing in the history has to be trusted, checked or cleaned, and nothing the agent does with
    /// git has to be refused.
    static func git(_ command: String, cwd: URL, env: [String: String] = [:],
                    onLine: @escaping @MainActor (String) -> Void = { _ in }) async -> Int32 {
        guard let confined = confined(command, in: cwd) else { return unconfined }
        return await Shell.run(confined, cwd: cwd, env: env.merging(environment) { $1 }, onLine: onLine)
    }

    /// The same, for the one caller that can't await (the migration, at launch).
    static func gitBlocking(_ command: String, cwd: URL) -> Subprocess.Result {
        guard let confined = confined(command, in: cwd) else {
            return Subprocess.Result(status: unconfined, output: "", errors: "", timedOut: false)
        }
        return Subprocess.runBlocking("/bin/zsh", ["-c", confined], cwd: cwd, env: environment, mergeErrors: false, timeout: 120)
    }

    /// What a git command returns when the sandbox couldn't be set up: it isn't run loose instead.
    static let unconfined: Int32 = 126

    /// The command as it is run: under the profile the agent's commands get for this folder, with the
    /// person's own git files that live elsewhere in the home folder opened for reading.
    static func confined(_ command: String, in folder: URL) -> String? {
        let app = LampProject(id: folder.lastPathComponent, name: "", exe: "", dir: folder)
        let wrapped = Sandbox.wrapEngine(command, for: app, opening: [], reading: personalFiles())
        if wrapped == nil { NSLog("Lamp: git was not run in %@: the sandbox could not be set up", folder.path) }
        return wrapped
    }

    /// Lamp's own runs don't need what the sandbox takes away, and say so rather than fail: signing (the
    /// person's keys are closed to the sandbox; these versions are Lamp's, not theirs) and hooks and the
    /// file-watcher command (which would only stall or stop a save). Settings given this way win over the
    /// repository's and the person's.
    static let environment: [String: String] = {
        let settings = [("core.hooksPath", "/dev/null"), ("core.fsmonitor", "false"), ("commit.gpgSign", "false"),
                        ("tag.gpgSign", "false"), ("tag.forceSignAnnotated", "false")]
        // Lamp looks at an app's state while a turn is saving it (the chat asks whether there's anything unsaved
        // as lines arrive). A look would otherwise take the index's lock for a moment to tidy it, and a save
        // that met the lock failed. With this, git's own switch for looks made in the background, they leave it alone.
        var environment = ["GIT_CONFIG_COUNT": "\(settings.count)", "GIT_OPTIONAL_LOCKS": "0"]
        for (index, setting) in settings.enumerated() {
            environment["GIT_CONFIG_KEY_\(index)"] = setting.0
            environment["GIT_CONFIG_VALUE_\(index)"] = setting.1
        }
        return environment
    }()

    /// The person's own git files that the sandbox doesn't already open: Mac-wide settings kept in more than
    /// one file (git stops, saving nothing, at a settings file it is told to read and isn't allowed to; one
    /// that isn't there it passes over), a settings file
    /// moved with GIT_CONFIG_GLOBAL, and the ignore and attributes files those settings name (a
    /// `~/.gitignore_global`, say: without it Lamp would save what the person ignores everywhere). They are
    /// worked out away from any app's folder, and again only when one of the settings files has changed:
    /// asking git costs more than the git command it is asked for. That asking is git reading the person's
    /// own settings files, which the sandbox closes, so it is the one git call of Lamp's that isn't confined:
    /// it reads files the agent can't write and runs no program.
    ///
    /// What the settings name is opened only when it is a file, and never when it is in Lamp's own folders
    /// (keys, sign-ins, every other app): a setting that names a folder, the home folder say, would
    /// otherwise open all of it, Lamp's included.
    private static func personalFiles() -> [String] {
        let lamps = ["Lamp", "Lamp Dev"].map {
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/\($0)")
                .resolvingSymlinksInPath().standardizedFileURL.path
        }
        return namedFiles().filter { named in
            let path = URL(fileURLWithPath: named).resolvingSymlinksInPath().standardizedFileURL.path
            var folder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &folder), !folder.boolValue else { return false }
            return !lamps.contains { path == $0 || path.hasPrefix($0 + "/") }
        }
    }

    private static func namedFiles() -> [String] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let moved = ProcessInfo.processInfo.environment["GIT_CONFIG_GLOBAL"]?.nilIfEmpty
        let starts = moved.map { [$0] } ?? [home + "/.gitconfig", home + "/.config/git/config"]
        func stamp(_ files: [String]) -> String {
            files.map { "\($0)@\(((try? fm.attributesOfItem(atPath: $0))?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)" }
                .joined(separator: "\n")
        }
        func ask(_ arguments: [String]) -> String? {
            let answer = Subprocess.runBlocking("/usr/bin/git", ["config"] + arguments, cwd: URL(fileURLWithPath: "/"),
                                                mergeErrors: false, timeout: 10)
            return answer.ok ? answer.output : nil
        }
        return asked.withLock { known in
            guard known.starts != starts || known.stamp != stamp(known.settings) else { return known.files }
            // Every settings file the person's own may bring in, whatever the condition on it: which apply
            // depends on the folder git runs in. Each is read on its own, so one names the next.
            var settings: [String] = []
            var next = starts
            while let file = next.popLast(), settings.count < 50 {
                guard !settings.contains(file) else { continue }
                settings.append(file)
                let included = ask(["--file", file, "--type=path", "-z", "--get-regexp", #"^include(if\..*)?\.path$"#]) ?? ""
                for entry in included.split(separator: "\0") {
                    guard let path = entry.split(separator: "\n", maxSplits: 1).last.map(String.init), !path.isEmpty else { continue }
                    next.append(path.hasPrefix("/") ? path : URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: file).deletingLastPathComponent()).standardizedFileURL.path)
                }
            }
            // The ignore and attributes files, from each settings file on its own for the same reason.
            var files = settings
            for file in settings {
                let named = ask(["--file", file, "--type=path", "-z", "--get-regexp", #"^core\.(excludesfile|attributesfile)$"#]) ?? ""
                for entry in named.split(separator: "\0") {
                    if let path = entry.split(separator: "\n", maxSplits: 1).last.map(String.init), path.hasPrefix("/"), !files.contains(path) {
                        files.append(path)
                    }
                }
            }
            known = (starts, settings, stamp(settings), files)
            return files
        }
    }

    private static let asked = OSAllocatedUnfairLock<(starts: [String], settings: [String], stamp: String, files: [String])>(
        initialState: ([], [], "", []))

    /// Newest first.
    static func list(_ project: LampProject) async -> [AppVersion] {
        var names: [String: String] = [:]
        _ = await git("git for-each-ref refs/tags/forge/ --sort=creatordate --format='%(*objectname)%1f%(contents:subject)'",
                            cwd: project.dir) { line in
            let parts = line.split(separator: "\u{1f}", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            if parts.count == 2, !parts[1].isEmpty { names[parts[0]] = parts[1] }
        }
        let titles = VersionTitles.saved(in: project)
        var versions: [AppVersion] = []
        _ = await git("git log --first-parent --format='%H%x1f%P%x1f%ct%x1f%(trailers:key=Lamp-Undid,valueonly,separator=%x2C)%(trailers:key=Forge-Undid,valueonly,separator=%x2C)%x1f%s'",   // Undos from before the rename keep the old trailer
                            cwd: project.dir) { line in
            let parts = line.split(separator: "\u{1f}", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 5, let seconds = TimeInterval(parts[2]) else { return }
            versions.append(AppVersion(id: parts[0], parent: parts[1].split(separator: " ").first.map(String.init),
                                       date: Date(timeIntervalSince1970: seconds), message: parts[4],
                                       name: names[parts[0]], title: titles[parts[0]], undid: parts[3].nilIfEmpty))
        }
        return versions
    }

    /// Finds a version from the short id the agent was given.
    static func find(_ id: String, in versions: [AppVersion]) -> AppVersion? {
        let id = id.trimmed.lowercased()
        guard id.count >= 4 else { return nil }
        return versions.first { $0.id.hasPrefix(id) }
    }

    /// What Undo goes back to: the version before the current one. When the current one is itself an Undo,
    /// it goes back past what that Undo returned to, so repeated Undos step back through the history.
    /// Returns the version being undone too, for the message.
    static func undoTarget(in versions: [AppVersion]) -> (undoing: AppVersion, target: AppVersion)? {
        let byID = Dictionary(versions.map { ($0.id, $0) }) { first, _ in first }
        // The rename's own commits aren't anything the person did: Undo looks straight past them.
        func pastRenames(_ version: AppVersion) -> AppVersion {
            var version = version
            while version.message == "Rename to Lamp", let parent = version.parent.flatMap({ byID[$0] }) { version = parent }
            return version
        }
        guard let first = versions.first else { return nil }
        var current = pastRenames(first)
        while let undid = current.undid.flatMap({ byID[$0] }), let before = undid.parent.flatMap({ byID[$0] }) {
            current = pastRenames(before)
        }
        guard let target = current.parent.flatMap({ byID[$0] }).map(pastRenames) else { return nil }
        return (current, target)
    }

    /// Names a version, replacing any earlier name. An empty name removes it.
    static func name(_ project: LampProject, _ version: String, _ name: String) async {
        let name = name.trimmed
        let command = name.isEmpty
            ? "git tag -d \"forge/$LAMP_VERSION\""
            : "git -c user.name=Lamp -c user.email=lamp@localhost tag -f -a \"forge/$LAMP_VERSION\" -m \"$LAMP_NAME\" \"$LAMP_VERSION\""
        _ = await git(command, cwd: project.dir, env: ["LAMP_VERSION": version, "LAMP_NAME": name])
    }

    /// Puts the app's files back as they were in a version, without committing. Attachments stay:
    /// they're what people gave Lamp, and the chat still shows them.
    static func restoreFiles(_ project: LampProject, to version: AppVersion) async -> Bool {
        // Attachments and Lamp's own folder are left alone: a version from before the rename ignores .forge/,
        // not .lamp/, and clean would otherwise take the chat, token and sessions with it.
        let keep = "':!\(Attachments.folder)' ':!.lamp'"
        let ok = await git("git restore --source=\"$LAMP_VERSION\" --staged --worktree -- . \(keep) && git clean -fdq -e .lamp -- . \(keep)",
                                 cwd: project.dir, env: ["LAMP_VERSION": version.id]) { _ in } == 0
        // A version from before the rename calls the support library by its old names.
        if ok {
            // Before the restore is committed, so what comes back is already this Lamp's: the library's names
            // and the bundle id (an app copied from the other edition), with no change left over afterwards.
            Migration.normalize(project.dir, commit: false)
            try? Template.writeOwnedFiles(for: project)   // the build writes them again, and stops if it can't
        }
        return ok
    }

    /// Files changed since the last version, by a turn that was stopped or didn't finish.
    static func hasUnsavedChanges(_ project: LampProject) async -> Bool {
        var output = ""
        _ = await git("git status --porcelain -- . ':!\(Attachments.folder)'", cwd: project.dir) { output += $0 }
        return !output.trimmed.isEmpty
    }

    /// Restores a version's files and saves the result as a new version. False when nothing changed.
    static func restore(_ project: LampProject, to version: AppVersion, message: String, trailer: String? = nil) async -> Bool {
        guard await restoreFiles(project, to: version) else { return false }
        return await save(project, message: message, trailer: trailer)
    }

    /// Saves the app's files as they are now as a new version. False when nothing changed.
    static func save(_ project: LampProject, message: String, trailer: String? = nil) async -> Bool {
        let trailerArgument = trailer.map { " -m \"\($0)\"" } ?? ""
        return await commitAll("-q -m \"$LAMP_MESSAGE\"\(trailerArgument)", in: project.dir, env: ["LAMP_MESSAGE": message]) == .saved
    }

    /// How a save ended. `failed` is a save that had something to save and couldn't: not the same as nothing
    /// having changed, which is how it used to pass.
    enum Saved { case saved, nothingToSave, failed }

    /// How long a save waits before trying again, each time it is shut out.
    static let savePauses: [Duration] = [.milliseconds(250), .milliseconds(600)]

    /// Stages everything and commits it, with `arguments` for the commit. A save can be shut out for a moment
    /// by something else at work in the folder (the agent's own git, say, which is free to use it), so one
    /// that fails with changes still unsaved is tried again before it's given up on.
    static func commitAll(_ arguments: String, in dir: URL, env: [String: String] = [:]) async -> Saved {
        for attempt in 0...savePauses.count {
            if await git("git add -A && \(commit) \(arguments)", cwd: dir, env: env) == 0 { return .saved }
            var unsaved = ""
            let looked = await git("git status --porcelain", cwd: dir) { unsaved += $0 }
            if looked == 0, unsaved.trimmed.isEmpty { return .nothingToSave }
            if attempt < savePauses.count { try? await Task.sleep(for: savePauses[attempt]) }
        }
        return .failed
    }

    static func head(_ project: LampProject) async -> String? {
        var output = ""
        guard await git("git rev-parse HEAD", cwd: project.dir, onLine: { output += $0 }) == 0 else { return nil }
        return output.trimmed.nilIfEmpty
    }

    // MARK: - Pictures

    /// A small picture of the app's window as it looked in a version.
    static func pictureURL(in project: LampProject, for version: String) -> URL {
        project.dir.appendingPathComponent(".lamp/versions/\(version).jpg")
    }

    /// Saves a reduced copy of a screenshot as a version's picture.
    static func savePicture(_ screenshot: URL, in project: LampProject, for version: String) {
        Previews.write(screenshot, to: pictureURL(in: project, for: version), maxPixels: 900, quality: 0.8)
    }

    static func copyPicture(in project: LampProject, from version: String, to other: String) {
        let source = pictureURL(in: project, for: version)
        let target = pictureURL(in: project, for: other)
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.copyItem(at: source, to: target)
    }

    // MARK: - Telling the agent

    private static func noteURL(_ project: LampProject) -> URL {
        project.dir.appendingPathComponent(".lamp/restored-note")
    }

    /// Remembers a restore so the agent hears about it on the next request. Its conversation still
    /// remembers files that are no longer there.
    static func remember(_ project: LampProject, restoredTo label: String, from date: Date) {
        let note = """


        Note from Lamp: before this message, the user went back to an earlier version of the app \
        (“\(label)”, from \(date.formatted(date: .abbreviated, time: .shortened))). The files may no longer \
        match what you remember from this conversation, so read them again before editing.
        """
        try? note.write(to: noteURL(project), atomically: true, encoding: .utf8)
    }

    /// Remembers that the app's code was replaced by a newer version someone shared, so the agent hears about
    /// it on the next request. Its conversation still remembers the code from before.
    static func rememberUpdate(_ project: LampProject) {
        let note = """


        Note from Lamp: before this message, the user updated this app from a newer version of it that \
        someone shared with them. Its code, files and description were replaced, so they may no longer match \
        what you remember from this conversation: read them again before editing.
        """
        try? note.write(to: noteURL(project), atomically: true, encoding: .utf8)
    }

    /// Remembers that a request was taken back and sent again in other words, so the agent hears about it
    /// with the new one. Its conversation still holds the old request and everything that followed it.
    static func remember(_ project: LampProject, tookBack request: String) {
        let old = request.count > 400 ? String(request.prefix(400)) + "…" : request
        let note = """


        Note from Lamp: the message above replaces an earlier one. The user went back to this message of \
        theirs in the conversation, changed it to the message above and sent it again:

        “\(old)”

        That earlier message and everything after it (their later requests, your replies and your changes) no \
        longer count, and the app's files are back to how they were just before it. Don't bring any of that \
        back unless the message above asks for it, and read the files again before editing.
        """
        try? note.write(to: noteURL(project), atomically: true, encoding: .utf8)
    }

    /// The note about a restore since the last request. It stays until the agent has had it (`forgetNote`).
    static func note(for project: LampProject) -> String {
        (try? String(contentsOf: noteURL(project), encoding: .utf8)) ?? ""
    }

    static func forgetNote(for project: LampProject) {
        try? FileManager.default.removeItem(at: noteURL(project))
    }

    /// What a version made by going back to `version` is called. Going back to one that was itself made by
    /// going back keeps that one's words, so the name never quotes itself: Restored to “Restored to “…””.
    static func restoredMessage(to version: AppVersion) -> String {
        if version.name == nil, version.message.hasPrefix("Restored to “") { return version.message }
        return "Restored to “\(version.label)”"
    }

    /// The history as the agent's `list_versions` tool shows it.
    static func describe(_ versions: [AppVersion], limit: Int = 30) -> String {
        guard !versions.isEmpty else { return "There are no versions yet." }
        var lines = versions.prefix(limit).enumerated().map { index, version in
            var line = "\(version.shortID) · \(version.date.formatted(date: .abbreviated, time: .shortened)) · "
            line += version.name.map { "named “\($0)” (made by: \(version.message))" } ?? version.message
            if index == 0 { line += " · current" }
            return line
        }
        if versions.count > limit { lines.append("…and \(versions.count - limit) older versions.") }
        return "Versions, newest first:\n" + lines.joined(separator: "\n")
    }
}

/// Short titles for versions, written by a small model from what actually changed, so the list reads
/// "Added account shortcuts" instead of the whole request. Kept in .lamp/version-titles.json.
enum VersionTitles {
    private static func url(_ project: LampProject) -> URL {
        project.dir.appendingPathComponent(".lamp/version-titles.json")
    }

    static func saved(in project: LampProject) -> [String: String] {
        (try? Data(contentsOf: url(project))).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    static func save(_ title: String, for version: String, in project: LampProject) {
        var titles = saved(in: project)
        titles[version] = title
        if let data = try? JSONEncoder().encode(titles) { try? data.write(to: url(project)) }
    }

    /// The titles the prompt shows as examples. One of them back as the answer is the model repeating the
    /// prompt, so the version keeps the request as its label. ("First version" is a real answer, and stays.)
    static let examples = ["Added account shortcuts", "Fixed vanishing profile photo", "Darker sidebar"]

    private static let prompt = """
    Write a title for one saved version of a small app, from the change below. It's shown in a list of \
    versions so the user can find the one they want to go back to.

    Say what changed for the person using the app, in 2 to 5 plain words, starting with a past-tense verb \
    when it fits: \(examples.map { "\"\($0)\"" }.joined(separator: ", ")), "First \
    version". Never mention files, code, types or Lamp. If the request and the change disagree, describe the \
    change. No quotes, no full stop.

    Respond with JSON: {"title": "..."}
    """

    /// Nil when the model couldn't be reached or gave something unusable.
    static func make(for version: AppVersion, in project: LampProject) async -> String? {
        var files: [String] = []
        _ = await Versions.git("git show --format= --name-only \"$LAMP_VERSION\"", cwd: project.dir,
                            env: ["LAMP_VERSION": version.id]) { if !$0.trimmed.isEmpty { files.append($0.trimmed) } }
        // Lamp refreshing the support code it puts in every app isn't a change the user made.
        if !files.isEmpty, files.allSatisfy({ $0 == "Sources/LampSupport.swift" || $0 == Template.widgetFolder + "/" + Template.widgetSupportFile }) { return "Lamp update" }
        var diff = ""
        _ = await Versions.git("git show --format= --unified=1 \"$LAMP_VERSION\" -- . ':!Sources/LampSupport.swift' ':!\(Template.widgetFolder)/\(Template.widgetSupportFile)' ':!\(Attachments.folder)'",
                            cwd: project.dir, env: ["LAMP_VERSION": version.id]) { line in
            if diff.count < 8000 { diff += line + "\n" }
        }
        let request = """
        \(prompt)

        The user asked for:
        \(version.message.prefix(1500))

        Files changed: \(files.joined(separator: ", "))

        The change:
        \(diff)
        """
        guard let (text, _) = try? await AppAI.complete(prompt: request, images: [], system: "", json: true,
                                                         model: await AppAI.helperModel()),
              let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let raw = object["title"] as? String else { return nil }
        return title(from: raw, asked: version.message)
    }

    /// The model's title tidied, or nil when it's unusable: too long, or an example from the prompt.
    static func title(from raw: String, asked: String) -> String? {
        let title = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’."))
        guard !title.isEmpty, title.split(separator: " ").count <= 7, title.count <= 48,
              !AppAI.parrots(title, examples: examples, asked: asked) else { return nil }
        return title
    }
}
