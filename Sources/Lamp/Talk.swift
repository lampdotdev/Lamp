import AppKit
import Foundation
import LampSidebarKit

/// The pieces the agent talks to the person with instead of paragraphs: a card of questions answered by
/// clicking (`ask`). The agent
/// chooses the piece and fills it in; Lamp draws it (TalkCards.swift) and turns a click into the person's
/// next message, so to the agent a click and a typed answer arrive the same way. Nothing here waits: the
/// tool returns at once, the agent ends its reply, and the answer starts the next turn. That keeps it the
/// same for every engine, none of which would hold a tool call open for as long as a person takes.
enum Talk {
    // The cards' data, shared with the chat inside each app's window (LampSidebarKit), which draws them too.
    typealias Layout = TalkCard.Layout
    typealias Option = TalkCard.Option
    typealias Question = TalkCard.Question
    typealias Ask = TalkCard.Ask
    typealias Guess = TalkCard.Guess
    typealias Idea = TalkCard.Idea
    typealias News = TalkCard.News
    typealias Result = TalkCard.Result

    static let questionLimit = 4
    static let optionLimit = 4

    /// The most words each piece of a card may have. A card is read at a glance and answered with a click: a
    /// long sentence in it is a paragraph again, set in bold. Too long goes back to the agent to say shorter, so
    /// every engine is held to the same; the tools' descriptions give the same numbers.
    enum Words {
        static let question = 10, option = 4, wish = 40, progress = 12
    }

    static func words(in text: String) -> Int { text.split(whereSeparator: \.isWhitespace).count }

    /// Nil when `text` fits in `limit` words; otherwise what to tell the agent.
    private static func tooLong(_ text: String, _ limit: Int, as what: String) -> Trouble? {
        let count = words(in: text)
        return count <= limit ? nil
            : .message("“\(text)” is \(count) words. Keep \(what) to \(limit) words or fewer, and call again.")
    }

    enum Trouble: Error, Equatable {
        case message(String)
        var text: String { switch self { case .message(let text): text } }
    }

    /// Said after every refusal of `ask`. Between a refusal and its retry the agent tends to say something about
    /// the fix ("Shortening the answers."), which reads as a non sequitur to someone who never saw the card.
    static let askNotShown = "These questions were not shown. Correct the arguments and call ask again without sending an intervening message."

    /// The agent's `ask` arguments, checked. What's wrong goes back to the agent in words it can act on.
    static func ask(from arguments: [String: Any], hasSymbol: (String) -> Bool = Talk.hasSymbol) -> Swift.Result<Ask, Trouble> {
        checkedAsk(arguments, hasSymbol: hasSymbol).mapError { .message($0.text + " " + askNotShown) }
    }

    private static func checkedAsk(_ arguments: [String: Any], hasSymbol: (String) -> Bool) -> Swift.Result<Ask, Trouble> {
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
            if let trouble = tooLong(question, Words.question, as: "a question") { return .failure(trouble) }
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
            for option in options {
                if let trouble = tooLong(option.title, Words.option, as: "an answer's `title` (more goes in `detail`)") { return .failure(trouble) }
            }
            questions.append(Question(question: question, options: options))
        }
        // One question has nothing to lay out together.
        return .success(Ask(layout: layout ?? .steps, questions: questions))
    }

    /// The agent's `progress` line, checked: its words, or nil when it says what the turn's last line said
    /// already (a line repeated would only look stuck).
    static func progress(from arguments: [String: Any], after lines: [LogLine]) -> Swift.Result<String?, Trouble> {
        let text = (arguments["text"] as? String)?.trimmed ?? ""
        guard !text.isEmpty else { return .failure(.message("Give the line in `text`.")) }
        if let trouble = tooLong(text, Words.progress, as: "a progress line") { return .failure(trouble) }
        let turn = lines.lastIndex { $0.kind == .user }.map { lines[($0 + 1)...] } ?? lines[...]
        return .success(turn.last { $0.kind == .progress }?.text == text ? nil : text)
    }

    static func hasSymbol(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    /// What a question is answered with when the person leaves it to Lamp.
    static let youDecide = TalkCard.youDecide

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

    /// Notes a click's answers on its card, only while it still waits for them. A card stays clickable until
    /// the chat has drawn it folded, which in the sidebar takes a trip through another process, so while Lamp is
    /// slow it can be clicked again, and each click would queue the answer once more. Returns the card as
    /// answered, or nil when it had been answered already, by a click or in words.
    static func give(_ answers: [String], to card: UUID, in lines: inout [LogLine]) -> Ask? {
        guard open(in: lines)?.id == card, let index = lines.firstIndex(where: { $0.id == card }),
              var ask = lines[index].ask else { return nil }
        ask.answers = answers
        lines[index].ask = ask
        return ask
    }

    /// The card that holds the wish up until it's answered: an open one the agent asked. A starter's offer
    /// (`Ask.offer`) is open too, and the message box answers it, but the wish can be used meanwhile.
    static func waiting(in lines: [LogLine]) -> LogLine? {
        guard let open = open(in: lines), open.ask?.offer != true else { return nil }
        return open
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

    /// The waiting message whose answers were clicked on `card`, which the folded card stands for until it's sent
    /// (`AskWaiting`), so the chat never shows it and then takes it away.
    static func waiting(on card: LogLine, in queue: [QueuedMessage]) -> QueuedMessage? {
        guard card.ask?.answers != nil else { return nil }
        return queue.first { $0.card == card.id }
    }

    /// The waiting messages drawn as such: not those a folded card stands for, and not Lamp's own that carries a
    /// paused request on after Reload (`Store.pause`), which the Reload line stands for.
    static func drawnWaiting(_ queue: [QueuedMessage], in lines: [LogLine]) -> [QueuedMessage] {
        let clicked = Set(lines.filter { $0.ask?.answers != nil }.map(\.id))
        return queue.filter { message in !message.afterReload && (message.card.map { !clicked.contains($0) } ?? true) }
    }

    /// The messages a card shows, which the chat leaves out. A guess turned on a result card saved by an earlier Lamp was
    /// shown only by that card, which no longer is, so its message shows again: a message clicked on a card
    /// stays hidden only when the card before it is a question card.
    static func cardMessages(in lines: [LogLine]) -> Set<UUID> {
        var lastCard: LogLine.Kind?
        var hidden: Set<UUID> = []
        for line in lines {
            if line.kind == .ask || line.kind == .result { lastCard = line.kind }
            if line.fromCard == true, lastCard == .ask { hidden.insert(line.id) }
        }
        return hidden
    }

    static let told = "The person sees that line in the chat. Carry on with the work."
    static let saidAlready = "That's what the last line said, so it wasn't shown again. Carry on with the work."

    static let asked = "The person now sees your questions as a card and answers by clicking or typing. Your turn ends here: change nothing and call nothing more. Their answer is the next message: one line for each question, in the order you asked, each question followed by its answer, or their own words."
    static let alreadyAsked = "The person already sees the questions you asked and hasn't answered yet, so these weren't shown. End your reply now with no more words; their answer is the next message."
}
