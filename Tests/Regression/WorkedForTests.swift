import XCTest
@testable import Lamp
import LampSidebarKit

/// A finished turn's steps are gathered into one "Worked for …" line at its end, where the line saying what it was
/// doing stood while it went on; a turn still going keeps its steps in that line (`ChatItem.live`).
final class WorkedForTests: XCTestCase {
    func testAFinishedTurnsStepsGoUnderItsAnswer() {
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
        XCTAssertEqual(shape, ["make it", "statuses:\(ChatLook.fixingCrash)", "Done.", "Worked for 2 min 3 s:Ran: ls,Puzzle is ready",
                               "more", "statuses:Ran: pwd"])
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
        XCTAssertEqual(shape, ["make it", "which?", "Worked for 5 s:Ran: ls", "Done.", "Worked for 9 s:Ran: pwd",
                               "statuses:Building…"])
    }

    /// A fix Lamp starts on its own after a crash sends a request the chat doesn't show, so the line saying why the
    /// agent is at work stays in sight, above the fold, instead of going into its steps with nothing asked above it.
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
        XCTAssertEqual(shape, ["You now have a counter.", "statuses:\(ChatLook.fixingCrash)",
                               "Crash Now no longer crashes the app.", "Worked for 15 s:Crash Counter is ready,Working on the interface",
                               "statuses:Crash Counter is ready"])
    }

    func testHowLongItWorked() {
        XCTAssertEqual(ChatItem.workedFor("Worked for 8s · $0.01"), "Worked for 8 s")
        XCTAssertEqual(ChatItem.workedFor("Worked for 3m 0s · $0.01"), "Worked for 3 min")
        XCTAssertEqual(ChatItem.workedFor("Worked for 1m 5s · $0.01"), "Worked for 1 min 5 s")
    }

    /// While a turn goes on, its steps aren't rows of their own but what its one live line opens to; what it says stays
    /// in the chat, and what came after the summary of the turn before stays where it was.
    func testATurnGoingOnKeepsItsStepsInItsLine() {
        let lines = [LogLine(kind: .agent, text: "Done before."), LogLine(kind: .summary, text: "Worked for 9s · $0"),
                     LogLine(kind: .status, text: "Shelf is ready"), LogLine(kind: .user, text: "make it beer"),
                     LogLine(kind: .agent, text: "I'll look first."), LogLine(kind: .status, text: "Ran: ls", said: "Looking around"),
                     LogLine(kind: .status, text: "Ran: grep hot", said: "Finding every mention"),
                     LogLine(kind: .agent, text: "Now the words."), LogLine(kind: .status, text: "Building…")]
        let live = ChatItem.live(lines)
        XCTAssertEqual(live.shown.map(\.text), ["Done before.", "Worked for 9s · $0", "Shelf is ready", "make it beer",
                                                 "I'll look first.", "Now the words."])
        // The step still going ("Building…") is what the line itself says.
        XCTAssertEqual(live.steps.map(\.said), ["Looking around", "Finding every mention"])
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
                                                 "Filter by the peppers shown (intensity)."])
        XCTAssertEqual(live.steps.map(\.text), ["Looking things over", "Working on the interface", "Checking how it looks",
                                                 "Building…", "Working on the interface", "Checking how it looks"])
        XCTAssertFalse(live.steps.contains { $0.text.contains(".swift") || $0.text.contains(".md") })
        // Agent Details still shows the calls themselves.
        XCTAssertEqual(LogLine.visible(lines, details: true).filter { $0.kind == .tool }.count, 8)
        // Over, the same steps are what "Worked for…" opens to.
        let done = visible + LogLine.visible([LogLine(kind: .agent, text: "Done."), LogLine(kind: .summary, text: "Worked for 3m 56s · $0.18")], details: false)
        guard case .work(_, _, let steps)? = ChatItem.items(done, gather: true).last else { return XCTFail("no Worked for") }
        // As on any turn, a build there is a step only until the next one.
        XCTAssertEqual(steps.map(\.text), ["Looking things over", "Working on the interface", "Checking how it looks",
                                            "Working on the interface", "Checking how it looks", "Building…"])
        // A look again after a build that went before it is one step, not the same words twice.
        let looks = lines.prefix(10) + [LogLine(kind: .status, text: "Building…"), LogLine(kind: .tool, text: "look_at_app"), LogLine(kind: .agent, text: "Done."),
                                         LogLine(kind: .summary, text: "Worked for 1m 0s · $0.01")]
        guard case .work(_, _, let again)? = ChatItem.items(LogLine.visible(Array(looks), details: false), gather: true).last else {
            return XCTFail("no Worked for")
        }
        XCTAssertEqual(again.map(\.text), ["Looking things over", "Working on the interface", "Checking how it looks"])
    }

    /// A command is logged as a call and as its own row: only the row, by its name, is a step, so commands the agent
    /// gave one name to stay one step.
    func testACommandIsOneStepByItsName() {
        let lines = [LogLine(kind: .user, text: "check it"), LogLine(kind: .tool, text: "bash ls Sources"),
                     LogLine(kind: .status, text: "Ran: ls Sources", said: "Looking around"),
                     LogLine(kind: .tool, text: "bash grep heat"), LogLine(kind: .status, text: "Ran: grep heat", said: "Looking around"),
                     LogLine(kind: .tool, text: "read Model.swift"), LogLine(kind: .agent, text: "Done."),
                     LogLine(kind: .summary, text: "Worked for 9s · $0")]
        let visible = LogLine.visible(lines, details: false)
        XCTAssertEqual(ChatItem.live(Array(visible.prefix(4))).steps.map { $0.said ?? $0.text },
                       ["Looking around", "Looking around", "Looking things over"])
        guard case .work(_, _, let steps)? = ChatItem.items(visible, gather: true).last else { return XCTFail("no Worked for") }
        XCTAssertEqual(steps.map { $0.said ?? $0.text }, ["Looking around", "Looking things over"])
        XCTAssertEqual(steps.first?.text, "Ran: ls Sources\ngrep heat")
    }

    /// The step the turn is still on is what the line at the bottom says, not a step done yet: it joins the list above
    /// the line once the agent moves on (it writes, it thinks, it starts another step).
    func testTheStepGoingOnIsTheLineNotAStepDone() {
        let going = LogLine.visible([LogLine(kind: .user, text: "add a filter"), LogLine(kind: .tool, text: "read ShelfView.swift"),
                                     LogLine(kind: .tool, text: "edit ShelfView.swift")], details: false)
        XCTAssertEqual(ChatItem.live(going, doing: "Working on the interface").steps.map(\.text), ["Looking things over"])
        // Thinking after it, the edit is done.
        XCTAssertEqual(ChatItem.live(going, doing: Activity.thinking).steps.map(\.text), ["Looking things over", "Working on the interface"])
        // So it is once the agent says something after it.
        let said = going + [LogLine(kind: .agent, text: "Now the buttons.")]
        XCTAssertEqual(ChatItem.live(said, doing: "Replying").steps.map(\.text), ["Looking things over", "Working on the interface"])
        // A look's own stages after it ("Building…") are still the look.
        let look = going + LogLine.visible([LogLine(kind: .tool, text: "look_at_app"), LogLine(kind: .status, text: "Building…")], details: false)
        XCTAssertEqual(ChatItem.live(look, doing: "Building…").steps.map(\.text), ["Looking things over", "Working on the interface"])
        // The next call being written says its words before it's logged: the edit before it is done.
        XCTAssertEqual(ChatItem.live(going, doing: "Looking things over").steps.map(\.text), ["Looking things over", "Working on the interface"])
        // Nor is a look still going once the next call is being written after it.
        XCTAssertEqual(ChatItem.live(look, doing: "Working on the interface").steps.map(\.text),
                       ["Looking things over", "Working on the interface", "Checking how it looks"])
        // While it's going, its stages are Lamp's own words, not a call's.
        XCTAssertEqual(ChatItem.live(look, doing: "Opening Hot Shelf…").steps.map(\.text), ["Looking things over", "Working on the interface"])
        // A named command running is the line's words, and done it's a step by that name.
        let command = going + [LogLine(kind: .status, text: "Ran: swift build", said: "Checking it builds")]
        XCTAssertEqual(ChatItem.live(command, doing: "Checking it builds").steps.map { $0.said ?? $0.text },
                       ["Looking things over", "Working on the interface"])
    }
}
