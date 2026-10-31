import JavaScriptCore
import XCTest
@testable import Lamp

/// `LampVoice` and `LampAI.hear` in lamp.js, against stand-ins for the app around the page and for Lamp: what a page
/// learns about a host that can't hear (or an old one that says nothing), that a recording's levels reach only its own
/// session, and that what was said goes to each way to the Mac once, under one id, never tried again after a moment
/// as other AI calls are.
@MainActor
final class VoicePageTests: XCTestCase {
    private func page(apple: Bool = false, install: String? = nil, xhr: Bool = false) throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        context.exceptionHandler = { _, value in XCTFail(value?.toString() ?? "?") }
        context.evaluateScript("""
            var window = this, timers = [], store = {}, voiceCalls = [], gateway = [], opened = [], sent = [];
            var console = { error: function () {}, log: function () {} };
            window.addEventListener = function () {}; window.removeEventListener = function () {};
            var navigator = {}, document = { addEventListener: function () {} };
            window.localStorage = { getItem: function (k) { return k in store ? store[k] : null; }, setItem: function (k, v) { store[k] = String(v); }, removeItem: function (k) { delete store[k]; } };
            function setTimeout(fn) { timers.push(fn); return timers.length; } function clearTimeout() {}
            function setInterval() { return 0; } function clearInterval() {}
            var voiceAnswer = null, held = null;
            window.webkit = { messageHandlers: {
              lampGateway: { postMessage: function (m) { gateway.push(m.path); return Promise.resolve({ status: 404, body: '{"error":"Not found"}' }); } }
              \(apple ? """
              , lampVoice: { postMessage: function (m) {
                  voiceCalls.push(m.cmd + (m.session ? ':' + m.session : ''));
                  if (m.cmd === 'listen') return new Promise(function (r) { held = r; });
                  return Promise.resolve(m.cmd === 'status' ? voiceAnswer : true);
                } }
              """ : "")
            } };
            \(xhr ? """
            delete window.webkit;
            store['lamp:install.token'] = JSON.stringify({ app: 'board', token: 't' });
            function XMLHttpRequest() {} XMLHttpRequest.prototype.open = function (m, url) { this.url = url; };
            XMLHttpRequest.prototype.setRequestHeader = function () {};
            XMLHttpRequest.prototype.send = function (b) { opened.push(this.url); sent.push(b); var x = this; x.onerror(); };
            """ : "")
            """)
        var js = DeviceSupport.webJS
        if let install { js = js.replacingOccurrences(of: DeviceSupport.webMarker, with: "/*LAMP_INSTALL*/" + install) }
        context.evaluateScript(js)
        return context
    }

    private func settle(_ c: JSContext) { for _ in 0..<20 { c.evaluateScript("0") } }
    private func value(_ c: JSContext, _ script: String) -> Any? {
        c.evaluateScript("JSON.stringify(\(script))")?.toString().flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8), options: .fragmentsAllowed) }
    }

    func testAPageWithNoHostThatHearsIsToldSoAtOnce() throws {
        let c = try page()
        c.evaluateScript("var got; LampVoice.status().then(function (s) { got = s; }); LampVoice.listen({ session: 'a' }).then(function (r) { window.r = r; });")
        settle(c)
        XCTAssertEqual(value(c, "got.listen") as? Bool, false)
        XCTAssertEqual(value(c, "got.permission") as? String, "none")
        XCTAssertEqual(value(c, "r.ended") as? String, "error")
    }

    func testAnOldHostThatAnswersNothingIsNoVoiceNotAWait() throws {
        let c = try page(apple: true)
        // An app around the page from before it could hear: its status answers nothing.
        c.evaluateScript("voiceAnswer = undefined; var got = null; LampVoice.status().then(function (s) { got = s; });")
        settle(c)
        XCTAssertEqual(value(c, "got.listen") as? Bool, false)
        // And one that hangs: the page stops waiting.
        c.evaluateScript("""
            window.webkit.messageHandlers.lampVoice.postMessage = function () { return new Promise(function () {}); };
            got = null; LampVoice.status().then(function (s) { got = s; });
            """)
        settle(c)
        XCTAssertTrue(c.evaluateScript("got === null")?.toBool() == true)
        c.evaluateScript("timers.forEach(function (f) { f(); });")
        settle(c)
        XCTAssertEqual(value(c, "got.listen") as? Bool, false)
    }

    func testStatusNeverListensAndLevelsReachOnlyTheirOwnSession() throws {
        let c = try page(apple: true)
        c.evaluateScript("""
            voiceAnswer = { listen: true, speak: true, permission: 'ask' };
            var got, levels = [], result;
            LampVoice.status().then(function (s) { got = s; });
            LampVoice.listen({ session: 's2', onLevel: function (l) { levels.push(l.level); } }).then(function (r) { result = r; });
            """)
        settle(c)
        XCTAssertEqual(value(c, "got.permission") as? String, "ask")
        XCTAssertEqual(value(c, "voiceCalls") as? [String], ["status", "listen:s2"])
        c.evaluateScript("""
            window.__lampVoice({ event: 'level', session: 's1', level: 0.9 });
            window.__lampVoice({ event: 'level', session: 's2', level: 0.4 });
            held({ ended: 'quiet', audio: 'UklGRg==', seconds: 1.2, speech: true });
            """)
        settle(c)
        // A level that comes after the recording ended: no one is listening for it.
        c.evaluateScript("window.__lampVoice({ event: 'level', session: 's2', level: 0.7 });")
        XCTAssertEqual(value(c, "levels") as? [Double], [0.4])
        XCTAssertEqual(value(c, "result.ended") as? String, "quiet")
        XCTAssertEqual(value(c, "result.audio") as? String, "UklGRg==")
    }

    func testHearingIsAvailableOnlyWhenTheHostLetsTheRouteThrough() throws {
        let c = try page(apple: true)
        c.evaluateScript("var yes = null; LampAI.isAvailable('hear').then(function (v) { yes = v; });")
        settle(c)
        XCTAssertEqual(value(c, "yes") as? Bool, false)
        XCTAssertEqual(value(c, "gateway") as? [String], ["/ai/hear"])
    }

    func testWhatWasSaidIsSentOnceWhereOtherCallsTryAgain() throws {
        let install = #"{ "app": "board", "routes": ["http://10.0.0.2:47800", "http://mac.local:47800"] }"#
        let c = try page(install: install, xhr: true)
        c.evaluateScript("var heard = null, asked = null;")
        c.evaluateScript("LampAI.hear('UklGRg==').then(null, function (e) { heard = e.message; });")
        settle(c)
        c.evaluateScript("timers.forEach(function (f) { f(); });")
        settle(c)
        XCTAssertEqual((value(c, "opened") as? [String])?.count, 2, "each way to the Mac once")
        // Both with the recording's own id, by which Lamp transcribes and charges it once.
        let ops = Set(((value(c, "sent.map(function (b) { return JSON.parse(b).op; })") as? [String]) ?? []))
        XCTAssertEqual(ops.count, 1)
        XCTAssertFalse(ops.first?.isEmpty ?? true)
        XCTAssertNotNil(value(c, "heard") as? String)
        c.evaluateScript("opened = []; timers = []; LampAI.ask('hi').then(null, function (e) { asked = e.message; });")
        settle(c)
        c.evaluateScript("timers.forEach(function (f) { f(); });")
        settle(c)
        XCTAssertEqual((value(c, "opened") as? [String])?.count, 4, "an ask tries every way twice")
    }
}
