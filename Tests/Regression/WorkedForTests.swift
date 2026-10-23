import XCTest
@testable import Lamp
import LampSidebarKit

/// The chat reads in the order things happened: a finished turn's steps fold where they came, the ones before its
/// answer into "Worked for …"; a turn still going keeps the steps since it last said something in its live line
/// (`ChatItem.live`), and the ones before stay where they came.
final class WorkedForTests: XCTestCase {
    func testAFinishedTurnsStepsFoldWhereTheyCame() {
        let lines = [LogLine(kind: .user, text: "make it"), LogLine(kind: .status, text: "Ran: ls"),
                     LogLine(kind: .status, text: "Building…"), LogLine(kind: .status, text: ChatLook.fixingCrash),
                     LogLine(kind: .agent, text: "Done."), LogLine(kind: .status, text: "Puzzle is ready"),
                     LogLine(kind: .summary, text: "Worked for 2m 3s · $0.12"),
                     LogLine(kind: .user, text: "more"), LogLine(kind: .status, text: "Ran: pwd")]
        let items = ChatItem.items(lines, gather: true)
        let shape = items.map { item -> String in
            switch item {
            case .line(let line): line.text
            case .statuses(let run): "statuses:" + run.map(\.text).joined(separator: ",")
            case .tools: "tools"
            case .work(_, let title, let steps): "\(title):" + steps.map(\.text).joined(separator: ",")
            }
        }
        XCTAssertEqual(shape, ["make it", "Worked for 2 min 3 s:Ran: ls,Building…", "statuses:\(ChatLook.fixingCrash)", "Done.",
                               "statuses:Puzzle is ready", "more", "statuses:Ran: pwd"])
    }

    /// A card answered by a click leaves no request in the chat, and Lamp starts runs of its own: each run still
    /// gets its own fold, and a run with no summary yet isn't folded under the one before.
    func testRunsEndAtTheirSummaries() {
        let lines = [LogLine(kind: .user, text: "make it"), LogLine(kind: .status, text: "Ran: ls"),
                     LogLine(kind: .ask, text: "which?", ask: Talk.Ask(layout: .steps, questions: [], answers: ["A"])),
                     LogLine(kind: .summary, text: "Worked for 5s · $0"),
                     LogLine(kind: .status, text: "Ran: pwd"), LogLine(kind: .agent, text: "Done."),
                     LogLine(kind: .summary, text: "Worked for 9s · $0"),
                     LogLine(kind: .status, text: "Building…")]
        let shape = ChatItem.items(lines, gather: true).map { item -> String in
            switch item {
            case .line(let line): line.text
            case .statuses(let run): "statuses:" + run.map(\.text).joined(separator: ",")
            case .tools: "tools"
            case .work(_, let title, let steps): "\(title):" + steps.map(\.text).joined(separator: ",")
            }
        }
        XCTAssertEqual(shape, ["make it", "Worked for 5 s:Ran: ls", "which?", "Worked for 9 s:Ran: pwd", "Done.",
                               "statuses:Building…"])
    }

    /// A fix Lamp starts on its own after a crash sends a request the chat doesn't show, so the line saying why the
    /// agent is at work stays in sight, in its place, instead of going into its steps with nothing asked above it.
    func testACrashFixLampStartedSaysSo() {
        var request = LogLine(kind: .user, text: "Fix the crash.")
        request.byLamp = true
        let lines = [LogLine(kind: .agent, text: "You now have a counter."), LogLine(kind: .summary, text: "Worked for 1m 16s · $0.08"),
                     LogLine(kind: .status, text: "Crash Counter is ready"), LogLine(kind: .status, text: ChatLook.fixingCrash),
                     request, LogLine(kind: .tool, text: "edit ContentView.swift"),
                     LogLine(kind: .agent, text: "Crash Now no longer crashes the app."),
                     LogLine(kind: .summary, text: "Worked for 15s · $0.08"), LogLine(kind: .status, text: "Building…"),
                     LogLine(kind: .status, text: "Crash Counter is ready")]
        let shape = ChatItem.items(LogLine.visible(lines, details: false), gather: true).map { item -> String in
            switch item {
            case .line(let line): line.text
            case .statuses(let run): "statuses:" + run.map(\.text).joined(separator: ",")
            case .tools: "tools"
            case .work(_, let title, let steps): "\(title):" + steps.map(\.text).joined(separator: ",")
            }
        }
        XCTAssertEqual(shape, ["You now have a counter.", "statuses:Crash Counter is ready", "statuses:\(ChatLook.fixingCrash)",
                               "Worked for 15 s:Working on the interface", "Crash Now no longer crashes the app.",
                               "statuses:Crash Counter is ready"])
    }

