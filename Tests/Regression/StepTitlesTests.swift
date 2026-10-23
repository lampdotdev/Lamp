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
        // The next turn's first message closes nothing of this one: what came after its summary is its own end.
        let next = whole + [LogLine(kind: .status, text: "Building…", at: at(92)), LogLine(kind: .status, text: "Hot Shelf is updated", at: at(93)),
                            LogLine(kind: .user, text: "Now a dark mode", at: at(100)), LogLine(kind: .agent, text: "On it.", at: at(102))]
        let (nextRequest, nextGroups) = StepTitles.closed(in: LogLine.visible(next, details: false))
        XCTAssertEqual(nextRequest, "Now a dark mode")
        XCTAssertTrue(nextGroups.isEmpty)
    }

    /// While the turn goes on, a stretch the agent has said something after folds to its one line, its title once it
    /// has one; the stretch still going stays open, its steps rows.
    func testAClosedStretchFoldsWhileTheTurnGoesOn() {
        let live = Array(turn(timed: true, titled: false)[...8])
        XCTAssertEqual(titles(live), ["3 steps"])
        XCTAssertEqual(titles(Array(turn(timed: true, titled: true)[...8])), ["Read the shelf and found its hot-sauce words · 42 s"])
        let items = ChatItem.items(LogLine.visible(live, details: false), gather: true)
        XCTAssertEqual(items.filter { if case .work = $0 { return false }; return true }.flatMap { item -> [String] in
            switch item {
            case .line(let line): [line.text]
            case .statuses(let lines), .tools(let lines): lines.map(\.text)
            case .work: []
            }
        }, ["Make it a beer journal", "I'll look first.", "First, the look.", "Ran: sed", "Ran: swift build"])
    }

    /// A stretch asked about while the turn went on is asked about once: one whose title failed, or was turned away,
    /// isn't asked again, and paid for again, at every later message. The call at the turn's end is its one more try.
    @MainActor func testAFailedEarlyTitleIsNotAskedAgainAtTheNextMessage() async {
        final class Calls { var groups: [[String]] = [] }
        let calls = Calls()
        let saved = StepTitles.asker
        defer { StepTitles.asker = saved }
        StepTitles.asker = { _, groups, _, _ in
            await MainActor.run { calls.groups += groups.map(\.steps) }
            return nil
        }
        let whole = turn(timed: true, titled: false)
        // "First, the look." closes the first stretch; "It's a beer journal now." closes the second.
        for lines in [Array(whole[...8]), Array(whole[...9])] {
            for task in StepTitles.askEarly(LogLine.visible(lines, details: false), turn: .openRouter, apply: { _ in }) { await task.value }
        }
        XCTAssertEqual(calls.groups, [["Looking at the shelf", "Reading the saved entries", "Finding every hot-sauce word"],
                                      ["Painting the shelves oak", "Checking it builds"]])
    }

    /// The call at the turn's end is a fold's last: when its title is turned away, or the call fails, it's asked
    /// for once more straight away, told why when its title was turned away, and then left with its words.
    @MainActor func testTheTurnsEndTriesOnceMoreWhenItsTitleIsTurnedAwayOrTheCallFails() async {
        final class Calls { var again: [Bool] = [] }
        let saved = StepTitles.asker
        defer { StepTitles.asker = saved }
        let lines = LogLine.visible(turn(timed: true, titled: false), details: false)
        let (_, groups, _) = StepTitles.groups(in: lines)
        let first = groups[0].id, second = groups[1].id
        // A reply that parsed but whose second title wasn't fit to show, then one that failed outright.
        for firstReply in [[first: "Read the shelf"], nil] as [[UUID: String]?] {
            let calls = Calls()
            StepTitles.asker = { _, asked, _, again in
                await MainActor.run { calls.again.append(again) }
                if calls.again.count == 1 { return firstReply }
                return Dictionary(uniqueKeysWithValues: asked.map { ($0.id, "Titled on the second try") })
            }
            var applied: [UUID: String] = [:]
            await StepTitles.askAtEnd(lines, turn: .openRouter) { applied = $0 }.value
            XCTAssertEqual(calls.again, [false, firstReply != nil])
            XCTAssertEqual(applied[second], "Titled on the second try")
            XCTAssertEqual(applied[first], firstReply == nil ? "Titled on the second try" : "Read the shelf")
        }
        // Twice turned away is the end of it: no third call.
        let calls = Calls()
        StepTitles.asker = { _, _, _, again in
            await MainActor.run { calls.again.append(again) }
            return [:]
        }
        var applied: [UUID: String]? = nil
        await StepTitles.askAtEnd(lines, turn: .openRouter) { applied = $0 }.value
        XCTAssertEqual(calls.again, [false, true])
        XCTAssertEqual(applied, [:])
    }

    /// A fold whose call is still out when the turn ends isn't asked about twice at once; if that call then comes
    /// to nothing, the turn's end is tried for it then, rather than never.
    @MainActor func testAFoldStillBeingAskedAboutWhenTheTurnEndsIsTriedOnceItsCallFails() async {
        final class Calls { var groups: [[String]] = []; var held: CheckedContinuation<[UUID: String]?, Never>? }
        let calls = Calls()
        let saved = StepTitles.asker
        defer { StepTitles.asker = saved }
        StepTitles.asker = { _, groups, _, _ in
            let first = await MainActor.run { calls.groups += groups.map(\.steps); return calls.groups.count == 1 }
            // The early call hangs on until the test lets it fail.
            if first { return await withCheckedContinuation { held in Task { @MainActor in calls.held = held } } }
            return Dictionary(uniqueKeysWithValues: groups.map { ($0.id, "Read the shelf") })
        }
        let whole = turn(timed: true, titled: false)
        let early = StepTitles.askEarly(LogLine.visible(Array(whole[...8]), details: false), turn: .openRouter, apply: { _ in })
        while calls.held == nil { await Task.yield() }
        var applied: [UUID: String] = [:]
        await StepTitles.askAtEnd(LogLine.visible(whole, details: false), turn: .openRouter) { applied.merge($0) { $1 } }.value
        // The turn's end asked only for the fold nobody was asking about.
        XCTAssertEqual(calls.groups, [["Looking at the shelf", "Reading the saved entries", "Finding every hot-sauce word"],
                                      ["Painting the shelves oak", "Checking it builds"]])
        calls.held?.resume(returning: nil)
        for task in early { await task.value }
        XCTAssertEqual(calls.groups.count, 3)
        XCTAssertEqual(calls.groups.last, ["Looking at the shelf", "Reading the saved entries", "Finding every hot-sauce word"])
        XCTAssertEqual(applied[whole[2].id], "Read the shelf")
    }

    /// A title asked of Claude Code or Codex that doesn't come is given up at its time limit, its engine ended,
    /// rather than held on to for good.
    @MainActor func testATitleCallThroughAnEngineEndsAtItsTimeLimit() async throws {
        let savedFolder = EngineInstall.folder, savedFinder = EngineInstall.finder
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-titles-\(UUID().uuidString)")
        defer {
            EngineInstall.folder = savedFolder
            EngineInstall.finder = savedFinder
            EngineInstall.lookNow()
            try? FileManager.default.removeItem(at: root)
        }
        let stuck = root.appendingPathComponent("claude")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: stuck.path, contents: Data("#!/bin/sh\nexec sleep 60\n".utf8),
                                       attributes: [.posixPermissions: 0o755])
        EngineInstall.folder = root
        EngineInstall.finder = { $0 == .claude ? stuck.path : nil }
        EngineInstall.lookNow()
        let began = Date()
        do {
            _ = try await AppAI.complete(prompt: "Group 1", images: [], system: StepTitles.system, json: true,
                                         via: route("engine:claude:haiku", .engine(.claude, model: "haiku")), timeLimit: 2)
            XCTFail("a stuck engine answered")
        } catch {
            XCTAssertEqual(error.localizedDescription, "\(Engine.claude.title) took too long to answer.")
        }
        XCTAssertLessThan(Date().timeIntervalSince(began), 20)
    }

    /// Whatever the turn says, it closes the steps before it, so each closed stretch is titled as it closes: the
    /// lines Lamp puts in the chat itself for a tool (a progress line, a question card) as much as a message or what
    /// `log` adds. The lines are added in the gateway's handler, which runs with Lamp itself, so the check reads it.
    func testEveryLineSaidInATurnClosesTheStepsBeforeIt() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let store = try String(contentsOf: root.appendingPathComponent("Sources/Lamp/Store.swift"), encoding: .utf8)
            .components(separatedBy: "\n")
        let appends = store.indices.filter { store[$0].contains("logs[project.id, default: []].append(LogLine(kind: .") }
        XCTAssertFalse(appends.isEmpty)
        for index in appends {
            let kind = store[index].firstMatch(of: #/kind: \.(\w+)/#).map { String($0.1) } ?? "?"
            XCTAssertTrue(store[index...min(index + 3, store.count - 1)].contains { $0.contains("closeSteps(project)") },
                          "the \(kind) line added at Store.swift:\(index + 1) doesn't close the steps before it")
        }
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
