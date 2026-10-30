import CryptoKit
import Foundation

/// One game's phones as controllers, run by the game itself on the Mac, an iPhone or an iPad: its phone page, served from the copy Lamp put
/// in the game's bundle (`PhonePageServer`), and the relay its phones and its page meet at (`Relay`), both in the
/// game's own process, each on a port the system gives it free. The game's page asks for its session (`/app/controller`,
/// which the app around the page answers from here) as `Lamp.controllers` starts and every few seconds after; the first
/// ask opens both, and `stop` (the page stopping its controllers, or the game quitting) closes them. Lamp has no part in
/// it, so a game's phones go on playing, and new ones join, whether Lamp is open or not.
///
/// The credentials are signed with a key made for each session and kept only in this object's memory: never in the
/// page's files, its JavaScript, the link a phone opens or the bundle. A session that stops and starts again has a new
/// key, so nothing handed out before gets in.
///
/// A page held to its sites (`NetworkPolicy`) reaches the relay only at an address named in the rules its document came
/// with, which are fixed as it loads, so that port comes first (`holdingPagePort`, `pageSites`): held on this device
/// alone, from before the document is served until the game quits, through every session and the stops between them,
/// while phones join at a port of their own that opens and closes with the session as anyone else's does. Letting the
/// port go would leave a live page allowed to reach whatever took it next, so a port that's lost anyway is asked for
/// back, and when it can't be had the pages are retired (`onPagePortMoved`). It's never saved and never comes from the
/// page.
///
/// Lamp builds this file into its own relay (LampRelayKit), where the tests reach it, and into every game on the Mac,
/// the iPhone and the iPad (`GameKit.controllerKit`), where LampPage.swift runs it.
public final class ControllerRuntime: @unchecked Sendable {
    public let app: String
    /// The page served: the bundle's, or the newer one Lamp gave the game as it's played (`use`).
    private var root: URL
    private var version: String?
    private let queue = DispatchQueue(label: "dev.lamp.controllers")
    private var key: SymmetricKey?
    private var relay: Relay?
    /// The port the game's page reaches the relay at. Phones' is `sharedRelayPort`, the same one unless it's held.
    private var relayPort: UInt16?
    private var site: PhonePageServer?
    private let holdingPagePort: Bool
    /// The port the pages' rules name, kept through a relay lost so that port can be asked for again.
    private var heldPort: UInt16?
    /// The device's names and addresses, and the host a phone's link carries (nil: on no network a phone can share).
    /// Changed by tests.
    public var hosts: @Sendable () -> Set<String> = { ControllerAddresses.names() }
    public var linkHost: @Sendable () -> String? = { ControllerAddresses.linkHost() }
    /// The port the pages' rules should name has changed: every page and worker the game has must go, on the main thread,
    /// and come back under `pageSites`. Never before the relay's port is settled, so a page can't be served the old one.
    public var onPagePortMoved: @Sendable () -> Void = {}

    /// How often the page asks again, which tells the relay where the page is now (the device's address moves with the network).
    public static let renew = 15

    /// `root`: the game's phone page, as Lamp put it in the bundle. `holdingPagePort`: its page is held to its sites.
    public init(app: String, page root: URL, holdingPagePort: Bool = false) {
        self.app = app
        self.root = root
        self.holdingPagePort = holdingPagePort
    }

    /// Serves a newer page, as Lamp handed it to the game (`LampPageLive`), under the session that's open: every player
    /// keeps their seat, and each phone's page finds the new version and opens again from it.
    public func use(page root: URL, version: String, _ done: @escaping @Sendable () -> Void = {}) {
        queue.async {
            self.root = root
            self.version = version
            self.site?.use(page: root, version: version)
            done()
        }
    }

    /// The same, waiting for it: for tests.
    public func useNow(page root: URL, version: String) { queue.sync { self.root = root; self.version = version; site?.use(page: root, version: version) } }

