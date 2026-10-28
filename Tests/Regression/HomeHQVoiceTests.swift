import JavaScriptCore
import XCTest
@testable import Lamp

/// Home HQ's Ask (Resources/Starters/homehq/Web/js/agent.js), the panel floating over the page, with stand-ins for the
/// page, the app around it (`LampVoice`) and Lamp (`LampAI.hear`, `LampAI.act`): one press listens and that press can't
/// stop it; the remote stays in the panel and comes back to where it was; a question offers the AI's choices with the
/// first focused and listens again by itself, and its first answer, said or pressed, is the only one taken; nothing
/// heard, transcribed or answered after Ask closes is acted on; and where there's no voice, typing is there.
@MainActor
final class HomeHQVoiceTests: XCTestCase {
    private let agent = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Starters/homehq/Web/js/agent.js")

    private func page(voice: String = "{ listen: true, speak: true, permission: 'granted' }", hear: Bool = true) throws -> JSContext {
        let c = try XCTUnwrap(JSContext())
        c.exceptionHandler = { _, value in XCTFail(value?.toString() ?? "?") }
        c.evaluateScript("""
            var window = this, log = [], timers = [], clock = 1000, handlers = {}, backs = [];
            Date = (function (Real) { function Fake() { return new Real(clock); } Fake.now = function () { return clock; }; return Fake; })(Date);
            function setTimeout(fn) { timers.push(fn); return timers.length; } function clearTimeout(id) { if (id) timers[id - 1] = null; }
            function setInterval() { return 0; } function clearInterval() {}
            function run() { var t = timers; timers = []; t.forEach(function (f) { if (f) f(); }); }

            // A stand-in for the page: elements found by the data-ask-* attributes their HTML gives them.
            function el(tag, name) {
              var e = { tagName: tag, name: name, hidden: false, disabled: false, style: {}, children: [], kids: {}, listeners: {}, attrs: {},
                offsetParent: {}, className: '', parentNode: null,
                classList: { toggle: function () {}, add: function () {}, remove: function () {} },
                setAttribute: function (k, v) { e.attrs[k] = v; }, getAttribute: function (k) { return e.attrs[k]; },
                addEventListener: function (t, fn) { (e.listeners[t] = e.listeners[t] || []).push(fn); },
                fire: function (t, ev) { ev = ev || {}; ev.target = ev.target || e; ev.preventDefault = function () {}; ev.stopPropagation = function () {};
                  var at = e; while (at) { (at.listeners[t] || []).forEach(function (fn) { fn(ev); }); at = at.parentNode; } },
                focus: function () { document.activeElement = e; },
                closest: function (sel) { var at = e; while (at) { if (sel === '[data-ask-act]' && at.attrs['data-ask-act']) return at; at = at.parentNode; } return null; },
                contains: function (x) { while (x) { if (x === e) return true; x = x.parentNode; } return false; },
                appendChild: function (x) { x.parentNode = e; e.children.push(x); }, removeChild: function (x) { e.children.splice(e.children.indexOf(x), 1); x.parentNode = null; },
                querySelector: function (sel) { if (e.kids[sel]) return e.kids[sel]; for (var k in e.kids) { var f = e.kids[k].querySelector(sel); if (f) return f; } return null; },
                querySelectorAll: function () { var out = []; for (var k in e.kids) { var x = e.kids[k]; if (x.tagName === 'BUTTON' || x.tagName === 'INPUT') out.push(x); out = out.concat(x.querySelectorAll()); } return out; },
                set innerHTML(v) {
                  e._h = v; e.kids = {};
                  var re = /<(\\w+)[^>]*?(data-ask-[\\w-]+|data-meter)(?:="([^"]*)")?[^>]*>/g, m;
                  while ((m = re.exec(v))) {
                    var key = m[3] && m[2] === 'data-ask-act' ? '[data-ask-act="' + m[3] + '"]' : '[' + m[2] + ']';
                    var k = el(m[1].toUpperCase(), key); k.parentNode = e; if (m[3]) k.attrs[m[2]] = m[3];
                    if (/ hidden/.test(m[0])) k.hidden = true;
                    e.kids[key] = k;
                  }
                }, get innerHTML() { return e._h || ''; } };
              return e;
            }
            var stage = el('DIV', 'stage'), rail = el('DIV', 'rail'), askButton = el('BUTTON', 'rail-ask');
            var document = { hidden: false, activeElement: null, body: { contains: function (x) { return !!x; } },
              addEventListener: function (t, fn) { document['on' + t] = fn; },
              createElement: function (t) { return el(t.toUpperCase(), t); },
              getElementById: function (id) { return id === 'stage' ? stage : rail; },
              querySelector: function (s) { return s === '.rail-ask' ? askButton : null; } };
            var Lamp = { scope: null, onBack: function (fn) { backs.push(fn); return function () { backs.splice(backs.indexOf(fn), 1); }; } };
            function back() { for (var i = backs.length - 1; i >= 0; i--) if (backs[i]()) return true; return false; }
            function panel() { return stage.children[0] || null; }
            function q(sel) { return panel() && panel().querySelector(sel); }
            function buttons() { var a = q('[data-ask-acts]'); return a ? (a.innerHTML.match(/data-ask-act="[^"]+"/g) || []).map(function (s) { return s.slice(14, -1); }) : []; }
            function focusedKey() { var f = document.activeElement; return f && f.attrs && f.attrs['data-ask-act'] || (f && f.name) || ''; }
            function press(key) { q('[data-ask-act="' + key + '"]').fire('click'); }
            function now() { return (q('[data-ask-now]') || {}).innerHTML; }
            var DATA = { people: [], chores: [] };
            var App = { write: { addGrocery: {}, checkGrocery: {}, completeChore: {}, uncompleteChore: {}, addEvent: {} }, read: { people: function () { return []; } },
              on: function (e, fn) { handlers[e] = fn; }, emit: function () {}, rerender: function () {}, esc: function (s) { return String(s); }, icon: function () { return ''; },
              dayText: function () { return '2026-10-28'; }, now: function () { return new Date(); }, changesOf: function (t) { return t && t.changes || []; }, resetIdle: function () {},
              person: function () { return { name: 'x' }; } };
            var listenDone = null, hearDone = null, hears = [], actDone = null, acts = [], statusDone = null, speaks = [];
            var LampVoice = {
              status: function () { return \(voice == "held" ? "new Promise(function (r) { statusDone = r; })" : "Promise.resolve(\(voice))"); },
              listen: function (o) { log.push('listen:' + o.session); return new Promise(function (r) { listenDone = r; }); },
              stop: function (s) { log.push('stop:' + s); return Promise.resolve(); },
              cancel: function (s) { log.push('cancel:' + s); return Promise.resolve(); },
              speak: function (t) { log.push('speak'); return new Promise(function (r) { speaks.push(r); }); },
              hush: function () { return Promise.resolve(); }
            };
            var LampAI = {
              act: function (request) { acts.push(request); log.push('act'); var r; var p = new Promise(function (x) { r = x; });
                actDone = r; return { id: 't' + acts.length, result: p, cancel: function () { log.push('cancel turn'); } }; },
              hear: function (audio) { log.push('hear'); return new Promise(function (r) { hearDone = r; hears.push(r); }); },
              isAvailable: function (what) { return Promise.resolve(what === 'hear' ? \(hear) : true); },
              whenText: String, date: function (t) { return new Date(); }
            };
            // What each turn was asked: the words themselves, or for an answer to a question, the answer.
            function asked() { return acts.map(function (a) { var p = a.split('The person answered: "'); return p.length > 1 ? p[p.length - 1].split('"')[0] : a; }); }
            function answer(r) { var o = { done: [], failed: [], skipped: [], reply: '', ask: false, choices: [], turn: {} }; for (var k in r) o[k] = r[k]; actDone(o); }
            function spoken() { var s = speaks; speaks = []; s.forEach(function (r) { r(true); }); }
            """)
        c.evaluateScript(try String(contentsOf: agent, encoding: .utf8))
        c.evaluateScript("handlers.ready();")
        settle(c)
        return c
    }

