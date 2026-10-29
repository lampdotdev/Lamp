import XCTest
@testable import Lamp

/// `/ai/act` on the routes without OpenRouter: a step asked of Claude Code, Codex or a model on this Mac as one prompt
/// that must answer in `AppAct.planSchema`'s shape, read back into the same checked calls or reply. The answers in
/// Tests/Fixtures/claude-code-act are Claude Code's own (2.1.310, its Sonnet) and those in Tests/Fixtures/codex-act are
/// Codex's (0.164.0-alpha.11.1, its default model), both recorded on 2026-10-29 by `testRecordEngineAnswers` with the
/// prompt and flags `AppAct.ask` uses.
final class AppActRoutesTests: XCTestCase {
    private func fixture(_ engine: Engine) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(engine == .codex ? "codex-act" : "claude-code-act")/add-bananas.json")
    }

    private let tools: [[String: Any]] = [
        ["name": "groceries", "about": "The shopping list.", "reads": true, "args": [String: Any]()],
        ["name": "addGrocery", "about": "Put something on the list.",
         "args": ["name": ["type": "string"], "qty": ["type": "integer", "min": 1, "max": 99, "optional": true],
                  "store": ["type": "string", "oneOf": ["grocer", "costco"], "optional": true]]],
    ]
    private let added: [String: Any] = ["calls": [["id": "s1c1", "name": "addGrocery", "args": ["name": "Bananas"]]],
                                        "results": [["id": "s1c1", "ok": true, "value": ["added": "Bananas", "qty": 1, "store": "grocer"]]]]

    private func request(_ extra: [String: Any] = [:]) throws -> AppAct.Request {
        var b: [String: Any] = ["request": "Add bananas", "tools": tools, "about": "A family dashboard with the shopping list."]
        b.merge(extra) { $1 }
        return try AppAct.parse(JSONSerialization.data(withJSONObject: b))
    }

    private func recorded(_ name: String, by engine: Engine = .claude) throws -> String {
        let all = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture(engine))) as? [String: Any])
        return try XCTUnwrap(all[name] as? String)
    }

    /// Asks the signed-in engine on this Mac (`LAMP_RECORD_ACT=claude` or `codex`) for both steps and writes what it
    /// said to its fixture.
    func testRecordEngineAnswers() async throws {
        let wanted = ProcessInfo.processInfo.environment["LAMP_RECORD_ACT"] ?? ""
        guard let engine = ["claude": Engine.claude, "codex": .codex][wanted] else {
            throw XCTSkip("Set LAMP_RECORD_ACT=claude or codex to ask that engine")
        }
        EngineInstall.lookNow()
        var out: [String: Any] = [:]
        for (name, r) in [("call", try request()), ("reply", try request(["steps": [added]]))] {
            let (system, prompt) = AppAct.planPrompt(r, tag: "outside-text-1", retry: nil, schemaInPrompt: false)
            let (text, _) = try await AppAI.viaEngine(engine, prompt: prompt, images: [], system: system,
                                                      model: engine == .claude ? "sonnet" : "",
                                                      schema: AppAct.planSchema(r), timeLimit: 60, sealed: true)
            out[name] = text
        }
        let file = fixture(engine)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]).write(to: file)
    }

    func testClaudeCodesRecordedCallBecomesOneCheckedCallWithNullsLeftOut() throws {
        guard case .success(let parsed) = AppAct.parse(plan: try recorded("call"), for: try request()) else { return XCTFail("not parsed") }
        XCTAssertEqual(parsed.calls.map(\.name), ["addGrocery"])
        XCTAssertEqual(parsed.calls.first?.id, "s1c1")
        XCTAssertEqual((parsed.calls.first?.args["name"] as? String)?.lowercased(), "bananas")
        XCTAssertFalse(parsed.calls.first?.args.values.contains { $0 is NSNull } ?? true)
    }

    func testClaudeCodesRecordedReplyComesBackAsTheReply() throws {
        guard case .success(let parsed) = AppAct.parse(plan: try recorded("reply"), for: try request(["steps": [added]])),
              case .reply(let text, let ask, _) = parsed.answer else { return XCTFail("not a reply") }
        XCTAssertTrue(text.localizedCaseInsensitiveContains("banana"))
        XCTAssertFalse(ask)
    }

    /// Codex looks the list up first, as the rules ask before a change: one checked read, no arguments.
    func testCodexsRecordedCallBecomesOneCheckedRead() throws {
        guard case .success(let parsed) = AppAct.parse(plan: try recorded("call", by: .codex), for: try request()) else { return XCTFail("not parsed") }
        XCTAssertEqual(parsed.calls.map(\.name), ["groceries"])
        XCTAssertEqual(parsed.calls.first?.id, "s1c1")
    }

    func testCodexsRecordedReplyComesBackAsTheReply() throws {
        guard case .success(let parsed) = AppAct.parse(plan: try recorded("reply", by: .codex), for: try request(["steps": [added]])),
              case .reply(let text, let ask, _) = parsed.answer else { return XCTFail("not a reply") }
        XCTAssertTrue(text.localizedCaseInsensitiveContains("banana"))
        XCTAssertFalse(ask)
    }

    /// A plan's calls go through the same checks as OpenRouter's: a call that doesn't fit its tool is asked again.
    func testAPlanCallThatDoesntFitIsAskedAgain() throws {
        let bad = #"{"calls": [{"name": "addGrocery", "args": {"name": "Bananas", "qty": 0, "store": null}}], "reply": null}"#
        guard case .failure(let problem) = AppAct.parse(plan: bad, for: try request()) else { return XCTFail("taken") }
        XCTAssertTrue(problem.reason.contains("qty"))
    }

    /// Arguments that aren't an object are refused, as OpenRouter's are, even for a tool that needs none.
    func testAPlanCallWhoseArgumentsArentAnObjectIsAskedAgain() throws {
        let odd = #"{"calls": [{"name": "groceries", "args": "all"}], "reply": null}"#
        guard case .failure(let problem) = AppAct.parse(plan: odd, for: try request()) else { return XCTFail("taken") }
        XCTAssertTrue(problem.reason.contains("JSON object"))
    }

    /// Ask was refused on every route but OpenRouter's; each one that can answer now takes a step.
    @MainActor func testEveryRouteThatCanAnswerTakesAStep() {
        func route(_ kind: AppAI.TextRoute.Kind, _ available: Bool = true) -> AppAI.TextRoute {
            AppAI.TextRoute(id: "r", label: "r", group: "g", name: "n", kind: kind, available: available)
        }
        XCTAssertNil(AppAct.refusal(for: route(.engine(.claude, model: "sonnet"))))
        XCTAssertNil(AppAct.refusal(for: route(.engine(.codex, model: ""))))
        XCTAssertNil(AppAct.refusal(for: route(.localModel(provider: "local", model: "qwen3.5-4b"))))
        XCTAssertNil(AppAct.refusal(for: route(.openRouter(model: "m"))))
        XCTAssertEqual(AppAct.refusal(for: route(.engine(.claude, model: "sonnet"), false)), AppAI.noTextRoute)
    }

    /// Ask is ready on a sign-in with no OpenRouter key, and an app set to a model on this Mac never has its actions
    /// sent to a service while that model can't answer: they're refused instead, with the reason.
    @MainActor func testActionsStayOnAModelOnThisMacWhenOneWasChosen() {
        func route(_ kind: AppAI.TextRoute.Kind, _ available: Bool = true) -> AppAI.TextRoute {
            AppAI.TextRoute(id: "r", label: "r", group: "g", name: "Qwen", kind: kind, available: available)
        }
        let claude = route(.engine(.claude, model: "sonnet")), local = route(.localModel(provider: "local", model: "qwen3.5-4b"))
        guard case .success = AppAct.choose(wanted: nil, resolved: claude) else { return XCTFail("a sign-in alone should answer") }
        guard case .success = AppAct.choose(wanted: local, resolved: local) else { return XCTFail("the chosen local model should answer") }
        // The model was removed: the routes Lamp lists no longer have it at all.
        let removed = AppAct.wanted("local:qwen3.5-4b", among: [claude])
        guard case .failure(let refused) = AppAct.choose(wanted: removed, resolved: claude) else {
            return XCTFail("actions went to Claude Code though a model on this Mac was chosen")
        }
        XCTAssertTrue(refused.message.contains("qwen3.5-4b on this Mac"))
        XCTAssertNil(AppAct.wanted("engine:claude:sonnet", among: []), "a cloud choice that's gone is no choice to keep to")
        guard case .success = AppAct.choose(wanted: route(.openRouter(model: "m"), false), resolved: claude) else {
            return XCTFail("a cloud choice standing in for another cloud route should answer")
        }
        guard case .failure(let none) = AppAct.choose(wanted: nil, resolved: route(.openRouter(model: "m"), false)) else { return XCTFail("nothing can answer") }
        XCTAssertEqual(none.message, AppAI.noTextRoute)
    }

    /// An MLX model whose chat template mlx-lm has no tool-call parser for hands a call back as plain text, so it's
    /// asked for the JSON plan instead, whatever the version. The templates in Tests/Fixtures/mlx-templates are the
    /// `chat_template` of each mlx-community repository's tokenizer_config.json, as published on 2026-10-29.
    func testAnMLXModelWithoutAToolParserIsAskedForThePlan() {
        let templates = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/mlx-templates")
        XCTAssertFalse(AppAct.mlxNativeTools(version: "0.32.2", model: templates.appendingPathComponent("Llama-3.2-3B-Instruct-4bit")))
        XCTAssertTrue(AppAct.mlxNativeTools(version: "0.32.2", model: templates.appendingPathComponent("Qwen3-4B-4bit")))
        XCTAssertFalse(AppAct.mlxNativeTools(version: "0.30.3", model: templates.appendingPathComponent("Qwen3-4B-4bit")))
        XCTAssertFalse(AppAct.mlxNativeTools(version: "0.32.2", model: nil))
    }

    /// mlx-lm hands the tools to the model's template from 0.30.4 (ml-explore/mlx-lm#747); before that, the shape is
    /// asked for in words.
    func testMLXToolCallsOnlyFromTheVersionThatPassesThem() {
        XCTAssertFalse(AppAct.mlxTakesTools(nil))
        XCTAssertFalse(AppAct.mlxTakesTools("0.26.0"))
        XCTAssertFalse(AppAct.mlxTakesTools("0.30.3"))
        XCTAssertTrue(AppAct.mlxTakesTools("0.30.4"))
        XCTAssertTrue(AppAct.mlxTakesTools("0.32.2"))
        XCTAssertTrue(AppAct.mlxTakesTools("1.0"))
    }
}
