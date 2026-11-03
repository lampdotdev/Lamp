import XCTest
@testable import Lamp

/// What Lamp's extension does in a real pi, against a stand-in for the model and for Lamp's gateway: tools held back with
/// pi's `deferred` exposure, calls sent with no words for the person, and a look or a use sent beside the writes it's for.
final class PiFirstTurnToolsTests: XCTestCase {
    private var work: URL!
    private var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("pi-tools-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work.appendingPathComponent("config"), withIntermediateDirectories: true)
        let tarballs = (try? FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("vendor").resolvingSymlinksInPath(), includingPropertiesForKeys: nil)) ?? []
        guard let tarball = tarballs.first(where: { $0.lastPathComponent.hasPrefix("pi-") && $0.pathExtension == "gz" }) else {
            throw XCTSkip("No pi in vendor/: build.sh downloads it")
        }
        let untar = Process()
        untar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        untar.arguments = ["-xzf", tarball.path, "-C", work.path]
        try untar.run()
        untar.waitUntilExit()
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: work) }

    func testAFirstRunDefersAndARunThatResumesSendsEveryTool() throws {
        let model = try standIn(#"[[["tool_search", {"query": "list_versions"}]], "done", "done again"]"#)
        defer { model.stop() }
        try run(model, prompt: "go", defers: true)
        try run(model, prompt: "again", defers: false)
        let declared = try requests().map { $0["tools"] as? [String] ?? [] }
        XCTAssertEqual(declared.count, 3)
        XCTAssertFalse(declared[0].contains("list_versions"), "held back until it's loaded")
        XCTAssertTrue(declared[0].contains("look_at_app"))
        XCTAssertTrue(Set(Agent.deferringTools).isSubset(of: declared[0]), "tool_search and the file tools are there with no --tools")
        XCTAssertTrue(declared[1].contains("list_versions"), "loaded for the next call")
        XCTAssertFalse(declared[1].contains("device_integration"), "what wasn't loaded stays back")
        XCTAssertTrue(Set(Agent.deferredTools).isSubset(of: declared[2]), "a run that resumes names all its tools")
    }

    func testAMakeAppForThatIsNoMacGameDeclaresEverything() throws {
        let model = try standIn(#"[[["make_app_for", {"kind": "app", "made": "native", "devices": ["mac"]}]], "done"]"#)
        defer { model.stop() }
        try run(model, prompt: "go", defers: true)
        let declared = try requests().map { $0["tools"] as? [String] ?? [] }
        XCTAssertFalse(declared[0].contains("connectors"))
        XCTAssertTrue(Set(Agent.deferredTools).isSubset(of: declared[1]))
    }

    func testACommandWithNoDescriptionRunsWithTheFieldStillRequired() throws {
        let model = try standIn(#"[[["bash", {"command": "touch ran"}]], "done"]"#)
        defer { model.stop() }
        try run(model, prompt: "go", defers: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: work.appendingPathComponent("ran").path))
        let required = try XCTUnwrap(requests()[0]["bashRequired"] as? [String])
        XCTAssertTrue(required.contains("description"), "the model is still asked for it")
    }

    func testAnEditWithNoWordsRunsInPisOlderFormToo() throws {
        try "one".write(to: work.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        // Top-level oldText and newText: the form pi's own prepareArguments takes, which has to run as well.
        let model = try standIn(#"[[["edit", {"path": "a.txt", "oldText": "one", "newText": "two"}]], "done"]"#)
        defer { model.stop() }
        try run(model, prompt: "go", defers: true)
        XCTAssertEqual(try String(contentsOf: work.appendingPathComponent("a.txt"), encoding: .utf8), "two")
    }

    func testACommandWithNothingToRunIsStillRefused() throws {
        let model = try standIn(#"[[["bash", {"description": "Doing nothing"}]], "done"]"#)
        defer { model.stop() }
        try run(model, prompt: "go", defers: true)
        XCTAssertTrue((try requests()[1]["result"] as? String ?? "").contains("command"), "pi's validation still answers")
    }

    func testALookSeesTheWritesListedBeforeIt() throws {
        let model = try standIn(#"[[["bash", {"command": "sleep 1; touch written", "description": "Writing"}], ["look_at_app", {}]], "done"]"#)
        defer { model.stop() }
        try run(model, prompt: "go", defers: true)
        XCTAssertEqual(try String(contentsOf: work.appendingPathComponent("look-saw"), encoding: .utf8), "written")
    }

    func testAUseSeesTheWritesListedBeforeIt() throws {
        let model = try standIn(#"[[["bash", {"command": "sleep 1; touch written", "description": "Writing"}], ["use_app", {"actions": [{"action": "wait"}]}]], "done"]"#)
        defer { model.stop() }
        try run(model, prompt: "go", defers: true)
        XCTAssertEqual(try String(contentsOf: work.appendingPathComponent("use-saw"), encoding: .utf8), "written")
    }

    /// Order is all that's promised: a look listed first sees the state before, and nothing moves it.
    func testALookListedBeforeAWriteRunsFirst() throws {
        let model = try standIn(#"[[["look_at_app", {}], ["bash", {"command": "touch written", "description": "Writing"}]], "done"]"#)
        defer { model.stop() }
        try run(model, prompt: "go", defers: true)
        XCTAssertEqual(try String(contentsOf: work.appendingPathComponent("look-saw"), encoding: .utf8), "not yet")
    }

    func testALookStillRunsAfterAWriteThatFailed() throws {
        let model = try standIn(#"[[["bash", {"command": "exit 3", "description": "Failing"}], ["look_at_app", {}]], "done"]"#)
        defer { model.stop() }
        try run(model, prompt: "go", defers: true)
        XCTAssertEqual(try String(contentsOf: work.appendingPathComponent("look-saw"), encoding: .utf8), "not yet")
    }

    // MARK: The stand-in

    private final class StandIn {
        let port: String, process: Process, stays: Pipe
        init(port: String, process: Process, stays: Pipe) { self.port = port; self.process = process; self.stays = stays }
        // It goes when this closes: /usr/bin/python3 hands over to another process, which `terminate` wouldn't reach.
        func stop() { try? stays.fileHandleForWriting.close() }
    }

    private func standIn(_ answers: String) throws -> StandIn {
        try answers.write(to: work.appendingPathComponent("answers.json"), atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-I", "-c", Self.server, work.path]
        let port = Pipe(), stays = Pipe()
        process.standardOutput = port
        process.standardError = FileHandle.nullDevice
        process.standardInput = stays
        try process.run()
        let line = String(decoding: port.fileHandleForReading.availableData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let models = #"{"providers":{"stand-in":{"baseUrl":"http://127.0.0.1:\#(line)/v1","api":"openai-completions","apiKey":"local","models":[{"id":"big","contextWindow":1000000,"maxTokens":64000,"input":["text"]}]}}}"#
        try models.write(to: work.appendingPathComponent("config/models.json"), atomically: true, encoding: .utf8)
        return StandIn(port: line, process: process, stays: stays)
    }

    private func run(_ model: StandIn, prompt: String, defers: Bool) throws {
        let url = "http://127.0.0.1:\(model.port)"
        let config = work.appendingPathComponent("config")
        XCTAssertTrue(MainActor.assumeIsolated { PiCompaction.setDefaultTools(Agent.deferringTools, in: config) })
        var env = ["LAMP_PROMPT": prompt, "LAMP_SYSTEM": "Work.", "LAMP_SESSION": "11111111-1111-4111-8111-111111111111",
                   "LAMP_SESSION_DIR": work.appendingPathComponent("sessions").path, "LAMP_PI": work.appendingPathComponent("pi/pi").path,
                   "LAMP_PROVIDER": "stand-in", "LAMP_MODEL": "big", "LAMP_DIR": work.path,
                   "LAMP_TOOLS": root.appendingPathComponent("Resources/lamp-tools.ts").path,
                   "LAMP_TOOLS_JSON": root.appendingPathComponent("Resources/lamp-tools.json").path,
                   "LAMP_LOOK_URL": url + "/look", "LAMP_USE_URL": url + "/use", "LAMP_APPROVE_URL": url + "/approve", "LAMP_KIND_URL": url + "/kind",
                   "LAMP_TOKEN": "t", "PI_CODING_AGENT_DIR": work.appendingPathComponent("config").path, "PI_OFFLINE": "1", "PATH": "/usr/bin:/bin"]
        if defers { env["LAMP_DEFER_TOOLS"] = Agent.deferredTools.joined(separator: ",") }
        // As `Agent.command` has it, with Lamp's extension from the source tree rather than from an app.
        let everyTool = (["read", "edit", "write", "grep", "find", "ls", "bash", "look_at_app", "make_app_for"] + Agent.deferredTools).joined(separator: ",")
        let chosen = defers ? "-e builtin:tool-search" : "--tools \(everyTool)"
        let command = #""$LAMP_PI" --mode json --provider "$LAMP_PROVIDER" --model "$LAMP_MODEL" "# + chosen + #" --no-extensions -e "$LAMP_TOOLS" --no-skills --no-prompt-templates --no-context-files --no-approve --session-dir "$LAMP_SESSION_DIR" --session-id "$LAMP_SESSION" --append-system-prompt "$LAMP_SYSTEM" -- "$LAMP_PROMPT" </dev/null"#
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.environment = env
        process.currentDirectoryURL = work
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    private func requests() throws -> [[String: Any]] {
        try String(contentsOf: work.appendingPathComponent("requests.jsonl"), encoding: .utf8).split(separator: "\n")
            .compactMap { try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    }

    /// An OpenAI-style streaming endpoint giving each answer in turn (words, or the tool calls of one message), which
    /// keeps the tools each request declared, and Lamp's gateway: every command allowed, a look noting what was written
    /// by the time it came, and make_app_for saying it made something other than a Mac game.
    private static let server = #"""
    import json, os, sys, threading
    from http.server import BaseHTTPRequestHandler, HTTPServer
    threading.Thread(target=lambda: (sys.stdin.read(), os._exit(0)), daemon=True).start()
    work = sys.argv[1]
    answers = json.load(open(work + "/answers.json"))
    state = {"n": 0}
    class Stand(BaseHTTPRequestHandler):
        def log_message(self, *args): pass
        def reply(self, value):
            data = json.dumps(value).encode()
            self.send_response(200)
            self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers["content-length"])))
            if self.path == "/approve": return self.reply({"allow": True, "command": body.get("command")})
            if self.path == "/kind": return self.reply({"text": "made", "allTools": True})
            if self.path in ("/look", "/use"):
                open(work + self.path + "-saw", "w").write("written" if os.path.exists(work + "/written") else "not yet")
                return self.reply({"text": "seen"})
            with open(work + "/requests.jsonl", "a") as log:
                tools = {t["function"]["name"]: t["function"]["parameters"] for t in body.get("tools", [])}
                last = body["messages"][-1]
                log.write(json.dumps({"tools": list(tools), "bashRequired": tools.get("bash", {}).get("required", []),
                                      "result": json.dumps(last.get("content")) if last.get("role") == "tool" else ""}) + "\n")
            answer = answers[min(state["n"], len(answers) - 1)]
            state["n"] += 1
            self.send_response(200)
            self.send_header("content-type", "text/event-stream")
            self.end_headers()
            def chunk(delta, finish=None):
                event = {"id": "x", "object": "chat.completion.chunk", "created": 1, "model": "big",
                         "choices": [{"index": 0, "delta": delta, "finish_reason": finish}]}
                self.wfile.write(("data: " + json.dumps(event) + "\n\n").encode())
            if isinstance(answer, str):
                chunk({"role": "assistant", "content": answer})
                chunk({}, "stop")
            else:
                for index, (name, arguments) in enumerate(answer):
                    call = {"name": name, "arguments": json.dumps(arguments)}
                    chunk({"tool_calls": [{"index": index, "id": "c%d-%d" % (state["n"], index), "type": "function", "function": call}]})
                chunk({}, "tool_calls")
            self.wfile.write(b"data: [DONE]\n\n")
    server = HTTPServer(("127.0.0.1", 0), Stand)
    print(server.server_address[1], flush=True)
    server.serve_forever()
    """#
}
