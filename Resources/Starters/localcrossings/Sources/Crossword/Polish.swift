import Foundation

/// The AI's pass over a place, once, in the background: it picks the answers that make a fair, fun puzzle for
/// someone living there and rewords their clues with some wit. It never adds what the map didn't say: a clue
/// naming anything that isn't in what it was made from keeps the plain one. Nothing waits for it: a place's
/// first puzzle is made without it, and the ones after use what it chose.
enum Polish {
    private struct Reply: Decodable {
        struct Pick: Decodable {
            var answer: String
            var clue: String
        }
        var picks: [Pick]
    }

    static func curate(_ candidates: [Candidate], in place: Neighborhood) async -> [Neighborhood.Curated]? {
        guard candidates.count >= 12, await LampAI.isAvailable(.text) else { return nil }
        let lines = candidates.map { "\($0.answer)\t\($0.lengths)\t\($0.facts)" }.joined(separator: "\n")
        let prompt = """
        You edit a daily crossword made from the places around someone's home in \(place.title). The data is \
        candidate answers, one per line: ANSWER, the lengths of its words, and a plain clue made from the map. The \
        map's facts are the only facts you may use.

        Pick up to 40 answers, best first: first the ones anyone living here would know (the town, the main \
        streets, the big park, famous spots), then ones that can be worked out from the clue. Skip answers that only \
        a regular of one shop could know, and ones where the blank is a dull word. For each, write a crossword clue: \
        short, a little wit, in the voice of a good newspaper puzzle. Never state anything that isn't in its line, \
        never use the answer in the clue, and keep "___" where the answer goes in a name.

        Return JSON: {"picks": [{"answer": "ANSWER", "clue": "the clue"}]}
        """
        guard let reply = try? await LampAI.ask(prompt, data: lines, as: Reply.self) else { return nil }
        let byAnswer = Dictionary(candidates.map { ($0.answer, $0) }, uniquingKeysWith: { a, _ in a })
        var seen: Set<String> = []
        let picks = reply.picks.compactMap { pick -> Neighborhood.Curated? in
            let answer = pick.answer.uppercased()
            guard let candidate = byAnswer[answer], seen.insert(answer).inserted else { return nil }
            let clue = pick.clue.trimmingCharacters(in: .whitespacesAndNewlines)
            return Neighborhood.Curated(answer: answer, clue: isTrue(clue, to: candidate, in: place) ? clue : candidate.clue)
        }
        return picks.count >= 12 ? picks : nil
    }

    /// A reworded clue is kept only when it names nothing new: every capitalized word after the first must come
    /// from the plain clue or the place's name, it mustn't give the answer away, and it must stay short.
    static func isTrue(_ clue: String, to candidate: Candidate, in place: Neighborhood) -> Bool {
        guard !clue.isEmpty, clue.count <= 90 else { return false }
        let squeezed = clue.uppercased().filter(\.isLetter)
        if squeezed.contains(candidate.answer) { return false }
        let named = [candidate.facts, place.area ?? "", place.town ?? ""].joined(separator: " ")
        let known = Set(words(in: named).map { $0.lowercased() })
        for word in words(in: clue).dropFirst() where word.first?.isUppercase == true {
            if !known.contains(word.lowercased()) { return false }
        }
        return true
    }

    private static func words(in text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }
}
