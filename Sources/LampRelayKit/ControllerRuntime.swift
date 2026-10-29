import CryptoKit
import Foundation
import SystemConfiguration

/// One game's phones as controllers, run by the game itself on the Mac: its phone page, served from the copy Lamp put
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
/// Lamp builds this file into its own relay (LampRelayKit), where the tests reach it, and into every game on the Mac
/// (`GameKit.controllerKit`), where LampPage.swift runs it.
public final class ControllerRuntime: @unchecked Sendable {
    public let app: String
    private let root: URL
    private let queue = DispatchQueue(label: "dev.lamp.controllers")
    private var key: SymmetricKey?
    private var relay: Relay?
    private var relayPort: UInt16?
    private var site: PhonePageServer?
    /// This Mac's names and addresses, and the address a phone's link carries. Changed by tests.
    public var hosts: @Sendable () -> Set<String> = ControllerRuntime.macNames
    public var linkHost: @Sendable () -> String = { PhonePageServer.localAddresses().first ?? ControllerRuntime.localHostName() ?? "127.0.0.1" }

    /// How often the page asks again, which tells the relay where the page is now (the Mac's address moves with the network).
    public static let renew = 15

    /// `root`: the game's phone page, as Lamp put it in the bundle.
    public init(app: String, page root: URL) {
        self.app = app
        self.root = root
    }

    /// The game's session, opened if it isn't: what `/app/controller` answers, with its status. On the runtime's own
    /// queue, never the caller's, since opening waits for the system to give each listener its port.
    public func start(_ done: @escaping @Sendable (_ status: Int, _ answer: [String: Any]) -> Void) {
        queue.async { let (status, answer) = self.open(); done(status, answer) }
    }

    /// The same, waiting for it: for tests.
    public func startNow() -> (status: Int, answer: [String: Any]) { queue.sync { open() } }

    /// Closes the page and the relay: every phone and the page's own socket are let go, and the key is forgotten.
    public func stop() { queue.sync { close() } }

    public var pagePort: UInt16? { queue.sync { site?.port } }
    public var isRunning: Bool { queue.sync { relay != nil || site != nil } }

    private func open() -> (Int, [String: Any]) {
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("index.html").path) else {
            return (409, ["error": "The game has no phone page yet: put one in Phone/index.html."])
        }
        let key = self.key ?? SymmetricKey(size: .bits256)
        self.key = key
        guard let relayPort = openRelay(key) else {
            close()
            return (503, ["error": "The link for phones couldn't open on this Mac."])
        }
        if site == nil { openSite() }
        guard let site, let pagePort = site.port else {
            close()
            return (503, ["error": "The phone page couldn't open on this Mac."])
        }
        relay?.configure(app: app, Relay.Session(generation: 0, pagePort: pagePort, page: "http://\(linkHost()):\(pagePort)/",
                                                 hosts: Array(hosts()).sorted()))
        let credential = ControllerToken.issue(kind: .host, app: app, generation: 0, key: key)
        return (200, ["links": [["kind": "relay", "socket": "ws://127.0.0.1:\(relayPort)/", "app": app, "credential": credential]],
                      "renew": Self.renew])
    }

    private func close() {
        relay?.stop()
        relay = nil
        relayPort = nil
        share(nil)
        site?.stop()
        site = nil
        key = nil
    }

    /// The relay, on a port the system gives it, started when the session first needs it.
    private func openRelay(_ key: SymmetricKey) -> UInt16? {
        if let relayPort, relay != nil { return relayPort }
        let started = Relay(key: key)
        let ready = DispatchSemaphore(value: 0)
        let port = Said<UInt16>()
        started.onStopped = { [weak self, weak started] in
            self?.queue.async {
                // The network went away under it: the page's next ask opens the session afresh.
                guard let self, self.relay === started else { return }
                self.close()
            }
        }
        started.start(port: 0) { given in
            port.value = given
            ready.signal()
        }
        guard ready.wait(timeout: .now() + 5) == .success, let given = port.value else { started.stop(); return nil }
        relay = started
        relayPort = given
        share(given)
        return given
    }

    private func openSite() {
        let site = PhonePageServer(port: 0, root: root, app: app, hosts: hosts, relayPort: { [weak self] in self?.currentRelayPort })
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
    private var currentRelayPort: UInt16? { portLock.withLock { sharedRelayPort } }
    private func share(_ port: UInt16?) { portLock.withLock { sharedRelayPort = port } }

    // MARK: This Mac

    /// This Mac's Bonjour name, as phones may reach it ("name.local").
    public static func localHostName() -> String? {
        guard let name = SCDynamicStoreCopyLocalHostName(nil) as String?, !name.isEmpty else { return nil }
        return name + ".local"
    }

    /// The names and addresses a page is served as: this Mac's on its networks, and the loopback ones.
    public static func macNames() -> Set<String> {
        var names: Set<String> = ["127.0.0.1", "localhost", "::1"]
        if let name = localHostName() { names.insert(name.lowercased()) }
        for address in PhonePageServer.localAddresses() { names.insert(address.lowercased()) }
        return names
    }
}

/// What a callback on another queue says, read after a semaphore says it has.
private final class Said<Value>: @unchecked Sendable {
    var value: Value?
}
