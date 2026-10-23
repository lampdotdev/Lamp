import XCTest
@testable import Lamp

/// A new app's first build is drawn as its plan's parts, and each line goes under the part it came in. Which part that
/// is goes only by what Lamp is sure of (the plan, the files it lists, the files written); when it can't tell, a line
/// stays with the part the build is on.
final class ChaptersTests: XCTestCase {
    private func building() -> TurnProgress {
        var progress = TurnProgress(newApp: true)
        progress.plan = [
            PlanPart(id: 0, title: "The TV shows a waiting screen and plays the game", done: false,
                     files: ["index.html", "style.css", "app.js"]),
            PlanPart(id: 1, title: "Your phone becomes the controller", done: false, files: ["PadView.swift", "ContentView.swift"]),
            PlanPart(id: 2, title: "Pick the game on your phone and send it to the TV", done: false, files: ["Player.swift"]),
        ]
        return progress
    }

    /// Logs a line the way the store does: its part is decided as it comes, and a written file ticks the plan.
    private func log(_ kind: LogLine.Kind, _ text: String, in progress: inout TurnProgress) -> Int? {
        let part = progress.chapter(for: LogLine(kind: kind, text: text))
        if kind == .tool, let file = TurnProgress.file(changedBy: ToolCall(text)) { progress.wrote(file) }
        return part
    }

    func testWritingALaterPartsFileMovesOnAndEverythingElseStays() {
        var progress = building()
        XCTAssertEqual(log(.progress, "Two apps: one for the TV, one for your phone. TV first.", in: &progress), 0)
        XCTAssertEqual(log(.tool, "write index.html", in: &progress), 0)
        XCTAssertEqual(log(.tool, "write style.css", in: &progress), 0)
        XCTAssertEqual(log(.tool, "write app.js", in: &progress), 0)
        // The first part's files are all written, but checking it is still that part: a look, a command, a read.
        XCTAssertEqual(log(.tool, "look_at_app", in: &progress), 0)
        XCTAssertEqual(log(.status, "Building…", in: &progress), 0)
        XCTAssertEqual(log(.tool, "bash", in: &progress), 0)
        XCTAssertEqual(log(.tool, "read lamp.js", in: &progress), 0)
        // The agent says what's next once the part is done: that's the next part.
        XCTAssertEqual(log(.progress, "The TV plays NES games now. Next, the phone controller.", in: &progress), 1)
        XCTAssertEqual(log(.tool, "write PadView.swift", in: &progress), 1)
        // A file of the last part, written before this part is done: the build has moved on to it.
        XCTAssertEqual(log(.tool, "write Player.swift", in: &progress), 2)
        // Back to a file of an earlier part: which part the fix is for can't be told, so it stays where the build is.
        XCTAssertEqual(log(.tool, "edit PadView.swift", in: &progress), 2)
        XCTAssertEqual(log(.agent, "Sending the game in smaller pieces.", in: &progress), 2)
    }

    /// Something said while the part isn't done yet is part of it, whatever it says.
    func testAMessageBeforeThePartIsDoneStays() {
        var progress = building()
        XCTAssertEqual(log(.tool, "write index.html", in: &progress), 0)
        XCTAssertEqual(log(.progress, "The waiting screen is in. Now the game itself.", in: &progress), 0)
        XCTAssertEqual(log(.ask, "What kind of TV do you have?", in: &progress), 0)
    }

    /// A plan that lists no files is ticked only by the agent: once it says a part is done, the next thing said is the next part.
    func testAPlanWithNoFilesMovesOnWhenThePlanSaysSo() {
        var progress = TurnProgress(newApp: true)
        progress.plan = [PlanPart(id: 0, title: "The board", done: false), PlanPart(id: 1, title: "The pieces", done: false)]
        XCTAssertEqual(log(.tool, "write Board.swift", in: &progress), 0)
        progress.plan[0].done = true
        XCTAssertEqual(log(.tool, "write Pieces.swift", in: &progress), 0)
        XCTAssertEqual(log(.tool, "plan", in: &progress), 1)
    }

    /// No plan, no part; and nothing after the agent's run is over (Lamp's own build and opening).
    func testNoPartWithoutAPlanOrAfterTheRun() {
        var progress = TurnProgress(newApp: true)
        XCTAssertNil(log(.tool, "read App.swift", in: &progress))
        progress = building()
        progress.chaptersClosed = true
        XCTAssertNil(log(.status, "Retro Player is ready", in: &progress))
        var later = TurnProgress(newApp: false)
        later.plan = building().plan
        XCTAssertNil(log(.tool, "write index.html", in: &later))
    }

    private func line(_ kind: LogLine.Kind, _ text: String, part: Int? = nil) -> LogLine {
        var line = LogLine(kind: kind, text: text, at: Date())
        line.part = part
        return line
    }

