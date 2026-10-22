import XCTest
@testable import Lamp
import LampSidebarKit

/// Each fold of a finished turn's steps reads as what it did and how long it took, once a small model has said so
/// after the turn; until then, when it can't, and in chats from before lines were timed, it reads as it did.
final class StepTitlesTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    /// A turn of two stretches: three steps before "First, the look.", two before the answer.
    private func turn(timed: Bool, titled: Bool) -> [LogLine] {
        func line(_ kind: LogLine.Kind, _ text: String, said: String? = nil, _ seconds: TimeInterval) -> LogLine {
            LogLine(kind: kind, text: text, said: said, at: timed ? at(seconds) : nil)
        }
        var lines = [line(.user, "Make it a beer journal", 0), line(.agent, "I'll look first.", 2),
                     line(.status, "Ran: ls", said: "Looking at the shelf", 5), line(.status, "Ran: cat Shelf.swift", said: "Reading the saved entries", 9),
                     line(.detail, "struct Shelf { let secret = \"hunter2\" }", 10),
                     line(.status, "Ran: grep hot", said: "Finding every hot-sauce word", 14),
                     line(.agent, "First, the look.", 47), line(.status, "Ran: sed", said: "Painting the shelves oak", 50),
                     line(.status, "Ran: swift build", said: "Checking it builds", 61),
                     line(.agent, "It's a beer journal now.", 90), line(.summary, "Worked for 1m 31s · $0.10", 91)]
        if titled {
            lines[2].foldTitle = "Read the shelf and found its hot-sauce words"
            lines[7].foldTitle = "Painted the shelves oak and checked the build"
        }
        return lines
    }

    private func titles(_ lines: [LogLine]) -> [String] {
        ChatItem.items(LogLine.visible(lines, details: false), gather: true).compactMap { item in
            guard case .work(_, let title, _) = item else { return nil }
            return title
        }
    }

    func testATitledFoldSaysWhatItDidAndHowLong() {
        XCTAssertEqual(titles(turn(timed: true, titled: true)),
                       ["Read the shelf and found its hot-sauce words · 42 s", "Painted the shelves oak and checked the build · 40 s"])
    }

    /// Until the title comes, or when it never does, a fold keeps its words; "Worked for…" stays the run's total.
    func testAnUntitledFoldKeepsItsWords() {
        XCTAssertEqual(titles(turn(timed: true, titled: false)), ["3 steps", "Worked for 1 min 31 s"])
    }

    /// A chat from before lines were timed shows no time rather than a guess.
    func testAnOlderChatShowsNoTime() {
        XCTAssertEqual(titles(turn(timed: false, titled: true)),
                       ["Read the shelf and found its hot-sauce words", "Painted the shelves oak and checked the build"])
    }

    /// The model is told the request and the steps' words: never a command, nor what one printed, nor what the agent
    /// said around them, which it took claims from that the steps didn't show.
    @MainActor func testTheModelIsToldOnlyStepsAndWords() {
        let lines = LogLine.visible(turn(timed: true, titled: false), details: false)
        let (request, groups, own) = StepTitles.groups(in: lines)
        XCTAssertEqual(groups.map(\.steps), [["Looking at the shelf", "Reading the saved entries", "Finding every hot-sauce word"],
                                             ["Painting the shelves oak", "Checking it builds"]])
        XCTAssertTrue(own.isEmpty)
        let prompt = StepTitles.prompt(request: request, groups: groups)
        XCTAssertFalse(prompt.contains("hunter2"))
        XCTAssertFalse(prompt.contains("cat Shelf.swift"))
        XCTAssertFalse(prompt.contains("swift build"))
        XCTAssertFalse(prompt.contains("I'll look first."))
        XCTAssertTrue(prompt.contains("Make it a beer journal"))
        // Folds already titled aren't asked about again.
        XCTAssertTrue(StepTitles.groups(in: LogLine.visible(turn(timed: true, titled: true), details: false)).groups.isEmpty)
    }

    /// While the turn goes on, a stretch of steps is asked about as soon as the agent says something after it, so its
    /// title is there when the turn ends; the stretch still going isn't, nor one already titled.
    @MainActor func testAStretchIsTitledOnceSomethingIsSaidAfterIt() {
        let whole = turn(timed: true, titled: false)
        // The turn as it stands when "First, the look." starts: the summary and the answer aren't there yet.
        let live = LogLine.visible(Array(whole[...8]), details: false)
        let (request, groups) = StepTitles.closed(in: live)
        XCTAssertEqual(request, "Make it a beer journal")
        XCTAssertEqual(groups.map(\.steps), [["Looking at the shelf", "Reading the saved entries", "Finding every hot-sauce word"]])
        XCTAssertEqual(groups.map(\.id), [whole[2].id])
        // Before anything is said after the steps, nothing is closed.
        XCTAssertTrue(StepTitles.closed(in: LogLine.visible(Array(whole[...5]), details: false)).groups.isEmpty)
        var titled = whole
        titled[2].foldTitle = "Read the shelf"
        XCTAssertEqual(StepTitles.closed(in: LogLine.visible(Array(titled[...9]), details: false)).groups.map(\.id), [whole[7].id])
    }

    /// A reply that isn't fit to show is no title: the fold keeps its words.
    @MainActor func testOnlyTitlesFitToShowAreKept() {
        let groups = [StepTitles.Group(id: UUID(), steps: ["a", "b"]),
                      StepTitles.Group(id: UUID(), steps: ["c", "d"]),
                      StepTitles.Group(id: UUID(), steps: ["e", "f"]),
                      StepTitles.Group(id: UUID(), steps: ["g", "h"])]
        let reply = #"{"titles": {"1": "\"Read the shelf's saved entries.\"", "2": "Edited ShelfView.swift for the oak look", "#
            + #""3": "Listed Keychain item names and accounts, without secrets", "4": "one two three four five six seven eight nine ten eleven twelve thirteen"}}"#
        XCTAssertEqual(StepTitles.read(reply, groups: groups), [groups[0].id: "Read the shelf's saved entries"])
        XCTAssertEqual(StepTitles.read("not json", groups: groups), [:])
    }

    @MainActor func testTheAnswersOneStepIsItsOwnTitle() {
        let lines = [LogLine(kind: .user, text: "go"), LogLine(kind: .status, text: "Ran: ls", said: "Looking around"),
                     LogLine(kind: .agent, text: "Done."), LogLine(kind: .summary, text: "Worked for 9s · $0")]
        let (_, groups, own) = StepTitles.groups(in: lines)
        XCTAssertTrue(groups.isEmpty)
        XCTAssertEqual(own, [lines[1].id: "Looking around"])
    }

    private func route(_ id: String, _ kind: AppAI.TextRoute.Kind, available: Bool = true) -> AppAI.TextRoute {
        AppAI.TextRoute(id: id, label: id, group: "", name: id, kind: kind, available: available)
    }

    /// A turn built on this Mac is titled on this Mac or not at all, whatever key is saved: the request and the
    /// steps' words never go to the cloud for a turn that stayed here.
    func testALocalTurnIsTitledOnThisMacOrNotAtAll() {
        let openRouter = route("sonnet", .openRouter(model: AppAI.defaultOpenRouterModel))
        let local = route("local:qwen", .localModel(provider: Builder.localProvider, model: "qwen"))
        let routes = [openRouter, local, route("engine:claude:opus", .engine(.claude, model: "opus"))]
        XCTAssertEqual(StepTitles.route(for: .local(model: "qwen"), among: routes)?.route.id, "local:qwen")
        XCTAssertNil(StepTitles.route(for: .local(model: "gone"), among: routes))
        XCTAssertNil(StepTitles.route(for: .local(model: "qwen"), among: [openRouter, route("local:qwen", local.kind, available: false)]))
        // A turn through OpenRouter or a sign-in is titled there, by its small model where it has one.
        XCTAssertEqual(StepTitles.route(for: .openRouter, among: routes)?.route.id, "sonnet")
        XCTAssertEqual(StepTitles.route(for: .engine(.claude), among: routes)?.model, Builder.claudeFastModel)
        XCTAssertNil(StepTitles.route(for: .openRouter, among: [local]))
    }
}
