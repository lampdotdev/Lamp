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
    }

    struct Ask: Codable, Equatable {
        var layout: Layout
        var questions: [Question]
        /// What was chosen on the card, one for each question, once it was answered there. A typed answer
        /// leaves this nil: the message under the card says it.
        var answers: [String]?

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

    struct Result: Codable, Equatable {
        var summary: String
        var guesses: [Guess]
        var idea: Idea?
        /// The version this request made, for its picture.
        var version: String?

        var text: String {
            ([summary] + guesses.map { "- \($0.guess) (or: \($0.instead))" } + (idea.map { ["- Idea: \($0.title)"] } ?? []))
                .joined(separator: "\n")
        }
    }

    static let questionLimit = 4
    static let optionLimit = 4
    static let guessLimit = 3

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
        return .success(Result(summary: summary, guesses: guesses, idea: idea))
    }

    static func hasSymbol(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    /// What a question is answered with when the person leaves it to Lamp.
    static let youDecide = "You decide"

    /// The message a card's answers make: one line for each question, in the order asked, which is how the
    /// agent is told to read them. The questions aren't repeated: the card above the message shows them.
    static func message(for ask: Ask, answers: [String]) -> String {
        ask.questions.indices.map { $0 < answers.count ? answers[$0] : youDecide }.joined(separator: "\n")
    }

    /// The card still waiting for its answer: the last one asked, with nothing said by the person since.
    /// A typed message answers it as well as a click does.
    static func open(in lines: [LogLine]) -> LogLine? {
        guard let index = lines.lastIndex(where: { $0.kind == .ask }),
              lines[index].ask?.answers == nil,
              !lines[(index + 1)...].contains(where: { $0.kind == .user }) else { return nil }
        return lines[index]
    }

    /// The result whose buttons still mean something: the latest, until the person asks for anything else.
    static func current(in lines: [LogLine]) -> LogLine? {
        guard let index = lines.lastIndex(where: { $0.kind == .result }),
              !lines[(index + 1)...].contains(where: { $0.kind == .user }) else { return nil }
        return lines[index]
    }

    static let asked = "The person now sees your questions as a card and answers by clicking or typing. End your reply here with no more words. Their answer is the next message: one line for each question, in the order you asked, or their own words."
    static let alreadyAsked = "The person already sees the questions you asked and hasn't answered yet, so these weren't shown. End your reply now with no more words; their answer is the next message."
    static let resultKept = "Lamp shows this when the app is built and open. End your reply now with nothing more: no question, no offer, nothing the card already says."
}
