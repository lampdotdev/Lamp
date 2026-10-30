import CryptoKit
import Foundation

/// Putting a change into a page while it's open (a game while it's played, a screen, a web app), on the Mac and in the
/// simulator, without the app reopening.
/// The app around the page (`LampPageLive` in LampPage.swift) asks Lamp what has changed, a request Lamp holds until
/// there's a change or a while has passed. When a build changes only the page (Web/: its code, pictures, models,
/// sounds), Lamp answers with the files that differ from what that copy of the app was installed with, which the app
/// fetches and serves in place of its own; a page without the game runtime opens itself again; a game's (lamp-game.js) puts new pictures, models and sounds into the running
/// game, and new code where its modules take it (`hot(import.meta).accept()`), opens itself again for code that can't be
/// swapped in, keeping the player's place (`snapshot()` and `restore()`), or, while the game says a match is on
/// (`busy()`), waits for a pause. The app tells Lamp which it did, and the chat says so: a change that
/// waits shows the chat's Reload, which puts it in at once.
/// Anything else in the build (the app's Swift, its package, what it declares) reopens the app as before. So does a
/// copy Lamp didn't install or isn't hearing from.
@MainActor final class PageLive {
    static let shared = PageLive()

    /// Where a copy of the app is open. A phone's copy doesn't ask: a change reaches it when Lamp installs it again, and
    /// the page restores the snapshot it kept then, as on Android and the Xbox.
    enum Place: String { case mac, simulator }

    /// What it did with a change.
    enum Outcome: Equatable {
        /// Not a change this way can make: the app reopens as before.
        case cannot
        /// The open copy already has it.
        case unchanged
        /// In, as the page says it went: `swapped` into the running game, `rerun` (its code run again in place, the page,
        /// renderer and kept parts staying), or `reloading`, each with the player's place kept.
        case went(String)
        /// Waiting for a pause in the game, or the person's Reload.
        case held
    }

    private struct Key: Hashable { let id: String; let place: Place }

    /// What a copy was installed with: the page's files by their hashes, and the rest of the app's (`native`).
    private struct Installed: Codable {
        var files: [String: String]
        var native: String
    }

    /// The change the copy has been given: every file that differs from what it was installed with, by its hash, and
    /// those it no longer has.
    private struct Given: Codable {
        var gen: Int
        var files: [String: String]
        var gone: [String]
        var changed: [String]
        var now = false
        /// The page said it holds this change for a pause, and hasn't said it went in since: kept with it, so a Lamp
        /// started again while the game waits still shows Reload.
        var waits: Bool? = nil
    }

    /// Lamp's launch: a copy that asked an earlier Lamp starts counting again.
    let epoch = UUID().uuidString
    private var installs: [Key: Installed] = [:]
    private var given: [Key: Given] = [:]
    private var heard: [Key: Date] = [:]
    private var listening: [Key: [(id: UUID, waiter: CheckedContinuation<Void, Never>)]] = [:]
    private var deciding: [Key: (gen: Int, answer: CheckedContinuation<String?, Never>)] = [:]
    private var held: Set<Key> = []
    /// Why the page last said it had to open again, or hold a change for a pause (code that couldn't be swapped in), by
    /// app: for the agent's look, so its next change can be one that swaps.
    private var reasons: [String: String] = [:]
    /// Asked of the copy on the Mac: what its page has saved, for a preview to start from (`saved(of:)`).
    private var asking: [String: CheckedContinuation<[String: String]?, Never>] = [:]
    /// What each app's copy on the Mac last said it had saved, by app, kept only while Lamp runs.
    private var lastSaved: [String: [String: String]] = [:]

    /// Whether a project's open copy can take changes this way: a page in an app of Lamp's own (a game drawn on Lamp's
    /// game runtime, a screen, a web app). A page without the game runtime is opened again with what it saved, keeping
    /// its window where the person has it.
    nonisolated static func takes(_ project: LampProject) -> Bool {
        GameKit.hostsPage(project)
    }

    /// The page as the build that's about to be installed has it.
    static func web(of project: LampProject, at place: Place) -> URL {
        place == .mac ? project.dir.appendingPathComponent("build/\(project.exe).app/Contents/Resources/Web")
            : project.dir.appendingPathComponent("build/iOS/\(project.exe).app/Web")
    }

