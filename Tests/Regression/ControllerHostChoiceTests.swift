import JavaScriptCore
import XCTest
@testable import Lamp

/// A game chooses who hosts its phones as it starts them (`Lamp.controllers.start({ host })`): the same page script
/// reaches the game's own host or Lamp's, and a host that fails is said, never swapped for the other.
final class ControllerHostChoiceTests: XCTestCase {
    /// The page script on the Xbox (a WebView2 host's pipe is there), with Lamp's gateway answering `lamp` as asked.
    private func xboxPage(lamp: String) throws -> (JSContext, () -> String?) {
        let context = try XCTUnwrap(JSContext())
        var failure: String?
        context.exceptionHandler = { _, value in failure = value?.toString() }
        context.evaluateScript("""
            var window = this, posted = [], later = [], listeners = [], askedLamp = [], errors = [];
            var console = { error: function () {}, log: function () {} };
            window.Lamp = {};
            window.chrome = { webview: { postMessage: function (m) { posted.push(m); },
                                         addEventListener: function (kind, fn) { listeners.push(fn); } } };
            function host(m) { for (var i = 0; i < listeners.length; i++) listeners[i]({ data: m }); }
            var LampAI = { _post: function (path, body) { askedLamp.push(body); return \(lamp); } };
            function WebSocket() { throw new Error('An https page may not open a plain link.'); }
            function setInterval() { return 0; } function clearInterval() {}
            function setTimeout(fn) { later.push(fn); return later.length; } function clearTimeout() {}
            function asks() { return posted.filter(function (m) { return m.lamp === 'controllers'; }); }
            function opened() { return posted.filter(function (m) { return m.lamp === 'ws' && m.op === 'open'; }); }
            """)
        context.evaluateScript(TVTemplate.controllersJS)
        context.evaluateScript("Lamp.controllers.onError(function (m) { errors.push(m); });")
        return (context, { failure })
    }

    private static let lampAnswers = "Promise.resolve({ renew: 15, links: [{ kind: 'relay', socket: 'ws://192.168.1.20:47900/', app: 'padgame', credential: 'lamp' }] })"
    private static let lampFails = "Promise.reject(new Error('Couldn\\'t reach Lamp on your Mac.'))"

    func testTheSameBuildReachesTheGamesOwnHostOrLampsAsChosen() throws {
        let (game, gameFailure) = try xboxPage(lamp: Self.lampAnswers)
        game.evaluateScript("Lamp.controllers.start({ host: 'game' }); later.shift()();")
        game.evaluateScript("""
            host({ lamp: 'controllers', id: asks()[0].id, status: 200, body: { renew: 15,
              links: [{ kind: 'relay', socket: 'ws://lamp-controllers.invalid/', app: 'padgame', credential: 'game' }] } });
            """)
        XCTAssertNil(gameFailure())
        XCTAssertEqual(game.evaluateScript("asks()[0].op")?.toString(), "start")
        XCTAssertEqual(game.evaluateScript("opened()[0].url")?.toString(), "ws://lamp-controllers.invalid/")
        XCTAssertEqual(game.evaluateScript("askedLamp.length")?.toInt32(), 0, "the game's own host: Lamp is never asked")

        let (lamp, lampFailure) = try xboxPage(lamp: Self.lampAnswers)
        lamp.evaluateScript("Lamp.controllers.start({ host: 'lamp' }); later.shift()();")
        lamp.evaluateScript("var link = opened()[0];")
        XCTAssertNil(lampFailure())
        XCTAssertEqual(lamp.evaluateScript("askedLamp[0].host")?.toString(), "lamp")
        XCTAssertEqual(lamp.evaluateScript("link.url")?.toString(), "ws://192.168.1.20:47900/", "Lamp's relay, through the host's pipe")
        XCTAssertEqual(lamp.evaluateScript("asks().length")?.toInt32(), 0, "Lamp's host: the console's own is never asked")

        // Stopping ends the session it started, with the host that started it.
        game.evaluateScript("Lamp.controllers.stop();")
        XCTAssertEqual(game.evaluateScript("asks().map(function (m) { return m.op; }).join(',')")?.toString(), "start,stop")
        lamp.evaluateScript("Lamp.controllers.stop();")
        XCTAssertEqual(lamp.evaluateScript("askedLamp[1].stop && askedLamp[1].host")?.toString(), "lamp")
    }

    func testAFailingHostIsSaidAndTheOtherIsNeverTried() throws {
        // The game's own host can't open: the game hears why, and the next try asks the same host again.
        let (game, gameFailure) = try xboxPage(lamp: Self.lampAnswers)
        game.evaluateScript("Lamp.controllers.start({ host: 'game' }); later.shift()();")
        game.evaluateScript("""
            host({ lamp: 'controllers', id: asks()[0].id, status: 503,
                   body: { error: "This console isn't on a network phones can join." } });
            """)
        game.evaluateScript("later.shift()();")
        XCTAssertNil(gameFailure())
        XCTAssertEqual(game.evaluateScript("errors.join('|')")?.toString(), "This console isn't on a network phones can join.")
        XCTAssertEqual(game.evaluateScript("asks().length")?.toInt32(), 2, "tried again, on the same host")
        XCTAssertEqual(game.evaluateScript("askedLamp.length")?.toInt32(), 0)
        XCTAssertEqual(game.evaluateScript("opened().length")?.toInt32(), 0)

        // Lamp can't be reached: the same, the other way round.
        let (lamp, lampFailure) = try xboxPage(lamp: Self.lampFails)
        lamp.evaluateScript("Lamp.controllers.start({ host: 'lamp' }); later.shift()();")
        lamp.evaluateScript("later.shift()();")
        XCTAssertNil(lampFailure())
        XCTAssertEqual(lamp.evaluateScript("errors[0]")?.toString(), "Couldn't reach Lamp on your Mac.")
        XCTAssertEqual(lamp.evaluateScript("askedLamp.length")?.toInt32(), 2, "tried again, on the same host")
        XCTAssertEqual(lamp.evaluateScript("asks().length")?.toInt32(), 0)
        XCTAssertEqual(lamp.evaluateScript("opened().length")?.toInt32(), 0)
    }

    func testAnUnknownHostOrASecondHostIsRefused() throws {
        let (page, failure) = try xboxPage(lamp: Self.lampAnswers)
        page.evaluateScript("""
            var said = [];
            Lamp.controllers.start({ host: 'cloud' }).catch(function (e) { said.push(e.message); });
            """)
        page.evaluateScript("""
            Lamp.controllers.start({ host: 'game' });
            Lamp.controllers.start({ host: 'lamp' }).catch(function (e) { said.push(e.message); });
            """)
        XCTAssertNil(failure())
        XCTAssertEqual(page.evaluateScript("said.join('|')")?.toString(),
                       "Lamp.controllers.start: host is 'game' or 'lamp'.|Lamp.controllers: started with another host; call stop() first.")
    }
}
