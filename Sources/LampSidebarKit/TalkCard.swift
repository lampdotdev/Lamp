import Foundation

/// The agent's cards as data (Lamp's `Talk` keeps its names for them): questions to click through, and what a
/// request made. Here so Lamp's window and the chat inside each app's window draw them from the same values.
public enum TalkCard {
    /// What a question left unanswered is given as, for Lamp to decide.
    public static let youDecide = "You decide"

    /// How a set of questions is laid out. The agent picks; the person can always type instead.
    public enum Layout: String, Codable, CaseIterable {
        case steps      // one question at a time, on a card in the chat
        case together   // every question on one card, answers as chips
    }

    public struct Option: Codable, Equatable {
        public var title: String
        public var detail: String?
        /// An SF Symbol's name, kept only when this Mac has it.
        public var symbol: String?

        public init(title: String, detail: String? = nil, symbol: String? = nil) {
            self.title = title
            self.detail = detail
            self.symbol = symbol
        }
    }

    public struct Question: Codable, Equatable {
        public var question: String
        public var options: [Option]
        /// A line under the question, for what it's about: Lamp's own cards have one (`Starters`), the agent's don't.
        public var detail: String?

        public init(question: String, options: [Option], detail: String? = nil) {
            self.question = question
            self.options = options
            self.detail = detail
        }

