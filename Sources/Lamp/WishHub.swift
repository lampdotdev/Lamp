import Foundation
import LampRelayKit

/// The apps of one wish seeing each other and talking: a room for the wish at the controllers' relay (`Relay`,
/// `ControllerRelay`), which each of its apps joins as a peer named by its part ("tv", "iphone", "mac", "android").
/// Lamp only introduces them: an app shows its own token at `/app/wish` and is told where the relay is, which peer it
/// is, a peer credential for the room and who is in it now; what the apps then say to each other goes through the
/// relay's process, never Lamp's, except for an app that can't hold a socket (an Android app, whose blocks speak HTTP),
/// which Lamp joins to the room on its behalf and feeds by long-poll (`WishProxies`). A room is opened the first time
/// an app of the wish asks, told the wish's apps again when they change, and ended when the wish is gone, has no other
/// app, or has had nobody in it and nobody asking for a while, so the relay runs only while something needs it.
///
/// The builder is told the same block in every language (`Agent.Rules.wishTalk`) and, at the end of each request, where
/// each app of the wish is: open or not, in the room or not (`WishNote`).
@MainActor
enum WishRooms {
    /// The room's key at the relay: never a TV app's game key (the app's id), so a credential says which it is for.
    static func key(for wish: LampProject) -> String { "wish:" + wish.id }

    /// Which of the wish's apps this one is, in the word the tools use for it.
    static func peer(_ app: LampProject) -> String { Parts.word(for: app.platform) }

    /// Every app the wish has, as the relay and the libraries describe one.
    static func apps(of wish: LampProject, parts: [LampProject]) -> [[String: Any]] {
        ([wish] + parts).map(describe)
    }

    static func describe(_ app: LampProject) -> [String: Any] {
        ["peer": peer(app), "kind": app.platform.rawValue, "name": Parts.name(of: app.platform)]
    }

    /// When each room was last asked for by one of its apps, by key.
    private static var asked: [String: Date] = [:]
    /// A room nobody is in, and nobody has asked for in this long, is ended.
    static let idle: TimeInterval = 15 * 60
    private static var timer: Timer?

    /// What an app of a wish is told when it asks (`/app/wish`): the relay's socket by the name it reached Lamp at, its
    /// room, which peer it is, a credential for the room, and who is in it now. An app whose wish has no other app is
    /// told it's alone, and asks again later in case one is added.
    static func answer(for project: LampProject, wish: LampProject, parts: [LampProject], host: String) async -> (Int, [String: Any]) {
        let me = describe(project)
        guard !parts.isEmpty else { return (200, ["alone": true, "renew": 300, "me": me]) }
        let key = key(for: wish)
        asked[key] = Date()
        ControllerRelay.openRoom(key, generation: ControllerCredential.generation(key), apps: apps(of: wish, parts: parts))
        startTimer()
        guard let port = await ControllerRelay.ready() else { return (503, ["error": "Lamp couldn't start the link between the wish's apps."]) }
        return (200, ["socket": "ws://\(host):\(port)/", "room": key, "peer": peer(project),
                      "credential": ControllerCredential.issue(kind: .peer, app: key, peer: peer(project)),
                      "renew": 60, "peers": presence(of: wish), "apps": apps(of: wish, parts: parts), "me": me])
    }

    /// Who is in the wish's room now, as the relay last said.
    static func presence(of wish: LampProject) -> [[String: Any]] { ControllerRelay.presence[key(for: wish)] ?? [] }

    /// Kept in step with the list of apps: a room whose wish is gone, or alone now, ends; one whose apps changed is
    /// told them again.
    static func sync(_ projects: [LampProject]) {
        let wishes = Dictionary(projects.filter { !$0.isPart }.map { (key(for: $0), $0) }, uniquingKeysWith: { a, _ in a })
        for key in ControllerRelay.roomKeys {
            guard let wish = wishes[key] else { end(key); continue }
            let parts = projects.filter { $0.partOf == wish.id }
            guard !parts.isEmpty else { end(key); continue }
            ControllerRelay.openRoom(key, generation: ControllerCredential.generation(key), apps: apps(of: wish, parts: parts))
        }
        expire()
    }

