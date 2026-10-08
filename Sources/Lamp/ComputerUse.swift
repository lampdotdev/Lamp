import AppKit
import CryptoKit
import Foundation

/// Lets apps read and use the other apps on the Mac (Slack, Mail, Chrome with Gmail or LinkedIn, …) with the
/// person's own sign-ins, through trycua's cua-driver (github.com/trycua/cua, MIT).
///
/// cua-driver works through macOS Accessibility and window captures, in the background, without taking over
/// the pointer. It runs as CuaDriver.app in /Applications, which holds the Accessibility and Screen Recording
/// permissions; Lamp installs it on demand (a pinned, checksummed and signature-checked release) rather than
/// shipping it in every download. Lamp talks to it over MCP and runs the agent loop itself: a model gets the
/// task and a short list of the driver's tools, and works until it can answer.
///
/// Reading is always allowed. Clicking, typing and pressing keys only happen when the app asked to act
/// (`LampComputer.perform`), and each one waits for the person's OK in a Lamp dialog.
enum ComputerUse {
    static let version = "0.32.0"
    private static let teamID = "YCK386LBJ7"   // Cua AI, Inc.
    private static let releases: [String: (file: String, sha256: String)] = [
        "arm64": ("cua-driver-rs-0.32.0-darwin-arm64.tar.gz", "31f278f38015616a02142ccbb396721897cee4892927db103a31b297f60035a9"),
        "x86_64": ("cua-driver-rs-0.32.0-darwin-x86_64.tar.gz", "0322e9316d81fbe34cbe8efe2eae83a32cf4dd86b9f34639cc0a4b3a6ed74868"),
    ]

