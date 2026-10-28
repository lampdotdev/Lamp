import CryptoKit
import Foundation

/// Putting a change into a game's page while it's played, on the Mac and in the simulator, without the app reopening.
/// The app around the page (`LampPageLive` in LampPage.swift) asks Lamp what has changed, a request Lamp holds until
/// there's a change or a while has passed. When a build changes only the page (Web/: its code, pictures, models,
/// sounds), Lamp answers with the files that differ from what that copy of the app was installed with, which the app
/// fetches and serves in place of its own; the page (lamp-game.js) puts new pictures, models and sounds into the running
/// game, opens itself again for new code keeping the player's place (`snapshot()` and `restore()`), or, while the game
/// says a match is on (`busy()`), waits for a pause. The app tells Lamp which it did, and the chat says so: a change that
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
        /// In, as the page says it went (`swapped`, `reloading`…).
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
    private struct Given {
        var gen: Int
        var files: [String: String]
        var gone: [String]
        var changed: [String]
        var now = false
    }

    /// Lamp's launch: a copy that asked an earlier Lamp starts counting again.
    let epoch = UUID().uuidString
    private var installs: [Key: Installed] = [:]
    private var given: [Key: Given] = [:]
    private var heard: [Key: Date] = [:]
    private var listening: [Key: [(id: UUID, waiter: CheckedContinuation<Void, Never>)]] = [:]
    private var deciding: [Key: (gen: Int, answer: CheckedContinuation<String?, Never>)] = [:]
    private var held: Set<Key> = []

    /// Whether a project's open copy can take changes this way: a game drawn on Lamp's game runtime.
    static func takes(_ project: LampProject) -> Bool {
        GameKit.isGame(project) && GameKit.engine(project) == .web
    }

    /// The page as the build that's about to be installed has it.
    static func web(of project: LampProject, at place: Place) -> URL {
        place == .mac ? project.dir.appendingPathComponent("build/\(project.exe).app/Contents/Resources/Web")
            : project.dir.appendingPathComponent("build/iOS/\(project.exe).app/Web")
    }

    private static func folder(_ project: LampProject) -> URL { project.dir.appendingPathComponent(".lamp/page-live") }
    private static func record(_ project: LampProject, _ place: Place) -> URL { folder(project).appendingPathComponent("\(place.rawValue).json") }
    private static func copies(_ project: LampProject, _ place: Place) -> URL { folder(project).appendingPathComponent(place.rawValue) }

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
        let before = given[key].map { given in
            installed.files.filter { !given.gone.contains($0.key) }.merging(given.files) { $1 }
        } ?? installed.files
        let files = now.filter { installed.files[$0.key] != $0.value }
        let gone = installed.files.keys.filter { now[$0] == nil }.sorted()
        let changed = Set(now.keys).union(before.keys).filter { now[$0] != before[$0] }
            .filter { $0 != GamePage.deviceFile && $0 != GamePage.buildFile }.sorted()
        guard !changed.isEmpty else { return .unchanged }
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
        given[key] = Given(gen: gen, files: files, gone: gone, changed: changed)
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
            given[key] = change
            held.remove(key)
            wake(key)
            asked = true
        }
        return asked
    }

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

    // MARK: The app's requests

    /// The app asking what has changed (`/app/page/live`): answered at once when there's something newer than it has,
    /// else held until there is, or for 25 seconds.
    func poll(_ body: [String: Any], for project: LampProject) async -> (Int, [String: Any]) {
        guard let place = (body["place"] as? String).flatMap(Place.init(rawValue:)) else { return (404, ["error": "Not found"]) }
        let key = Key(id: project.id, place: place)
        heard[key] = Date()
        let after = (body["epoch"] as? String) == epoch ? body["after"] as? Int ?? 0 : 0
        func newer() -> Given? { given[key].flatMap { $0.gen > after ? $0 : nil } }
        if newer() == nil {
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
        guard let change = newer() else { return (200, ["epoch": epoch, "gen": given[key]?.gen ?? 0]) }
        return (200, ["epoch": epoch, "gen": change.gen, "files": change.files, "gone": change.gone, "changed": change.changed, "now": change.now])
    }

    /// One of the files of the change, by its path in Web/ (`/app/page/file`).
    func file(_ body: [String: Any], for project: LampProject) -> (Int, [String: Any]) {
        guard let path = body["path"] as? String else { return (404, ["error": "Not found"]) }
        for place in [Place.mac, .simulator] {
            guard let hash = given[Key(id: project.id, place: place)]?.files[path],
                  let data = AppFile.read(Self.copies(project, place).appendingPathComponent(hash), in: project) else { continue }
            return (200, ["data": data.base64EncodedString()])
        }
        return (404, ["error": "Not found"])
    }

    /// What the page did with a change (`/app/page/state`): the first word of a change answers `put`; a held change
    /// going in later (at a pause, or after Reload) lets go of the chat's Reload.
    func state(_ body: [String: Any], for project: LampProject) -> (Int, [String: Any]) {
        guard let place = (body["place"] as? String).flatMap(Place.init(rawValue:)), let state = body["state"] as? String else {
            return (200, [:])
        }
        let key = Key(id: project.id, place: place)
        let gen = body["gen"] as? Int ?? 0
        if state == "held" { held.insert(key) }
        if let waiting = deciding[key], gen >= waiting.gen, ["swapped", "reloading", "held"].contains(state) {
            deciding[key] = nil
            waiting.answer.resume(returning: state)
            return (200, [:])
        }
        if ["swapped", "reloading"].contains(state) {
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
