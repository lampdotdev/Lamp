import XCTest
import JavaScriptCore

/// The sidebar says "This tab is on a new page" when the toolbar click's access to the tab is gone. Chrome keeps
/// that access while the tab stays on the same site (a reload, another page there), so only a move to another site
/// may say so. Runs the extension's own worker.js with a stand-in for Chrome's APIs.
final class BrowserMovedNoteTests: XCTestCase {
    private func worker() throws -> (JSContext, () -> [String: Any]) {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("experiments/browser-connector/extension/worker.js")
        let script = try String(contentsOf: source, encoding: .utf8)
        let context = JSContext()!
        context.exceptionHandler = { _, error in XCTFail("worker.js threw: \(error?.toString() ?? "")") }
        context.evaluateScript("""
            var session = {}, listeners = {};
            const event = name => ({addListener: f => { listeners[name] = f; }});
            const area = store => ({
              setAccessLevel: async () => {},
              get: async keys => { const out = {}; for (const k of [].concat(keys ?? Object.keys(store))) if (k in store) out[k] = store[k]; return out; },
              set: async values => { Object.assign(store, values); },
              remove: async keys => { for (const k of [].concat(keys)) delete store[k]; },
              onChanged: event('changed'),
            });
            // Enough of URL for the worker: scheme, host and path.
            var URL = function (text) {
              const m = /^([a-z]+:)\\/\\/([^\\/?#]+)([^?#]*)/.exec(String(text));
              if (!m) throw new TypeError('Invalid URL');
              this.protocol = m[1]; this.host = this.hostname = m[2]; this.pathname = m[3] || '/'; this.origin = m[1] + '//' + m[2];
            };
            var crypto = {randomUUID: () => 'id-' + Math.random()};
            var setInterval = () => 0;
            var chrome = {
              storage: {local: area({}), session: area(session)},
              runtime: {id: 'x', getURL: p => 'chrome-extension://x/' + p, lastError: undefined,
                        connectNative: () => ({onMessage: event('port'), onDisconnect: event('gone'), postMessage: () => { Promise.resolve().then(() => listeners.port({error: 'Lamp is closed.'})); }}),
                        onMessage: event('message'), onStartup: event('startup'), onInstalled: event('installed')},
              alarms: {create: () => {}, onAlarm: event('alarm')},
              action: {onClicked: event('click')},
              sidePanel: {setOptions: () => {}, open: async () => {}},
              tabs: {onUpdated: event('updated'), onRemoved: event('removed'), get: async () => null},
              declarativeContent: {onPageChanged: {removeRules: (a, f) => f(), addRules: (a, f) => f()}},
              scripting: {executeScript: async () => [{result: []}]},
            };
            """)
        context.evaluateScript(script)
        let read = { () -> [String: Any] in
            (context.evaluateScript("JSON.stringify(session['tab:7'] || {})").toString())
                .flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] } ?? [:]
        }
        return (context, read)
    }

    /// Clicks Lamp on a tab, then the tab starts loading `then` (nil: Chrome gave no address, as it does once access is gone).
    private func moved(after then: String?) throws -> Bool? {
        let (context, read) = try worker()
        context.evaluateScript("listeners.click({id: 7, url: 'https://www.example.com/recipes/pancakes'})")
        try waitFor { read()["at"] != nil }
        let tab = then.map { "{id: 7, url: '\($0)'}" } ?? "{id: 7}"
        context.evaluateScript("listeners.updated(7, {status: 'loading'}, \(tab))")
        try waitFor(seconds: 0.3) { false }
        return read()["moved"] as? Bool
    }

    private func waitFor(seconds: Double = 2, _ done: () -> Bool) throws {
        let end = Date().addingTimeInterval(seconds)
        while !done() && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    }

    func testAReloadOnTheSameSiteKeepsTheSidebarUsable() throws {
        XCTAssertNotEqual(try moved(after: "https://www.example.com/recipes/pancakes"), true)
        XCTAssertNotEqual(try moved(after: "https://www.example.com/recipes/waffles"), true)
    }

    func testAnotherSiteSaysTheTabMoved() throws {
        XCTAssertEqual(try moved(after: "https://news.example.org/today"), true)
        XCTAssertEqual(try moved(after: nil), true)
    }
}
