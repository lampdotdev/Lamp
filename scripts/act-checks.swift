import Foundation

// The native `LampActSession` from LampSupport.swift, against a stand-in for Lamp that answers each `/ai/act` step from
// a script: the answers a model can't be relied on to give (a change asked twice, an answer after a cancel, a second
// answer to one question), so the app's own guarantees are checked without one. Run by scripts/check-act.sh.

@MainActor
final class Lamp {
    var answers: [[String: Any]] = []
    var bodies: [[String: Any]] = []
    /// When set, the next step waits here until it's let go.
    var hold: CheckedContinuation<Void, Never>?
    var holdNext = false

    func send(_ body: [String: Any], _ timeout: TimeInterval) async throws -> [String: Any] {
        bodies.append(body)
        if holdNext {
            holdNext = false
            await withCheckedContinuation { hold = $0 }
        }
        return answers.isEmpty ? ["reply": "Done."] : answers.removeFirst()
    }

    func release() { let h = hold; hold = nil; h?.resume() }
}

struct Add: Decodable { let name: String }

@MainActor
final class Groceries {
    var list: [String] = []
    var log: [String] = []
    var slow: CheckedContinuation<Void, Never>?
    var slowNext = false

    var tools: [LampActTool] {
        [
            .read("items", "The list.") { self.log.append("read"); return self.list },
            .write("add", "Adds an item.", args: ["name": .text("What to add")], as: Add.self,
                   check: { add, _ in self.log.append("check:\(add.name)"); return add.name == "gone" ? "That item isn't there any more." : nil },
                   run: { add, call in
                       if self.slowNext { self.slowNext = false; await withCheckedContinuation { self.slow = $0 } }
                       self.log.append("run:\(add.name)")
                       self.list.append(add.name)
                       return LampActReceipt("Added \(add.name)", details: ["key": call.key])
                   }),
        ]
    }
}

func call(_ id: String, _ name: String, _ args: [String: Any] = [:]) -> [String: Any] { ["id": id, "name": name, "args": args] }

var failures = 0
func expect(_ ok: Bool, _ what: String, line: Int = #line) {
    print(ok ? "✓ \(what)" : "✗ \(what) (line \(line))")
    if !ok { failures += 1 }
}

@MainActor
func settle() async { for _ in 0..<50 { await Task.yield() } }

