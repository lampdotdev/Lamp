import XCTest
@testable import Lamp

/// A terminal session's operations (`OutsideWork`): one at a time across the wish, a retry answered without running
/// twice, an answer marked stale when the code changed under it, and a session ended while one runs and another waits.
@MainActor
final class OutsideSessionTests: XCTestCase {
    /// Calls sent together run one after another, in the order asked, never side by side.
    func testOperationsRunOneAtATime() async {
        let work = OutsideWork()
        var events: [String] = []
        async let first: Void? = work.run {
            events.append("first begins")
            try? await Task.sleep(for: .milliseconds(150))
            events.append("first ends")
        }
        try? await Task.sleep(for: .milliseconds(20))
        async let second: Void? = work.run {
            events.append("second begins")
            events.append("second ends")
        }
        _ = await (first, second)
        XCTAssertEqual(events, ["first begins", "first ends", "second begins", "second ends"])
        XCTAssertFalse(work.isBusy)
    }

    /// The same operation id for the same code is the first answer again, and the work runs once; a retry sent while
    /// the first is still running waits for it and gets its answer.
    func testRetryGetsTheFirstAnswer() async {
        let work = OutsideWork()
        var runs = 0
        func apply() async -> [String: Any]? {
            await work.apply(id: "op-1", fingerprint: { "code A" }) {
                runs += 1
                try? await Task.sleep(for: .milliseconds(100))
                return ["outcome": "live", "run": runs]
            }
        }
        async let original = apply()
        try? await Task.sleep(for: .milliseconds(20))
        async let retry = apply()
        let (a, b) = await (original, retry)
        XCTAssertEqual(runs, 1)
        XCTAssertEqual(a?["run"] as? Int, 1)
        XCTAssertNil(a?["retried"])
        XCTAssertEqual(b?["run"] as? Int, 1)
        XCTAssertEqual(b?["retried"] as? Bool, true)
        // A new id runs again.
        let fresh = await work.apply(id: "op-2", fingerprint: { "code A" }) { runs += 1; return ["run": runs] }
        XCTAssertEqual(fresh?["run"] as? Int, 2)
    }

    /// Code that changed while the operation ran makes its answer stale; the same id asked again for the new code runs
    /// again rather than handing back the stale answer.
    func testChangeDuringApplyIsStaleAndRunsAgain() async {
        let work = OutsideWork()
        var code = "code A"
        var runs = 0
        let first = await work.apply(id: "op-1", fingerprint: { code }) {
            runs += 1
            code = "code B"   // an edit that landed while it built
            return ["run": runs]
        }
        XCTAssertEqual(first?["stale"] as? Bool, true)
        let again = await work.apply(id: "op-1", fingerprint: { code }) {
            runs += 1
            return ["run": runs]
        }
        XCTAssertEqual(runs, 2)
        XCTAssertNil(again?["stale"])
        XCTAssertNil(again?["retried"])
    }

    /// Ending the session while one operation runs and another waits: the waiting one never runs, the running one
    /// finishes, `drained` returns only after it has, and nothing is taken afterwards.
    func testEndingDrainsTheRunningOperationAndDropsTheRest() async {
        let session = OutsideSession(wish: "w")
        var events: [String] = []
        async let running: Void? = session.work.run {
            events.append("running begins")
            try? await Task.sleep(for: .milliseconds(200))
            events.append("running ends")
        }
        try? await Task.sleep(for: .milliseconds(20))
        async let waiting: Void? = session.work.run { events.append("waiting ran") }
        try? await Task.sleep(for: .milliseconds(20))
        session.end(.takenBack)
        XCTAssertFalse(session.isLive)
        await session.work.drained()
        events.append("drained")
        let (ran, dropped) = await (running, waiting)
        XCTAssertNotNil(ran)
        XCTAssertNil(dropped)
        XCTAssertEqual(events, ["running begins", "running ends", "drained"])
        let after: Void? = await session.work.run { events.append("after") }
        XCTAssertNil(after)
        XCTAssertFalse(events.contains("after"))
    }

    /// The launcher's ticket is good once, only within its life, and only until the session ends.
    func testTicketIsGoodOnce() {
        let session = OutsideSession(wish: "w")
        let ticket = session.ticket!
        XCTAssertFalse(session.claim("not it", launcher: 4242))
        XCTAssertTrue(session.claim(ticket, launcher: 4242))
        XCTAssertEqual(session.launcher, 4242)
        XCTAssertFalse(session.claim(ticket, launcher: 4343))
        XCTAssertEqual(session.launcher, 4242)

        let late = OutsideSession(wish: "w")
        XCTAssertFalse(late.claim(late.ticket!, launcher: 4242, now: Date().addingTimeInterval(OutsideSession.ticketLife + 1)))
        let ended = OutsideSession(wish: "w")
        let kept = ended.ticket!
        ended.end(.takenBack)
        XCTAssertFalse(ended.claim(kept, launcher: 4242))
    }

    /// What the launcher evaluates gives back every value as it was, quotes, spaces and `$` included.
    func testSetupScriptKeepsValuesAsTheyAre() throws {
        let tricky = "it's \"quoted\" $HOME `x` \\ end\nsecond line"
        let script = OutsideSession.setupScript(env: ["LAMP_A": tricky, "LAMP_B": "plain"], folder: "/tmp", command: "echo 'hi'")
            + "printf '%s|%s|%s|%s' \"$LAMP_A\" \"$LAMP_B\" \"$LAMP_RUN\" \"$PWD\"\n"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-f", "-c", script]
        let out = Pipe()
        process.standardOutput = out
        try process.run()
        process.waitUntilExit()
        let printed = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(printed, tricky + "|plain|echo 'hi'|" + URL(fileURLWithPath: "/tmp").resolvingSymlinksInPath().path)
    }
}
