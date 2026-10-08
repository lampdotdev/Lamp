import XCTest
@testable import Lamp

/// Not a regression test: runs Lamp's judgment of each command in a corpus against the real models, several
/// times, and writes what it decided, for Tests/CommandApprovals/compare.py. Skipped unless LAMP_EVAL_CORPUS
/// names the corpus; needs OPENROUTER_API_KEY.
///
/// Each command goes the way the app sends it under "Only when risky": `CommandRisk.judge`, then, only when that's unsure, `CommandRisk.rating`, whose "low" runs it. Those two are the
/// app's own code; what stands in for the app here is only who carries the questions to the models (straight
/// to OpenRouter: Jev for the judgment, Sonnet for the rating, as Lamp does with an OpenRouter key).
/// LAMP_EVAL_REQUEST_EVERYWHERE=1 puts the request in front of every question, as this judgment did before
/// it was kept to its own: for measuring what that changed.
final class CommandApprovalEvalTests: XCTestCase {
    func testJudgeTheCorpus() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["LAMP_EVAL_CORPUS"], let key = environment["OPENROUTER_API_KEY"] else { throw XCTSkip("No corpus to judge.") }
        let runs = Int(environment["LAMP_EVAL_RUNS"] ?? "") ?? 5
        let requestEverywhere = environment["LAMP_EVAL_REQUEST_EVERYWHERE"] == "1"
        let corpus = (try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [[String: Any]] ?? [])
            .map { $0.compactMapValues { $0 as? String } }
        XCTAssertFalse(corpus.isEmpty, "Nothing to judge in \(path).")
        let folder = environment["LAMP_EVAL_APP"] ?? "/Users/Shared/lamp-eval/Apps/tally"

        // The profile the app would confine these commands with, for compare.py's `enforce`.
        if let profile = environment["LAMP_EVAL_PROFILE"] {
            try Sandbox.profile(for: LampProject(id: "tally", name: "Tally", exe: "Tally", dir: URL(fileURLWithPath: folder)))
                .write(toFile: profile, atomically: true, encoding: .utf8)
        }

        @Sendable func post(_ endpoint: String, _ body: [String: Any]) async throws -> [String: Any] {
            var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/\(endpoint)")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 90
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            for attempt in 0..<5 {
                if let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200,
                   let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    return reply
                }
                try await Task.sleep(for: .seconds(1 + attempt * 2))
            }
            throw URLError(.badServerResponse)
        }

        var results: [String: [[String: String]]] = [:]
        await withTaskGroup(of: (String, [String: String]).self) { group in
            var waiting = corpus.flatMap { item in (0..<runs).map { _ in item } }[...]
            func add() {
                guard let item = waiting.popFirst(), let id = item["id"], let command = item["command"] else { return }
                group.addTask {
                    let request = item["request"] ?? ""
                    var why = "the model didn't answer"
                    var given: [String: Any] = [:]
                    let judgment = await CommandRisk.judge(command: command, request: request, folder: item["folder"] ?? folder) { state, questions in
                        var state = state
                        if requestEverywhere { state["user_request"] = request }
                        guard let answers = try await post("systemone", ["state": state, "model": "jev-latest", "questions": questions])["answers"] as? [String: Any] else {
                            throw URLError(.cannotParseResponse)
                        }
                        given.merge(answers) { $1 }
                        return answers
                    }
                    if let read = CommandRisk.Answers(given, asked: given) {
                        why = String(format: "level %.1f (sure %.2f), reads %.2f, sends %.2f, secrets %.2f, hides %.2f, asked %.2f",
                                     read.risk, read.riskConfidence, read.onlyReads, read.sendsOut, read.readsSecrets,
                                     read.hidesWhatItDoes, read.matchesRequest ?? -1)
                    }
                    var result = ["verdict": "\(judgment.verdict)", "why": why, "reason": judgment.reason.map { "\($0)" } ?? ""]
                    // As Store.requestApproval does under "Only when risky": the rating is asked for only when the
                    // judgment wasn't sure, and only its "low" runs the command.
                    var runs = judgment.verdict == .run
                    if judgment.verdict == .unsure {
                        let rating = await CommandRisk.rating(command: command, request: request, building: "a Mac app called \"Tally\"") { prompt, system in
                            let reply = try await post("chat/completions", ["model": "anthropic/claude-sonnet-5.5", "messages": [
                                ["role": "system", "content": system + "\n\nRespond with only valid JSON. No prose, no code fences."],
                                ["role": "user", "content": prompt]]])
                            let text = ((reply["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String ?? ""
                            return text.replacingOccurrences(of: #"^```(?:json)?\s*|\s*```$"#, with: "", options: .regularExpression)
                        }
                        result["rating"] = rating?.risk ?? "no rating"
                        runs = rating?.risk == "low"
                    }
                    result["outcome"] = runs ? "run" : "card"
                    return (id, result)
                }
            }
            for _ in 0..<12 { add() }
            for await (id, result) in group {
                results[id, default: []].append(result)
                add()
            }
        }
        try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: environment["LAMP_EVAL_OUT"] ?? path + ".after.json"))
    }
}
