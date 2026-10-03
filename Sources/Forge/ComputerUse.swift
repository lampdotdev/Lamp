import AppKit
import CryptoKit
import Foundation

/// Lets apps read and use the other apps on the Mac (Slack, Mail, Chrome with Gmail or LinkedIn, …) with the
/// person's own sign-ins, through trycua's cua-driver (github.com/trycua/cua, MIT).
///
/// cua-driver works through macOS Accessibility and window captures, in the background, without taking over
/// the pointer. It runs as CuaDriver.app in /Applications, which holds the Accessibility and Screen Recording
/// permissions; Forge installs it on demand (a pinned, checksummed and signature-checked release) rather than
/// shipping it in every download. Forge talks to it over MCP and runs the agent loop itself: a model gets the
/// task and a short list of the driver's tools, and works until it can answer.
///
/// Reading is always allowed. Clicking, typing and pressing keys only happen when the app asked to act
/// (`ForgeComputer.perform`), and each one waits for the person's OK in a Forge dialog.
enum ComputerUse {
    static let version = "0.32.0"
    private static let teamID = "YCK386LBJ7"   // Cua AI, Inc.
    private static let releases: [String: (file: String, sha256: String)] = [
        "arm64": ("cua-driver-rs-0.32.0-darwin-arm64.tar.gz", "31f278f38015616a02142ccbb396721897cee4892927db103a31b297f60035a9"),
        "x86_64": ("cua-driver-rs-0.32.0-darwin-x86_64.tar.gz", "0322e9316d81fbe34cbe8efe2eae83a32cf4dd86b9f34639cc0a4b3a6ed74868"),
    ]

    static let app = URL(fileURLWithPath: "/Applications/CuaDriver.app")
    static var executable: URL { app.appendingPathComponent("Contents/MacOS/cua-driver") }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: Setup

    enum Status: Equatable {
        case notInstalled
        case needsPermission
        case ready
    }

