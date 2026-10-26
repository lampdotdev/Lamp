import CryptoKit
import Foundation
import LampRelayKit

/// Each wish's key: 32 random bytes that every app of the wish is given as Lamp puts it on its device, and that it proves
/// it holds to get into its wish's room (`WishChannel`), so nothing that crosses the network lets anyone else in or reads
/// what the apps say. Made the first time an app of a wish of more than one app needs it, kept in Lamp's own folder (never
/// the wish's, which the agent's commands read and versions and shared files carry), by the wish's instance so a rename
/// keeps it, and forgotten with the wish. It reaches each kind of app only by a way nobody on the network can read: a Mac
/// app's installed copy and a phone's build in Lamp's own folder (`Template.wishKeyPlistLines`), the simulator's app
/// folder after the install (`Store.tellSimulatorApp`), an Android app's own storage through adb (`androidInstallValues`),
/// the TV preview through its bridge, and a TV over the network only sealed to a key the TV app just made, inside the
/// claim Lamp opened for that TV as it put the app there (`WishRooms.claim`).
enum WishKeys {
    /// For tests, which keep theirs apart from any Lamp's.
    nonisolated(unsafe) static var folder = Edition.supportFolder.appendingPathComponent("Wish Keys") {
        didSet { lock.withLock { known = [:] } }
    }
    private static let lock = NSLock()
    /// Each key once read or made, so a key that couldn't be written stays the same for as long as Lamp runs.
    nonisolated(unsafe) private static var known: [String: Data] = [:]

    /// The wish's key, made on first use.
    static func key(for wish: LampProject) -> Data {
        lock.withLock {
            let url = file(for: wish)
            if let key = known[url.path] { return key }
            if let kept = try? Data(contentsOf: url), let key = Data(base64Encoded: String(decoding: kept, as: UTF8.self).trimmed),
               key.count == WishChannel.keySize {
                known[url.path] = key
                return key
            }
            let made = WishChannel.random(WishChannel.keySize)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if !FileManager.default.createFile(atPath: url.path, contents: Data(made.base64EncodedString().utf8), attributes: [.posixPermissions: 0o600]) {
                NSLog("Lamp couldn't keep the key for \(wish.name)'s apps: they'll need to be put on their devices again after Lamp restarts.")
            }
            known[url.path] = made
            return made
        }
    }

    /// The wish is gone: its apps' key with it.
    static func forget(_ wish: LampProject) {
        lock.withLock {
            let url = file(for: wish)
            known[url.path] = nil
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func file(for wish: LampProject) -> URL {
        let name = (wish.instance.isEmpty ? wish.id : wish.instance).map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }
        return folder.appendingPathComponent(String(name))
    }
}

/// The claims Lamp opens for a wish's key as it puts a wish's TV app on a TV: one per app, from that TV's address, for
/// two minutes from when Lamp starts putting it there and, if no claim was answered by then, two from when it opened it,
/// and spent by the first claim answered, after which only that page's own key pair is answered, for the claim's
/// minutes, in case the answer was lost on its way: sealed to the page again, it's no use to anyone else.
/// Apart from the TV's token claim (`DeviceSupport.Claims`), which lasts half an hour and may be answered any number of
/// times: the key, unlike the token, never crosses the network in clear, and the claim is the one moment someone on the
/// network could get it, by answering for the page. A request that fails on the way (the network, a key that can't be
/// used) spends nothing, so the page's tries again still work; once the claim is spent a page that opens again uses
/// the key it kept.
final class WishClaims: @unchecked Sendable {
    static let shared = WishClaims()
    /// For tests.
    nonisolated(unsafe) static var window: TimeInterval = 2 * 60
    private let lock = NSLock()
    private var open: [String: (address: String, until: Date)] = [:]
    /// The public half each spent claim was answered for, from where, and until when it may be answered again.
    private var spent: [String: (key: Data, address: String, until: Date)] = [:]

    /// Opens the claim as Lamp starts putting the app on the TV.
    func open(_ app: String, from address: String) {
        lock.withLock {
            spent[app] = nil
            open[app] = (DeviceSupport.Claims.plain(address), Date().addingTimeInterval(Self.window))
        }
    }

