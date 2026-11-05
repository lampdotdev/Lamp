import AppKit
import Foundation

/// Try It First: someone's suggested change, opened in a copy of the person's app that's never on the desk and never
/// theirs, so they can see it before bringing it in.
///
/// The copy is an app of its own. It has its own id, bundle id and data folder (`trial-…`, `dataID`), is built in a folder
/// of Lamp's of its own for each try (`Trials/<generation>`), and runs from there, never installed among the person's
/// apps. It starts with none of their data, none of Lamp's keys for the app (no token: it can't reach Lamp's AI or
/// gateway), no pairing and no shared network: the files are copied as a remix copies them, without what a remix carries
/// over. The shared-app review runs before anything of it builds, as it does for Bring In. The change goes in through the
/// same three-way merge Bring In uses (`Upstream.merge`), against the same base; if the two overlap, no agent settles it
/// in a copy, so the try stops and says Bring In does that.
///
/// Each try owns everything it makes: the build and the process building it, the running app, its bundle and its data,
/// written first into a list in its folder (`Manifest`), so whatever ends it (the app quitting, another try, Bring In,
/// Not for Me, a failure, Lamp quitting, or Lamp starting again after a crash) takes all of it away. A try is known by
/// its generation: one that's been ended can't come back by a build that finishes late.
///
/// What was tried is pinned in the record (`SuggestedChanges.Tried`): the request's head and the app's version it was
/// built on. Bring In says so when what it brings differs.
enum SuggestionTrial {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Where every try's folder is.
    nonisolated(unsafe) static var folder = Edition.supportFolder.appendingPathComponent("Trials")

    /// Whether this wish can be tried on this Mac: one Mac app, built with its plain build. Others don't offer it.
    static func canTry(_ project: LampProject) -> Bool {
        project.partFolders.isEmpty && project.apps.count <= 1 && project.openPlaces == [.mac] && project.platform != .universal
            && !GameKit.isGame(project) && !ScreenKit.hostsOnApple(project) && !GameKit.usesPlayer(project)
    }

    /// Said beside the button.
    static let note = "Opens a copy with none of your data. Your app stays as it is."

    /// What a try leaves behind, written before anything else, for whoever cleans up after it.
    struct Manifest: Codable, Equatable {
        var wish: String
        var number: Int
        var bundleID: String
        var dataID: String
    }

    /// One try, while it lasts.
    @MainActor final class Running {
        enum Stage: Equatable { case preparing, building, open, failed(String) }
        let wish: String
        let number: Int
        let generation: String
        let folder: URL
        var stage: Stage = .preparing
        var build: Process?
        var app: NSRunningApplication?
        var watching: NSObjectProtocol?

        init(wish: String, number: Int, generation: String, folder: URL) {
            self.wish = wish
            self.number = number
            self.generation = generation
            self.folder = folder
        }
    }

    /// The copy as Lamp knows it: the wish's kind and code under an identity of the try's own.
    static func copy(of project: LampProject, generation: String) -> LampProject {
        let id = "trial-" + generation.prefix(12)
        var copy = project.named(project.name + " (Trying)", id: id, exe: project.exe,
                                 dir: folder.appendingPathComponent(generation).appendingPathComponent("App"))
        copy.instance = generation
        return copy
    }

    static func manifest(for copy: LampProject, wish: String, number: Int) -> Manifest {
        Manifest(wish: wish, number: number, bundleID: copy.bundleID, dataID: Edition.appBundlePrefix + copy.id)
    }

    /// What the copy is told about itself: who it is, and nothing that reaches Lamp's gateway or the person's keys.
    static func installValues(for copy: LampProject) -> [String: String] {
        var values = Template.installValues(for: copy)
        for secret in ["token", "widgetToken", "widgetPort", "port", "macHost"] { values[secret] = "" }
        values["apps"] = copy.dir.deletingLastPathComponent().path
        return values
    }

