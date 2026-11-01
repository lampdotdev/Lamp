import XCTest
@testable import Lamp

/// pi compacting at Lamp's size: each model's reserve in pi's settings, and a long turn going on through a compaction.
final class PiCompactionTests: XCTestCase {
    func testAReserveIsTheWindowLessLampsSizeOnlyWhenPiWouldWaitLonger() {
        XCTAssertEqual(PiCompaction.reserve(window: 1_000_000, compactAt: 200_000), 800_000)
        XCTAssertEqual(PiCompaction.reserve(window: 262_144, compactAt: 200_000), 62_144)
        XCTAssertNil(PiCompaction.reserve(window: 216_384, compactAt: 200_000))
        XCTAssertNil(PiCompaction.reserve(window: 128_000, compactAt: 200_000))
    }

    /// Lines of `{"type":"get_available_models"}` as pi 1.0.0 answers it, cut to a model each with the fields read.
    func testWindowsComeFromPisAnswerWithSlashesInIDs() {
        let answer = #"{"id":"1","type":"response","command":"get_available_models","success":true,"data":{"models":[{"type":"chat","id":"anthropic/claude-sonnet-5.5","provider":"openrouter","contextWindow":1000000,"maxTokens":128000},{"id":"no-window","provider":"openrouter"}]}}"#
        XCTAssertEqual(PiCompaction.windows(inAnswer: answer), ["openrouter/anthropic/claude-sonnet-5.5": 1_000_000])
        XCTAssertNil(PiCompaction.windows(inAnswer: "Warning: something"))
        XCTAssertNil(PiCompaction.windows(inAnswer: #"{"type":"response","command":"get_available_models","success":false}"#))
        XCTAssertNil(PiCompaction.windows(inAnswer: #"{"type":"response","command":"get_state","success":true,"data":{}}"#))
    }

    func testLampsReservesGoStaleAndEverythingElseStays() {
        let current: [String: Any] = [
            "defaultThinkingLevel": "high",
            "lampCompactionModels": ["a/gone", "a/kept", "a/shared"],
            "compaction": [
                "enabled": false,
                "keepRecentTokens": 30_000,
                "modelOverrides": [
                    "a/gone": ["reserveTokens": 1],
                    "a/kept": ["reserveTokens": 2],
                    "a/shared": ["reserveTokens": 3, "keepRecentTokens": 40_000],
                    "other/theirs": ["reserveTokens": 4],
                ],
            ] as [String: Any],
        ]
        let updated = PiCompaction.settings(current, windows: ["a/kept": 1_000_000, "other/theirs": 1_000_000, "a/small": 100_000],
                                            compactAt: 200_000)
        XCTAssertEqual(updated["defaultThinkingLevel"] as? String, "high")
        XCTAssertEqual(updated["lampCompactionModels"] as? [String], ["a/kept"])
        let compaction = updated["compaction"] as? [String: Any]
        XCTAssertEqual(compaction?["enabled"] as? Bool, true)
        XCTAssertEqual(compaction?["keepRecentTokens"] as? Int, 30_000)
        let overrides = compaction?["modelOverrides"] as? [String: [String: Int]]
        XCTAssertEqual(overrides, ["a/kept": ["reserveTokens": 800_000], "a/shared": ["keepRecentTokens": 40_000],
                                   "other/theirs": ["reserveTokens": 4]])
        // Asked again, nothing changes.
        let again = PiCompaction.settings(updated, windows: ["a/kept": 1_000_000, "other/theirs": 1_000_000], compactAt: 200_000)
        XCTAssertTrue(NSDictionary(dictionary: again).isEqual(to: updated))
    }

    /// A pi that hangs while starting and won't be told, with a child of its own: the wait ends by the limit and both go.
    @MainActor func testAPiThatHangsIsEndedWithItsChildrenAtTheLimit() async throws {
        let work = try folder()
        defer { try? FileManager.default.removeItem(at: work) }
        let child = work.appendingPathComponent("child")
        let pi = try script(in: work, "trap '' TERM HUP INT\nsleep 30 & echo $! > '\(child.path)'\nwait\n")
        let started = Date()
        var said: [String] = []
        await PiCompaction.update(pi: pi, folder: work, env: [:], compactAt: 200_000, timeout: 1) { said.append($0) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 8)
        XCTAssertEqual(said, ["pi's models unknown: compaction settings left as they were"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: work.appendingPathComponent("settings.json").path))
        let pid = try XCTUnwrap(pid_t(String(contentsOf: child, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        for _ in 0..<40 where Subprocess.alive([pid]) { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertFalse(Subprocess.alive([pid]), "pi's child outlived it")
    }

    /// pi is asked once while nothing it depends on changes, and again when something does.
    @MainActor func testPiIsAskedAgainOnlyWhenItsModelsMayHaveChanged() async throws {
        let work = try folder()
        defer { try? FileManager.default.removeItem(at: work) }
        let asked = work.appendingPathComponent("asked")
        let answer = #"{"type":"response","command":"get_available_models","success":true,"data":{"models":[{"id":"big","provider":"a","contextWindow":1000000}]}}"#
        let pi = try script(in: work, "cat > /dev/null\necho x >> '\(asked.path)'\necho '\(answer)'\n")
        func askedCount() -> Int { ((try? String(contentsOf: asked, encoding: .utf8)) ?? "").split(separator: "\n").count }
        func update(compactAt: Int = 200_000) async {
            await PiCompaction.update(pi: pi, folder: work, env: [:], compactAt: compactAt) { XCTFail($0) }
        }
        let file = work.appendingPathComponent("settings.json")
        func settings() throws -> [String: Any] { try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]) }

        await update()
        await update()
        XCTAssertEqual(askedCount(), 1)
        let overrides = try XCTUnwrap((settings()["compaction"] as? [String: Any])?["modelOverrides"] as? [String: [String: Int]])
        XCTAssertEqual(overrides, ["a/big": ["reserveTokens": 800_000]])

        try "{}".write(to: work.appendingPathComponent("models.json"), atomically: true, encoding: .utf8)
        await update()
        XCTAssertEqual(askedCount(), 2, "a new models file")
        await update(compactAt: 100_000)
        XCTAssertEqual(askedCount(), 3, "a new size")

        var off = try settings()
        off["compaction"] = ["enabled": false]
        try JSONSerialization.data(withJSONObject: off).write(to: file)
        await update(compactAt: 100_000)
        XCTAssertEqual(askedCount(), 4, "compaction turned off")
        XCTAssertEqual((try settings()["compaction"] as? [String: Any])?["enabled"] as? Bool, true)
    }

    private func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pi-compaction-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func script(in folder: URL, _ body: String) throws -> URL {
        let file = folder.appendingPathComponent("pi")
        try ("#!/bin/sh\n" + body).write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }

    func testAFailedCompactionIsNoFailureOfTheTurn() {
        let started = Agent.parse(#"{"type":"compaction_start","reason":"threshold"}"#)
        guard case .compacting? = started.first else { return XCTFail("\(started)") }
        let done = Agent.parse(#"{"type":"compaction_end","reason":"threshold","result":{"tokensBefore":240007},"aborted":false,"willRetry":false}"#)
        guard case .compacted? = done.first else { return XCTFail("\(done)") }
        let failed = Agent.parse(#"{"type":"compaction_end","reason":"threshold","aborted":false,"willRetry":false,"errorMessage":"Auto-compaction failed: no"}"#)
        guard case .compactionFailed(let reason)? = failed.first else { return XCTFail("\(failed)") }
        XCTAssertEqual(reason, "Auto-compaction failed: no")
    }

    /// The real pi and Lamp's real extension, set up as a run is, against a stand-in for the model that keeps calling a
    /// tool as its context grows past 200k: the turn compacts between requests and reaches its last answer.
    func testALongTurnCompactsAndCarriesOn() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("pi-compaction-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        let config = work.appendingPathComponent("config")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)

        let tarballs = (try? FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("vendor").resolvingSymlinksInPath(), includingPropertiesForKeys: nil)) ?? []
        guard let tarball = tarballs.first(where: { $0.lastPathComponent.hasPrefix("pi-") && $0.pathExtension == "gz" }) else {
            throw XCTSkip("No pi in vendor/: build.sh downloads it")
        }
        XCTAssertEqual(try run("/usr/bin/tar", ["-xzf", tarball.path, "-C", work.path]).status, 0)

        let model = Process()
        model.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        model.arguments = ["-I", "-c", Self.standInModel]
        let port = Pipe()
        let staysOpen = Pipe()
        model.standardOutput = port
        model.standardError = FileHandle.nullDevice
        model.standardInput = staysOpen
        try model.run()
        // It goes when this closes: /usr/bin/python3 hands over to another process, which `terminate` wouldn't reach.
        defer { try? staysOpen.fileHandleForWriting.close() }
        let portLine = String(decoding: port.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        let models = #"{"providers":{"stand-in":{"baseUrl":"http://127.0.0.1:\#(portLine)/v1","api":"openai-completions","apiKey":"local","models":[{"id":"big","contextWindow":1000000,"maxTokens":64000,"input":["text"]}]}}}"#
        try models.write(to: config.appendingPathComponent("models.json"), atomically: true, encoding: .utf8)
        let settings = PiCompaction.settings([:], windows: ["stand-in/big": 1_000_000], compactAt: 200_000)
        try JSONSerialization.data(withJSONObject: settings).write(to: config.appendingPathComponent("settings.json"))

        var env = ["LAMP_PROMPT": "go", "LAMP_SYSTEM": "Work.", "LAMP_SESSION": UUID().uuidString.lowercased(),
                   "LAMP_SESSION_DIR": work.appendingPathComponent("sessions").path]
        env["LAMP_PI"] = work.appendingPathComponent("pi/pi").path
        env["LAMP_PROVIDER"] = "stand-in"
        env["LAMP_MODEL"] = "big"
        env["LAMP_TOOLS"] = root.appendingPathComponent("Resources/lamp-tools.ts").path
        env["LAMP_TOOLS_JSON"] = root.appendingPathComponent("Resources/lamp-tools.json").path
        env["PI_CODING_AGENT_DIR"] = config.path
        env["PI_OFFLINE"] = "1"
        env["PATH"] = "/usr/bin:/bin"
        // As `Agent.command` has it, with Lamp's extension from the source tree rather than from an app.
        let command = #""$LAMP_PI" --mode json --provider "$LAMP_PROVIDER" --model "$LAMP_MODEL" --tools bash --no-extensions -e "$LAMP_TOOLS" --no-skills --no-prompt-templates --no-context-files --no-approve --session-dir "$LAMP_SESSION_DIR" --session-id "$LAMP_SESSION" --append-system-prompt "$LAMP_SYSTEM" -- "$LAMP_PROMPT""#
        let output = try run("/bin/zsh", ["-c", command + " </dev/null"], env: env, in: work).output
        let events = output.split(separator: "\n").flatMap { Agent.parse(String($0)) }
        XCTAssertTrue(events.contains { if case .compacted = $0 { true } else { false } }, output.suffix(800).description)
        XCTAssertFalse(events.contains { if case .failed = $0 { true } else { false } }, output.suffix(800).description)
        XCTAssertTrue(events.contains { if case .text(let text) = $0 { text == "all done" } else { false } }, output.suffix(800).description)
    }

    private func run(_ tool: String, _ arguments: [String], env: [String: String]? = nil, in folder: URL? = nil) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        if let env { process.environment = env }
        if let folder { process.currentDirectoryURL = folder }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: output, as: UTF8.self))
    }

    /// An OpenAI-style streaming endpoint. A request with no tools is a summary; until one has come, each request
    /// reports 60k tokens more and carries about as much text, and after seven it answers.
    private static let standInModel = #"""
    import json, os, sys, threading
    from http.server import BaseHTTPRequestHandler, HTTPServer
    threading.Thread(target=lambda: (sys.stdin.read(), os._exit(0)), daemon=True).start()
    state = {"requests": 0, "summarized": False}
    class Model(BaseHTTPRequestHandler):
        def log_message(self, *args): pass
        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers["content-length"])))
            self.send_response(200)
            self.send_header("content-type", "text/event-stream")
            self.end_headers()
            def chunk(delta, finish=None, tokens=None):
                event = {"id": "x", "object": "chat.completion.chunk", "created": 1, "model": "big",
                         "choices": [{"index": 0, "delta": delta, "finish_reason": finish}]}
                if tokens: event["usage"] = {"prompt_tokens": tokens, "completion_tokens": 5, "total_tokens": tokens + 5}
                self.wfile.write(("data: " + json.dumps(event) + "\n\n").encode())
            if not body.get("tools"):
                state["summarized"] = True
                chunk({"role": "assistant", "content": "## Goal\nsummary"})
                chunk({}, "stop", 100)
            else:
                state["requests"] += 1
                n = state["requests"]
                tokens = 30000 + 1000 * n if state["summarized"] else 60000 + 60000 * n
                if n >= 7:
                    chunk({"role": "assistant", "content": "all done"})
                    chunk({}, "stop", tokens)
                else:
                    chunk({"role": "assistant", "content": "words " * 40000})
                    call = {"name": "bash", "arguments": json.dumps({"command": "true", "description": "step"})}
                    chunk({"tool_calls": [{"index": 0, "id": "c%d" % n, "type": "function", "function": call}]})
                    chunk({}, "tool_calls", tokens)
            self.wfile.write(b"data: [DONE]\n\n")
    server = HTTPServer(("127.0.0.1", 0), Model)
    print(server.server_address[1], flush=True)
    server.serve_forever()
    """#
}