    /// Gives it its minutes again once the app is open on the TV, unless a claim was answered meanwhile.
    func renew(_ app: String, from address: String) {
        lock.withLock {
            guard spent[app] == nil else { return }
            open[app] = (DeviceSupport.Claims.plain(address), Date().addingTimeInterval(Self.window))
        }
    }

    func isOpen(_ app: String, from address: String?, for key: Data) -> Bool {
        lock.withLock {
            let from = address.map(DeviceSupport.Claims.plain)
            if let answered = spent[app] {
                return answered.until > Date() && answered.address == from && answered.key == key
            }
            guard let claim = open[app], claim.until > Date() else { open[app] = nil; return false }
            return from == claim.address
        }
    }

    func spend(_ app: String, on key: Data) {
        lock.withLock {
            guard spent[app] == nil, let claim = open.removeValue(forKey: app) else { return }
            spent[app] = (key, claim.address, Date().addingTimeInterval(Self.window))
        }
    }
}

/// The apps of one wish seeing each other and talking: a room for the wish at the controllers' relay (`Relay`,
/// `ControllerRelay`), which each of its apps joins as a peer named by its folder in the wish ("tv", "iphone", "apple",
/// "mac", "android"). Where a wish's apps are is `Store.apps(of:)`'s to know, and nothing here asks which is at the root.
/// Lamp only introduces them: an app shows its own token at `/app/wish` and is told where the relay is, which peer it
/// is and who is in the room now; it gets in by proving it holds the wish's key (`WishKeys`, `WishChannel`), and what
/// the apps then say to each other is sealed and goes through the relay's process, never Lamp's. An app that can't hold
/// a socket (an Android app, whose blocks speak HTTP) has Lamp hold one to the room for it (`WishProxies`), which carries
/// its handshake and sealed messages as they are, unread. A room is opened the first time an app of the wish asks, told
/// the wish's apps again when they change, and ended when the wish is gone, has no other app, or has had nobody in it
/// and nobody asking for a while, so the relay runs only while something needs it.
///
/// The builder is told the same block in every language (`Agent.Rules.wishTalk`) and, at the end of each request, where
/// each app of the wish is: open or not, in the room or not (`WishNote`).
///
/// A wish of one app has a room too, for its copies on several devices (two iPhones, a screen on an iPad and a TV),
/// and its building blocks carry the code (`Template.carriesWish`); what's for a wish of several apps alone is the rule
/// in the prompt and the builder's note.
@MainActor
enum WishRooms {
    /// What this Lamp's apps of a wish say to each other, numbered as LampSupport.swift, LampSupport.kt and lamp.js number
    /// it (`wire` in each): an app in the room that says less was built by an earlier Lamp.
    static let wire = 4

    /// The room's key at the relay: never a TV app's game key (the app's id), so a credential says which it is for.
    static func key(for wish: LampProject) -> String { "wish:" + wish.id }

    /// Which of the wish's apps this one is: its folder in the wish, lowercased ("tv", "iphone", "apple", "mac", "android").
    /// An app keeps its folder when its kind changes in place (an iPhone app made for the Mac too stays in iPhone/), so
    /// its name holds; the app at a wish's root, which has no folder of its own yet, is named by the folder an app of its
    /// kind gets, the one it will have once every app is in a folder.
    static func peer(_ app: LampProject, in wish: LampProject) -> String {
        (app.id == wish.id ? Parts.folder(for: app.platform, integration: Parts.listedIntegration(of: app)) : app.dir.lastPathComponent).lowercased()
    }

    /// Whether an app of this kind joins the room. A device's app made through its integration doesn't yet (a Roku's
    /// channel has none of the room's handshake), so it's left out of the room's list and the others never wait for it.
    nonisolated static func joins(_ kind: Platform) -> Bool { kind.target.part?.joinsWish ?? true }

    /// Every app the wish has, and every one it asks for and doesn't have yet (`Parts.waiting`), as the relay and the
    /// libraries describe one: an app waiting to be made is in the list from the start, not open, so the first app of a
    /// wish meant to be several is one of several from its first build, as its building blocks are.
    static func described(_ apps: [LampProject], in wish: LampProject) -> [[String: Any]] {
        apps.filter { joins($0.platform) }.map { describe($0, in: wish) }
            + Parts.waiting(in: wish, parts: apps.filter { $0.id != wish.id }).filter { joins($0.kind) }.map { describe($0, in: wish) }
    }

