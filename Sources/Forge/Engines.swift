import Foundation

/// Which coding agent builds apps.
enum Engine: String, CaseIterable, Identifiable {
    case pi, claude, codex, opencode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pi: "Forge's built-in agent"
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .opencode: "opencode"
        }
    }

    /// The command-line tool an external engine needs (nil for the bundled pi).
    var tool: String? {
        switch self {
        case .pi: nil
        case .claude: "claude"
        case .codex: "codex"
        case .opencode: "opencode"
        }
    }
}

/// When the agent needs the user's go-ahead to run a shell command (Settings → Building).
enum CommandApproval: String, CaseIterable, Identifiable {
    case auto, always, never

    var id: String { rawValue }

    static var current: CommandApproval {
        get { CommandApproval(rawValue: UserDefaults.standard.string(forKey: "commandApproval") ?? "") ?? .auto }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "commandApproval") }
    }

    /// Claude Code's auto mode turned out to be unavailable for this account; use "always" instead.
    static var claudeAutoUnavailable: Bool {
        get { UserDefaults.standard.bool(forKey: "claudeAutoUnavailable") }
        set { UserDefaults.standard.set(newValue, forKey: "claudeAutoUnavailable") }
    }

    var title: String {
        switch self {
        case .auto: "Only when needed"
        case .always: "Always"
        case .never: "Never"
        }
    }

    var detail: String {
        switch self {
        case .auto: "Routine commands run on their own; Forge asks about anything risky or unexpected. Claude Code uses its safety classifier; other agents use the decision model."
        case .always: "Forge asks before every command."
        case .never: "Commands run without asking. They still show in the chat."
        }
    }
}

/// The user's builder choice (Settings → AI). Stored in UserDefaults.
enum Builder {
    /// pi providers that aren't API keys.
    static let localProvider = "forge-local"
    static let myPiProvider = "my-pi"

    static var engine: Engine {
        get { Engine(rawValue: UserDefaults.standard.string(forKey: "engine") ?? "") ?? .pi }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "engine") }
    }

    static var piProvider: String {
        get { UserDefaults.standard.string(forKey: "piProvider") ?? "openrouter" }
        set { UserDefaults.standard.set(newValue, forKey: "piProvider") }
    }

    /// The model for the current pi provider; each provider remembers its own.
    static var piModel: String {
        get {
            if let saved = UserDefaults.standard.string(forKey: "piModel.\(piProvider)"), !saved.isEmpty { return saved }
            if piProvider == "openrouter" {   // from before the provider picker
                let old = UserDefaults.standard.string(forKey: "model") ?? ""
                return old.contains("/") ? old : Provider.models[0].id
            }
            if piProvider == localProvider { return LocalModels.installedIDs().first ?? "" }
            return ""
        }
        set { UserDefaults.standard.set(newValue, forKey: "piModel.\(piProvider)") }
    }

    /// Whether the current choice can build right now, and if not, why.
    static func problem() -> String? {
        switch engine {
        case .pi:
            if Agent.executable == nil { return "Forge's AI builder is missing from the app. Download Forge again." }
            switch piProvider {
            case localProvider:
                let installed = LocalModels.scan()
                if installed.isEmpty { return "Download a model in Settings → Providers → Native Mac AI." }
                if let model = installed.first(where: { $0.id == piModel }), model.format == .mlx, LocalModels.mlxServerPath == nil {
                    return "\(model.name) is an MLX model and needs mlx-lm: run `uv tool install mlx-lm`."
                }
            case myPiProvider:
                if !FileManager.default.fileExists(atPath: Agent.userConfigDir) { return "No pi setup found in ~/.pi/agent." }
            case let id where id.hasPrefix("ext-"):
                break   // a detected Ollama / LM Studio server
            default:
                if KeyStore.key(for: piProvider) == nil {
                    return "Add your \(Provider.apiProvider(piProvider)?.name ?? piProvider) key."
                }
            }
            if piModel.isEmpty { return "Choose a model." }
        default:
            if ToolLocator.path(for: engine) == nil { return "\(engine.title) isn't installed on this Mac." }
        }
        return nil
    }

    static var summary: String {
        switch engine {
        case .pi:
            let provider: String = switch piProvider {
            case localProvider: "Native Mac AI"
            case myPiProvider: "your pi setup"
            case let id where id.hasPrefix("ext-"): LocalModels.externalName(id)
            default: Provider.apiProvider(piProvider)?.name ?? piProvider
            }
            return "\(piModel.isEmpty ? "No model" : piModel) via \(provider)"
        default:
            return engine.title
        }
    }
}

