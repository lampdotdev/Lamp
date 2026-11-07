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
                return ["outcome": "live", "run": runs, "text": "live"]
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
        // Only the text reaches Claude Code: the retry says so there, once, however often it's asked.
        XCTAssertFalse((a?["text"] as? String ?? "").contains("retried:"))
        let again = await apply()
        let said = again?["text"] as? String ?? ""
        XCTAssertTrue(said.hasPrefix("retried: "), said)
        XCTAssertEqual(said.components(separatedBy: "retried:").count, 2, said)
        XCTAssertTrue(said.hasSuffix("live"), said)
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
            return ["run": runs, "text": "mac: live"]
        }
        XCTAssertEqual(first?["stale"] as? Bool, true)
        // Said in the text, before what the apply found, since only the text reaches Claude Code.
        let said = first?["text"] as? String ?? ""
        XCTAssertTrue(said.hasPrefix("stale: "), said)
        XCTAssertTrue(said.hasSuffix("mac: live"), said)
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
        // The running operation holds until it's let go, so nothing here depends on how long anything takes.
        var letGo: CheckedContinuation<Void, Never>?
        async let running: Void? = session.work.run {
            events.append("running begins")
            await withCheckedContinuation { letGo = $0 }
            events.append("running ends")
        }
        while letGo == nil { await Task.yield() }
        async let waiting: Void? = session.work.run { events.append("waiting ran") }
        while session.work.queued == 0 { await Task.yield() }
        session.end(.takenBack)
        XCTAssertFalse(session.isLive)
        XCTAssertEqual(session.work.queued, 0, "what waited is told at once")
        Task { @MainActor in letGo?.resume() }
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

    /// A request's checkpoints amend only the version the request itself saved, and only while it's still the latest:
    /// a restore or another commit since makes the next save a version of its own.
    func testCheckpointsAmendOnlyTheRequestsOwnLatestVersion() {
        var request = OutsideRequest()
        XCTAssertFalse(request.amends(head: "abc"), "nothing saved yet: a new version")
        request.saved("v1")
        XCTAssertTrue(request.amends(head: "v1"))
        XCTAssertFalse(request.amends(head: "restored"), "something else is the latest: a new version")
        XCTAssertFalse(request.amends(head: nil))
    }

    /// Claude Code stopping checks the code again when it changed since the last checkpoint that went through, when the
    /// last checkpoint failed even though nothing changed since, and when a file no build reads is left out of a version;
    /// not when the last good checkpoint saw this very code and everything is saved.
    func testStopChecksChangesAndUnresolvedFailures() {
        var request = OutsideRequest()
        XCTAssertTrue(request.checksAtStop(code: "A", unsaved: false), "never checked")
        request.checkpointed(at: "A", failed: false)
        XCTAssertFalse(request.checksAtStop(code: "A", unsaved: false))
        XCTAssertTrue(request.checksAtStop(code: "A", unsaved: true), "a README changed after the checkpoint is saved at the end")
        XCTAssertTrue(request.checksAtStop(code: "B", unsaved: false))
        request.checkpointed(at: "B", failed: true)
        XCTAssertTrue(request.checksAtStop(code: "B", unsaved: false), "a failure not known to be fixed is checked again")
        request.checkpointed(at: "B2", failed: false)
        XCTAssertFalse(request.checksAtStop(code: "B2", unsaved: false))
    }

    /// Stopping with something broken turns Claude Code back twice at most per request, however many checkpoints come
    /// between, and never when nothing's broken.
    func testStopTurnsBackAtMostTwicePerRequest() {
        var request = OutsideRequest()
        XCTAssertFalse(request.turnsBack(failed: false))
        for _ in 0..<5 { request.checkpointed(at: "X", failed: true) }
        XCTAssertTrue(request.turnsBack(failed: true))
        request.checkpointed(at: "Y", failed: true)
        XCTAssertTrue(request.turnsBack(failed: true))
        XCTAssertFalse(request.turnsBack(failed: true), "spent: the request ends")
        var next = OutsideRequest()
        XCTAssertTrue(next.turnsBack(failed: true), "a new request has its own")
    }

    /// Lamp can't be reached: every hook of a session's Claude Code says no by itself (a command, a file, a permission, a
    /// prompt), since Claude Code takes a hook that fails any other way as leave to go on.
    func testHooksRefuseWhenLampCantBeReached() throws {
        var env: [String: String] = [:]
        let session = Agent.outsideHooks(&env)
        var commands: [(String, String)] = [
            ("PreToolUse", Agent.claudeHook("LAMP_APPROVE_URL", event: "PreToolUse")["command"] as! String),
            ("PermissionRequest", Agent.claudeHook("LAMP_APPROVE_URL", event: "PermissionRequest")["command"] as! String),
        ]
        for (event, entries) in session {
            let hooks = (entries as! [[String: Any]]).first!["hooks"] as! [[String: Any]]
            commands.append((event, hooks.first!["command"] as! String))
        }
        // Port 9 on this Mac's own address: nothing listens, so curl fails at once.
        let closed = "http://127.0.0.1:9/nowhere"
        for (event, command) in commands {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            process.environment = ["LAMP_TOKEN": "t", "LAMP_APPROVE_URL": closed, "LAMP_BEGIN_URL": closed, "LAMP_FINISH_URL": closed,
                                   "PATH": "/usr/bin:/bin"]
            let input = Pipe(), output = Pipe()
            process.standardInput = input
            process.standardOutput = output
            try process.run()
            input.fileHandleForWriting.write(Data("{}".utf8))
            try input.fileHandleForWriting.close()
            process.waitUntilExit()
            let said = try XCTUnwrap(JSONSerialization.jsonObject(with: output.fileHandleForReading.readDataToEndOfFile()) as? [String: Any], event)
            let specific = said["hookSpecificOutput"] as? [String: Any]
            switch event {
            case "PreToolUse": XCTAssertEqual(specific?["permissionDecision"] as? String, "deny")
            case "PermissionRequest": XCTAssertEqual((specific?["decision"] as? [String: Any])?["behavior"] as? String, "deny")
            case "UserPromptSubmit": XCTAssertEqual(said["decision"] as? String, "block")
            case "Stop": XCTAssertNotNil(said["systemMessage"], "Stop can only say so: the request is ended by the next prompt")
            default: XCTFail("a hook nobody expected: \(event)")
            }
        }
        XCTAssertEqual(Set(commands.map(\.0)), ["PreToolUse", "PermissionRequest", "UserPromptSubmit", "Stop"])
    }
}
