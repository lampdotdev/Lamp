import CryptoKit
import Foundation
import LampRelayKit

/// A page's change put into each copy of it open on another device (a screen on the kitchen iPad, a TV, the Xbox, an
/// Android photo frame) as soon as it's made, with no build and no wait. Every copy of a page that uses the wish (its
/// values, `LampStore.shared`, `Lamp.wish`) is already in the wish's room, so the files go to it there, as Lamp's own
/// word (`Relay.say`, from the relay's name, which no app has), in pieces under the room's size for a message; the page
/// takes them in place, keeping what it saved (lamp.js, "A change while it's open"). The copies on this Mac and in the
/// simulator take a change from Lamp itself (`PageLive`), so they're left out here, and so is Lamp's own preview.
///
/// Lamp asks each copy first what it has: lamp.js answers with the app around the page as its build had it (`native`,
/// written into lamp.js as it's built, `TVTemplate.withShell`). A copy that doesn't answer has an earlier Lamp's lamp.js,
/// and one in an app of Lamp's (an iPhone or iPad, Android) whose app around the page changed needs it put there again:
/// each waits for Reload, which puts the app on every place. Every other copy is given the whole page as it is, and the
/// change counts as reaching it only once the page says it took it (or why it couldn't, which waits for Reload too).
enum PageCopies {
    /// The page's files by their path in Web/, each by the hash of its contents: Lamp's own files left out, since they
    /// differ from place to place and the page never takes them in place.
    struct Files: Codable, Equatable {
        var files: [String: String]
        /// Everything else the app is built from (`native`): a change of it is a new app around the page, put there by
        /// Reload or Play.
        var native: String?
    }

    /// The most bytes of page one change carries: what the page can keep (sessionStorage) as it opens again.
    static let most = 3_000_000
    /// The text of one piece, well under the room's 16 KB for a message with its envelope.
    static let piece = 9_000

    private static func folder(_ project: LampProject) -> URL { project.dir.appendingPathComponent(".lamp/page-live/built") }

