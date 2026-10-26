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
    /// The app's name from this version on and the one it had before, when this version changed it (a rename, or
    /// an Undo or restore across one). The name is kept in Lamp's own folder, which versions don't hold, so the
    /// versions that change it carry it, and going back to a version brings back the name it had (`name(at:in:)`).
    var renamedTo: String? = nil
    var renamedFrom: String? = nil
    /// The kinds of app the wish asked for when this version was saved (`LampProject.apps`), kept in Lamp's own folder
    /// as the name is, and so carried by each version Lamp saves (`appsTrailer`), a device's app with its device. Nil for
    /// a version saved without it.
    var apps: [WishApp]? = nil

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
        return await Shell.run(confined, cwd: cwd, env: env.merging(environment) { $1 }, login: false, onLine: onLine)
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
        let lamps = Edition.lampFolderNames.map {
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
            let answer = Subprocess.runBlocking(DeveloperTools.path("git"), ["config"] + arguments, cwd: URL(fileURLWithPath: "/"),
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
        _ = await git("git log --first-parent --format='%H%x1f%P%x1f%ct%x1f%(trailers:key=Lamp-Undid,valueonly,separator=%x2C)%(trailers:key=Forge-Undid,valueonly,separator=%x2C)%x1f%(trailers:key=Lamp-Name,valueonly,separator=%x2C)%x1f%(trailers:key=Lamp-Renamed-From,valueonly,separator=%x2C)%x1f%(trailers:key=Lamp-Apps,valueonly,separator=%x2C)%x1f%s'",   // Undos from before the rename keep the old trailer
                            cwd: project.dir) { line in
            let parts = line.split(separator: "\u{1f}", maxSplits: 7, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 8, let seconds = TimeInterval(parts[2]) else { return }
            let message = parts[7]
            // A rename saved before versions carried the name says the new one in its message, and not the old.
            let older = message.hasPrefix("Rename to ") && message != "Rename to Lamp" ? String(message.dropFirst("Rename to ".count)) : nil
            versions.append(AppVersion(id: parts[0], parent: parts[1].split(separator: " ").first.map(String.init),
                                       date: Date(timeIntervalSince1970: seconds), message: message,
                                       name: names[parts[0]], title: titles[parts[0]], undid: parts[3].nilIfEmpty,
                                       renamedTo: parts[4].trimmed.nilIfEmpty ?? older, renamedFrom: parts[5].trimmed.nilIfEmpty,
                                       apps: apps(from: parts[6])))
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

    /// The app's name in `version`: the name given by the latest version at or before it that changed the name, else
    /// the name the first one after it changed from. Nil when no version says (an app never renamed, or renamed only
    /// by a Lamp from before versions carried the name), and the name stays as it is.
    static func name(at version: AppVersion, in versions: [AppVersion]) -> String? {
        let byID = Dictionary(versions.map { ($0.id, $0) }) { first, _ in first }
        var walked: AppVersion? = version
        while let at = walked {
            if let name = at.renamedTo { return name }
            walked = at.parent.flatMap { byID[$0] }
        }
        // `versions` is newest first: the first one after `version` to change the name is the nearest above it.
        guard let index = versions.firstIndex(where: { $0.id == version.id }) else { return nil }
        return versions[..<index].last { $0.renamedTo != nil }?.renamedFrom
    }

    /// The kinds of app a wish asked for in `version`: those the latest version at or before it that says them gave
    /// (`appsTrailer`). Nil when none does (versions saved before versions carried them), and the list is then what the
    /// version's files make.
    static func apps(at version: AppVersion, in versions: [AppVersion]) -> [WishApp]? {
        let byID = Dictionary(versions.map { ($0.id, $0) }) { first, _ in first }
        var walked: AppVersion? = version
        while let at = walked {
            if let apps = at.apps { return apps }
            walked = at.parent.flatMap { byID[$0] }
        }
        return nil
    }

    /// The `Lamp-Apps` trailer as a version carries it: the kinds, by name, between spaces, a device's app with its
    /// integration after a colon ("device:roku"), so one restored while it waits is made for that device. One the version
    /// names that this Lamp doesn't know is passed over (as an earlier Lamp passes over "device:roku").
    static func apps(from trailer: String) -> [WishApp]? {
        guard let said = trailer.split(separator: ",").first.map({ String($0).trimmed }), !said.isEmpty else { return nil }
        return said.split(separator: " ").compactMap { word in
            let parts = word.split(separator: ":", maxSplits: 1).map(String.init)
            return Platform(rawValue: parts[0]).map { WishApp(kind: $0, integration: parts.count > 1 ? parts[1] : nil) }
        }
    }

    /// One app as the trailer says it.
    nonisolated static func trailerWord(_ app: WishApp) -> String { app.kind.rawValue + (app.integration.map { ":" + $0 } ?? "") }

    /// What every version Lamp saves of a wish carries: the kinds of app it asks for then, whether made or waiting
    /// (`Parts.wanted`), since the list is kept in meta.json, which no version holds. Going back to a version brings
    /// its list back with its files (`restoreFiles`), so an Undo of an app asked for and still waiting takes it off the
    /// list too, rather than leaving it to be made at the next turn. Nil for a folder that isn't a wish's.
    nonisolated static func appsTrailer(in dir: URL) -> String? {
        guard let kinds = listedKinds(in: dir), !kinds.isEmpty else { return nil }
        return "Lamp-Apps: " + kinds.map(trailerWord).joined(separator: " ")
    }

    /// The kinds of app the wish in this folder asks for now, made or waiting.
    private nonisolated static func listedKinds(in dir: URL) -> [WishApp]? {
        guard var wish = Store.readWish(at: dir) else { return nil }
        wish.partFolders = Parts.folders(in: dir)
        return Parts.wanted(in: wish, parts: Parts.load(wish)).map { WishApp(kind: $0.kind, integration: $0.integration) }
    }

    /// Whether going back to the latest version would give the wish another list of apps than it has, its files being
    /// the same: the list changed and nothing else did (an app asked for that this Mac can't make yet). Read as a restore
    /// reads it: the nearest version that says one, with what the files make.
    private static func listDiffersFromLatest(in dir: URL) async -> Bool {
        guard var wish = Store.readWish(at: dir), let now = listedKinds(in: dir) else { return false }
        var said = ""
        _ = await git("git log --first-parent --format='%(trailers:key=Lamp-Apps,valueonly,separator=%x2C)'", cwd: dir) { line in
            if said.isEmpty { said = line.trimmed }
        }
        wish.partFolders = Parts.folders(in: dir)
        wish.apps = apps(from: said) ?? []
        let latest = Parts.wanted(in: wish, parts: Parts.load(wish)).map(trailerWord)
        return Set(latest) != Set(now.map(trailerWord))
    }

    /// What a version that changes the app's name carries, for `name(at:in:)`.
    static func nameTrailers(from old: String, to new: String) -> String {
        "Lamp-Name: \(new)\nLamp-Renamed-From: \(old)"
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
    /// `name` is the name the restore gives back, when it gives one: Lamp's own files carry the app's name, so they're
    /// written under it before the restore is saved, or the next build writes them again and leaves the app unsaved.
    static func restoreFiles(_ project: LampProject, to version: AppVersion, name: String? = nil) async -> Bool {
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
            // A version from before the app was made for other devices brings back its kind with its code, so
            // Lamp's own files and its next build are for what that code was written for (Store.followRestoredKind).
            var project = name.map { project.named($0) } ?? project
            var changed = false
            if let kind = Template.platform(fromPackageIn: project.dir), kind != project.platform {
                project.platform = kind
                if !kind.reaches(.ios) { project.device = nil }
                project.integration = kind.target.recipe.integration(project.dir)
                changed = true
            }
            if !project.isPart {
                // The wish's list of apps is the version's, as its name is: what each app's building blocks are written
                // from below, and what the next turn makes. Each app the version's files have is on it, and one it asked
                // for and didn't have keeps what stops it here, so it isn't tried again at every turn.
                project.partFolders = Parts.folders(in: project.dir)
                let parts = Parts.load(project)
                let asked = await apps(at: version, in: list(project)) ?? []
                var listed = project
                // A device's app is for the device the version names, else the one the list has now.
                listed.apps = asked.map { app in
                    let now = project.apps.first { $0.kind == app.kind }
                    return WishApp(kind: app.kind, needs: now?.needs, places: now?.places, integration: app.integration ?? now?.integration)
                }
                let apps = Parts.wanted(in: listed, parts: parts)
                if apps != project.apps { project.apps = apps; changed = true }
                // A Lamp from before reads the wish by its meta.json's layout, which follows whether its folder holds an app.
                if NewerWish.savedLayout(at: project.dir) != Template.layout(of: project) { changed = true }
            }
            // Before any app's own files are written: a part reads its wish's list from there (`talksToOtherApps`).
            if changed { try? Template.saveMeta(project) }
            try? Template.writeOwnedFiles(for: project)   // the build writes them again, and stops if it can't
            // Every other app of the wish too, as the restore left them: they carry the wish's name and what the wish's
            // list makes of their building blocks, and no app of it comes first. Left to their next build, they'd leave
            // the restore unsaved, and the next Undo would only discard that.
            if !project.isPart {
                for part in Parts.load(project) { try? Template.writeOwnedFiles(for: part) }
            }
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
    /// `renaming` is a name the restore gives back (`name(at:in:)`): a version is saved for it even when the files
    /// come back the same, as a rename's own version may have changed nothing else.
    static func restore(_ project: LampProject, to version: AppVersion, message: String, trailer: String? = nil,
                        renaming: (from: String, to: String)? = nil) async -> Bool {
        guard await restoreFiles(project, to: version, name: renaming?.to) else { return false }
        let trailers = [trailer, renaming.map { nameTrailers(from: $0.from, to: $0.to) }].compactMap { $0 }
        return await save(project, message: message, trailer: trailers.isEmpty ? nil : trailers.joined(separator: "\n"),
                          allowEmpty: renaming != nil)
    }

    /// Saves the app's files as they are now as a new version. False when nothing changed.
    static func save(_ project: LampProject, message: String, trailer: String? = nil, allowEmpty: Bool = false) async -> Bool {
        // In the environment rather than the command: a name may hold anything the shell reads in quotes.
        var env = ["LAMP_MESSAGE": message]
        if let trailer { env["LAMP_TRAILER"] = trailer }
        let arguments = "-q\(allowEmpty ? " --allow-empty" : "") -m \"$LAMP_MESSAGE\"" + (trailer == nil ? "" : " -m \"$LAMP_TRAILER\"")
        return await commitAll(arguments, in: project.dir, env: env) == .saved
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
        // The wish's list of apps goes with each new version (`appsTrailer`); a version amended keeps the one it has.
        var arguments = arguments, env = env
        if !arguments.contains("--amend"), let apps = appsTrailer(in: dir) {
            arguments += " --trailer \"$LAMP_APPS\""
            env["LAMP_APPS"] = apps
        }
        for attempt in 0...savePauses.count {
            if await git("git add -A && \(commit) \(arguments)", cwd: dir, env: env) == 0 { return .saved }
            var unsaved = ""
            let looked = await git("git status --porcelain", cwd: dir) { unsaved += $0 }
            if looked == 0, unsaved.trimmed.isEmpty {
                // Only the wish's list changed: that's a version too, so Undo takes the request that changed it back.
                guard env["LAMP_APPS"] != nil, await listDiffersFromLatest(in: dir),
                      await git("\(commit) --allow-empty \(arguments)", cwd: dir, env: env) == 0 else { return .nothingToSave }
                return .saved
            }
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
        guard let url = Previews.destination(for: version + ".jpg", under: ".lamp/versions", in: project) else { return }
        Previews.write(screenshot, in: project, to: url, maxPixels: 900, quality: 0.8)
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
        // It goes into the next request word for word, so never through a link the agent put in its place.
        AppFile.text(noteURL(project), in: project) ?? ""
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
        // A version with no files changed is a request that changed only the wish's list of apps (an app asked for that
        // this Mac can't make yet): the request says what it was, and a model shown no change could only say "nothing".
        // It's given as the title, so the versions before it still get theirs (titling stops at the first without one).
        guard !files.isEmpty else { return version.message }
        // Lamp refreshing the support code it puts in every app isn't a change the user made.
        if files.allSatisfy({ $0 == "Sources/LampSupport.swift" || $0 == Template.sceneSupportPath || $0 == Template.widgetFolder + "/" + Template.widgetSupportFile
                                              || $0 == Template.shareFolder + "/" + Template.shareSupportFile
                                              || Template.watchSupportPaths.contains($0) || Template.isAndroidSupport($0)
                                              || DeviceSupport.isSupport($0, in: project) }) { return "Lamp update" }
        var diff = ""
        let watchSupport = (Template.watchSupportPaths + DeviceSupport.paths(for: project)).map { " ':!\($0)'" }.joined()
        _ = await Versions.git("git show --format= --unified=1 \"$LAMP_VERSION\" -- . ':!Sources/LampSupport.swift' ':!\(Template.sceneSupportPath)' ':!\(Template.widgetFolder)/\(Template.widgetSupportFile)' ':!\(Template.shareFolder)/\(Template.shareSupportFile)'\(watchSupport) ':!\(Attachments.folder)'",
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