    func testHowLongItWorked() {
        XCTAssertEqual(ChatItem.workedFor("Worked for 8s · $0.01"), "Worked for 8 s")
        XCTAssertEqual(ChatItem.workedFor("Worked for 3m 0s · $0.01"), "Worked for 3 min")
        XCTAssertEqual(ChatItem.workedFor("Worked for 1m 5s · $0.01"), "Worked for 1 min 5 s")
    }

    /// While a turn goes on, the steps since it last said something aren't rows of their own but what its live line
    /// opens to; the steps before that stay rows where they came, between what it said, as Dan asked: "eyes naturally
    /// follow the chat, newest at the bottom always".
    func testATurnGoingOnKeepsItsStepsInOrder() {
        let lines = [LogLine(kind: .agent, text: "Done before."), LogLine(kind: .summary, text: "Worked for 9s · $0"),
                     LogLine(kind: .status, text: "Shelf is ready"), LogLine(kind: .user, text: "make it beer"),
                     LogLine(kind: .agent, text: "I'll look first."), LogLine(kind: .status, text: "Ran: ls", said: "Looking around"),
                     LogLine(kind: .status, text: "Ran: grep hot", said: "Finding every mention"),
                     LogLine(kind: .agent, text: "Now the words."), LogLine(kind: .status, text: "Ran: sed", said: "Changing the words"),
                     LogLine(kind: .status, text: "Building…")]
        let live = ChatItem.live(lines)
        XCTAssertEqual(live.shown.map(\.text), ["Done before.", "Worked for 9s · $0", "Shelf is ready", "make it beer",
                                                 "I'll look first.", "Ran: ls", "Ran: grep hot", "Now the words."])
        // The step still going ("Building…") is what the line itself says.
        XCTAssertEqual(live.steps.map(\.said), ["Changing the words"])
    }