    /// An app the wish asks for and doesn't have yet, by the folder it will be made in (`Parts.folder(waiting:in:)`),
    /// marked as waiting so the others say it isn't ready rather than ask the person to open it.
    static func describe(_ app: WishApp, in wish: LampProject) -> [String: Any] {
        ["peer": Parts.folder(waiting: app, in: wish.dir).lowercased(), "kind": Parts.word(for: app.kind), "name": Parts.name(of: app), "waiting": true]
    }

    /// `kind` is the device word the tools use for the app ("iphone" for an app for iPhone and iPad, Mac too).
    static func describe(_ app: LampProject, in wish: LampProject) -> [String: Any] {
        ["peer": peer(app, in: wish), "kind": Parts.word(for: app.platform), "name": Parts.name(of: app)]
    }

    /// When each room was last asked for by one of its apps, by key.
    private static var asked: [String: Date] = [:]
    /// A room nobody is in, and nobody has asked for in this long, is ended.
    static let idle: TimeInterval = 15 * 60
    private static var timer: Timer?

    /// What an app of a wish is told when it asks (`/app/wish`): the relay's socket by the name it reached Lamp at, which
    /// peer it is, and who is in the room now; nothing that lets it in, which is the wish's key the app was given when it
    /// was put on its device. The TV preview, whose page asks through its bridge on this Mac and was put nowhere, is
    /// given the key here (`preview`). A wish of one app has a room all the same, for the app's copies.
    static func answer(for project: LampProject, wish: LampProject, apps: [LampProject], host: String, preview: Bool = false) async -> (Int, [String: Any]) {
        let me = describe(project, in: wish)
        let roster = described(apps, in: wish)
        guard !roster.isEmpty else { return (200, ["alone": true, "renew": 300, "me": me]) }
        let key = key(for: wish)
        asked[key] = Date()
        ControllerRelay.openRoom(key, wishKey: WishKeys.key(for: wish), apps: roster)
        startTimer()
        guard let port = await ControllerRelay.ready() else { return (503, ["error": "Lamp couldn't start the link between the wish's apps."]) }
        var answer: [String: Any] = ["socket": "ws://\(host):\(port)/", "peer": peer(project, in: wish),
                                     "peers": presence(of: wish), "apps": roster, "me": me]
        if preview { answer["key"] = WishKeys.key(for: wish).base64EncodedString() }
        return (200, answer)
    }

    /// A TV app Lamp has just put on a TV asking for its wish's key (`/app/wish/claim`), which never goes in a TV's
    /// package (a Samsung TV's goes over a link anyone on the network can read) nor in clear: the page makes a key pair
    /// as it opens and sends its public half, and the wish's key comes back sealed to it, so only that page can open it.
    /// The request is plain HTTP, so someone on the network between the TV and this Mac could put a public half of their
    /// own in its place and have the key sealed to them; nothing short of an encrypted link to the gateway stops that.
    /// So the claim is open only as long as it must be (`WishClaims`): from the TV's address, for minutes after Lamp put
    /// the app there and opened it, and only until the first claim it answers, which in a normal install is the page's
    /// own a moment after it opens.
    static func claim(for project: LampProject, wish: LampProject, apps: [LampProject], publicKey: Data, from address: String?) -> (Int, [String: Any]) {
        guard WishClaims.shared.isOpen(project.id, from: address, for: publicKey) else { return (403, ["error": "Lamp didn't just put this app here."]) }
        let answer = claim(for: wish, apps: apps, publicKey: publicKey)
        if answer.0 == 200 { WishClaims.shared.spend(project.id, on: publicKey) }
        return answer
    }