    /// A build of the page for a place, made from these sources: what that place has once it's installed there.
    static func record(_ project: LampProject, as fingerprint: String) {
        guard project.platform.target.changesAreWeb(project), fingerprint.allSatisfy({ $0.isHexDigit }),
              let data = try? JSONEncoder().encode(Files(files: hashes(of: project), native: native(of: project))) else { return }
        let dir = folder(project)
        try? AppFolder.write(data, to: dir.appendingPathComponent(fingerprint + ".json"), in: project.dir)
        // A few builds are kept: a place's record may be one a later build replaced and an install that didn't reach it
        // put back (`Store.update`).
        let kept = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .sorted { modified($0) > modified($1) }
        for old in kept.dropFirst(24) { AppFolder.remove(old, in: project.dir) }
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    /// What the copy at `place` was built with, when that build recorded it.
    static func built(_ project: LampProject, at place: Destination) -> Files? {
        Runtime.builtFingerprint(project.at(place)).flatMap { record(project, $0) }
    }

    private static func record(_ project: LampProject, _ fingerprint: String) -> Files? {
        AppFile.read(folder(project).appendingPathComponent(fingerprint + ".json"), in: project)
            .flatMap { try? JSONDecoder().decode(Files.self, from: $0) }
    }

    /// Every build a copy at `place` may have, newest first: the place's latest, and each one Lamp put on a device of the
    /// person's there (`Runtime.placed`), since a copy on one TV or iPad can be older than the place's last build. Nil for
    /// a build that recorded nothing (an earlier Lamp's).
    static func builds(_ project: LampProject, at place: Destination) -> [Files?] {
        var dated: [(String, Date)] = []
        let latest = project.at(place)
        if let fingerprint = Runtime.builtFingerprint(latest) { dated.append((fingerprint, Runtime.builtDate(latest) ?? .distantPast)) }
        for placed in Runtime.placed(project) where placed.place == place { dated.append((placed.fingerprint, placed.at)) }
        var seen: Set<String> = []
        return dated.sorted { $0.1 > $1.1 }.filter { seen.insert($0.0).inserted }.map { record(project, $0.0) }
    }

    /// The page's files as they are in the app's folder.
    static func hashes(of project: LampProject) -> [String: String] {
        let web = project.dir.appendingPathComponent(TVTemplate.webFolder)
        let owned = Set(DeviceSupport.paths(for: project))
        let base = web.standardizedFileURL.path + "/"
        var found: [String: String] = [:]
        for case let url as URL in FileManager.default.enumerator(at: web, includingPropertiesForKeys: nil) ?? FileManager.DirectoryEnumerator() {
            let path = String(url.standardizedFileURL.path.dropFirst(base.count))
            guard !path.hasPrefix("."), !path.contains("/."), !owned.contains(TVTemplate.webFolder + "/" + path),
                  let data = AppFile.read(url, in: project) else { continue }
            found[path] = name(of: data)
        }
        return found
    }

    /// Everything the app is built from but its page and Lamp's own files: its Swift, what it declares, its Android app.
    /// Lamp's own files change only with Lamp, whose update rebuilds the app, and some are written after lamp.js, which
    /// carries this.
    static func native(of project: LampProject) -> String {
        var hasher = SHA256()
        let owned = Set(DeviceSupport.paths(for: project))
        for folder in ["Sources", GameAndroid.folder] {
            let dir = project.dir.appendingPathComponent(folder)
            // What a build leaves there (Gradle's and Kotlin's caches, build/) isn't what the app is made from, and is big.
            for name in ((try? FileManager.default.subpathsOfDirectory(atPath: dir.path)) ?? []).sorted()
            where !name.split(separator: "/").contains(where: { $0 == "build" || $0.hasPrefix(".") }) && !owned.contains(folder + "/" + name) {
                guard let data = AppFile.read(dir.appendingPathComponent(name), in: project) else { continue }
                hasher.update(data: Data((folder + "/" + name).utf8))
                hasher.update(data: data)
            }
        }
        for name in [Template.Capabilities.file] {
            hasher.update(data: Data(name.utf8))
            hasher.update(data: AppFile.read(project.dir.appendingPathComponent(name), in: project) ?? Data())
        }
        return name(of: Data(hasher.finalize()))
    }

    /// Whether what's changed since the copies at `place` were built is their page alone, which each open copy takes as
    /// it is.
    static func pageOnly(_ project: LampProject, at place: Destination) -> Bool {
        guard let newest = builds(project, at: place).first else { return false }
        return !hasShell(place) || newest?.native == native(of: project)
    }

    /// Whether a page's copy at `place` runs in an app of Lamp's built from the rest of the folder (this Mac, an iPhone or
    /// iPad, Android), whose change needs the app put there again. A TV's browser and the Xbox's host have none of it.
    static func hasShell(_ place: Destination) -> Bool { place != .tv && place != .device }

    static func name(of data: Data) -> String { SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined() }

    /// A change for one copy: the whole page as it is now, which the copy serves in place of its own whatever build it
    /// has, and what changed since it was last given one (or since any build it may have).
    struct Change {
        /// The files the copy serves in place of its own, each as text or bytes.
        var files: [String: Data]
        var gone: [String]
        /// What differs from what the copy has: the page swaps a stylesheet in place when that's all.
        var changed: [String]
        /// Why the page can't take it in place, when it can't: it waits for Reload, which puts it on every place.
        var cannot: String?
    }

    /// The change for a copy that said what it has (`shell`, nil when it said nothing: an earlier Lamp's lamp.js); nil when
    /// it has the page as it is.
    static func change(for project: LampProject, at place: Destination, shell: String?, given: [String: String]?) -> Change? {
        let now = hashes(of: project)
        let changed = given.map { given in Set(now.keys).union(given.keys).filter { now[$0] != given[$0] } } ?? Set(now.keys)
        let around = hasShell(place) && shell != nil && shell != native(of: project)
        guard !changed.isEmpty || shell == nil || around else { return nil }
        let web = project.dir.appendingPathComponent(TVTemplate.webFolder)
        var files: [String: Data] = [:]
        for path in now.keys {
            guard let data = AppFile.read(web.appendingPathComponent(path), in: project) else { continue }
            files[path] = data
        }
        var change = Change(files: files, gone: [], changed: changed.sorted())
        change.cannot = shell == nil ? "it was put there by an earlier Lamp"
            : around ? "the app around the page changed" : cannot(project, change)
        return change
    }

    /// What keeps a page from taking a change in place, as lamp.js would find it: the page opens again from the files it's
    /// given, with lamp.js running first, so a script that runs before lamp.js, a module script (whose imports a file put
    /// in place can't follow), or more than the page can keep across opening again needs the app put there again.
    static func cannot(_ project: LampProject, _ change: Change) -> String? {
        if change.files.values.reduce(0, { $0 + $1.count }) > most { return "its page is too big to send" }
        let web = project.dir.appendingPathComponent(TVTemplate.webFolder)
        let index = change.files["index.html"].map { String(decoding: $0, as: UTF8.self) }
            ?? AppFile.text(web.appendingPathComponent("index.html"), in: project) ?? ""
        let tags = try? NSRegularExpression(pattern: "<script\\b[^>]*>", options: .caseInsensitive)
        let scripts = (tags?.matches(in: index, range: NSRange(index.startIndex..., in: index)) ?? [])
            .compactMap { Range($0.range, in: index).map { String(index[$0]) } }
        guard let first = scripts.firstIndex(where: { $0.contains("lamp.js") }) else { return "its page doesn't load lamp.js" }
        if first > 0 { return "a script runs before lamp.js" }
        if scripts.contains(where: { $0.range(of: "type=[\"']?module", options: [.regularExpression, .caseInsensitive]) != nil }) {
            return "it has a module script"
        }
        return nil
    }

    /// The change as Lamp's words to a copy: its files as JSON, in pieces the page puts together again.
    static func words(_ change: Change, id: String) -> [[String: Any]] {
        var files: [String: Any] = [:]
        for (path, data) in change.files {
            let ext = (path as NSString).pathExtension.lowercased()
            if ["html", "htm", "css", "js", "json", "svg", "txt", "md"].contains(ext), let text = String(data: data, encoding: .utf8) {
                files[path] = ["t": text]
            } else {
                files[path] = ["b": data.base64EncodedString()]
            }
        }
        let whole: [String: Any] = ["v": 1, "files": files, "gone": change.gone, "changed": change.changed]
        guard let json = try? JSONSerialization.data(withJSONObject: whole) else { return [] }
        let text = json.base64EncodedString()
        let count = max(1, (text.count + piece - 1) / piece)
        return (0..<count).map { i in
            let start = text.index(text.startIndex, offsetBy: i * piece)
            let end = text.index(start, offsetBy: min(piece, text.distance(from: start, to: text.endIndex)))
            return ["lampPage": ["id": id, "i": i, "n": count, "s": String(text[start..<end])]]
        }
    }

    /// Where a copy in the room is, by the device it said it is (`LampWish.device` in each library): nil for the copies
    /// Lamp reaches itself (this Mac's, the simulator's) and its own preview.
    static func place(of device: String) -> Destination? {
        switch device {
        case "Mac", "iPhone simulator", "TV preview": nil
        case "TV": .tv
        case "Xbox": .device
        case "Android device", "Android emulator": .android
        default: device.hasPrefix("iP") ? .ios : nil
        }
    }

    /// What each copy was last given, by app and copy: the next change says only what differs from it.
    @MainActor private static var given: [String: [String: String]] = [:]
    /// What copies have said to Lamp, by room and copy, waited for by `ask`: what they have, and what they did with a change.
    @MainActor private static var waiters: [String: CheckedContinuation<[String: Any]?, Never>] = [:]

    /// What a copy said to Lamp through its room (`Relay.onHeard`): handed to whoever waits for it.
    @MainActor static func heard(_ copy: String, in room: String, _ data: Any) {
        guard let said = (data as? [String: Any])?["lampPage"] as? [String: Any], let state = said["state"] as? String else { return }
        let id = said["id"] as? String ?? ""
        waiters.removeValue(forKey: room + "\t" + copy + "\t" + (state == "here" ? "" : id))?.resume(returning: said)
    }

    /// Waits for a copy to say something to Lamp (`id` "" for what it has), a few seconds at most.
    @MainActor private static func answer(from copy: String, in room: String, id: String, seconds: Int) async -> [String: Any]? {
        let key = room + "\t" + copy + "\t" + id
        waiters.removeValue(forKey: key)?.resume(returning: nil)
        return await withCheckedContinuation { answer in
            waiters[key] = answer
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                waiters.removeValue(forKey: key)?.resume(returning: nil)
            }
        }
    }