    /// A turn that only read, searched and edited files, and looked at the app, ran no command: its steps are what the
    /// line said while each call ran, never the calls' file names, and they're there while it goes on and in its
    /// "Worked for…". These are a real turn's lines up to its second look's build.
    func testATurnOfFileToolsHasStepsInPlainWords() {
        let lines = [LogLine(kind: .user, text: "Add a filter row"), LogLine(kind: .detail, text: "Warning: new session"),
                     LogLine(kind: .agent, text: "I'll add the heat filter row under the title."),
                     LogLine(kind: .tool, text: "read APP.md"), LogLine(kind: .tool, text: "find Sources/*.swift"),
                     LogLine(kind: .tool, text: "read ShelfView.swift"), LogLine(kind: .tool, text: "grep Model.swift"),
                     LogLine(kind: .agent, text: "Filter by the peppers shown (intensity)."),
                     LogLine(kind: .tool, text: "edit ShelfView.swift"), LogLine(kind: .tool, text: "look_at_app"),
                     LogLine(kind: .status, text: "Building…"), LogLine(kind: .detail, text: "Build failed: warning"),
                     LogLine(kind: .tool, text: "edit ShelfView.swift"), LogLine(kind: .tool, text: "look_at_app"),
                     LogLine(kind: .status, text: "Building…")]
        let visible = LogLine.visible(lines, details: false)
        let live = ChatItem.live(visible)
        XCTAssertEqual(live.shown.map(\.text), ["Add a filter row", "I'll add the heat filter row under the title.",
                                                 "Looking things over", "Filter by the peppers shown (intensity)."])
        XCTAssertEqual(live.steps.map(\.text), ["Working on the interface", "Checking how it looks",
                                                 "Building…", "Working on the interface", "Checking how it looks"])
        XCTAssertFalse(live.steps.contains { $0.text.contains(".swift") || $0.text.contains(".md") })
        // Agent Details still shows the calls themselves.
        XCTAssertEqual(LogLine.visible(lines, details: true).filter { $0.kind == .tool }.count, 8)
        // Not a command's call, though: its "Ran: …" row says it, by its name.
        let command = [LogLine(kind: .tool, text: "bash swift build", said: "Checking it builds"),
                       LogLine(kind: .status, text: "Ran: swift build", said: "Checking it builds")]
        XCTAssertEqual(LogLine.visible(command, details: true).map(\.text), ["Ran: swift build"])
        // Over, the same steps are what "Worked for…" opens to, the ones before the message still before it.
        let done = visible + LogLine.visible([LogLine(kind: .agent, text: "Done."), LogLine(kind: .summary, text: "Worked for 3m 56s · $0.18")], details: false)
        guard let steps = worked(ChatItem.items(done, gather: true)) else { return XCTFail("no Worked for") }
        // As on any turn, a build there is a step only until the next one.
        XCTAssertEqual(steps.map(\.text), ["Working on the interface", "Checking how it looks",
                                            "Working on the interface", "Checking how it looks", "Building…"])
        // A look again after a build that went before it is one step, not the same words twice.
        let looks = lines.prefix(10) + [LogLine(kind: .status, text: "Building…"), LogLine(kind: .tool, text: "look_at_app"), LogLine(kind: .agent, text: "Done."),
                                         LogLine(kind: .summary, text: "Worked for 1m 0s · $0.01")]
        guard let again = worked(ChatItem.items(LogLine.visible(Array(looks), details: false), gather: true)) else {
            return XCTFail("no Worked for")
        }
        XCTAssertEqual(again.map(\.text), ["Working on the interface", "Checking how it looks"])
    }

    /// A command is logged as a call and as its own row: only the row, by its name, is a step, so commands the agent
    /// gave one name to stay one step.
    func testACommandIsOneStepByItsName() {
        let lines = [LogLine(kind: .user, text: "check it"), LogLine(kind: .tool, text: "bash ls Sources"),
                     LogLine(kind: .status, text: "Ran: ls Sources", said: "Looking around"),
                     LogLine(kind: .tool, text: "bash grep heat"), LogLine(kind: .status, text: "Ran: grep heat", said: "Looking around"),
                     // File work named after the command before it is part of that step, not the same words again.
                     LogLine(kind: .tool, text: "read Model.swift", said: "Looking around"),
                     LogLine(kind: .tool, text: "read Shelf.swift"), LogLine(kind: .agent, text: "Done."),
                     LogLine(kind: .summary, text: "Worked for 9s · $0")]
        let visible = LogLine.visible(lines, details: false)
        XCTAssertEqual(ChatItem.live(Array(visible.prefix(4))).steps.map { $0.said ?? $0.text },
                       ["Looking around", "Looking around", "Looking things over"])
        guard let steps = worked(ChatItem.items(visible, gather: true)) else { return XCTFail("no Worked for") }
        XCTAssertEqual(steps.map { $0.said ?? $0.text }, ["Looking around", "Looking things over"])
        XCTAssertEqual(steps.first?.text, "Ran: ls Sources\ngrep heat")
    }