    private static func folder(_ project: LampProject) -> URL { project.dir.appendingPathComponent(".lamp/page-live") }
    private static func record(_ project: LampProject, _ place: Place) -> URL { folder(project).appendingPathComponent("\(place.rawValue).json") }
    private static func copies(_ project: LampProject, _ place: Place) -> URL { folder(project).appendingPathComponent(place.rawValue) }
    private static func givenRecord(_ project: LampProject, _ place: Place) -> URL { folder(project).appendingPathComponent("\(place.rawValue)-given.json") }

    /// What the copy at `key` was last given, kept on disk beside its install: an app left open across Lamp's restart
    /// still serves it, so the next change is measured against it, not against the install.
    private func lastGiven(_ project: LampProject, _ key: Key) -> Given? {
        if let known = given[key] { return known }
        guard let data = AppFile.read(Self.givenRecord(project, key.place), in: project),
              var kept = try? JSONDecoder().decode(Given.self, from: data) else { return nil }
        kept.now = false
        given[key] = kept
        if kept.waits == true { held.insert(key) }
        return kept
    }

    private func give(_ change: Given, to key: Key, in project: LampProject) {
        given[key] = change
        if let data = try? JSONEncoder().encode(change) { try? AppFolder.write(data, to: Self.givenRecord(project, key.place), in: project.dir) }
    }

    // MARK: Installs

    /// A copy was installed at `place` from the build: what it has is what the changes are measured against. Kept on
    /// disk, so a copy left open across Lamp's own restart still takes changes.
    func installed(_ project: LampProject, at place: Place) {
        guard Self.takes(project) else { return }
        let key = Key(id: project.id, place: place)
        let record = Installed(files: Self.hashes(of: Self.web(of: project, at: place), in: project), native: Self.native(project))
        installs[key] = record
        given[key] = nil
        held.remove(key)
        AppFolder.remove(Self.givenRecord(project, place), in: project.dir)
        if let data = try? JSONEncoder().encode(record) { try? AppFolder.write(data, to: Self.record(project, place), in: project.dir) }
        AppFolder.remove(Self.copies(project, place), in: project.dir)
    }

    private func install(_ project: LampProject, _ key: Key) -> Installed? {
        if let known = installs[key] { return known }
        guard let data = AppFile.read(Self.record(project, key.place), in: project),
              let record = try? JSONDecoder().decode(Installed.self, from: data) else { return nil }
        installs[key] = record
        return record
    }

    /// Whether a copy at `place` has asked lately (it asks again within half a minute of each answer).
    func isOpen(_ project: LampProject, at place: Place) -> Bool {
        let key = Key(id: project.id, place: place)
        return listening[key]?.isEmpty == false || heard[key].map { Date().timeIntervalSince($0) < 40 } == true
    }

    // MARK: A change

    /// Puts the build's page into the copy open at `place`, when nothing but the page changed since that copy was
    /// installed, and waits (a few seconds at most) for the page to say what it did.
    func put(_ project: LampProject, at place: Place) async -> Outcome {
        let key = Key(id: project.id, place: place)
        guard Self.takes(project), isOpen(project, at: place), let installed = install(project, key),
              installed.native == Self.native(project) else { return .cannot }
        let now = Self.hashes(of: Self.web(of: project, at: place), in: project)
        guard !now.isEmpty else { return .cannot }
        // Measured against the install, so the copy gets the whole difference however many changes it missed; what
        // this change changed is measured against what it has now.
        let before = lastGiven(project, key).map { given in
            installed.files.filter { !given.gone.contains($0.key) }.merging(given.files) { $1 }
        } ?? installed.files
        let files = now.filter { installed.files[$0.key] != $0.value }
        let gone = installed.files.keys.filter { now[$0] == nil }.sorted()
        let changed = Set(now.keys).union(before.keys).filter { now[$0] != before[$0] }
            .filter { $0 != GamePage.deviceFile && $0 != GamePage.buildFile }.sorted()
        // The copy already has this build: still waiting for a pause when it said so, and otherwise in.
        guard !changed.isEmpty else { return held.contains(key) ? .held : .unchanged }
        // The files handed over are copied out of the build, which the next change rewrites while the app may still be
        // fetching them.
        let web = Self.web(of: project, at: place), copies = Self.copies(project, place)
        do {
            for (path, hash) in files where AppFile.read(copies.appendingPathComponent(hash), in: project) == nil {
                try AppFolder.copy(web.appendingPathComponent(path), to: copies.appendingPathComponent(hash), in: project.dir)
            }
        } catch {
            return .cannot
        }
        for name in (try? FileManager.default.contentsOfDirectory(atPath: copies.path)) ?? [] where !files.values.contains(name) {
            AppFolder.remove(copies.appendingPathComponent(name), in: project.dir)
        }
        let gen = (given[key]?.gen ?? 0) + 1
        give(Given(gen: gen, files: files, gone: gone, changed: changed), to: key, in: project)
        held.remove(key)
        let said = await answer(key, gen: gen)
        switch said {
        case nil: return .cannot
        case "held": return .held
        case let state?: return .went(state)
        }
    }

