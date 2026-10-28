import JavaScriptCore
import XCTest
@testable import Lamp

/// `Lamp.wish` in a game's or a screen's page on the Mac, the iPhone and the iPad, where the app around the page is the
/// wish's peer (`LampPageWish`) and the page mirrors it (`hosted` in lamp.js): what the app says comes to
/// `window.__lampWish`, and what the page does is posted to the app's `lampWish` handler.
@MainActor
final class WishHostedPageTests: XCTestCase {
    private func page() throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        context.exceptionHandler = { _, value in XCTFail(value?.toString() ?? "?") }
        context.evaluateScript("""
            var window = this, posted = [], errors = [], later = [];
            var console = { error: function (m) { errors.push(String(m)); }, log: function () {} };
            window.location = { protocol: 'lamp-game:' };
            window.webkit = { messageHandlers: { lampGateway: {}, lampWish: { postMessage: function (m) { posted.push(m); } } } };
            window.Lamp = {};
            window.btoa = function (s) { return 'b64:' + s.length; };
            function setInterval() { return 0; } function clearInterval() {}
            function setTimeout(fn) { later.push(fn); return later.length; } function clearTimeout() {}
            """)
        context.evaluateScript(TVTemplate.wishJS)
        return context
    }

    /// Promises settle on the context's microtask queue, which runs when the script returns.
    private func settle(_ context: JSContext) { context.evaluateScript("0") }

    private func ops(_ context: JSContext) -> [String] {
        context.evaluateScript("posted.map(function (m) { return m.op; })")?.toArray() as? [String] ?? []
    }

    /// The values the app kept on the device reach the page after it asked for them: a page that draws from `values()`
    /// and again on `onChange`, as the wish-links skill says to, draws them; and a value the page set itself is said
    /// once, not again when the app's copy of it comes back.
    func testValuesTheAppKeptReachOnChange() throws {
        let context = try page()
        context.evaluateScript("""
            var seen = [];
            Lamp.wish.onChange(function (key, value, from) { seen.push([key, value, from]); });
            __lampWish({ t: 'state', me: 'game', apps: [{ peer: 'mac', kind: 'mac', name: 'the Mac app', device: 'Mac', open: true,
                         status: { state: 'connected', reason: '', lastSeen: null } }], status: { state: 'connected', reason: '' } });
            __lampWish({ t: 'values', values: { score: 3 }, changed: [] });
            """)
        XCTAssertEqual(context.evaluateScript("JSON.stringify(seen)")?.toString(), #"[["score",3,"game"]]"#, "kept values are said to onChange")
        XCTAssertEqual(context.evaluateScript("Lamp.wish.values().score")?.toInt32(), 3)

        context.evaluateScript("__lampWish({ t: 'values', values: { score: 4 }, changed: [{ key: 'score', value: 4, from: 'mac' }] });")
        XCTAssertEqual(context.evaluateScript("JSON.stringify(seen[1])")?.toString(), #"["score",4,"mac"]"#, "another app's change, with who made it")

        context.evaluateScript("""
            Lamp.wish.set('round', 2);
            __lampWish({ t: 'values', values: { score: 4, round: 2 }, changed: [{ key: 'round', value: 2, from: 'game' }] });
            __lampWish({ t: 'values', values: { score: 4 }, changed: [{ key: 'round', value: null, from: 'mac' }] });
            """)
        XCTAssertEqual(context.evaluateScript("JSON.stringify(seen.slice(2))")?.toString(), #"[["round",2,"game"],["round",null,"mac"]]"#,
                       "the page's own setting once, then another app's removal")
    }

    /// A file cancelled before its bytes are ready never starts, and its transfer says it was cancelled; one cancelled
    /// once it's on its way is cancelled in the app.
    func testAFileCancelledBeforeItStartsIsNeverSent() throws {
        let context = try page()
        context.evaluateScript("""
            var failed = null;
            Lamp.wish.start();
            var t = Lamp.wish.sendFile(new Uint8Array([1, 2, 3]), 'mac', { name: 'a.bin' });
            t.cancel();
            t.done.then(function () { failed = 'sent'; }, function (e) { failed = e.message; });
            """)
        settle(context)
        XCTAssertEqual(ops(context), ["start"], "nothing of the cancelled file reaches the app")
        XCTAssertEqual(context.evaluateScript("failed")?.toString(), "The file was cancelled.")

        context.evaluateScript("var u = Lamp.wish.sendFile(new Uint8Array([4]), 'mac', { name: 'b.bin' });")
        settle(context)
        context.evaluateScript("u.cancel();")
        XCTAssertEqual(ops(context), ["start", "sendFile", "cancel"])
    }
}
