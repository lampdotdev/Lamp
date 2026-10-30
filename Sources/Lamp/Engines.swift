import Foundation

/// Which coding agent builds apps.
enum Engine: String, CaseIterable, Identifiable {
    case pi, claude, codex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pi: "Lamp's built-in agent"
        case .claude: "Claude"
        case .codex: "ChatGPT"
        }
    }
}

/// When the agent needs the user's go-ahead to run a shell command (Settings → Building).
enum CommandApproval: String, CaseIterable, Identifiable {
    /// risky: Claude Code's and Codex's own reviewers decide their commands; for pi's, the card is for commands
    /// the decision model's answers show to be risky, and the rest run confined.
    /// There was an "unusual" beside it, which differed only in not letting the in-app model's "low" run a
    /// command; nothing does that now, so a saved "unusual" (or the older "auto") is risky.
    case risky, always, never

    var id: String { rawValue }

    static var current: CommandApproval {
        get {
            let saved = UserDefaults.standard.string(forKey: "commandApproval") ?? ""
            if let mode = CommandApproval(rawValue: saved) { return mode }
            // "auto" or "unusual", from earlier versions: written back, so the picker shows the choice it stands for.
            if !saved.isEmpty { UserDefaults.standard.set(CommandApproval.risky.rawValue, forKey: "commandApproval") }
            return .risky
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "commandApproval") }
    }

    /// The modes where a classifier or model decides, as opposed to the person every time or never.
    var isAutomatic: Bool { self == .risky }

    /// Claude Code's auto mode turned out to be unavailable for this account; use "always" instead.
    static var claudeAutoUnavailable: Bool {
        get { UserDefaults.standard.bool(forKey: "claudeAutoUnavailable") }
        set { UserDefaults.standard.set(newValue, forKey: "claudeAutoUnavailable") }
    }

    var title: String {
        switch self {
        case .risky: "Only when risky"
        case .always: "Always"
        case .never: "Never"
        }
    }
}

/// The user's builder choice (Settings → Building). Stored in UserDefaults.
enum Builder {
    /// pi's provider for a model on this Mac (Native Mac AI); the other is OpenRouter.
    static let localProvider = "forge-local"

    static var engine: Engine {
        get { Engine(rawValue: UserDefaults.standard.string(forKey: "engine") ?? "") ?? .pi }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "engine") }
    }

    /// What pi builds through: OpenRouter, or a model on this Mac. Anything else saved reads as OpenRouter.
    static var piProvider: String {
        get { UserDefaults.standard.string(forKey: "piProvider") == localProvider ? localProvider : "openrouter" }
        set { UserDefaults.standard.set(newValue == localProvider ? localProvider : "openrouter", forKey: "piProvider") }
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
        ("", "Claude's default"),
        ("claude-fable-5-1", "Fable"),
        ("opus", "Opus"),
        ("sonnet", "Sonnet"),
        ("haiku", "Haiku"),
    ]

    /// Codex's choices: the models its account can use, from the list Codex itself caches
    /// (models_cache.json in the folder of the copy Lamp runs), best first. Just the default when the cache isn't there.
    static var codexModels: [(id: String, label: String)] {
        [("", "ChatGPT's default")] + codexCatalog.map { ($0.slug, $0.name) }
    }

    /// Claude Code's small, fast model, for quick judgments: Haiku 5.5 by its full id, since Claude Code's
    /// own "haiku" alias still names Haiku 4.5.
    static let claudeFastModel = "claude-haiku-5-5"

    /// Codex's small, fast model, for quick judgments: Luna 6 when the account has it, else the Luna its
    /// catalog ranks first.
    static var codexFastModel: String? {
        let lunas = codexCatalog.filter { $0.slug.contains("luna") }
        return (lunas.first { $0.slug == "gpt-6-luna" } ?? lunas.first)?.slug
    }

    private static var codexCatalog: [(slug: String, name: String)] {
        let url = EngineInstall.configFolder(.codex).appendingPathComponent("models_cache.json")
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
        get { piModel(for: piProvider) }
        set { UserDefaults.standard.set(newValue, forKey: "piModel.\(piProvider)") }
    }

    /// The model saved for one of pi's providers, chosen or not.
    static func piModel(for provider: String) -> String {
        if let saved = UserDefaults.standard.string(forKey: "piModel.\(provider)"), !saved.isEmpty { return saved }
        if provider == localProvider { return LocalModels.installedIDs().first ?? "" }
        return Provider.defaultModel
    }

    /// Whether the current choice can build right now, and if not, why.
    static func problem() -> String? {
        switch engine {
        case .pi:
            if Agent.executable == nil { return "Lamp's AI builder is missing from the app. Download Lamp again." }
            switch piProvider {
            case localProvider:
                let installed = LocalModels.scan()
                if installed.isEmpty { return "Download a model in Settings → AI Providers → Native Mac AI." }
                if let model = installed.first(where: { $0.id == piModel }), model.format == .mlx, LocalModels.mlxServerPath == nil {
                    return "\(model.name) needs a one-time install before it can run: click Install beside it in Settings → AI Providers → Native Mac AI."
                }
            default:
                if KeyStore.openRouterKey == nil { return "Add your OpenRouter key." }
            }
            if piModel.isEmpty { return "Choose a model." }
        default:
            // With no copy on the Mac, Lamp downloads its own when the engine is chosen (EngineDownloads), so
            // this is a moment's state.
            if EngineInstall.path(for: engine) == nil { return "\(engine.title) hasn't been downloaded yet." }
        }
        return nil
    }

    static var summary: String {
        switch engine {
        case .pi:
            if piProvider == localProvider { return "\(piModel.isEmpty ? "No model" : piModel) via Native Mac AI" }
            return "\(Provider.models.first { $0.id == piModel }?.name ?? piModel) via OpenRouter"
        default:
            let model = engineModel(engine)
            guard !model.isEmpty else { return engine.title }
            let names = engine == .claude ? claudeModels : codexModels
            return "\(engine.title), \(names.first { $0.id == model }?.label ?? model)"
        }
    }
}