    /// The game's session, opened if it isn't: what `/app/controller` answers, with its status. On the runtime's own
    /// queue, never the caller's, since opening waits for the system to give each listener its port.
    public func start(_ done: @escaping @Sendable (_ status: Int, _ answer: [String: Any]) -> Void) {
        queue.async { let (status, answer) = self.open(); done(status, answer) }
    }

    /// The same, waiting for it: for tests.
    public func startNow() -> (status: Int, answer: [String: Any]) { queue.sync { open() } }

    /// Closes the page and the relay: every phone and the page's own socket are let go, and the key is forgotten. On the
    /// same queue as `start`, so a stop and the start after it (a game's next round) happen in the order they were asked.
    public func stop(_ done: @escaping @Sendable () -> Void) {
        queue.async { self.close(); done() }
    }

    /// The same, waiting for it: for tests.
    public func stop() { queue.sync { close() } }

    public var pagePort: UInt16? { queue.sync { site?.port } }
    public var isRunning: Bool { queue.sync { key != nil || site != nil } }

    /// The sites a page held to its rules may connect to, for the document being served: the relay at its held port,
    /// taken now if it isn't yet, or nothing for a game with no phone page. Asked for every file, so the usual answer
    /// doesn't wait; the first waits for the system to give the port, which a document must before it's served.
    public func pageSites() -> [String] {
        guard holdingPagePort else { return [] }
        let port = portLock.withLock { sharedHeldPort } ?? queue.sync { hold(forDocument: true) }
        return port.map { [Self.socket($0)] } ?? []
    }

