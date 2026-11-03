import XCTest
@testable import Lamp

/// The answer beside a running turn: which messages get one, what the agent is told, and the run's limits.
@MainActor
final class SideAnswerTests: XCTestCase {
    func testOnlyAPlainTypedMessageIsAnswered() {
        XCTAssertTrue(SideAnswer.canAnswer(QueuedMessage(text: "Make it blue")))
        let others = [
            QueuedMessage(text: String(repeating: "x", count: SideAnswer.messageLimit + 1)),
            QueuedMessage(text: "   "),
            QueuedMessage(text: "Blue", card: UUID()),
            QueuedMessage(text: "Like this", attachments: [URL(fileURLWithPath: "/tmp/a.png")]),
            QueuedMessage(text: "Again", kept: ["a.png"]),
            QueuedMessage(text: "This", pointed: PointedAt(title: "Button", detail: nil, picture: "/tmp/a.png")),
            QueuedMessage(text: "Again", replaces: "Before"),
            QueuedMessage(text: "Again", tookBack: ["Before"]),
            QueuedMessage(text: "Now", sendNow: true),
            QueuedMessage(text: "Fix it", byLamp: true),
            QueuedMessage(text: "Carry on", afterReload: true),
        ]
        for message in others { XCTAssertFalse(SideAnswer.canAnswer(message), message.text) }
    }

    func testThePersonsWordsStandApart() {
        XCTAssertTrue(SideAnswer.prompt(for: "Make it blue").contains("<message>\nMake it blue\n</message>"))
        XCTAssertTrue(SideAnswer.prompt(for: "Make it blue", chat: "Person: Hi").hasPrefix("What's been said so far"))
    }

    func testSentAgainInTheSameWordsItKeepsItsAnswer() {
        var line = LogLine(kind: .user, text: "Make it blue")
        line.sideReply = "I'll make it blue shortly."
        XCTAssertEqual(SideAnswer.kept(line, sentAs: "Make it blue")?.reply, "I'll make it blue shortly.")
        XCTAssertNil(SideAnswer.kept(line, sentAs: "Make it green"), "new words are a new message")
    }

    private func fixture(_ name: String) throws -> [String] {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/side-answer/\(name)")
        return try String(contentsOf: file, encoding: .utf8).split(separator: "\n").map(String.init)
    }

    private func verdict(of lines: [String], from reader: inout SideAnswer.Reader) -> SideAnswer.Reader.Verdict? {
        for line in lines {
            let verdict = reader.read(line)
            if verdict != .going { return verdict }
        }
        return nil
    }

