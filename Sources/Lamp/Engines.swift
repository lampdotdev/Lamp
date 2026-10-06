import Foundation

/// Which coding agent builds apps.
enum Engine: String, CaseIterable, Identifiable {
    case pi, claude, codex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pi: "Lamp's built-in agent"
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    /// The command-line tool an external engine needs (nil for the bundled pi).
    var tool: String? {
        switch self {
        case .pi: nil
        case .claude: "claude"
        case .codex: "codex"
        }
    }
}

/// When the agent needs the user's go-ahead to run a shell command (Settings → Building).
enum CommandApproval: String, CaseIterable, Identifiable {
    /// risky: routine commands run, and so does anything the in-app model rates low risk; the card is for
    /// medium and high. unusual: the same, but low-risk ones wait for the person too (the older "auto").
    case risky, unusual, always, never

    var id: String { rawValue }

    static var current: CommandApproval {
        get {
            let saved = UserDefaults.standard.string(forKey: "commandApproval") ?? ""
            return CommandApproval(rawValue: saved) ?? .risky   // "auto", from before "risky" existed, lands here too
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "commandApproval") }
    }

    /// The modes where a classifier or model decides, as opposed to the person every time or never.
    var isAutomatic: Bool { self == .risky || self == .unusual }

    /// Claude Code's auto mode turned out to be unavailable for this account; use "always" instead.
    static var claudeAutoUnavailable: Bool {
        get { UserDefaults.standard.bool(forKey: "claudeAutoUnavailable") }
        set { UserDefaults.standard.set(newValue, forKey: "claudeAutoUnavailable") }
    }

    var title: String {
        switch self {
        case .risky: "Only when risky"
        case .unusual: "Anything unusual"
        case .always: "Always"
        case .never: "Never"
        }
    }

    var detail: String {
        switch self {
        case .risky: "Routine commands run on their own, and so does anything the in-app model rates low risk. Lamp asks about the rest."
        case .unusual: "Routine commands run on their own; Lamp asks about anything else, including the low-risk ones. Claude Code uses its safety classifier; other agents use the decision model."
        case .always: "Lamp asks before every command."
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

    /// The model Claude Code or Codex builds with; "" leaves it to the tool's own default (for Claude Code,
    /// the account's default, since Lamp runs it without the person's settings). Claude Code starts on
    /// Opus, like Lamp's other builders.
    static func engineModel(_ engine: Engine) -> String {
        UserDefaults.standard.string(forKey: "engineModel.\(engine.rawValue)") ?? (engine == .claude ? "opus" : "")
    }

    static func setEngineModel(_ model: String, for engine: Engine) {
        UserDefaults.standard.set(model.trimmed, forKey: "engineModel.\(engine.rawValue)")
    }

    /// Claude Code's choices: its own short names, and the full ID for models without one.
    static let claudeModels: [(id: String, label: String)] = [
        ("", "Claude Code's default"),
        ("claude-fable-5-1", "Fable"),
        ("opus", "Opus"),
        ("sonnet", "Sonnet"),
        ("haiku", "Haiku"),
    ]

    /// Codex's choices: the models its account can use, from the list Codex itself caches
    /// (~/.codex/models_cache.json), best first. Just the default when the cache isn't there.
    static var codexModels: [(id: String, label: String)] {
        [("", "Codex's default")] + codexCatalog.map { ($0.slug, $0.name) }
    }

    /// Codex's small, fast model, for quick judgments: the "Luna" line.
    static var codexFastModel: String? { codexCatalog.first { $0.slug.contains("luna") }?.slug }

    private static var codexCatalog: [(slug: String, name: String)] {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/models_cache.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return [] }
        return models
            .filter { $0["visibility"] as? String == "list" }
            .sorted { ($0["priority"] as? Int ?? 99) < ($1["priority"] as? Int ?? 99) }
            .compactMap { model in
                guard let slug = model["slug"] as? String else { return nil }
                return (slug, model["display_name"] as? String ?? slug)
            }
    }

    /// The model for the current pi provider; each provider remembers its own.
    static var piModel: String {
        get {
            if let saved = UserDefaults.standard.string(forKey: "piModel.\(piProvider)"), !saved.isEmpty { return saved }
            if piProvider == "openrouter" {   // from before the provider picker
                let old = UserDefaults.standard.string(forKey: "model") ?? ""
                return old.contains("/") ? old : Provider.defaultModel
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
            if Agent.executable == nil { return "Lamp's AI builder is missing from the app. Download Lamp again." }
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
            let model = engineModel(engine)
            guard !model.isEmpty else { return engine.title }
            let names = engine == .claude ? claudeModels : codexModels
            return "\(engine.title), \(names.first { $0.id == model }?.label ?? model)"
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
        parts += ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        var seen = Set<String>()
        let path = parts.filter { seen.insert($0).inserted }.joined(separator: ":")
        resolvedPath = path
        return path
    }

    static func path(for engine: Engine) -> String? {
        engine.tool.flatMap(path(named:))
    }

    nonisolated(unsafe) private static var chosen: [String: String] = [:]

    /// The tool's path. When several copies are installed (say, one from npm under nvm and one under mise),
    /// the newest version wins rather than whichever comes first in PATH.
    static func path(named tool: String) -> String? {
        lock.lock()
        // The Claude app replaces its bundled copy when it updates, so a remembered path can disappear.
        if let cached = chosen[tool], FileManager.default.isExecutableFile(atPath: cached) { lock.unlock(); return cached }
        lock.unlock()
        var seen = Set<String>()
        let candidates = (userPath.split(separator: ":").map { "\($0)/\(tool)" } + desktopCopies(of: tool)).filter {
            FileManager.default.isExecutableFile(atPath: $0)
                && seen.insert(URL(fileURLWithPath: $0).resolvingSymlinksInPath().path).inserted
        }
        guard let first = candidates.first else { return nil }
        var best = first
        if candidates.count > 1 {
            best = candidates.max { version(of: $0).lexicographicallyPrecedes(version(of: $1)) } ?? first
        }
        lock.lock()
        chosen[tool] = best
        lock.unlock()
        return best
    }

    /// Copies bundled with the desktop apps, so someone with only the Claude or ChatGPT app can build with
    /// them: the Claude app keeps Claude Code in its support folder (one folder per version), and the
    /// ChatGPT app ships Codex inside its bundle.
    static func desktopCopies(of tool: String) -> [String] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        switch tool {
        case "claude":
            let root = home + "/Library/Application Support/Claude/claude-code"
            return ((try? fm.contentsOfDirectory(atPath: root)) ?? []).flatMap { version in
                ((try? fm.contentsOfDirectory(atPath: "\(root)/\(version)")) ?? []).map {
                    "\(root)/\(version)/\($0)/claude.app/Contents/MacOS/claude"
                }
            }
        case "codex":
            return ["/Applications/ChatGPT.app", home + "/Applications/ChatGPT.app"]
                .map { $0 + "/Contents/Resources/codex-cli/bin/codex" }
        default:
            return []
        }
    }

    /// Which desktop app a tool came with, for Settings: "the Claude app", or nil for a command-line install.
    static func desktopApp(for path: String) -> String? {
        if path.contains("/Application Support/Claude/claude-code/") { return "the Claude app" }
        if path.contains("/ChatGPT.app/") { return "the ChatGPT app" }
        return nil
    }

    /// The numbers in `<tool> --version` (e.g. "codex-cli 0.160.0" → [0, 160, 0]); [] if it can't tell.
    private static func version(of path: String) -> [Int] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = userPath
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate(); return [] }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard let match = output.firstMatch(of: #/(\d+)\.(\d+)(?:\.(\d+))?/#) else { return [] }
        return [Int(match.1) ?? 0, Int(match.2) ?? 0, Int(match.3 ?? "0") ?? 0]
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
    static func run(prompt: String, files: [String], project: LampProject, session: String?) -> AgentRun {
        var env: [String: String] = ["LAMP_PROMPT": prompt, "LAMP_SYSTEM": systemPrompt, "LAMP_DIR": project.dir.path,
                                     "PATH": ToolLocator.userPath]
        for (index, file) in files.enumerated() { env["LAMP_FILE_\(index)"] = file }
        let fileArgs = (0..<files.count).map { "\"$LAMP_FILE_\($0)\"" }
        if let session { env["LAMP_SESSION"] = session }

        switch Builder.engine {
        case .pi:
            env["LAMP_LOOK_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/look"
            env["LAMP_USE_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/use"
            env["LAMP_VERSIONS_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/versions"
            env["LAMP_APPROVE_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/approve"
            env["LAMP_TOKEN"] = Template.token(for: project)
            return AgentRun(command: command(fileCount: files.count),
                            env: env.merging(environment(prompt: prompt, files: files, session: session ?? "",
                                                         sessionDir: project.dir.appendingPathComponent(".lamp/pi-sessions").path)) { $1 })
        case .claude:
            // Lamp builds the app itself. Attachments are listed in the prompt; Claude reads them.
            // Isolated from the user's own Claude Code setup: --restricted ignores their settings files (hooks,
            // permission rules, plugins) while keeping their sign-in and Lamp's --settings; --strict-mcp-config
            // skips their MCP servers and --disable-slash-commands their skills. --tools then lists exactly
            // what the agent gets.
            // Shell commands go through a PreToolUse hook that asks Lamp and waits for the user's answer; Lamp
            // replies in Claude Code's hook format. If Lamp can't be reached the hook fails and the command is denied.
            env["LAMP_TOKEN"] = Template.token(for: project)
            env["LAMP_SYSTEM"] = systemPrompt + tryRules
            // How commands are approved (Settings → Building):
            // - auto: Claude Code's own classifier (--permission-mode auto) runs routine commands; when it would
            //   ask, its PermissionRequest hook sends the request to Lamp's approval card.
            // - always: a PreToolUse hook sends every shell command to Lamp first.
            // - never: the shell is allowed outright.
            // Hooks call Lamp's gateway and wait for the user; if Lamp can't be reached the hook fails and the
            // command is denied.
            var approval = CommandApproval.current
            if approval.isAutomatic && CommandApproval.claudeAutoUnavailable { approval = .always }
            let hook = #"{"type":"command","timeout":3600,"command":"curl -sf --max-time 3600 -X POST -H \"Authorization: Bearer $LAMP_TOKEN\" -H 'Content-Type: application/json' --data-binary @- \"$LAMP_APPROVE_URL\""}"#
            var permissionMode = "acceptEdits"
            var allowed = "Read,Edit,Write,Glob,Grep,WebFetch,WebSearch,mcp__lamp__look_at_app,mcp__lamp__use_app"
            // look_at_app and use_app come from Lamp's own MCP endpoint (Store.mcp); --strict-mcp-config keeps
            // it the only server.
            // A look can build the app, and a use_app batch can wait a minute or more: well past the engines'
            // default tool timeouts (pi's extension allows ten minutes).
            env["MCP_TOOL_TIMEOUT"] = "600000"
            env["LAMP_CLAUDE_MCP"] = #"{"mcpServers":{"lamp":{"type":"http","url":"http://127.0.0.1:"# + "\(Gateway.port)" +
                #"/mcp","headers":{"Authorization":"Bearer "# + Template.token(for: project) + #""}}}}"#
            switch approval {
            case .risky, .unusual:
                permissionMode = "auto"
                env["LAMP_APPROVE_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/approve?format=claude-permission"
                env["LAMP_CLAUDE_SETTINGS"] = #"{"hooks":{"PermissionRequest":[{"matcher":"*","hooks":["# + hook + "]}]}}"
            case .always:
                env["LAMP_APPROVE_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/approve?format=claude"
                env["LAMP_CLAUDE_SETTINGS"] = #"{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":["# + hook + "]}]}}"
            case .never:
                allowed += ",Bash"
                env["LAMP_CLAUDE_SETTINGS"] = "{}"
            }
            env["LAMP_CLAUDE_MODE"] = permissionMode
            env["LAMP_CLAUDE_ALLOWED"] = allowed
            env["LAMP_TOOL"] = ToolLocator.path(for: .claude) ?? "claude"
            var command = """
            "$LAMP_TOOL" -p "$LAMP_PROMPT" --output-format stream-json --verbose --include-partial-messages \\
              --restricted --strict-mcp-config --mcp-config "$LAMP_CLAUDE_MCP" --disable-slash-commands \\
              --tools 'Read,Edit,Write,Glob,Grep,Bash,WebFetch,WebSearch' \\
              --permission-mode "$LAMP_CLAUDE_MODE" --allowedTools "$LAMP_CLAUDE_ALLOWED" \\
              --settings "$LAMP_CLAUDE_SETTINGS" \\
              --append-system-prompt "$LAMP_SYSTEM"
            """
            if session != nil { command += " --resume \"$LAMP_SESSION\"" }
            let model = Builder.engineModel(.claude)
            if !model.isEmpty {
                env["LAMP_MODEL"] = model
                command += " --model \"$LAMP_MODEL\""
            }
            return AgentRun(command: command, env: env)
        case .codex:
            // Isolated from the user's own Codex setup (--ignore-user-config --ignore-rules: their model, MCP
            // servers, features and rules), keeping their sign-in. Lamp's rules go in as developer instructions.
            env["LAMP_TOOL"] = ToolLocator.path(for: .codex) ?? "codex"
            env["LAMP_CODEX_INSTRUCTIONS"] = "developer_instructions=" + Self.tomlString(systemPrompt + tryRules + Self.codexNote)
            // Approvals (Settings → Building): a PreToolUse hook sends each shell command to Lamp before it runs.
            // Lamp lets known read-only commands through (Codex reads with its shell), and otherwise applies the
            // setting: the decision model then the user (auto), the user (always). "Never" has no hook. In every
            // mode Codex stays in its sandbox (writes only in the app's folder), with network access.
            let approval = CommandApproval.current
            env["LAMP_TOKEN"] = Template.token(for: project)
            env["LAMP_APPROVE_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/approve?format=codex"
            let hook = Bundle.main.resourceURL?.appendingPathComponent("lamp-approve.sh").path ?? "lamp-approve.sh"
            env["LAMP_CODEX_HOOKS"] = approval == .never ? "hooks={}"
                : #"hooks.PreToolUse=[{matcher="^Bash$",hooks=[{type="command",timeout=3600,command="'"# + hook + #"'"}]}]"#
            let codexModel = Builder.engineModel(.codex)
            if !codexModel.isEmpty { env["LAMP_MODEL"] = codexModel }
            let options = (codexModel.isEmpty ? "" : "-m \"$LAMP_MODEL\" ") + """
            --json --ignore-user-config --ignore-rules --dangerously-bypass-hook-trust --skip-git-repo-check \\
              -c sandbox_mode="workspace-write" -c sandbox_workspace_write.network_access=true \\
              -c web_search="live" -c "$LAMP_CODEX_INSTRUCTIONS" -c "$LAMP_CODEX_HOOKS" \\
              -c mcp_servers.lamp.url="http://127.0.0.1:\(Gateway.port)/mcp" -c mcp_servers.lamp.bearer_token_env_var="LAMP_TOKEN" \\
              -c mcp_servers.lamp.tool_timeout_sec=600 -c mcp_servers.lamp.default_tools_approval_mode="approve"
            """
            if session != nil {
                // `exec resume` keeps the conversation; it takes no -C/-i (Lamp already runs in the app's folder).
                return AgentRun(command: "\"$LAMP_TOOL\" exec resume \(options) \"$LAMP_SESSION\" -- \"$LAMP_PROMPT\"", env: env)
            }
            let images = files.enumerated().filter { Attachments.isImage(URL(fileURLWithPath: $0.element)) }
                .map { "-i \"$LAMP_FILE_\($0.offset)\"" }.joined(separator: " ")
            return AgentRun(command: "\"$LAMP_TOOL\" exec \(options) -C \"$LAMP_DIR\" \(images) -- \"$LAMP_PROMPT\"", env: env)
        }
    }

    /// Codex reads and searches with its shell (it has no separate file tools), which is fine inside the sandbox.
    static let codexNote = """

    - (Codex) Your shell is how you read and search files; reading inside the app's folder needs no approval. \
    The "never use the shell to read files" rule above is for agents with separate file tools.
    """

    /// A TOML basic string, for `codex -c key=value`.
    static func tomlString(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F { out += String(format: "\\u%04X", scalar.value) }
                else { out.unicodeScalars.append(scalar) }
            }
        }
        return out + "\""
    }

    /// Parses one output line from the current engine.
    static func parseLine(_ line: String) -> [AgentEvent] { parse(line, engine: Builder.engine) }

    static func parse(_ line: String, engine: Engine) -> [AgentEvent] {
        switch engine {
        case .pi: parse(line)
        case .claude: parseClaude(line)
        case .codex: parseCodex(line)
        }
    }

    private static func json(_ line: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
    }

    private static func tool(_ name: String, _ input: [String: Any]) -> String {
        let name = name.replacingOccurrences(of: "mcp__lamp__", with: "")
        if let path = input["file_path"] as? String ?? input["filePath"] as? String ?? input["path"] as? String {
            return "\(name) \((path as NSString).lastPathComponent)"
        }
        if let pattern = input["pattern"] as? String { return "\(name) \(pattern)" }
        if let command = input["command"] as? String { return "\(name): \(command)" }
        if let actions = input["actions"] as? [[String: Any]] { return "\(name) \(Agent.summary(of: actions))" }
        return name
    }

    /// Claude Code calls Lamp's MCP tools `mcp__lamp__look_at_app`; Lamp knows them by their plain names.
    private static func plainName(_ tool: String) -> String { tool.replacingOccurrences(of: "mcp__lamp__", with: "") }

    static func parseClaude(_ line: String) -> [AgentEvent] {
        // Many streamed lines are pieces of thinking, which Lamp has no use for. Skip them before parsing:
        // there can be thousands per turn, all handled on the main thread.
        if line.hasPrefix(#"{"type":"stream_event""#), line.contains(#""type":"content_block_delta""#),
           !line.contains("input_json_delta"), !line.contains(#""type":"text_delta""#) { return [] }
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
                          call: callKey(plainName(block["name"] as? String ?? "Tool"), block["input"] as? [String: Any] ?? [:]))
                default: nil
                }
            }
        case "stream_event":
            // The message as it's written, so Lamp can say what the model has started on: a long file
            // takes minutes to write, and the finished message only arrives at the end.
            let event = obj["event"] as? [String: Any] ?? [:]
            switch event["type"] as? String {
            case "content_block_start":
                let block = event["content_block"] as? [String: Any] ?? [:]
                return block["type"] as? String == "tool_use" ? [.step(plainName(block["name"] as? String ?? ""))] : [.step("")]
            case "content_block_delta":
                let delta = event["delta"] as? [String: Any] ?? [:]
                if delta["type"] as? String == "input_json_delta", let piece = delta["partial_json"] as? String {
                    return [.stepArgs(piece)]
                }
                // What the model is saying, as it says it; the finished message follows as an "assistant" line.
                if delta["type"] as? String == "text_delta", let piece = delta["text"] as? String {
                    return [.textPiece(piece)]
                }
            default: break
            }
        case "user":
            // A tool result: the tool has finished and the model is thinking about what's next.
            let content = (obj["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            if content.contains(where: { $0["type"] as? String == "tool_result" }) { return [.step("")] }
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
        guard let obj = json(line), let type = obj["type"] as? String else {
            // Notices Codex prints for the flags Lamp chose on purpose.
            if line.contains("--dangerously-bypass-hook-trust") || line.hasPrefix("Reading additional input") { return [] }
            return line.trimmed.isEmpty ? [] : [.raw(line)]
        }
        let item = obj["item"] as? [String: Any] ?? [:]
        switch (type, item["type"] as? String) {
        case ("thread.started", _):
            return (obj["thread_id"] as? String).map { [.session($0)] } ?? []
        case ("item.completed", "agent_message"):
            return (item["text"] as? String)?.trimmed.nilIfEmpty.map { [.text($0)] } ?? []
        case ("item.started", "web_search"):
            return [.tool("Search the web", call: "web_search \(item["query"] as? String ?? "")")]
        case ("item.completed", "error"):
            guard let message = item["message"] as? String, !message.contains("--dangerously-bypass-hook-trust") else { return [] }
            return [.raw(message)]
        case ("item.completed", "command_execution"), ("item.completed", "mcp_tool_call"):
            return [.step("")]
        case ("item.started", "mcp_tool_call"):
            let name = item["tool"] as? String ?? "tool"
            let arguments = item["arguments"] as? [String: Any] ?? [:]
            return [.tool(tool(name, arguments), call: callKey(name, arguments))]
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

}

/// Whether Claude Code or Codex is signed in, and signing in without Terminal: both tools' login commands
/// open the browser and finish on their own.
enum EngineSignIn {
    /// nil when Lamp can't tell (the tool didn't answer).
    static func isSignedIn(_ engine: Engine) async -> Bool? {
        guard let tool = ToolLocator.path(for: engine) else { return nil }
        switch engine {
        case .claude:
            let (status, output) = await run(tool, ["auth", "status"], timeout: 20)
            guard status == 0, let info = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]
            else { return status == 0 ? nil : false }
            return info["loggedIn"] as? Bool
        case .codex:
            let (status, output) = await run(tool, ["login", "status"], timeout: 20)
            return status == 0 && output.localizedCaseInsensitiveContains("logged in")
        default:
            return nil
        }
    }

    /// Runs the tool's sign-in, which opens the browser, and waits for it (up to 10 minutes).
    static func signIn(_ engine: Engine) async -> Bool {
        guard let tool = ToolLocator.path(for: engine) else { return false }
        let arguments = engine == .claude ? ["auth", "login"] : ["login"]
        return await run(tool, arguments, timeout: 600).status == 0
    }

    private static func run(_ tool: String, _ arguments: [String], timeout: TimeInterval) async -> (status: Int32, output: String) {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = ToolLocator.userPath
            process.environment = env
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            process.standardInput = FileHandle.nullDevice
            process.terminationHandler = { process in
                let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                continuation.resume(returning: (process.terminationStatus, output))
            }
            do { try process.run() } catch { continuation.resume(returning: (-1, "")); return }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if process.isRunning { process.terminate() } }
        }
    }
}