    static func claim(for wish: LampProject, apps: [LampProject], publicKey: Data) -> (Int, [String: Any]) {
        guard !described(apps, in: wish).isEmpty else { return (200, ["alone": true]) }
        guard let theirs = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: publicKey) else { return (400, ["error": "That key can't be used."]) }
        let mine = Curve25519.KeyAgreement.PrivateKey()
        guard let shared = try? mine.sharedSecretFromKeyAgreement(with: theirs) else { return (400, ["error": "That key can't be used."]) }
        let secret = shared.withUnsafeBytes { Data($0) }
        // A key the page couldn't have made (one of the few points every secret comes out zero for) seals nothing.
        guard secret.contains(where: { $0 != 0 }) else { return (400, ["error": "That key can't be used."]) }
        let sealing = SymmetricKey(data: claimKey(secret: secret, lamp: mine.publicKey.rawRepresentation, page: publicKey))
        let nonce = AES.GCM.Nonce()
        guard let box = try? AES.GCM.seal(WishKeys.key(for: wish), using: sealing, nonce: nonce) else { return (500, ["error": "Lamp couldn't seal the key."]) }
        return (200, ["public": mine.publicKey.rawRepresentation.base64EncodedString(), "nonce": Data(nonce).base64EncodedString(),
                      "sealed": (box.ciphertext + box.tag).base64EncodedString()])
    }

    /// What a claim's key is sealed with: from the two keys' shared secret and both public halves, as lamp.js makes it.
    static func claimKey(secret: Data, lamp: Data, page: Data) -> Data {
        WishChannel.derive("lamp-wish claim", key: SymmetricKey(data: secret), lamp + page)
    }

    /// Who is in the wish's room now, as the relay last said.
    static func presence(of wish: LampProject) -> [[String: Any]] { ControllerRelay.presence[key(for: wish)] ?? [] }

    /// Kept in step with the list of apps (each wish with its apps, `Store.apps(of:)`): a room whose wish is gone, or has
    /// no app now, ends; one whose apps changed is told them again.
    static func sync(_ wishes: [(wish: LampProject, apps: [LampProject])]) {
        let byKey = Dictionary(wishes.map { (key(for: $0.wish), $0) }, uniquingKeysWith: { a, _ in a })
        for key in ControllerRelay.roomKeys {
            guard let entry = byKey[key] else { end(key); continue }
            let roster = described(entry.apps, in: entry.wish)
            guard !roster.isEmpty else { end(key); continue }
            ControllerRelay.openRoom(key, wishKey: WishKeys.key(for: entry.wish), apps: roster)
        }
        expire()
    }

    /// The room is over: its members are let go, and the apps Lamp joined to it are dropped.
    static func end(_ key: String) {
        asked[key] = nil
        ControllerRelay.endRoom(key)
        WishProxies.end(room: key)
    }

    /// For tests.
    static func forgetAll() {
        for key in ControllerRelay.roomKeys { end(key) }
        asked = [:]
    }

    private static func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { expire() }
        }
    }

    private static func expire() {
        let now = Date()
        for key in ControllerRelay.roomKeys {
            let lastAsked = max(asked[key] ?? .distantPast, WishProxies.lastAsked(room: key) ?? .distantPast)
            guard (ControllerRelay.presence[key] ?? []).isEmpty, now.timeIntervalSince(lastAsked) > idle else { continue }
            end(key)
        }
        if ControllerRelay.roomKeys.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }
}

/// An app that can't hold a WebSocket (an Android app: its blocks speak HTTP on a socket) in its wish's room: Lamp holds
/// the socket for it and carries what goes each way as it is, unread, since the app does its own handshake and seals its
/// own messages (`WishChannel`). The app asks Lamp to open the socket (`/app/wish/open`, which ends any it had), sends
/// its handshake's text and its sealed messages (`/app/wish/send`), and polls for what came (`/app/wish/poll`, answered
/// as soon as there is something, or after a wait). Each socket is a link of its own, numbered, so nothing of an old one
/// reaches a new handshake. Lamp keeps what arrived only until the next poll, and lets the socket go when the app has
/// stopped polling.
@MainActor
enum WishProxies {
    final class Proxy {
        let app: String
        /// Which copy of the app it holds the socket for: an app open on two Android devices at once has one each. An
        /// app built before copies says none.
        let copy: String
        let room: String
        let link: Int
        var task: URLSessionWebSocketTask?
        var events: [[String: Any]] = []
        var waiter: CheckedContinuation<[[String: Any]], Never>?
        var lastPoll = Date()
        var beat: Timer?
        /// What the app sent, waiting its turn: each goes once the one before it has, so they reach the relay in order.
        var sending: Task<Void, Never>?
        init(app: String, copy: String, room: String, link: Int) {
            self.app = app
            self.copy = copy
            self.room = room
            self.link = link
        }
    }

