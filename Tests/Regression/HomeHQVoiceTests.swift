import JavaScriptCore
import XCTest
@testable import Lamp

/// Home HQ's Ask (Resources/Starters/homehq/Web/js/agent.js) by voice, with stand-ins for the sheet, the app around the
/// page (`LampVoice`) and Lamp (`LampAI.hear`, `LampAI.act`): one press listens, the press that opened it can't stop it,
/// and nothing heard, transcribed or answered after Ask closes is acted on; a recording cut off at the limit isn't
/// acted on either; a transcription that a newer recording or typing has overtaken is dropped; and where there's no
/// voice, typing is there.
@MainActor
final class HomeHQVoiceTests: XCTestCase {
    private let agent = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Starters/homehq/Web/js/agent.js")

    private func page(voice: String = "{ listen: true, speak: true, permission: 'granted' }", hear: Bool = true) throws -> JSContext {
        let c = try XCTUnwrap(JSContext())
        c.exceptionHandler = { _, value in XCTFail(value?.toString() ?? "?") }
        c.evaluateScript("""
            var window = this, log = [], timers = [], clock = 1000, lines = [], focused = '', handlers = {}, sheet = null;
            Date = (function (Real) { function Fake() { return new Real(clock); } Fake.now = function () { return clock; }; return Fake; })(Date);
            function setTimeout(fn) { timers.push(fn); return timers.length; } function clearTimeout(id) { if (id) timers[id - 1] = null; }
            function setInterval() { return 0; } function clearInterval() {}
            function el(name) {
              var e = { name: name, hidden: false, disabled: false, style: {}, children: [], listeners: {},
                classList: { add: function () {}, remove: function () {}, toggle: function () {} },
                addEventListener: function (t, fn) { (e.listeners[t] = e.listeners[t] || []).push(fn); },
                fire: function (t, ev) { (e.listeners[t] || []).forEach(function (fn) { fn(ev || { preventDefault: function () {} }); }); },
                focus: function () { focused = name; }, appendChild: function (d) { lines.push(d.innerHTML); },
                querySelector: function (s) { return registry[s] || (registry[s] = el(s)); }, set innerHTML(v) { this._h = v; }, get innerHTML() { return this._h; } };
              return e;
            }
            var registry = {};
            var document = { hidden: false, addEventListener: function (t, fn) { document['on' + t] = fn; }, createElement: function () { return el('line'); }, getElementById: function () { return el('rail'); } };
            var DATA = { people: [], chores: [] };
            var App = { write: { addGrocery: {}, checkGrocery: {}, completeChore: {}, uncompleteChore: {}, addEvent: {} }, read: { people: function () { return []; } },
              on: function (e, fn) { handlers[e] = fn; }, emit: function () {}, rerender: function () {}, esc: function (s) { return s; }, icon: function () { return ''; },
              dayText: function () { return '2026-10-28'; }, now: function () { return new Date(); }, changesOf: function () { return []; }, resetIdle: function () {},
              person: function () { return { name: 'x' }; },
              sheet: function (html, o) { registry = {}; sheet = o; var s = el('sheet'); s.innerHTML = html; registry['[data-ask-form]'] = el('form'); if (html.indexOf('data-ask-form hidden') > -1) registry['[data-ask-form]'].hidden = true; o.onMount(s, function () { o.onClose(); }); } };
            var listenDone = null, hearDone = null, hears = [], actDone = null, acts = [], statusDone = null;
            var LampVoice = {
              status: function () { return \(voice == "held" ? "new Promise(function (r) { statusDone = r; })" : "Promise.resolve(\(voice))"); },
              listen: function (o) { log.push('listen:' + o.session); return new Promise(function (r) { listenDone = r; }); },
              stop: function (s) { log.push('stop:' + s); return Promise.resolve(); },
              cancel: function (s) { log.push('cancel:' + s); return Promise.resolve(); },
              speak: function (t) { log.push('speak'); return Promise.resolve(true); },
              hush: function () { return Promise.resolve(); }
            };
            var LampAI = {
              act: function (request) { acts.push(request); log.push('act'); var r; var p = new Promise(function (x) { r = x; });
                actDone = r; return { id: 't' + acts.length, result: p, cancel: function () { log.push('cancel turn'); } }; },
              hear: function (audio) { log.push('hear'); return new Promise(function (r) { hearDone = r; hears.push(r); }); },
              isAvailable: function (what) { return Promise.resolve(what === 'hear' ? \(hear) : true); },
              whenText: String, date: function (t) { return new Date(); }
            };
            """)
        c.evaluateScript(try String(contentsOf: agent, encoding: .utf8))
        c.evaluateScript("handlers.ready();")
        settle(c)
        return c
    }