        /// A card saved while options were plain words, some with the one the agent had `chosen`, reads too.
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            question = try values.decode(String.self, forKey: .question)
            detail = try values.decodeIfPresent(String.self, forKey: .detail)
            if let options = try? values.decode([Option].self, forKey: .options) {
                self.options = options
            } else {
                options = try values.decode([String].self, forKey: .options).map { Option(title: $0) }
            }
        }
    }

    /// Whether "You decide" is one of a question's tiles: beside up to three answers, where the tiles make a row of
    /// four or two by two. With four of its own there's no room left in the row, and it's a link under them.
    public static func decidesAsTile(_ question: Question) -> Bool { question.options.count < 4 }

    public struct Ask: Codable, Equatable {
        public var layout: Layout
        public var questions: [Question]
        /// What was chosen on the card, one for each question, once it was answered there. A typed answer
        /// leaves this nil: the message under the card says it.
        public var answers: [String]?
        /// Answered in the message box instead. Noted as the message is sent, since it may wait in line
        /// behind the agent's turn: the card folds then, not when the message gets its turn.
        public var typed: Bool?
        /// Lamp's own card, not the agent's: what a wish Lamp came with offers to change first (`Starters`).
        /// It's answered the same way, but nothing waits on it: the wish is there to use meanwhile.
        public var offer: Bool?

        public init(layout: Layout, questions: [Question], answers: [String]? = nil, typed: Bool? = nil, offer: Bool? = nil) {
            self.layout = layout
            self.questions = questions
            self.answers = answers
            self.typed = typed
            self.offer = offer
        }

        private enum Earlier: String, CodingKey { case questions, dismissed }
        private struct Chosen: Decodable { var chosen: String? }

        /// Reads the cards of an earlier shape as well: no layout, an answer that could be missing, a mark
        /// for a card answered in words, and choices the agent had made shown on the same card. Those last
        /// read as answered with what was chosen: what was decided stays in the chat, folded.
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let earlier = try decoder.container(keyedBy: Earlier.self)
            layout = (try? values.decode(Layout.self, forKey: .layout)) ?? .together
            questions = try values.decode([Question].self, forKey: .questions)
            typed = try values.decodeIfPresent(Bool.self, forKey: .typed)
            offer = try values.decodeIfPresent(Bool.self, forKey: .offer)
            let chosen = ((try? earlier.decode([Chosen].self, forKey: .questions)) ?? []).map(\.chosen)
            let given = try values.decodeIfPresent([String?].self, forKey: .answers)
            let assumed = !chosen.isEmpty && chosen.allSatisfy { $0 != nil }
            if given != nil || assumed {
                answers = questions.indices.map { index in
                    (given.flatMap { $0.indices.contains(index) ? $0[index] : nil })
                        ?? (chosen.indices.contains(index) ? chosen[index] : nil) ?? TalkCard.youDecide
                }
            } else if (try? earlier.decodeIfPresent(Bool.self, forKey: .dismissed)) == true {
                typed = true
            }
        }

        /// What the card says once it's folded after a click: each question with what was chosen for it, a line
        /// each. The answers alone don't read on their own ("Both · Both"), and the card isn't there any more.
        public var folded: String? {
            guard let answers else { return nil }
            return questions.indices.map { index in
                let question = questions[index].question
                let asked = question.last.map { ".?!…:".contains($0) } == true ? question : question + "?"
                return asked + " " + (answers.indices.contains(index) ? answers[index] : TalkCard.youDecide)
            }.joined(separator: "\n")
        }

        /// The questions as plain words, for everything that reads a chat line's text.
        public var text: String {
            questions.map { question in
                question.question + "\n" + question.options.map { "- " + $0.title }.joined(separator: "\n")
            }.joined(separator: "\n\n")
        }
    }

    /// One thing the agent decided for the person, and the other way it could have gone, from cards saved while
    /// a new app's card showed them as buttons. The agent isn't asked for them any more: beside the picture they
    /// made the card a form to go through, when it's the app itself the person wants to try. Kept so those
    /// chats still read, along with the idea they ended on.
    public struct Guess: Codable, Equatable {
        public var guess: String
        /// The button: the other way, in a few words.
        public var instead: String
        /// What the button sends, as the person would say it.
        public var request: String

        public init(guess: String, instead: String, request: String) {
            self.guess = guess
            self.instead = instead
            self.request = request
        }
    }

    public struct Idea: Codable, Equatable {
        public var title: String
        public var detail: String?
        public var request: String

        public init(title: String, detail: String? = nil, request: String) {
            self.title = title
            self.detail = detail
            self.request = request
        }
    }

    /// Something a change added and where it is, from cards saved while the card listed them as rows. The
    /// agent isn't asked for them any more; the ones already in a chat are kept and shown with the summary, so
    /// an older card still says where to find what it made.
    public struct News: Codable, Equatable {
        public var what: String
        public var place: String

        public init(what: String, place: String) {
            self.what = what
            self.place = place
        }
    }

    public struct Result: Codable, Equatable {
        public var summary: String
        /// Only on cards saved while there were guesses and ideas (see `Guess`); empty or nil on newer ones.
        public var guesses: [Guess]
        public var idea: Idea?
        /// Only on cards saved while there were rows of what's new (see `News`).
        public var news: [News]?
        /// Read from cards saved by an earlier Lamp; not shown.
        public var untried: String?
        /// The word that the request is finished ("Ann Arbor Drive is ready"), heading the card: it takes the
        /// place of the status line that would say it. Missing on cards saved before it was.
        public var status: String?
        /// The version this request made.
        public var version: String?
        /// The guesses the person turned the other way on the card, by their place in `guesses`.
        public var switched: [Int]?

        public init(summary: String, guesses: [Guess] = [], idea: Idea? = nil, news: [News]? = nil, untried: String? = nil,
                    version: String? = nil, switched: [Int]? = nil, status: String? = nil) {
            self.summary = summary
            self.guesses = guesses
            self.idea = idea
            self.news = news
            self.untried = untried
            self.version = version
            self.switched = switched
            self.status = status
        }

        public var text: String {
            // In steps: as one expression it's more than the compiler will type-check in reasonable time.
            var lines: [String] = [summary]
            lines += (news ?? []).map { "- \($0.what): \($0.place)" }
            lines += guesses.map { "- \($0.guess) (or: \($0.instead))" }
            if let idea { lines.append("- Idea: \(idea.title)") }
            if let untried { lines.append("- Not tried: \(untried)") }
            return lines.joined(separator: "\n")
        }
    }
}
