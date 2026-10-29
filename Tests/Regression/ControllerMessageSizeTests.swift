import JavaScriptCore
import LampRelayKit
import XCTest
@testable import Lamp

/// The relay passes at most `ControllerWire.message` bytes in one message between devices and closes a socket that
/// sends more. A TV app whose phone sent a file in pieces too big for a message lost every one of them, and its builder
/// saw only a transfer that stopped: each library of Lamp's refuses such a message before it goes, says so with the
/// limit, and tells the TV app, whose log the builder reads. (A file goes with `sendFile` now, in pieces of its own.)
final class ControllerMessageSizeTests: XCTestCase {
    private static let limit = ControllerWire.message
    /// A message a little over the limit.
    private static let tooMany = limit + 600

    // The wish's iPhone or Mac app (LampController in LampSupport): `WishFilesTests`, where it plays a TV page's game.

    // MARK: The phone's page (lamp-controller.js) and the TV's (lamp.js)

    func testThePhonePageRefusesAMessageOverTheLimitAndTellsTheTV() throws {
        let context = try XCTUnwrap(JSContext())
        var failure: String?
        context.exceptionHandler = { _, value in failure = value?.toString() }
        context.evaluateScript("""
            var window = this, sent = [], errors = [], sockets = [], store = {};
            var console = { error: function (m) { errors.push(String(m)); }, log: function () {} };
            var location = { hash: '#join', pathname: '/', search: '', protocol: 'http:', host: '192.168.1.20:47860', hostname: '192.168.1.20' };
            var history = { replaceState: function () { location.hash = ''; } };
            var sessionStorage = {
              getItem: function (k) { return store.hasOwnProperty(k) ? store[k] : null; },
              setItem: function (k, v) { store[k] = String(v); }, removeItem: function (k) { delete store[k]; }
            };
            function WebSocket(url) { this.readyState = 1; sockets.push(this); }
            WebSocket.prototype.send = function (text) { sent.push(text); };
            WebSocket.prototype.close = function () {};
            function fetch() { return Promise.resolve({ ok: true, json: function () { return { port: 47900, app: 'padgame' }; } }); }
            function setInterval() { return 0; } function clearInterval() {} function setTimeout() { return 0; }
            """)
        context.evaluateScript(TVTemplate.phoneControllerJS)
        context.evaluateScript("var pad = LampController.connect({});")
        context.evaluateScript("""
            sockets[0].onopen();
            sockets[0].onmessage({ data: JSON.stringify({ t: 'welcome', place: 2, host: true, credential: 'kept' }) });
            var big = pad.send({ chunk: new Array(\(Self.tooMany)).join('A') });
            var small = pad.send({ chunk: 'small' });
            """)
        XCTAssertNil(failure)
        XCTAssertEqual(context.evaluateScript("big")?.toBool(), false)
        XCTAssertEqual(context.evaluateScript("small")?.toBool(), true)
        XCTAssertEqual(context.evaluateScript("sent.filter(function (s) { return s.length > \(Self.limit); }).length")?.toInt32(), 0,
                       "nothing over the limit goes to Lamp")
        XCTAssertEqual(context.evaluateScript("sent.filter(function (s) { return JSON.parse(s).t === 'too-big'; }).length")?.toInt32(), 1,
                       "the TV app is told")
        XCTAssertTrue(context.evaluateScript("errors.join(' ')")?.toString().contains("at most \(Self.limit) bytes") == true)
    }

