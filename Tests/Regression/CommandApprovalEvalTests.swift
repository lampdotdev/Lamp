import XCTest
@testable import Lamp

/// Not a regression test: runs Lamp's judgment of each command in a corpus against the real decision model,
/// several times, and writes what it decided, for Tests/CommandApprovals/compare.py. Skipped unless
/// LAMP_EVAL_CORPUS names the corpus; needs OPENROUTER_API_KEY.
final class CommandApprovalEvalTests: XCTestCase {
    func testJudgeTheCorpus() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["LAMP_EVAL_CORPUS"], let key = environment["OPENROUTER_API_KEY"] else { throw XCTSkip("No corpus to judge.") }
        let runs = Int(environment["LAMP_EVAL_RUNS"] ?? "") ?? 5
        let corpus = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [[String: String]] ?? []
        let folder = URL(fileURLWithPath: environment["LAMP_EVAL_APP"] ?? "/Users/Shared/lamp-eval/Apps/tally")
        let project = LampProject(id: folder.lastPathComponent, name: "Tally", exe: "Tally", dir: folder)

        @Sendable func decide(_ state: [String: Any], _ questions: [String: Any]) async throws -> [String: Any] {
            var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/systemone")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 90
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["state": state, "model": "jev-latest", "questions": questions] as [String: Any])
            for attempt in 0..<5 {
                if let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200,
                   let answers = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["answers"] as? [String: Any] {
                    return answers
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
                    if Privacy.reachesOutside(command, project: project) { return (id, ["verdict": "risky", "why": "names a place outside the app's folder"]) }
                    var why = "the model didn't answer"
                    let verdict = await CommandRisk.judge(command: command, request: item["request"] ?? "", folder: folder.path, asksOutside: true) { state, questions in
                        let answers = try await decide(state, questions)
                        if let read = CommandRisk.Answers(answers, asked: questions) {
                            why = String(format: "level %.1f (sure %.2f), reads %.2f, inside %.2f, sends %.2f, secrets %.2f, hides %.2f, personal %.2f, asked %.2f",
                                         read.risk, read.riskConfidence, read.onlyReads, read.staysInside, read.sendsOut, read.readsSecrets,
                                         read.hidesWhatItDoes, read.readsPersonalFiles ?? -1, read.matchesRequest ?? -1)
                        }
                        return answers
                    }
                    return (id, ["verdict": "\(verdict)", "why": why])
                }
            }
            for _ in 0..<12 { add() }
            for await (id, result) in group {
                results[id, default: []].append(result)
                add()
            }
        }
        try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path + ".after.json"))
    }
}
