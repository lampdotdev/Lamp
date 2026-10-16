import XCTest
import JavaScriptCore

/// Chrome reports a right-click item it refused through `runtime.lastError` in `contextMenus.create`'s callback. The
/// worker keeps what it last registered so it doesn't register the same items again; a refused item must not count
/// as registered, or it stays missing until the app's fits change. Runs the extension's own worker.js with a stand-in
/// for Chrome's APIs that refuses, then accepts, and a clock the test moves.
final class BrowserMenuSyncTests: XCTestCase {
    private func worker() throws -> JSContext {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("experiments/browser-connector/extension/worker.js")
        let context = JSContext()!
        context.exceptionHandler = { _, error in XCTFail("worker.js threw: \(error?.toString() ?? "")") }
        context.evaluateScript("""
            var listeners = {}, installed = [], refuse = true, clock = 1000000;
            Date.now = () => clock;
            const event = name => ({addListener: f => { listeners[name] = f; }});
            const area = store => ({
              setAccessLevel: async () => {},
              get: async keys => { const out = {}; for (const k of [].concat(keys ?? Object.keys(store))) if (k in store) out[k] = store[k]; return out; },
              set: async values => { Object.assign(store, values); },
              remove: async keys => { for (const k of [].concat(keys)) delete store[k]; },
              onChanged: event('changed'),
            });
            var crypto = {randomUUID: () => 'id-' + Math.random()};
            var setInterval = () => 0;
            var chrome = {
              storage: {local: area({}), session: area({})},
              runtime: {id: 'x', getURL: p => 'chrome-extension://x/' + p, lastError: undefined,
                        connectNative: () => ({onMessage: event('port'), onDisconnect: event('gone'), postMessage: () => {}}),
                        onMessage: event('message'), onStartup: event('startup'), onInstalled: event('installed')},
              alarms: {create: () => {}, onAlarm: event('alarm')},
              action: {onClicked: event('click')},
              contextMenus: {onClicked: event('menu'),
                removeAll: done => { installed = []; done && done(); },
                create: (item, done) => {
                  if (refuse) chrome.runtime.lastError = {message: 'Refused.'}; else installed.push(item.title);
                  done && done(); chrome.runtime.lastError = undefined;
                }},
              sidePanel: {setOptions: () => {}, open: async () => {}},
              tabs: {onUpdated: event('updated'), onRemoved: event('removed'), get: async () => null},
              declarativeContent: {onPageChanged: {removeRules: (a, f) => f(), addRules: (a, f) => f()}},
              scripting: {executeScript: async () => [{result: []}]},
            };
            """)
        context.evaluateScript(try String(contentsOf: source, encoding: .utf8))
        return context
    }

    func testARefusedItemIsRegisteredOnceChromeTakesIt() throws {
        let context = try worker()
        context.evaluateScript("""
            var apps = [{id: 'plainwords', menu: 'Explain in Plain Words', fits: [{site: 'wikipedia.org'}]}], done = 0, soon;
            syncMenus(apps)
              .then(() => { refuse = false; clock += 1000; return syncMenus(apps); })
              .then(() => { soon = JSON.stringify(installed); clock += 30000; return syncMenus(apps); })
              .then(() => { done = 1; });
            """)
        let end = Date().addingTimeInterval(2)
        while context.evaluateScript("done").toInt32() == 0 && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertEqual(context.evaluateScript("done").toInt32(), 1)
        // Asked again within half a minute of the refusal, it waits; after that, Chrome takes it.
        XCTAssertEqual(context.evaluateScript("soon").toString(), "[]")
        XCTAssertEqual(context.evaluateScript("JSON.stringify(installed)").toString(), #"["Explain in Plain Words"]"#)
    }

    /// A replacement Chrome refuses leaves nothing registered (the old items went first), so going back to the old
    /// items must register them again, not find them in the cache.
    func testGoingBackAfterARefusedReplacementRegistersAgain() throws {
        let context = try worker()
        context.evaluateScript("""
            refuse = false;
            var a = [{id: 'plainwords', menu: 'Explain in Plain Words', fits: [{site: 'wikipedia.org'}]}];
            var b = [{id: 'plainwords', menu: 'Translate to Spanish', fits: [{site: 'wikipedia.org'}]}], done = 0;
            syncMenus(a)
              .then(() => { refuse = true; clock += 1000; return syncMenus(b); })
              .then(() => { refuse = false; clock += 31000; return syncMenus(a); })
              .then(() => { done = 1; });
            """)
        let end = Date().addingTimeInterval(2)
        while context.evaluateScript("done").toInt32() == 0 && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertEqual(context.evaluateScript("done").toInt32(), 1)
        XCTAssertEqual(context.evaluateScript("JSON.stringify(installed)").toString(), #"["Explain in Plain Words"]"#)
    }
}