/// Finds command-line tools the way the user's own Terminal would. GUI apps don't get the shell's
/// PATH, and tools installed with nvm, mise, Homebrew or npm live in places only that PATH knows.
enum ToolLocator {
    nonisolated(unsafe) private static var resolvedPath: String?
    private static let lock = NSLock()

    /// The user's interactive-shell PATH (resolved once, with a timeout), plus common locations.
    static var userPath: String {
        lock.lock()
        defer { lock.unlock() }
        if let resolvedPath { return resolvedPath }
        let home = NSHomeDirectory()
        var parts: [String] = []
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-ilc", "printf '%s' \"$PATH\""]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        if (try? process.run()) != nil {
            let deadline = Date().addingTimeInterval(5)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
            if process.isRunning { process.terminate() }
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            parts = output.split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        }
        parts += ["\(home)/.local/bin", "\(home)/.opencode/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        var seen = Set<String>()
        let path = parts.filter { seen.insert($0).inserted }.joined(separator: ":")
        resolvedPath = path
        return path
    }

    static func path(for engine: Engine) -> String? {
        engine.tool.flatMap(path(named:))
    }

    static func path(named tool: String) -> String? {
        for dir in userPath.split(separator: ":") {
            let candidate = "\(dir)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}

/// One agent turn: the shell command and its environment.
struct AgentRun {
    let command: String
    let env: [String: String]
}

extension Agent {
    /// The user's own pi config (logins, subscriptions, settings).
    static let userConfigDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pi/agent").path

    /// Builds the command for one turn with the chosen engine. `files` are attachment paths
    /// relative to the app folder; `session` is the engine's saved conversation id, if any.
    static func run(prompt: String, files: [String], project: ForgeProject, session: String?) -> AgentRun {
        var env: [String: String] = ["FORGE_PROMPT": prompt, "FORGE_SYSTEM": systemPrompt, "FORGE_DIR": project.dir.path,
                                     "PATH": ToolLocator.userPath]
        for (index, file) in files.enumerated() { env["FORGE_FILE_\(index)"] = file }
        let fileArgs = (0..<files.count).map { "\"$FORGE_FILE_\($0)\"" }
        if let session { env["FORGE_SESSION"] = session }

        switch Builder.engine {
        case .pi:
            env["FORGE_LOOK_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/look"
            env["FORGE_VERSIONS_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/versions"
            env["FORGE_APPROVE_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/approve"
            env["FORGE_TOKEN"] = Template.token(for: project)
            return AgentRun(command: command(fileCount: files.count),
                            env: env.merging(environment(prompt: prompt, files: files, session: session ?? "",
                                                         sessionDir: project.dir.appendingPathComponent(".forge/pi-sessions").path)) { $1 })
        case .claude:
            // Forge builds the app itself. Attachments are listed in the prompt; Claude reads them.
            // Isolated from the user's own Claude Code setup: --restricted ignores their settings files (hooks,
            // permission rules, plugins) while keeping their sign-in and Forge's --settings; --strict-mcp-config
            // skips their MCP servers and --disable-slash-commands their skills. --tools then lists exactly
            // what the agent gets.
            // Shell commands go through a PreToolUse hook that asks Forge and waits for the user's answer; Forge
            // replies in Claude Code's hook format. If Forge can't be reached the hook fails and the command is denied.
            env["FORGE_TOKEN"] = Template.token(for: project)
            // How commands are approved (Settings → Building):
            // - auto: Claude Code's own classifier (--permission-mode auto) runs routine commands; when it would
            //   ask, its PermissionRequest hook sends the request to Forge's approval card.
            // - always: a PreToolUse hook sends every shell command to Forge first.
            // - never: the shell is allowed outright.
            // Hooks call Forge's gateway and wait for the user; if Forge can't be reached the hook fails and the
            // command is denied.
            var approval = CommandApproval.current
            if approval == .auto && CommandApproval.claudeAutoUnavailable { approval = .always }
            let hook = #"{"type":"command","timeout":3600,"command":"curl -sf --max-time 3600 -X POST -H \"Authorization: Bearer $FORGE_TOKEN\" -H 'Content-Type: application/json' --data-binary @- \"$FORGE_APPROVE_URL\""}"#
            var permissionMode = "acceptEdits"
            var allowed = "Read,Edit,Write,Glob,Grep,WebFetch,WebSearch"
            switch approval {
            case .auto:
                permissionMode = "auto"
                env["FORGE_APPROVE_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/approve?format=claude-permission"
                env["FORGE_CLAUDE_SETTINGS"] = #"{"hooks":{"PermissionRequest":[{"matcher":"*","hooks":["# + hook + "]}]}}"
            case .always:
                env["FORGE_APPROVE_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/approve?format=claude"
                env["FORGE_CLAUDE_SETTINGS"] = #"{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":["# + hook + "]}]}}"
            case .never:
                allowed += ",Bash"
                env["FORGE_CLAUDE_SETTINGS"] = "{}"
            }
            env["FORGE_CLAUDE_MODE"] = permissionMode
            env["FORGE_CLAUDE_ALLOWED"] = allowed
            env["FORGE_TOOL"] = ToolLocator.path(for: .claude) ?? "claude"
            var command = """
            "$FORGE_TOOL" -p "$FORGE_PROMPT" --output-format stream-json --verbose \\
              --restricted --strict-mcp-config --disable-slash-commands \\
              --tools 'Read,Edit,Write,Glob,Grep,Bash,WebFetch,WebSearch' \\
              --permission-mode "$FORGE_CLAUDE_MODE" --allowedTools "$FORGE_CLAUDE_ALLOWED" \\
              --settings "$FORGE_CLAUDE_SETTINGS" \\
              --append-system-prompt "$FORGE_SYSTEM"
            """
            if session != nil { command += " --resume \"$FORGE_SESSION\"" }
            return AgentRun(command: command, env: env)
        case .codex:
            // Codex has no system-prompt flag, so Forge's rules go in front of each request.
            env["FORGE_TOOL"] = ToolLocator.path(for: .codex) ?? "codex"
            env["FORGE_PROMPT"] = "Instructions from Forge (follow these):\n\(systemPrompt)\n\nRequest:\n\(prompt)"
            let images = files.enumerated().filter { Attachments.isImage(URL(fileURLWithPath: $0.element)) }
                .map { "-i \"$FORGE_FILE_\($0.offset)\"" }.joined(separator: " ")
            return AgentRun(command: """
            "$FORGE_TOOL" exec --json -C "$FORGE_DIR" --sandbox workspace-write --skip-git-repo-check \(images) -- "$FORGE_PROMPT"
            """, env: env)
        case .opencode:
            env["FORGE_TOOL"] = ToolLocator.path(for: .opencode) ?? "opencode"
            env["FORGE_PROMPT"] = "Instructions from Forge (follow these):\n\(systemPrompt)\n\nRequest:\n\(prompt)"
            // Edits allowed, shell and web off: Forge does the building.
            // opencode has no way to ask for approval when run like this, so its shell is on only when the user
            // chose to never be asked. Reading the web is allowed.
            env["OPENCODE_CONFIG_CONTENT"] = CommandApproval.current == .never
                ? #"{"permission":{"edit":"allow","bash":"allow","webfetch":"allow"}}"#
                : #"{"permission":{"edit":"allow","bash":"deny","webfetch":"allow"}}"#
            var command = "\"$FORGE_TOOL\" run --format json --dir \"$FORGE_DIR\""
            if session != nil { command += " -s \"$FORGE_SESSION\"" }
            command += " \"$FORGE_PROMPT\""
            if !fileArgs.isEmpty { command += " " + fileArgs.map { "-f \($0)" }.joined(separator: " ") }
            return AgentRun(command: command, env: env)
        }
    }

    /// Parses one output line from the current engine.
    static func parseLine(_ line: String) -> [AgentEvent] {
        switch Builder.engine {
        case .pi: parse(line)
        case .claude: parseClaude(line)
        case .codex: parseCodex(line)
        case .opencode: parseOpencode(line)
        }
    }

    private static func json(_ line: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
    }

    private static func tool(_ name: String, _ input: [String: Any]) -> String {
        if let path = input["file_path"] as? String ?? input["filePath"] as? String ?? input["path"] as? String {
            return "\(name) \((path as NSString).lastPathComponent)"
        }
        if let pattern = input["pattern"] as? String { return "\(name) \(pattern)" }
        if let command = input["command"] as? String { return "\(name): \(command)" }
        return name
    }

    static func parseClaude(_ line: String) -> [AgentEvent] {
        guard let obj = json(line), let type = obj["type"] as? String else { return line.trimmed.isEmpty ? [] : [.raw(line)] }
        switch type {
        case "system":
            if obj["subtype"] as? String == "init", let id = obj["session_id"] as? String { return [.session(id)] }
        case "assistant":
            let content = (obj["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            return content.compactMap { block in
                switch block["type"] as? String {
                case "text": (block["text"] as? String)?.trimmed.nilIfEmpty.map(AgentEvent.text)
                case "tool_use":
                    .tool(tool(block["name"] as? String ?? "Tool", block["input"] as? [String: Any] ?? [:]),
                          call: callKey(block["name"] as? String ?? "Tool", block["input"] as? [String: Any] ?? [:]))
                default: nil
                }
            }
        case "result":
            var events: [AgentEvent] = []
            if let cost = obj["total_cost_usd"] as? Double, cost > 0 { events.append(.cost(cost)) }
            if obj["is_error"] as? Bool == true { events.append(.failed(obj["result"] as? String ?? "Claude Code failed.")) }
            return events
        default: break
        }
        return []
    }

    static func parseCodex(_ line: String) -> [AgentEvent] {
        guard let obj = json(line), let type = obj["type"] as? String else { return line.trimmed.isEmpty ? [] : [.raw(line)] }
        let item = obj["item"] as? [String: Any] ?? [:]
        switch (type, item["type"] as? String) {
        case ("thread.started", _):
            return (obj["thread_id"] as? String).map { [.session($0)] } ?? []
        case ("item.completed", "agent_message"):
            return (item["text"] as? String)?.trimmed.nilIfEmpty.map { [.text($0)] } ?? []
        case ("item.started", "command_execution"):
            let command = "Run: \(item["command"] as? String ?? "")"
            return [.tool(command, call: command)]
        case ("item.completed", "file_change"):
            let paths = (item["changes"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String }
            // Codex doesn't say what an edit changed, so two edits to one file can't be told apart:
            // each counts as its own step.
            return [.tool("Edit \(paths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "))",
                          call: item["id"] as? String ?? UUID().uuidString)]
        case ("error", _), ("turn.failed", _):
            let raw = obj["message"] as? String ?? ((obj["error"] as? [String: Any])?["message"] as? String) ?? "Codex failed."
            // Codex nests the API error as JSON text; surface its message.
            let nested = json(raw).flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
            return [.failed(nested ?? raw)]
        default:
            return []
        }
    }

    static func parseOpencode(_ line: String) -> [AgentEvent] {
        guard let obj = json(line), let type = obj["type"] as? String else { return line.trimmed.isEmpty ? [] : [.raw(line)] }
        var events: [AgentEvent] = []
        if let id = obj["sessionID"] as? String { events.append(.session(id)) }
        let part = obj["part"] as? [String: Any] ?? [:]
        switch type {
        case "text":
            if let text = (part["text"] as? String)?.trimmed.nilIfEmpty { events.append(.text(text)) }
        case "tool_use":
            let state = part["state"] as? [String: Any] ?? [:]
            events.append(.tool(tool(part["tool"] as? String ?? "tool", state["input"] as? [String: Any] ?? [:]),
                                call: callKey(part["tool"] as? String ?? "tool", state["input"] as? [String: Any] ?? [:])))
        case "step_finish":
            if let cost = part["cost"] as? Double, cost > 0 { events.append(.cost(cost)) }
        case "error":
            let error = obj["error"] as? [String: Any] ?? [:]
            let message = (error["data"] as? [String: Any])?["message"] as? String ?? error["name"] as? String
            events.append(.failed(message ?? "opencode failed."))
        default:
            break
        }
        return events
    }
}
