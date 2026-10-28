import XCTest
@testable import Lamp

/// `/ai/act`'s side of `LampAI.act` (`AppAct`): what it takes from the page, what it asks OpenRouter, and how it reads
/// the answer. The answers in Tests/Fixtures/openrouter-act are anthropic/claude-sonnet-5.5's own through OpenRouter,
/// recorded on 2026-10-27 with the request shape `openRouterBody` makes.
final class AppActTests: XCTestCase {
    private let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/openrouter-act")

    private let tools: [[String: Any]] = [
        ["name": "groceries", "about": "The shopping list.", "reads": true, "args": [String: Any]()],
        ["name": "addGrocery", "about": "Put something on the list.",
         "args": ["name": ["type": "string"], "qty": ["type": "integer", "min": 1, "max": 99, "optional": true]]],
    ]

    private func body(_ extra: [String: Any] = [:]) throws -> Data {
        var b: [String: Any] = ["request": "Add milk", "tools": tools]
        b.merge(extra) { $1 }
        return try JSONSerialization.data(withJSONObject: b)
    }

    private func step(_ n: Int) -> [String: Any] {
        ["calls": [["id": "s\(n)c1", "name": "groceries", "args": [String: Any]()]], "results": [["id": "s\(n)c1", "ok": true, "value": []]]]
    }

    private func message(_ name: String) throws -> [String: Any] {
        let all = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appendingPathComponent("add-milk.json"))) as? [String: Any])
        return try XCTUnwrap(all[name] as? [String: Any])
    }

    private func refusal(_ data: Data) -> String? {
        do { _ = try AppAct.parse(data); return nil } catch let f as AppAct.Failure { return f.message } catch { return "\(error)" }
    }

    func testRecordedCallBecomesOneCheckedCallWithLampsOwnId() throws {
        let r = try AppAct.parse(body())
        guard case .success(let parsed) = AppAct.parse(openRouterMessage: try message("call"), for: r) else { return XCTFail("not parsed") }
        XCTAssertEqual(parsed.calls.map(\.name), ["addGrocery"])
        XCTAssertEqual(parsed.calls.first?.id, "s1c1")
        XCTAssertEqual(parsed.calls.first?.args["name"] as? String, "milk")
    }

    func testRecordedReplyComesBackAsTheReply() throws {
        let r = try AppAct.parse(body(["steps": [["calls": [["id": "s1c1", "name": "addGrocery", "args": ["name": "milk"]]],
                                                  "results": [["id": "s1c1", "ok": true, "value": ["added": "Milk"]]]]]]))
        guard case .success(let parsed) = AppAct.parse(openRouterMessage: try message("reply"), for: r),
              case .reply(let text, let ask) = parsed.answer else { return XCTFail("not a reply") }
        XCTAssertTrue(text.contains("Milk"))
        XCTAssertFalse(ask)
    }

    func testWordsWithoutACallAreTheReply() throws {
        let r = try AppAct.parse(body())
        guard case .success(let parsed) = AppAct.parse(openRouterMessage: ["content": "Which store, the grocer or Costco?"], for: r),
              case .reply(_, let ask) = parsed.answer else { return XCTFail("not a reply") }
        XCTAssertTrue(ask)
    }

    func testCallsThatDontFitAreAskedAgainNotHandedOn() throws {
        let r = try AppAct.parse(body())
        func call(_ name: String, _ args: String) -> [String: Any] { ["function": ["name": name, "arguments": args]] }
        let cases: [[[String: Any]]] = [
            [call("addGrocery", #"{"name":"milk","qty":0}"#)],                       // under its minimum
            [call("addGrocery", #"{"name":"milk","aisle":"Dairy"}"#)],               // an argument it doesn't have
            [call("addGrocery", #"{}"#)],                                            // a required one missing
            [call("removeEverything", #"{}"#)],                                      // no such tool
            [call("addGrocery", #"{"name":"milk"}"#), call("reply", #"{"text":"Done","ask":false}"#)],  // a reply among calls
            Array(repeating: call("groceries", "{}"), count: AppAct.maxCalls + 1),  // over the cap
        ]
        for calls in cases {
            if case .success = AppAct.parse(openRouterMessage: ["tool_calls": calls], for: r) { XCTFail("handed on: \(calls)") }
        }
    }

    func testReplyIsLampsAndNamesAndIdsAreUnique() throws {
        let reply: [String: Any] = ["name": "reply", "args": [String: Any]()]
        XCTAssertNotNil(refusal(try JSONSerialization.data(withJSONObject: ["request": "x", "tools": [reply]])))
        XCTAssertNotNil(refusal(try JSONSerialization.data(withJSONObject: ["request": "x", "tools": tools + [tools[0]]])))
        let twice: [String: Any] = ["calls": [["id": "s1c1", "name": "groceries", "args": [String: Any]()]], "results": []]
        XCTAssertNotNil(refusal(try body(["steps": [twice, twice]])))
        let odd: [String: Any] = ["name": "x", "args": ["a": ["type": "string", "pattern": ".*"]]]
        XCTAssertNotNil(refusal(try JSONSerialization.data(withJSONObject: ["request": "x", "tools": [odd]])))
    }

    func testThreeStepsBehindMeanReplyOnlyAndAFourthIsRefused() throws {
        XCTAssertFalse(try AppAct.parse(body(["steps": [step(1), step(2)]])).final)
        let last = try AppAct.parse(body(["steps": [step(1), step(2), step(3)]]))
        XCTAssertTrue(last.final)
        XCTAssertEqual(AppAct.openRouterBody(last, model: "m", tag: "t")["tool_choice"] as? String, "none")
        guard case .failure = AppAct.parse(openRouterMessage: ["tool_calls": [["function": ["name": "groceries", "arguments": "{}"]]]], for: last) else {
            return XCTFail("a call after the last step")
        }
        XCTAssertNotNil(refusal(try body(["steps": [step(1), step(2), step(3), step(4)]])))
    }

    func testAStepPastItsDeadlineStartsNoAttempt() async throws {
        for deadline in [Date().addingTimeInterval(-5), Date().addingTimeInterval(0.5)] {
            do {
                _ = try await AppAct.openRouterStep([:], until: deadline)
                XCTFail("an attempt started past the deadline")
            } catch is AppAct.OutOfTime {}
        }
    }

    func testOpenRouterIsAskedForProvidersThatTakeTheTools() throws {
        let sent = AppAct.openRouterBody(try AppAct.parse(body(["context": ["list": ["eggs"]]])), model: "anthropic/claude-sonnet-5.5", tag: "outside-text-1")
        XCTAssertEqual((sent["provider"] as? [String: Any])?["require_parameters"] as? Bool, true)
        XCTAssertEqual(sent["tool_choice"] as? String, "auto")
        let names = (sent["tools"] as? [[String: Any]] ?? []).compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
        XCTAssertEqual(names, ["groceries", "addGrocery", "reply"])
        // What the app shows goes in fenced, as outside text.
        let user = ((sent["messages"] as? [[String: Any]])?[1]["content"] as? String) ?? ""
        XCTAssertTrue(user.contains("<outside-text-1>") && user.contains("eggs"))
    }
}