    private func settle(_ c: JSContext) { for _ in 0..<20 { c.evaluateScript("0") } }
    private func value(_ c: JSContext, _ script: String) -> Any? {
        c.evaluateScript("JSON.stringify(\(script))")?.toString().flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8), options: .fragmentsAllowed) }
    }
    private func log(_ c: JSContext) -> [String] { value(c, "log") as? [String] ?? [] }
    private func str(_ c: JSContext, _ script: String) -> String? { c.evaluateScript(script)?.toString() }

    /// Ask open, a request heard, and the AI asking back with choices: the state most tests start from.
    private func asked(_ c: JSContext, choices: String = "['Yes', 'No']") {
        c.evaluateScript("document.activeElement = askButton; App.openAsk();")
        settle(c)
        c.evaluateScript("listenDone({ ended: 'quiet', audio: 'UklGRg==', seconds: 1.2, speech: true });")
        settle(c)
        c.evaluateScript("hearDone({ text: 'Add milk', nothing: false });")
        settle(c)
        c.evaluateScript("answer({ reply: 'Milk 2% is on the list already. Add one more?', ask: true, choices: \(choices) });")
        settle(c)
    }

    func testOnePressListensAndThatPressCannotAlsoStopIt() throws {
        let c = try page()
        c.evaluateScript("App.openAsk();")
        settle(c)
        XCTAssertEqual(log(c), ["listen:ask1-1"])
        XCTAssertEqual(str(c, "focusedKey()"), "mic")
        // The opening OK coming up, or repeating, on the Stop that just took focus: ignored.
        c.evaluateScript("press('mic'); clock += 300; press('mic');")
        XCTAssertFalse(log(c).contains { $0.hasPrefix("stop") })
        c.evaluateScript("clock += 800; press('mic');")
        XCTAssertEqual(log(c).last, "stop:ask1-1")
    }

    func testTheRemoteStaysInThePanelAndComesBackWhereItWas() throws {
        let c = try page()
        c.evaluateScript("document.activeElement = askButton; App.openAsk();")
        settle(c)
        XCTAssertTrue(c.evaluateScript("Lamp.scope === panel()")?.toBool() == true)
        XCTAssertTrue(c.evaluateScript("App.askOpen()")?.toBool() == true, "the page's own shortcuts wait while it's open")
        c.evaluateScript("back();")
        settle(c)
        XCTAssertTrue(c.evaluateScript("Lamp.scope === null && panel() === null && document.activeElement === askButton")?.toBool() == true)
        XCTAssertTrue(c.evaluateScript("App.askOpen()")?.toBool() == false)
    }

    func testWhatIsSaidIsHeardThenDoneAndClosesOnlyAfterItIsReadOut() throws {
        let c = try page()
        c.evaluateScript("App.openAsk();")
        settle(c)
        c.evaluateScript("listenDone({ ended: 'quiet', audio: 'UklGRg==', seconds: 1.4, speech: true });")
        settle(c)
        c.evaluateScript("hearDone({ text: 'Add milk', nothing: false });")
        settle(c)
        XCTAssertEqual(log(c), ["listen:ask1-1", "hear", "act"])
        XCTAssertEqual(str(c, "acts[0]"), "Add milk")
        c.evaluateScript("answer({ reply: 'Added.', done: [{ name: 'addGrocery', args: { name: 'Milk' }, result: { item: { name: 'Milk' } } }] });")
        settle(c)
        XCTAssertEqual(str(c, "now()"), "Added Milk.")
        // Still open while it's read out; then it closes by itself.
        c.evaluateScript("run();")
        XCTAssertNotNil(value(c, "panel() && 1"))
        c.evaluateScript("spoken();")
        settle(c)
        c.evaluateScript("run();")
        XCTAssertTrue(c.evaluateScript("panel() === null")?.toBool() == true)
    }

    func testAQuestionOffersItsChoicesFocusedAndListensAgainByItself() throws {
        let c = try page()
        asked(c)
        XCTAssertEqual(value(c, "buttons()") as? [String], ["choice:0", "choice:1", "mic", "type"])
        XCTAssertEqual(str(c, "focusedKey()"), "choice:0")
        // Not before the question has been read out to the end.
        c.evaluateScript("run();")
        XCTAssertEqual(log(c).filter { $0.hasPrefix("listen") }.count, 1)
        c.evaluateScript("spoken();")
        settle(c)
        c.evaluateScript("run();")
        settle(c)
        XCTAssertEqual(log(c).filter { $0.hasPrefix("listen") }.count, 2)
        // Listening again leaves focus on Yes.
        XCTAssertEqual(str(c, "focusedKey()"), "choice:0")
        // It never closes by itself while the question waits.
        c.evaluateScript("run();")
        XCTAssertNotNil(value(c, "panel() && 1"))
    }

    func testPressingAChoiceTakesTheAnswerAndDropsWhatWasBeingHeard() throws {
        let c = try page()
        asked(c)
        c.evaluateScript("spoken();")
        settle(c)
        c.evaluateScript("run();")
        settle(c)
        c.evaluateScript("var tag = log.filter(function (l) { return l.indexOf('listen') === 0; })[1].slice(7); clock += 1000; press('choice:0');")
        settle(c)
        XCTAssertEqual(value(c, "asked()") as? [String], ["Add milk", "Yes"])
        XCTAssertTrue(log(c).contains("cancel:" + (str(c, "tag") ?? "?")))
        // What the microphone had, coming back late, is never a second answer.
        c.evaluateScript("listenDone({ ended: 'quiet', audio: 'UklGRg==', seconds: 1, speech: true });")
        settle(c)
        XCTAssertEqual(value(c, "acts.length") as? Int, 2)
        XCTAssertEqual(log(c).filter { $0 == "hear" }.count, 1)
    }

    func testASaidAnswerTakesItAndAButtonAfterDoesNothing() throws {
        let c = try page()
        asked(c)
        c.evaluateScript("spoken();")
        settle(c)
        c.evaluateScript("run();")
        settle(c)
        c.evaluateScript("var yes = q('[data-ask-act=\"choice:0\"]'); listenDone({ ended: 'quiet', audio: 'UklGRg==', seconds: 0.8, speech: true });")
        settle(c)
        c.evaluateScript("hearDone({ text: 'yes', nothing: false });")
        settle(c)
        XCTAssertEqual(value(c, "asked()") as? [String], ["Add milk", "yes"])
        // The Yes still on screen a moment before, pressed now: the question is answered, nothing more happens.
        c.evaluateScript("clock += 1000; yes.fire('click');")
        settle(c)
        XCTAssertEqual(value(c, "acts.length") as? Int, 2)
    }

    func testAHeldOrRepeatedOKNeverPressesTheNewlyFocusedChoice() throws {
        let c = try page()
        asked(c)
        c.evaluateScript("press('choice:0'); clock += 300; press('choice:0');")
        settle(c)
        XCTAssertEqual(value(c, "acts.length") as? Int, 1)
        c.evaluateScript("clock += 800; press('choice:1');")
        settle(c)
        XCTAssertEqual(value(c, "asked()") as? [String], ["Add milk", "No"])
    }

    func testSilenceKeepsTheQuestionAndItsButtons() throws {
        let c = try page()
        asked(c)
        c.evaluateScript("spoken();")
        settle(c)
        c.evaluateScript("run();")
        settle(c)
        c.evaluateScript("listenDone({ ended: 'nothing', seconds: 6, peak: 0.002, speech: false });")
        settle(c)
        XCTAssertEqual(value(c, "buttons()") as? [String], ["choice:0", "choice:1", "mic", "type"])
        XCTAssertEqual(str(c, "now()"), "Milk 2% is on the list already. Add one more?")
        c.evaluateScript("clock += 1000; press('choice:0');")
        settle(c)
        XCTAssertEqual(value(c, "asked()") as? [String], ["Add milk", "Yes"])
    }

    func testAQuestionWithoutChoicesIsAnsweredByVoiceOrTyping() throws {
        let c = try page()
        asked(c, choices: "[]")
        XCTAssertEqual(value(c, "buttons()") as? [String], ["mic", "type"])
        XCTAssertEqual(str(c, "focusedKey()"), "mic")
        c.evaluateScript("spoken();")
        settle(c)
        c.evaluateScript("run();")
        settle(c)
        XCTAssertEqual(log(c).filter { $0.hasPrefix("listen") }.count, 2)
        XCTAssertEqual(str(c, "focusedKey()"), "mic")
    }

    func testAFailureNeverClosesByItself() throws {
        let c = try page()
        c.evaluateScript("App.openAsk();")
        settle(c)
        c.evaluateScript("listenDone({ ended: 'quiet', audio: 'UklGRg==' });")
        settle(c)
        c.evaluateScript("hearDone({ text: 'Add milk', nothing: false });")
        settle(c)
        c.evaluateScript("answer({ reply: 'I could not.', failed: [{ name: 'addGrocery', args: { name: 'Milk' }, reason: 'Not that.' }] });")
        settle(c)
        c.evaluateScript("spoken();")
        settle(c)
        c.evaluateScript("run(); run();")
        XCTAssertNotNil(value(c, "panel() && 1"))
        XCTAssertEqual(value(c, "buttons()") as? [String], ["mic", "type", "close"])
    }

    func testClosingDuringTheRecordingOrTheTranscriptionActsOnNothing() throws {
        let c = try page()
        c.evaluateScript("App.openAsk();")
        settle(c)
        c.evaluateScript("back(); listenDone({ ended: 'quiet', audio: 'UklGRg==' });")
        settle(c)
        XCTAssertEqual(log(c), ["listen:ask1-1", "cancel:ask1-1"])
        c.evaluateScript("log = []; App.openAsk();")
        settle(c)
        c.evaluateScript("listenDone({ ended: 'quiet', audio: 'UklGRg==' });")
        settle(c)
        c.evaluateScript("back(); hearDone({ text: 'Add milk', nothing: false });")
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
        XCTAssertTrue((str(c, "now()") ?? "").contains("shorter"))
    }

    func testWithNoVoiceTypingIsThereAndNothingListens() throws {
        let c = try page(voice: "{ listen: false, speak: false, permission: 'none' }")
        c.evaluateScript("App.openAsk();")
        settle(c)
        XCTAssertEqual(log(c), [])
        XCTAssertEqual(c.evaluateScript("q('[data-ask-form]').hidden")?.toBool(), false)
        XCTAssertEqual(str(c, "focusedKey()"), "[data-ask-input]")
    }

    func testWithAMicrophoneButNoTranscriptionTypingIsThere() throws {
        let c = try page(hear: false)
        c.evaluateScript("App.openAsk();")
        settle(c)
        XCTAssertEqual(log(c), [])
        XCTAssertEqual(c.evaluateScript("q('[data-ask-form]').hidden")?.toBool(), false)
    }

    func testTypingDropsATranscriptionStillOnItsWay() throws {
        let c = try page()
        c.evaluateScript("App.openAsk();")
        settle(c)
        c.evaluateScript("listenDone({ ended: 'quiet', audio: 'UklGRg==', seconds: 1.4, speech: true });")
        settle(c)
        // While "Add milk" is being worked out, the person types something else, and that turn finishes.
        c.evaluateScript("""
            clock += 1000; press('type');
            q('[data-ask-input]').value = 'Mark the dishes done'; q('[data-ask-form]').fire('submit');
            """)
        settle(c)
        c.evaluateScript("answer({ reply: 'Done.' });")
        settle(c)
        c.evaluateScript("hearDone({ text: 'Add milk', nothing: false });")
        settle(c)
        XCTAssertEqual(str(c, "JSON.stringify(acts)"), #"["Mark the dishes done"]"#)
    }

    func testAnOlderRecordingsTranscriptIsDroppedOnceAnotherHasStarted() throws {
        let c = try page()
        c.evaluateScript("App.openAsk();")
        settle(c)
        c.evaluateScript("listenDone({ ended: 'quiet', audio: 'UklGRg==', seconds: 1.4, speech: true });")
        settle(c)
        // Talk again while the first is still being worked out; the first's words come back during the second.
        c.evaluateScript("clock += 1000; press('mic');")
        settle(c)
        c.evaluateScript("hears[0]({ text: 'Add milk', nothing: false });")
        settle(c)
        XCTAssertEqual(c.evaluateScript("acts.length")?.toInt32(), 0)
        c.evaluateScript("listenDone({ ended: 'quiet', audio: 'UklGRg==', seconds: 1.1, speech: true });")
        settle(c)
        c.evaluateScript("hears[1]({ text: 'Add eggs', nothing: false });")
        settle(c)
        XCTAssertEqual(str(c, "JSON.stringify(acts)"), #"["Add eggs"]"#)
    }

    func testAskOpenedBeforeTheVoiceAnswersStillListens() throws {
        let c = try page(voice: "held")
        c.evaluateScript("App.openAsk();")
        settle(c)
        c.evaluateScript("statusDone({ listen: true, speak: true, permission: 'granted' });")
        settle(c)
        XCTAssertEqual(log(c), ["listen:ask1-1"])
    }

    func testBackBeforeTheVoiceAnswersLeavesAskClosed() throws {
        let c = try page(voice: "held")
        c.evaluateScript("App.openAsk(); back();")
        settle(c)
        c.evaluateScript("statusDone({ listen: true, speak: true, permission: 'granted' });")
        settle(c)
        c.evaluateScript("run();")
        settle(c)
        XCTAssertEqual(log(c).filter { $0.hasPrefix("listen") }, [])
        XCTAssertTrue(c.evaluateScript("panel() === null")?.toBool() == true)
    }

    func testHidingClosesAskAndStartsNothingLater() throws {
        let c = try page(voice: "held")
        c.evaluateScript("App.openAsk(); document.hidden = true; document.onvisibilitychange();")
        settle(c)
        c.evaluateScript("statusDone({ listen: true, speak: true, permission: 'granted' });")
        settle(c)
        c.evaluateScript("document.hidden = false; run();")
        settle(c)
        XCTAssertEqual(log(c).filter { $0.hasPrefix("listen") }, [])
        XCTAssertTrue(c.evaluateScript("panel() === null")?.toBool() == true)
    }

    /// After an answer, focus goes to what comes next: Undo when something changed, Talk otherwise, never left on the
    /// Close that stood alone while it was thinking.
    func testAfterAnAnswerFocusIsOnUndoOrTalk() throws {
        let c = try page()
        c.evaluateScript("App.openAsk();")
        settle(c)
        c.evaluateScript("listenDone({ ended: 'quiet', audio: 'UklGRg==' });")
        settle(c)
        c.evaluateScript("hearDone({ text: 'Add milk', nothing: false });")
        settle(c)
        XCTAssertEqual(str(c, "focusedKey()"), "close")
        c.evaluateScript("answer({ reply: 'Added.', done: [{ name: 'addGrocery', args: { name: 'Milk' }, result: { item: { name: 'Milk' } } }], turn: { changes: [1] } });")
        settle(c)
        XCTAssertEqual(str(c, "focusedKey()"), "undo")
        c.evaluateScript("clock += 1000; press('mic');")
        settle(c)
        c.evaluateScript("listenDone({ ended: 'quiet', audio: 'UklGRg==' });")
        settle(c)
        c.evaluateScript("hearDone({ text: 'What is on today', nothing: false });")
        settle(c)
        c.evaluateScript("answer({ reply: 'Soccer at 4.' });")
        settle(c)
        XCTAssertEqual(str(c, "focusedKey()"), "mic")
    }
}