    /// The room is over: its members are let go, its credentials are worthless, and the apps Lamp joined to it are dropped.
    static func end(_ key: String) {
        asked[key] = nil
        ControllerCredential.forget(key)
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

/// An app that can't hold a WebSocket (an Android app: its blocks speak HTTP on a socket) in its wish's room: Lamp
/// opens the room's socket for it, as it, and the app polls Lamp for what came (`/app/wish/poll`, answered as soon as
/// there is something, or after a wait) and posts what it sends (`/app/wish/send`). The link is the app's own: Lamp
/// keeps what arrived only until the next poll, and lets the socket go when the app has stopped polling.
@MainActor
enum WishProxies {
    final class Proxy {
        let app: String
        let room: String
        var device: String
        var task: URLSessionWebSocketTask?
        var opening = false
        var events: [[String: Any]] = []
        var waiter: CheckedContinuation<[[String: Any]], Never>?
        var lastPoll = Date()
        var beat: Timer?
        init(app: String, room: String, device: String) {
            self.app = app
            self.room = room
            self.device = device
        }
    }

    /// Events kept for an app between polls, past which the oldest go: a poll takes them all.
    static let backlog = 256
    /// A poll waits this long for something to come before answering with nothing.
    static let wait: TimeInterval = 25
    /// An app that hasn't polled for this long has stopped: its socket is let go.
    static let idle: TimeInterval = 90

    private static var proxies: [String: Proxy] = [:]

    static func lastAsked(room: String) -> Date? { proxies.values.filter { $0.room == room }.map(\.lastPoll).max() }

    /// What has come for the app since its last poll (`events`: the room's own messages, `welcome`, `joined`, `left`,
    /// `message`, `undelivered`, and `closed` when the socket went), waiting a while for the first. The first poll opens
    /// the app's place in the room; one after the socket closed opens it again, so the app sees a fresh welcome.
    static func poll(_ project: LampProject, wish: LampProject, parts: [LampProject], device: String) async -> (Int, [String: Any]) {
        let key = WishRooms.key(for: wish)
        let proxy = proxies[project.id] ?? Proxy(app: project.id, room: key, device: device)
        proxies[project.id] = proxy
        proxy.lastPoll = Date()
        if !device.isEmpty { proxy.device = device }
        if proxy.task == nil, !proxy.opening {
            proxy.opening = true
            let (status, answer) = await WishRooms.answer(for: project, wish: wish, parts: parts, host: "127.0.0.1")
            proxy.opening = false
            guard status == 200 else { proxies[project.id] = nil; return (status, answer) }
            if answer["alone"] as? Bool == true { proxies[project.id] = nil; return (200, ["alone": true, "renew": 300, "events": []]) }
            guard let socket = (answer["socket"] as? String).flatMap(URL.init(string:)), let credential = answer["credential"] as? String else {
                proxies[project.id] = nil
                return (503, ["error": "Lamp couldn't say where the wish's apps meet."])
            }
            open(proxy, socket: socket, credential: credential)
        }
        if !proxy.events.isEmpty { return (200, ["events": take(proxy)]) }
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

    /// Sends what the app said to one peer or to all, as the app would on its own socket.
    static func send(_ project: LampProject, body: [String: Any]) async -> (Int, [String: Any]) {
        guard let proxy = proxies[project.id], let task = proxy.task else { return (409, ["error": "The app isn't in the wish's room yet: poll first."]) }
        guard let data = body["data"] else { return (400, ["error": "Nothing to send."]) }
        var frame: [String: Any] = ["t": "send", "data": data]
        if let to = body["to"] as? String { frame["to"] = to }
        guard JSONSerialization.isValidJSONObject(frame), let text = try? JSONSerialization.data(withJSONObject: frame),
              text.count <= ControllerWire.message else {
            return (413, ["error": "A message between the wish's apps is at most \(ControllerWire.message) bytes as JSON."])
        }
        proxy.lastPoll = Date()
        do {
            try await task.send(.string(String(decoding: text, as: UTF8.self)))
        } catch {
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
        if proxy.events.count > backlog { proxy.events.removeFirst(proxy.events.count - backlog) }
        if let waiter = proxy.waiter {
            proxy.waiter = nil
            waiter.resume(returning: take(proxy))
        }
    }

    private static func open(_ proxy: Proxy, socket: URL, credential: String) {
        let task = URLSession.shared.webSocketTask(with: socket)
        task.maximumMessageSize = ControllerWire.message + 1024
        proxy.task = task
        task.resume()
        let hello: [String: Any] = ["t": "hello", "app": proxy.room, "credential": credential, "device": proxy.device]
        if let data = try? JSONSerialization.data(withJSONObject: hello) {
            task.send(.string(String(decoding: data, as: UTF8.self))) { _ in }
        }
        receive(proxy, on: task)
        proxy.beat?.invalidate()
        proxy.beat = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard proxy.task === task else { return }
                if Date().timeIntervalSince(proxy.lastPoll) > idle {
                    close(proxy)
                    proxies[proxy.app] = nil
                    return
                }
                task.send(.string(#"{"t":"beat"}"#)) { _ in }
            }
        }
    }

    private static func receive(_ proxy: Proxy, on task: URLSessionWebSocketTask) {
        task.receive { result in
            Task { @MainActor in
                guard proxy.task === task else { return }
                switch result {
                case .success(.string(let text)):
                    if let event = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any], event["t"] as? String != "beat" {
                        push(proxy, event)
                    }
                    receive(proxy, on: task)
                case .success:
                    receive(proxy, on: task)
                case .failure:
                    let code = task.closeCode.rawValue
                    proxy.task = nil
                    proxy.beat?.invalidate()
                    proxy.beat = nil
                    push(proxy, ["t": "closed", "code": code])
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
        let parts = store.parts(of: wish)
        guard !parts.isEmpty else { return "" }
        let present = Dictionary(WishRooms.presence(of: wish).compactMap { member in (member["peer"] as? String).map { ($0, member) } },
                                 uniquingKeysWith: { a, _ in a })
        return ([wish] + parts).map { app in
            let name = Parts.name(of: app.platform)
            var line = "\(name.prefix(1).uppercased() + name.dropFirst()) (peer \"\(WishRooms.peer(app))\"): \(store.isOpen(app) ? "open" : "not open")"
            if let member = present[WishRooms.peer(app)] {
                let since = (member["since"] as? Int).map { Date(timeIntervalSince1970: Double($0) / 1000).formatted(date: .omitted, time: .shortened) } ?? "?"
                line += ", in the wish's room as \"\(member["device"] as? String ?? "")\" since \(since)"
            } else {
                line += ", not in the room"
            }
            return line
        }.joined(separator: "; ") + "."
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
    /// How the apps of a wish see each other and talk: one block, the same in every language. Given to the wish's prompt
    /// (`Parts.rule`) and to each part's rules, so every app of the wish is told the same thing.
    static let wishTalk = """

    - The apps of this wish see each other and talk through Lamp, with the same building block in each language: \
    `LampWish.shared` in LampSupport.swift, `LampWish` in LampSupport.kt, `Lamp.wish` in lamp.js. Each app of the wish is \
    a peer named by its part's word ("tv", "iphone", "mac", "android"). `peers` lists the wish's other apps that are open \
    now (observable: @Published, a StateFlow, onPeers), `send(data, to: "tv")` sends JSON of 16 KB at most to one of \
    them and `send(data)` to all, false (with why in the app's log) when it wasn't sent, and `onMessage { from, data in … }` \
    hears what they send. Lamp introduces the apps over the home Wi‑Fi, with nothing to pair, host or set up: never build \
    your own server, sockets, polling or pairing between them, and never put the app's token or Lamp's addresses in the \
    code. Start it as each app opens, show plainly when an app it needs isn't open ("Open it on the TV"), and keep every \
    control usable meanwhile. Read the block's comment before using it.
    """
}
