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
            || ["Scaffold", "Imported from a shared file", "Fix a crash on launch"].contains(message)
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

    /// Newest first.
    static func list(_ project: LampProject) async -> [AppVersion] {
        var names: [String: String] = [:]
        _ = await Shell.run("git for-each-ref refs/tags/forge/ --sort=creatordate --format='%(*objectname)%1f%(contents:subject)'",
                            cwd: project.dir) { line in
            let parts = line.split(separator: "\u{1f}", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            if parts.count == 2, !parts[1].isEmpty { names[parts[0]] = parts[1] }
        }
        let titles = VersionTitles.saved(in: project)
        var versions: [AppVersion] = []
        _ = await Shell.run("git log --first-parent --format='%H%x1f%P%x1f%ct%x1f%(trailers:key=Lamp-Undid,valueonly,separator=%x2C)%(trailers:key=Forge-Undid,valueonly,separator=%x2C)%x1f%s'",   // Undos from before the rename keep the old trailer
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
        _ = await Shell.run(command, cwd: project.dir, env: ["LAMP_VERSION": version, "LAMP_NAME": name]) { _ in }
    }

    /// Puts the app's files back as they were in a version, without committing. Attachments stay:
    /// they're what people gave Lamp, and the chat still shows them.
    static func restoreFiles(_ project: LampProject, to version: AppVersion) async -> Bool {
        // Attachments and Lamp's own folder are left alone: a version from before the rename ignores .forge/,
        // not .lamp/, and clean would otherwise take the chat, token and sessions with it.
        let keep = "':!\(Attachments.folder)' ':!.lamp'"
        let ok = await Shell.run("git restore --source=\"$LAMP_VERSION\" --staged --worktree -- . \(keep) && git clean -fdq -e .lamp -- . \(keep)",
                                 cwd: project.dir, env: ["LAMP_VERSION": version.id]) { _ in } == 0
        // A version from before the rename calls the support library by its old names.
        if ok {
            // Before the restore is committed, so what comes back is already this Lamp's: the library's names
            // and the bundle id (an app copied from the other edition), with no change left over afterwards.
            Migration.normalize(project.dir, commit: false)
            Template.upgradeBuildScript(for: project)
        }
        return ok
    }

    /// Files changed since the last version, by a turn that was stopped or didn't finish.
    static func hasUnsavedChanges(_ project: LampProject) async -> Bool {
        var output = ""
        _ = await Shell.run("git status --porcelain -- . ':!\(Attachments.folder)'", cwd: project.dir) { output += $0 }
        return !output.trimmed.isEmpty
    }

    /// Unlike a failed commit, a clean tree proves there is nothing left to save. Include attachments
    /// and require Git to succeed, so a read failure can't pass for an already-saved request.
    static func isSaved(_ project: LampProject) async -> Bool {
        var output = ""
        let status = await Shell.run("git status --porcelain", cwd: project.dir) { output += $0 }
        return status == 0 && output.trimmed.isEmpty
    }

    /// Restores a version's files and saves the result as a new version. False when nothing changed.
    static func restore(_ project: LampProject, to version: AppVersion, message: String, trailer: String? = nil) async -> Bool {
        guard await restoreFiles(project, to: version) else { return false }
        return await save(project, message: message, trailer: trailer)
    }

    /// Saves the app's files as they are now as a new version. False when nothing changed.
    static func save(_ project: LampProject, message: String, trailer: String? = nil) async -> Bool {
        let trailerArgument = trailer.map { " -m \"\($0)\"" } ?? ""
        return await Shell.run("git add -A && ! git diff --cached --quiet && \(commit) -q -m \"$LAMP_MESSAGE\"\(trailerArgument)",
                               cwd: project.dir, env: ["LAMP_MESSAGE": message]) { _ in } == 0
    }

    static func head(_ project: LampProject) async -> String? {
        var output = ""
        guard await Shell.run("git rev-parse HEAD", cwd: project.dir, onLine: { output += $0 }) == 0 else { return nil }
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

    private static let prompt = """
    Write a title for one saved version of a small Mac app, from the change below. It's shown in a list of \
    versions so the user can find the one they want to go back to.

    Say what changed for the person using the app, in 2 to 5 plain words, starting with a past-tense verb \
    when it fits: "Added account shortcuts", "Fixed vanishing profile photo", "Darker sidebar", "First \
    version". Never mention files, code, types or Lamp. If the request and the change disagree, describe the \
    change. No quotes, no full stop.

    Respond with JSON: {"title": "..."}
    """

    /// Nil when the model couldn't be reached or gave something unusable.
    static func make(for version: AppVersion, in project: LampProject) async -> String? {
        var files: [String] = []
        _ = await Shell.run("git show --format= --name-only \"$LAMP_VERSION\"", cwd: project.dir,
                            env: ["LAMP_VERSION": version.id]) { if !$0.trimmed.isEmpty { files.append($0.trimmed) } }
        // Lamp refreshing the support code it puts in every app isn't a change the user made.
        if !files.isEmpty, files.allSatisfy({ $0 == "Sources/LampSupport.swift" }) { return "Lamp update" }
        var diff = ""
        _ = await Shell.run("git show --format= --unified=1 \"$LAMP_VERSION\" -- . ':!Sources/LampSupport.swift' ':!\(Attachments.folder)'",
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
                                                         model: AppAI.defaultModel.openRouter),
              let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let raw = object["title"] as? String else { return nil }
        let title = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’."))
        guard !title.isEmpty, title.split(separator: " ").count <= 7, title.count <= 48 else { return nil }
        return title
    }
}
