import JavaScriptCore
import XCTest
@testable import Lamp

/// `LampAI.act` in lamp.js, the page's half of an app's agent loop, against a stand-in for Lamp that answers each
/// `/ai/act` step from a script: these are the answers a model can't be relied on to give (a write asked twice, a step
/// over the limit, an answer after a cancel), so the page's own guarantees are tested without one.
@MainActor
final class ActLoopTests: XCTestCase {
    private func page() throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        context.exceptionHandler = { _, value in XCTFail(value?.toString() ?? "?") }
        context.evaluateScript("""
            var window = this, log = [], requests = [], answers = [], held = null, timers = [], store = {};
            var console = { error: function () {}, log: function () {} };
            window.addEventListener = function () {}; window.removeEventListener = function () {};
            var navigator = {}, document = { addEventListener: function () {} };
            window.localStorage = { getItem: function (k) { return k in store ? store[k] : null; }, setItem: function (k, v) { store[k] = String(v); }, removeItem: function (k) { delete store[k]; } };
            function setTimeout(fn) { timers.push(fn); return timers.length; } function clearTimeout() {}
            function setInterval() { return 0; } function clearInterval() {}
            window.webkit = { messageHandlers: { lampGateway: { postMessage: function (m) {
              requests.push({ path: m.path, body: JSON.parse(m.body) });
              var a = answers.shift();
              if (a === 'hold') return new Promise(function (r) { held = function (x) { r({ status: 200, body: JSON.stringify(x) }); }; });
              if (!a) a = { reply: 'Done.' };
              return Promise.resolve({ status: a.status || 200, body: JSON.stringify(a.status ? { error: a.error } : a) });
            } } } };
            """)
        context.evaluateScript(DeviceSupport.webJS)
        context.evaluateScript("""
            var list = [];
            var tools = {
              groceries: { reads: true, args: {}, run: function () { log.push('read'); return list.slice(); } },
              add: { args: { name: { type: 'string' } },
                     check: function (a) { log.push('check:' + a.name); return a.name === 'nope' ? 'Not that.' : null; },
                     run: function (a, call) { log.push('run:' + a.name); list.push(a.name); return { added: a.name, key: call.key }; } }
            };
            var outcome = null;
            function go(request, extra) {
              var o = { tools: tools }; for (var k in extra || {}) o[k] = extra[k];
              var t = LampAI.act(request, o); t.result.then(function (r) { outcome = r; }); return t;
            }
            function call(id, name, args) { return { id: id, name: name, args: args || {} }; }
            """)
        return context
    }

    private func settle(_ context: JSContext) { for _ in 0..<20 { context.evaluateScript("0") } }
    private func value(_ context: JSContext, _ script: String) -> Any? { context.evaluateScript("JSON.stringify(\(script))")?.toString().flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8), options: .fragmentsAllowed) } }
    private func log(_ context: JSContext) -> [String] { value(context, "log") as? [String] ?? [] }

    func testReadsComeFirstThenEachWriteIsCheckedRightBeforeItRuns() throws {
        let c = try page()
        c.evaluateScript("answers = [{ calls: [call('s1c1', 'add', { name: 'milk' }), call('s1c2', 'groceries'), call('s1c3', 'add', { name: 'eggs' })] }, { reply: 'Added milk and eggs.' }]; go('Add milk and eggs');")
        settle(c)
        XCTAssertEqual(log(c), ["read", "check:milk", "run:milk", "check:eggs", "run:eggs"])
        XCTAssertEqual(value(c, "outcome.done.map(function (d) { return d.args.name; })") as? [String], ["milk", "eggs"])
        XCTAssertEqual(value(c, "outcome.reply") as? String, "Added milk and eggs.")
        // The second step carried what the first did, for the model to see.
        XCTAssertEqual(value(c, "requests[1].body.steps[0].results.map(function (r) { return r.ok; })") as? [Bool], [true, true, true])
    }

    func testAFailedWriteSkipsTheWritesAfterItAndSaysSo() throws {
        let c = try page()
        c.evaluateScript("answers = [{ calls: [call('s1c1', 'add', { name: 'nope' }), call('s1c2', 'add', { name: 'eggs' })] }, { reply: 'I could not.' }]; go('x');")
        settle(c)
        XCTAssertEqual(log(c), ["check:nope"])
        XCTAssertEqual(value(c, "outcome.failed[0].reason") as? String, "Not that.")
        XCTAssertEqual(value(c, "outcome.skipped[0].args.name") as? String, "eggs")
        XCTAssertEqual(value(c, "outcome.done.length") as? Int, 0)
        XCTAssertNotNil(value(c, "requests[1].body.steps[0].results[1].skipped") as? String)
    }

    func testTheSameWriteInATurnRunsOnceEvenWhenTheTurnIsTriedAgain() throws {
        let c = try page()
        c.evaluateScript("answers = [{ calls: [call('s1c1', 'add', { name: 'milk' })] }, { calls: [call('s2c1', 'add', { name: 'milk' })] }, { reply: 'Added.' }]; var first = go('Add milk', { turn: 't1' });")
        settle(c)
        XCTAssertEqual(log(c).filter { $0.hasPrefix("run:") }, ["run:milk"])
        XCTAssertEqual(value(c, "requests[2].body.steps[1].results[0].repeat") as? Bool, true)
        c.evaluateScript("answers = [{ calls: [call('s1c1', 'add', { name: 'milk' })] }, { reply: 'Added.' }]; go('Add milk', { turn: 't1' });")
        settle(c)
        XCTAssertEqual(log(c).filter { $0.hasPrefix("run:") }, ["run:milk"])
    }

    func testWritesOverTheLimitAreRefused() throws {
        let c = try page()
        c.evaluateScript("answers = [{ calls: [call('s1c1', 'add', { name: 'a' }), call('s1c2', 'add', { name: 'b' })] }]; go('x', { limits: { writes: 1 } });")
        settle(c)
        XCTAssertEqual(log(c).filter { $0.hasPrefix("run:") }, ["run:a"])
        XCTAssertTrue((value(c, "outcome.failed[0].reason") as? String ?? "").contains("limit"))
    }

    func testTheFourthStepIsAskedForAReplyOnly() throws {
        let c = try page()
        c.evaluateScript("answers = [{ calls: [call('s1c1', 'groceries')] }, { calls: [call('s2c1', 'groceries')] }, { calls: [call('s3c1', 'groceries')] }, { reply: 'Here.' }]; go('x');")
        settle(c)
        XCTAssertEqual(value(c, "requests.map(function (r) { return !!r.body.final; })") as? [Bool], [false, false, false, true])
        XCTAssertEqual(value(c, "outcome.reply") as? String, "Here.")
    }

    func testAnAnswerAfterACancelRunsNothing() throws {
        let c = try page()
        c.evaluateScript("answers = ['hold']; var t = go('Add milk');")
        settle(c)
        c.evaluateScript("t.cancel(); held({ calls: [call('s1c1', 'add', { name: 'milk' })] });")
        settle(c)
        XCTAssertEqual(log(c), [])
        XCTAssertEqual(value(c, "outcome.stopped") as? String, "cancelled")
    }

    func testAnAnswerAfterTheDeadlineRunsNothing() throws {
        let c = try page()
        c.evaluateScript("answers = ['hold']; go('Add milk');")
        settle(c)
        c.evaluateScript("timers.forEach(function (f) { f(); }); held({ calls: [call('s1c1', 'add', { name: 'milk' })] });")
        settle(c)
        XCTAssertEqual(log(c), [])
        XCTAssertEqual(value(c, "outcome.stopped") as? String, "time")
    }

    func testTheClockIsReadBeforeEachWriteNotOnlyTheTimer() throws {
        let c = try page()
        // A write slow enough to carry the turn past its deadline, before the deadline's timer has had its turn.
        c.evaluateScript("""
            var clock = Date.now(), realNow = Date.now; Date.now = function () { return clock; };
            tools.add.run = function (a) { log.push('run:' + a.name); clock += 30000; return { added: a.name }; };
            answers = [{ calls: [call('s1c1', 'add', { name: 'a' }), call('s1c2', 'add', { name: 'b' })] }]; go('x');
            """)
        settle(c)
        XCTAssertEqual(log(c).filter { $0.hasPrefix("run:") }, ["run:a"])
        XCTAssertEqual(value(c, "outcome.stopped") as? String, "time")
        XCTAssertEqual(value(c, "timers.length") as? Int, 1, "the deadline's timer never ran")
    }

    func testAnAnswerTakenAfterTheClockPassedTheDeadlineRunsNothing() throws {
        let c = try page()
        c.evaluateScript("var clock = Date.now(); Date.now = function () { return clock; }; answers = ['hold']; go('Add milk');")
        settle(c)
        c.evaluateScript("clock += 26000; held({ calls: [call('s1c1', 'add', { name: 'milk' })] });")
        settle(c)
        XCTAssertEqual(log(c), [])
        XCTAssertEqual(value(c, "outcome.stopped") as? String, "time")
    }

    func testTheTurnKeepsTheRouteTheFirstStepWasAnsweredBy() throws {
        let c = try page()
        c.evaluateScript("answers = [{ route: 'sonnet', calls: [call('s1c1', 'groceries')] }, { reply: 'Here.' }]; go('x');")
        settle(c)
        XCTAssertEqual(value(c, "requests[1].body.route") as? String, "sonnet")
    }

    func testActIsAvailableOnlyWhenTheHostAndLampBothTakeIt() throws {
        let c = try page()
        c.evaluateScript("var seen = []; answers = [{ status: 404, error: 'Not found' }, { act: false }, { act: true }];")
        c.evaluateScript("LampAI.isAvailable('act').then(function (v) { seen.push(v); }); 0")
        settle(c)
        c.evaluateScript("LampAI.isAvailable('act').then(function (v) { seen.push(v); }); 0")
        settle(c)
        c.evaluateScript("LampAI.isAvailable('act').then(function (v) { seen.push(v); }); 0")
        settle(c)
        XCTAssertEqual(value(c, "seen") as? [Bool], [false, false, true])
        XCTAssertEqual(value(c, "requests[0].path") as? String, "/ai/act")
    }

    /// A question back hands the page its choices as Lamp checked them, and checks them again: anything that isn't a
    /// short plain set on a question comes through as none.
    func testAQuestionsChoicesReachThePageOnlyAsAShortPlainSet() throws {
        let c = try page()
        c.evaluateScript("answers = [{ reply: 'Milk 2% is on the list. One more?', ask: true, choices: ['Yes', 'No'] }]; go('Add milk');")
        settle(c)
        XCTAssertEqual(value(c, "outcome.choices") as? [String], ["Yes", "No"])
        c.evaluateScript("outcome = null; answers = [{ reply: 'Added.', ask: false, choices: ['Yes', 'No'] }]; go('Add milk');")
        settle(c)
        XCTAssertEqual(value(c, "outcome.choices") as? [String], [])
        c.evaluateScript("outcome = null; answers = [{ reply: 'Which?', ask: true, choices: ['<b>Yes</b>', 'No'] }]; go('Add milk');")
        settle(c)
        XCTAssertEqual(value(c, "outcome.choices") as? [String], [])
    }
}
