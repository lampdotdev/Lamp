import CryptoKit
import Foundation

/// Lamp on the Mac as a keeper of a wish's shared collections (`LampStore.shared`, the wish's own, and shared files): a
/// member of the wish's room under the relay's own name (`WishChannel.relayName`, "lamp"), which no app of a wish may
/// take, that keeps every collection the copies share and speaks the copies' own `store` messages (`items`, `sum`, `ask`,
/// `file`), so a copy that opens while no other is open still gets the latest, and what it changes while only Lamp is
/// there reaches the others when they open. It never sets an item itself: it merges what copies send by their rules
/// (item by item, the latest setting winning, a deletion kept a month) and answers with what it has, so a copy that
/// meets it is as if it met the copy that set each item.
///
/// It isn't an app of the wish: it's never in the room's list or its members, so no app counts it among its copies or
/// apps; the room's `welcome` says it keeps (`keeps`), and a copy that speaks 7 or more (`wire`) then counts it among
/// those it shares collections with, all of them, an app's own by that app (`scope`) and the wish's own together. An
/// older copy never hears from it; what such copies send each other through the room is kept all the same.
///
/// What it keeps is in Lamp's own folder (the room's `keep`, by the wish's tag), sealed with a key from the wish's key,
/// so it reads as nothing without the key, which is kept apart (`WishKeys`). It runs on the relay's queue, as the room does.
final class WishKeeper {
    /// The first wire that knows Lamp keeps: only such a copy is sent anything.
    static let wire = 7
    static let itemLimit = 8 * 1024
    static let sharedLimit = 1024 * 1024
    static let filesLimit = 256 * 1024 * 1024
    static let collectionsLimit = 32
    static let removalsKept: Int64 = 30 * 24 * 3600 * 1000
    /// The wish's own collections, as a scope: every other scope is one app's, by its name.
    static let wishWide = "*"

