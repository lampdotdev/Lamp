import Foundation
// Judges each command as Lamp does under "Only when risky" for pi (confined, so the request's question isn't asked):
// runs on .run, or on .unsure when judged; a check that couldn't be made goes to the rating, whose low or medium
// runs it. Also records the rating alone (the decision model unavailable), which is what authorizes then.
let env = ProcessInfo.processInfo.environment
let corpusPath = CommandLine.arguments[1], outPath = CommandLine.arguments[2]
let runs = Int(env["RUNS"] ?? "") ?? 5, ratingRuns = Int(env["RATING_RUNS"] ?? "") ?? 3
let key = env["OPENROUTER_API_KEY"]!
let corpus = (try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: corpusPath))) as! [[String: Any]]).map { $0.compactMapValues { $0 as? String } }
let defaultFolder = "/Users/sam/Library/Application Support/Lamp/Apps/tally"

@Sendable func post(_ endpoint: String, _ body: [String: Any]) async throws -> [String: Any] {
    var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/\(endpoint)")!)
    request.httpMethod = "POST"; request.timeoutInterval = 90
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    for attempt in 0..<5 {
        if let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200,
           let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return reply }
        try await Task.sleep(for: .seconds(1 + attempt * 2))
    }
    throw URLError(.badServerResponse)
}
@Sendable func textModel(_ prompt: String, _ system: String) async throws -> String {
    func ask(_ prompt: String) async throws -> String {
        let body: [String: Any] = ["model": "anthropic/claude-sonnet-5.5", "response_format": ["type": "json_object"], "max_tokens": 4000,
            "messages": [["role": "system", "content": system + "\n\nRespond with only valid JSON. No prose, no code fences."],
                         ["role": "user", "content": [["type": "text", "text": prompt]]]]]
        guard let choice = (try await post("chat/completions", body)["choices"] as? [[String: Any]])?.first else { throw URLError(.cannotParseResponse) }
        var text = ((choice["message"] as? [String: Any])?["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = String(text.drop(while: { $0 != "\n" }).dropFirst())
            if let end = text.range(of: "```", options: .backwards) { text = String(text[..<end.lowerBound]) }
        }
        return text
    }
    func isJSON(_ t: String) -> Bool { (try? JSONSerialization.jsonObject(with: Data(t.utf8))) != nil }
    var reply = try await ask(prompt)
    if !isJSON(reply) { reply = try await ask(prompt + "\n\nYour previous reply was not valid JSON (it may have been cut off). Reply with the complete JSON only.") }
    return reply
}

var results: [String: [[String: String]]] = [:]
let jobs = corpus.flatMap { item in (0..<runs).map { (item, $0) } }
var next = jobs[...]
await withTaskGroup(of: (String, [String: String]).self) { group in
    func add() {
        guard let (item, n) = next.popFirst(), let id = item["id"], let command = item["command"] else { return }
        group.addTask {
            let request = item["request"] ?? ""
            var given: [String: Any] = [:]
            let judgment = await CommandRisk.judge(command: command, request: request, folder: item["folder"] ?? defaultFolder, aboutRequest: false) { state, questions in
                guard let answers = try await post("systemone", ["state": state, "model": "jev-latest", "questions": questions])["answers"] as? [String: Any] else { throw URLError(.cannotParseResponse) }
                given.merge(answers) { $1 }
                return answers
            }
            var r = ["verdict": "\(judgment.verdict)", "judged": "\(judgment.judged)", "reason": judgment.reason.map { "\($0)" } ?? ""]
            if let a = CommandRisk.Answers(given, asked: given) {
                r["why"] = String(format: "level %.2f reach %.2f reads %.2f sends %.2f secrets %.2f hides %.2f", a.risk, a.reach, a.onlyReads, a.sendsOut, a.readsSecrets, a.hidesWhatItDoes)
            }
            var rating: Store.CommandExplanation?
            if n < ratingRuns || !judgment.judged {
                rating = await CommandRisk.rating(command: command, request: request, building: "a Mac app called \"Tally\"") { p, s in try await textModel(p, s) }
                r["rating"] = rating?.risk ?? "none"
                r["fallback"] = CommandRisk.runsOnRating(rating, flagged: nil) ? "run" : "card"
            }
            let piRuns: Bool
            switch judgment.verdict {
            case .run: piRuns = true
            case .risky: piRuns = false
            case .unsure: piRuns = judgment.judged || CommandRisk.runsOnRating(rating, flagged: nil)
            }
            r["pi"] = piRuns ? "run" : "card"
            return (id, r)
        }
    }
    for _ in 0..<12 { add() }
    for await (id, r) in group { results[id, default: []].append(r); add() }
}
try! JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath): \(results.values.map(\.count).reduce(0, +)) judgments")