    private var finished: [LogLine] {
        var summary = line(.summary, "Worked for 4m 29s")
        summary.plan = building().plan.map(\.title)
        return [line(.user, "I want to play smb.nes on my TV using my phone"),
                line(.tool, "read App.swift"),
                line(.progress, "Two apps: one for the TV, one for your phone. TV first.", part: 0),
                line(.tool, "write index.html", part: 0),
                line(.progress, "The TV plays NES games now. Next, the phone controller.", part: 1),
                line(.tool, "write PadView.swift", part: 1),
                line(.progress, "The controller works. Now sending the game across.", part: 2),
                line(.agent, "Retro Player is ready. Open it on your TV, then pick smb.nes on your phone.", part: 2),
                summary,
                line(.status, "Retro Player is ready")]
    }

    /// Over, the build folds to one line with the agent's answer under it, read back from the chat file the same way,
    /// and what came before the plan goes under the first part.
    func testAFinishedBuildFoldsTheSameAfterARelaunch() throws {
        let saved = try JSONDecoder().decode([LogLine].self, from: JSONEncoder().encode(finished))
        let segments = Chapters.segments(saved, progress: nil)
        XCTAssertEqual(segments.count, 3)
        guard case .build(let build) = segments[1] else { return XCTFail("no build in \(segments)") }
        XCTAssertTrue(build.folded)
        XCTAssertEqual(build.foldTitle, "Built it in 3 parts")
        XCTAssertEqual(build.time, "4 min 29 s")
        XCTAssertEqual(build.answer?.text, "Retro Player is ready. Open it on your TV, then pick smb.nes on your phone.")
        XCTAssertEqual(build.parts.map { $0.map(\.text) }, [
            ["read App.swift", "Two apps: one for the TV, one for your phone. TV first.", "write index.html"],
            ["The TV plays NES games now. Next, the phone controller.", "write PadView.swift"],
            ["The controller works. Now sending the game across."],
        ])
        guard case .lines(let after) = segments[2] else { return XCTFail() }
        XCTAssertEqual(after.map(\.text), ["Retro Player is ready"])
    }

    /// A build that asked a question on the way isn't folded: the card stays where it is, under its part.
    func testABuildThatAskedIsntFolded() {
        var lines = finished
        lines.insert(line(.ask, "What kind of TV do you have?", part: 1), at: 6)
        guard case .build(let build) = Chapters.segments(lines, progress: nil)[1] else { return XCTFail() }
        XCTAssertFalse(build.folded)
        XCTAssertNil(build.answer)
        XCTAssertEqual(build.parts[1].last?.kind, .ask)
    }

    /// While it's going, the plan comes from the turn, and a chat without a plan on its summary is drawn as it is.
    func testTheBuildGoingOnTakesItsPlanFromTheTurn() {
        let lines = Array(finished.prefix(6))
        XCTAssertEqual(Chapters.segments(lines, progress: nil).count, 1)
        var progress = building()
        progress.reached = 1
        guard case .build(let build) = Chapters.segments(lines, progress: progress).last else { return XCTFail() }
        XCTAssertTrue(build.live)
        XCTAssertEqual(build.current, 1)
        XCTAssertEqual([0, 1, 2].map(build.state(of:)), [.done, .now, .later])
    }

    /// Seen in a real first build: Lamp asked first, the answer was clicked on its card, and the build that followed
    /// had no request of its own in the chat (the card shows the answer), so it was drawn as any turn, not as chapters.
    func testABuildBegunByAClickedAnswerIsChaptered() {
        var asked = line(.ask, "How should your bank transactions get in?")
        asked.ask = Talk.Ask(layout: .steps, questions: [Talk.Question(question: "How should your bank transactions get in?",
                                                                       options: [Talk.Option(title: "Import bank files")])],
                             answers: ["Import bank files"])
        var answer = line(.user, "How should your bank transactions get in? Import bank files.")
        answer.fromCard = true
        let chat = [line(.user, "A tracker for my monthly spending that pulls in my bank transactions"),
                    line(.agent, "I'll check how you'd like your bank transactions to come in."),
                    asked, line(.summary, "Worked for 12s"), answer] + finished.dropFirst()
        let segments = Chapters.segments(LogLine.visible(chat, details: false), progress: nil)
        guard segments.count == 3, case .build(let build) = segments[1] else { return XCTFail("no build in \(segments)") }
        XCTAssertTrue(build.folded)
        XCTAssertEqual(build.parts[0].first?.text, "Looking things over")
    }