    /// A page that says it's ready as soon as it's given its number, on the welcome that says the TV app is there:
    /// that message goes, on the first link and after a reconnect (Roomote's review of 2f7b3ede).
    func testAMessageSentWhenThePhoneIsGivenItsNumberGoes() throws {
        let context = try XCTUnwrap(JSContext())
        var failure: String?
        context.exceptionHandler = { _, value in failure = value?.toString() }
        context.evaluateScript("""
            var window = this, sent = [], sockets = [], store = {}, later = [], results = [];
            var location = { hash: '#join', pathname: '/', search: '', protocol: 'http:', host: '192.168.1.20:47860', hostname: '192.168.1.20' };
            var history = { replaceState: function () { location.hash = ''; } };
            var sessionStorage = {
              getItem: function (k) { return store.hasOwnProperty(k) ? store[k] : null; },
              setItem: function (k, v) { store[k] = String(v); }, removeItem: function (k) { delete store[k]; }
            };
            function WebSocket(url) { this.readyState = 1; sockets.push(this); }
            WebSocket.prototype.send = function (text) { sent.push(text); };
            WebSocket.prototype.close = function () {};
            function fetch() { return Promise.resolve({ ok: true, json: function () { return { port: 47900, app: 'padgame' }; } }); }
            function setInterval() { return 0; } function clearInterval() {}
            function setTimeout(fn) { later.push(fn); return later.length; } function clearTimeout() {}
            """)
        context.evaluateScript(TVTemplate.phoneControllerJS)
        // The relay welcomes the phone, saying the TV app is there, and the TV app gives it its number.
        context.evaluateScript("""
            var pad = LampController.connect({ onPlayer: function (n) { results.push(pad.send({ ready: n })); } });
            var welcome = JSON.stringify({ t: 'welcome', place: 2, host: true, credential: 'kept' });
            var number = JSON.stringify({ t: 'player', number: 2 });
            """)
        context.evaluateScript("""
            sockets[0].onopen(); sockets[0].onmessage({ data: welcome }); sockets[0].onmessage({ data: number });
            sockets[0].onclose({ code: 1006 });   // the Wi-Fi dropped, and the page joins again
            later.shift()();
            """)
        context.evaluateScript("sockets[1].onopen(); sockets[1].onmessage({ data: welcome }); sockets[1].onmessage({ data: number });")
        XCTAssertNil(failure)
        XCTAssertEqual(context.evaluateScript("results.join(',')")?.toString(), "true,true")
        XCTAssertEqual(context.evaluateScript("sent.filter(function (s) { return JSON.parse(s).t === 'message'; }).length")?.toInt32(), 2)
    }

    func testTheTVPageRefusesAMessageOverTheLimitAndLogsAPhonesRefusedOne() throws {
        let context = try XCTUnwrap(JSContext())
        var failure: String?
        context.exceptionHandler = { _, value in failure = value?.toString() }
        context.evaluateScript("""
            var window = this, sent = [], errors = [], heardErrors = [], sockets = [], later = [];
            var console = { error: function (m) { errors.push(String(m)); }, log: function () {} };
            window.Lamp = {};
            var LampAI = { _post: function () {
              return Promise.resolve({ links: [{ kind: 'relay', socket: 'ws://127.0.0.1:47900/', app: 'padgame', credential: 'host' }] });
            } };
            function WebSocket(url) { this.readyState = 1; sockets.push(this); }
            WebSocket.prototype.send = function (text) { sent.push(text); };
            WebSocket.prototype.close = function () {};
            function setInterval() { return 0; } function clearInterval() {}
            function setTimeout(fn) { later.push(fn); return later.length; } function clearTimeout() {}
            """)
        context.evaluateScript(TVTemplate.controllersJS)
        context.evaluateScript("""
            Lamp.controllers.onError(function (m) { heardErrors.push(m); });
            Lamp.controllers.start();
            later.shift()();   // asks Lamp who the players are
            """)
        context.evaluateScript("""
            sockets[0].onopen();
            sockets[0].onmessage({ data: JSON.stringify({ t: 'welcome', role: 'host', players: [2], now: Date.now() }) });
            var big = Lamp.controllers.send(2, { chunk: new Array(\(Self.tooMany)).join('A') });
            var small = Lamp.controllers.send(2, { chunk: 'small' });
            sockets[0].onmessage({ data: JSON.stringify({ t: 'too-big', player: 2, bytes: 17000 }) });
            """)
        XCTAssertNil(failure)
        XCTAssertEqual(context.evaluateScript("big")?.toBool(), false)
        XCTAssertEqual(context.evaluateScript("small")?.toBool(), true)
        XCTAssertEqual(context.evaluateScript("sent.filter(function (s) { return JSON.parse(s).t === 'send'; }).length")?.toInt32(), 1,
                       "only the small one went")
        let errors = context.evaluateScript("errors.join('\\n')")?.toString() ?? ""
        XCTAssertTrue(errors.contains("A message of"), errors)
        XCTAssertTrue(errors.contains("Player 2's message of 17000 bytes was not sent: a message between devices is at most \(Self.limit) bytes"), errors)
        XCTAssertEqual(context.evaluateScript("heardErrors.length")?.toInt32(), 2)
    }

