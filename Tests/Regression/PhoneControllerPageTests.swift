import JavaScriptCore
import Network
import XCTest
@testable import Lamp

/// The phone's side of a controller: a link the person has just opened is the one used, and each app's phone page is an
/// origin of its own, so what one app's page keeps is out of reach of another's.
final class PhoneControllerPageTests: XCTestCase {
    /// Lamp's phone library in a stand-in browser: a page opened at `hash`, with `kept` already in its session's storage.
    private func firstHello(hash: String, kept: String?) throws -> String? {
        let context = try XCTUnwrap(JSContext())
        var failure: String?
        context.exceptionHandler = { _, value in failure = value?.toString() }
        context.evaluateScript("""
            var window = this, sent = [], sockets = [], store = {};
            var location = { hash: \(String(reflecting: hash)), pathname: '/', search: '', protocol: 'http:', host: '192.168.1.20:47860', hostname: '192.168.1.20' };
            var history = { replaceState: function () { location.hash = ''; } };
            var sessionStorage = {
              getItem: function (k) { return store.hasOwnProperty(k) ? store[k] : null; },
              setItem: function (k, v) { store[k] = String(v); },
              removeItem: function (k) { delete store[k]; }
            };
            function WebSocket(url) { this.url = url; this.readyState = 1; sockets.push(this); }
            WebSocket.prototype.send = function (text) { sent.push(text); };
            WebSocket.prototype.close = function () {};
            function fetch() { return Promise.resolve({ ok: true, json: function () { return { port: 47900, app: 'padgame' }; } }); }
            function setInterval() { return 0; } function clearInterval() {} function setTimeout() { return 0; }
            """)
        if let kept { context.evaluateScript("store['lamp-controller:/'] = \(String(reflecting: kept));") }
        context.evaluateScript(TVTemplate.phoneControllerJS)
        context.evaluateScript("LampController.connect({});")
        context.evaluateScript("sockets[0].onopen();")
        XCTAssertNil(failure)
        let hello = context.evaluateScript("sent.length ? JSON.parse(sent[0]).credential : null")
        return hello?.isNull == false ? hello?.toString() : nil
    }

    /// How many times the page reloads when the browser refuses its socket (a SecurityError, as WebKit throws for a
    /// policy's refusal and for a blocked port alike), with lamp-relay.json saying the page has rules (`held`) or not.
    private func reloads(held: Bool) throws -> Int {
        let context = try XCTUnwrap(JSContext())
        context.exceptionHandler = { _, _ in }
        context.evaluateScript("""
            var window = this, reloads = 0, store = {};
            var location = { hash: '#join', pathname: '/', search: '', protocol: 'http:', host: '192.168.1.20:47860', hostname: '192.168.1.20',
                             reload: function () { reloads++; } };
            var history = { replaceState: function () { location.hash = ''; } };
            var sessionStorage = {
              getItem: function (k) { return store.hasOwnProperty(k) ? store[k] : null; },
              setItem: function (k, v) { store[k] = String(v); },
              removeItem: function (k) { delete store[k]; }
            };
            function WebSocket(url) { var e = new Error('refused'); e.name = 'SecurityError'; throw e; }
            var relay = { port: 47900, app: 'padgame' }; \(held ? "relay.policy = true;" : "")
            function fetch() { return Promise.resolve({ ok: true, json: function () { return relay; } }); }
            function setInterval() { return 0; } function clearInterval() {} function setTimeout() { return 0; }
            """)
        context.evaluateScript(TVTemplate.phoneControllerJS)
        context.evaluateScript("LampController.connect({});")
        return Int(context.evaluateScript("reloads")?.toInt32() ?? -1)
    }

    /// Only a page Lamp gave rules to (a shared app's) takes a refused socket for a relay that moved and loads again; an
    /// app's own page never reloads for one, as before these rules.
    func testOnlyAHeldPageReloadsForARefusedSocket() throws {
        XCTAssertEqual(try reloads(held: true), 1)
        XCTAssertEqual(try reloads(held: false), 0)
    }

    func testALinkJustOpenedWinsOverACredentialKeptFromBefore() throws {
        XCTAssertEqual(try firstHello(hash: "#fresh-join", kept: "stale-resume"), "fresh-join")
    }

    func testAReloadedPageComesBackWithWhatItKept() throws {
        XCTAssertEqual(try firstHello(hash: "", kept: "kept-resume"), "kept-resume")
    }