    private func settle(_ c: JSContext) { for _ in 0..<20 { c.evaluateScript("0") } }
    private func log(_ c: JSContext) -> [String] { (c.evaluateScript("JSON.stringify(log)")?.toString()).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String] } ?? [] }

    func testOnePressListensAndThatPressCannotAlsoStopIt() throws {
        let c = try page()
        c.evaluateScript("App.openAsk();")
        settle(c)
        XCTAssertEqual(log(c), ["listen:ask1-1"])
        XCTAssertEqual(c.evaluateScript("focused")?.toString(), "[data-ask-stop]")
        // The opening OK coming up, or repeating, on the Stop that just took focus: ignored.
        c.evaluateScript("registry['[data-ask-stop]'].fire('click'); clock += 300; registry['[data-ask-stop]'].fire('click');")
        XCTAssertFalse(log(c).contains { $0.hasPrefix("stop") })
        c.evaluateScript("clock += 800; registry['[data-ask-stop]'].fire('click');")
        XCTAssertEqual(log(c).last, "stop:ask1-1")
    }

    func testWhatIsSaidIsHeardThenDone() throws {
        let c = try page()
        c.evaluateScript("App.openAsk();")
        settle(c)
        c.evaluateScript("listenDone({ ended: 'quiet', audio: 'UklGRg==', seconds: 1.4, speech: true });")
        settle(c)
        c.evaluateScript("hearDone({ text: 'Add milk', nothing: false });")
        settle(c)
        XCTAssertEqual(log(c), ["listen:ask1-1", "hear", "act"])
        XCTAssertEqual(c.evaluateScript("acts[0]")?.toString(), "Add milk")
    }

    func testClosingDuringTheRecordingOrTheTranscriptionActsOnNothing() throws {
        let c = try page()
        c.evaluateScript("App.openAsk();")
        settle(c)
        c.evaluateScript("sheet.onClose(); listenDone({ ended: 'quiet', audio: 'UklGRg==' });")
        settle(c)
        XCTAssertEqual(log(c), ["listen:ask1-1", "cancel:ask1-1"])
        c.evaluateScript("log = []; App.openAsk();")
        settle(c)
        c.evaluateScript("listenDone({ ended: 'quiet', audio: 'UklGRg==' });")
        settle(c)
        c.evaluateScript("sheet.onClose(); hearDone({ text: 'Add milk', nothing: false });")
        settle(c)
        XCTAssertEqual(log(c).filter { $0 == "act" }, [])
    }

    func testARecordingCutOffAtTheLimitIsNotActedOn() throws {
        let c = try page()
        c.evaluateScript("App.openAsk();")
        settle(c)
        c.evaluateScript("listenDone({ ended: 'cap', audio: 'UklGRg==', seconds: 15, speech: true });")
        settle(c)
        XCTAssertEqual(log(c), ["listen:ask1-1"])
        XCTAssertTrue((c.evaluateScript("JSON.stringify(lines)")?.toString() ?? "").contains("shorter"))
    }

    func testWithNoVoiceTypingIsThereAndNothingListens() throws {
        let c = try page(voice: "{ listen: false, speak: false, permission: 'none' }")
        c.evaluateScript("App.openAsk();")
        settle(c)
        XCTAssertEqual(log(c), [])
        XCTAssertEqual(c.evaluateScript("registry['[data-ask-form]'].hidden")?.toBool(), false)
        XCTAssertEqual(c.evaluateScript("focused")?.toString(), "[data-ask-input]")
    }

    func testWithAMicrophoneButNoTranscriptionTypingIsThere() throws {
        let c = try page(hear: false)
        c.evaluateScript("App.openAsk();")
        settle(c)
        XCTAssertEqual(log(c), [])
        XCTAssertEqual(c.evaluateScript("registry['[data-ask-form]'].hidden")?.toBool(), false)
    }

    func testTypingInsteadDropsATranscriptionStillOnItsWay() throws {
        let c = try page()
        c.evaluateScript("App.openAsk();")
        settle(c)
        c.evaluateScript("listenDone({ ended: 'quiet', audio: 'UklGRg==', seconds: 1.4, speech: true });")
        settle(c)
        // While "Add milk" is being worked out, the person types something else, and that turn finishes.
        c.evaluateScript("""
            registry['[data-ask-type]'].fire('click');
            registry['[data-ask-input]'].value = 'Mark the dishes done'; registry['[data-ask-form]'].fire('submit');
            """)
        settle(c)
        c.evaluateScript("actDone({ done: [], failed: [], skipped: [], reply: 'Done.', turn: {} });")
        settle(c)
        c.evaluateScript("hearDone({ text: 'Add milk', nothing: false });")
        settle(c)
        XCTAssertEqual(c.evaluateScript("JSON.stringify(acts)")?.toString(), #"["Mark the dishes done"]"#)
    }

    func testAnOlderRecordingsTranscriptIsDroppedOnceAnotherHasStarted() throws {
        let c = try page()
        c.evaluateScript("App.openAsk();")
        settle(c)
        c.evaluateScript("listenDone({ ended: 'quiet', audio: 'UklGRg==', seconds: 1.4, speech: true });")
        settle(c)
        // Talk again while the first is still being worked out; the first's words come back during the second.
        c.evaluateScript("registry['[data-ask-talk]'].fire('click');")
        settle(c)
        c.evaluateScript("hears[0]({ text: 'Add milk', nothing: false });")
        settle(c)
        XCTAssertEqual(c.evaluateScript("acts.length")?.toInt32(), 0)
        c.evaluateScript("listenDone({ ended: 'quiet', audio: 'UklGRg==', seconds: 1.1, speech: true });")
        settle(c)
        c.evaluateScript("hears[1]({ text: 'Add eggs', nothing: false });")
        settle(c)
        XCTAssertEqual(c.evaluateScript("JSON.stringify(acts)")?.toString(), #"["Add eggs"]"#)
    }

    func testAskOpenedBeforeTheVoiceAnswersStillListens() throws {
        let c = try page(voice: "held")
        c.evaluateScript("App.openAsk();")
        settle(c)
        c.evaluateScript("statusDone({ listen: true, speak: true, permission: 'granted' });")
        settle(c)
        XCTAssertEqual(log(c), ["listen:ask1-1"])
    }
}
