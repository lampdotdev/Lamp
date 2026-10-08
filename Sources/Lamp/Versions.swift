import Foundation
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

    /// Lamp's own git, which runs outside the sandbox on a folder the agent's commands can write. Git runs
    /// programs named by what it finds in a repository, so four things keep that to what Lamp put there:
    /// the app's `.git` is read-only to a confined command and to the file tools (Sandbox, Privacy); its
    /// settings are cut back to the ones Lamp knows before every call (`own`), which is what covers a `.git`
    /// written before any of this; hooks and the file-watcher command are off whatever a repository says;
    /// and a repository inside the app's folder (a clone, say), whose `.git` the agent can write, is never
    /// entered (`stage` keeps such folders out of the history, and status doesn't look inside them).
    static func git(_ command: String, cwd: URL, env: [String: String] = [:],
                    onLine: @escaping @MainActor (String) -> Void = { _ in }) async -> Int32 {
        await Shell.run(script(command), cwd: cwd, env: env.merging(environment) { $1 }, onLine: onLine)
    }

    /// The same, for the one caller that can't await (the migration, at launch).
    static func gitBlocking(_ command: String, cwd: URL) -> Subprocess.Result {
        Subprocess.runBlocking("/bin/zsh", ["-c", script(command)], cwd: cwd, env: environment, mergeErrors: false, timeout: 120)
    }

    /// What is run for a git command: nothing at all unless the history is Lamp's to trust.
    static func script(_ command: String) -> String { "\(own) && {\n\(command)\n}" }

    /// Settings given this way win over the repository's, and reach the git that git itself starts.
    static let environment = [
        "GIT_CONFIG_COUNT": "2",
        "GIT_CONFIG_KEY_0": "core.hooksPath", "GIT_CONFIG_VALUE_0": "/dev/null",
        "GIT_CONFIG_KEY_1": "core.fsmonitor", "GIT_CONFIG_VALUE_1": "false",
    ]

    /// Makes the history's settings Lamp's own before git reads them. Git has no way to be told "don't trust
    /// this repository's settings", and the ones that make it run a program are too many to switch off one
    /// by one (filters, text converters, signing programs, includes, hooks named in settings, and more with
    /// each release), so every setting but the plain ones below is removed, with git's own command for it.
    /// An app's history from before `.git` was closed can hold anything; one written since holds nothing else.
    ///
    /// First, the history has to be a real folder in the app, with its settings a real file of its own: a
    /// `.git` that points somewhere else (a file or a link, or a shared folder named inside it) leads to a
    /// place the agent can still write, and then git isn't run at all: Lamp saves nothing until the folder is
    /// put right. A settings file with a second name (a hard link) can be written by that name, so it is
    /// replaced by a copy in a file made new for it, never one that might already be there under a known name.
    private static let own = #"""
    { { [ ! -e .git ] && [ ! -L .git ]; } || { [ -d .git ] && [ ! -L .git ] && [ ! -e .git/commondir ] && [ ! -L .git/config ] \
    && { [ ! -e .git/config ] || [ "$(stat -f %l .git/config)" = 1 ] || { fresh="$(mktemp .git/config.XXXXXXXX)" && cat .git/config > "$fresh" && mv -f "$fresh" .git/config; }; } \
    && git config --file .git/config --name-only -z --list 2>/dev/null | sort -zu | while IFS= read -r -d '' key; do case "$key" in \
    core.repositoryformatversion|core.filemode|core.bare|core.logallrefupdates|core.ignorecase|core.precomposeunicode|core.symlinks) ;; \
    extensions.objectformat|user.name|user.email|remote.*.url|remote.*.fetch|branch.*.remote|branch.*.merge) ;; \
    *) git config --file .git/config --unset-all "$key" || exit 1 ;; esac; done; }; }
    """#

    /// `git add -A`, without the repositories inside the app's folder. Git records one as a link to a commit
    /// (none of its files), and from then on runs git inside it, with its settings, to see whether it changed.
    /// Git has no switch for "never go in there", so this is a guard of Lamp's own: any link already recorded
    /// is dropped before anything is added, and any just added is dropped again and its folder put on the
    /// history's own ignore list, so it stops counting as unsaved work. The list is started again at every
    /// save: a folder that has stopped being a repository is the app's files again, and is saved.
    static let stage = "{ \(forget) && \(unlink) && git add -A && \(unlink); }"

    /// Lamp's part of the ignore list is everything from this line on.
    private static let listed = "# Lamp: repositories inside the app's folder"
    private static let forget = """
    { [ ! -f .git/info/exclude ] || sed -i '' "/^\(listed)$/,\\$d" .git/info/exclude; } \\
    && mkdir -p .git/info && echo "\(listed)" >> .git/info/exclude
    """

    /// Takes every such link out of what's staged. Names end at a zero byte, so no name can hide one; a name
    /// with a line break in it can't be written as an ignore rule, and is dropped each time instead.
    private static let unlink = #"""
    git ls-files -s -z | while IFS= read -r -d '' entry; do case "$entry" in 160000\ *) name=${entry#*$'\t'}; \
    git rm -qf --cached -- ":(literal)$name" || exit 1; \
    case "$name" in *$'\n'*) ;; *) printf '/%s/\n' "$name" | sed 's/[^A-Za-z0-9\/._-]/\\&/g' >> .git/info/exclude ;; esac ;; \
    esac; done
    """#

    /// For `git status`: what's inside a repository in the app's folder is not Lamp's to look at.
    static let closed = "--ignore-submodules=all"

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
        _ = await git("git status --porcelain \(closed) -- . ':!\(Attachments.folder)'", cwd: project.dir) { output += $0 }
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
        return await git("\(stage) && ! git diff --cached --quiet && \(commit) -q -m \"$LAMP_MESSAGE\"\(trailerArgument)",
                               cwd: project.dir, env: ["LAMP_MESSAGE": message]) { _ in } == 0
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
        let url = pictureURL(in: project, for: version)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 900,
                       kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(screenshot as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        CGImageDestinationFinalize(destination)
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
        if !files.isEmpty, files.allSatisfy({ $0 == "Sources/LampSupport.swift" }) { return "Lamp update" }
        var diff = ""
        _ = await Versions.git("git show --format= --unified=1 \"$LAMP_VERSION\" -- . ':!Sources/LampSupport.swift' ':!\(Attachments.folder)'",
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