    static var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: executable.path) }

    static func status() async -> Status {
        guard isInstalled else { return .notInstalled }
        // The daemon answers with its own permission state (it holds them, not Forge). Right after an install
        // it may not be up yet, and the answer has no permissions in it: ask again shortly.
        for attempt in 0..<4 {
            let output = await capture(executable.path, ["permissions", "status", "--json"])
            let info = (try? JSONSerialization.jsonObject(with: Data(output.utf8))) as? [String: Any] ?? [:]
            if let accessibility = info["accessibility"] as? Bool, let screen = info["screen_recording"] as? Bool {
                return accessibility && screen ? .ready : .needsPermission
            }
            if attempt < 3 { try? await Task.sleep(for: .seconds(2)) }
        }
        return .needsPermission
    }

    /// The installed CuaDriver's version, e.g. "0.32.0".
    static var installedVersion: String? {
        NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
    }

    /// Downloads the pinned release, checks it, and puts CuaDriver.app in /Applications.
    static func install(progress: @escaping @MainActor (String) -> Void) async throws {
        // Replacing CuaDriver, even with the same version, makes macOS drop its screen capture consent, so
        // leave a current install alone. An upgrade asks for the permissions again (see ComputerUseSettings).
        if isInstalled, installedVersion == version { return }
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        guard let release = releases[machine.hasPrefix("arm64") ? "arm64" : "x86_64"] else {
            throw Failure(message: "Using other apps isn't available on this Mac.")
        }
        await progress("Downloading…")
        let url = URL(string: "https://github.com/trycua/cua/releases/download/cua-driver-rs-v\(version)/\(release.file)")!
        let (download, response) = try await URLSession.shared.download(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw Failure(message: "Couldn't download the helper. Check your internet connection and try again.")
        }
        await progress("Checking…")
        let data = try Data(contentsOf: download, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == release.sha256 else { throw Failure(message: "The download didn't match the expected file.") }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("forge-cua-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        guard await run("/usr/bin/tar", ["-xzf", download.path, "-C", work.path]) == 0,
              let folder = try FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil).first
        else { throw Failure(message: "Couldn't unpack the helper.") }
        let unpacked = folder.appendingPathComponent("CuaDriver.app")
        guard signedByCua(unpacked) else { throw Failure(message: "The helper isn't signed by its developer.") }

        await progress("Installing…")
        _ = await run("/usr/bin/pkill", ["-f", "CuaDriver.app/Contents/MacOS/cua-driver"])
        try? FileManager.default.removeItem(at: app)
        guard await run("/usr/bin/ditto", [unpacked.path, app.path]) == 0 else {
            throw Failure(message: "Couldn't add CuaDriver to your Applications folder.")
        }
        _ = await run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                      ["-f", app.path])
        // Content-free product telemetry is on by default; Forge turns it off.
        _ = await run(executable.path, ["telemetry", "disable"])
    }

    /// Opens macOS's permission requests for CuaDriver and waits until they're answered.
    static func requestPermissions() async {
        _ = await run(executable.path, ["permissions", "grant"])
    }

    private static func signedByCua(_ bundle: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil) == errSecSuccess
        else { return false }
        var info: CFDictionary?
        SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String == teamID
    }

    // MARK: Running a task

    /// Tools that only look. Scrolling changes nothing, so it counts as looking.
    static let readTools: Set<String> = ["list_apps", "list_windows", "get_window_state", "zoom", "scroll"]
    /// Tools that act, each confirmed by the person first.
    static let actTools: Set<String> = ["click", "double_click", "right_click", "type_text", "press_key", "hotkey",
                                        "set_value", "invoke_menu", "launch_app"]

    /// What a step wants to do, for the person to approve.
    struct Action {
        let tool: String
        let summary: String   // the model's own description of the step
    }

    /// Runs `task` and returns the model's answer, plus the cost in USD. `approve` is asked before every action
    /// and returns false to refuse it.
    static func run(task: String, appName: String, allowActions: Bool, model: String,
                    approve: @escaping (Action) async -> Bool) async throws -> (String, Double) {
        guard isInstalled else {
            throw Failure(message: "Using other apps isn't set up yet. Turn it on in Forge → Settings → Apps.")
        }
        guard let key = KeyStore.openRouterKey else {
            throw Failure(message: "Using other apps needs an OpenRouter key. Add one in Forge → Settings → Providers.")
        }
        let client = try MCPClient(executable: executable, arguments: ["mcp"])
        defer { client.close() }
        let instructions = try await client.initialize()
        let allowed = allowActions ? readTools.union(actTools) : readTools
        let tools = try await client.listTools().filter { allowed.contains($0.name) }.map { tool -> [String: Any] in
            var schema = tool.inputSchema
            if actTools.contains(tool.name) {
                // Every action carries a plain description, shown to the person before it happens.
                var properties = schema["properties"] as? [String: Any] ?? [:]
                properties["intent"] = ["type": "string",
                                        "description": "What this does, in plain words for the person approving it, e.g. “Click Send in Slack”."]
                schema["properties"] = properties
                schema["required"] = ((schema["required"] as? [String]) ?? []) + ["intent"]
            }
            return ["type": "function", "function": ["name": tool.name, "description": tool.description, "parameters": schema]]
        }

        let system = """
        You use the apps on this Mac on behalf of "\(appName)", an app the person made, to do one task, then answer.
        The person is signed in to their apps and browsers already; work with what's there.
        \(allowActions
            ? "You may click, type and press keys when the task needs it. Each action is shown to the person to approve first, so give every action a clear `intent`. Never send, post, delete, buy or change settings unless the task asks for exactly that."
            : "Only look: you can read windows and scroll, but not click, type or change anything.")
        Find the right window with list_windows, read it with get_window_state, and scroll to see more. Prefer the \
        element tree to the picture when both have what you need. Keep going until you can answer, then reply \
        with only the answer, in the form the task asks for. If you can't do it, say what stopped you.

        About the tools:
        \(instructions)
        """
        var messages: [[String: Any]] = [["role": "system", "content": system], ["role": "user", "content": task]]
        var cost = 0.0
        for _ in 0..<40 {
            let (message, stepCost) = try await complete(messages: messages, tools: tools, model: model, key: key)
            cost += stepCost
            messages.append(message)
            let calls = message["tool_calls"] as? [[String: Any]] ?? []
            if calls.isEmpty {
                return ((message["content"] as? String ?? "").trimmed, cost)
            }
            var pictures: [[String: Any]] = []
            for call in calls {
                let function = call["function"] as? [String: Any] ?? [:]
                let name = function["name"] as? String ?? ""
                var arguments = ((function["arguments"] as? String).flatMap {
                    try? JSONSerialization.jsonObject(with: Data($0.utf8))
                } as? [String: Any]) ?? [:]
                let intent = arguments.removeValue(forKey: "intent") as? String
                var reply: String
                if !allowed.contains(name) {
                    reply = "That tool isn't available for this task."
                } else if actTools.contains(name),
                          !(await approve(Action(tool: name, summary: intent ?? name.replacingOccurrences(of: "_", with: " ")))) {
                    reply = "The person declined this action. Don't try it another way; finish with what you have, or say what you needed."
                } else {
                    if name == "get_window_state", arguments["max_image_dimension"] == nil { arguments["max_image_dimension"] = 1280 }
                    do {
                        let result = try await client.call(name, arguments: arguments)
                        reply = result.text.isEmpty ? "Done." : String(result.text.prefix(60_000))
                        if name == "list_windows", let windows = visibleWindows(result.structured) { reply = windows }
                        pictures += result.images.map {
                            ["type": "image_url", "image_url": ["url": "data:\($0.mimeType);base64,\($0.data)"]]
                        }
                    } catch {
                        reply = "Error: \(error.localizedDescription)"
                    }
                }
                messages.append(["role": "tool", "tool_call_id": call["id"] as? String ?? "", "content": reply])
            }
            // Tool results are text; pictures from them follow as one message the model can see.
            if !pictures.isEmpty {
                messages.append(["role": "user", "content": [["type": "text", "text": "Pictures from those steps:"]] + pictures.suffix(2)])
            }
            // Keep only the latest pictures: older ones are stale and costly.
            var seen = 0
            for index in messages.indices.reversed() where messages[index]["role"] as? String == "user"
                && (messages[index]["content"] as? [[String: Any]])?.first?["text"] as? String == "Pictures from those steps:" {
                seen += 1
                if seen > 1 { messages[index]["content"] = "(An earlier picture, removed to save space.)" }
            }
        }
        throw Failure(message: "The task took too many steps, so Forge stopped it.")
    }

    /// list_windows lists every window on the Mac, hundreds of them, most off screen or untitled. The model only
    /// needs the ones a person could be looking at.
    private static func visibleWindows(_ structured: Any?) -> String? {
        guard let windows = (structured as? [String: Any])?["windows"] as? [[String: Any]] else { return nil }
        let lines = windows.compactMap { window -> String? in
            guard window["is_on_screen"] as? Bool == true, let title = window["title"] as? String, !title.isEmpty,
                  let pid = window["pid"] as? Int, let id = window["window_id"] as? Int else { return nil }
            return "pid=\(pid) window_id=\(id) app=\(window["app_name"] as? String ?? "?") title=\(title)"
        }
        return lines.isEmpty ? "No visible windows." : "Visible windows:\n" + lines.joined(separator: "\n")
    }

    private static func complete(messages: [[String: Any]], tools: [[String: Any]], model: String,
                                 key: String) async throws -> ([String: Any], Double) {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Forge", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "messages": messages, "tools": tools, "usage": ["include": true],
        ] as [String: Any])
        let (data, response) = try await URLSession.shared.data(for: request)
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, let message = ((obj["choices"] as? [[String: Any]])?.first?["message"]) as? [String: Any] else {
            let detail = (obj["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(status)"
            throw Failure(message: Provider.friendlyError("\(status) \(detail)"))
        }
        var kept: [String: Any] = ["role": "assistant", "content": message["content"] as? String ?? ""]
        if let calls = message["tool_calls"] { kept["tool_calls"] = calls }
        return (kept, (obj["usage"] as? [String: Any])?["cost"] as? Double ?? 0)
    }

    // MARK: Processes

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(returning: -1) }
        }
    }

    private static func capture(_ tool: String, _ arguments: [String]) async -> String {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { _ in
                continuation.resume(returning: String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
            }
            do { try process.run() } catch { continuation.resume(returning: "") }
        }
    }
}

