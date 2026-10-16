import XCTest
import JavaScriptCore

/// Choosing an app's right-click item lets its page act on the page beside it only within 15 seconds of the click.
/// When the app's page is ready later than that (a slow start), the sidebar must say the choice didn't run and how to
/// run it again, not drop it quietly. Runs the extension's own sidebar.js with stand-ins for the page and Chrome.
final class BrowserMenuDeliveryTests: XCTestCase {
    /// Delivers a choice made `elapsed` ms before the app's page was ready; returns what the page was sent and the note.
    private func deliver(after elapsed: Int) throws -> (sent: Int, note: String) {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("experiments/browser-connector/extension/sidebar.js")
        let context = JSContext()!
        context.exceptionHandler = { _, error in XCTFail("sidebar.js threw: \(error?.toString() ?? "")") }
        context.evaluateScript("""
            var posted = [], clock = 1000000, els = {};
            Date.now = () => clock;
            const el = id => els[id] || (els[id] = {id, dataset: {}, hidden: false, textContent: '', children: [],
              style: {setProperty() {}, removeProperty() {}}, classList: {toggle() {}, add() {}, remove() {}},
              addEventListener() {}, append() {}, replaceChildren() {}, focus() {}, querySelectorAll: () => [],
              contentWindow: {postMessage: (message, origin) => posted.push([message, origin])}});
            var document = {getElementById: el, querySelector: s => el('query ' + s), createElement: t => el('new ' + Math.random()),
              addEventListener() {}, body: el('body'), activeElement: null};
            var window = {addEventListener() {}}, navigator = {userActivation: {isActive: false}}, location = {search: '?tab=7'};
            var setInterval = () => 0;
            var URLSearchParams = function (text) {
              const pairs = String(text).replace(/^[?#]/, '').split('&').filter(Boolean).map(p => p.split('='));
              this.get = key => (pairs.find(p => p[0] === key) || [])[1] ?? null;
            };
            var chrome = {runtime: {sendMessage: async () => ({})},
              storage: {session: {get: async () => ({}), set: async () => {}, onChanged: {addListener() {}}}}};
            """)
        context.evaluateScript(try String(contentsOf: source, encoding: .utf8))
        settle(context)
        context.evaluateScript("""
            apps = [{id: 'plainwords', name: 'Plain Words', menu: 'Explain in Plain Words'}];
            framed = 'plainwords'; frameReady = true; pageToken = 'proved';
            el('page').dataset.origin = 'http://plainwords.localhost:52100';
            info = {menu: {app: 'plainwords', at: clock, url: 'https://en.wikipedia.org/wiki/Photosynthesis'}};
            clock += \(elapsed);
            var done = 0; deliverMenu().then(() => { done = 1; });
            """)
        settle(context) { context.evaluateScript("done").toInt32() == 1 }
        return (Int(context.evaluateScript("posted.length").toInt32()), context.evaluateScript("el('note').textContent").toString())
    }

    private func settle(_ context: JSContext, until done: () -> Bool = { false }) {
        let end = Date().addingTimeInterval(1)
        while !done() && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    }

    func testAChoiceInTimeReachesThePage() throws {
        let (sent, note) = try deliver(after: 1000)
        XCTAssertEqual(sent, 1)
        XCTAssertEqual(note, "")
    }

    func testAChoiceTooLateSaysSoAndHowToRunItAgain() throws {
        let (sent, note) = try deliver(after: 16000)
        XCTAssertEqual(sent, 0, "a late choice must not reach the page")
        XCTAssertTrue(note.contains("“Explain in Plain Words” didn’t run"), note)
        XCTAssertTrue(note.contains("choose it again"), note)
    }
}