    /// Events kept for an app between polls, past which the link is let go: a sealed message missed can't be skipped,
    /// so an app that fell this far behind starts its link again.
    static let backlog = 256
    /// A poll waits this long for something to come before answering with nothing. Short, since an app that stops (closed,
    /// force-stopped, its phone asleep) is noticed only by its polls stopping, and the wish's other apps should see it
    /// leave while it's gone, so that they see it arrive again when it's back.
    static var wait: TimeInterval = 6
    /// An app that hasn't started a poll this long after its last one could have ended has stopped: its socket is let go,
    /// so the room tells the others it left, within seconds, as it does for an app holding its own socket.
    static var grace: TimeInterval = 4

    /// By app and copy (`slot`).
    private static var proxies: [String: Proxy] = [:]
    private static func slot(_ app: String, _ copy: String) -> String { app + "\t" + copy }
    /// The app's proxy on this link, whichever copy it's for.
    private static func proxy(_ project: LampProject, link: Int?) -> Proxy? { proxies.values.first { $0.app == project.id && $0.link == link } }
    private static var links = 0

    static func lastAsked(room: String) -> Date? { proxies.values.filter { $0.room == room }.map(\.lastPoll).max() }

    /// Opens the socket to its wish's room for this copy of the app, closing any it had, and says which link it is, with
    /// what `/app/wish` says (alone, which peer it is).
    static func open(_ project: LampProject, copy: String = "", wish: LampProject, apps: [LampProject]) async -> (Int, [String: Any]) {
        let copy = WishChannel.isName("a." + copy) ? copy : ""
        let slot = slot(project.id, copy)
        if let old = proxies[slot] { close(old); proxies[slot] = nil }
        var (status, answer) = await WishRooms.answer(for: project, wish: wish, apps: apps, host: "127.0.0.1")
        guard status == 200, answer["alone"] as? Bool != true else { return (status, answer) }
        guard let socket = (answer["socket"] as? String).flatMap(URL.init(string:)) else {
            return (503, ["error": "Lamp couldn't say where the wish's apps meet."])
        }
        links += 1
        let proxy = Proxy(app: project.id, copy: copy, room: WishRooms.key(for: wish), link: links)
        proxies[slot] = proxy
        let task = URLSession.shared.webSocketTask(with: socket)
        task.maximumMessageSize = WishChannel.pieceLimit + 1024   // a file's piece, sealed
        proxy.task = task
        task.resume()
        receive(proxy, on: task)
        // The relay's beats are answered here, in clear as they always are (they carry nothing), so the app polls only
        // when something has come.
        var ticks = 0
        proxy.beat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard proxy.task === task else { return }
                if proxy.waiter == nil, Date().timeIntervalSince(proxy.lastPoll) > wait + grace {
                    close(proxy)
                    if proxies[slot] === proxy { proxies[slot] = nil }
                    return
                }
                ticks += 1
                if ticks % 5 == 0 { task.send(.string(#"{"t":"beat"}"#)) { _ in } }
            }
        }
        answer["socket"] = nil
        answer["link"] = proxy.link
        return (200, answer)
    }

    /// What has come for the app on this link since its last poll: `{"text": …}` for the handshake's, `{"data": base64}`
    /// for a sealed message, and `{"closed": code}` when the socket went; waiting a while for the first. A link that isn't
    /// the app's now is answered 409, and the app opens a new one.
    static func poll(_ project: LampProject, link: Int) async -> (Int, [String: Any]) {
        guard let proxy = proxy(project, link: link) else { return (409, ["error": "That link to the wish's apps is over: open another."]) }
        proxy.lastPoll = Date()
        if !proxy.events.isEmpty || proxy.task == nil { return (200, ["events": take(proxy)]) }
        // One poll waits at a time: a second one ends the first with nothing, since the app has moved on.
        proxy.waiter?.resume(returning: [])
        proxy.waiter = nil
        let events: [[String: Any]] = await withCheckedContinuation { continuation in
            proxy.waiter = continuation
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(wait))
                guard let waiting = proxy.waiter else { return }
                proxy.waiter = nil
                waiting.resume(returning: take(proxy))
            }
        }
        return (200, ["events": events])
    }

    /// Sends what the app said on this link, in order: its handshake's `text`s, and its sealed messages (`data`, base64),
    /// each as one message on the socket, as the app would on its own.
    static func send(_ project: LampProject, body: [String: Any]) async -> (Int, [String: Any]) {
        guard let proxy = proxy(project, link: body["link"] as? Int), let task = proxy.task else {
            return (409, ["error": "That link to the wish's apps is over: open another."])
        }
        var messages: [URLSessionWebSocketTask.Message] = []
        for item in body["frames"] as? [[String: Any]] ?? [] {
            if let text = item["text"] as? String, text.utf8.count <= ControllerWire.message { messages.append(.string(text)) }
            else if let data = (item["data"] as? String).flatMap({ Data(base64Encoded: $0) }), data.count <= max(WishChannel.sealedLimit, WishChannel.pieceLimit) + 16 { messages.append(.data(data)) }
            else { return (413, ["error": "A message between the wish's apps is at most \(ControllerWire.message) bytes as JSON."]) }
        }
        proxy.lastPoll = Date()
        let before = proxy.sending
        let sent = Task { @MainActor () -> Error? in
            await before?.value
            for message in messages {
                do { try await task.send(message) } catch { return error }
            }
            return nil
        }
        proxy.sending = Task { _ = await sent.value }
        if let error = await sent.value {
            return (503, ["error": "The message didn't reach the wish's other apps: \(error.localizedDescription)"])
        }
        return (200, ["ok": true])
    }

    /// The room ended: every app Lamp joined to it is dropped.
    static func end(room: String) {
        for (id, proxy) in proxies where proxy.room == room { close(proxy); proxies[id] = nil }
    }

    private static func take(_ proxy: Proxy) -> [[String: Any]] {
        let events = proxy.events
        proxy.events = []
        return events
    }

    private static func push(_ proxy: Proxy, _ event: [String: Any]) {
        proxy.events.append(event)
        // Too far behind to catch up: a sealed message can't be skipped, so the link ends and the app starts another.
        if proxy.events.count > backlog, proxy.task != nil { close(proxy); proxy.events.append(["closed": 1008]) }
        if let waiter = proxy.waiter {
            proxy.waiter = nil
            waiter.resume(returning: take(proxy))
        }
    }

    private static func receive(_ proxy: Proxy, on task: URLSessionWebSocketTask) {
        task.receive { result in
            Task { @MainActor in
                guard proxy.task === task else { return }
                switch result {
                case .success(.string(let text)):
                    let said = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
                    if said?["t"] as? String != "beat" { push(proxy, ["text": text]) }
                    receive(proxy, on: task)
                case .success(.data(let data)):
                    push(proxy, ["data": data.base64EncodedString()])
                    receive(proxy, on: task)
                case .success:
                    receive(proxy, on: task)
                case .failure:
                    let code = task.closeCode.rawValue
                    proxy.task = nil
                    proxy.beat?.invalidate()
                    proxy.beat = nil
                    push(proxy, ["closed": code])
                }
            }
        }
    }

    private static func close(_ proxy: Proxy) {
        proxy.beat?.invalidate()
        proxy.beat = nil
        proxy.task?.cancel(with: .goingAway, reason: nil)
        proxy.task = nil
        proxy.waiter?.resume(returning: [])
        proxy.waiter = nil
    }
}