    /// A command's row can be logged after file work named after it (calls made together, the command still
    /// running): the file work is part of that row, so the name shows once, in the live line and in "Worked for…".
    func testFileWorkBeforeItsCommandsRowIsThatRow() {
        let lines = [LogLine(kind: .user, text: "make it a beer tracker"),
                     LogLine(kind: .tool, text: "read Model.swift", said: "Reading how the shelf works"),
                     LogLine(kind: .tool, text: "bash grep -rn label Sources", said: "Reading how labels and pictures are found"),
                     LogLine(kind: .tool, text: "read Label.swift", said: "Reading how labels and pictures are found"),
                     LogLine(kind: .status, text: "Ran: grep -rn label Sources", said: "Reading how labels and pictures are found"),
                     LogLine(kind: .tool, text: "bash grep -rn hot Sources", said: "Finding every hot-sauce word and number"),
                     LogLine(kind: .status, text: "Ran: grep -rn hot Sources", said: "Finding every hot-sauce word and number")]
        let visible = LogLine.visible(lines, details: false)
        let live = ChatItem.items(ChatItem.live(visible, doing: Activity.thinking).steps)
        XCTAssertEqual(live.flatMap { item -> [String] in
            guard case .statuses(let run) = item else { return [] }
            return run.map { $0.said ?? $0.text }
        }, ["Reading how the shelf works", "Reading how labels and pictures are found", "Finding every hot-sauce word and number"])
        let done = visible + [LogLine(kind: .agent, text: "Done."), LogLine(kind: .summary, text: "Worked for 9s · $0")]
        guard let steps = worked(ChatItem.items(done, gather: true)) else { return XCTFail("no Worked for") }
        XCTAssertEqual(steps.map { $0.said ?? $0.text },
                       ["Reading how the shelf works", "Reading how labels and pictures are found", "Finding every hot-sauce word and number"])
    }

    /// The step the turn is still on is what the line at the bottom says, not a step done yet: it joins the list above
    /// the line once the agent moves on (it writes, it thinks, it starts another step).
    func testTheStepGoingOnIsTheLineNotAStepDone() {
        let going = LogLine.visible([LogLine(kind: .user, text: "add a filter"), LogLine(kind: .tool, text: "read ShelfView.swift"),
                                     LogLine(kind: .tool, text: "edit ShelfView.swift")], details: false)
        XCTAssertEqual(ChatItem.live(going, doing: "Working on the interface").steps.map(\.text), ["Looking things over"])
        // Thinking after it, the edit is done.
        XCTAssertEqual(ChatItem.live(going, doing: Activity.thinking).steps.map(\.text), ["Looking things over", "Working on the interface"])
        // So it is once the agent says something after it: the steps stay above what it said, and the line starts afresh.
        let said = going + [LogLine(kind: .agent, text: "Now the buttons.")]
        XCTAssertEqual(ChatItem.live(said, doing: "Replying").shown.map(\.text),
                       ["add a filter", "Looking things over", "Working on the interface", "Now the buttons."])
        XCTAssertEqual(ChatItem.live(said, doing: "Replying").steps.map(\.text), [])
        // While Lamp looks at the app, the line says the look's stages: the look is still going.
        let look = going + LogLine.visible([LogLine(kind: .tool, text: "look_at_app"), LogLine(kind: .status, text: "Building…")], details: false)
        XCTAssertEqual(ChatItem.live(look, doing: "Building…", looking: true).steps.map(\.text), ["Looking things over", "Working on the interface"])
        XCTAssertEqual(ChatItem.live(look, doing: "Opening Hot Shelf…", looking: true).steps.map(\.text), ["Looking things over", "Working on the interface"])
        // Once the look is over and the next call is being written, the look is done.
        XCTAssertEqual(ChatItem.live(look, doing: "Working on the interface").steps.map(\.text),
                       ["Looking things over", "Working on the interface", "Checking how it looks"])
        // The next call being written says its words before it's logged: the edit before it is done.
        XCTAssertEqual(ChatItem.live(going, doing: "Looking things over").steps.map(\.text), ["Looking things over", "Working on the interface"])
        // So is a command named from Codex's reasoning before its row is logged, whatever its name.
        XCTAssertEqual(ChatItem.live(going, doing: "Checking it builds").steps.map(\.text), ["Looking things over", "Working on the interface"])
        // A named command running is the line's words, and done it's a step by that name.
        let command = going + [LogLine(kind: .status, text: "Ran: swift build", said: "Checking it builds")]
        XCTAssertEqual(ChatItem.live(command, doing: "Checking it builds").steps.map { $0.said ?? $0.text },
                       ["Looking things over", "Working on the interface"])
    }