    /// The person's choice in Settings → Apps. Off until they turn it on, even if CuaDriver is already installed.
    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "computerUse") }
        set { UserDefaults.standard.set(newValue, forKey: "computerUse") }
    }

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
        if CodexComputerUse.isAvailable { return .ready }   // its helper app holds the permissions
        guard isInstalled else { return .notInstalled }
        // The daemon answers with its own permission state (it holds them, not Lamp). Right after an install
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
        // A current install is left alone: replacing it would stop the running driver for nothing.
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
        if await run("/usr/bin/ditto", [unpacked.path, app.path]) != 0 {
            // /Applications is writable by administrators only. A standard account (common on work Macs) gets
            // macOS's own password prompt instead, for someone who can approve it.
            let script = """
            do shell script "/bin/rm -rf " & quoted form of "\(app.path)" & " && /usr/bin/ditto " & \
            quoted form of "\(unpacked.path)" & " " & quoted form of "\(app.path)" with administrator privileges \
            with prompt "Lamp needs to add CuaDriver to the Applications folder so your apps can use your other apps."
            """
            guard await run("/usr/bin/osascript", ["-e", script]) == 0, isInstalled else {
                throw Failure(message: "Couldn't add CuaDriver to the Applications folder. It needs an administrator's password; on a work Mac, ask your IT team.")
            }
        }
        _ = await run("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                      ["-f", app.path])
        // Content-free product telemetry is on by default; Lamp turns it off.
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
        /// The app it acts in, worked out from the process, not taken from the model.
        let target: String
        /// What will actually happen, built from the tool's arguments: the exact text typed, the keys pressed,
        /// the element clicked (named from the last window read), the menu chosen.
        let details: String
        /// The model's own description. Shown second: it can be wrong, or steered by what's on screen.
        let intent: String?
    }

    /// Describes an action from its real arguments. `labels` maps element tokens to what the person sees.
    static func describe(_ tool: String, _ arguments: [String: Any], labels: [String: String]) -> Action {
        let pid = (arguments["pid"] as? Int) ?? (arguments["pid"] as? NSNumber)?.intValue
        let app = pid.flatMap { NSRunningApplication(processIdentifier: pid_t($0))?.localizedName }
        let bundle = arguments["bundle_id"] as? String
        let target = app ?? (arguments["name"] as? String) ?? bundle ?? "an app"
        let element: String? = (arguments["element_token"] as? String).map { labels[$0] ?? "an unnamed item" }
        let spot = element ?? "a spot in the window"
        func quoted(_ text: String) -> String {
            text.count > 600 ? "“\(text.prefix(600))…” (\(text.count - 600) more characters)" : "“\(text)”"
        }
        func keys(_ list: [String]) -> String {
            let symbols = ["cmd": "⌘", "command": "⌘", "shift": "⇧", "option": "⌥", "alt": "⌥", "ctrl": "⌃",
                           "control": "⌃", "return": "⏎", "enter": "⏎", "tab": "⇥", "escape": "⎋", "esc": "⎋",
                           "delete": "⌫", "space": "Space", "up": "↑", "down": "↓", "left": "←", "right": "→"]
            return list.map { symbols[$0.lowercased()] ?? $0.uppercased() }.joined()
        }
        let details: String
        switch tool {
        case "click":
            let count = arguments["count"] as? Int ?? 1
            let verb = arguments["button"] as? String == "right" ? "Right-click" : count > 1 ? "Double-click" : "Click"
            details = "\(verb) \(spot)"
        case "double_click": details = "Double-click \(spot)"
        case "right_click": details = "Right-click \(spot)"
        case "type_text":
            details = "Type \(quoted(arguments["text"] as? String ?? ""))" + (element.map { " into \($0)" } ?? "")
        case "set_value":
            details = "Set \(element ?? "a field") to \(quoted("\(arguments["value"] ?? "")"))"
        case "press_key":
            let modifiers = arguments["modifiers"] as? [String] ?? []
            details = "Press \(keys(modifiers + [arguments["key"] as? String ?? "?"]))"
        case "hotkey":
            details = "Press \(keys(arguments["keys"] as? [String] ?? []))"
        case "invoke_menu":
            details = "Choose \((arguments["path"] as? [String] ?? []).joined(separator: " → ")) from the menu"
        case "launch_app":
            let urls = arguments["urls"] as? [String] ?? []
            details = "Open \(target)" + (urls.isEmpty ? "" : " with \(urls.joined(separator: ", "))")
        default:
            details = tool.replacingOccurrences(of: "_", with: " ")
        }
        return Action(tool: tool, target: target, details: details, intent: nil)
    }

    /// "the “Send” button": what a person would call an element from the last window read.
    static func label(of element: [String: Any]) -> String? {
        let text = [element["label"], element["title"], element["value"], element["description"]]
            .compactMap { ($0 as? String)?.trimmed }.first { !$0.isEmpty }
        guard let text else { return nil }
        let kinds = ["AXButton": "button", "AXLink": "link", "AXTextField": "text field", "AXTextArea": "text box",
                     "AXMenuItem": "menu item", "AXCheckBox": "checkbox", "AXRadioButton": "option",
                     "AXPopUpButton": "menu", "AXTab": "tab", "AXRow": "row", "AXCell": "item"]
        let kind = kinds[element["role"] as? String ?? ""] ?? "item"
        return "the “\(text.prefix(80))” \(kind)"
    }

    /// What stops a task before it starts, or nil.
    static func check() -> Failure? {
        guard isInstalled || CodexComputerUse.isAvailable else {
            return Failure(message: "Using other apps isn't set up yet. Turn on “Let apps use your other apps” in Lamp → Settings → Apps.")
        }
        // While the Mac is locked, apps don't expose their windows and screen capture is refused.
        if (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true {
            return Failure(message: "The Mac is locked, so other apps can't be read. Try again once it's unlocked.")
        }
        return nil
    }

    /// Turning the setting off stops a task that's already running, before its next step.
    static let stopped = Failure(message: "Using other apps was turned off, so Lamp stopped the task.")

    /// One task in progress (not Swift's Task): the connection to the driver, the tools the model may use, what the person has
    /// to approve, and the names of what's on screen. Whichever model drives the task (OpenRouter, a local
    /// model, or a coding agent through Lamp's MCP endpoint) calls `call` for each step.
    /// What does the looking and clicking: Codex's computer use when the ChatGPT app has it, else CuaDriver.
    enum Driver: String { case codex, cua }

    final class Job {
        let taskText: String
        let appName: String
        let allowActions: Bool
        let approve: (Action) async -> Bool
        let driver: Driver
        private let client: MCPClient
        private let allowed: Set<String>
        /// The driver's tools the model may use, with `intent` added to those that act.
        let tools: [MCPClient.Tool]
        let systemPrompt: String
        private var labels: [String: String] = [:]   // element tokens from the windows read so far

        init(_ taskText: String, appName: String, allowActions: Bool, approve: @escaping (Action) async -> Bool) async throws {
            self.taskText = taskText
            self.appName = appName
            self.allowActions = allowActions
            self.approve = approve
            // Codex's computer use first, when it's there and starts; CuaDriver otherwise. Codex's asks before
            // each step, and the answer is the person's for anything that acts.
            var codex: MCPClient?
            var codexInstructions = ""
            if CodexComputerUse.isAvailable {
                if let client = try? CodexComputerUse.connect(elicitation: { _ in false }),
                   let instructions = try? await client.initialize() {
                    codex = client
                    codexInstructions = instructions
                } else {
                    print("Codex's computer use is installed but didn't start; using CuaDriver.")
                }
            }
            if let codex {
                driver = .codex
                client = codex
                let names: Set<String> = ["js", "js_reset"]
                allowed = names
                let listed = try await client.listTools()
                tools = listed.filter { names.contains($0.name) }
                systemPrompt = CodexComputerUse.systemPrompt(appName: appName, allowActions: allowActions, instructions: codexInstructions,
                                                             toolDescription: listed.first { $0.name == "js" }?.description ?? "")
                return   // the server's questions are answered from `call`, once self exists
            }
            driver = .cua
            guard isInstalled else {
                throw Failure(message: "Using other apps isn't set up yet. Turn on “Let apps use your other apps” in Lamp → Settings → Apps.")
            }
            client = try MCPClient(executable: executable, arguments: ["mcp"])
            let instructions: String
            do {
                instructions = try await client.initialize()
            } catch {
                client.close()
                throw error
            }
            allowed = allowActions ? readTools.union(actTools) : readTools
            let allowed = allowed
            tools = try await client.listTools().filter { allowed.contains($0.name) }.map { tool in
                var schema = tool.inputSchema
                if actTools.contains(tool.name) {
                    // Every action carries a plain description, shown to the person before it happens.
                    var properties = schema["properties"] as? [String: Any] ?? [:]
                    properties["intent"] = ["type": "string",
                                            "description": "What this does, in plain words for the person approving it, e.g. “Click Send in Slack”."]
                    schema["properties"] = properties
                    schema["required"] = ((schema["required"] as? [String]) ?? []) + ["intent"]
                }
                return MCPClient.Tool(name: tool.name, description: tool.description, inputSchema: schema)
            }
            systemPrompt = """
            You use the apps on this Mac on behalf of "\(appName)", an app the person made, to do one task, then answer.
            The person is signed in to their apps and browsers already; work with what's there.
            \(allowActions
                ? "You may click, type and press keys when the task needs it. Each action is shown to the person to approve first, so give every action a clear `intent`. Never send, post, delete, buy or change settings unless the task asks for exactly that."
                : "Only look: you can read windows and scroll, but not click, type or change anything.")
            Find the right window with list_windows, read it with get_window_state, and scroll to see more. A web page \
            that's open but not in front: find it with list_browser_tabs and bring it forward with show_browser_tab, \
            then read its window. Prefer the \
            element tree to the picture when both have what you need. Keep going until you can answer, then reply \
            with only the answer, in the form the task asks for. If you can't do it, say what stopped you. Use only \
            these tools: never a shell, and never files.

            About the tools:
            \(instructions)
            """
        }

        func close() { client.close() }

        /// Codex's question before a step: reads go ahead, actions only when the task may act and the person
        /// allows this one (or allowed all for the task). The same dialog as CuaDriver's actions get.
        private func decide(_ elicitation: MCPClient.Elicitation) async -> Bool {
            guard enabled else { return false }
            if CodexComputerUse.read(elicitation) { return true }
            guard allowActions else { return false }
            let allowed = await approve(CodexComputerUse.action(elicitation, intent: currentIntent))
            return allowed && enabled   // it may have been turned off during the dialog
        }

        /// What the model said the current `js` step is for, shown with each approval it raises.
        private var currentIntent: String?

        /// The tools in OpenAI's function-calling shape, for the chat-completions loop.
        var openAITools: [[String: Any]] {
            tools.map { ["type": "function", "function": ["name": $0.name, "description": $0.description, "parameters": $0.inputSchema]] }
                + BrowserTabs.tools
        }

        /// The tools as an MCP server lists them, for the coding agents.
        var mcpTools: [[String: Any]] {
            tools.map { ["name": $0.name, "description": $0.description, "inputSchema": $0.inputSchema] }
                + BrowserTabs.tools.compactMap { tool in
                    guard let function = tool["function"] as? [String: Any] else { return nil }
                    return ["name": function["name"] ?? "", "description": function["description"] ?? "", "inputSchema": function["parameters"] ?? [:]]
                }
        }

        /// One step: the person's approval when it acts, then the driver. Pictures come back apart from
        /// the text, for the caller to hand to its model in that model's way.
        func call(_ name: String, _ arguments: [String: Any]) async throws -> (text: String, pictures: [(mimeType: String, data: String)]) {
            var arguments = arguments
            let intent = arguments.removeValue(forKey: "intent") as? String
            guard enabled else { throw stopped }
            if BrowserTabs.handles(name) { return (await BrowserTabs.call(name, arguments), []) }
            guard allowed.contains(name) else { return ("That tool isn't available for this task.", []) }
            if driver == .codex {
                // The server asks about each step itself (decide); the title is the model's word for it.
                client.elicitationHandler = { [weak self] in await self?.decide($0) ?? false }
                currentIntent = arguments["title"] as? String ?? intent
                do {
                    let result = try await client.call(name, arguments: arguments)
                    return (String(result.text.prefix(60_000)), result.images.map { (mimeType: "image/jpeg", data: compactJPEG($0.data, mimeType: $0.mimeType)) })
                } catch {
                    return ("Error: \(error.localizedDescription)", [])
                }
            }
            if actTools.contains(name) {
                let described = ComputerUse.describe(name, arguments, labels: labels)
                let action = Action(tool: name, target: described.target, details: described.details, intent: intent)
                guard await approve(action) else {
                    return ("The person declined this action. Don't try it another way; finish with what you have, or say what you needed.", [])
                }
                guard enabled else { throw stopped }   // it may have been turned off during the dialog
            }
            if name == "get_window_state", arguments["max_image_dimension"] == nil { arguments["max_image_dimension"] = 1024 }
            do {
                let result = try await client.call(name, arguments: arguments)
                var text = result.text.isEmpty ? "Done." : String(result.text.prefix(60_000))
                if name == "list_windows", let windows = visibleWindows(result.structured) { text = windows }
                if name == "get_window_state",
                   let elements = (result.structured as? [String: Any])?["elements"] as? [[String: Any]] {
                    for element in elements {
                        if let token = element["element_token"] as? String, let label = ComputerUse.label(of: element) {
                            labels[token] = label
                        }
                    }
                }
                return (text, result.images.map { (mimeType: "image/jpeg", data: compactJPEG($0.data, mimeType: $0.mimeType)) })
            } catch {
                return ("Error: \(error.localizedDescription)", [])
            }
        }
    }

    /// Runs the task along the app's text route and returns the answer plus the cost in USD: an OpenRouter
    /// model in Lamp's own loop, Claude Code or Codex with the driver's tools over Lamp's MCP endpoint, or pi
    /// (with its key provider, its own sign-ins, or a model on this Mac) through its extension. `token` is
    /// the task's, for that endpoint.
    static func answer(_ task: Job, route: AppAI.TextRoute, token: String) async throws -> (String, Double) {
        switch route.kind {
        case .openRouter(let model):
            guard let key = KeyStore.openRouterKey else {
                throw Failure(message: "Using other apps needs an OpenRouter key, or a working builder. Set one up in Lamp → Settings (⌘,).")
            }
            return try await loop(task, endpoint: "https://openrouter.ai/api/v1/chat/completions", key: key, model: model)
        case .engine(.pi, _), .localModel:
            guard Agent.executable != nil else { throw Failure(message: "Lamp's AI builder is missing. Download Lamp again.") }
            // A local model's server is started, and Ollama's or LM Studio's models are registered with pi,
            // as before a build turn.
            if case .localModel(let provider, let model) = route.kind {
                if provider == Builder.localProvider { _ = try await LocalModels.shared.ensureServer(for: model) }
                if LocalModels.externalIDs.contains(provider) { await LocalModels.shared.detectExternal() }
            }
            return try await viaEngine(.pi, task, token: token, model: nil, piRoute: route)
        case .engine(let engine, let model):
            guard ToolLocator.path(for: engine) != nil else {
                throw Failure(message: "Using other apps needs an OpenRouter key, or a working builder. Set one up in Lamp → Settings (⌘,).")
            }
            return try await viaEngine(engine, task, token: token, model: model)
        }
    }

    /// The loop for OpenRouter's chat-completions API with tool calling: the model gets the task and the
    /// tools, and each tool call goes to the driver until it answers.
    private static func loop(_ task: Job, endpoint: String, key: String?, model: String) async throws -> (String, Double) {
        let tools = task.openAITools
        var messages: [[String: Any]] = [["role": "system", "content": task.systemPrompt], ["role": "user", "content": task.taskText]]
        var cost = 0.0
        for _ in 0..<40 {
            guard enabled else { throw stopped }
            let (message, stepCost) = try await complete(endpoint: endpoint, messages: messages, tools: tools, model: model, key: key)
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
                let arguments = ((function["arguments"] as? String).flatMap {
                    try? JSONSerialization.jsonObject(with: Data($0.utf8))
                } as? [String: Any]) ?? [:]
                let (reply, images) = try await task.call(name, arguments)
                pictures += images.map { ["type": "image_url", "image_url": ["url": "data:\($0.mimeType);base64,\($0.data)"]] }
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
        throw Failure(message: "The task took too many steps, so Lamp stopped it.")
    }

    /// The task as one turn of a coding agent, with the driver's tools: pi through its extension (which
    /// posts each call to Lamp), Claude Code and Codex through Lamp's MCP endpoint. Isolated from the
    /// person's own setup like a build turn, in an empty folder, with no file or shell tools. The agent's
    /// last message is the answer.
    private static func viaEngine(_ engine: Engine, _ task: Job, token: String, model: String?, piRoute: AppAI.TextRoute? = nil) async throws -> (String, Double) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-computer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var env: [String: String] = ["PATH": ToolLocator.userPath, "LAMP_TOKEN": token,
                                     "LAMP_SYSTEM": task.systemPrompt, "LAMP_PROMPT": task.taskText,
                                     "MCP_TOOL_TIMEOUT": "600000"]
        // What the turn goes through, for an error to name.
        var source = Provider.name(of: engine)
        let command: String
        switch engine {
        case .pi:
            // The extension registers the tools from this file and posts each call to Lamp.
            let toolsFile = folder.appendingPathComponent("computer-tools.json")
            try JSONSerialization.data(withJSONObject: task.mcpTools).write(to: toolsFile)
            env.merge(Agent.environment(prompt: task.taskText, files: [], session: "", sessionDir: folder.path)) { $1 }
            // The route's own provider and model when it's a model on this Mac rather than the builder's.
            // Those providers are registered in Lamp's own pi configuration, so pi reads that even when
            // building goes through the person's own setup.
            if case .localModel(let provider, let model)? = piRoute?.kind {
                env["LAMP_PROVIDER"] = provider == Builder.localProvider ? LocalModels.piProvider(for: model) : provider
                env["LAMP_MODEL"] = model
                env["PI_CODING_AGENT_DIR"] = Agent.configDir
                source = piRoute?.group ?? source
            }
            env["LAMP_COMPUTER_TOOLS_JSON"] = toolsFile.path
            env["LAMP_COMPUTER_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/computer"
            env["LAMP_SYSTEM"] = task.systemPrompt
            // No built-in tools (files, shell) but the extension's; no extensions but Lamp's, whatever the
            // person's own pi setup has.
            command = """
            "$LAMP_PI" --mode json --provider "$LAMP_PROVIDER" --model "$LAMP_MODEL" --no-builtin-tools --no-session \\
              --no-extensions -e "$LAMP_TOOLS" --no-skills --no-prompt-templates --no-context-files --no-approve \\
              --system-prompt "$LAMP_SYSTEM" -- "$LAMP_PROMPT"
            """
        case .claude:
            env["LAMP_TOOL"] = ToolLocator.path(for: .claude) ?? "claude"
            let mcpConfig = folder.appendingPathComponent("mcp.json")
            let mcp: [String: Any] = ["mcpServers": ["lamp": ["type": "http", "url": "http://127.0.0.1:\(Gateway.port)/mcp",
                                                               "headers": ["Authorization": "Bearer ${LAMP_TOKEN}"]]]]
            try JSONSerialization.data(withJSONObject: mcp).write(to: mcpConfig)
            env["LAMP_CLAUDE_MCP"] = mcpConfig.path
            env["LAMP_CLAUDE_ALLOWED"] = task.mcpTools.compactMap { $0["name"] as? String }.map { "mcp__lamp__" + $0 }.joined(separator: ",")
            env["LAMP_MODEL"] = model ?? ""
            command = """
            "$LAMP_TOOL" -p "$LAMP_PROMPT" --output-format stream-json --verbose --no-session-persistence \\
              --restricted --strict-mcp-config --mcp-config "$LAMP_CLAUDE_MCP" --disable-slash-commands \\
              --tools '' --allowedTools "$LAMP_CLAUDE_ALLOWED" --system-prompt "$LAMP_SYSTEM"
            """ + ((model ?? "").isEmpty ? "" : " --model \"$LAMP_MODEL\"")
        case .codex:
            env["LAMP_TOOL"] = ToolLocator.path(for: .codex) ?? "codex"
            env["LAMP_CODEX_INSTRUCTIONS"] = "developer_instructions=" + Agent.tomlString(task.systemPrompt)
            var modelArg = ""
            if let model, Builder.codexModels.contains(where: { $0.id == model && !model.isEmpty }) {
                env["LAMP_MODEL"] = model
                modelArg = "-m \"$LAMP_MODEL\" "
            }
            // Codex keeps its shell whatever the sandbox, and reads files with it: a hook says no to every
            // command, so the task has nothing but its own tools. The read-only sandbox covers writes.
            let deny = folder.appendingPathComponent("deny.sh")
            try """
            #!/bin/sh
            printf '%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"This task may only use the tools Lamp gave it: no shell, no files."}}'

            """.write(to: deny, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: deny.path)
            env["LAMP_CODEX_HOOKS"] = #"hooks.PreToolUse=[{matcher="^Bash$",hooks=[{type="command",timeout=60,command="'"# + deny.path + #"'"}]}]"#
            command = """
            "$LAMP_TOOL" exec --json --ignore-user-config --ignore-rules --dangerously-bypass-hook-trust --skip-git-repo-check --ephemeral \\
              -s read-only -c "$LAMP_CODEX_HOOKS" \(modelArg)-c "$LAMP_CODEX_INSTRUCTIONS" \\
              -c mcp_servers.lamp.url="http://127.0.0.1:\(Gateway.port)/mcp" -c mcp_servers.lamp.bearer_token_env_var="LAMP_TOKEN" \\
              -c mcp_servers.lamp.tool_timeout_sec=3600 -c mcp_servers.lamp.default_tools_approval_mode="approve" -- "$LAMP_PROMPT"
            """
        }
        var text = ""
        var cost = 0.0
        var failure: String?
        var notice: String?   // the agent's own last word about what went wrong, when it didn't answer
        var lastLine = ""
        let status = await Shell.run(command, cwd: folder, env: env) { line in
            lastLine = line
            for event in Agent.parse(line, engine: engine) {
                switch event {
                case .text(let chunk): text = chunk   // the last message is the answer
                case .cost(let amount): cost += amount
                case .failed(let message): failure = message
                case .raw(let message): notice = message
                default: break
                }
            }
        }
        guard enabled else { throw stopped }
        if let failure { throw Failure(message: Provider.friendlyError(failure, from: source)) }
        guard status == 0 || !text.isEmpty else {
            let why = notice ?? (lastLine.hasPrefix("{") ? "" : lastLine.trimmed)
            // 137 is a kill: the agent was stopped from outside, before it said anything.
            let stoppedEarly = status == 137 && text.isEmpty && why.isEmpty
            throw Failure(message: stoppedEarly ? "\(engine.title) stopped before it could answer. Try again."
                          : "The AI didn't answer." + (why.isEmpty ? "" : " " + Provider.friendlyError(why, from: source)))
        }
        return (text.trimmed, cost)
    }

    /// The driver's pictures are PNGs, around a megabyte each: as JPEGs they're a tenth of that, which keeps each
    /// request small enough to upload reliably. Base64 of the JPEG (or of the original when it can't be read).
    static func compactJPEG(_ base64: String, mimeType: String) -> String {
        guard let data = Data(base64Encoded: base64), let bitmap = NSBitmapImageRep(data: data),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else { return base64 }
        return jpeg.base64EncodedString()
    }

    /// list_windows lists every window on the Mac, hundreds of them, most off screen or untitled. The model only
    /// needs the ones a person could be looking at.
    static func visibleWindows(_ structured: Any?) -> String? {
        guard let windows = (structured as? [String: Any])?["windows"] as? [[String: Any]] else { return nil }
        let lines = windows.compactMap { window -> String? in
            guard window["is_on_screen"] as? Bool == true, let title = window["title"] as? String, !title.isEmpty,
                  let pid = window["pid"] as? Int, let id = window["window_id"] as? Int else { return nil }
            return "pid=\(pid) window_id=\(id) app=\(window["app_name"] as? String ?? "?") title=\(title)"
        }
        return lines.isEmpty ? "No visible windows." : "Visible windows:\n" + lines.joined(separator: "\n")
    }

    private static func complete(endpoint: String, messages: [[String: Any]], tools: [[String: Any]], model: String,
                                 key: String?) async throws -> ([String: Any], Double) {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Lamp", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "messages": messages, "tools": tools, "usage": ["include": true],
        ] as [String: Any])
        // A dropped connection mid-upload is worth one more try.
        var reply: (Data, URLResponse)?
        for attempt in 0..<2 {
            do {
                reply = try await URLSession.shared.data(for: request)
                break
            } catch let error as URLError where attempt == 0 && error.code != .cancelled {
                try await Task.sleep(for: .seconds(1))
            }
        }
        guard let (data, response) = reply else { throw Failure(message: "Couldn't reach the AI.") }
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, let message = ((obj["choices"] as? [[String: Any]])?.first?["message"]) as? [String: Any] else {
            let detail = (obj["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(status)"
            throw Failure(message: Provider.friendlyError("\(status) \(detail)", from: Provider.openRouter))
        }
        var kept: [String: Any] = ["role": "assistant", "content": message["content"] as? String ?? ""]
        if let calls = message["tool_calls"] { kept["tool_calls"] = calls }
        return (kept, (obj["usage"] as? [String: Any])?["cost"] as? Double ?? 0)
    }

    // MARK: Processes

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) async -> Int32 {
        await Subprocess.run(tool, arguments, timeout: 600).status   // an install can take a while
    }

    private static func capture(_ tool: String, _ arguments: [String]) async -> String {
        await Subprocess.run(tool, arguments, mergeErrors: false, timeout: 120).output
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

    /// A question the server asks before a step (MCP elicitation): what it wants to do and in which app.
    struct Elicitation {
        let message: String
        let tool: String                    // _meta.tool_name, e.g. "click"
        let parameters: [String: Any]       // _meta.tool_params
        let display: [String: String]       // _meta.tool_params_display, by display name
        let risk: String?
    }

    /// Answers the server's elicitations: true accepts, false declines. Without one, every question is declined.
    var elicitationHandler: ((Elicitation) async -> Bool)?

    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let lock = NSLock()
    private var buffer = Data()
    private var waiting: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var nextID = 1
    /// When each request in flight gives up, pushed back while the person is being asked about a step, and
    /// again when they've answered, so the driver gets its full time after a slow dialog.
    private var deadlines: [Int: Date] = [:]
    private var asking = 0   // elicitations the handler is answering right now
    /// Rises when a request gives up or the server stops: a question asked for a request that's gone is
    /// declined when its answer comes, so a step approved late can't run after the model has moved on.
    private var generation = 0
    /// Set when the server has been stopped or has gone: requests after that fail at once.
    private var closed = false
    private static let patience: TimeInterval = 120

    init(executable: URL, arguments: [String], environment: [String: String] = [:]) throws {
        process.executableURL = executable
        process.arguments = arguments
        if !environment.isEmpty { process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 } }
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
            "protocolVersion": "2025-06-18", "capabilities": ["elicitation": [:] as [String: Any]] as [String: Any],
            "clientInfo": ["name": "Lamp", "version": BuildStamp.current.lamp ?? "0"],
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

    /// A stalled driver would otherwise leave the app's request, and the gateway connection behind it, waiting
    /// forever: after two minutes the request fails instead.
    private func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            guard !closed else {
                lock.unlock()
                continuation.resume(throwing: ComputerUse.Failure(message: "The computer-use driver has stopped; the task can't go on."))
                return
            }
            let id = nextID
            nextID += 1
            waiting[id] = continuation
            deadlines[id] = Date().addingTimeInterval(Self.patience)
            lock.unlock()
            send(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
            watch(id)
        }
    }

    /// Gives up on a request at its deadline, unless the deadline has moved (the person was being asked
    /// about a step) or the person is still being asked, in which case it looks again later.
    private func watch(_ id: Int) {
        lock.lock()
        let deadline = deadlines[id] ?? Date()
        lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + max(deadline.timeIntervalSinceNow, 0.1)) { [weak self] in
            guard let self else { return }
            lock.lock()
            guard waiting[id] != nil else { lock.unlock(); return }
            if asking > 0 { deadlines[id] = Date().addingTimeInterval(Self.patience) }
            if let moved = deadlines[id], moved > Date() {
                lock.unlock()
                watch(id)
                return
            }
            let late = waiting.removeValue(forKey: id)
            deadlines[id] = nil
            generation += 1
            lock.unlock()
            late?.resume(throwing: ComputerUse.Failure(message: "The computer-use driver didn't answer in two minutes, so it was stopped."))
            // The call may still be running in the server, and could ask about a step later, while a newer
            // call of ours is waiting: there's no telling the two apart, so the server goes with the call.
            close()
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
        var questions: [(Any, [String: Any])] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
            // A request from the server, which arrives while a call of ours is in flight: answered on its own.
            if message["method"] as? String == "elicitation/create", let id = message["id"] {
                questions.append((id, message["params"] as? [String: Any] ?? [:]))
                continue
            }
            guard let id = message["id"] as? Int, let continuation = waiting.removeValue(forKey: id) else { continue }
            if let error = message["error"] as? [String: Any] {
                replies.append((continuation, .failure(ComputerUse.Failure(message: error["message"] as? String ?? "The helper failed."))))
            } else {
                replies.append((continuation, .success(message["result"] as? [String: Any] ?? [:])))
            }
        }
        lock.unlock()
        for (continuation, result) in replies { continuation.resume(with: result) }
        for (id, params) in questions { answer(id, params) }
    }

    /// Asks the handler and replies: accept with an empty form (the server's forms have no fields), or decline.
    private func answer(_ id: Any, _ params: [String: Any]) {
        let meta = params["_meta"] as? [String: Any] ?? [:]
        var display: [String: String] = [:]
        for item in meta["tool_params_display"] as? [[String: Any]] ?? [] {
            if let name = item["display_name"] as? String ?? item["name"] as? String, let value = item["value"] { display[name] = "\(value)" }
        }
        let elicitation = Elicitation(message: params["message"] as? String ?? "", tool: meta["tool_name"] as? String ?? "",
                                      parameters: meta["tool_params"] as? [String: Any] ?? [:], display: display, risk: meta["riskLevel"] as? String)
        let handler = elicitationHandler
        lock.lock()
        // A question with no call of ours waiting is the server carrying on after a call gave up: nobody
        // is asked, and the step doesn't run.
        guard !waiting.isEmpty else {
            lock.unlock()
            send(["jsonrpc": "2.0", "id": id, "result": ["action": "decline"]])
            return
        }
        let asked = generation
        asking += 1
        lock.unlock()
        Task.detached { [weak self] in
            let answer = await handler?(elicitation) ?? false
            guard let self else { return }
            let accepted = answered(answer, askedIn: asked)
            let result: [String: Any] = accepted ? ["action": "accept", "content": [:] as [String: Any]] : ["action": "decline"]
            send(["jsonrpc": "2.0", "id": id, "result": result])
        }
    }

    /// Books the person's answer: the call this was asked for may have given up meanwhile, and then whatever
    /// they said, the step doesn't run. The requests still waiting get their full time again.
    private func answered(_ accepted: Bool, askedIn generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        asking -= 1
        for id in waiting.keys { deadlines[id] = Date().addingTimeInterval(Self.patience) }
        return accepted && generation == self.generation
    }

    private func failAll() {
        lock.lock()
        closed = true
        let pending = waiting
        waiting.removeAll()
        deadlines.removeAll()
        generation += 1
        lock.unlock()
        for continuation in pending.values {
            continuation.resume(throwing: ComputerUse.Failure(message: "The helper stopped unexpectedly."))
        }
    }
}

