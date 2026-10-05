import Foundation

enum AgentEvent {
    case text(String)
    /// A tool call as shown in the chat ("grep cache.json"), and the whole call with its arguments,
    /// which is what tells a repeated call from a similar one.
    case tool(String, call: String)
    case cost(Double)
    case failed(String)
    case raw(String)
    case session(String)   // an external engine's conversation id, to resume next turn
    case step(String)      // the model has started on a tool call (its name), or on text ("")
    case stepArgs(String)  // a piece of that call's arguments, as they stream in
    case plan([PlanPart])  // the agent's checklist for the build card
}

/// Drives the bundled pi coding agent (github.com/badlogic/pi-mono, MIT) in JSON mode.
/// pi only gets file tools: Forge does the building and feeds compiler errors back.
enum Agent {
    /// `bash` only with Forge's extension, which routes every command through the user's approval.
    static var tools: String {
        "read,edit,write,grep,find,ls" + (forgeTools == nil ? "" :
            ",bash,web_fetch,look_at_app,use_app,plan,delete_file,list_versions,name_version,restore_version")
    }

    /// Forge's own tools for pi (Resources/forge-tools.ts): `look_at_app` has Forge build and open the app
    /// mid-turn and shows the agent the result; `plan` is the checklist on the build card; `delete_file`
    /// removes a file, which pi's own tools can't; the version tools list, name and restore the app's saved
    /// versions. Other engines don't have them.
    static var forgeTools: URL? {
        let url = Bundle.main.resourceURL?.appendingPathComponent("forge-tools.ts")
        return url.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

    static let toolRules = """

    - `look_at_app` builds the app with your changes, opens it, and shows you its windows, what it printed \
    and any build errors or crash, so you can check your work instead of guessing. Once your edits are in, use \
    it after changing the interface or after a fix you can't verify from the code, and fix what you see before \
    finishing. Skip it for small changes you're sure of.
    - `use_app` then uses the open app like a person: clicks at points in its latest picture, types, presses keys, \
    scrolls and picks from menus, and shows you the result. When the change is about behaviour (sorting, a button's effect, a form, \
    a flow between screens), try it with `use_app` before saying it works. It tells you what each click landed \
    on and whether the window changed: when nothing changed, the click probably missed, so aim again before \
    deciding the app is broken. It uses the app as last built, so call `look_at_app` again after editing code.
    - When you build a new app, call `plan` once, before writing any code, with its 3 to 5 main parts in the \
    user's own words (what they'll be able to do, never file or type names) and, for each part, the files \
    you'll write for it. Forge ticks a part off when its files are written, so the user watches the list \
    fill in while they wait. Give every file to exactly one part. Don't use it for small changes.
    - `delete_file` removes a file the app no longer needs, for example after moving its code elsewhere or \
    removing a screen. Never leave an emptied file behind instead.
    - Forge saves a version of the app after every request. `name_version` names one so the user can find it \
    later: name the version this request makes after a milestone the user is happy with, or name the current \
    one (its id from `list_versions`) before a big or risky change, e.g. “Before the redesign”. \
    `restore_version` brings back an earlier version's files: use it only when the user asks to go back, \
    never to undo your own attempt, and find the version with `list_versions` first.
    """

    /// pi ships inside Forge.app (see build.sh).
    static var executable: URL? {
        let url = Bundle.main.resourceURL?.appendingPathComponent("pi/pi")
        return url.flatMap { FileManager.default.isExecutableFile(atPath: $0.path) ? $0 : nil }
    }

    /// Forge's own pi settings and caches, separate from any pi the user runs themselves.
    static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Forge/pi").path

    static let systemPrompt = """
    You are Forge's builder agent. The current directory is a standalone macOS SwiftUI app \
    (Swift Package, Swift 5.9 language mode, macOS 14+, no Xcode project). Read APP.md first for context.

    Rules:
    - Make the change the user asks for by editing files under Sources/. Split code into files as it grows.
    - When a request for a new app or a big change is too vague to build well, ask before writing code: \
    reply with up to three short questions, each with two or three likely answers to pick from (e.g. "Who \
    is it for: just you, or your team?"), and change no files; Forge then waits for the answers. Only ask \
    when the answers would really change what you build. Most requests, including short ones, are clear \
    enough: build a good first version with sensible choices, and end by naming the main assumptions so \
    the user can correct them ("I assumed one list of deals; say if you'd rather have a pipeline board"). \
    Never ask about things you can decide yourself, like layout, colours or names.
    - You can read, search and edit files and read web pages without asking. You can also run shell commands \
    (to clone a repo, convert data, run a script); Forge may ask the user to approve them. Never use the shell to \
    read, list or search files (no cat, ls, head, grep, find or cd): use your file tools for that, which need \
    no approval. Save the shell for what the file tools can't do. Don't build or run the app yourself: when \
    you finish, Forge builds and relaunches it, and if the build fails your next message will contain the \
    compiler errors to fix. If something you need is denied or unavailable, say plainly what you need (for \
    example "attach the files" or "allow the clone"). To read a GitHub repo, clone it shallowly into \
    .forge/reference/ (`gh repo clone owner/name .forge/reference/name -- --depth 1` when gh is installed, which \
    also works for private repos; otherwise `git clone --depth 1`); it's reference only, not part of the app. \
    Never tell the user to approve prompts or change \
    permission settings anywhere else: Forge is the only place they can approve anything.
    - Write code that compiles first time: only use Apple frameworks (SwiftUI, AppKit, Foundation, etc.), \
    no third-party packages, and APIs available on macOS 14.
    - ForgeSupport.swift has tested building blocks for common Mac jobs. Use them instead of writing your own: \
    `ForgeFolderWatcher(folder) { changedURLs in }` (files added or changed in a folder; keep it alive) and \
    `ForgeFolders` (downloads, desktop, documents, screenshots, `files(in:)` newest first); \
    `ForgeHotKey("cmd+shift+space") { }` (a shortcut that works from any app; keep it alive); \
    `ForgeLoginItem.isEnabled` (open at login: offer it as a toggle in Settings, never turn it on silently); \
    `await ForgeText.read(url)` (text from PDFs, scanned PDFs, images and screenshots via Live Text, RTF, Word, \
    HTML, plain text, all on the Mac and free; use it before sending documents to ForgeAI) and \
    `await ForgeText.recognize(in: nsImage)`; `.forgeDropFiles { urls in }` on any view and `ForgeDropZone("Drop \
    screenshots here") { urls in }` for an empty state (Finder files, images from other apps, links); \
    `ForgeClipboardWatcher { item in }` (item.text / image / fileURLs; keep it alive) and \
    `ForgeClipboardWatcher.copy(text)`; `ForgeNotifications.send("Title", body: "…")`. For an app that lives in \
    the menu bar, use SwiftUI's `MenuBarExtra` scene (with `.menuBarExtraStyle(.window)` for a panel), and add \
    `NSApp.setActivationPolicy(.accessory)` only if the user wants no Dock icon. Make the most of being on the \
    Mac: local files, drag and drop, the menu bar, keyboard shortcuts, and fitting into what the user already does.
    - When the information or the job lives in another app the person uses (Slack, Mail, Messages, Notes, or a \
    site in their browser such as Gmail, LinkedIn or a CRM), use `ForgeComputer.ask("…")` to read it or \
    `ForgeComputer.perform("…")` to act there, from ForgeSupport.swift. It works with what they're already signed \
    in to, with no API keys or connectors, and returns text (ask for JSON in the task when the app needs \
    structure). Calls take 10–60 seconds, so run them when the person asks (a button), never on a timer, and \
    show progress. `perform` asks the person before every click or keystroke. Prefer files, ForgeText and \
    the web when they can do the job.
    - Keep the user's data with ForgeStore (in ForgeSupport.swift), backed by SQLite. Settings and small state: \
    `ForgeStore.load(T.self, from: "name")` / `ForgeStore.save(value, to: "name")`. Lists of things (notes, tasks, \
    files seen, history): `ForgeStore.collection("notes", of: Note.self)` with `put`, `get`, `delete`, `count` and \
    `all(where:equals:orderBy:descending:limit:)`, which saves one item at a time and scales to large lists; \
    prefer it over saving a whole array. Only for joins, aggregates or full-text search, your own tables with \
    `ForgeStore.execute` / `query` (create them IF NOT EXISTS, change them only by adding columns). Keep big files \
    such as images in `ForgeStore.folder` and store their names. ForgeStore backs data up and never overwrites \
    data the app can't read. People rely on their data through every change you make, so once a type is saved, \
    only ever add to it: new properties must be optional (or decoded with decodeIfPresent and a default), and \
    never rename, remove or retype a saved property. If you must restructure, decode the old shape and convert \
    it. An app made before ForgeStore may keep data elsewhere; keep reading it from there, or move it over \
    without losing anything.
    - Design: the user's own direction always wins. If they describe a look, attach a mockup or ask for something \
    unconventional (full-screen, no chrome, a game, an art piece, a custom visual style), build exactly that and \
    don't add standard UI they didn't ask for. Otherwise, make it feel like Apple made it, following the macOS \
    Human Interface Guidelines: content first, little chrome. Collections go in a NavigationSplitView with a \
    sidebar. Primary actions go in the toolbar as SF Symbols with help tooltips, and also in the menu bar with the \
    standard shortcuts (⌘N new, ⌫ delete, ⌘F find). Right-click gives context menus. Settings go in a `Settings` \
    scene, not in the window. Focused tasks use sheets, and destructive actions ask first with confirmationDialog. \
    Use native controls and grouped Forms rather than custom-drawn ones, semantic text styles and system colours \
    rather than fixed sizes and hex values, so dark mode and the accent colour just work. Show a \
    ContentUnavailableView when there's nothing yet. Support selection, keyboard navigation, drag and drop and \
    undo where they make sense. Avoid web and iOS habits: no splash or onboarding screens, hamburger menus, \
    floating action buttons, in-window back buttons or big coloured headers.
    - Sources/ForgeSupport.swift is generated by Forge: never edit it. Keep the `.commands { ForgeCommands() }` modifier.
    - Prefer Apple's on-device frameworks whenever one fits the job: they're instant, free, private and work \
    offline. Text in images or PDFs, barcodes and QR codes, faces, body or hand poses, cutting a subject out of \
    its background, image tags or similarity → Vision (VisionKit's ImageAnalysisOverlayView for Live Text in an \
    image view). Speech to text → Speech (SFSpeechRecognizer, with requiresOnDeviceRecognition when supported). \
    Reading text aloud → AVSpeechSynthesizer. Language detection, names and places, sentiment, semantic search \
    → NaturalLanguage (NLTagger, NLEmbedding). Recognising sounds → SoundAnalysis. Photo filters and effects → \
    Core Image. Translation → Translation, inside `if #available(macOS 15, *)`. The app already declares \
    microphone, speech recognition and camera permissions; request authorization before use and handle denial \
    in the UI.
    - For open-ended AI work those frameworks can't do (summarising, extracting, rewriting, answering questions, \
    generating text, understanding what a picture means), use `ForgeAI.ask(...)` from ForgeSupport.swift. Read \
    its doc comment for usage. Never call AI APIs directly, never ask the user for API keys. It accepts \
    `images: [NSImage]` when the AI needs to look at photos or screenshots. To create or edit pictures, use \
    `ForgeAI.makeImage(...)`, `ForgeAI.editImage(...)` or `ForgeAI.editImages(...)`; these take 10–60 seconds. \
    Show a ProgressView while waiting and show errors in the UI.
    - Decisions are your default tool for anything that depends on meaning. `ForgeAI.isTrue`, `ForgeAI.choose`, \
    `ForgeAI.rate` and `ForgeAI.decide` call a decision model (TypeSafe's Jev) that is smart, very fast \
    (well under a second) and extremely cheap (about $0.04 per million input tokens: judging hundreds of items \
    costs a fraction of a cent). Use them generously, without being asked, whenever the app sorts, filters, \
    labels, prioritises, groups, matches, routes, moderates or flags things by what they are or mean: file \
    names, messages, notes, titles, descriptions, user intent. Prefer a decision over keyword lists, regexes, \
    extension rules or other hand-written heuristics that guess at meaning; those are brittle and the decision \
    model is better at it. It's fine to judge every item individually: run calls concurrently (a TaskGroup of \
    about 10–20 at a time), and ask several questions about the same item in one `decide` call. Use code for \
    exact facts (sizes, dates, duplicates, arithmetic) and combine them with decisions: pass the facts in as \
    part of the state. Use the returned probabilities and confidence to choose between acting automatically, \
    suggesting, and asking the user. Decisions take text or JSON-friendly data, not images.
    - The app icon is defined in icon.json: `subject` (the ONE tangible object the icon shows, as a short noun \
    phrase, e.g. "a yellow legal pad with a red pencil"), `symbol` (an SF Symbol name shown until artwork is \
    ready), `background` (one of \(Icons.backgrounds.map(\.name).joined(separator: ", "))) and `tint` (hex main \
    colour of the object). To change the icon, edit icon.json; Forge redraws it. Never create icon files yourself.
    - Files the user attaches are saved in Attachments/ and bundled inside the app. When the app should use \
    one (a logo, a data file, a sound), load it with `ForgeAssets.url("name")`, `ForgeAssets.image("name")` or \
    `ForgeAssets.text("name")` from ForgeSupport.swift, writing the full file name (e.g. "logo.png") in the code: \
    shared copies of the app include only attachments the code names. Screenshots and mockups are usually just references for you.
    - You can't watch the app run, but Forge saves what it prints (print, NSLog, SwiftUI runtime warnings, \
    fatal errors, failed ForgeAI calls) in .forge/runtime/log.txt for the latest launch and \
    .forge/runtime/previous-log.txt for the one before. When the user says something doesn't work, read the log \
    before guessing. If the code doesn't show the cause, add `print` statements around it: the output will be \
    there on your next turn, after the user has tried again. When Forge mentions a screenshot of the app's \
    window, that is what the user was looking at: use it to check layout and visual problems rather than \
    imagining the result from the code.
    - Keep APP.md current: what the app does and how the code is organised.
    - The person you're talking to isn't a programmer and never sees the code: to them, Forge makes apps, \
    and you're the one making theirs. Everything you say to them is about their app and what it does, in \
    everyday words. Never name files, folders, types, functions, frameworks or tools, and never show code, \
    commands or compiler errors, unless they ask for them. Don't narrate your steps as you go ("Now I'll \
    update the view"): do the work, then say what's different.
    - Finish with one or two plain sentences describing what changed. Users often don't know what a Mac can \
    do on its own, and assume things like reading text from a photo, cutting a person out of a picture, \
    transcribing speech or reading aloud need extra software. When one of the on-device abilities above would \
    clearly make this app better, and the user hasn't asked for it or turned it down, you may add one short \
    suggestion in plain words (no framework names), e.g. "Want it to read the text out of pasted screenshots? \
    Your Mac can do that on its own, offline." At most one suggestion, not every turn, and never build it unasked.
    """

    /// The shell command for one agent turn. Values come from FORGE_* environment variables;
    /// attached files are passed as pi `@file` arguments (images and text go straight to the model).
    static func command(fileCount: Int) -> String {
        let files = (0..<fileCount).map { "\"@$FORGE_FILE_\($0)\"" }.joined(separator: " ")
        return """
        "$FORGE_PI" --mode json --provider "$FORGE_PROVIDER" --model "$FORGE_MODEL" --tools \(tools) \\
          --no-extensions\(forgeTools == nil ? "" : " -e \"$FORGE_TOOLS\"") --no-skills --no-prompt-templates --no-context-files --no-approve \\
          --session-dir "$FORGE_SESSION_DIR" --session-id "$FORGE_SESSION" \\
          --append-system-prompt "$FORGE_SYSTEM" -- \(files) "$FORGE_PROMPT"
        """
    }

    static func environment(prompt: String, files: [String] = [], session: String, sessionDir: String) -> [String: String] {
        var env = [
            "FORGE_PI": executable?.path ?? "pi",
            "FORGE_PROVIDER": Builder.piProvider == Builder.myPiProvider ? myPiProvider
                : Builder.piProvider == Builder.localProvider ? LocalModels.piProvider(for: Builder.piModel)
                : Builder.piProvider,
            "FORGE_MODEL": Builder.piProvider == Builder.myPiProvider ? myPiModel : Builder.piModel,
            "FORGE_SESSION": session,
            "FORGE_SESSION_DIR": sessionDir,
            "FORGE_SYSTEM": systemPrompt + (forgeTools == nil ? "" : toolRules),
            "FORGE_PROMPT": prompt,
            "FORGE_TOOLS": forgeTools?.path ?? "",
            // "My pi setup" uses the user's own pi config (their logins); everything else uses Forge's.
            "PI_CODING_AGENT_DIR": Builder.piProvider == Builder.myPiProvider ? userConfigDir : configDir,
            "PI_SKIP_VERSION_CHECK": "1",
            "PI_TELEMETRY": "0",
        ]
        for (index, file) in files.enumerated() { env["FORGE_FILE_\(index)"] = file }
        if let provider = Provider.apiProvider(Builder.piProvider), let key = KeyStore.key(for: provider.id) {
            env[provider.envVar] = key
        }
        return env
    }

    /// "My pi setup" models are stored as "provider/model" (e.g. "anthropic/claude-opus-5-5").
    static var myPiProvider: String { String(Builder.piModel.split(separator: "/", maxSplits: 1).first ?? "") }
    static var myPiModel: String {
        let parts = Builder.piModel.split(separator: "/", maxSplits: 1)
        return parts.count == 2 ? String(parts[1]) : Builder.piModel
    }

    /// Models pi can use for a provider, from `pi --list-models` (offline, from pi's catalog).
    /// For "My pi setup" the result is "provider/model" for every provider signed in there.
    static func listModels(provider: String) async -> [String] {
        guard let pi = executable else { return [] }
        var env = ["PI_SKIP_VERSION_CHECK": "1", "PI_TELEMETRY": "0", "PI_OFFLINE": "1",
                   "PI_CODING_AGENT_DIR": provider == Builder.myPiProvider ? userConfigDir : configDir]
        if let api = Provider.apiProvider(provider) { env[api.envVar] = KeyStore.key(for: api.id) ?? "placeholder" }
        var rows: [String] = []
        _ = await Shell.run("\"$FORGE_PI\" --list-models", cwd: URL(fileURLWithPath: NSTemporaryDirectory()),
                            env: env.merging(["FORGE_PI": pi.path]) { $1 }) { line in
            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            guard columns.count >= 2, columns[0] != "provider" else { return }
            if provider == Builder.myPiProvider {
                rows.append("\(columns[0])/\(columns[1])")
            } else if columns[0] == provider {
                rows.append(String(columns[1]))
            }
        }
        return rows
    }

    /// Parses one line of pi's JSONL event stream (stderr is merged in, so non-JSON lines are diagnostics).
    static func parse(_ line: String) -> [AgentEvent] {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String
        else { return line.trimmed.isEmpty ? [] : [.raw(line)] }

        switch type {
        case "message_update":
            // What the model is writing right now, long before the tool runs: a `write` call's file name
            // arrives seconds into a response that then streams the whole file.
            let update = obj["assistantMessageEvent"] as? [String: Any] ?? [:]
            switch update["type"] as? String {
            case "toolcall_start": return [.step(update["toolName"] as? String ?? "")]
            case "toolcall_delta": return [.stepArgs(update["delta"] as? String ?? "")]
            case "text_start", "thinking_start": return [.step("")]
            default: return []
            }
        case "tool_execution_start":
            let name = obj["toolName"] as? String ?? "tool"
            let args = obj["args"] as? [String: Any] ?? [:]
            var events: [AgentEvent] = [.tool(describe(name, args), call: callKey(name, args))]
            if name == "plan", let parts = args["parts"] as? [[String: Any]] {
                events.append(.plan(parts.enumerated().compactMap { index, part in
                    (part["title"] as? String).map {
                        PlanPart(id: index, title: $0, done: part["done"] as? Bool ?? false,
                                 files: (part["files"] as? [String] ?? []).map { ($0 as NSString).lastPathComponent })
                    }
                }))
            }
            return events
        case "message_end":
            guard let message = obj["message"] as? [String: Any], message["role"] as? String == "assistant" else { return [] }
            var events: [AgentEvent] = []
            for block in message["content"] as? [[String: Any]] ?? [] where block["type"] as? String == "text" {
                if let text = (block["text"] as? String)?.trimmed, !text.isEmpty { events.append(.text(text)) }
            }
            let usage = message["usage"] as? [String: Any]
            if let cost = (usage?["cost"] as? [String: Any])?["total"] as? Double, cost > 0 { events.append(.cost(cost)) }
            if message["stopReason"] as? String == "error" {
                events.append(.failed(message["errorMessage"] as? String ?? "Unknown error"))
            }
            return events
        case "auto_retry_end":
            if obj["success"] as? Bool == false { return [.failed(obj["finalError"] as? String ?? "Unknown error")] }
        default:
            break
        }
        return []
    }

    /// A tool call in full: its name and every argument, in a stable order.
    static func callKey(_ name: String, _ args: [String: Any]) -> String {
        let json = (try? JSONSerialization.data(withJSONObject: args, options: .sortedKeys)).map { String(decoding: $0, as: UTF8.self) }
        return "\(name) \(json ?? "")"
    }

    private static func describe(_ name: String, _ args: [String: Any]) -> String {
        if let path = args["path"] as? String ?? args["file_path"] as? String {
            return "\(name) \((path as NSString).lastPathComponent)"
        }
        if let pattern = args["pattern"] as? String { return "\(name) \(pattern)" }
        return name
    }
}

enum Shell {
    /// GUI apps don't inherit the user's shell PATH, so add the usual install locations.
    private static let extraPath = ["/opt/homebrew/bin", "/usr/local/bin"].joined(separator: ":")

