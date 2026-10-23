import JavaScriptCore
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
            var location = { hash: \(String(reflecting: hash)), pathname: '/', search: '', protocol: 'http:', host: '192.168.1.20:47860' };
            var history = { replaceState: function () { location.hash = ''; } };
            var sessionStorage = {
              getItem: function (k) { return store.hasOwnProperty(k) ? store[k] : null; },
              setItem: function (k, v) { store[k] = String(v); },
              removeItem: function (k) { delete store[k]; }
            };
            function WebSocket(url) { this.url = url; this.readyState = 1; sockets.push(this); }
            WebSocket.prototype.send = function (text) { sent.push(text); };
            WebSocket.prototype.close = function () {};
            function setInterval() { return 0; } function clearInterval() {} function setTimeout() { return 0; }
            """)
        if let kept { context.evaluateScript("store['lamp-controller:/'] = \(String(reflecting: kept));") }
        context.evaluateScript(TVTemplate.phoneControllerJS)
        context.evaluateScript("LampController.connect({}); sockets[0].onopen();")
        XCTAssertNil(failure)
        let hello = context.evaluateScript("sent.length ? JSON.parse(sent[0]).credential : null")
        return hello?.isNull == false ? hello?.toString() : nil
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