/// A minimal MCP client over stdio (newline-delimited JSON-RPC), enough for one server's tools.
final class MCPClient: @unchecked Sendable {
    struct Tool {
        let name: String
        let description: String
        let inputSchema: [String: Any]
    }

    struct CallResult {
        let text: String
        let images: [(mimeType: String, data: String)]
        var structured: Any? = nil
    }

    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let lock = NSLock()
    private var buffer = Data()
    private var waiting: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var nextID = 1

    init(executable: URL, arguments: [String]) throws {
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self else { return }
            if chunk.isEmpty { self.failAll(); return }
            self.receive(chunk)
        }
        process.terminationHandler = { [weak self] _ in self?.failAll() }
        try process.run()
    }

    /// Starts the session; returns the server's instructions.
    func initialize() async throws -> String {
        let result = try await request("initialize", [
            "protocolVersion": "2025-06-18", "capabilities": [:] as [String: Any],
            "clientInfo": ["name": "Forge", "version": BuildStamp.current.forge ?? "0"],
        ])
        notify("notifications/initialized")
        return result["instructions"] as? String ?? ""
    }

    func listTools() async throws -> [Tool] {
        let result = try await request("tools/list", [:])
        return (result["tools"] as? [[String: Any]] ?? []).compactMap { tool in
            guard let name = tool["name"] as? String else { return nil }
            return Tool(name: name, description: tool["description"] as? String ?? "",
                        inputSchema: tool["inputSchema"] as? [String: Any] ?? ["type": "object"])
        }
    }

    func call(_ name: String, arguments: [String: Any]) async throws -> CallResult {
        let result = try await request("tools/call", ["name": name, "arguments": arguments])
        var texts: [String] = []
        var images: [(String, String)] = []
        for item in result["content"] as? [[String: Any]] ?? [] {
            switch item["type"] as? String {
            case "text": if let text = item["text"] as? String { texts.append(text) }
            case "image":
                if let data = item["data"] as? String { images.append((item["mimeType"] as? String ?? "image/png", data)) }
            default: break
            }
        }
        var text = texts.joined(separator: "\n")
        // Some tools put their data only in structuredContent and give a one-line summary as text
        // ("Found 12 window(s)."). Long text, like a window's element tree, already says it all.
        if text.count < 500, let structured = result["structuredContent"],
           let data = try? JSONSerialization.data(withJSONObject: structured, options: [.sortedKeys]) {
            text += (text.isEmpty ? "" : "\n") + String(decoding: data, as: UTF8.self)
        }
        if result["isError"] as? Bool == true { throw ComputerUse.Failure(message: text.isEmpty ? "The step failed." : text) }
        return CallResult(text: text, images: images, structured: result["structuredContent"])
    }

    func close() {
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        failAll()
    }

    private func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            let id = nextID
            nextID += 1
            waiting[id] = continuation
            lock.unlock()
            send(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        }
    }

    private func notify(_ method: String) { send(["jsonrpc": "2.0", "method": method]) }

    private func send(_ message: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: message) else { return }
        data.append(0x0A)
        try? input.fileHandleForWriting.write(contentsOf: data)
    }

    private func receive(_ chunk: Data) {
        lock.lock()
        buffer.append(chunk)
        var replies: [(CheckedContinuation<[String: Any], Error>, Result<[String: Any], Error>)] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  let id = message["id"] as? Int, let continuation = waiting.removeValue(forKey: id) else { continue }
            if let error = message["error"] as? [String: Any] {
                replies.append((continuation, .failure(ComputerUse.Failure(message: error["message"] as? String ?? "The helper failed."))))
            } else {
                replies.append((continuation, .success(message["result"] as? [String: Any] ?? [:])))
            }
        }
        lock.unlock()
        for (continuation, result) in replies { continuation.resume(with: result) }
    }

    private func failAll() {
        lock.lock()
        let pending = waiting
        waiting.removeAll()
        lock.unlock()
        for continuation in pending.values {
            continuation.resume(throwing: ComputerUse.Failure(message: "The helper stopped unexpectedly."))
        }
    }
}
