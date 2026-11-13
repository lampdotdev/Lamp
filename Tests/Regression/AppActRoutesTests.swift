import XCTest
@testable import Lamp

/// `/ai/act`'s routes: which answers a step, and how it's asked. What the model is told and how its answer is read is
/// lamp's command line's (cli/app-ai.mjs), tested there with the answers recorded in Tests/Fixtures: those in
/// claude-code-act are Claude Code's own (2.1.310, its Sonnet) and those in codex-act Codex's (0.164.0-alpha.11.1, its
/// default model), both recorded on 2026-10-29 by `testRecordEngineAnswers` with the prompt and flags `AppAct.ask` uses.
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

    private func request(_ extra: [String: Any] = [:]) async throws -> AppAct.Request {
        var b: [String: Any] = ["request": "Add bananas", "tools": tools, "about": "A family dashboard with the shopping list."]
        b.merge(extra) { $1 }
        return try await AppAct.parse(JSONSerialization.data(withJSONObject: b))
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
        for (name, r) in [("call", try await request()), ("reply", try await request(["steps": [added]]))] {
            let asked = try await LampCLI.ask("actAsk", ["step": r, "tag": "outside-text-1", "way": "plan"])
            let (text, _) = try await AppAI.viaEngine(engine, prompt: asked["prompt"] as? String ?? "", images: [], system: asked["system"] as? String ?? "",
                                                      model: engine == .claude ? "sonnet" : "",
                                                      schema: asked["schema"] as? [String: Any], timeLimit: 60)
            out[name] = text
        }
        let file = fixture(engine)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]).write(to: file)
    }

    /// A step is taken through lamp's command line: what the page sent is checked there, and a call that doesn't fit is
    /// asked again, never handed on.
    func testAStepIsCheckedAndReadThroughLampsCommandLine() async throws {
        let r = try await request()
        XCTAssertEqual(r["final"] as? Bool, false)
        let bad = #"{"calls": [{"name": "addGrocery", "args": {"name": "Bananas", "qty": 0, "store": null}}], "reply": null}"#
        guard case .failure(let problem) = try await AppAct.read(["plan": bad], for: r) else { return XCTFail("taken") }
        XCTAssertTrue(problem.reason.contains("qty"))
        do { _ = try await AppAct.parse(Data(#"{"request": "x", "tools": [{"name": "reply"}]}"#.utf8)); XCTFail("reply is Lamp's") }
        catch let failure as AppAct.Failure { XCTAssertEqual(failure.status, 400) }
    }

    func testAStepPastItsDeadlineStartsNoAttempt() async throws {
        for deadline in [Date().addingTimeInterval(-5), Date().addingTimeInterval(0.5)] {
            do {
                _ = try await AppAct.openRouterStep([:], until: deadline)
                XCTFail("an attempt started past the deadline")
            } catch is AppAct.OutOfTime {}
        }
    }

    /// Ask was refused on every route but OpenRouter's; each one that can answer now takes a step.
    @MainActor func testEveryRouteThatCanAnswerTakesAStep() {
        func route(_ kind: AppAI.TextRoute.Kind, _ available: Bool = true) -> AppAI.TextRoute {
            AppAI.TextRoute(id: "r", label: "r", group: "g", name: "n", kind: kind, available: available)
        }
        XCTAssertNil(AppAct.refusal(for: route(.engine(.claude, model: "sonnet"))))
        XCTAssertNil(AppAct.refusal(for: route(.engine(.codex, model: ""))))
        XCTAssertNil(AppAct.refusal(for: route(.openRouter(model: "m"))))
        XCTAssertEqual(AppAct.refusal(for: route(.engine(.claude, model: "sonnet"), false)), AppAI.noTextRoute)
    }

    /// Ask is ready on a sign-in with no OpenRouter key, and refused with the reason when nothing can answer.
    @MainActor func testASignInAloneTakesAStep() {
        let claude = AppAI.TextRoute(id: "r", label: "r", group: "g", name: "n", kind: .engine(.claude, model: "sonnet"), available: true)
        guard case .success = AppAct.choose(claude) else { return XCTFail("a sign-in alone should answer") }
        let none = AppAI.TextRoute(id: "r", label: "r", group: "g", name: "n", kind: .openRouter(model: "m"), available: false)
        guard case .failure(let refused) = AppAct.choose(none) else { return XCTFail("nothing can answer") }
        XCTAssertEqual(refused.message, AppAI.noTextRoute)
    }

    /// `/ai/models` says what answers each model as its own fields, the default's harness first, and every id is one
    /// route: the same model through Claude Code and through OpenRouter are told apart, and each id chooses its own.
    func testModelsSayWhatAnswersEachAndEveryIdIsOneRoute() throws {
        let routes = [
            AppAI.TextRoute(id: "opus", label: "Best at coding (Claude Opus) via OpenRouter", group: "OpenRouter", name: "Best at coding (Claude Opus)",
                            kind: .openRouter(model: "anthropic/claude-opus-5.5"), available: true),
            AppAI.TextRoute(id: "sonnet", label: "Faster & cheaper (Claude Sonnet) via OpenRouter", group: "OpenRouter", name: "Faster & cheaper (Claude Sonnet)",
                            kind: .openRouter(model: "anthropic/claude-sonnet-5.5"), available: true),
            AppAI.TextRoute(id: "engine:claude:opus", label: "Opus via Claude", group: "Claude", name: "Opus", kind: .engine(.claude, model: "opus"), available: true),
            AppAI.TextRoute(id: "engine:claude:sonnet", label: "Sonnet via Claude", group: "Claude", name: "Sonnet", kind: .engine(.claude, model: "sonnet"), available: true),
            AppAI.TextRoute(id: "engine:codex", label: "ChatGPT's default model via ChatGPT", group: "ChatGPT", name: "ChatGPT's default model",
                            kind: .engine(.codex, model: ""), available: false),
        ]
        let list = AppAI.modelList(routes, answering: routes[3], reason: "Not set up.")
        let models = try XCTUnwrap(list["models"] as? [[String: Any]])
        XCTAssertEqual(models.map { $0["id"] as? String }, ["engine:claude:opus", "engine:claude:sonnet", "openrouter:opus", "openrouter:sonnet", "engine:codex"])
        XCTAssertEqual(models.map { $0["model"] as? String }, ["Claude Opus", "Claude Sonnet", "Claude Opus", "Claude Sonnet", "ChatGPT's default model"])
        XCTAssertEqual(models.map { ($0["via"] as? [String: String])?["id"] }, ["claude-code", "claude-code", "openrouter", "openrouter", "codex"])
        XCTAssertEqual((models[2]["via"] as? [String: String])?["name"], "OpenRouter")
        XCTAssertEqual(models[2]["name"] as? String, "Best at coding (Claude Opus) via OpenRouter")
        XCTAssertEqual(list["default"] as? String, "engine:claude:sonnet")
        XCTAssertEqual(models[4]["reason"] as? String, "Not set up.")
        // Each listed id goes through its own route; a bare one through the default's harness, else OpenRouter as before.
        func choice(_ asked: String, default fallback: AppAI.TextRoute = routes[3]) -> String? {
            AppAI.choice(asked: asked, canonical: asked.hasPrefix("openrouter:") ? String(asked.dropFirst(11)) : asked, among: routes, answering: fallback)
        }
        XCTAssertEqual(choice("engine:claude:opus"), "engine:claude:opus")
        XCTAssertEqual(choice("openrouter:opus"), "opus")
        XCTAssertEqual(choice("opus"), "engine:claude:opus")
        XCTAssertEqual(choice("opus", default: routes[1]), "opus")
        XCTAssertNil(choice("engine:codex"))
    }
}