    /// What's said when Bring In would bring something other than what was tried; nil when it's the same.
    static func differs(_ tried: SuggestedChanges.Tried, head: String, version: String?) -> String? {
        if tried.head != head { return "They've sent more changes since you tried it, so what comes in now has those too." }
        if let was = tried.version, let version, was != version { return "Your app changed since you tried it, so this may come out a little differently." }
        return nil
    }

    // MARK: Taking it all away

    /// Where macOS keeps what an app with this id saved: its data folder (`LampSupport`'s), its caches, settings, web
    /// storage and saved windows.
    static func leftovers(of manifest: Manifest, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        let library = home.appendingPathComponent("Library")
        var places: [URL] = []
        for id in Set([manifest.bundleID, manifest.dataID]) where id.hasPrefix(Edition.appBundlePrefix + "trial-") {
            places += [
                library.appendingPathComponent("Application Support/\(id)"),
                library.appendingPathComponent("Caches/\(id)"),
                library.appendingPathComponent("HTTPStorages/\(id)"),
                library.appendingPathComponent("WebKit/\(id)"),
                library.appendingPathComponent("Preferences/\(id).plist"),
                library.appendingPathComponent("Saved Application State/\(id).savedState"),
            ]
        }
        return places
    }

    /// Takes away one try's folder and everything its app saved, from what its folder's list says.
    static func remove(_ trial: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let fm = FileManager.default
        if let data = try? Data(contentsOf: trial.appendingPathComponent("trial.json")),
           let manifest = try? JSONDecoder().decode(Manifest.self, from: data) {
            for place in leftovers(of: manifest, home: home) where fm.fileExists(atPath: place.path) { try? fm.removeItem(at: place) }
            // Its preferences are cached by macOS too; asked to forget them so the file doesn't come back.
            CFPreferencesAppSynchronize(manifest.bundleID as CFString)
        }
        let run = trial.appendingPathComponent("Run")
        for app in (try? fm.contentsOfDirectory(at: run, includingPropertiesForKeys: nil)) ?? [] where app.pathExtension == "app" {
            _ = Subprocess.runBlocking("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                                       ["-u", app.path], timeout: 20)
        }
        try? fm.removeItem(at: trial)
    }

    /// Every try left from before, at launch: a crash or a quit that couldn't wait leaves them. No try runs yet.
    static func sweep(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        for trial in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] { remove(trial, home: home) }
    }

    // MARK: Making the copy

    /// The copy of the wish with the change merged in, ready to build, in the try's own folder; its list of what it
    /// leaves is written first. Throws with what to say when it can't be made, or when the change overlaps the person's.
    static func prepare(_ project: LampProject, generation: String, number: Int, package: Sharing.Package, pull: BringIn.Pull,
                        kept: GitHubRepo.Repo?) async throws -> LampProject {
        let copy = copy(of: project, generation: generation)
        let folder = copy.dir.deletingLastPathComponent()
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: copy.dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
            try JSONEncoder().encode(manifest(for: copy, wish: project.id, number: number)).write(to: folder.appendingPathComponent("trial.json"))
            // The code and its history, as a remix copies them, and none of what a remix carries over besides.
            for item in try fm.contentsOfDirectory(atPath: project.dir.path) where ![".lamp", "build", ".build"].contains(item) {
                try fm.copyItem(at: project.dir.appendingPathComponent(item), to: copy.dir.appendingPathComponent(item))
            }
            try Template.saveMeta(copy)
        } catch {
            throw Failure(message: "Lamp couldn't make a copy to try it in.")
        }
        // The copy's files saved as they are, as the merge expects them.
        _ = await Versions.git("git add -A -- . ':!.lamp' && \(Versions.commit) -q --allow-empty -m 'Before trying'", cwd: copy.dir, onLine: { _ in })
        let merged: Upstream.Merged
        do {
            let given = try await BringIn.given(for: pull, kept: kept, in: copy)
            merged = try await Upstream.merge(package, into: copy, from: nil, commit: nil, arrival: nil, ref: "refs/lamp/trial", given: given)
            try Template.writeOwnedFiles(for: copy)
        } catch {
            throw Failure(message: "Lamp couldn't put the change into a copy: \(error.localizedDescription)")
        }
        guard merged.conflicts.isEmpty, merged.newParts.isEmpty else {
            throw Failure(message: "It changes some of the same lines you did. Bring it in instead, and Lamp fits the two together.")
        }
        return copy
    }
}