    /// Where a change went, by place: the places whose copy said it took it, those whose copy can't take it as it's open
    /// (with why), which wait for Reload, and those whose copy didn't answer.
    struct Outcome {
        var took: Set<Destination> = []
        var waiting: [Destination: String] = [:]
        var silent: Set<Destination> = []
        /// The page changed while it was being put into its copies: they're given it again (`Store.updatePlaces`).
        var stale = false
    }

    /// Puts the page as it is now into every copy of `project` open in its wish's room on a device Lamp doesn't reach
    /// itself: each is asked what it has, given the change when it can take it, and counted once it says it did.
    @MainActor static func put(_ project: LampProject, wish: LampProject) async -> Outcome {
        guard project.platform.target.changesAreWeb(project) else { return Outcome() }
        let room = WishRooms.key(for: wish), app = WishRooms.peer(project, in: wish)
        var outcome = Outcome()
        // The pages as they were sent, by copy: what each that takes it then has, though the folder may change meanwhile.
        var sentPages: [[String: String]] = []
        for member in WishRooms.presence(of: wish) {
            guard let copy = member["peer"] as? String, WishChannel.app(of: copy) == app,
                  var place = (member["device"] as? String).flatMap(place(of:)) else { continue }
            // Android's phone and TV places are one app: the copy is on whichever was built.
            if place == .android, built(project, at: .android) == nil, built(project, at: .androidTV) != nil { place = .androidTV }
            // A copy already on an Xbox gets no new files from an app kept off it.
            if place == .device, SharedNetwork.keptOffXbox(project) { outcome.waiting[place] = SharedNetwork.xboxRefusal; continue }
            let key = project.id + "\t" + copy
            // What it has: an earlier Lamp's lamp.js says nothing.
            let asking = Task { await Self.answer(from: copy, in: room, id: "", seconds: 6) }
            guard await ControllerRelay.say(in: room, to: [copy], data: ["lampPage": ["ask": true]]) == [copy] else { asking.cancel(); continue }
            let here = await asking.value
            guard let change = change(for: project, at: place, shell: here?["shell"] as? String, given: given[key]) else { continue }
            if let why = change.cannot { outcome.waiting[place] = why; continue }
            let id = UUID().uuidString.lowercased()
            let sent = change.files.mapValues { name(of: $0) }
            sentPages.append(sent)
            // Its answer comes once the page has opened again from the change, which can take a TV a while.
            let answer = Task { await Self.answer(from: copy, in: room, id: id, seconds: 45) }
            var went = true
            for word in words(change, id: id) where went {
                went = await ControllerRelay.say(in: room, to: [copy], data: word) == [copy]
            }
            let said = went ? await answer.value : nil
            if !went { answer.cancel() }
            switch said?["state"] as? String {
            case "took":
                given[key] = sent
                outcome.took.insert(place)
            case "failed":
                given[key] = nil
                outcome.waiting[place] = (said?["why"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "the page couldn't take it"
            default:
                outcome.silent.insert(place)
            }
        }
        let now = hashes(of: project)
        outcome.stale = sentPages.contains { $0 != now }
        return outcome
    }

    /// The copies were given the app again (Reload, Play): what each has is its build's.
    @MainActor static func installed(_ project: LampProject) {
        given = given.filter { !$0.key.hasPrefix(project.id + "\t") }
    }
}
