import AppKit
import Foundation

/// The pieces the agent talks to the person with instead of paragraphs: a card of questions answered by
/// clicking (`ask`), and a card for a finished request whose guesses are buttons (`show_result`). The agent
/// chooses the piece and fills it in; Lamp draws it (TalkCards.swift) and turns a click into the person's
/// next message, so to the agent a click and a typed answer arrive the same way. Nothing here waits: the
/// tool returns at once, the agent ends its reply, and the answer starts the next turn. That keeps it the
/// same for every engine, none of which would hold a tool call open for as long as a person takes.
enum Talk {
    /// How a set of questions is laid out. The agent picks; the person can always type instead.
    enum Layout: String, Codable, CaseIterable {
        case steps      // one question at a time, on a card in the chat
        case together   // every question on one card, answers as chips
    }

    struct Option: Codable, Equatable {
        var title: String
        var detail: String?
        /// An SF Symbol's name, kept only when this Mac has it.
        var symbol: String?
    }

    struct Question: Codable, Equatable {
        var question: String
        var options: [Option]

        init(question: String, options: [Option]) {
            self.question = question
            self.options = options
        }

        /// A card saved while options were plain words, some with the one the agent had `chosen`, reads too.
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            question = try values.decode(String.self, forKey: .question)
            if let options = try? values.decode([Option].self, forKey: .options) {
                self.options = options
            } else {
                options = try values.decode([String].self, forKey: .options).map { Option(title: $0) }
            }
        }
    }

    struct Ask: Codable, Equatable {
        var layout: Layout
        var questions: [Question]
        /// What was chosen on the card, one for each question, once it was answered there. A typed answer
        /// leaves this nil: the message under the card says it.
        var answers: [String]?
        /// Answered in the message box instead. Noted as the message is sent, since it may wait in line
        /// behind the agent's turn: the card folds then, not when the message gets its turn.
        var typed: Bool?

        init(layout: Layout, questions: [Question], answers: [String]? = nil, typed: Bool? = nil) {
            self.layout = layout
            self.questions = questions
            self.answers = answers
            self.typed = typed
        }

        private enum Earlier: String, CodingKey { case questions, dismissed }
        private struct Chosen: Decodable { var chosen: String? }

        /// Reads the cards of an earlier shape as well: no layout, an answer that could be missing, a mark
        /// for a card answered in words, and choices the agent had made shown on the same card. Those last
        /// read as answered with what was chosen: what was decided stays in the chat, folded.
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let earlier = try decoder.container(keyedBy: Earlier.self)
            layout = (try? values.decode(Layout.self, forKey: .layout)) ?? .together
            questions = try values.decode([Question].self, forKey: .questions)
            typed = try values.decodeIfPresent(Bool.self, forKey: .typed)
            let chosen = ((try? earlier.decode([Chosen].self, forKey: .questions)) ?? []).map(\.chosen)
            let given = try values.decodeIfPresent([String?].self, forKey: .answers)
            let assumed = !chosen.isEmpty && chosen.allSatisfy { $0 != nil }
            if given != nil || assumed {
                answers = questions.indices.map { index in
                    (given.flatMap { $0.indices.contains(index) ? $0[index] : nil })
                        ?? (chosen.indices.contains(index) ? chosen[index] : nil) ?? Talk.youDecide
                }
            } else if (try? earlier.decodeIfPresent(Bool.self, forKey: .dismissed)) == true {
                typed = true
            }
        }

        /// The questions as plain words, for everything that reads a chat line's text.
        var text: String {
            questions.map { question in
                question.question + "\n" + question.options.map { "- " + $0.title }.joined(separator: "\n")
            }.joined(separator: "\n\n")
        }
    }

    /// One thing the agent decided for the person, and the other way it could have gone.
    struct Guess: Codable, Equatable {
        var guess: String
        /// The button: the other way, in a few words.
        var instead: String
        /// What the button sends, as the person would say it.
        var request: String
    }

    struct Idea: Codable, Equatable {
        var title: String
        var detail: String?
        var request: String
    }

    /// Something a change added that the person can now do, and where in the app it is.
    struct News: Codable, Equatable {
        var what: String
        var place: String
    }

    struct Result: Codable, Equatable {
        var summary: String
        var guesses: [Guess]
        var idea: Idea?
        /// What an ordinary change added, a row each. Optional so that cards from before there were any still read.
        var news: [News]?
        /// What the agent built and didn't try in the running app, offered back as something to try.
        var untried: String?
        /// The version this request made, for its picture.
        var version: String?
        /// The guesses the person turned the other way on the card, by their place in `guesses`.
        var switched: [Int]?

        var text: String {
            ([summary] + (news ?? []).map { "- \($0.what): \($0.place)" }
                + guesses.map { "- \($0.guess) (or: \($0.instead))" } + (idea.map { ["- Idea: \($0.title)"] } ?? [])
                + (untried.map { ["- Not tried: \($0)"] } ?? []))
                .joined(separator: "\n")
        }
    }

    /// What the card's Try It button sends: the agent's own words for what it didn't try, as a request.
    static func tryRequest(_ untried: String) -> String { "Please try this out: \(untried)" }

    static let questionLimit = 4
    static let optionLimit = 4
    static let guessLimit = 3
    static let newsLimit = 4

    enum Trouble: Error, Equatable {
        case message(String)
        var text: String { switch self { case .message(let text): text } }
    }

    /// The agent's `ask` arguments, checked. What's wrong goes back to the agent in words it can act on.
    static func ask(from arguments: [String: Any], hasSymbol: (String) -> Bool = Talk.hasSymbol) -> Swift.Result<Ask, Trouble> {
        let layout = (arguments["layout"] as? String).flatMap(Layout.init(rawValue:))
        let given = arguments["questions"] as? [[String: Any]] ?? []
        guard !given.isEmpty else { return .failure(.message("`questions` needs at least one question.")) }
        guard given.count <= questionLimit else {
            return .failure(.message("Ask at most \(questionLimit) questions at a time: only the ones that change what you build."))
        }
        var questions: [Question] = []
        for item in given {
            let question = (item["question"] as? String)?.trimmed ?? ""
            guard !question.isEmpty else { return .failure(.message("Every question needs its `question`.")) }
            let options: [Option] = (item["options"] as? [[String: Any]] ?? []).compactMap { option in
                guard let title = (option["title"] as? String)?.trimmed, !title.isEmpty else { return nil }
                return Option(title: title, detail: (option["detail"] as? String)?.trimmed.nilIfEmpty,
                              symbol: (option["symbol"] as? String)?.trimmed.nilIfEmpty.flatMap { hasSymbol($0) ? $0 : nil })
            }
            guard Set(options.map(\.title)).count == options.count else {
                return .failure(.message("“\(question)” has the same option twice. Give 2 to \(optionLimit) different ones."))
            }
            guard (2...optionLimit).contains(options.count) else {
                return .failure(.message("“\(question)” needs 2 to \(optionLimit) options, each with a `title`. The person can always type something else."))
            }
            questions.append(Question(question: question, options: options))
        }
        // One question has nothing to lay out together.
        return .success(Ask(layout: layout ?? .steps, questions: questions))
    }

    /// The agent's `show_result` arguments, checked.
    static func result(from arguments: [String: Any]) -> Swift.Result<Result, Trouble> {
        let summary = (arguments["summary"] as? String)?.trimmed ?? ""
        guard !summary.isEmpty else { return .failure(.message("Say in `summary` what the person now has, in one sentence.")) }
        let guesses: [Guess] = (arguments["guesses"] as? [[String: Any]] ?? []).compactMap { item in
            guard let guess = (item["guess"] as? String)?.trimmed.nilIfEmpty,
                  let instead = (item["instead"] as? String)?.trimmed.nilIfEmpty,
                  let request = (item["request"] as? String)?.trimmed.nilIfEmpty else { return nil }
            return Guess(guess: guess, instead: instead, request: request)
        }
        guard guesses.count <= guessLimit else {
            return .failure(.message("At most \(guessLimit) guesses: the ones the person is most likely to want changed."))
        }
        let idea = (arguments["idea"] as? [String: Any]).flatMap { item -> Idea? in
            guard let title = (item["title"] as? String)?.trimmed.nilIfEmpty,
                  let request = (item["request"] as? String)?.trimmed.nilIfEmpty else { return nil }
            return Idea(title: title, detail: (item["detail"] as? String)?.trimmed.nilIfEmpty, request: request)
        }
        let news: [News] = (arguments["news"] as? [[String: Any]] ?? []).compactMap { item in
            guard let what = (item["what"] as? String)?.trimmed.nilIfEmpty,
                  let place = (item["where"] as? String)?.trimmed.nilIfEmpty else { return nil }
            return News(what: what, place: place)
        }
        guard news.count <= newsLimit else {
            return .failure(.message("At most \(newsLimit) new things: the ones they wouldn't find by themselves."))
        }
        return .success(Result(summary: summary, guesses: guesses, idea: idea, news: news.isEmpty ? nil : news,
                               untried: (arguments["untried"] as? String)?.trimmed.nilIfEmpty))
    }

    static func hasSymbol(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    /// What a question is answered with when the person leaves it to Lamp.
    static let youDecide = "You decide"

    /// The message a card's answers make: one line for each question, in the order asked, each with the
    /// question it answers. An engine that reads the conversation again later, or has summed it up, has
    /// the answers with what they were about. The chat doesn't show the message: the card shows what was chosen.
    static func message(for ask: Ask, answers: [String]) -> String {
        func ended(_ text: String, with mark: String) -> String {
            text.last.map { ".?!…".contains($0) } == true ? text : text + mark
        }
        return ask.questions.indices.map { index in
            ended(ask.questions[index].question, with: "?") + " " + ended(index < answers.count ? answers[index] : youDecide, with: ".")
        }.joined(separator: "\n")
    }

    /// The card still waiting for its answer: the last one asked, with nothing said by the person since.
    /// A typed message answers it as well as a click does.
    static func open(in lines: [LogLine]) -> LogLine? {
        guard let index = lines.lastIndex(where: { $0.kind == .ask }),
              lines[index].ask?.answers == nil, lines[index].ask?.typed != true,
              !lines[(index + 1)...].contains(where: { $0.kind == .user }) else { return nil }
        return lines[index]
    }

    /// Takes a message that was waiting to be sent back out of the line. An answer to a card, clicked or
    /// typed, was noted on it when it was given; taken back before it went out, it was never given, so the
    /// card waits again. Left folded, nothing would be asking the question any more. A guess turned the
    /// other way goes back the same. True when a card changed.
    static func unqueue(_ message: QueuedMessage, from queue: inout [QueuedMessage], lines: inout [LogLine]) -> Bool {
        guard let waiting = queue.firstIndex(where: { $0.id == message.id }) else { return false }
        queue.remove(at: waiting)
        guard let card = message.card, let index = lines.firstIndex(where: { $0.id == card }) else { return false }
        if lines[index].ask?.answers != nil || lines[index].ask?.typed == true {
            lines[index].ask?.answers = nil
            lines[index].ask?.typed = nil
            return true
        }
        if lines[index].result?.switched != nil {
            lines[index].result?.switched = nil
            return true
        }
        return false
    }

    /// Whether the card shows what a message says, so the chat doesn't say it again under it: answers
    /// clicked on a question card, or a guess turned the other way. An answer typed instead is its own message.
    static func shows(_ card: LogLine?) -> Bool {
        card?.ask?.answers != nil || card?.result?.switched != nil
    }

    /// The result whose buttons still mean something: the latest, until the person asks for anything else.
    static func current(in lines: [LogLine]) -> LogLine? {
        guard let index = lines.lastIndex(where: { $0.kind == .result }),
              !lines[(index + 1)...].contains(where: { $0.kind == .user }) else { return nil }
        return lines[index]
    }

    static let asked = "The person now sees your questions as a card and answers by clicking or typing. Your turn ends here: change nothing and call nothing more. Their answer is the next message: one line for each question, in the order you asked, each question followed by its answer, or their own words."
    static let alreadyAsked = "The person already sees the questions you asked and hasn't answered yet, so these weren't shown. End your reply now with no more words; their answer is the next message."
    static let resultKept = "Lamp shows this when the app is built and open. End your reply now with nothing more: no question, no offer, nothing the card already says."
}