    /// The steps a "Worked for…" opens to, wherever it is in the chat.
    private func worked(_ items: [ChatItem]) -> [LogLine]? {
        items.lazy.compactMap { item -> [LogLine]? in
            guard case .work(_, let title, let steps) = item, title.hasPrefix("Worked") else { return nil }
            return steps
        }.first
    }

    /// Steps before something said, other than the answer's, fold to how many they were; one is just itself.
    func testStepsBetweenMessagesFoldInPlace() {
        let lines = [LogLine(kind: .user, text: "go"), LogLine(kind: .status, text: "Ran: ls", said: "Looking around"),
                     LogLine(kind: .status, text: "Ran: cat", said: "Reading the shelf"),
                     LogLine(kind: .agent, text: "First, the look."), LogLine(kind: .status, text: "Ran: sed", said: "Painting"),
                     LogLine(kind: .reload, text: ""), LogLine(kind: .status, text: "Ran: swift build", said: "Checking it builds"),
                     LogLine(kind: .agent, text: "Done."), LogLine(kind: .summary, text: "Worked for 9s · $0")]
        let shape = ChatItem.items(lines, gather: true).map { item -> String in
            switch item {
            case .line(let line): line.kind == .reload ? "Reload" : line.text
            case .statuses(let run): "statuses:" + run.map { $0.said ?? $0.text }.joined(separator: ",")
            case .tools: "tools"
            case .work(_, let title, let steps): "\(title):" + steps.map { $0.said ?? $0.text }.joined(separator: ",")
            }
        }
        XCTAssertEqual(shape, ["go", "2 steps:Looking around,Reading the shelf", "First, the look.", "statuses:Painting",
                               "Reload", "Worked for 9 s:Checking it builds", "Done."])
    }

    /// A Reload line that's spent (the change went in) isn't shown, so it can't split the turn: the steps on either side
    /// of it are one stretch, and every step is in exactly one place, in the chat or in the live line. Each chat's two
    /// halves once read the turn with and without that line, and a step before it went missing from both.
    @MainActor func testASpentReloadDoesntHideTheStepsBeforeIt() {
        let project = LampProject(id: "spent-reload", name: "Shelf", exe: "Shelf", dir: URL(fileURLWithPath: "/tmp/spent-reload"))
        let log = [LogLine(kind: .user, text: "go"), LogLine(kind: .agent, text: "First, the look."),
                   LogLine(kind: .status, text: "Ran: ls", said: "Step A"), LogLine(kind: .reload, text: ""),
                   LogLine(kind: .status, text: "Ran: pwd", said: "Step B")]
        let chat = SidebarServer.lines(log, project: project, busy: true, progressShown: true).compactMap(\.said)
        let live = (SidebarServer.liveSteps(log, project: project, details: false, doing: Activity.thinking) ?? []).compactMap(\.said)
        XCTAssertEqual((chat + live).sorted(), ["Step A", "Step B"])
        // Lamp's window splits it the same way: what its live line opens to and what its transcript leaves out agree.
        let partition = ChatItem.live(log, dir: project.dir, doing: Activity.thinking)
        XCTAssertEqual(partition.steps.compactMap(\.said), live)
        XCTAssertFalse(partition.shown.contains { $0.said != nil })
    }
}