    /// The person pressed Reload for a change the page is holding: it goes in now. False when none is held.
    func putInNow(_ project: LampProject) -> Bool {
        var asked = false
        for place in [Place.mac, .simulator] {
            let key = Key(id: project.id, place: place)
            guard held.contains(key), var change = given[key] else { continue }
            change.gen += 1
            change.now = true
            give(change, to: key, in: project)
            held.remove(key)
            wake(key)
            asked = true
        }
        return asked
    }

    /// Why the page last opened again or held a change, in its words (lamp-game.js); nil after a swap.
    func reason(_ project: LampProject) -> String? { reasons[project.id] }

    /// Whether a copy is holding a change for a pause.
    func holds(_ project: LampProject) -> Bool { held.contains { $0.id == project.id } }

    private func answer(_ key: Key, gen: Int) async -> String? {
        deciding[key]?.answer.resume(returning: nil)
        let said = await withCheckedContinuation { (answer: CheckedContinuation<String?, Never>) in
            deciding[key] = (gen, answer)
            wake(key)
            // The app fetches the files before it tells the page: a big picture over the network takes a moment.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(20))
                if let waiting = self.deciding[key], waiting.gen == gen { self.deciding[key] = nil; waiting.answer.resume(returning: nil) }
            }
        }
        return said
    }

    private func wake(_ key: Key) {
        for waiting in listening.removeValue(forKey: key) ?? [] { waiting.waiter.resume() }
    }

    // MARK: What the page saved

    /// What the page open in the app's copy on this Mac has saved (its localStorage, where LampStore keeps it): asked of
    /// the copy when it's open, else what it said last while Lamp has run; nil when there's neither. Read for a preview
    /// to start from, one way: nothing goes back.
    func saved(of project: LampProject) async -> [String: String]? {
        guard Self.takes(project) else { return nil }
        guard isOpen(project, at: .mac) else { return lastSaved[project.id] }
        asking[project.id]?.resume(returning: nil)
        let key = Key(id: project.id, place: .mac)
        let fresh = await withCheckedContinuation { (answer: CheckedContinuation<[String: String]?, Never>) in
            asking[project.id] = answer
            wake(key)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                self.asking.removeValue(forKey: project.id)?.resume(returning: nil)
            }
        }
        if let fresh { lastSaved[project.id] = fresh }
        return fresh ?? lastSaved[project.id]
    }

    /// The copy's answer (`/app/page/saved`).
    func savedArrived(_ body: [String: Any], for project: LampProject) -> (Int, [String: Any]) {
        guard let data = body["data"] as? [String: String] else { return (400, ["error": "No data."]) }
        lastSaved[project.id] = data
        asking.removeValue(forKey: project.id)?.resume(returning: data)
        return (200, [:])
    }

    /// Forgets what an app's copy said it saved: the app is gone.
    func forgetSaved(_ id: String) { lastSaved[id] = nil }

    // MARK: The app's requests

    /// The app asking what has changed (`/app/page/live`): answered at once when there's something newer than it has,
    /// else held until there is, or for 25 seconds.
    func poll(_ body: [String: Any], for project: LampProject) async -> (Int, [String: Any]) {
        guard let place = (body["place"] as? String).flatMap(Place.init(rawValue:)) else { return (404, ["error": "Not found"]) }
        let key = Key(id: project.id, place: place)
        heard[key] = Date()
        let after = (body["epoch"] as? String) == epoch ? body["after"] as? Int ?? 0 : 0
        func newer() -> Given? { lastGiven(project, key).flatMap { $0.gen > after ? $0 : nil } }
        func wanted() -> Bool { place == .mac && asking[project.id] != nil }
        if newer() == nil, !wanted() {
            let id = UUID()
            await withCheckedContinuation { (waiter: CheckedContinuation<Void, Never>) in
                listening[key, default: []].append((id, waiter))
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(25))
                    guard let index = self.listening[key]?.firstIndex(where: { $0.id == id }) else { return }
                    self.listening[key]?.remove(at: index)
                    waiter.resume()
                }
            }
        }
        heard[key] = Date()
        // What its page saved is asked for before anything else: a preview waits on it.
        if wanted() { return (200, ["epoch": epoch, "gen": after, "send": "saved"]) }
        guard let change = newer() else { return (200, ["epoch": epoch, "gen": given[key]?.gen ?? 0]) }
        return (200, ["epoch": epoch, "gen": change.gen, "files": change.files, "gone": change.gone, "changed": change.changed, "now": change.now])
    }

    /// One of the files of the change (`/app/page/file`): the copy kept for `place` under the hash the change named,
    /// which the app checks against what it gets.
    func file(_ body: [String: Any], for project: LampProject) -> (Int, [String: Any]) {
        guard let place = (body["place"] as? String).flatMap(Place.init(rawValue:)), let hash = body["hash"] as? String,
              hash.count == 32, hash.allSatisfy(\.isHexDigit),
              lastGiven(project, Key(id: project.id, place: place))?.files.values.contains(hash) == true,
              let data = AppFile.read(Self.copies(project, place).appendingPathComponent(hash), in: project) else {
            return (404, ["error": "Not found"])
        }
        return (200, ["data": data.base64EncodedString()])
    }

    /// What the page did with a change (`/app/page/state`): the first word of a change answers `put`; a held change
    /// going in later (at a pause, or after Reload) lets go of the chat's Reload.
    func state(_ body: [String: Any], for project: LampProject) -> (Int, [String: Any]) {
        guard let place = (body["place"] as? String).flatMap(Place.init(rawValue:)), let state = body["state"] as? String else {
            return (200, [:])
        }
        let key = Key(id: project.id, place: place)
        let gen = body["gen"] as? Int ?? 0
        // The change is on screen: the light Lamp holds over the window while it's put in crosses it now.
        if state == "shown" {
            Store.shared.pageShown(project)
            return (200, [:])
        }
        if ["held", "reloading", "rerun", "swapped"].contains(state) { reasons[project.id] = (body["why"] as? String).map { String($0.prefix(300)) } }
        if state == "held" { held.insert(key) }
        if let change = lastGiven(project, key), ["held", "swapped", "rerun", "reloading"].contains(state) {
            var marked = change
            marked.waits = state == "held"
            if marked.waits != (change.waits ?? false) { give(marked, to: key, in: project) }
        }
        if let waiting = deciding[key], gen >= waiting.gen, ["swapped", "rerun", "reloading", "held"].contains(state) {
            deciding[key] = nil
            waiting.answer.resume(returning: state)
            return (200, [:])
        }
        if ["swapped", "rerun", "reloading"].contains(state) {
            held.remove(key)
            Store.shared.pageWentIn(project)
        }
        return (200, [:])
    }

    // MARK: What a copy is made of

    /// The page's files by their path in it, each by the hash of its contents.
    private static func hashes(of web: URL, in project: LampProject) -> [String: String] {
        let base = web.standardizedFileURL.path + "/"
        var found: [String: String] = [:]
        for case let url as URL in FileManager.default.enumerator(at: web, includingPropertiesForKeys: nil) ?? FileManager.DirectoryEnumerator() {
            guard let data = AppFile.read(url, in: project) else { continue }
            let path = String(url.standardizedFileURL.path.dropFirst(base.count))
            found[path] = SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined()
        }
        return found
    }

    /// Everything else the app is built from (its Swift, its package, what it declares): a change to any of it reopens
    /// the app.
    private static func native(_ project: LampProject) -> String {
        var hasher = SHA256()
        let sources = project.dir.appendingPathComponent("Sources")
        let names = ((try? FileManager.default.subpathsOfDirectory(atPath: sources.path)) ?? []).sorted()
        for name in names {
            guard let data = AppFile.read(sources.appendingPathComponent(name), in: project) else { continue }
            hasher.update(data: Data(name.utf8))
            hasher.update(data: data)
        }
        for name in ["Package.swift", Template.Capabilities.file] {
            hasher.update(data: Data(name.utf8))
            hasher.update(data: AppFile.read(project.dir.appendingPathComponent(name), in: project) ?? Data())
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