    /// Put this before a build command. The macOS 27 SDK makes `@State` a macro, and its compiler plugin
    /// only ships with full Xcode. With just the Command Line Tools, this builds against the newest
    /// installed SDK that doesn't need the plugin. The same lines are in Forge's own build.sh.
    static let compatibleSDK = #"""
    dev="$(xcode-select -p 2>/dev/null)"
    if [ -z "${SDKROOT:-}" ] && [ -d "$dev/SDKs" ] && [ ! -e "$dev/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib" ]; then
      for sdk in "$dev"/SDKs/MacOSX*.sdk(/NnOn); do
        if ! grep -qs StateMacro /dev/null "$sdk"/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/*-macos.swiftinterface(N); then
          export SDKROOT="$sdk"; break
        fi
      done
    fi

    """#

    /// Runs a zsh command, streaming merged stdout/stderr line by line. Returns the exit status.
    static func run(
        _ command: String,
        cwd: URL,
        env: [String: String] = [:],
        started: (@MainActor (Process) -> Void)? = nil,
        onLine: @escaping @MainActor (String) -> Void
    ) async -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "export PATH=\"\(extraPath):$PATH\"; \(command)"]
        process.currentDirectoryURL = cwd
        let environment = ProcessInfo.processInfo.environment.merging(env) { $1 }
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        // Not `fileHandleForReading.bytes`: every FileHandle shares one serial reader, so a quiet process
        // (the agent waiting on its look_at_app tool) would hold up the output of every other one (the build
        // that tool is waiting for).
        let (lines, output) = AsyncStream<String>.makeStream()
        let reader = LineReader(output)
        pipe.fileHandleForReading.readabilityHandler = { reader.read(from: $0) }

        // Not waitUntilExit(): off the main thread it can wait forever for a process that has already exited.
        let (exit, exited) = AsyncStream<Int32>.makeStream()
        process.terminationHandler = {
            exited.yield($0.terminationStatus)
            exited.finish()
        }
        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            await onLine("Could not start process: \(error.localizedDescription)")
            return -1
        }
        await started?(process)
        for await line in lines { await onLine(line) }
        // In its own task so a cancelled caller (e.g. a SwiftUI .task restarting) still waits for the exit,
        // instead of reading terminationStatus from a process that's still running, which throws.
        return await Task {
            for await status in exit { return status }
            return -1
        }.value
    }

    /// Splits a pipe's output into lines as it arrives.
    private final class LineReader: @unchecked Sendable {
        private var buffer = Data()   // only touched from the handle's readability callbacks, which are serial
        private let output: AsyncStream<String>.Continuation

        init(_ output: AsyncStream<String>.Continuation) { self.output = output }

        func read(from handle: FileHandle) {
            let data = handle.availableData
            guard !data.isEmpty else {   // end of output
                handle.readabilityHandler = nil
                emit(buffer)
                output.finish()
                return
            }
            buffer.append(data)
            while let newline = buffer.firstIndex(of: 0x0A) {
                emit(buffer[..<newline])
                buffer.removeSubrange(...newline)
            }
        }

        private func emit(_ line: Data) {
            let text = String(decoding: line, as: UTF8.self).trimmingCharacters(in: .newlines)
            if !text.isEmpty { output.yield(text) }
        }
    }
}