@main
struct Checks {
    @MainActor static func main() async {
        // Reads run first; each change is checked right before it runs; what's said comes from the receipts.
        do {
            let lamp = Lamp(), app = Groceries()
            lamp.answers = [["calls": [call("c1", "add", ["name": "milk"]), call("c2", "items"), call("c3", "add", ["name": "eggs"])]],
                            ["reply": "I added milk, eggs and bread."]]
            let session = LampActSession(tools: app.tools, send: lamp.send)
            let result = await session.ask("add milk and eggs").result
            expect(app.log == ["read", "check:milk", "run:milk", "check:eggs", "run:eggs"], "reads first, then each change checked right before it runs")
            expect(result.done.map(\.receipt.summary) == ["Added milk", "Added eggs"], "done comes from the tools' receipts")
            expect(result.summary == "Added milk\nAdded eggs", "the summary is the receipts, not the AI's claim of bread")
            let steps = lamp.bodies.last?["steps"] as? [[String: Any]]
            let oks = (steps?.first?["results"] as? [[String: Any]])?.compactMap { $0["ok"] as? Bool }
            expect(oks == [true, true, true], "the next step carries every result to the AI")
        }

        // A stale id is refused by the app's check before anything runs, and the rest of that step is skipped.
        do {
            let lamp = Lamp(), app = Groceries()
            lamp.answers = [["calls": [call("c1", "add", ["name": "gone"]), call("c2", "add", ["name": "eggs"])]], ["reply": "Done."]]
            let result = await LampActSession(tools: app.tools, send: lamp.send).ask("add the old one and eggs").result
            expect(!app.log.contains("run:gone"), "a change its check refuses never runs")
            expect(!app.log.contains("check:eggs") && !app.log.contains("run:eggs"), "the changes after a refused one in its step are skipped")
            expect(result.failed.map(\.reason) == ["That item isn't there any more."], "the refusal is reported with the app's own reason")
            expect(result.skipped.count == 1, "the skipped change is reported")
            expect(app.list.isEmpty, "nothing changed")
        }

        // An argument the tool didn't declare, or one it needs left out, is refused before its check.
        do {
            let lamp = Lamp(), app = Groceries()
            lamp.answers = [["calls": [call("c1", "add", ["name": "milk", "url": "http://example.com"])]], ["calls": [call("c2", "add")]], ["reply": "No."]]
            let result = await LampActSession(tools: app.tools, send: lamp.send).ask("add milk").result
            expect(app.log.isEmpty, "a call with an undeclared or missing argument isn't checked or run")
            expect(result.failed.count == 2, "both are reported as failed")
        }

        // The same change delivered twice in a request runs once; the second gets the first's result.
        do {
            let lamp = Lamp(), app = Groceries()
            lamp.answers = [["calls": [call("c1", "add", ["name": "milk"])]], ["calls": [call("c2", "add", ["name": "milk"])]], ["reply": "Added."]]
            let result = await LampActSession(tools: app.tools, send: lamp.send).ask("add milk").result
            expect(app.list == ["milk"], "a duplicate delivery doesn't repeat the change")
            let second = ((lamp.bodies.last?["steps"] as? [[String: Any]])?.last?["results"] as? [[String: Any]])?.first
            expect(second?["repeat"] as? Bool == true, "the AI hears it was a repeat")
            expect(result.done.count == 1, "one receipt")
        }

        // Cancelling while a change runs keeps that change's receipt and stops everything after it.
        do {
            let lamp = Lamp(), app = Groceries()
            lamp.answers = [["calls": [call("c1", "add", ["name": "milk"]), call("c2", "add", ["name": "eggs"])]], ["reply": "Done."]]
            app.slowNext = true
            let session = LampActSession(tools: app.tools, send: lamp.send)
            let turn = session.ask("add milk and eggs")
            await settle()
            turn.cancel()
            app.slow?.resume()
            let result = await turn.result
            expect(result.stopped == .cancelled, "the turn says it was cancelled")
            expect(app.list == ["milk"], "the change under way finishes; the next never starts")
            expect(result.done.map(\.receipt.summary) == ["Added milk"] && session.receipts.count == 1, "the change that happened keeps its receipt")
            expect(lamp.bodies.count == 1, "no step is asked after the cancel")
        }

        // An answer that arrives after a cancel runs nothing.
        do {
            let lamp = Lamp(), app = Groceries()
            lamp.answers = [["calls": [call("c1", "add", ["name": "milk"])]]]
            lamp.holdNext = true
            let turn = LampActSession(tools: app.tools, send: lamp.send).ask("add milk")
            await settle()
            turn.cancel()
            lamp.release()
            let result = await turn.result
            expect(app.log.isEmpty && result.stopped == .cancelled, "a late answer after cancel changes nothing")
        }

        // A new request replaces the one under way: the old one's late answer runs nothing.
        do {
            let lamp = Lamp(), app = Groceries()
            lamp.answers = [["reply": "Hello."]]
            lamp.holdNext = true
            let session = LampActSession(tools: app.tools, send: lamp.send)
            let first = session.ask("add milk")
            await settle()
            _ = await session.ask("never mind").result
            // The first request's answer comes back only now, after the second has finished.
            lamp.answers = [["calls": [call("c1", "add", ["name": "milk"])]]]
            lamp.release()
            let old = await first.result
            expect(old.stopped == .cancelled && app.list.isEmpty, "a replaced request's late answer changes nothing")
        }

        // A question back: only the first answer counts, the request is kept, and what was done isn't done again.
        do {
            let lamp = Lamp(), app = Groceries()
            lamp.answers = [["calls": [call("c1", "add", ["name": "milk"])]],
                            ["reply": "Which bread?", "ask": true, "choices": ["White", "Rye"]],
                            ["calls": [call("c2", "add", ["name": "milk"]), call("c3", "add", ["name": "rye"])]],
                            ["reply": "Done."]]
            let session = LampActSession(tools: app.tools, send: lamp.send)
            let asked = await session.ask("add milk and bread").result
            expect(asked.question == "Which bread?" && asked.choices == ["White", "Rye"], "the question and its choices come back")
            let answered = session.answer("Rye")
            let again = session.answer("White")
            expect(answered != nil && again == nil, "only the first answer is taken")
            _ = await answered?.result
            let request = lamp.bodies.last?["request"] as? String ?? ""
            expect(request.hasPrefix("add milk and bread") && request.contains("The person answered: Rye"), "the original request and the answer go together")
            expect(app.list == ["milk", "rye"], "a change made before the question isn't made again after it")
        }

        // Cancel drops the question: a late answer to it is refused.
        do {
            let lamp = Lamp(), app = Groceries()
            lamp.answers = [["reply": "Which one?", "ask": true]]
            let session = LampActSession(tools: app.tools, send: lamp.send)
            _ = await session.ask("add it").result
            session.cancel()
            expect(session.answer("that one") == nil, "an answer after cancel is refused")
        }

        // More changes than a request may make: the seventh is refused and the turn says why.
        do {
            let lamp = Lamp(), app = Groceries()
            lamp.answers = [["calls": (1...7).map { call("c\($0)", "add", ["name": "item \($0)"]) }]]
            let result = await LampActSession(tools: app.tools, send: lamp.send).ask("add seven things").result
            expect(app.list.count == 6 && result.stopped == .limit, "a request makes at most six changes, and says so")
        }

        // Lamp out of reach is told apart from an AI that failed.
        do {
            let app = Groceries()
            let session = LampActSession(tools: app.tools, send: { _, _ in throw LampAI.Failure(message: "Couldn't reach Lamp. Open Lamp and try again.") })
            let result = await session.ask("add milk").result
            expect(result.stopped == .unreachable, "Lamp out of reach stops as unreachable")
        }

        print(failures == 0 ? "All act checks passed." : "\(failures) act check(s) failed.")
        exit(failures == 0 ? 0 : 1)
    }
}