    @MainActor
    func testEachAppsPhonePageIsAnOriginOfItsOwn() throws {
        let one = LampProject(id: "padgame", name: "Pad Game", exe: "PadGame", dir: URL(fileURLWithPath: "/tmp/padgame"))
        let two = LampProject(id: "quizgame", name: "Quiz Game", exe: "QuizGame", dir: URL(fileURLWithPath: "/tmp/quizgame"))
        func origin(_ project: LampProject) throws -> String {
            let url = try XCTUnwrap(URL(string: TVs.phonePage(for: project)))
            return "\(url.scheme ?? "")://\(url.host ?? ""):\(url.port ?? 0)"
        }
        XCTAssertNotEqual(try origin(one), try origin(two))
        XCTAssertEqual(try origin(one), try origin(one), "an app keeps its address")
        for project in [one, two] {
            let port = try XCTUnwrap(URL(string: TVs.phonePage(for: project))?.port)
            XCTAssertTrue(Edition.phonePagePorts.contains(UInt16(port)))
        }
    }

    @MainActor
    func testPortsOfAppsWhosePagesArentServedGoBackToThePool() {
        PhoneSites.forgetAll()
        defer { PhoneSites.forgetAll() }
        // As many apps as the range has ports were given one (each staged once), and none is served now.
        for index in 0..<Edition.phonePagePorts.count { _ = PhoneSites.port(for: "closed\(index)") }
        XCTAssertNotNil(PhoneSites.port(for: "one-more"), "a port no open page holds is given to the app that needs one")
    }

    @MainActor
    func testASiteWhosePortWasTakenOpensOnAnotherAndIsOpenOnlyOnceListening() async throws {
        PhoneSites.forgetAll()
        defer { PhoneSites.forgetAll() }
        let kept = try XCTUnwrap(PhoneSites.port(for: "busy"))
        // Another program has taken the port the app was given, after it was given it.
        let holder = try XCTUnwrap(Self.listen(on: kept))
        defer { close(holder) }
        let opened = await PhoneSites.open("busy", wanted: { true })
        XCTAssertTrue(opened)
        XCTAssertTrue(PhoneSites.isOpen("busy"))
        let now = try XCTUnwrap(PhoneSites.port(for: "busy"))
        XCTAssertNotEqual(now, kept, "the site is on a port it could take")
        XCTAssertFalse(PhoneSites.isFree(now), "and it's listening there")
    }

    @MainActor
    func testAPageIsOnlyEverGivenAPortItsSiteHolds() async throws {
        PhoneSites.forgetAll()
        defer { PhoneSites.forgetAll() }
        let kept = try XCTUnwrap(PhoneSites.port(for: "moved"))
        let holder = try XCTUnwrap(Self.listen(on: kept))
        defer { close(holder) }
        let ready = await PhoneSites.ready("moved", wanted: { true })
        let given = try XCTUnwrap(ready)
        XCTAssertNotEqual(given, kept, "the address names the port the site took, not the one it lost")
        XCTAssertTrue(PhoneSites.isOpen("moved"))
    }

    /// A second screen draws its QR code from `Lamp.phonePage()`: when the site has moved since the copy was staged, the
    /// page is given the address it's at now, by Lamp's answer as it opens and by the preview at once.
    func testATVPageShowsThePhonePageWhereItsSiteIsNow() throws {
        let context = try XCTUnwrap(JSContext())
        var failure: String?
        context.exceptionHandler = { _, value in failure = value?.toString() }
        context.evaluateScript("""
            var window = this, later = [], asked = [], drawn = [];
            var document = { addEventListener: function () {}, activeElement: null, body: {} };
            function setTimeout(fn) { later.push(fn); return 0; } function setInterval() { return 0; }
            var LampAI = { _post: function (path) { asked.push(path); return Promise.resolve({ url: 'http://192.168.1.20:47861/' }); } };
            """)
        let staged = TVTemplate.remoteJS.replacingOccurrences(of: TVTemplate.phoneMarker, with: "/*LAMP_PHONE*/\"http://192.168.1.20:47860/\"")
        context.evaluateScript(staged)
        context.evaluateScript("Lamp.onPhonePage(function () { drawn.push(Lamp.phonePage('room')); }); while (later.length) later.shift()();")
        XCTAssertNil(failure)
        XCTAssertEqual(context.evaluateScript("asked.join()")?.toString(), "/app/phone-page", "the page asks where its phone page is")
        XCTAssertEqual(context.evaluateScript("drawn.join(' ')")?.toString(),
                       "http://192.168.1.20:47860/#room http://192.168.1.20:47861/#room", "and draws its code again at the new address")
        context.evaluateScript("window.__lampPhonePage('http://192.168.1.20:47862/');")
        XCTAssertEqual(context.evaluateScript("Lamp.phonePage()")?.toString(), "http://192.168.1.20:47862/", "the preview tells it at once")
        XCTAssertEqual(context.evaluateScript("drawn.length")?.toInt32(), 3)
    }