/// Lists and switches browser tabs through the browsers' own AppleScript support. Browsers don't expose their
/// tab strips to Accessibility, so this is how a page that's open but not in front gets read. Switching a tab
/// changes nothing on the page, so it's allowed even when an app only asked to look. macOS asks the person
/// once per browser before Lamp may do this.
enum BrowserTabs {
    /// Chromium browsers share Chrome's scripting terms; Safari has its own.
    private static let chromium = ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
                                   "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser",
                                   "org.chromium.Chromium", "com.vivaldi.Vivaldi", "net.imput.helium"]
    private static let safari = "com.apple.Safari"

    static let tools: [[String: Any]] = [
        ["type": "function", "function": [
            "name": "list_browser_tabs",
            "description": "Lists every open tab in the running web browsers (Chrome, Safari, Arc, Brave, Edge…): browser, window number, tab number, whether it's the active tab, title and URL.",
            "parameters": ["type": "object", "properties": [:] as [String: Any]],
        ] as [String: Any]],
        ["type": "function", "function": [
            "name": "show_browser_tab",
            "description": "Makes a tab the active tab of its window and brings that window to the front of its browser, so get_window_state can read it. Use the browser, window and tab numbers from list_browser_tabs.",
            "parameters": ["type": "object", "required": ["browser", "window", "tab"], "properties": [
                "browser": ["type": "string", "description": "The browser's name as list_browser_tabs gave it"],
                "window": ["type": "integer"],
                "tab": ["type": "integer"],
            ] as [String: Any]],
        ] as [String: Any]],
    ]

    static func handles(_ tool: String) -> Bool { tool == "list_browser_tabs" || tool == "show_browser_tab" }

    private static var running: [(name: String, id: String)] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let id = app.bundleIdentifier, id == safari || chromium.contains(id) else { return nil }
            return (app.localizedName ?? id, id)
        }
    }

    static func call(_ tool: String, _ arguments: [String: Any]) async -> String {
        let browsers = running
        guard !browsers.isEmpty else { return "No supported web browser is running." }
        if tool == "list_browser_tabs" {
            var lines: [String] = []
            for browser in browsers {
                let output = await osascript(listScript(browser.id))
                if output.hasPrefix("error:") {
                    lines.append("\(browser.name): couldn't list tabs (\(String(output.dropFirst(6)).trimmed)). The person may need to allow Lamp to control \(browser.name).")
                    continue
                }
                for row in output.split(separator: "\n") {
                    let fields = row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                    guard fields.count >= 5 else { continue }
                    lines.append("browser=\(browser.name) window=\(fields[0]) tab=\(fields[1])\(fields[2] == "true" ? " (active)" : "") title=\(fields[3]) url=\(fields[4])")
                }
            }
            return lines.isEmpty ? "No tabs are open." : lines.joined(separator: "\n")
        }
        guard let name = arguments["browser"] as? String,
              let browser = browsers.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }),
              let window = arguments["window"] as? Int, let tab = arguments["tab"] as? Int else {
            return "Give browser, window and tab from list_browser_tabs."
        }
        let output = await osascript(showScript(browser.id, window: window, tab: tab))
        return output.hasPrefix("error:") ? "Couldn't switch tabs: \(String(output.dropFirst(6)).trimmed)" : "Showing that tab."
    }

    private static func listScript(_ id: String) -> String {
        let tabs = id == safari ? "(index of current tab of window w) is t" : "(active tab index of window w) is t"
        let title = id == safari ? "name" : "title"
        return """
        set out to ""
        tell application id "\(id)"
          repeat with w from 1 to count of windows
            repeat with t from 1 to count of tabs of window w
              set out to out & w & (character id 9) & t & (character id 9) & (\(tabs)) & (character id 9) & \
                (\(title) of tab t of window w) & (character id 9) & (URL of tab t of window w) & linefeed
            end repeat
          end repeat
        end tell
        return out
        """
    }

    private static func showScript(_ id: String, window: Int, tab: Int) -> String {
        let select = id == safari ? "set current tab of window \(window) to tab \(tab) of window \(window)"
                                  : "set active tab index of window \(window) to \(tab)"
        return """
        tell application id "\(id)"
          \(select)
          set index of window \(window) to 1
        end tell
        """
    }

    /// Runs AppleScript in osascript; errors come back as "error: …".
    private static func osascript(_ script: String) async -> String {
        let result = await Subprocess.run("/usr/bin/osascript", ["-e", script], mergeErrors: false, timeout: 120)
        return result.ok ? result.output : "error: " + (result.timedOut ? "the script took too long" : result.errors)
    }
}