    /// Seen in a real first build: the agent asked, went on to give its plan before Lamp ended the run, and the chat drew
    /// chapters round the card still waiting for its answer, which moved it under the pointer.
    func testAQuestionAskedBeforeThePlanWaitsAsItCame() {
        var asked = line(.ask, "How should the app get your bank transactions?")
        asked.ask = Talk.Ask(layout: .steps, questions: [Talk.Question(question: "How should the app get your bank transactions?",
                                                                       options: [Talk.Option(title: "Bank export file")])])
        var summary = line(.summary, "Worked for 24s")
        summary.plan = ["Menu bar item with this month's total", "Panel with spending details"]
        let chat = [line(.user, "A menu bar item that shows what I've spent this month"),
                    line(.agent, "I'll look at how your bank transactions can reach the app."), asked, line(.tool, "plan"), summary]
        let segments = Chapters.segments(LogLine.visible(chat, details: false), progress: nil)
        XCTAssertEqual(segments.count, 1)
        guard case .lines = segments[0] else { return XCTFail("chapters round a waiting card: \(segments)") }
        // And while the run is still going, with the plan in the turn.
        var progress = building()
        progress.asking = true
        let live = Chapters.segments(LogLine.visible(Array(chat.dropLast()), details: false), progress: progress)
        guard case .build(let build) = live.last else { return XCTFail() }
        XCTAssertTrue(build.titles.isEmpty)
    }

    /// A real first build (a TV game show, 2026-10-23): the plan listed Phone/index.html for its second part, and Lamp
    /// keeps a listed file by its name alone, so writing the TV page's index.html ticked that part too. The agent's
    /// "Now the phone buzzer page." then went past it to the third, and the phone page's part stayed empty.
    func testTheNextThingSaidGoesToTheNextPartEvenWhenItLooksDone() {
        var progress = TurnProgress(newApp: true)
        progress.plan = PlanPart.parts(from: ["parts": [
            ["title": "Lobby with a code for phones to join", "files": ["index.html", "style.css", "qr.js", "about.json"]],
            ["title": "Phone buzzer page", "files": ["Phone/index.html"]],
            ["title": "Question rounds, buzzing and scores", "files": ["questions.js", "app.js"]],
            ["title": "Winner screen", "files": ["APP.md"]],
        ]])
        for file in ["qr.js", "index.html", "style.css", "about.json"] { XCTAssertEqual(log(.tool, "write \(file)", in: &progress), 0) }
        XCTAssertEqual(log(.agent, "Now the phone buzzer page.", in: &progress), 1)
        XCTAssertEqual(log(.tool, "write index.html", in: &progress), 1)
        XCTAssertEqual(log(.tool, "write questions.js", in: &progress), 2)
    }

    /// Seen in a real first build: the bar said Part 2 of 3 while the chat still drew the first part as the one going
    /// on. The chat shows a tool call as a step in plain words, a line made anew, and that line had lost its part, so
    /// every step went under the part of the message before it.
    func testAStepKeepsItsPartInTheChat() {
        let steps = LogLine.visible([line(.user, "a kitchen board"), line(.tool, "write BoardView.swift", part: 0),
                                     line(.tool, "write ShoppingStore.swift", part: 1)], details: false)
        XCTAssertEqual(steps.map(\.part), [nil, 0, 1])
    }

    /// A question asked once the plan had come is in a part, so the build keeps its plan when the run ends on it: without
    /// it the chapters round the waiting card would go and the card would move. One asked before any plan keeps none.
    func testAQuestionAskedInAPartKeepsThePlan() {
        let before = [line(.user, "a game show"), line(.ask, "TV, Mac or both?")]
        XCTAssertFalse(TurnProgress.savesPlan(asked: true, in: before))
        let inPart = [line(.user, "a game show"), line(.tool, "write index.html", part: 0), line(.ask, "How many teams?", part: 0)]
        XCTAssertTrue(TurnProgress.savesPlan(asked: true, in: inPart))
        XCTAssertTrue(TurnProgress.savesPlan(asked: false, in: before))
    }

    /// While Lamp builds and opens the app after the agent's run, what it logs comes after the build's summary and is no
    /// part's: it's drawn after the chapters, not as a second build with the same plan.
    func testLampsOwnBuildAfterTheRunIsNoSecondBuild() {
        var progress = building()
        progress.chaptersClosed = true
        let lines = Array(finished.dropLast()) + [line(.status, "Building…")]
        let segments = Chapters.segments(lines, progress: progress)
        XCTAssertEqual(segments.count, 3)
        guard case .build(let build) = segments[1], case .lines(let after) = segments[2] else { return XCTFail("\(segments)") }
        XCTAssertTrue(build.live)
        XCTAssertEqual(after.map(\.text), ["Building…"])
    }

    /// Two steps in the same words are one step, but not across parts: the later part's step would go, and with it the
    /// only sign in the chat that the build had moved on.
    func testEqualStepsInTwoPartsAreTwoSteps() {
        let steps = LogLine.visible([line(.user, "a kitchen board"), line(.tool, "write BoardView.swift", part: 0),
                                     line(.tool, "write DetailView.swift", part: 1)], details: false)
        XCTAssertEqual(steps.map(\.part), [nil, 0, 1])
    }
}
