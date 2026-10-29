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
/// What each copy has is what Lamp last built for its place: each build of a page records its files by their hashes
/// (`record`, from `Runtime.markBuilt`), and a change is every file that differs from that, so a copy that missed one
/// gets it with the next. A place built before that record has a lamp.js that knows nothing of these words: it gets the
/// change when Reload or Play puts the app there, as before.
enum PageCopies {
    /// The page's files by their path in Web/, each by the hash of its contents: Lamp's own files left out, since they
    /// differ from place to place and the page never takes them in place.
    struct Files: Codable, Equatable {
        var files: [String: String]
    }

    /// The most bytes of files one change carries: what's left the page to keep it with (sessionStorage) as it opens again.
    static let most = 3_000_000
    /// The text of one piece, well under the room's 16 KB for a message with its envelope.
    static let piece = 9_000

    private static func folder(_ project: LampProject) -> URL { project.dir.appendingPathComponent(".lamp/page-live/built") }

    /// A build of the page for a place, made from these sources: what that place has once it's installed there.
    static func record(_ project: LampProject, as fingerprint: String) {
        guard project.platform.target.changesAreWeb(project), fingerprint.allSatisfy({ $0.isHexDigit }),
              let data = try? JSONEncoder().encode(Files(files: hashes(of: project))) else { return }
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
        guard let fingerprint = Runtime.builtFingerprint(project.at(place)),
              let data = AppFile.read(folder(project).appendingPathComponent(fingerprint + ".json"), in: project) else { return nil }
        return try? JSONDecoder().decode(Files.self, from: data)
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

    static func name(of data: Data) -> String { SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined() }

    /// A change for one place: what differs from its build, as the page takes it.
    struct Change {
        /// The files the copy serves in place of its own, each as text or bytes.
        var files: [String: Data]
        var gone: [String]
        /// What differs from what the copy was last given: the page swaps a stylesheet in place when that's all.
        var changed: [String]
        /// Why the page can't take it in place, when it can't: it waits for Reload, which puts it on every place.
        var cannot: String?
    }

    /// The change for the copy at `place`, measured against its build; nil when it has the page as it is, or its build
    /// recorded nothing (an earlier Lamp's lamp.js, which doesn't take these words).
    static func change(for project: LampProject, at place: Destination, given: [String: String]?) -> Change? {
        guard let built = built(project, at: place) else { return nil }
        let now = hashes(of: project)
        let had = given ?? built.files
        let changed = Set(now.keys).union(had.keys).filter { now[$0] != had[$0] }.sorted()
        guard !changed.isEmpty else { return nil }
        let web = project.dir.appendingPathComponent(TVTemplate.webFolder)
        var files: [String: Data] = [:]
        // index.html always goes, so the page opens again from it without reading its own (which a TV's may not let it).
        for (path, hash) in now where built.files[path] != hash || path == "index.html" {
            guard let data = AppFile.read(web.appendingPathComponent(path), in: project) else { continue }
            files[path] = data
        }
        let gone = built.files.keys.filter { now[$0] == nil }.sorted()
        var change = Change(files: files, gone: gone, changed: changed)
        change.cannot = cannot(project, change)
        return change
    }

    /// What keeps a page from taking a change in place, as lamp.js would find it: the page opens again from the files it's
    /// given, with lamp.js running first, so a script that runs before lamp.js, a module script (whose imports a file put
    /// in place can't follow), or more than the page can keep across opening again needs the app put there again.
    static func cannot(_ project: LampProject, _ change: Change) -> String? {
        if change.files.values.reduce(0, { $0 + $1.count }) > most { return "the change is too big to send" }
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
    static func words(_ change: Change) -> [[String: Any]] {
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
        let id = UUID().uuidString.lowercased()
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

    /// Puts the page as it is now into every copy of `project` open in its wish's room on a device Lamp doesn't reach
    /// itself. Answers the places it went to, and those whose copy is open but can't take it in place (with why), which
    /// wait for Reload.
    @MainActor static func put(_ project: LampProject, wish: LampProject) async -> (reached: Set<Destination>, waiting: [Destination: String]) {
        guard project.platform.target.changesAreWeb(project) else { return ([], [:]) }
        let room = WishRooms.key(for: wish), app = WishRooms.peer(project, in: wish)
        var reached: Set<Destination> = [], waiting: [Destination: String] = [:]
        for member in WishRooms.presence(of: wish) {
            guard let copy = member["peer"] as? String, WishChannel.app(of: copy) == app,
                  var place = (member["device"] as? String).flatMap(place(of:)) else { continue }
            // Android's phone and TV places are one app: the copy is on whichever was built.
            if place == .android, built(project, at: .android) == nil, built(project, at: .androidTV) != nil { place = .androidTV }
            let key = project.id + "\t" + copy
            guard let change = change(for: project, at: place, given: given[key]) else { continue }
            if let why = change.cannot { waiting[place] = why; continue }
            var went = true
            for word in words(change) where went {
                went = await ControllerRelay.say(in: room, to: [copy], data: word) == [copy]
            }
            guard went else { continue }
            given[key] = hashes(of: project)
            reached.insert(place)
        }
        return (reached, waiting)
    }

    /// The copies were given the app again (Reload, Play): what each has is its build's.
    @MainActor static func installed(_ project: LampProject) {
        given = given.filter { !$0.key.hasPrefix(project.id + "\t") }
    }
}