    /// A copy of pi's session is forked, never the file itself, and only one with no other name.
    func testOnlyTheAppsOwnSessionIsCopied() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("side-\(UUID().uuidString)").resolvingSymlinksInPath()
        let app = root.appendingPathComponent("app"), sessions = app.appendingPathComponent(".lamp/pi-sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = LampProject(id: "app", name: "App", exe: "", dir: app)
        let other = root.appendingPathComponent("other.jsonl")
        try "theirs".write(to: other, atomically: true, encoding: .utf8)
        let own = sessions.appendingPathComponent("a-lamp-1.jsonl"), copy = root.appendingPathComponent("copy.jsonl")
        try "mine".write(to: own, atomically: true, encoding: .utf8)
        XCTAssertTrue(AppFile.copy(own, in: project, to: copy))
        XCTAssertEqual(try String(contentsOf: copy, encoding: .utf8), "mine")
        let linked = sessions.appendingPathComponent("zz-lamp-1.jsonl"), named = sessions.appendingPathComponent("zy-lamp-1.jsonl")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: other)
        try FileManager.default.linkItem(at: other, to: named)
        XCTAssertFalse(AppFile.copy(linked, in: project, to: root.appendingPathComponent("1")), "a link")
        XCTAssertFalse(AppFile.copy(named, in: project, to: root.appendingPathComponent("2")), "a second name")
    }

    /// The run's pi has the one provider's entry, not every sign-in pi keeps.
    func testPiGetsItsSettingsAndOneSignIn() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("side-\(UUID().uuidString)")
        let source = root.appendingPathComponent("pi"), config = root.appendingPathComponent("config")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try #"{"openrouter":{"type":"api_key","key":"!cmd"},"anthropic":{"type":"oauth"}}"#.write(to: source.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: source.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        XCTAssertTrue(SideAnswer.piConfig(from: source, provider: "openrouter", to: config))
        let auth = try JSONSerialization.jsonObject(with: Data(contentsOf: config.appendingPathComponent("auth.json"))) as? [String: Any]
        XCTAssertEqual(auth?.keys.sorted(), ["openrouter"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: config.appendingPathComponent("settings.json").path))
    }

    /// pi 1.0.0's own output, recorded on 2026-11-02 from a fork through OpenRouter (anthropic/claude-sonnet-5.5) told to
    /// write a line and call bash in one reply, with its thinking taken out.
    func testWordsBesideAToolCallAreNoAnswer() throws {
        var reader = SideAnswer.Reader(.pi)
        XCTAssertEqual(verdict(of: try fixture("mixed-reply.jsonl"), from: &reader), .tool("toolCall"))
        XCTAssertGreaterThan(reader.cost, 0)
    }

    /// None is offered, so a tool that ran and one that failed both say the launch isn't what it was.
    func testAnyToolAtAllIsATool() {
        for line in [#"{"type":"tool_execution_start","toolName":"bash"}"#,
                     #"{"type":"tool_execution_end","toolName":"bash","isError":true,"result":{"content":[{"type":"text","text":"Tool bash not found"}]}}"#] {
            var reader = SideAnswer.Reader(.pi)
            XCTAssertEqual(reader.read(line), .tool("bash"))
        }
    }

    /// What isn't known isn't an answer, for any engine.
    func testWhatItDoesntKnowEndsTheRun() {
        for engine in Engine.allCases {
            var reader = SideAnswer.Reader(engine)
            XCTAssertEqual(reader.read(#"{"type":"item.completed","item":{"type":"agent_mess"#), .failed("unreadable output"), engine.rawValue)
        }
        var codex = SideAnswer.Reader(.codex)
        XCTAssertEqual(codex.read(#"{"type":"exec_command_begin"}"#), .failed("unexpected output"))
        var pi = SideAnswer.Reader(.pi)
        XCTAssertEqual(pi.read(#"{"type":"message_end","message":{"role":"assistant","stopReason":"stop","content":[{"type":"text","text":"Hi"},{"type":"image"}]}}"#), .failed("unexpected output"))
        var claude = SideAnswer.Reader(.claude)
        _ = claude.read(#"{"type":"system","subtype":"init","tools":[],"mcp_servers":[]}"#)
        XCTAssertEqual(claude.read(#"{"type":"assistant","message":{"content":[{"type":"text","text":"Hi"},{"type":"server_tool_use","name":"web_search"}]}}"#), .tool("server_tool_use"))
    }

    func testClaudeCutShortIsNoAnswer() throws {
        var reader = SideAnswer.Reader(.claude)
        let lines = try fixture("claude.jsonl").map { $0.replacingOccurrences(of: #""stop_reason":"end_turn""#, with: #""stop_reason":"max_tokens""#) }
        XCTAssertEqual(verdict(of: lines, from: &reader), .failed("ended without an answer"))
    }

    /// Claude Code 2.1.316's own output, recorded on 2026-11-02 from `claudeArguments` under `Sandbox.sideProfile`, told to run a
    /// command, with its paths and ids taken out.
    func testClaudeAnswersOnceItsListIsEmpty() throws {
        var reader = SideAnswer.Reader(.claude)
        guard case .answered(let reply) = verdict(of: try fixture("claude.jsonl"), from: &reader) else { return XCTFail("no answer") }
        XCTAssertFalse(reply.isEmpty)
        XCTAssertGreaterThan(reader.output, 0)
    }

    func testClaudeIsTrustedOnlyWithNoToolsListed() throws {
        var offered = SideAnswer.Reader(.claude)
        XCTAssertEqual(offered.read(#"{"type":"system","subtype":"init","tools":["Bash"],"mcp_servers":[]}"#), .failed("offered tools"))
        var unlisted = SideAnswer.Reader(.claude)
        let lines = try fixture("claude.jsonl").filter { !$0.contains(#""subtype":"init""#) }
        XCTAssertEqual(verdict(of: lines, from: &unlisted), .failed("no tool list"))
    }

    func testClaudeToolUseBesideWordsIsNoAnswer() {
        var reader = SideAnswer.Reader(.claude)
        _ = reader.read(#"{"type":"system","subtype":"init","tools":[],"mcp_servers":[]}"#)
        XCTAssertEqual(reader.read(#"{"type":"assistant","message":{"content":[{"type":"text","text":"On it."},{"type":"tool_use","name":"Bash"}]}}"#), .tool("tool_use"))
    }

    /// Codex 0.166.0-alpha.5.1's own output, recorded on 2026-11-02 from the launch `codexArguments` makes, told to use every
    /// tool it had, with a path taken out. It wrote a line about looking first, then its answer.
    func testCodexAnswerIsItsLastMessage() throws {
        var reader = SideAnswer.Reader(.codex)
        guard case .answered(let reply) = verdict(of: try fixture("codex.jsonl"), from: &reader) else { return XCTFail("no answer") }
        XCTAssertFalse(reply.contains("inspect"), "the line before it isn't the answer")
        XCTAssertEqual(reader.input, 7392)
    }

    func testCodexAnyStepThatIsntWordsStopsIt() {
        var reader = SideAnswer.Reader(.codex)
        XCTAssertEqual(reader.read(#"{"type":"item.started","item":{"id":"item_1","type":"command_execution","command":"ls"}}"#), .tool("command_execution"))
        XCTAssertEqual(reader.read(#"{"type":"item.completed","item":{"type":"web_search","query":"x"}}"#), .tool("web_search"))
        XCTAssertEqual(reader.read(#"{"type":"turn.failed","error":{"message":"no"}}"#), .failed("the request failed"))
    }

    func testOnlyTestedVersionsAnswer() {
        XCTAssertEqual(SideAnswer.version(in: "2.1.316 (Claude Code)\n"), "2.1.316")
        XCTAssertEqual(SideAnswer.version(in: "codex-cli 0.166.0-alpha.5.1\n"), "0.166.0-alpha.5.1")
        XCTAssertTrue(SideAnswer.isTested(.codex, version: "0.166.0-alpha.5.1"))
        XCTAssertFalse(SideAnswer.isTested(.codex, version: "0.166.0-alpha.5.2"))
        XCTAssertFalse(SideAnswer.isTested(.codex, version: "0.167.0"))
        XCTAssertTrue(SideAnswer.isTested(.claude, version: "2.1.316"))
        XCTAssertTrue(SideAnswer.isTested(.claude, version: "2.1.400"))
        XCTAssertFalse(SideAnswer.isTested(.claude, version: "2.1.315"))
        XCTAssertFalse(SideAnswer.isTested(.claude, version: "2.2.0"))
        XCTAssertFalse(SideAnswer.isTested(.claude, version: "2.2"), "sorts before 2.2.0")
        XCTAssertTrue(SideAnswer.isTested(.pi, version: ""))
    }

    func testAToolThatRanStopsThatVersionForGood() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SideAnswerTests"))
        defaults.removePersistentDomain(forName: "SideAnswerTests")
        SideAnswer.stop(.claude, version: "2.1.316", in: defaults)
        SideAnswer.stop(.claude, version: "2.1.320", in: defaults)
        XCTAssertTrue(SideAnswer.isStopped(.claude, version: "2.1.316", in: defaults), "a later stop keeps the earlier one")
        XCTAssertTrue(SideAnswer.isStopped(.claude, version: "2.1.320", in: defaults))
        XCTAssertFalse(SideAnswer.isStopped(.claude, version: "2.1.317", in: defaults), "a new version is looked at again")
        XCTAssertFalse(SideAnswer.isStopped(.codex, version: "2.1.316", in: defaults))
    }

    func testCodexCatalogTakesEveryToolFieldAway() throws {
        let list = #"{"models":[{"slug":"gpt-6-luna","tool_mode":"code_mode_only","multi_agent_version":"v2","apply_patch_tool_type":"freeform","experimental_supported_tools":["clock"],"shell_type":"unified_exec","supports_search_tool":true,"web_search_tool_type":"text_and_image","context_window":1}]}"#
        let data = try XCTUnwrap(SideAnswer.codexCatalog(from: Data(list.utf8), model: "gpt-6-luna"))
        let entry = try XCTUnwrap(((JSONSerialization.jsonObject(with: data) as? [String: Any])?["models"] as? [[String: Any]])?.first)
        XCTAssertTrue(entry["tool_mode"] is NSNull)
        XCTAssertTrue(entry["multi_agent_version"] is NSNull)
        XCTAssertTrue(entry["apply_patch_tool_type"] is NSNull)
        XCTAssertEqual(entry["experimental_supported_tools"] as? [String], [])
        XCTAssertEqual(entry["shell_type"] as? String, "disabled")
        XCTAssertEqual(entry["supports_search_tool"] as? Bool, false)
        XCTAssertEqual(entry["context_window"] as? Int, 1, "the rest stays Codex's own")
        XCTAssertNil(SideAnswer.codexCatalog(from: Data(list.utf8), model: "gpt-7"))
        XCTAssertNil(SideAnswer.codexCatalog(from: Data(#"{"models":[{"slug":"gpt-6-luna"}]}"#.utf8), model: "gpt-6-luna"), "a shape it wasn't proven with")
    }

    func testTheSandboxLetsItWriteOnlyItsOwnFolderAndReadNothingShared() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("side-\(UUID().uuidString)").resolvingSymlinksInPath()
        let scratch = root.appendingPathComponent("scratch"), allowed = root.appendingPathComponent("allowed")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: allowed, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let secret = root.appendingPathComponent("secret"), given = allowed.appendingPathComponent("given"), link = scratch.appendingPathComponent("link")
        try "x".write(to: secret, atomically: true, encoding: .utf8)
        try "x".write(to: given, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secret)
        let profile = root.appendingPathComponent("p.sb")
        try Sandbox.sideProfile(scratch: scratch.path, reading: [allowed.path], readingFiles: []).write(to: profile, atomically: true, encoding: .utf8)
        func run(_ command: String) -> Int32 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: Sandbox.executable)
            process.arguments = ["-f", profile.path, "/bin/sh", "-c", command]
            process.standardError = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }
        XCTAssertEqual(run("cat '\(given.path)'"), 0, "what it's given")
        XCTAssertEqual(run("echo x > '\(scratch.path)/made' && cat '\(scratch.path)/made'"), 0, "its own folder")
        XCTAssertNotEqual(run("cat '\(secret.path)'"), 0, "the shared temporary folders")
        XCTAssertNotEqual(run("cat '\(link.path)'"), 0, "a link out of its folder")
        XCTAssertNotEqual(run("echo x > '\(allowed.path)/made'"), 0, "what it may only read")
        XCTAssertNotEqual(run("echo x > /tmp/side-answer-sandbox-test"), 0, "anywhere else")
        XCTAssertNotEqual(run("cat ~/.zshrc ~/.ssh/config ~/Library/Keychains/login.keychain-db"), 0, "the home folder")
        XCTAssertNotEqual(run("ls ~"), 0, "nor what's in it")
    }

    func testSendNowAsksForNoSecondAcknowledgementOnceAnswered() {
        let answered = QueuedMessage(text: "Make it blue", side: .answered("I'll make it blue shortly."))
        let unanswered = QueuedMessage(text: "And the title")
        XCTAssertEqual(Agent.midTurnNote(for: [answered]), Agent.midTurnAnsweredNote)
        XCTAssertEqual(Agent.midTurnNote(for: [unanswered]), Agent.midTurnNote)
        XCTAssertEqual(Agent.midTurnNote(for: [answered, unanswered]), Agent.midTurnNote, "one still needs hearing back")
    }

    func testReceiptIsLabeledAndGrantsNothing() {
        let receipt = SideAnswer.receipt("Got it, I'll do that next.")
        XCTAssertTrue(receipt.contains("Lamp context, not a new user instruction"))
        XCTAssertTrue(receipt.contains("Got it, I'll do that next."))
        XCTAssertTrue(receipt.contains("grant no permissions"))
    }

    func testAnswerStaysWithItsMessageAcrossARelaunch() {
        let waiting = QueuedMessage(text: "Make it blue", side: .answered("Got it."))
        XCTAssertEqual(QueuedMessage(saved: waiting.saved, attachments: []).sideReply, "Got it.")
        let unfinished = QueuedMessage(text: "Make it blue", side: .answering)
        XCTAssertNil(QueuedMessage(saved: unfinished.saved, attachments: []).side)
    }

    /// An answered message reads as heard, so a quit mustn't lose it, nor what's waiting beside it.
    func testAQueueWithAnAnswerIsKeptAcrossARelaunch() {
        let answered = QueuedMessage(text: "Make it blue", side: .answered("Got it."))
        let beside = QueuedMessage(text: "And the title")
        XCTAssertTrue(Store.keptAcrossRelaunch([answered], setupReady: true))
        XCTAssertTrue(Store.keptAcrossRelaunch([beside, answered], setupReady: true))
        XCTAssertFalse(Store.keptAcrossRelaunch([QueuedMessage(text: "Make it blue", side: .answering)], setupReady: true),
                       "nobody was told anything yet")
    }

    func testEachEngineHasARouteAndALocalModelHasNone() {
        let pi = ["LAMP_PI": "/pi", "PI_CODING_AGENT_DIR": "/config", "LAMP_PROVIDER": "openrouter", "LAMP_MODEL": "m",
                  "LAMP_SYSTEM": "s", "LAMP_SESSION": "lamp-1"]
        XCTAssertEqual(SideAnswer.route(env: pi, engine: .pi, local: false, keyProvider: "openrouter")?.model, "m")
        XCTAssertNil(SideAnswer.route(env: pi, engine: .pi, local: true, keyProvider: "openrouter"))
        let claude = ["LAMP_TOOL": "/claude", "LAMP_SYSTEM": "s", "LAMP_MODEL": "opus"]
        XCTAssertEqual(SideAnswer.route(env: claude, engine: .claude, local: false, keyProvider: "")?.model, "opus")
        XCTAssertEqual(SideAnswer.route(env: ["LAMP_TOOL": "/codex"], engine: .codex, local: false, keyProvider: "")?.model, SideAnswer.testedCodexModel)
        XCTAssertNil(SideAnswer.route(env: [:], engine: .codex, local: false, keyProvider: ""))
    }

    private func route(_ engine: Engine) -> SideAnswer.Route {
        SideAnswer.Route(engine: engine, executable: "/usr/bin/true", configFolder: "/config", model: "m", system: "s", path: "/usr/bin",
                         session: "lamp-1", provider: "openrouter", keyProvider: "openrouter")
    }

    func testEveryEngineStartsWithNoToolsAndNoneOfTheBuildersRoutes() throws {
        let transcript = URL(fileURLWithPath: "/main.jsonl"), folder = URL(fileURLWithPath: "/private/side")
        let pi = try XCTUnwrap(SideAnswer.launch(route(.pi), prompt: "p", transcript: transcript, folder: folder, keys: ["LAMP_KEY_TICKET": "t"]))
        XCTAssertTrue(pi.arguments.contains("--no-tools"))
        XCTAssertFalse(pi.arguments.contains("-e"), "no extension")
        XCTAssertEqual(pi.arguments[pi.arguments.firstIndex(of: "--fork")! + 1], "/main.jsonl")
        XCTAssertFalse(pi.arguments.contains("lamp-1"), "the fork has a session of its own")
        XCTAssertEqual(pi.environment["HOME"], "/private/side/home")
        XCTAssertFalse(pi.profile.contains("main.jsonl"), "pi forks its own copy, in its folder")
        XCTAssertFalse(pi.profile.contains("/config\""), "nor reads pi's own settings")
        XCTAssertEqual(pi.environment["PI_CODING_AGENT_DIR"], "/private/side/config")
        let claude = try XCTUnwrap(SideAnswer.launch(route(.claude), prompt: "p", transcript: transcript, folder: folder))
        XCTAssertEqual(claude.arguments[claude.arguments.firstIndex(of: "--tools")! + 1], "")
        XCTAssertTrue(claude.arguments.contains("--no-session-persistence"))
        XCTAssertTrue(claude.arguments.contains("--strict-mcp-config"))
        let codex = try XCTUnwrap(SideAnswer.launch(route(.codex), prompt: "p", transcript: nil, folder: folder))
        XCTAssertTrue(codex.arguments.contains("--ephemeral"))
        XCTAssertTrue(codex.arguments.contains(#"web_search="disabled""#))
        XCTAssertFalse(codex.arguments.contains("fork"))
        XCTAssertEqual(codex.environment["CODEX_SQLITE_HOME"], "/private/side/state")
        for launch in [pi, claude, codex] {
            XCTAssertNil(launch.environment["LAMP_TOKEN"])
            XCTAssertTrue(launch.environment.keys.filter { $0.hasSuffix("_URL") && $0 != "LAMP_KEY_URL" }.isEmpty)
            XCTAssertTrue(launch.profile.contains("(deny file-write*)"))
        }
        XCTAssertNil(SideAnswer.launch(route(.claude), prompt: "p", transcript: nil, folder: folder), "nothing to fork")
    }

    func testChatForCodexIsTheNewestWithinItsLimit() {
        let old = LogLine(kind: .user, text: String(repeating: "x", count: SideAnswer.chatLimit))
        let chat = SideAnswer.chat(of: [old, LogLine(kind: .status, text: "Saved"), LogLine(kind: .user, text: "Make it blue"), LogLine(kind: .agent, text: "On it")])
        XCTAssertEqual(chat, "Person: Make it blue\n\nAgent: On it")
    }
}
