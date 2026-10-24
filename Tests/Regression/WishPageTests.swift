import JavaScriptCore
import XCTest
@testable import Lamp

/// `Lamp.wish` in lamp.js, the TV page's half of LampWish: it asks Lamp for its room, joins it with the credential it's
/// given, keeps the list of the wish's other apps as they come and go, delivers their messages with who sent them, and
/// refuses a message that can't go rather than losing it quietly.
final class WishPageTests: XCTestCase {
    private func page() throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        context.exceptionHandler = { _, value in XCTFail(value?.toString() ?? "?") }
        context.evaluateScript("""
            var window = this, sent = [], errors = [], sockets = [], later = [], peerLists = [], states = [], heard = [];
            var console = { error: function (m) { errors.push(String(m)); }, log: function () {} };
            window.Lamp = {};
            var LampAI = { _post: function (path, body) {
              sent.push(JSON.stringify({ post: path, body: body }));
              return Promise.resolve({ socket: 'ws://127.0.0.1:47900/', room: 'wish:scoreboard', peer: 'tv', credential: 'peer-credential',
                                       peers: [], apps: [] });
            } };
            function WebSocket(url) { this.url = url; this.readyState = 1; sockets.push(this); }
            WebSocket.prototype.send = function (text) { sent.push(text); };
            WebSocket.prototype.close = function () {};
            function setInterval() { return 0; } function clearInterval() {}
            function setTimeout(fn) { later.push(fn); return later.length; } function clearTimeout() {}
            """)
        context.evaluateScript(TVTemplate.wishJS)
        return context
    }

    /// Promises settle on the context's microtask queue, which runs when the script returns.
    private func settle(_ context: JSContext) { context.evaluateScript("0") }

    func testThePageJoinsItsRoomAndFollowsWhoIsThere() throws {
        let context = try page()
        context.evaluateScript("""
            Lamp.wish.onPeers(function (list) { peerLists.push(list.map(function (p) { return p.peer; }).join(',')); });
            Lamp.wish.onState(function (s) { states.push(s); });
            Lamp.wish.onMessage(function (from, data) { heard.push(from + ':' + JSON.stringify(data)); });
            Lamp.wish.start();
            """)
        settle(context)
        XCTAssertEqual(context.evaluateScript("sockets.length")?.toInt32(), 1, "asked Lamp, then opened its socket to the relay")
        XCTAssertEqual(context.evaluateScript("sockets[0].url")?.toString(), "ws://127.0.0.1:47900/")
        context.evaluateScript("sockets[0].onopen();")
        let hello = context.evaluateScript("JSON.parse(sent[sent.length - 1])")?.toDictionary() ?? [:]
        XCTAssertEqual(hello["t"] as? String, "hello")
        XCTAssertEqual(hello["app"] as? String, "wish:scoreboard")
        XCTAssertEqual(hello["credential"] as? String, "peer-credential")
        XCTAssertEqual(hello["device"] as? String, "TV")
        context.evaluateScript("""
            sockets[0].onmessage({ data: JSON.stringify({ t: 'welcome', role: 'peer', peer: 'tv', peers: [{ peer: 'iphone', kind: 'iphone', name: 'the iPhone app', device: 'iPhone', since: 1 }], apps: [{ peer: 'tv', kind: 'tv', name: 'the TV app' }, { peer: 'iphone', kind: 'iphone', name: 'the iPhone app' }, { peer: 'android', kind: 'android', name: 'the Android app' }], credential: 'renewed-1', now: Date.now() }) });
            var androidBefore = Lamp.wish.peer('android');
            sockets[0].onmessage({ data: JSON.stringify({ t: 'joined', peer: { peer: 'android', kind: 'android', name: 'the Android app', device: 'Android emulator', since: 2 } }) });
            sockets[0].onmessage({ data: JSON.stringify({ t: 'message', from: 'android', data: { score: 3 } }) });
            sockets[0].onmessage({ data: JSON.stringify({ t: 'left', peer: 'iphone' }) });
            """)
        XCTAssertEqual(context.evaluateScript("Lamp.wish.me()")?.toString(), "tv")
        XCTAssertEqual(context.evaluateScript("Lamp.wish.state()")?.toString(), "connected")
        XCTAssertEqual(context.evaluateScript("peerLists.join('|')")?.toString(), "|iphone|iphone,android|android")
        XCTAssertEqual(context.evaluateScript("heard.join('|')")?.toString(), "android:{\"score\":3}")
        XCTAssertEqual(context.evaluateScript("Lamp.wish.peer('android').name")?.toString(), "the Android app")
        // Every app of the wish is known, open or not, with why in words to show and when it was last seen.
        XCTAssertEqual(context.evaluateScript("androidBefore.status.state + '|' + androidBefore.status.reason")?.toString(),
                       "notOpen|The Android app isn't open.")
        XCTAssertEqual(context.evaluateScript("Lamp.wish.peer('iphone').status.state")?.toString(), "notOpen")
        XCTAssertEqual(context.evaluateScript("Lamp.wish.peer('iphone').status.reason")?.toString(), "The iPhone app isn't open.")
        XCTAssertEqual(context.evaluateScript("typeof Lamp.wish.peer('iphone').status.lastSeen")?.toString(), "number")
        XCTAssertTrue(context.evaluateScript("Lamp.wish.peer('roku')")?.isNull == true, "no such app in the wish")
        XCTAssertEqual(context.evaluateScript("Lamp.wish.status().state + '|' + Lamp.wish.status().reason")?.toString(), "connected|")
        XCTAssertEqual(context.evaluateScript("states.join(',')")?.toString(), "connecting,connected")
    }

    func testAMessageGoesToOneAppOrAllAndIsRefusedWhenItCant() throws {
        let context = try page()
        context.evaluateScript("Lamp.wish.start();")
        settle(context)
        context.evaluateScript("""
            sockets[0].onopen();
            var early = Lamp.wish.send({ hi: 1 }, 'iphone');
            sockets[0].onmessage({ data: JSON.stringify({ t: 'welcome', role: 'peer', peer: 'tv', peers: [{ peer: 'iphone', kind: 'iphone', name: 'the iPhone app', device: 'iPhone', since: 1 }], apps: [{ peer: 'tv', kind: 'tv', name: 'the TV app' }, { peer: 'iphone', kind: 'iphone', name: 'the iPhone app' }, { peer: 'android', kind: 'android', name: 'the Android app' }], now: Date.now() }) });
            var toOne = Lamp.wish.send({ score: 3 }, 'iphone');
            var toAll = Lamp.wish.send('round 2');
            var toAbsent = Lamp.wish.send({ x: 1 }, 'android');
            var big = Lamp.wish.send({ chunk: new Array(17000).join('A') });
            """)
        XCTAssertEqual(context.evaluateScript("early")?.toBool(), false, "nothing goes before the welcome")
        XCTAssertEqual(context.evaluateScript("toOne")?.toBool(), true)
        XCTAssertEqual(context.evaluateScript("toAll")?.toBool(), true)
        XCTAssertEqual(context.evaluateScript("toAbsent")?.toBool(), false, "the Android app isn't open")
        XCTAssertEqual(context.evaluateScript("big")?.toBool(), false)
        let frames = context.evaluateScript("sent.filter(function (s) { return s.charAt(0) === '{' && JSON.parse(s).t === 'send'; })")?.toArray() as? [String] ?? []
        XCTAssertEqual(frames.count, 2, "only the two that could go went: \(frames)")
        XCTAssertEqual(frames.first.flatMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] }?["to"] as? String, "iphone")
        XCTAssertNil(frames.last.flatMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] }?["to"], "to all")
        let errors = context.evaluateScript("errors.join('\\n')")?.toString() ?? ""
        XCTAssertTrue(errors.contains("not connected"), errors)
        XCTAssertTrue(errors.contains("is not open now"), errors)
        XCTAssertTrue(errors.contains("at most 16384 bytes"), errors)
    }

    /// The room hands the page a fresh credential over its socket; a dropped link comes back with the newest one, and the
    /// one it last used is never sent again.
    func testADroppedLinkComesBackWithTheCredentialTheRoomLastGave() throws {
        let context = try page()
        context.evaluateScript("Lamp.wish.start();")
        settle(context)
        context.evaluateScript("""
            sockets[0].onopen();
            sockets[0].onmessage({ data: JSON.stringify({ t: 'welcome', role: 'peer', peer: 'tv', peers: [], apps: [], credential: 'from-welcome', now: Date.now() }) });
            sockets[0].onmessage({ data: JSON.stringify({ t: 'credential', credential: 'renewed' }) });
            sockets[0].onclose({ code: 1006 }); later.pop()();
            """)
        settle(context)
        XCTAssertEqual(context.evaluateScript("sockets.length")?.toInt32(), 2)
        context.evaluateScript("sockets[1].onopen();")
        let hellos = context.evaluateScript("sent.filter(function (s) { return s.charAt(0) === '{' && JSON.parse(s).t === 'hello'; }).map(function (s) { return JSON.parse(s).credential; }).join(',')")?.toString()
        XCTAssertEqual(hellos, "peer-credential,renewed", "the first from Lamp, then the renewed one, each once")
        XCTAssertEqual(context.evaluateScript("sent.filter(function (s) { return s.indexOf('\"post\":\"/app/wish\"') >= 0; }).length")?.toInt32(), 1,
                       "no need to ask Lamp again")
    }

    func testTurnedAwayThePageAsksLampAgainForAFreshCredential() throws {
        let context = try page()
        context.evaluateScript("Lamp.wish.start();")
        settle(context)
        context.evaluateScript("sockets[0].onopen(); sockets[0].onclose({ code: 4003 }); later.pop()();")
        settle(context)
        XCTAssertEqual(context.evaluateScript("sent.filter(function (s) { return s.indexOf('\"post\":\"/app/wish\"') >= 0; }).length")?.toInt32(), 2,
                       "asked twice: once at the start, once after being turned away")
        XCTAssertEqual(context.evaluateScript("sockets.length")?.toInt32(), 2)
    }
}
