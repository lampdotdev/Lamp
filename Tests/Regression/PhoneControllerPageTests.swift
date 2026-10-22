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
}