    /// On the Xbox the game's own host runs its phones: the page asks the host for its session, never Lamp, and its link
    /// to the relay goes over the host's pipe (an https page may not open a plain link), where phones reach the game.
    func testAGameOnTheXboxReachesItsOwnHostsRelayWithoutLamp() throws {
        let context = try XCTUnwrap(JSContext())
        var failure: String?
        context.exceptionHandler = { _, value in failure = value?.toString() }
        context.evaluateScript("""
            var window = this, posted = [], heard = [], later = [], listeners = [], askedLamp = 0;
            var console = { error: function () {}, log: function () {} };
            window.Lamp = {};
            window.chrome = { webview: { postMessage: function (m) { posted.push(m); },
                                         addEventListener: function (kind, fn) { listeners.push(fn); } } };
            function host(m) { for (var i = 0; i < listeners.length; i++) listeners[i]({ data: m }); }
            var LampAI = { _post: function () { askedLamp++; return Promise.reject(new Error('Lamp is not open.')); } };
            function WebSocket() { throw new Error('An https page may not open a plain link.'); }
            function setInterval() { return 0; } function clearInterval() {}
            function setTimeout(fn) { later.push(fn); return later.length; } function clearTimeout() {}
            """)
        context.evaluateScript(TVTemplate.controllersJS)
        context.evaluateScript("""
            Lamp.controllers.onButton(function (player, name, down) { heard.push(player + ':' + name + ':' + down); });
            Lamp.controllers.start();
            later.shift()();
            var asked = posted.filter(function (m) { return m.lamp === 'controllers'; })[0];
            host({ lamp: 'controllers', id: asked.id, status: 200, body: { renew: 15,
              links: [{ kind: 'relay', socket: 'ws://lamp-controllers.invalid/', app: 'padgame', credential: 'host' }] } });
            """)
        context.evaluateScript("""
            var opened = posted.filter(function (m) { return m.op === 'open'; })[0];
            host({ lamp: 'ws', ev: 'open', id: opened.id });
            host({ lamp: 'ws', ev: 'message', id: opened.id, text: JSON.stringify({ t: 'welcome', role: 'host', players: [], now: Date.now() }) });
            host({ lamp: 'ws', ev: 'message', id: opened.id, text: JSON.stringify({ t: 'button', player: 1, name: 'a', down: true, seq: 1 }) });
            Lamp.controllers.stop();
            """)
        XCTAssertNil(failure)
        XCTAssertEqual(context.evaluateScript("asked.op")?.toString(), "start")
        XCTAssertEqual(context.evaluateScript("opened.url")?.toString(), "ws://lamp-controllers.invalid/")
        let hello = context.evaluateScript("JSON.parse(posted.filter(function (m) { return m.op === 'send'; })[0].text).t")?.toString()
        XCTAssertEqual(hello, "hello", "the page says hello to the relay over the host's pipe")
        XCTAssertEqual(context.evaluateScript("heard.join(',')")?.toString(), "1:a:true,1:a:false",
                       "a phone's button reaches the game, and stopping lets it go")
        XCTAssertEqual(context.evaluateScript("posted.filter(function (m) { return m.lamp === 'controllers'; }).map(function (m) { return m.op; }).join(',')")?.toString(),
                       "start,stop", "stopping tells the host")
        XCTAssertEqual(context.evaluateScript("askedLamp")?.toInt32(), 0, "Lamp is never asked")
    }
}