/// Finds command-line tools the way the user's own Terminal would. GUI apps don't get the shell's
/// PATH, and tools installed with nvm, mise, Homebrew or npm live in places only that PATH knows. Claude
/// Code and Codex are looked for through EngineInstall, which adds the desktop apps' copies.
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
        // Only what the shell prints, not what its startup files say on stderr: that would land in the PATH.
        let shell = Subprocess.runBlocking("/bin/zsh", ["-ilc", "printf '%s' \"$PATH\""], mergeErrors: false, timeout: 5)
        if shell.ok { parts = shell.output.split(separator: ":").map(String.init).filter { $0.hasPrefix("/") } }
        parts += ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        var seen = Set<String>()
        let path = parts.filter { seen.insert($0).inserted }.joined(separator: ":")
        resolvedPath = path
        return path
    }

    nonisolated(unsafe) private static var chosen: [String: String] = [:]

    /// The tool's path. When several copies are installed (say, one from npm under nvm and one under mise,
    /// or one inside a desktop app, `alsoAt`), the newest version wins rather than whichever comes first.
    static func path(named tool: String, alsoAt extra: [String] = []) -> String? {
        if Pretend.isMissing(tool) { return nil }
        lock.lock()
        // A remembered path can disappear (a tool uninstalled, or updated into a new folder).
        if let cached = chosen[tool], FileManager.default.isExecutableFile(atPath: cached) { lock.unlock(); return cached }
        lock.unlock()
        var seen = Set<String>()
        let candidates = (userPath.split(separator: ":").map { "\($0)/\(tool)" } + extra).filter {
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

    /// The numbers in `<tool> --version` (e.g. "codex-cli 0.160.0" → [0, 160, 0]); [] if it can't tell.
    private static func version(of path: String) -> [Int] {
        let result = Subprocess.runBlocking(path, ["--version"], env: ["PATH": userPath], mergeErrors: false, timeout: 5)
        guard !result.timedOut, let match = result.output.firstMatch(of: #/(\d+)\.(\d+)(?:\.(\d+))?/#) else { return [] }
        return [Int(match.1) ?? 0, Int(match.2) ?? 0, Int(match.3 ?? "0") ?? 0]
    }
}

/// One agent turn: the shell command and its environment.
struct AgentRun {
    let command: String
    let env: [String: String]
    /// For an engine that reads its request from its input and keeps reading while it works (Claude Code): the
    /// request as the first line written there. Nil for one given it on the command line.
    var opening: String? = nil
    /// Whether the chat says each command the engine ran from its own output (`AgentEvent.ran`), for a run whose
    /// commands come to no card of Lamp's.
    var saysCommands = false
}

extension Agent {
    /// Said at the end of a request while the app has no description Lamp can use, so an app gets one from
    /// the request that first builds it, and an app made before descriptions existed from its next request;
    /// and while its description is too long for the desk, so it's shortened rather than cut off there.
    static func undescribed(_ project: LampProject) -> String {
        guard let words = AppDescription.description(of: project) else {
            return "\n\n---\nThis app has no description yet (from Lamp, not part of the request above): once your work is done, write it in \(AppDescription.file), one short sentence saying what the app is."
        }
        guard words.count > AppDescription.limit else { return "" }
        return "\n\n---\nThis app's description in \(AppDescription.file) is \(words.count) characters (from Lamp, not part of the request above): once your work is done, shorten it to \(AppDescription.limit) at most, still one sentence saying what the app is."
    }

    /// Said with each request while the app's code is still Lamp's placeholder. The rule on `plan` is for a new
    /// app, and left to tell one from the placeholder code on its own, not every model does: some build the whole
    /// app with no checklist at all.
    static func newApp(_ project: LampProject) -> String {
        guard !project.makesNoApp, Template.isScaffold(project) else { return "" }
        return "\n\n---\nThis is a new app (from Lamp, not part of the request above): its code is still Lamp's placeholder. Unless you ask first, call `plan` before writing any code."
    }

    /// Builds the command for one turn with the chosen engine. `files` are attachment paths
    /// relative to the app folder; `session` is the engine's saved conversation id, if any; `token` is the
    /// agent's own token for this turn (Store.agentTokens), never the app's.
    @MainActor static func run(prompt: String, files: [String], project: LampProject, offered: Set<SetupOffer>,
                               session: String?, token: String) -> AgentRun {
        // A line on what Lamp remembers, one on what AI the app has, one on the skills that apply to it and one
        // on the device it's for go with the request when the conversation needs telling, the same for each engine.
        // A device's setup has no app for any of those to be about: it's told what the conversation is, every time.
        let prompt = project.isDeviceSetup ? prompt + Agent.deviceSetupNote(project) : prompt + Memory.brief(for: project, engine: Builder.engine, session: session)
            + AIStatus.brief(for: project, engine: Builder.engine, session: session, offered: offered)
            + Skills.brief(for: project, engine: Builder.engine, session: session)
            + DeviceNote.brief(for: project, engine: Builder.engine, session: session)
            + WishNote.brief(for: project, engine: Builder.engine, session: session)
            + Parts.brief(for: project, engine: Builder.engine, session: session)
            + Agent.undescribed(project)
            + Agent.newApp(project)
            + GitHubProjects.note(for: prompt)
            + (LiveReload.eligible(project) ? Agent.liveNote : "")
        var env: [String: String] = ["LAMP_PROMPT": prompt, "LAMP_SYSTEM": systemPrompt(for: project), "LAMP_DIR": project.dir.path,
                                     "PATH": ToolLocator.userPath]
        for (index, file) in files.enumerated() { env["LAMP_FILE_\(index)"] = file }
        let fileArgs = (0..<files.count).map { "\"$LAMP_FILE_\($0)\"" }
        if let session { env["LAMP_SESSION"] = session }

        switch Builder.engine {
        case .pi:
            env["LAMP_LOOK_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/look"
            env["LAMP_USE_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/use"
            env["LAMP_VERSIONS_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/versions"
            env["LAMP_MEMORY_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/memory"
            env["LAMP_SETUP_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/setup"
            env["LAMP_KIND_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/kind"
            env["LAMP_REMOVE_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/remove"
            env["LAMP_RENAME_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/rename"
            env["LAMP_CONNECTORS_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/connectors"
            env["LAMP_LAMPIFY_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/lampify"
            env["LAMP_NETWORK_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/network"
            env["LAMP_INTEGRATION_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/integration"
            env["LAMP_TALK_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/talk"
            env["LAMP_ART_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/art"
            env["LAMP_ASSETS_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/assets"
            env["LAMP_SKILL_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/skill"
            env["LAMP_APPROVE_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/approve"
            env["LAMP_STEER_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/steer"
            env["LAMP_TOKEN"] = token
            return AgentRun(command: command(fileCount: files.count),
                            env: env.merging(environment(prompt: prompt, files: files, project: project, session: session ?? "",
                                                         sessionDir: project.dir.appendingPathComponent(".lamp/pi-sessions").path)) { $1 })
        case .claude:
            // Lamp builds the app itself. Attachments are listed in the prompt; Claude reads them.
            // Isolated from the user's own Claude Code setup, whether this is their copy (with their sign-in) or
            // Lamp's (EngineInstall): --restricted ignores settings files (hooks, permission rules, plugins) while
            // keeping Lamp's --settings; --strict-mcp-config
            // skips their MCP servers and --disable-slash-commands their skills. --tools then lists exactly
            // what the agent gets; in particular, it omits Claude Code's interactive AskUserQuestion tool.
            // Shell commands go through a PreToolUse hook that asks Lamp and waits for the user's answer; Lamp
            // replies in Claude Code's hook format. If Lamp can't be reached the hook fails and the command is denied.
            env["LAMP_TOKEN"] = token
            env["LAMP_SYSTEM"] = systemPrompt(for: project) + tryRules + Self.claudeNote + sandboxNote
            // No background commands, as pi has none: after answering, Claude Code waits for one it started (a
            // server the agent ran to try something) and takes another turn once it ends, so a server kept the turn
            // going with nobody to answer to. A command that runs long stops at its time limit instead.
            env["CLAUDE_CODE_DISABLE_BACKGROUND_TASKS"] = "1"
            // How commands are approved (Settings → Building):
            // - auto: Claude Code's own classifier (--permission-mode auto) runs routine commands; when it would
            //   ask, its PermissionRequest hook sends the request to Lamp's approval card.
            // - always: a PreToolUse hook sends every shell command to Lamp first.
            // - never: the shell is allowed outright.
            // Hooks call Lamp's gateway and wait for the user; if Lamp can't be reached the hook fails and the
            // command is denied.
            var approval = CommandApproval.current
            if approval.isAutomatic && CommandApproval.claudeAutoUnavailable { approval = .always }
            // When Lamp can't be reached (or answers with an error), the hook says no itself: Claude Code treats a
            // hook that fails any other way as "carry on", which for a tool on the allowed list means running it.
            // curl gives up before the hook's own deadline so that fallback gets to run.
            func hook(_ urlVariable: String, event: String) -> [String: Any] {
                let reason = "Lamp could not be reached, so this was not allowed."
                let refusal: [String: Any] = event == "PermissionRequest"
                    ? ["hookEventName": event, "decision": ["behavior": "deny", "message": reason]]
                    : ["hookEventName": event, "permissionDecision": "deny", "permissionDecisionReason": reason]
                let fallback = String(decoding: try! JSONSerialization.data(withJSONObject: ["hookSpecificOutput": refusal]), as: UTF8.self)
                    .replacingOccurrences(of: "'", with: "'\\''")
                return ["type": "command", "timeout": 3600,
                        "command": "/usr/bin/curl -sf --max-time 3540 -X POST -H \"Authorization: Bearer $LAMP_TOKEN\" -H 'Content-Type: application/json' --data-binary @- \"$\(urlVariable)\" || printf '%s' '\(fallback)'"]
            }
            var permissionMode = "acceptEdits"
            var allowed = "Read,Edit,Write,Glob,Grep,WebFetch,WebSearch,mcp__lamp__look_at_app,mcp__lamp__use_app,mcp__lamp__plan,mcp__lamp__delete_file,mcp__lamp__list_versions,mcp__lamp__name_version,mcp__lamp__restore_version,mcp__lamp__make_art,mcp__lamp__assets,mcp__lamp__offer_setup,mcp__lamp__make_app_for,mcp__lamp__remove_app,mcp__lamp__rename_app,mcp__lamp__connectors,mcp__lamp__lampify,mcp__lamp__network_devices,mcp__lamp__device_integration,mcp__lamp__device_permission,mcp__lamp__ask,mcp__lamp__progress,mcp__lamp__write_wish,mcp__lamp__read_skill"
            if Memory.isOn { allowed += ",mcp__lamp__read_notes,mcp__lamp__save_notes" }
            // look_at_app and use_app come from Lamp's own MCP endpoint (Store.mcp); --strict-mcp-config keeps
            // it the only server. The config is a file that reads the token from the environment, so the
            // token isn't on the command line for every process on the Mac to see.
            // A look can build the app, and a use_app batch can wait a minute or more: well past the engines'
            // default tool timeouts (pi's extension allows ten minutes).
            env["MCP_TOOL_TIMEOUT"] = "600000"
            let mcpConfig = project.dir.appendingPathComponent(".lamp/mcp.json")
            let mcp: [String: Any] = ["mcpServers": ["lamp": ["type": "http", "url": "http://127.0.0.1:\(Gateway.port)/mcp",
                                                               "headers": ["Authorization": "Bearer ${LAMP_TOKEN}"]]]]
            try? JSONSerialization.data(withJSONObject: mcp).write(to: mcpConfig)
            env["LAMP_CLAUDE_MCP"] = mcpConfig.path
            // The file tools go through Lamp's privacy check like pi's and Codex's do, whatever the approval
            // mode: a read outside the app's folder asks, and sign-ins and keys are never opened.
            env["LAMP_FILE_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/approve?format=claude-file"
            var preToolUse: [[String: Any]] = [["matcher": "Read|Edit|Write|Glob|Grep", "hooks": [hook("LAMP_FILE_URL", event: "PreToolUse")]]]
            var hooks: [String: Any] = [:]
            var autoMode: [String: Any]?
            // Every shell command goes to Lamp before it runs, in every mode but Never, so the setting means
            // the same with Claude Code as with pi and Codex: Lamp's decision model decides what is routine, and
            // the user sees the rest. Claude's own classifier never gets to wave a command through on its own.
            // In every mode, Never included: the hook is also how a command comes back confined (Sandbox); with
            // Never, Lamp answers at once without a card.
            env["LAMP_APPROVE_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/approve?format=claude"
            preToolUse.append(["matcher": "Bash", "hooks": [hook("LAMP_APPROVE_URL", event: "PreToolUse")]])
            switch approval {
            case .risky:
                // Claude Code's own classifier (auto mode) decides, shell commands included: Lamp's hook only hands
                // each command back confined (Sandbox), with no decision, and what the classifier would ask about
                // comes to Lamp's card through PermissionRequest. A command that ran is said in the chat afterwards.
                // `classifyAllShell` keeps any narrow allow rule from letting a command past it.
                permissionMode = "auto"
                env["LAMP_APPROVE_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/approve?format=claude-confine"
                env["LAMP_RAN_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/approve?format=claude-ran"
                // A command that ran says so whether it succeeded or failed (a failing build or test).
                hooks["PostToolUse"] = [["matcher": "Bash", "hooks": [hook("LAMP_RAN_URL", event: "PostToolUse")]]]
                hooks["PostToolUseFailure"] = [["matcher": "Bash", "hooks": [hook("LAMP_RAN_URL", event: "PostToolUseFailure")]]]
                // What the classifier refused is the classifier's to refuse (the agent is told why), and the chat says so.
                env["LAMP_REFUSED_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/approve?format=claude-refused"
                hooks["PermissionDenied"] = [["matcher": "Bash", "hooks": [hook("LAMP_REFUSED_URL", event: "PermissionDenied")]]]
                // Lamp's rule for the person's devices beside the classifier's own (`$defaults` keeps them).
                autoMode = ["classifyAllShell": true, "soft_deny": ["$defaults", "Device Control: " + DevicePermissions.commandRule]]
                env["LAMP_PERMISSION_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/approve?format=claude-permission"
                hooks["PermissionRequest"] = [["matcher": "*", "hooks": [hook("LAMP_PERMISSION_URL", event: "PermissionRequest")]]]
            case .always:
                break
            case .never:
                allowed += ",Bash"
            }
            hooks["PreToolUse"] = preToolUse
            var settings: [String: Any] = ["hooks": hooks]
            if let autoMode { settings["autoMode"] = autoMode }
            env["LAMP_CLAUDE_SETTINGS"] = String(decoding: (try? JSONSerialization.data(withJSONObject: settings)) ?? Data("{}".utf8), as: UTF8.self)
            env["LAMP_CLAUDE_MODE"] = permissionMode
            env["LAMP_CLAUDE_ALLOWED"] = allowed
            env["LAMP_TOOL"] = EngineInstall.path(for: .claude) ?? "claude"
            env.merge(EngineInstall.environment(for: .claude)) { $1 }
            // The request goes in on Claude Code's input, which stays open while it works: a message the person
            // sends meanwhile is written there too, and Claude Code hands it to the model after the tools it is
            // running (Store.steer), in the same turn. Lamp closes the input once Claude Code has answered.
            var command = """
            "$LAMP_TOOL" -p --input-format stream-json --output-format stream-json --verbose --include-partial-messages --replay-user-messages \\
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
            return AgentRun(command: command, env: env, opening: claudeMessage(prompt))
        case .codex:
            // Isolated from the user's own Codex setup, whether this is their copy (with their sign-in) or Lamp's
            // (EngineInstall): --ignore-user-config --ignore-rules keep out any model, MCP servers, features and
            // rules set there. Lamp's rules go in as developer instructions. `codex exec` is non-interactive and
            // does not expose its interactive question tool; the rules direct every question to Lamp's `ask`.
            env["LAMP_TOOL"] = EngineInstall.path(for: .codex) ?? "codex"
            env.merge(EngineInstall.environment(for: .codex)) { $1 }
            env["LAMP_CODEX_INSTRUCTIONS"] = "developer_instructions=" + Self.tomlString(systemPrompt(for: project) + tryRules + Self.codexNote + sandboxNote)
            // Codex's commands run in Codex's own sandbox (`Sandbox.codexPermissions`): the app's folder, the system,
            // developer tools, caches and temporary folders, with network access; the rest of the Mac stays closed.
            // Approvals (Settings → Building): under "Only when risky" Codex's own reviewer (Auto-review, with Lamp's
            // rules in its policy, `CodexReview`) decides whatever needs more than the sandbox gives, and refuses
            // what Lamp calls risky; nothing comes to Lamp's card. "Always" sends each shell command to Lamp's card
            // first through a PreToolUse hook, and "Never" lets every command run in the sandbox. In both, a command
            // that needs more is refused rather than reviewed (`approval_policy="never"`): the person chose to
            // decide every command, or none.
            // Codex has no file tools of its own, and a shell command can read anything on the Mac without
            // Lamp knowing what. So it reads with Lamp's `read`, `ls`, `find` and `grep` (FileTools, listed for
            // it by `files=1`), which are held to the privacy rule pi's file tools follow, and needs no shell
            // for reading. A read outside the app's folder waits for the user, so those calls may wait as long
            // as a command does.
            let approval = CommandApproval.current
            env["LAMP_TOKEN"] = token
            // Under "Only when risky" the hook asks only whether a command would change one of the person's devices
            // (`DevicePermissions.mayChangeADevice`): Codex's reviewer never sees what runs inside its sandbox.
            env["LAMP_APPROVE_URL"] = "http://127.0.0.1:\(Gateway.port)/agent/approve?format=" + (approval == .risky ? "codex-devices" : "codex")
            let hook = Bundle.main.resourceURL?.appendingPathComponent("lamp-approve.sh").path ?? "lamp-approve.sh"
            env["LAMP_CODEX_HOOKS"] = approval == .never ? "hooks={}"
                : #"hooks.PreToolUse=[{matcher="^Bash$",hooks=[{type="command",timeout=3600,command="'"# + hook + #"'"}]}]"#
            env["LAMP_CODEX_PERMISSIONS"] = Sandbox.codexPermissions(for: project)
            env["LAMP_CODEX_POLICY"] = "auto_review.policy=" + Self.tomlString(CodexReview.policy)
            let review = approval == .risky
                ? #"-c approval_policy="on-request" -c approvals_reviewer="auto_review" -c "$LAMP_CODEX_POLICY""#
                : #"-c approval_policy="never""#
            let codexModel = Builder.engineModel(.codex)
            if !codexModel.isEmpty { env["LAMP_MODEL"] = codexModel }
            // Codex's own bundled skills stay off, as every engine's own skills do (Skills).
            // `skills.bundled.enabled` is defined in Codex's config (BundledSkillsConfig in its config schema) but isn't
            // in OpenAI's published reference; a Codex that drops it ignores the setting and offers its own skills.
            // Codex sends no summaries of the model's thinking unless asked; their headings name its steps in the
            // chat (`AgentEvent.naming`), where the shell commands alone said nothing a person could follow.
            let options = (codexModel.isEmpty ? "" : "-m \"$LAMP_MODEL\" ") + """
            --json --ignore-user-config --ignore-rules --dangerously-bypass-hook-trust --skip-git-repo-check \\
              -c "$LAMP_CODEX_PERMISSIONS" -c default_permissions="lamp" \(review) \\
              -c web_search="live" -c model_reasoning_summary="detailed" -c skills.bundled.enabled=false -c "$LAMP_CODEX_INSTRUCTIONS" -c "$LAMP_CODEX_HOOKS" \\
              -c mcp_servers.lamp.url="http://127.0.0.1:\(Gateway.port)/mcp?files=1" -c mcp_servers.lamp.bearer_token_env_var="LAMP_TOKEN" \\
              -c mcp_servers.lamp.tool_timeout_sec=3600 -c mcp_servers.lamp.default_tools_approval_mode="approve"
            """
            // Lamp's `swift` first on the commands' path, as for the other engines (Sandbox.bin): SwiftPM's own
            // sandbox can't start inside Codex's either.
            let tool = "/usr/bin/env \(Sandbox.shimEnvironment) \"$LAMP_TOOL\""
            let launch: String
            if session != nil {
                // `exec resume` keeps the conversation; it takes no -C/-i (Lamp already runs in the app's folder).
                launch = "\(tool) exec resume \(options) \"$LAMP_SESSION\" -- \"$LAMP_PROMPT\""
            } else {
                let images = files.enumerated().filter { Attachments.isImage(URL(fileURLWithPath: $0.element)) }
                    .map { "-i \"$LAMP_FILE_\($0.offset)\"" }.joined(separator: " ")
                launch = "\(tool) exec \(options) -C \"$LAMP_DIR\" \(images) -- \"$LAMP_PROMPT\""
            }
            // The profile names the app's folder by its own name, and Codex refuses a writable folder that is a link
            // (`Sandbox.codexPermissions`); a folder already swapped for one is said here in Lamp's own words. Codex
            // starts only with the shims it puts on the path.
            let folder = project.realDir.path
            let linked = (try? FileManager.default.destinationOfSymbolicLink(atPath: folder)) != nil
            let command = !linked && Sandbox.prepareShims() ? launch
                : "echo 'Lamp could not set up the sandbox that keeps ChatGPT inside the app.' >&2; exit 1"
            return AgentRun(command: command, env: env, saysCommands: approval != .always)
        }
    }

    /// Claude Code asks the model what each shell command is for; Lamp shows that, in place of the command, as
    /// the step's name in the chat and the line saying what's going on (`AgentEvent.naming`).
    static let claudeNote = """

    - (Claude Code) A shell command's description is what the person sees for that step, never the command: \
    write it for them, a few plain words on what you're doing ("Reading how the shelf works", "Checking it \
    builds"), with no file names, paths or commands.
    - (Claude Code) A command may be refused by Claude Code's own check, which the person never sees and which \
    never asks them. Then it didn't run, and nothing will ask them about it: don't try another way, and never say \
    that Lamp will ask them or that they can approve it. Say in a sentence, in their words, what you couldn't do \
    and why ("I couldn't leave a helper running in the background: it would stay on after the app closes."), never the \
    command or the check itself.
    """

    /// Which tools the "file tools" of the rules above are, for Codex: its own are the shell and apply_patch.
    static let codexNote = """

    - (Codex) Your file tools are Lamp's `read`, `ls`, `find` and `grep`. Read, list and search files with \
    them, never with the shell (no cat, sed, nl, ls, rg, grep or find there): inside the app's folder they need \
    no approval, while a shell command may wait for the user's OK. Change files with apply_patch.
    - (Codex) A command that would reach outside this app may be refused by a review the person never sees. Then \
    it didn't run: don't try another way. Say in a sentence, in their words, what you couldn't do and why (\
    "I didn't delete the old-notes folder: it's outside this app."), never the command, a path you didn't name \
    for them, or the review itself.
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
        if let note = Agent.noteArgument(name, input) { return "\(name) \(note)" }
        return name
    }

    /// A message from the person as Claude Code reads it on its input (`--input-format stream-json`).
    static func claudeMessage(_ text: String) -> String {
        let message: [String: Any] = ["type": "user", "message": ["role": "user", "content": text]]
        return String(decoding: (try? JSONSerialization.data(withJSONObject: message)) ?? Data(), as: UTF8.self)
    }

    /// The request Lamp sends once the change a turn left waiting for Reload is in: after a pause (`Store.pause`), or
    /// after Lamp reloaded the app while the person was away (`Store.reloadIfAway`). The next request of the same
    /// conversation, on every engine, so the agent carries on where it stopped.
    static let afterReload = """
        Your change is in: the app was reloaded with it (by the person, or by Lamp while they were away), or the person \
        closed the app and the new version went in. Look at it now, then carry on with the request from where you stopped, unless a message \
        below says otherwise. If nothing was left to do, say so in a sentence.
        """

    /// Messages the person sent while Codex worked, as the run that resumes its conversation sends them. Codex
    /// tells the model the person interrupted it on purpose, which reads as "stop": they were only passed on.
    static func carryOn(_ text: String) -> String {
        "The person sent this while you were working, and Lamp paused you to pass it on. Take it into account "
            + "and carry on with the request, unless it says otherwise.\n\n" + text
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
            if obj["subtype"] as? String == "compact_boundary" { return [.compacted] }
        case "assistant":
            let content = (obj["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            return content.flatMap { block -> [AgentEvent] in
                switch block["type"] as? String {
                case "text": return (block["text"] as? String)?.trimmed.nilIfEmpty.map { [AgentEvent.text($0)] } ?? []
                case "tool_use":
                    let name = block["name"] as? String ?? "Tool", input = block["input"] as? [String: Any] ?? [:]
                    let said = ((input["doing"] as? String) ?? (name == "Bash" ? input["description"] as? String : nil))?.trimmed.nilIfEmpty
                    let call = AgentEvent.tool(tool(name, input), call: callKey(plainName(name), input), said: said, id: block["id"] as? String,
                                               command: name == "Bash" ? input["command"] as? String : nil)
                    // Claude Code has the model say what each command is for, in a few words of its own.
                    guard name == "Bash" else { return [call] }
                    return [.naming((input["description"] as? String)?.trimmed ?? ""), call]
                default: return []
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
            // A message Lamp wrote to its input, said back as Claude Code hands it to the model.
            if obj["isReplay"] as? Bool == true { return [.received] }
            // A tool result: the tool has finished and the model is thinking about what's next.
            let content = (obj["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            let results = content.filter { $0["type"] as? String == "tool_result" }
            if !results.isEmpty {
                return [.step("")] + results.compactMap { result in
                    (result["tool_use_id"] as? String).map { AgentEvent.ended($0, failed: result["is_error"] as? Bool == true) }
                }
            }
        case "result":
            var events: [AgentEvent] = []
            // No cost from Claude Code: Lamp runs it with the person's Claude sign-in, so its `total_cost_usd` is what the
            // run would have cost at API prices, not money spent. What Lamp shows as spent is what was: OpenRouter's.
            if obj["is_error"] as? Bool == true { events.append(.failed(obj["result"] as? String ?? "Claude failed.")) }
            return events + [.finished]
        default: break
        }
        return []
    }

    /// The bold heading a Codex reasoning summary opens with, or nil when it has none: the rest is the model
    /// thinking aloud, too long to name a step.
    static func heading(of summary: String) -> String? {
        guard let first = summary.trimmed.components(separatedBy: .newlines).first?.trimmed,
              first.hasPrefix("**"), first.hasSuffix("**"), first.count > 4 else { return nil }
        return String(first.dropFirst(2).dropLast(2)).trimmed.nilIfEmpty
    }

    static func parseCodex(_ line: String) -> [AgentEvent] {
        guard let obj = json(line), let type = obj["type"] as? String else {
            // Notices Codex prints for the flags Lamp chose on purpose.
            if line.contains("--dangerously-bypass-hook-trust") || line.hasPrefix("Reading additional input") { return [] }
            // Codex looks for the person's own skills in ~/.agents/skills at every start, whatever its settings, and
            // says so when that folder can't be read: nothing the person needs to hear.
            if line.contains("codex_skills_extension"), line.contains("failed to walk skills root") { return [] }
            return line.trimmed.isEmpty ? [] : [.raw(line)]
        }
        let item = obj["item"] as? [String: Any] ?? [:]
        let kind = item["type"] as? String
        // What Codex does on its own, from its start to its end, so Lamp knows when nothing is half done.
        if ["command_execution", "mcp_tool_call", "file_change", "web_search"].contains(kind), let id = item["id"] as? String {
            if type == "item.started" { return [.acting(id, true)] + codexEvents(type, kind, obj, item) }
            if type == "item.completed" { return codexEvents(type, kind, obj, item) + [.acting(id, false)] }
        }
        return codexEvents(type, kind, obj, item)
    }

    /// The command as the agent wrote it: Codex reports each one inside the shell that runs it
    /// (`/bin/zsh -lc "…"` or `'…'`).
    static func unwrapped(_ command: String) -> String {
        for prefix in ["/bin/zsh -lc ", "/bin/bash -lc ", "/bin/zsh -c ", "/bin/bash -c "] where command.hasPrefix(prefix) {
            let rest = String(command.dropFirst(prefix.count))
            guard let quote = rest.first, quote == "'" || quote == "\"", rest.count >= 2, rest.last == quote else { return command }
            let inner = String(rest.dropFirst().dropLast())
            return quote == "'" ? inner.replacingOccurrences(of: "'\\''", with: "'")
                : inner.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
        }
        return command
    }

    private static func codexEvents(_ type: String, _ kind: String?, _ obj: [String: Any], _ item: [String: Any]) -> [AgentEvent] {
        switch (type, kind) {
        case ("thread.started", _):
            return (obj["thread_id"] as? String).map { [.session($0)] } ?? []
        case ("turn.started", _):
            // The model starts by thinking, sometimes for minutes, and says nothing until its first tool call.
            return [.step("")]
        case ("item.completed", "reasoning"):
            // A summary of what the model is thinking, which Codex opens with a heading of a few words in bold
            // ("**Reading the shelf code**"): what the commands after it are for.
            return Self.heading(of: item["text"] as? String ?? "").map { [.naming($0)] } ?? []
        case ("item.completed", "agent_message"):
            return (item["text"] as? String)?.trimmed.nilIfEmpty.map { [.text($0)] } ?? []
        case ("item.started", "web_search"):
            return [.tool("Search the web", call: "web_search \(item["query"] as? String ?? "")")]
        case ("item.completed", "error"):
            guard let message = item["message"] as? String, !message.contains("--dangerously-bypass-hook-trust") else { return [] }
            return [.raw(message)]
        case ("item.completed", "command_execution"):
            // "declined": Codex's reviewer refused it, and it never ran. "failed": it ran and exited with an error.
            let command = item["command"] as? String ?? ""
            let failed = item["status"] as? String == "failed" || (item["exit_code"] as? Int).map { $0 != 0 } == true
            return [.step("")] + (command.isEmpty ? [] : [.ran(Self.unwrapped(command), refused: item["status"] as? String == "declined",
                                                               failed: failed, id: item["id"] as? String)])
        case ("item.completed", "mcp_tool_call"):
            return [.step("")] + ((item["id"] as? String).map { [.ended($0, failed: item["status"] as? String == "failed")] } ?? [])
        case ("item.started", "mcp_tool_call"):
            let name = item["tool"] as? String ?? "tool"
            let arguments = item["arguments"] as? [String: Any] ?? [:]
            return [.tool(tool(name, arguments), call: callKey(name, arguments), said: (arguments["doing"] as? String)?.trimmed.nilIfEmpty,
                          id: item["id"] as? String)]
        case ("item.started", "command_execution"):
            let command = "Run: \(item["command"] as? String ?? "")"
            return [.tool(command, call: command)]
        case ("item.completed", "file_change"):
            let paths = (item["changes"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String }
            // Codex doesn't say what an edit changed, so two edits to one file can't be told apart:
            // each counts as its own step.
            let id = item["id"] as? String ?? UUID().uuidString
            return [.tool("Edit \(paths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "))", call: id, id: id),
                    .ended(id, failed: item["status"] as? String == "failed")]
        case ("error", _), ("turn.failed", _):
            let raw = obj["message"] as? String ?? ((obj["error"] as? [String: Any])?["message"] as? String) ?? "ChatGPT failed."
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
    /// What the last check found for each engine, for what has to be answered without waiting (whether its
    /// route can answer apps, `AppAI.resolve`). Missing until a check has run; a tool that can't tell leaves
    /// it as it was. On the main actor: checks run concurrently, and their answers land one at a time.
    @MainActor static var known: [Engine: Bool] = [:]
    /// When each engine was last checked, so callers that act on it can check again after a while.
    @MainActor static var checked: [Engine: Date] = [:]

    /// nil when Lamp can't tell (the tool didn't answer).
    static func isSignedIn(_ engine: Engine) async -> Bool? {
        let answer = await ask(engine)
        await MainActor.run {
            if let answer { known[engine] = answer }
            checked[engine] = Date()
        }
        return answer
    }

    /// Checks the engines that are installed and haven't been checked lately, so what Lamp knows of them is
    /// current without asking on every call.
    static func refresh(olderThan age: TimeInterval = 300) async {
        for engine in [Engine.claude, .codex] where EngineInstall.path(for: engine) != nil {
            let last = await MainActor.run { checked[engine] }
            if Date().timeIntervalSince(last ?? .distantPast) > age { _ = await isSignedIn(engine) }
        }
    }

    private static func ask(_ engine: Engine) async -> Bool? {
        guard let tool = EngineInstall.path(for: engine) else { return nil }
        switch engine {
        case .claude:
            let (status, output) = await run(engine, tool, ["auth", "status"], timeout: 20)
            guard status == 0, let info = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]
            else { return status == 0 ? nil : false }
            return info["loggedIn"] as? Bool
        case .codex:
            let (status, output) = await run(engine, tool, ["login", "status"], timeout: 20)
            return status == 0 && output.localizedCaseInsensitiveContains("logged in")
        default:
            return nil
        }
    }

    /// Runs the tool's sign-in, which opens the browser, and waits for it (up to 10 minutes). Gets Lamp's
    /// copy first if there isn't one yet. Nil when the person cancelled it (`cancelSignIn`), whether that was
    /// while the copy was still downloading or while the browser was open.
    static func signIn(_ engine: Engine) async -> Bool? {
        lock.withLock { signIns[engine] = (nil, false) }
        defer { lock.withLock { _ = signIns.removeValue(forKey: engine) } }
        func cancelled() -> Bool { lock.withLock { signIns[engine]?.cancelled ?? false } }
        let ready = await EngineDownloads.shared.ensure(engine)
        if cancelled() { return nil }
        guard ready, let tool = EngineInstall.path(for: engine) else { return false }
        let arguments = engine == .claude ? ["auth", "login"] : ["login"]
        let status = await run(engine, tool, arguments, timeout: 600) { process in
            // Cancelled in the moment between the check above and the login starting: it ends at once.
            let stop = lock.withLock { () -> Bool in
                signIns[engine] = (process, signIns[engine]?.cancelled ?? false)
                return signIns[engine]?.cancelled ?? false
            }
            if stop { Subprocess.terminateTree(process) }
        }.status
        let wasCancelled = cancelled()
        _ = await isSignedIn(engine)
        // Setup counts the sign-in (`SetupCheck.run`), so requests waiting for it start wherever it was made from.
        await Store.shared.recheckSetup()
        return wasCancelled ? nil : status == 0
    }

    /// Ends a sign-in still waiting: for the browser (the tab opened in the wrong browser profile, say, or for
    /// the wrong account), or for Lamp's copy to finish downloading, in which case the browser never opens.
    /// Sign In… can start again at once.
    static func cancelSignIn(_ engine: Engine) {
        let process = lock.withLock { () -> Process? in
            guard let running = signIns[engine] else { return nil }
            signIns[engine] = (running.process, true)
            return running.process
        }
        if let process { Subprocess.terminateTree(process) }
    }

    /// The sign-in under way for each engine: its login process once it has started, and whether it was cancelled.
    nonisolated(unsafe) private static var signIns: [Engine: (process: Process?, cancelled: Bool)] = [:]
    private static let lock = NSLock()

    private static func run(_ engine: Engine, _ tool: String, _ arguments: [String], timeout: TimeInterval,
                            started: (@Sendable (Process) -> Void)? = nil) async -> (status: Int32, output: String) {
        let env = EngineInstall.environment(for: engine).merging(["PATH": ToolLocator.userPath]) { $1 }
        let result = await Subprocess.run(tool, arguments, env: env, timeout: timeout, started: started)
        return (result.status, result.output)
    }
}