    /// A site's listener holds its handlers, and they once held it and the site back: every failed try and closed site
    /// stayed in memory. Both go once the listener is done.
    @MainActor func testAFailedOrClosedSiteIsLetGo() async throws {
        PhoneSites.forgetAll()
        defer { PhoneSites.forgetAll() }
        let taken = try XCTUnwrap(PhoneSites.port(for: "taken"))
        let holder = try XCTUnwrap(Self.listen(on: taken))
        defer { close(holder) }
        let free = try XCTUnwrap(PhoneSites.port(for: "free", avoiding: [taken]))

        for (port, opens) in [(taken, false), (free, true)] {
            weak var site: Gateway?
            weak var listener: NWListener?
            do {
                let gateway = Gateway(site: port, pages: { _ in Gateway.Page(status: 404) })
                site = gateway
                // The callback holds the site, as the one PhoneSites gives it may.
                let started = await gateway.startSite(onFailure: { _ = gateway })
                XCTAssertEqual(started, opens)
                listener = Mirror(reflecting: gateway).children.first { $0.label == "listener" }?.value as? NWListener
                XCTAssertNotNil(listener)
                gateway.stop()
            }
            for _ in 0..<40 where site != nil || listener != nil { try await Task.sleep(for: .milliseconds(50)) }
            XCTAssertNil(listener, "the listener at \(port) is released once it's done")
            XCTAssertNil(site, "and so is its site")
        }
    }

    /// A pad closed while its reconnect waited (the page replaced it after its link dropped) stays closed: the
    /// waiting reconnect opens no socket to rejoin beside its replacement.
    func testAClosedPadDoesntReconnect() throws {
        let context = try XCTUnwrap(JSContext())
        var failure: String?
        context.exceptionHandler = { _, value in failure = value?.toString() }
        context.evaluateScript("""
            var window = this, sockets = [], later = [], store = {};
            var location = { hash: '#join', pathname: '/', search: '', protocol: 'http:', host: '192.168.1.20:47860', hostname: '192.168.1.20' };
            var history = { replaceState: function () { location.hash = ''; } };
            var sessionStorage = {
              getItem: function (k) { return store.hasOwnProperty(k) ? store[k] : null; },
              setItem: function (k, v) { store[k] = String(v); }, removeItem: function (k) { delete store[k]; }
            };
            function WebSocket(url) { this.readyState = 1; sockets.push(this); }
            WebSocket.prototype.send = function () {};
            WebSocket.prototype.close = function () {};
            function fetch() { return Promise.resolve({ ok: true, json: function () { return { port: 47900, app: 'padgame' }; } }); }
            function setTimeout(fn) { later.push(fn); return later.length; }
            function clearTimeout(id) { if (id) later[id - 1] = null; }
            function setInterval() { return 0; } function clearInterval() {}
            """)
        context.evaluateScript(TVTemplate.phoneControllerJS)
        context.evaluateScript("var pad = LampController.connect({});")
        context.evaluateScript("""
            sockets[0].onclose({ code: 1006 });   // the Wi-Fi dropped: a reconnect waits
            pad.close();
            later.forEach(function (fn) { if (fn) fn(); });
            """)
        XCTAssertNil(failure)
        XCTAssertEqual(context.evaluateScript("sockets.length")?.toInt32(), 1, "no socket opens after the pad is closed")
    }

    /// An app whose phone page stops being served (deleted, or set to open nowhere) ends its game: its credentials stop
    /// working, and the relay lets its phones go.
    @MainActor func testAGameEndsWhenItsPhonePageIsNoLongerServed() {
        PhoneSites.forgetAll()
        defer { PhoneSites.forgetAll() }
        let project = LampProject(id: "unserved", name: "Unserved", exe: "Unserved", dir: URL(fileURLWithPath: "/tmp/unserved"))
        let host = PhoneControllers.shared.hostCredential(for: project, preview: false)
        XCTAssertNotNil(ControllerCredential.check(host, kinds: [.host], app: project.id))
        PhoneSites.sync([])
        XCTAssertNil(ControllerCredential.check(host, kinds: [.host], app: project.id), "the host's credential is worthless once the page isn't served")
    }

    /// A socket listening on every address at the port, as another program's would.
    private static func listen(on port: UInt16) -> Int32? {
        let fd = socket(AF_INET6, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var no: Int32 = 0
        setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &no, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in6()
        address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        address.sin6_family = sa_family_t(AF_INET6)
        address.sin6_port = port.bigEndian
        address.sin6_addr = in6addr_any
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) == 0 }
        }
        guard bound, Darwin.listen(fd, 1) == 0 else { close(fd); return nil }
        return fd
    }
}
