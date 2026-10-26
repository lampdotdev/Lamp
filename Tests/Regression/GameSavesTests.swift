import JavaScriptCore
import XCTest

/// A three.js game's saves on the Mac and iOS go to the app around the page, which keeps them in a file of the app's,
/// not in the web view's storage, which WebKit keeps by bundle id. What an earlier build left in that storage is handed
/// over the first time.
final class GameSavesTests: XCTestCase {
    /// Lamp's game runtime in a stand-in page, as the app around it starts it: `given` is `window.lampSaves`, and
    /// `stored` is what the web view's storage already holds.
    private func page(given: String, stored: [String: String]) throws -> JSContext {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let runtime = try String(contentsOf: source.appendingPathComponent("Resources/GameKit/web/lamp-game.js"), encoding: .utf8)
        let context = try XCTUnwrap(JSContext())
        var failure: String?
        context.exceptionHandler = { _, value in failure = value?.toString() }
        let storage = String(decoding: try JSONSerialization.data(withJSONObject: stored), as: UTF8.self)
        context.evaluateScript("""
            var window = this, told = [], store = \(storage);
            window.addEventListener = function () {};
            var navigator = { maxTouchPoints: 0 };
            var localStorage = {
              get length() { return Object.keys(store).length; },
              key: function (i) { return Object.keys(store)[i]; },
              getItem: function (k) { return store.hasOwnProperty(k) ? store[k] : null; },
              setItem: function (k, v) { store[k] = String(v); }
            };
            window.webkit = { messageHandlers: { lampSaves: { postMessage: function (m) { told.push(JSON.parse(JSON.stringify(m))); } } } };
            window.lampSaves = \(given);
            """)
        // The module as a plain script: its exports become the page's functions.
        context.evaluateScript(runtime.replacingOccurrences(of: "export ", with: ""))
        XCTAssertNil(failure)
        return context
    }

    private func json(_ context: JSContext, _ script: String) -> String? {
        context.evaluateScript("JSON.stringify(\(script))")?.toString()
    }

    func testSavesGoToTheAppNotTheWebViewsStorage() throws {
        let context = try page(given: #"{"saves": {"best": "40"}, "moved": true}"#, stored: [:])
        XCTAssertEqual(json(context, "load('best')"), "40")
        context.evaluateScript("save('level', { n: 3 })")
        XCTAssertEqual(json(context, "told"), #"[{"op":"set","name":"level","text":"{\"n\":3}"}]"#)
        XCTAssertEqual(json(context, "store"), "{}", "nothing is kept in the web view's storage")
        XCTAssertEqual(json(context, "load('level')"), #"{"n":3}"#)
    }

    func testWhatAnEarlierBuildSavedIsHandedOverOnce() throws {
        let stored = ["lamp.save.best": "12", "lamp.save.name": #""Ada""#, "other": "x"]
        let first = try page(given: #"{"saves": {"name": "\"Bo\""}, "moved": false}"#, stored: stored)
        XCTAssertEqual(json(first, "told"), #"[{"op":"move","saves":{"best":"12"}}]"#, "only the game's saves, and none the file already has")
        XCTAssertEqual(json(first, "load('best')"), "12")
        XCTAssertEqual(json(first, "load('name')"), #""Bo""#)

        let later = try page(given: #"{"saves": {"best": "12"}, "moved": true}"#, stored: stored)
        XCTAssertEqual(json(later, "told"), "[]")
    }
}