/// Where each app of a wish is, at the end of each request for a wish of more than one app: open or not, and in the
/// wish's room or not, so the builder can tell "the Android app never joined" from "it joined and the message was
/// lost" without guessing. Like `DeviceNote`, it rides with the request and is sent again only when it changes.
@MainActor
enum WishNote {
    static func line(for project: LampProject, store: Store) -> String {
        let wish = store.wish(of: project)
        let apps = store.apps(of: wish)
        let waiting = Parts.waiting(in: wish, parts: apps.filter { $0.id != wish.id })
        guard apps.count + waiting.count >= 2 else { return "" }
        // Each member is one copy of an app: the app open on one device ("screen.k3j9x0ab"), or an app built before copies
        // by its name alone.
        let present = Dictionary(grouping: WishRooms.presence(of: wish)) { member in
            (member["app"] as? String) ?? (member["peer"] as? String).map(WishChannel.app(of:)) ?? ""
        }
        return apps.map { app in
            let name = Parts.name(of: app)
            let peer = WishRooms.peer(app, in: wish)
            // One that can't join the room says so, rather than that it isn't in it.
            guard WishRooms.joins(app.platform) else {
                return "\(name.prefix(1).uppercased() + name.dropFirst()): can't reach the wish's other apps yet, and they can't reach it"
            }
            var line = "\(name.prefix(1).uppercased() + name.dropFirst()) (peer \"\(peer)\"): \(store.isOpen(app) ? "open" : "not open")"
            let copies = present[peer] ?? []
            if copies.count > 1 { line += ", open on \(copies.count) devices at once" }
            if copies.isEmpty { line += ", not in the room" }
            return line + copies.map { member in
                var line = ""
                let since = (member["since"] as? Int).map { Date(timeIntervalSince1970: Double($0) / 1000).formatted(date: .omitted, time: .shortened) } ?? "?"
                line += ", in the wish's room as \"\(member["device"] as? String ?? "")\" since \(since)"
                if copies.count > 1, let id = member["peer"] as? String { line += " (copy \"\(id)\")" }
                // Built by an earlier Lamp: its wish's other apps show it as out of date and share no values, files or game
                // controls with it,
                // which opening it from Lamp mends by building it again.
                if (member["wire"] as? Int ?? 1) < WishRooms.wire {
                    line += ", built by an earlier Lamp (the others show it as out of date and share nothing new with it (values, files, game controls) until it's opened from Lamp, which builds it again)"
                }
                // What the app says of its own link: the apps it reaches straight, which go on with Lamp closed, and
                // what stops it reaching them.
                let link = member["link"] as? [String: Any] ?? [:]
                if link["state"] as? String == "localNetworkDenied" {
                    line += ", Local Network is turned off for it, so it reaches the others only through Lamp"
                }
                if let direct = link["direct"] as? [String], !direct.isEmpty {
                    line += ", straight to \(direct.map { "\"\($0)\"" }.joined(separator: " and "))"
                } else if link["state"] != nil {
                    line += ", straight to none"
                }
                return line
            }.joined()
        }.joined(separator: "; ") + waiting.map { app in
            let name = Parts.name(of: app)
            return "; \(name.prefix(1).uppercased() + name.dropFirst()) (peer \"\(Parts.folder(waiting: app, in: wish.dir).lowercased())\"): not made yet"
        }.joined() + "."
    }

    static func brief(for project: LampProject, engine: Engine, session: String?) -> String {
        let now = line(for: project, store: .shared)
        guard !now.isEmpty else { return "" }
        switch note.telling(now, for: project, engine: engine, session: session) {
        case .fresh, .changed: return "\n\n---\nThe wish's apps right now (from Lamp, not part of the request above; the room is where they see each other through LampWish): \(now)"
        case .nothing: return ""
        }
    }

    static func delivered(to project: LampProject, session: String? = nil) { note.delivered(to: project, session: session) }
    static func compacted(_ project: LampProject) { note.compacted(project) }

    private static let note = RequestNote(file: ".lamp/wish-shown.json")
}

extension Agent.Rules {
    /// How the apps of a wish can share data: a pointer to the `wish-links` skill, which holds the ways (Lamp's `LampWish`,
    /// built into each of them, and when another fits) and what to do while one isn't made yet, since how a wish's apps
    /// talk is the agent's choice with the person, not a rule. Given to the wish's prompt (`Parts.rule`) and to each
    /// part's rules, so every app of the wish is told the same thing.
    static let wishTalk = """

    - The apps of this wish can share data and send each other messages. Each has Lamp's `LampWish` block for it, built \
    in (`LampWish.shared` in LampSupport.swift, `LampWish` in LampSupport.kt, `Lamp.wish` in lamp.js). Before writing how \
    they reach each other, open the `wish-links` skill with `read_skill`: the ways they can, when another fits better, \
    and what to do while one of them isn't made yet.
    """
}