    struct Entry {
        var value: Any?
        var ms: Int64
        var n: Int
        var peer: String
        func isLater(than other: Entry) -> Bool { (ms, n, peer) > (other.ms, other.n, other.peer) }
        var json: [String: Any] {
            var json: [String: Any] = ["c": [ms, n, peer]]
            if let value { json["v"] = value }
            return json
        }
        /// As the libraries take one: whole numbers in range only, as every language reads them.
        init?(_ json: Any?) {
            guard let json = json as? [String: Any], let c = json["c"] as? [Any], c.count == 3,
                  let ms = Self.whole(c[0]), let n = Self.whole(c[1]), let peer = c[2] as? String,
                  ms <= 1 << 50, n <= 1_000_000, peer.utf8.count <= 32 else { return nil }
            self.ms = ms
            self.n = Int(n)
            self.peer = peer
            self.value = json["v"].flatMap { $0 is NSNull ? nil : $0 }
        }
        private static func whole(_ value: Any) -> Int64? {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), !CFNumberIsFloatType(number),
                  number.int64Value >= 0 else { return nil }
            return number.int64Value
        }
    }

    struct Item {
        var entry: Entry
        /// What it takes of the scope's room: its id, and its value as JSON or at least 32 bytes, which a deletion takes.
        var held: Int
    }

    private final class Incoming {
        let scope: String, name: String, id: String, sum: String, size: Int
        var data = Data()
        var moved = Date()
        init(scope: String, name: String, id: String, sum: String, size: Int) {
            self.scope = scope; self.name = name; self.id = id; self.sum = sum; self.size = size
        }
    }

    private final class Outgoing {
        let bytes: Data
        var offset = 0
        var acknowledged = 0
        var moved = Date()
        init(bytes: Data) { self.bytes = bytes }
    }

    let folder: URL
    private let sealing: SymmetricKey
    /// Each scope's collections, by name, then each item by id: read from disk the first time it's needed.
    private var scopes: [String: [String: [String: Item]]] = [:]
    private var unsaved: Set<String> = []
    private var saving = false
    private var closed = false
    private let queue: DispatchQueue
    private var incoming: [String: Incoming] = [:]
    private var outgoing: [String: Outgoing] = [:]
    /// The files asked of each copy for, each by scope, collection and id: whom and when.
    private var fileAsks: [String: (copy: String, at: Date)] = [:]
    private var fileTries: [String: Int] = [:]
    private var nextFile: UInt32 = 1
    private var beats = 0

    /// How many apps the wish has, which bounds what's held from them as each copy's library bounds it.
    var appCount = 1
    /// Says a `store` or file message to one copy, as from Lamp (the room seals it); nothing for a copy not in the room.
    var send: (_ copy: String, _ message: [String: Any]) -> Void = { _, _ in }
    /// Hands one copy a piece of a file (`WishChannel.piece`, from Lamp); false when it can't take more now.
    var sendPiece: (_ copy: String, _ piece: Data) -> Bool = { _, _ in false }
    /// The copies in the room now, with what each speaks.
    var present: () -> [String: Int] = { [:] }

    init(folder: URL, key: SymmetricKey, queue: DispatchQueue) {
        self.folder = folder
        self.queue = queue
        sealing = SymmetricKey(data: WishChannel.derive("lamp-wish keep", key: key))
    }

    // MARK: From the room

    /// A copy came into the room: told what each of its collections adds up to here, so it asks for what it lacks, and
    /// asked for the files Lamp lacks.
    func joined(_ copy: String, wire: Int) {
        guard wire >= Self.wire, !closed else { return }
        sendSums(to: copy)
        fetchFiles()
    }

    func left(_ copy: String) {
        incoming = incoming.filter { !$0.key.hasPrefix(copy + "\t") }
        outgoing = outgoing.filter { !$0.key.hasPrefix(copy + "\t") }
        for (key, ask) in fileAsks where ask.copy == copy { fileAsks[key] = nil }
        fetchFiles()
    }

    /// A copy's `store` message to Lamp.
    func heard(_ m: [String: Any], from copy: String) {
        guard !closed, WishChannel.isName(copy) else { return }
        switch m["op"] as? String {
        case "items":
            guard let name = m["s"] as? String, Self.isCollection(name), let given = m["items"] as? [String: Any] else { return }
            merge(scope(of: name, copy: copy), name, given)
        case "sum":
            var asks: [String: [Int]] = [:]
            for (name, sum) in m["sums"] as? [String: String] ?? [:] where Self.isCollection(name) {
                let mine = sums(scope(of: name, copy: copy), name)
                let parts = Self.parts(sum)
                let differ = (0..<16).filter { parts[$0] != 0 && parts[$0] != mine[$0] }
                if !differ.isEmpty { asks[name] = differ }
            }
            for batch in Self.batches(asks) { send(copy, ["t": "store", "op": "ask", "asks": batch]) }
        case "ask":
            for (name, buckets) in m["asks"] as? [String: [Int]] ?? [:] where Self.isCollection(name) {
                let wanted = Set(buckets)
                let list = (collections(scope(of: name, copy: copy))[name] ?? [:]).filter { wanted.contains(Int(Self.fnv($0.key) & 15)) }
                if !list.isEmpty { shareItems(name, list.mapValues(\.entry), to: copy) }
            }
        case "file":
            guard let name = m["s"] as? String, name.hasPrefix("files:"), Self.isCollection(name), let id = m["id"] as? String,
                  let sum = m["sum"] as? String else { return }
            sendFile(scope(of: name, copy: copy), name, id: id, sum: sum, to: copy)
        default:
            break
        }
    }

    /// Items one copy sent another through the room: kept as if sent to Lamp, so what copies that don't know Lamp keeps
    /// (an older copy) say to each other is kept too.
    func overheard(_ m: [String: Any], from copy: String) {
        guard !closed, m["op"] as? String == "items", let name = m["s"] as? String, Self.isCollection(name),
              let given = m["items"] as? [String: Any] else { return }
        merge(scope(of: name, copy: copy), name, given)
    }

    /// Every few seconds, from the relay's beat: once a minute each copy that knows Lamp keeps is told its sums again,
    /// a file asked for and not come is asked again, and a file that stopped moving ends.
    func tick() {
        guard !closed else { return }
        let now = Date()
        for (key, file) in incoming where now.timeIntervalSince(file.moved) > 20 {
            incoming[key] = nil
            if let (copy, id) = Self.split(key) { send(copy, ["t": "file-refuse", "id": id, "reason": "The file stopped moving."]) }
        }
        for (key, file) in outgoing where now.timeIntervalSince(file.moved) > 20 {
            outgoing[key] = nil
            if let (copy, id) = Self.split(key) { send(copy, ["t": "file-cancel", "id": id]) }
        }
        beats += 1
        if beats % 12 == 0 { for (copy, wire) in present() where wire >= Self.wire { sendSums(to: copy) } }
        if beats % 12 == 6 { fetchFiles() }
    }

    /// The room is over: what's unsaved is written now, and nothing more is.
    func close() {
        save()
        closed = true
    }

    /// The wish is gone: everything kept for it goes.
    func forget() {
        closed = true
        scopes = [:]
        unsaved = []
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: Collections

    /// Which scope a copy's collection is in: the wish's own, or the copy's app's own.
    private func scope(of name: String, copy: String) -> String {
        Self.isWishWide(name) ? Self.wishWide : WishChannel.app(of: copy)
    }

    private func collections(_ scope: String) -> [String: [String: Item]] {
        if let kept = scopes[scope] { return kept }
        var list: [String: [String: Item]] = [:]
        if let sealed = try? Data(contentsOf: scopeURL(scope)), let box = try? AES.GCM.SealedBox(combined: sealed),
           let plain = try? AES.GCM.open(box, using: sealing),
           let kept = (try? JSONSerialization.jsonObject(with: plain)) as? [String: [String: Any]] {
            for (name, items) in kept where Self.isCollection(name) {
                for (id, json) in items where Self.isItemID(id) {
                    guard let entry = Entry(json) else { continue }
                    list[name, default: [:]][id] = Item(entry: entry, held: Self.held(id, entry))
                }
            }
        }
        scopes[scope] = list
        dropExpired(scope)
        return scopes[scope] ?? [:]
    }

    /// Items a copy sent, each taken when it's later than what Lamp has, so whatever order they come in it ends with the
    /// same as every copy. What a scope holds is bounded as a copy bounds what it holds from others: twice what every app
    /// of the wish could set, the oldest deletions let go first when a flood needs room.
    private func merge(_ scope: String, _ name: String, _ given: [String: Any]) {
        var all = collections(scope)
        guard all[name] != nil || all.count < Self.collectionsLimit * 2 else { return }
        let most = Self.sharedLimit * 2 * max(2, appCount)
        var held = all.values.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.held } }
        var removals: [(String, String)]? = nil, next = 0
        func oldestRemoval(except id: String) -> (String, String)? {
            if removals == nil {
                removals = all.flatMap { name, list in list.filter { $0.value.entry.value == nil }.map { (name, $0.key, $0.value.entry) } }
                    .sorted { $1.2.isLater(than: $0.2) }.map { ($0.0, $0.1) }
            }
            while let list = removals, next < list.count {
                let each = list[next]
                next += 1
                if each != (name, id), all[each.0]?[each.1]?.entry.value == nil { return each }
            }
            return nil
        }
        let old = Int64(Date().timeIntervalSince1970 * 1000) - Self.removalsKept
        var changed: [String] = []
        for (id, json) in given.sorted(by: { $0.key < $1.key }) {
            guard Self.isItemID(id), let entry = Entry(json) else { continue }
            let had = all[name]?[id]
            if let had, !entry.isLater(than: had.entry) { continue }
            let size = entry.value.map(Self.size(of:)) ?? 32
            if size > Self.itemLimit * 2 { continue }
            let need = id.utf8.count + max(32, size)
            // A deletion too old to keep, or with no room left to keep it, still deletes; a value with no room is left.
            func dropOnly() {
                guard entry.value == nil, let had = all[name]?.removeValue(forKey: id) else { return }
                held -= had.held
                changed.append(id)
            }
            if entry.value == nil, entry.ms < old { dropOnly(); continue }
            while held - (had?.held ?? 0) + need > most, let gone = oldestRemoval(except: id), let removal = all[gone.0]?.removeValue(forKey: gone.1) {
                held -= removal.held
            }
            if held - (had?.held ?? 0) + need > most { dropOnly(); continue }
            held += need - (had?.held ?? 0)
            all[name, default: [:]][id] = Item(entry: entry, held: need)
            changed.append(id)
        }
        all = all.filter { !$0.value.isEmpty }
        scopes[scope] = all
        unsaved.insert(scope)
        saveSoon()
        if name.hasPrefix("files:") {
            for id in changed { dropStaleBytes(scope, name, id: id) }
            if !changed.isEmpty { fetchFiles() }
        }
    }

    private func dropExpired(_ scope: String) {
        let old = Int64(Date().timeIntervalSince1970 * 1000) - Self.removalsKept
        guard let all = scopes[scope], all.values.contains(where: { $0.values.contains { $0.entry.value == nil && $0.entry.ms <= old } }) else { return }
        scopes[scope] = all.mapValues { $0.filter { $0.value.entry.value != nil || $0.value.entry.ms > old } }.filter { !$0.value.isEmpty }
        unsaved.insert(scope)
        saveSoon()
    }

    /// Sends items to a copy a few at a time, so each message stays within what a message may be.
    private func shareItems(_ name: String, _ list: [String: Entry], to copy: String) {
        var batch: [String: Any] = [:], size = 0
        func flush() {
            guard !batch.isEmpty else { return }
            send(copy, ["t": "store", "op": "items", "s": name, "items": batch])
            batch = [:]
            size = 0
        }
        for (id, entry) in list.sorted(by: { $0.key < $1.key }) {
            let json = entry.json
            let bytes = Self.json([id: json])?.count ?? 0
            if size + bytes > 12 * 1024 { flush() }
            batch[id] = json
            size += bytes
        }
        flush()
    }

    /// Tells a copy what each sixteenth of each collection it shares adds up to here: its app's own and the wish's own.
    private func sendSums(to copy: String) {
        var said: [String: String] = [:]
        for scope in [WishChannel.app(of: copy), Self.wishWide] {
            for (name, list) in collections(scope) where !list.isEmpty {
                said[name] = sums(scope, name).map { String(format: "%08x", $0) }.joined()
            }
        }
        for batch in Self.batches(said) { send(copy, ["t": "store", "op": "sum", "sums": batch]) }
    }

    private func sums(_ scope: String, _ name: String) -> [UInt32] {
        var parts = [UInt32](repeating: 0, count: 16)
        for (id, item) in collections(scope)[name] ?? [:] {
            parts[Int(Self.fnv(id) & 15)] ^= Self.fnv("\(id)\u{0}\(item.entry.ms)\u{0}\(item.entry.n)\u{0}\(item.entry.peer)")
        }
        return parts
    }

    // MARK: Shared files

    private func bytesURL(_ scope: String, _ name: String, id: String, sum: String) -> URL {
        folder.appendingPathComponent("files").appendingPathComponent(Self.hex(Data(SHA256.hash(data: Data("\(scope)\u{0}\(name)\u{0}\(id)".utf8))).prefix(16)) + "-" + sum)
    }

    private func hasBytes(_ scope: String, _ name: String, id: String, sum: String) -> Bool {
        FileManager.default.fileExists(atPath: bytesURL(scope, name, id: id, sum: sum).path)
    }

    private func dropStaleBytes(_ scope: String, _ name: String, id: String) {
        let sum = (collections(scope)[name]?[id]?.entry.value as? [String: Any])?["sum"] as? String
        let prefix = bytesURL(scope, name, id: id, sum: "").lastPathComponent
        let files = folder.appendingPathComponent("files")
        for each in (try? FileManager.default.contentsOfDirectory(atPath: files.path)) ?? [] where each.hasPrefix(prefix) && each != prefix + (sum ?? "") {
            try? FileManager.default.removeItem(at: files.appendingPathComponent(each))
        }
    }

    /// Asks a copy for each shared file Lamp lacks: the one that set it first, then each other in turn, two at a time of
    /// each, again after a minute without them.
    private func fetchFiles() {
        let open = present().filter { $0.value >= Self.wire }.keys.sorted()
        guard !open.isEmpty, !closed else { return }
        let now = Date()
        for (scope, all) in scopes.sorted(by: { $0.key < $1.key }) {
            let sources = open.filter { scope == Self.wishWide || WishChannel.app(of: $0) == scope }
            guard !sources.isEmpty else { continue }
            var here = 0
            for (name, list) in all where name.hasPrefix("files:") {
                for (id, item) in list {
                    guard let meta = item.entry.value as? [String: Any], let sum = meta["sum"] as? String, let size = meta["size"] as? Int,
                          hasBytes(scope, name, id: id, sum: sum) else { continue }
                    here += size
                }
            }
            for (name, list) in all.sorted(by: { $0.key < $1.key }) where name.hasPrefix("files:") {
                for (id, item) in list.sorted(by: { $0.key < $1.key }) {
                    guard let meta = item.entry.value as? [String: Any], let sum = meta["sum"] as? String, let size = meta["size"] as? Int,
                          size <= ControllerWire.file else { continue }
                    let key = scope + "\t" + name + "\t" + id
                    if hasBytes(scope, name, id: id, sum: sum) { fileAsks[key] = nil; fileTries[key] = nil; continue }
                    if let ask = fileAsks[key], sources.contains(ask.copy), now.timeIntervalSince(ask.at) < 60 { continue }
                    guard here + size <= Self.filesLimit * 2 else { break }
                    let tries = fileTries[key] ?? 0
                    let order = sources.contains(item.entry.peer) ? [item.entry.peer] + sources.filter { $0 != item.entry.peer } : sources
                    let source = order[tries % order.count]
                    guard fileAsks.values.filter({ $0.copy == source && now.timeIntervalSince($0.at) < 60 }).count < 2 else { continue }
                    fileTries[key] = tries + 1
                    fileAsks[key] = (source, now)
                    here += size
                    send(source, ["t": "store", "op": "file", "s": name, "id": id, "sum": sum])
                }
            }
        }
    }

    /// A copy sending Lamp a file's bytes it asked for: taken only for a shared file Lamp has as that size and lacks.
    func fileStarts(_ m: [String: Any], from copy: String) {
        guard !closed, let id = ControllerWire.isID(m["id"]) else { return }
        let key = "\(copy)\t\(id)"
        let channel = m["ch"] as? String ?? ""
        let name = String(channel.dropFirst(6))
        let item = m["name"] as? String ?? ""
        let scope = scope(of: name, copy: copy)
        guard channel.hasPrefix("store:files:"), Self.isCollection(name), let size = m["size"] as? Int, size >= 0, size <= ControllerWire.file,
              incoming[key] == nil, incoming.keys.filter({ $0.hasPrefix(copy + "\t") }).count < ControllerWire.transfers,
              let meta = collections(scope)[name]?[item]?.entry.value as? [String: Any], meta["size"] as? Int == size,
              let sum = meta["sum"] as? String, !hasBytes(scope, name, id: item, sum: sum) else {
            return send(copy, ["t": "file-refuse", "id": id, "reason": "Lamp doesn't need that file now."])
        }
        let file = Incoming(scope: scope, name: name, id: item, sum: sum, size: size)
        incoming[key] = file
        if size == 0 { finish(key, file, from: copy, id: id) }
    }

    func piece(_ bytes: Data, id: UInt32, from copy: String) {
        let key = "\(copy)\t\(id)"
        guard let file = incoming[key] else { return }
        guard file.data.count + bytes.count <= file.size else {
            incoming[key] = nil
            return send(copy, ["t": "file-refuse", "id": id, "reason": "The file was bigger than it said."])
        }
        file.data.append(bytes)
        file.moved = Date()
        send(copy, ["t": "file-ack", "id": id, "got": file.data.count])
        if file.data.count == file.size { finish(key, file, from: copy, id: id) }
    }

    private func finish(_ key: String, _ file: Incoming, from copy: String, id: UInt32) {
        incoming[key] = nil
        if file.size == 0 { send(copy, ["t": "file-ack", "id": id, "got": 0]) }
        fileAsks[file.scope + "\t" + file.name + "\t" + file.id] = nil
        guard Self.checksum(file.data) == file.sum, let sealed = try? AES.GCM.seal(file.data, using: sealing).combined else { return fetchFiles() }
        let url = bytesURL(file.scope, file.name, id: file.id, sum: file.sum)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard Self.write(sealed, to: url) else { return }
        fileTries[file.scope + "\t" + file.name + "\t" + file.id] = nil
        dropStaleBytes(file.scope, file.name, id: file.id)
        fetchFiles()
    }

    func fileEnded(_ m: [String: Any], from copy: String) {
        guard let id = ControllerWire.isID(m["id"]) else { return }
        let key = "\(copy)\t\(id)"
        switch m["t"] as? String {
        case "file-ack":
            guard let file = outgoing[key], let got = m["got"] as? Int, got >= file.acknowledged, got <= file.offset else { return }
            file.acknowledged = got
            file.moved = Date()
            if got == file.bytes.count { outgoing[key] = nil } else { pump(key, to: copy) }
        case "file-refuse":
            outgoing[key] = nil
        case "file-cancel":
            incoming[key] = nil
        default:
            break
        }
    }

    /// A copy asked for a shared file's bytes: sent when Lamp has them as the file is now, two at a time to each copy.
    private func sendFile(_ scope: String, _ name: String, id: String, sum: String, to copy: String) {
        guard let meta = collections(scope)[name]?[id]?.entry.value as? [String: Any], meta["sum"] as? String == sum,
              outgoing.keys.filter({ $0.hasPrefix(copy + "\t") }).count < ControllerWire.transfers,
              let sealed = try? Data(contentsOf: bytesURL(scope, name, id: id, sum: sum)),
              let box = try? AES.GCM.SealedBox(combined: sealed), let bytes = try? AES.GCM.open(box, using: sealing),
              Self.checksum(bytes) == sum else { return }
        let fileID = nextFile
        nextFile = nextFile >= UInt32(Int32.max) - 1 ? 1 : nextFile + 1
        let key = "\(copy)\t\(fileID)"
        outgoing[key] = Outgoing(bytes: bytes)
        send(copy, ["t": "file", "id": Int(fileID), "name": id, "type": String((meta["type"] as? String ?? "").prefix(100)),
                    "size": bytes.count, "ch": "store:" + name])
        pump(key, to: copy)
    }

    /// A file's next pieces, never more than a window past what the copy has acknowledged.
    private func pump(_ key: String, to copy: String) {
        guard let file = outgoing[key], let (_, id) = Self.split(key) else { return }
        while file.offset < file.bytes.count, file.offset - file.acknowledged < ControllerWire.window {
            let count = min(ControllerWire.chunk, file.bytes.count - file.offset)
            let piece = WishChannel.piece(peer: WishChannel.relayName, id: id, bytes: file.bytes.subdata(in: file.offset..<(file.offset + count)))
            guard sendPiece(copy, piece) else { break }
            file.offset += count
        }
    }

    // MARK: Kept on disk

    private func scopeURL(_ scope: String) -> URL {
        folder.appendingPathComponent(Self.hex(Data(SHA256.hash(data: Data(scope.utf8))).prefix(16)) + ".kept")
    }

    /// Written a moment after a change, so a burst of them is written once.
    private func saveSoon() {
        guard !saving, !closed else { return }
        saving = true
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in self?.save() }
    }

    private func save() {
        saving = false
        guard !closed else { return }
        for scope in unsaved {
            let url = scopeURL(scope)
            let list = scopes[scope] ?? [:]
            if list.isEmpty { try? FileManager.default.removeItem(at: url); continue }
            guard let plain = Self.json(list.mapValues { $0.mapValues(\.entry.json) }),
                  let sealed = try? AES.GCM.seal(plain, using: sealing).combined else { continue }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            Self.write(sealed, to: url)
        }
        unsaved = []
    }

    /// Written whole, readable by this account alone.
    @discardableResult
    private static func write(_ data: Data, to url: URL) -> Bool {
        guard (try? data.write(to: url, options: .atomic)) != nil else { return false }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return true
    }

    // MARK: As the libraries have them

    static func isCollection(_ name: String) -> Bool {
        var plain = name.hasPrefix("files:") ? String(name.dropFirst(6)) : name
        if plain.hasPrefix("wish:") { plain = String(plain.dropFirst(5)) }
        return (1...64).contains(plain.utf8.count) && plain != "__proto__" && plain.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
    }
    static func isWishWide(_ name: String) -> Bool { (name.hasPrefix("files:") ? String(name.dropFirst(6)) : name).hasPrefix("wish:") }
    static func isItemID(_ id: String) -> Bool { (1...128).contains(id.utf8.count) && id != "__proto__" }
    static func size(of value: Any) -> Int {
        ((try? JSONSerialization.data(withJSONObject: [value], options: .withoutEscapingSlashes)).map(\.count) ?? 2) - 2
    }
    static func held(_ id: String, _ entry: Entry) -> Int { id.utf8.count + max(32, entry.value.map(size(of:)) ?? 32) }
    static func fnv(_ text: String) -> UInt32 {
        var hash: UInt32 = 2166136261
        for byte in text.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
        return hash
    }
    static func parts(_ sum: String) -> [UInt32] {
        let chars = Array(sum.utf8)
        guard chars.count == 128 else { return [UInt32](repeating: 0, count: 16) }
        return (0..<16).map { UInt32(String(decoding: chars[($0 * 8)..<($0 * 8 + 8)], as: UTF8.self), radix: 16) ?? 0 }
    }
    static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
    static func checksum(_ data: Data) -> String { hex(Data(SHA256.hash(data: data)).prefix(16)) }
    static func json(_ object: Any) -> Data? { try? JSONSerialization.data(withJSONObject: object, options: .withoutEscapingSlashes) }
    private static func split(_ key: String) -> (String, UInt32)? {
        let parts = key.split(separator: "\t")
        guard parts.count == 2, let id = UInt32(parts[1]) else { return nil }
        return (String(parts[0]), id)
    }
    /// A map split so each part stays within a message, as sums and asks for many collections can't go in one.
    private static func batches<T>(_ map: [String: T]) -> [[String: T]] {
        var out: [[String: T]] = [], batch: [String: T] = [:], size = 0
        for (name, value) in map.sorted(by: { $0.key < $1.key }) {
            let bytes = (json([name: value])?.count ?? 0)
            if size + bytes > 12 * 1024, !batch.isEmpty { out.append(batch); batch = [:]; size = 0 }
            batch[name] = value
            size += bytes
        }
        if !batch.isEmpty { out.append(batch) }
        return out
    }
}
