import SwiftUI

struct ConversationTurn: Codable, Identifiable {
    var id = UUID()
    let who: String
    let text: String
    /// Her line in English, for Show English when the conversation is opened again.
    var english: String? = nil
}
struct RoleReply: Decodable {
    let italian: String
    let translation: String
    let coaching: String
    let score: Int
    let phrase: String
    let meaning: String
}
/// One milestone's conversation and the call for her next line. A reply is kept in the conversation, and saved,
/// before the call: when the call fails it stays there for Try again to send, so nothing is typed twice and
/// nothing is said twice.
@MainActor final class TableTalk: ObservableObject {
    @Published private(set) var turns: [ConversationTurn] = []
    @Published private(set) var busy = false
    @Published var error = ""
    private var milestone = 0
    private var requestID = UUID()

    /// The last word is the person's and she hasn't answered it: her call failed, or the app closed during it.
    var awaitsHer: Bool { turns.last?.who == "You" }

    func open(_ milestone: Int) {
        self.milestone = milestone
        turns = LampStore.load([ConversationTurn].self, from: "conversation-\(milestone)") ?? []
        error = ""
    }
    func clear() { turns = []; error = ""; save() }
    /// Leaving the page drops the call under way; a reply it was for stays to be sent again.
    func leave() { requestID = UUID(); busy = false }

    /// Her next line: her greeting when nothing has been said, her answer to `words`, or, with no words, her answer
    /// to the reply still waiting for one. `context` is what the coach knows besides the conversation.
    func ask(_ words: String? = nil, as mother: String, context: String) async -> RoleReply? {
        guard !busy else { return nil }
        let id = UUID(); requestID = id
        busy = true; error = ""
        defer { if requestID == id { busy = false } }
        if let words { turns.append(ConversationTurn(who: "You", text: words)); save() }
        do {
            guard await LampAI.isAvailable(.text) else { error = "Your Italian coach needs AI connected in Lamp."; return nil }
            guard requestID == id else { return nil }
            let conversation = "\(context) Conversation: \(turns.map { $0.who + ": " + $0.text }.joined(separator: "\n"))"
            let result = try await LampAI.ask("Play a fictional warm Italian-speaking mother of Marco at his wedding rehearsal dinner. Family from Naples; use natural standard Italian, no stereotypes or invented personal facts. Speak only Italian in character, short beginner-accessible turns, one question each. Adapt to demonstrated ability and current milestone; gradually reduce scaffolding. If starting, greet the user. Otherwise gently explain one useful correction in English and offer a usable Italian alternative; distinguish transcription uncertainty from language errors. Score this reply’s functional readiness 1–5 (not a completed milestone). Return JSON {italian:String, translation:String, coaching:String, score:Int, phrase:String, meaning:String}. On opening, coaching is a short encouraging English hint. phrase is a useful short Italian phrase for today and meaning its English meaning.", data: conversation, as: RoleReply.self)
            guard requestID == id else { return nil }
            turns.append(ConversationTurn(who: mother, text: result.italian, english: result.translation))
            save()
            return result
        } catch {
            if requestID == id { self.error = error.localizedDescription }
            return nil
        }
    }
    private func save() { LampStore.save(turns, to: "conversation-\(milestone)") }
}