extension SuggestedChanges {
    /// A request as it was tried: its head, and the version of the app the copy was made from.
    struct Tried: Codable, Equatable, Sendable {
        var head: String
        var version: String?
    }
}

extension Store {
    /// Try It First: the request fetched as Bring In fetches it, then the shared-app review, whose Try It makes the copy.
    func trySuggestion(_ project: LampProject, number: Int) {
        guard SuggestionTrial.canTry(project), let kept = GitHubRepo.kept(for: project), GitHubRepo.isUp(project),
              let request = SuggestedChanges.record(for: project)?.request(number) else { return }
        Task {
            guard let gh = await readyForTrial(project) else { return }
            endAllTrials()
            fetchingSuggestion[project.id] = number
            suggestionsRevision += 1
            defer { fetchingSuggestion[project.id] = nil; suggestionsRevision += 1 }
            do {
                let fetched = try await SuggestedChanges.fetch(project, kept: kept, request: request, gh: gh)
                importApp(from: fetched.tree, updating: project.id, bringingIn: fetched.pull, trying: true)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    private func readyForTrial(_ project: LampProject) async -> String? {
        guard let gh = await Publish.gh(), await Publish.login(gh: gh) != nil else {
            let alert = NSAlert()
            alert.messageText = "Sign in to GitHub with gh first"
            alert.informativeText = "Lamp reads what people sent with your own GitHub sign-in."
            alert.runModal()
            return nil
        }
        return gh
    }

    /// Try It, on the review: the copy is made, merged, built and opened, unless it's ended meanwhile.
    func confirmTrial() {
        guard let pending = pendingImport, pending.trying, let pull = pending.bringingIn, let number = pull.request,
              let project = pending.existing.flatMap({ existing in projects.first { $0.id == existing.id } }) else { return }
        pendingImport = nil
        Task {
            defer { try? FileManager.default.removeItem(at: pending.package.folder) }
            await startTrial(of: project, number: number, package: pending.package, pull: pull)
        }
    }

    private func startTrial(of project: LampProject, number: Int, package: Sharing.Package, pull: BringIn.Pull) async {
        endAllTrials()
        let generation = UUID().uuidString.lowercased()
        let folder = SuggestionTrial.folder.appendingPathComponent(generation)
        let running = SuggestionTrial.Running(wish: project.id, number: number, generation: generation, folder: folder)
        trials[project.id] = running
        func current() -> Bool { trials[project.id]?.generation == generation }
        // Whatever happened, what it made goes; only the try still current says so.
        func fail(_ message: String) {
            SuggestionTrial.remove(folder)
            guard current() else { return }
            running.stage = .failed(message)
            trials[project.id] = running
            suggestionsRevision += 1
        }
        let fm = FileManager.default
        let version = await Versions.head(project)
        let copy: LampProject
        do {
            copy = try await SuggestionTrial.prepare(project, generation: generation, number: number, package: package, pull: pull,
                                                     kept: GitHubRepo.kept(for: project))
        } catch {
            return fail(error.localizedDescription)
        }
        guard current() else { return SuggestionTrial.remove(folder) }
        running.stage = .building
        trials[project.id] = running
        suggestionsRevision += 1
        var output: [String] = []
        let status = await Self.buildSparing("./build.sh", for: copy, env: [:], started: { running.build = $0 }) { output = $0 }
        running.build = nil
        guard current() else { return SuggestionTrial.remove(folder) }
        guard status == 0, fm.fileExists(atPath: copy.builtURL.path) else {
            print("Trying #\(number) of \(project.name) didn't build:\n" + output.suffix(20).joined(separator: "\n"))
            return fail("It didn't build as it is. Bring it in instead, and Lamp works it out with you.")
        }
        // Run from a folder of Lamp's beside the copy, told who it is, and signed again.
        let run = folder.appendingPathComponent("Run").appendingPathComponent(copy.builtURL.lastPathComponent)
        do {
            try fm.createDirectory(at: run.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: copy.builtURL, to: run)
        } catch {
            return fail("Lamp couldn't open the copy.")
        }
        Self.setInstallValues(for: copy, in: run.appendingPathComponent("Contents/Info.plist"), root: run.deletingLastPathComponent(),
                              values: SuggestionTrial.installValues(for: copy))
        _ = await Shell.run("""
            xattr -cr "$LAMP_APP"
            for inner in "$LAMP_APP"/Contents/PlugIns/*.appex(N); do codesign --force -s - "$inner"; done
            codesign --force -s - "$LAMP_APP"
            """, cwd: folder, env: ["LAMP_APP": run.path], login: false) { _ in }
        guard current() else { return SuggestionTrial.remove(folder) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.addsToRecentItems = false
        guard let app = try? await NSWorkspace.shared.openApplication(at: run, configuration: configuration) else {
            return fail("The copy didn't open.")
        }
        guard current() else { app.forceTerminate(); return SuggestionTrial.remove(folder) }
        running.app = app
        running.stage = .open
        // Quitting the copy ends the try.
        running.watching = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                                                              object: nil, queue: .main) { note in
            guard (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier == app.processIdentifier else { return }
            Task { @MainActor in if Store.shared.trials[project.id]?.generation == generation { Store.shared.endTrial(of: project) } }
        }
        trials[project.id] = running
        SuggestedChanges.change(project) { $0.tried[String(number)] = SuggestedChanges.Tried(head: pull.head, version: version) }
        suggestionsRevision += 1
    }

    /// Ends the wish's try, whatever it's doing: its build stopped, its app quit, everything it made taken away.
    func endTrial(of project: LampProject) {
        guard let running = trials.removeValue(forKey: project.id) else { return }
        Self.finish(running)
        suggestionsRevision += 1
    }

    func endAllTrials() {
        let all = trials.values
        trials = [:]
        for running in all { Self.finish(running) }
        if !all.isEmpty { suggestionsRevision += 1 }
    }

    /// As Lamp quits, when nothing can wait: each try's app is made to go, and what it made taken away now.
    func endTrialsNow() {
        let all = trials.values
        trials = [:]
        for running in all {
            if let build = running.build { Subprocess.terminateTree(build) }
            if let app = running.app, !app.isTerminated {
                app.forceTerminate()
                for _ in 0..<10 where !app.isTerminated { Thread.sleep(forTimeInterval: 0.05) }
            }
            SuggestionTrial.remove(running.folder)
        }
    }

    private static func finish(_ running: SuggestionTrial.Running) {
        if let watching = running.watching { NSWorkspace.shared.notificationCenter.removeObserver(watching) }
        if let build = running.build { Subprocess.terminateTree(build) }
        let folder = running.folder
        guard let app = running.app, !app.isTerminated else { return SuggestionTrial.remove(folder) }
        app.terminate()
        // Given a moment to save and go; then made to, before its data is taken away.
        Task.detached {
            for _ in 0..<20 where !app.isTerminated { try? await Task.sleep(for: .milliseconds(100)) }
            if !app.isTerminated { app.forceTerminate() }
            for _ in 0..<20 where !app.isTerminated { try? await Task.sleep(for: .milliseconds(100)) }
            SuggestionTrial.remove(folder)
        }
    }
}