    private func open() -> (Int, [String: Any]) {
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("index.html").path) else {
            return (409, ["error": "The game has no phone page yet: put one in Phone/index.html."])
        }
        // Never a loopback link: a phone opening it would reach itself. The page's next ask tries again, once the device
        // is back on a network.
        guard let link = linkHost() else {
            close()
            return (503, ["error": "This device isn't on a Wi‑Fi network phones can join. Join one, and phones can play again."])
        }
        let key = self.key ?? SymmetricKey(size: .bits256)
        self.key = key
        guard let socket = openRelay(key) else {
            close()
            return (503, ["error": "The link for phones couldn't open on this Mac."])
        }
        if site == nil { openSite() }
        guard let site, let pagePort = site.port else {
            close()
            return (503, ["error": "The phone page couldn't open on this Mac."])
        }
        relay?.configure(app: app, Relay.Session(generation: 0, pagePort: pagePort, page: Self.address(link, pagePort),
                                                 hosts: Array(hosts()).sorted()))
        let credential = ControllerToken.issue(kind: .host, app: app, generation: 0, key: key)
        return (200, ["links": [["kind": "relay", "socket": Self.socket(socket) + "/", "app": app, "credential": credential]],
                      "renew": Self.renew])
    }

    /// Where a game's page reaches its relay.
    private static func socket(_ port: UInt16) -> String { "ws://127.0.0.1:\(port)" }

    /// A page's address at `host`, an IPv6 one in brackets.
    static func address(_ host: String, _ port: UInt16) -> String {
        "http://\(host.contains(":") ? "[\(host)]" : host):\(port)/"
    }

    private func close() {
        if holdingPagePort {
            // The session goes and its key with it, and only the port stays: nothing gets in until the next one.
            relay?.end(app: app)
            relay?.closeToPhones()
        } else {
            relay?.stop()
            relay = nil
            relayPort = nil
        }
        share(nil)
        site?.stop()
        site = nil
        key = nil
    }

    /// The relay, on a port the system gives it, started when the session first needs it, and where the page reaches it.
    private func openRelay(_ key: SymmetricKey) -> UInt16? {
        guard holdingPagePort else {
            if let relayPort, relay != nil { return relayPort }
            guard let given = bind(key, port: 0, thisDeviceOnly: false) else { return nil }
            share(given)
            return given
        }
        // A port that has only now come is in no page's rules: the pages go (`hold`), and it's theirs when they're back.
        let promised = heldPort
        guard let port = hold(forDocument: false), port == promised, let relay else { return nil }
        if currentRelayPort == nil {
            relay.use(key: key)
            guard let phones = given({ relay.openToPhones(ready: $0) }) else { return nil }
            share(phones)
        }
        return port
    }

    /// The port the pages' rules name, held from the first document on. One a page already has is kept; any other change
    /// retires the pages, but a document being served now takes the port it's given.
    private func hold(forDocument: Bool) -> UInt16? {
        if let relayPort, relay != nil { return relayPort }
        let promised = heldPort
        let hasPage = FileManager.default.fileExists(atPath: root.appendingPathComponent("index.html").path)
        // Its key opens nothing: there's no session until `open`, which gives it the session's.
        heldPort = hasPage ? bind(SymmetricKey(size: .bits256), port: promised ?? 0, thisDeviceOnly: true) : nil
        let port = heldPort
        portLock.withLock { sharedHeldPort = port }
        if port != promised, !(forDocument && promised == nil) { onPagePortMoved() }
        return port
    }

    private func bind(_ key: SymmetricKey, port: UInt16, thisDeviceOnly: Bool) -> UInt16? {
        let started = Relay(key: key)
        started.onStopped = { [weak self, weak started] in
            self?.queue.async {
                // The network went away under it: the page's next ask opens the session afresh.
                guard let self, self.relay === started else { return }
                self.lostRelay()
            }
        }
        started.onPhonesStopped = { [weak self, weak started] in
            self?.queue.async {
                guard let self, self.relay === started else { return }
                self.close()
            }
        }
        guard let port = given({ started.start(port: port, thisDeviceOnly: thisDeviceOnly, ready: $0) }) else { started.stop(); return nil }
        relay = started
        relayPort = port
        return port
    }

    private func lostRelay() {
        close()
        guard holdingPagePort else { return }
        relay?.stop()
        relay = nil
        relayPort = nil
        portLock.withLock { sharedHeldPort = nil }
        _ = hold(forDocument: false)
    }

    /// The relay stops as if the network had gone, with another service moving in before it's asked for again: for tests.
    func loseRelay(_ meanwhile: () -> Void) {
        queue.sync {
            relay?.stop()
            meanwhile()
            lostRelay()
        }
    }

    /// The port a listener opening now says it has, waited for.
    private func given(_ open: (@escaping @Sendable (UInt16?) -> Void) -> Void) -> UInt16? {
        let ready = DispatchSemaphore(value: 0)
        let port = Said<UInt16>()
        open { given in
            port.value = given
            ready.signal()
        }
        return ready.wait(timeout: .now() + 5) == .success ? port.value : nil
    }

    private func openSite() {
        if version == nil { version = (try? ControllerSnapshot.read(root))?.version }
        let site = PhonePageServer(port: 0, root: root, version: version, app: app, hosts: hosts, relayPort: { [weak self] in self?.currentRelayPort })
        let ready = DispatchSemaphore(value: 0)
        let listening = Said<Bool>()
        site.start(ready: { ok in listening.value = ok; ready.signal() }, onFailure: { [weak self, weak site] in
            self?.queue.async {
                // It stopped listening (the network went away under it): the page's next ask opens it again.
                guard let self, let site, self.site === site else { return }
                self.site = nil
            }
        })
        guard ready.wait(timeout: .now() + 5) == .success, listening.value == true else { site.stop(); return }
        self.site = site
    }

    /// Read by the page server from its own queue, so it never waits on this one.
    private let portLock = NSLock()
    private var sharedRelayPort: UInt16?
    private var sharedHeldPort: UInt16?
    private var currentRelayPort: UInt16? { portLock.withLock { sharedRelayPort } }
    private func share(_ port: UInt16?) { portLock.withLock { sharedRelayPort = port } }
}

/// What a callback on another queue says, read after a semaphore says it has.
private final class Said<Value>: @unchecked Sendable {
    var value: Value?
}
