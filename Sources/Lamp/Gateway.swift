import Foundation
import AppKit
import Network

/// A tiny HTTP server on 127.0.0.1 that lets generated apps use Lamp's AI
/// without ever seeing the key. Apps call it through `LampAI` (see Template.lampSupportSwift).
final class Gateway: @unchecked Sendable {
    static let port: UInt16 = Edition.gatewayPort

    struct Request {
        let method: String
        let path: String
        let headers: [String: String]   // lowercased names
        let body: Data
        /// Came in over the local network (an app on the person's phone) rather than from this Mac.
        var fromNetwork = false
    }

    private var listener: NWListener?
    private var networkListener: NWListener?
    private let queue = DispatchQueue(label: "dev.lamp.gateway")
    private let handler: @Sendable (Request) async -> (Int, [String: Any])

    init(handler: @escaping @Sendable (Request) async -> (Int, [String: Any])) {
        self.handler = handler
    }

    func start() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: self?.queue ?? .main)
            self?.receive(connection, buffer: Data(), fromNetwork: false)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    /// Also answers on the local network, for apps on the person's own iPhone or iPad (Settings →
    /// Experimental). Requests that come in this way are marked, and the handler lets them use only the
    /// app routes; the agent's stay on this Mac.
    func setLocalNetwork(_ on: Bool) {
        queue.async { [self] in
            if !on {
                networkListener?.cancel()
                networkListener = nil
                return
            }
            guard networkListener == nil else { return }
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            guard let listener = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.port)!) else { return }
            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: self?.queue ?? .main)
                self?.receive(connection, buffer: Data(), fromNetwork: true)
            }
            listener.start(queue: queue)
            networkListener = listener
        }
    }

    private func receive(_ connection: NWConnection, buffer: Data, fromNetwork: Bool) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, done, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if var request = Self.parse(buffer) {
                if request.method == "BAD" { self.respond(connection, status: 400, json: ["error": "Bad request"]); return }
                request.fromNetwork = fromNetwork
                Task {
                    let (status, json) = await self.handler(request)
                    self.respond(connection, status: status, json: json)
                }
            } else if done || error != nil || buffer.count > 40_000_000 {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer, fromNetwork: fromNetwork)
            }
        }
    }

    private func respond(_ connection: NWConnection, status: Int, json: [String: Any]) {
        // 202 is how the MCP endpoint acknowledges a notification: no body.
        let body = status == 202 ? Data() : (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
        let reason = HTTPURLResponse.localizedString(forStatusCode: status).capitalized
        var response = Data("HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    /// Returns a request once the headers and the full body have arrived.
    private static func parse(_ data: Data) -> Request? {
        guard let split = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[..<split.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let start = lines.removeFirst().split(separator: " ")
        guard start.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        // A negative or absurd length is a malformed request, not one to wait for (prefix(-1) would trap).
        guard let length = Int(headers["content-length"] ?? "0"), (0...40_000_000).contains(length) else {
            return Request(method: "BAD", path: String(start[1]), headers: headers, body: Data())
        }
        let body = data[split.upperBound...]
        guard body.count >= length else { return nil }
        return Request(method: String(start[0]), path: String(start[1]), headers: headers, body: Data(body.prefix(length)))
    }
}

/// Runs an in-app AI request with whatever Lamp is connected to.
enum AppAI {
    /// Where an app's text AI goes: a model through OpenRouter, the Claude Code or Codex sign-in, pi with its
    /// key provider, or a model running on this Mac. Settings and an app's own choice keep the id.
    struct TextRoute: Identifiable, Equatable {
        enum Kind: Equatable {
            case openRouter(model: String)
            case engine(Engine, model: String)   // Claude Code or Codex with one of its models; pi with its builder's
            case localModel(provider: String, model: String)   // Native Mac AI, Ollama or LM Studio
        }
        let id: String
        let label: String
        let kind: Kind
        /// Whether this route can answer right now: the key, the tool or the model it needs is there.
        /// Worked out when the list is made, on the main thread, where the local models live.
        let available: Bool

        /// The OpenRouter model that stands in for this route where only OpenRouter can answer (an app on a
        /// phone away from the Mac): the route's own model, else the usual default.
        var openRouter: String {
            if case .openRouter(let model) = kind { return model }
            return AppAI.anthropicModels.first { $0.id == "sonnet" }!.openRouter
        }

        @MainActor static func make(id: String, label: String, kind: Kind) -> TextRoute {
            let available: Bool
            switch kind {
            case .openRouter: available = Provider.hasKey
            case .engine(.pi, _):
                // pi with the person's own setup (their sign-ins), or with a key provider that has its key.
                available = Agent.executable != nil && (Builder.piProvider == Builder.myPiProvider
                    || (Provider.apiProvider(Builder.piProvider) != nil && KeyStore.key(for: Builder.piProvider) != nil))
            case .engine(let engine, _): available = ToolLocator.path(for: engine) != nil
            case .localModel(let provider, let model):
                available = provider == Builder.localProvider ? LocalModels.shared.installed.contains { $0.id == model }
                                                              : LocalModels.shared.external[provider]?.contains(model) == true
            }
            return TextRoute(id: id, label: label, kind: kind, available: available)
        }
    }

    /// Sonnet through OpenRouter: what Lamp's own calls use when there's a key.
    static var defaultOpenRouterModel: String { anthropicModels.first { $0.id == "sonnet" }!.openRouter }

    /// The models OpenRouter offers for apps; Sonnet is the default among them (Haiku is cheaper but
    /// noticeably worse, so it's only used when someone picks it).
    static let anthropicModels: [(id: String, label: String, openRouter: String)] = [
        ("claude-fable-5-1", "Smartest, priciest (Claude Fable)", "anthropic/claude-fable-5.1"),
        ("opus", "Best at coding (Claude Opus)", "anthropic/claude-opus-5.5"),
        ("sonnet", "Faster & cheaper (Claude Sonnet)", "anthropic/claude-sonnet-5.5"),
        ("haiku", "Fastest, cheapest (Claude Haiku)", "anthropic/claude-haiku-4.5"),
    ]

    /// Every route there is, whether or not it can answer right now; the pickers show the ones that can,
    /// plus whatever is chosen.
    @MainActor static var allTextRoutes: [TextRoute] {
        var routes = anthropicModels.map { TextRoute.make(id: $0.id, label: $0.label + " via OpenRouter", kind: .openRouter(model: $0.openRouter)) }
        // The sign-ins, one route per model they offer (Claude Code's short names; the models Codex lists).
        for model in Builder.claudeModels where !model.id.isEmpty {
            routes.append(.make(id: "engine:claude:\(model.id)", label: "\(model.label) via your Claude Code sign-in", kind: .engine(.claude, model: model.id)))
        }
        for model in Builder.codexModels where !model.id.isEmpty {
            routes.append(.make(id: "engine:codex:\(model.id)", label: "\(model.label) via your Codex sign-in", kind: .engine(.codex, model: model.id)))
        }
        if Builder.piProvider == Builder.myPiProvider {
            routes.append(.make(id: "engine:pi", label: "\(Builder.piModel) via your own pi setup", kind: .engine(.pi, model: Builder.piModel)))
        } else if let provider = Provider.apiProvider(Builder.piProvider), provider.id != "openrouter" {
            routes.append(.make(id: "engine:pi", label: "\(Builder.piModel) via your \(provider.name) key", kind: .engine(.pi, model: Builder.piModel)))
        }
        for model in LocalModels.shared.installed where !LocalModels.isDecisionModel(model.id) {
            routes.append(.make(id: "local:\(model.id)", label: "\(model.name) on this Mac", kind: .localModel(provider: Builder.localProvider, model: model.id)))
        }
        for (provider, models) in LocalModels.shared.external.sorted(by: { $0.key < $1.key }) {
            for model in models {
                routes.append(.make(id: "\(provider):\(model)", label: "\(model) (\(LocalModels.externalName(provider)))",
                                    kind: .localModel(provider: provider, model: model)))
            }
        }
        return routes
    }

    /// What the pickers offer: the routes that can answer now, and the chosen one even if it can't (so a
    /// choice isn't silently lost when a key or model goes), in that order.
    /// A route id as saved by an earlier Lamp, when the sign-ins were one route each with no model, read as
    /// today's: Sonnet through Claude Code, Codex's first model.
    @MainActor static func canonicalRoute(_ id: String) -> String {
        switch id {
        case "engine:claude": return "engine:claude:sonnet"
        case "engine:codex": return "engine:codex:\(Builder.codexModels.dropFirst().first?.id ?? "")"
        default: return id
        }
    }

    @MainActor static func textRoutes(including chosen: String?) -> [TextRoute] {
        let routes = allTextRoutes.filter(\.available)
        let chosen = chosen.map(canonicalRoute)
        if let chosen, !routes.contains(where: { $0.id == chosen }), let kept = allTextRoutes.first(where: { $0.id == chosen }) {
            return routes + [kept]
        }
        return routes
    }

    /// The route apps use when nothing was chosen: what builds apps when that's a model on this Mac (someone
    /// who chose to stay local keeps staying local), else OpenRouter's Sonnet with a key, else the builder's
    /// own sign-in, else the first thing that can answer.
    @MainActor static var defaultRoute: TextRoute {
        let routes = allTextRoutes
        func route(_ id: String) -> TextRoute? { routes.first { $0.id == id && $0.available } }
        if Builder.engine == .pi, Builder.piProvider == Builder.localProvider || LocalModels.externalIDs.contains(Builder.piProvider),
           let local = route("\(Builder.piProvider):\(Builder.piModel)") ?? route("local:\(Builder.piModel)") {
            return local
        }
        if let sonnet = route("sonnet") { return sonnet }
        // The builder's own sign-in: Sonnet through Claude Code (never Haiku unasked), Codex's best model, pi's.
        let own: String
        switch Builder.engine {
        case .claude: own = "engine:claude:sonnet"
        case .codex: own = "engine:codex:\(Builder.codexModels.dropFirst().first?.id ?? "")"
        case .pi: own = "engine:pi"
        }
        if let route = route(own) { return route }
        return routes.first(where: \.available) ?? routes.first { $0.id == "sonnet" }!
    }

    /// The OpenRouter model an app on the person's phone uses away from the Mac, where only OpenRouter can
    /// answer: Settings' choice, else the chosen route's own model when that's through OpenRouter, else Sonnet.
    @MainActor static var awayModel: (id: String, label: String, openRouter: String) {
        let saved = UserDefaults.standard.string(forKey: "awayModel") ?? ""
        if let chosen = anthropicModels.first(where: { $0.id == saved }) { return chosen }
        if case .openRouter(let name) = model.kind, let same = anthropicModels.first(where: { $0.openRouter == name }) { return same }
        return anthropicModels.first { $0.id == "sonnet" }!
    }

    /// The same for one app: its own choice (info panel), else Settings'.
    @MainActor static func awayModel(for choice: String?) -> (id: String, label: String, openRouter: String) {
        anthropicModels.first { $0.id == choice } ?? awayModel
    }

    /// The image model an app on the phone uses away from the Mac: Settings' choice, else the Mac's own
    /// choice when that's a cloud model, else the first cloud model. The model on this Mac can't travel.
    @MainActor static var awayImageModel: String {
        let saved = UserDefaults.standard.string(forKey: "awayImageModel") ?? ""
        if Icons.artModels.contains(where: { $0.id == saved }) { return saved }
        let macs = Icons.artModel
        return Icons.artModels.contains(where: { $0.id == macs }) ? macs : Icons.artModels[0].id
    }

    @MainActor static func awayImageModel(for choice: String?) -> String {
        Icons.artModels.contains { $0.id == choice } ? choice! : awayImageModel
    }

    /// The route Settings chose for apps, when it can still answer; else the default.
    @MainActor static var model: TextRoute { route(for: UserDefaults.standard.string(forKey: "appModel")) }

    /// The text route for one app: its own choice (info panel), or Settings', when it can answer; else the
    /// default.
    @MainActor static func route(for choice: String?) -> TextRoute {
        let choice = choice.map(canonicalRoute)
        if let choice, let route = allTextRoutes.first(where: { $0.id == choice }), route.available { return route }
        if let saved = UserDefaults.standard.string(forKey: "appModel").map(canonicalRoute), saved != choice,
           let route = allTextRoutes.first(where: { $0.id == saved }), route.available { return route }
        return defaultRoute
    }

    struct Failure: Error {
        let message: String
        /// What was billed before the failure (both JSON attempts, say), so the app's usage still counts it.
        var cost: Double = 0
    }

    /// Whether apps' text AI can answer: an OpenRouter key, or whatever builds apps.
    static var canAnswer: Bool {
        Provider.hasKey || Builder.engine == .pi || ToolLocator.path(for: Builder.engine) != nil
    }

    /// Returns the model's text and what the call cost in USD.
    /// An image from the app: `media_type` (e.g. image/jpeg) and base64 `data`.
    struct Image {
        let mediaType: String
        let data: String
    }

    /// `model` overrides the in-app model (an OpenRouter model ID), e.g. for Lamp's own import review.
    /// `appModel` is an app's own text model (an id from `models`), when it has one.
    static func complete(prompt: String, images: [Image], system: String, json: Bool,
                         model: String? = nil, appModel: String? = nil, engineModel: String? = nil) async throws -> (String, Double) {
        let chosen = await route(for: appModel)
        var system = system
        if json { system += "\n\nRespond with only valid JSON. No prose, no code fences." }
        var (text, cost) = try await dispatch(prompt: prompt, images: images, system: system, json: json, model: model, chosen: chosen, engineModel: engineModel)
        guard json else { return (text, cost) }
        // A JSON reply that doesn't parse (cut off, or wrapped in prose) is useless to the app: ask once more,
        // through the same provider, saying so, before giving up. Both attempts are billed, so the cost goes
        // with the failure too.
        var reply = stripFences(text)
        if !isJSON(reply) {
            let again = "\(prompt)\n\nYour previous reply was not valid JSON (it may have been cut off). Reply with the complete JSON only."
            do {
                let (retry, more) = try await dispatch(prompt: again, images: images, system: system, json: true, model: model, chosen: chosen, engineModel: engineModel)
                cost += more
                reply = stripFences(retry)
            } catch let failure as Failure {
                throw Failure(message: failure.message, cost: cost)
            } catch {
                throw Failure(message: error.localizedDescription, cost: cost)
            }
            if !isJSON(reply) {
                throw Failure(message: "The AI's reply wasn't valid JSON, even on a second try. Ask for less at once.", cost: cost)
            }
        }
        return (reply, cost)
    }

    /// One request along the route: `model` names an OpenRouter model to use instead of the route's own, for
    /// Lamp's own calls (the icon judge, suggestions) when there's a key; `engineModel` likewise names the
    /// model for Claude Code or Codex (the fast one for decisions by text).
    private static func dispatch(prompt: String, images: [Image], system: String, json: Bool, model: String?,
                                 chosen: TextRoute, engineModel: String? = nil) async throws -> (String, Double) {
        if let model, Provider.hasKey {
            return try await viaOpenRouter(prompt: prompt, images: images, system: system, model: model, json: json)
        }
        switch chosen.kind {
        case .openRouter(let model):
            guard Provider.hasKey else { throw Failure(message: "Apps' AI features need an OpenRouter key, or a working builder. Set one up in Lamp → Settings (⌘,).") }
            return try await viaOpenRouter(prompt: prompt, images: images, system: system, model: model, json: json)
        case .engine(.pi, _):
            return try await viaPi(prompt: prompt, images: images, system: system)
        case .engine(let engine, let model):
            return try await viaEngine(engine, prompt: prompt, images: images, system: system, model: engineModel ?? model)
        case .localModel(let provider, let model):
            let base: String
            if provider == Builder.localProvider {
                base = try await LocalModels.shared.ensureServer(for: model)
            } else {
                base = "http://127.0.0.1:\(provider == "ext-ollama" ? 11434 : 1234)"
            }
            return try await viaOpenAICompatible("\(base)/v1/chat/completions", key: nil,
                                                 prompt: prompt, images: images, system: system, model: model)
        }
    }

    private static func isJSON(_ text: String) -> Bool {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])) != nil
    }

    /// One-shot pi call (no tools, no session) with the builder's provider and model. Covers every
    /// provider pi supports, including "My pi setup" subscriptions.
    private static func viaPi(prompt: String, images: [Image], system: String) async throws -> (String, Double) {
        guard Agent.executable != nil else { throw Failure(message: "Lamp's AI builder is missing. Download Lamp again.") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-ai-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var files: [String] = []
        for (index, image) in images.enumerated() {
            guard let data = Data(base64Encoded: image.data) else { continue }
            let name = "image\(index).\(image.mediaType.hasSuffix("png") ? "png" : "jpg")"
            try data.write(to: folder.appendingPathComponent(name))
            files.append(name)
        }
        var env = Agent.environment(prompt: prompt, files: files, session: "", sessionDir: folder.path)
        env["LAMP_SYSTEM"] = system.isEmpty ? "You are a helpful assistant inside a Mac app." : system
        let fileArgs = files.indices.map { "\"@$LAMP_FILE_\($0)\"" }.joined(separator: " ")
        let command = """
        "$LAMP_PI" --mode json --provider "$LAMP_PROVIDER" --model "$LAMP_MODEL" --no-tools --no-session \\
          --no-extensions --no-skills --no-prompt-templates --no-context-files --no-approve \\
          --system-prompt "$LAMP_SYSTEM" -- \(fileArgs) "$LAMP_PROMPT"
        """
        var text = ""
        var cost = 0.0
        var failure: String?
        _ = await Shell.run(command, cwd: folder, env: env) { line in
            for event in Agent.parse(line) {
                switch event {
                case .text(let chunk): text = text.isEmpty ? chunk : text + "\n" + chunk
                case .cost(let amount): cost += amount
                case .failed(let message): failure = message
                default: break
                }
            }
        }
        if let failure { throw Failure(message: Provider.friendlyError(failure)) }
        guard !text.isEmpty else { throw Failure(message: "The AI didn't answer.") }
        return (text, cost)
    }

    /// One-shot answer from an external coding agent, using the user's own sign-in (and so their subscription).
    /// Isolated from their setup like a build turn, with no tools except reading the images it's given.
    private static func viaEngine(_ engine: Engine, prompt: String, images: [Image],
                                  system: String, model: String) async throws -> (String, Double) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-ai-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var files: [String] = []
        for (index, image) in images.enumerated() {
            guard let data = Data(base64Encoded: image.data) else { continue }
            let name = "image\(index).\(image.mediaType.hasSuffix("png") ? "png" : "jpg")"
            try data.write(to: folder.appendingPathComponent(name))
            files.append(name)
        }
        var env: [String: String] = ["PATH": ToolLocator.userPath, "LAMP_TOOL": ToolLocator.path(for: engine) ?? "",
                                     "LAMP_SYSTEM": system.isEmpty ? "You are a helpful assistant inside a Mac app." : system,
                                     "LAMP_PROMPT": prompt]
        for (index, file) in files.enumerated() { env["LAMP_FILE_\(index)"] = file }
        let command: String
        switch engine {
        case .claude:
            // Claude Code takes images by reading them, so it gets the Read tool and their names.
            if !files.isEmpty { env["LAMP_PROMPT"] = prompt + "\n\n(Images: " + files.joined(separator: ", ") + ". Read them.)" }
            env["LAMP_MODEL"] = model   // "haiku", "sonnet" or "opus": Claude Code's own aliases
            command = """
            "$LAMP_TOOL" -p "$LAMP_PROMPT" --output-format stream-json --verbose --no-session-persistence \\
              --restricted --strict-mcp-config --disable-slash-commands \\
              --tools \(files.isEmpty ? "''" : "Read --allowedTools Read") --model "$LAMP_MODEL" --system-prompt "$LAMP_SYSTEM"
            """
        case .codex:
            env["LAMP_CODEX_INSTRUCTIONS"] = "developer_instructions="
                + Agent.tomlString(env["LAMP_SYSTEM"]! + "\n\nAnswer directly. Don't run commands or change files.")
            let imageArgs = files.indices.map { "-i \"$LAMP_FILE_\($0)\"" }.joined(separator: " ")
            // Only one of Codex's own models is passed on; an Anthropic id (an app built before Codex
            // answered for it) means Codex's default.
            var modelArg = ""
            if Builder.codexModels.contains(where: { $0.id == model && !model.isEmpty }) {
                env["LAMP_MODEL"] = model
                modelArg = "-m \"$LAMP_MODEL\" "
            }
            command = """
            "$LAMP_TOOL" exec --json --ignore-user-config --ignore-rules --skip-git-repo-check --ephemeral \\
              -s read-only -c hooks={} -c model_reasoning_effort="low" \(modelArg)-c "$LAMP_CODEX_INSTRUCTIONS" \(imageArgs) -- "$LAMP_PROMPT"
            """
        case .pi:
            return try await viaPi(prompt: prompt, images: images, system: system)
        }
        var text = ""
        var cost = 0.0
        var failure: String?
        let status = await Shell.run(command, cwd: folder, env: env) { line in
            for event in Agent.parse(line, engine: engine) {
                switch event {
                case .text(let chunk): text = chunk   // the last message is the answer
                case .cost(let amount): cost += amount
                case .failed(let message): failure = message
                default: break
                }
            }
        }
        if let failure { throw Failure(message: Provider.friendlyError(failure)) }
        guard !text.isEmpty else {
            throw Failure(message: status == 0 ? "The AI didn't answer." : "\(engine.title) didn't answer. Check it's signed in.")
        }
        return (text, cost)
    }

    /// Chat completion against any OpenAI-compatible endpoint (the local llama.cpp server, Ollama, LM Studio).
    private static func viaOpenAICompatible(_ endpoint: String, key: String?, prompt: String, images: [Image],
                                            system: String, model: String) async throws -> (String, Double) {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 600   // local models may need to load first
        if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var messages: [[String: Any]] = []
        if !system.trimmed.isEmpty { messages.append(["role": "system", "content": system]) }
        let content: [[String: Any]] = [["type": "text", "text": prompt]] + images.map {
            ["type": "image_url", "image_url": ["url": "data:\($0.mediaType);base64,\($0.data)"]]
        }
        messages.append(["role": "user", "content": content])
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "messages": messages] as [String: Any])
        let (data, response) = try await URLSession.shared.data(for: request)
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let choices = obj["choices"] as? [[String: Any]],
              let text = (choices.first?["message"] as? [String: Any])?["content"] as? String else {
            let message = (obj["error"] as? [String: Any])?["message"] as? String ?? "The local model didn't answer."
            throw Failure(message: message)
        }
        // Reasoning models may wrap their thinking in <think>…</think>; apps only want the answer.
        let answer = text.replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
        return (answer.trimmed, 0)
    }

    // MARK: Decisions (System One models such as TypeSafe's Jev)

    /// Decision models: Jev through OpenRouter or directly through TypeSafe. Same request either way.
    /// Where decisions go: Jev through OpenRouter or TypeSafe, OpenAI's Decisions API, a decision model on
    /// this Mac, or a small text model answering as JSON (`decideByText`).
    static let decisionModels: [(id: String, label: String, provider: String, model: String)] = [
        ("openrouter:jev-latest", "Jev via OpenRouter", "openrouter", "jev-latest"),
        ("typesafe:jev-latest", "Jev via TypeSafe", "typesafe", "jev-latest"),
        ("openai:gpt-6-luna", "Luna via OpenAI (Decisions API)", "openai", "gpt-6-luna"),
        ("local:h2o-lightning-4b", "H2O Lightning 4B on this Mac", "local", "h2o-lightning-4b"),
        ("text", "By text, through what answers apps", "text", ""),
    ]

    /// The decision model on this Mac, as installed (its id for the local server), or nil.
    @MainActor static func localDecisionModel() -> String? {
        guard let spec = LocalModels.decisionCatalog.first else { return nil }
        return LocalModels.shared.installedID(for: spec)
    }

    static var decisionModel: (id: String, label: String, provider: String, model: String) {
        let saved = UserDefaults.standard.string(forKey: "decisionModel") ?? ""
        if let chosen = decisionModels.first(where: { $0.id == saved }) { return chosen }
        // Default to whichever key exists, preferring OpenRouter, then TypeSafe, then OpenAI.
        for provider in ["openrouter", "typesafe", "openai"] where KeyStore.key(for: provider) != nil {
            return decisionModels.first { $0.provider == provider }!
        }
        return decisionModels[0]
    }

    /// Sends `state` and typed `questions` (TypeSafe's System One format) to the decision model.
    /// Returns the answers keyed like the questions, and the cost in USD.
    static func decide(state: Any, questions: [String: Any],
                       model appChoice: String? = nil) async throws -> ([String: Any], Double) {
        let choice = decisionModels.first { $0.id == appChoice } ?? decisionModel
        if choice.provider == "text" { return try await decideByText(state: state, questions: questions) }
        if choice.provider == "local" {
            if let id = await localDecisionModel() { return try await decideLocally(state: state, questions: questions, model: id) }
            if canAnswer { return try await decideByText(state: state, questions: questions) }
            throw Failure(message: "The decision model on this Mac isn't downloaded yet. Get it in Lamp → Settings (⌘,) → Apps.")
        }
        guard let key = KeyStore.key(for: choice.provider) else {
            // No decision model: a small text model answers the same questions in JSON instead.
            if canAnswer { return try await decideByText(state: state, questions: questions) }
            let name = choice.provider == "typesafe" ? "a TypeSafe" : choice.provider == "openai" ? "an OpenAI" : "an OpenRouter"
            throw Failure(message: "Decisions need \(name) key. Add one in Lamp → Settings (⌘,) → AI.")
        }
        if choice.provider == "openai" { return try await decideViaOpenAI(state: state, questions: questions, key: key, model: choice.model) }
        let endpoint = choice.provider == "typesafe" ? "https://api.typesafe.ai/v1/systemone"
                                                     : "https://openrouter.ai/api/v1/systemone"
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Lamp", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["state": state, "model": choice.model,
                                                                       "questions": questions] as [String: Any])
        // Rate limits (429) and overload (529) are expected under load: back off and retry a few times.
        for attempt in 0..<4 {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            if (status == 429 || status == 529) && attempt < 3 {
                try await Task.sleep(for: .milliseconds(500 << attempt))
                continue
            }
            guard status == 200, let answers = obj["answers"] as? [String: Any] else {
                let error = obj["error"] as? [String: Any]
                let detail = error?["message"] as? String ?? obj["detail"].map { "\($0)" } ?? "HTTP \(status)"
                throw Failure(message: status == 422 ? "The decision request was invalid: \(detail)"
                                                     : Provider.friendlyError("\(status) \(detail)"))
            }
            let usage = obj["usage"] as? [String: Any] ?? [:]
            // Jev charges per input token ($0.042 per million); OpenRouter may report the exact cost.
            let cost = usage["cost"] as? Double ?? Double(usage["input_tokens"] as? Int ?? 0) * 0.042 / 1_000_000
            return (answers, cost)
        }
        throw Failure(message: "The decision model is busy. Try again in a moment.")
    }

    /// The state as the decision models read it: text as it is, anything else as JSON.
    private static func stateText(_ state: Any) -> String {
        if let text = state as? String { return text }
        return (try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys, .fragmentsAllowed]))
            .map { String(decoding: $0, as: UTF8.self) } ?? "\(state)"
    }

    /// Each question's options, in order: for a choice the criteria's names (with descriptions); for a
    /// score the levels, lowest first; for a noul true then false.
    private static func options(of question: [String: Any]) -> [(name: String, description: String)] {
        switch question["type"] as? String {
        case "noul":
            let criteria = question["criteria"] as? [String: Any] ?? [:]
            return [("true", criteria["true"] as? String ?? "Yes"), ("false", criteria["false"] as? String ?? "No")]
        case "score":
            return (question["criteria"] as? [String] ?? []).map { ($0, "") }
        default:
            if let dict = question["criteria"] as? [String: Any] {
                return dict.keys.sorted().map { ($0, dict[$0] as? String ?? "") }
            }
            return (question["criteria"] as? [String] ?? []).map { ($0, "") }
        }
    }

    /// OpenAI's Decisions API (gpt-6-luna): the same questions in its shape (predicate, choice, score), and
    /// its answers back in Jev's shape.
    static func decideViaOpenAI(state: Any, questions: [String: Any], key: String, model: String) async throws -> ([String: Any], Double) {
        var asked: [[String: Any]] = []
        for (id, value) in questions {
            guard let question = value as? [String: Any] else { continue }
            var instructions = question["instructions"] as? String ?? ""
            var item: [String: Any] = ["name": id]
            let options = options(of: question)
            switch question["type"] as? String {
            case "noul":
                item["type"] = "predicate"
                if let criteria = question["criteria"] as? [String: Any], !criteria.isEmpty {
                    instructions += "\nYes means: \(criteria["true"] ?? "yes"). No means: \(criteria["false"] ?? "no")."
                }
            case "score":
                item["type"] = "score"
                item["levels"] = options.map { ["label": $0.name, "description": $0.name] }
            default:
                item["type"] = "choice"
                item["choices"] = options.map { ["value": $0.name, "description": $0.description.isEmpty ? $0.name : $0.description] }
            }
            item["instructions"] = instructions
            asked.append(item)
        }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/decisions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "input": stateText(state), "questions": asked] as [String: Any])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard status == 200, let given = obj["answers"] as? [[String: Any]] else {
            let detail = (obj["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(status)"
            throw Failure(message: Provider.friendlyError("\(status) \(detail)"))
        }
        var answers: [String: Any] = [:]
        for answer in given {
            guard let id = answer["name"] as? String else { continue }
            switch answer["type"] as? String {
            case "predicate":
                answers[id] = ["noul": answer["probability"] as? Double ?? 0.5]
            case "score":
                var probabilities: [String: Double] = [:]
                for entry in answer["probabilities"] as? [[String: Any]] ?? [] {
                    if let index = entry["value"] as? Int, let p = entry["probability"] as? Double { probabilities[String(index)] = p }
                }
                answers[id] = ["score": answer["score"] as? Double ?? 0, "probabilities": probabilities, "confidence": answer["confidence"] as? Double ?? 0]
            default:
                var probabilities: [String: Double] = [:]
                for entry in answer["probabilities"] as? [[String: Any]] ?? [] {
                    if let value = entry["value"] as? String, let p = entry["probability"] as? Double { probabilities[value] = p }
                }
                answers[id] = ["choice": answer["choice"] as? String ?? "", "probabilities": probabilities, "confidence": answer["confidence"] as? Double ?? 0]
            }
        }
        // $0.10 per million input tokens, nothing for output.
        let cost = Double((obj["usage"] as? [String: Any])?["input_tokens"] as? Int ?? 0) * 0.10 / 1_000_000
        return (answers, cost)
    }

    /// A Jev-class model on this Mac, through the local server, the way its serving shim does it: one
    /// question per forward pass, the record and the lettered options in a chat prompt ending in "Answer:",
    /// and the probabilities read off the label tokens at that slot (softmax over their log-probabilities
    /// at the model's temperature), with the shim's confidence and the floor it holds yes/no answers to.
    static func decideLocally(state: Any, questions: [String: Any], model: String) async throws -> ([String: Any], Double) {
        let base = try await LocalModels.shared.ensureServer(for: model)
        let labels = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz").map(String.init)
        let record = stateText(state)
        var answers: [String: Any] = [:]
        for (id, value) in questions {
            guard let question = value as? [String: Any] else { continue }
            let options = options(of: question)
            guard !options.isEmpty, options.count <= labels.count else { throw Failure(message: "The question \"\(id)\" has no options, or too many.") }
            let lines = options.enumerated().map { index, option in
                "\(labels[index])) \(option.name)" + (option.description.isEmpty ? "" : ": \(option.description)")
            }
            let user = "record: \(record)\nquestion: \(question["instructions"] as? String ?? "")\noptions:\n" + lines.joined(separator: "\n")
            let prompt = "<|im_start|>system\nYou are a decision engine. You read a record and answer one question about it by choosing exactly one option. Reply with a single letter.<|im_end|>\n"
                + "<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\nAnswer:"
            var request = URLRequest(url: URL(string: "\(base)/v1/completions")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 600
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "prompt": prompt, "max_tokens": 1, "temperature": 0,
                                                                           "logprobs": max(options.count * 2, 20)] as [String: Any])
            let (data, response) = try await URLSession.shared.data(for: request)
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            // The server lists the likeliest tokens at the answer slot: [{token, logprob}] under the first
            // content entry (or, from older servers, a {token: logprob} dictionary).
            guard (response as? HTTPURLResponse)?.statusCode == 200, let choice = (obj["choices"] as? [[String: Any]])?.first,
                  let logprobs = choice["logprobs"] as? [String: Any] else {
                throw Failure(message: "The decision model on this Mac didn't answer: \((obj["error"] as? [String: Any])?["message"] as? String ?? "no probabilities came back").")
            }
            var top: [String: Double] = [:]
            if let content = (logprobs["content"] as? [[String: Any]])?.first, let list = content["top_logprobs"] as? [[String: Any]] {
                for entry in list { if let token = entry["token"] as? String, let p = entry["logprob"] as? Double { top[token] = p } }
            } else if let dict = (logprobs["top_logprobs"] as? [[String: Any]])?.first {
                for (token, p) in dict { if let p = p as? Double { top[token] = p } }
            }
            guard !top.isEmpty else { throw Failure(message: "The decision model on this Mac didn't answer: no probabilities came back.") }
            // The label's log-probability at the answer slot, with or without the space the tokenizer puts first.
            var logs: [Double] = []
            for index in options.indices {
                let label = labels[index]
                let found = top.first { $0.key.trimmingCharacters(in: .whitespaces) == label }?.value
                logs.append(found ?? -30)
            }
            let temperature = 0.8
            let scaled = logs.map { $0 / temperature }
            let peak = scaled.max() ?? 0
            let weights = scaled.map { exp($0 - peak) }
            let total = weights.reduce(0, +)
            let probabilities = weights.map { $0 / total }
            let confidence = options.count < 2 ? 1 : (probabilities.max()! - 1 / Double(options.count)) / (1 - 1 / Double(options.count))
            switch question["type"] as? String {
            case "noul":
                var p = probabilities[0]
                let floor = 0.801   // the shim commits a yes/no it isn't sure of to the floor on its side
                if max(p, 1 - p) < floor { p = p >= 0.5 ? floor : 1 - floor }
                answers[id] = ["noul": p]
            case "score":
                let score = probabilities.enumerated().reduce(0.0) { $0 + Double($1.offset) * $1.element }
                answers[id] = ["score": score, "probabilities": Dictionary(uniqueKeysWithValues: probabilities.enumerated().map { (String($0.offset), $0.element) }),
                               "confidence": confidence]
            default:
                let best = probabilities.enumerated().max { $0.element < $1.element }!.offset
                answers[id] = ["choice": options[best].name, "probabilities": Dictionary(uniqueKeysWithValues: zip(options.map(\.name), probabilities)),
                               "confidence": confidence]
            }
        }
        return (answers, 0)
    }

    /// The fast model of whatever answers for apps, for decisions made by text: Haiku through Claude Code,
    /// Luna through Codex, and pi's own model otherwise.
    static var fastModel: String? {
        switch Builder.engine {
        case .claude: "haiku"
        case .codex: Builder.codexFastModel
        case .pi: nil
        }
    }

    /// What `fastModel` is called in Settings.
    static var fastModelName: String {
        switch Builder.engine {
        case .claude: "Haiku through Claude Code"
        case .codex: (Builder.codexModels.first { $0.id == Builder.codexFastModel }?.label).map { "\($0) through ChatGPT Codex" } ?? "ChatGPT Codex"
        case .pi: "the builder's own model"
        }
    }

    /// Decisions without a decision model: the questions go to a small text model as JSON, and its answers
    /// come back in the same shape Jev's would (`noul`, `choice`/`score` with `probabilities` and
    /// `confidence`), checked against each question so an app can't be handed a made-up option.
    static func decideByText(state: Any, questions: [String: Any]) async throws -> ([String: Any], Double) {
        let stateJSON = (try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys, .fragmentsAllowed]))
            .map { String(decoding: $0, as: UTF8.self) } ?? "\(state)"
        let questionsJSON = (try? JSONSerialization.data(withJSONObject: questions, options: [.sortedKeys]))
            .map { String(decoding: $0, as: UTF8.self) } ?? ""
        // Worded for a small model: Luna got "rm -rf ~" backwards with a terser version of this.
        let system = """
        You answer typed questions about some state, like a calibrated classifier. The questions are JSON, keyed \
        by id; reply with one JSON object with the same keys and nothing else.

        For a question of type "noul", the value is {"noul": p}: p is the probability, from 0 to 1, that the \
        answer to its instructions is yes, judged against its criteria ("true" describes a yes, "false" a no). \
        A clear no is 0.0, a clear yes 1.0.

        For a question of type "choice", the criteria are the options (a description of when each applies, or \
        null). The value is {"choice": option, "probabilities": {option: p, ...}, "confidence": c}: one \
        probability per option, summing to 1; choice is the most likely option; confidence (0 to 1) is how \
        concentrated the probabilities are.

        For a question of type "score", the criteria are ordered levels, lowest first, each describing a \
        situation. The value is {"score": s, "probabilities": {"0": p, "1": p, ...}, "confidence": c}: one \
        probability per level index, summing to 1; s is the probability-weighted index; confidence (0 to 1) is \
        how concentrated the probabilities are.
        """
        let prompt = "State:\n\(stateJSON)\n\nQuestions:\n\(questionsJSON)"
        let (text, cost) = try await complete(prompt: prompt, images: [], system: system, json: true, engineModel: fastModel)
        guard let raw = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw Failure(message: "The model's decision wasn't valid JSON.", cost: cost)
        }
        var answers: [String: Any] = [:]
        for (id, question) in questions {
            guard let q = question as? [String: Any], let type = q["type"] as? String else { continue }
            let given = raw[id] as? [String: Any] ?? [:]
            func clamp(_ value: Any?) -> Double? { (value as? NSNumber).map { min(max($0.doubleValue, 0), 1) } }
            switch type {
            case "noul":
                guard let p = clamp(given["noul"]) else { throw Failure(message: "The model didn't answer \"\(id)\".", cost: cost) }
                answers[id] = ["noul": p]
            case "choice":
                let options = (q["criteria"] as? [String: Any])?.keys.map { $0 } ?? (q["criteria"] as? [String] ?? [])
                var probabilities = (given["probabilities"] as? [String: Any] ?? [:]).reduce(into: [String: Double]()) {
                    if options.contains($1.key), let p = clamp($1.value) { $0[$1.key] = p }
                }
                var choice = given["choice"] as? String
                if choice == nil || !options.contains(choice!) { choice = probabilities.max { $0.value < $1.value }?.key }
                guard let choice else { throw Failure(message: "The model didn't pick an option for \"\(id)\".", cost: cost) }
                if probabilities.isEmpty { probabilities = [choice: 1] }
                let total = probabilities.values.reduce(0, +)
                if total > 0 { probabilities = probabilities.mapValues { $0 / total } }
                answers[id] = ["choice": choice, "probabilities": probabilities,
                               "confidence": clamp(given["confidence"]) ?? probabilities[choice] ?? 1]
            case "score":
                let levels = (q["criteria"] as? [Any])?.count ?? 0
                let top = Double(max(levels - 1, 0))
                // One normalised distribution is the truth; the score is derived from it, so the two can't
                // disagree. The model's own score only stands in when it gave no usable probabilities.
                var probabilities = (given["probabilities"] as? [String: Any] ?? [:]).reduce(into: [String: Double]()) {
                    if let index = Int($1.key), index >= 0, Double(index) <= top, let p = clamp($1.value) { $0[$1.key] = p }
                }
                let total = probabilities.values.reduce(0, +)
                if total > 0 {
                    probabilities = probabilities.mapValues { $0 / total }
                } else if let given = (given["score"] as? NSNumber).map({ min(max($0.doubleValue, 0), top) }) {
                    probabilities = [String(Int(given.rounded())): 1]
                } else {
                    throw Failure(message: "The model didn't rate \"\(id)\".", cost: cost)
                }
                let score = probabilities.reduce(0) { $0 + Double($1.key)! * $1.value }
                answers[id] = ["score": score, "probabilities": probabilities,
                               "confidence": clamp(given["confidence"]) ?? probabilities.values.max() ?? 1]
            default:
                throw Failure(message: "Unknown question type \"\(type)\".", cost: cost)
            }
        }
        return (answers, cost)
    }

    /// Where images come from: OpenRouter's image models with a key; otherwise a picture model on this Mac
    /// (mflux, from Hugging Face), if one was downloaded; otherwise Codex's own image tool, with a ChatGPT
    /// sign-in; otherwise nothing, and Lamp asks the first time an app wants a picture. (Apple's on-device Image Playground has no
    /// programmatic API any more: ImageCreator stopped working in macOS 27.)
    enum ImageRoute { case openRouter, codex, local }

    /// The route as far as can be told without asking anything: for Settings' text. `imageRoute()` is the
    /// one to act on.
    static var imageRoute: ImageRoute? {
        if Provider.hasKey { return .openRouter }
        if ImageModels.ready { return .local }
        if ToolLocator.path(for: .codex) != nil, codexSignedIn != false { return .codex }
        return nil
    }

    /// The route to use now. Codex counts only when it's signed in (the copy inside the ChatGPT app is there
    /// whether or not anyone ever logged in); that's checked at most every few minutes. A model on this Mac
    /// makes pictures from words only, so a request that edits existing pictures skips it.
    static func imageRoute(editing: Bool = false) async -> ImageRoute? {
        if Provider.hasKey { return .openRouter }
        if ImageModels.ready, !editing { return .local }
        if ToolLocator.path(for: .codex) != nil {
            if codexSignedIn == nil || Date().timeIntervalSince(codexChecked) > 300 {
                codexSignedIn = await EngineSignIn.isSignedIn(.codex) ?? true
                codexChecked = Date()
            }
            if codexSignedIn == true { return .codex }
        }
        return nil
    }

    private static var codexSignedIn: Bool?
    private static var codexChecked = Date.distantPast

    /// What's making images, for Settings.
    static var imageRouteName: String? {
        switch imageRoute {
        case .openRouter: "OpenRouter"
        case .codex: "ChatGPT Codex, with your ChatGPT sign-in"
        case .local: "\(ImageModels.chosen?.name ?? "a model") on this Mac"
        case nil: nil
        }
    }

    /// The failure an app gets when nothing can make images: Lamp shows a card asking for a key or a download.
    static let noImageRoute = "Making images needs an OpenRouter key, or a picture model on this Mac. Add one in Lamp → Settings (⌘,)."

    /// Creates or edits an image. `references` are input images to edit or combine. Returns PNG data and
    /// the cost in USD (0 through Codex).
    static func image(prompt: String, references: [Image], aspectRatio: String?,
                      model appChoice: String? = nil) async throws -> (Data, Double) {
        // Someone who picked the Mac's own model over the cloud ones gets it, key or no key.
        let wantsLocal = (appChoice == Icons.localArt || (appChoice == nil && Icons.artModel == Icons.localArt)) && ImageModels.ready
        if wantsLocal, !references.isEmpty {
            throw Failure(message: "\(ImageModels.chosen?.name ?? "The model on this Mac") makes pictures from words and can't edit one. Pick a cloud image model in Lamp → Settings → AI for this.")
        }
        switch wantsLocal ? .local : await imageRoute(editing: !references.isEmpty) {
        case .openRouter: break
        case .codex: return (try await viaCodexImage(prompt: prompt, references: references, aspectRatio: aspectRatio), 0)
        case .local:
            let (width, height) = localSize(aspectRatio)
            return (try await ImageModels.generate(prompt: prompt, width: width, height: height), 0)
        case nil: throw Failure(message: noImageRoute)
        }
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/images")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 240
        request.setValue("Bearer \(KeyStore.openRouterKey ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Lamp", forHTTPHeaderField: "X-Title")
        let imageModel = Icons.artModels.contains { $0.id == appChoice } ? appChoice! : Icons.artModel
        var body: [String: Any] = ["model": imageModel, "prompt": prompt, "n": 1, "output_format": "png"]
        if let aspectRatio { body["aspect_ratio"] = aspectRatio }
        if !references.isEmpty {
            body["input_references"] = references.map {
                ["type": "image_url", "image_url": ["url": "data:\($0.mediaType);base64,\($0.data)"]]
            }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = (obj["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(status)"
            throw Failure(message: Provider.friendlyError("\(status) \(message)"))
        }
        guard let base64 = (obj["data"] as? [[String: Any]])?.first?["b64_json"] as? String,
              let decoded = Data(base64Encoded: base64), NSImage(data: decoded) != nil else {
            throw Failure(message: "The image model didn't return a picture.")
        }
        return (decoded, (obj["usage"] as? [String: Any])?["cost"] as? Double ?? 0)
    }

    /// Pixel sizes for the local models (multiples of 16, about a megapixel).
    private static func localSize(_ aspectRatio: String?) -> (Int, Int) {
        switch aspectRatio {
        case "16:9": (1024, 576)
        case "9:16": (576, 1024)
        case "4:3": (1024, 768)
        case "3:4": (768, 1024)
        case "3:2": (1024, 688)
        case "2:3": (688, 1024)
        default: (1024, 1024)
        }
    }

    /// Codex makes the picture with its built-in image tool and saves it in a scratch folder; reference
    /// images are attached and named in the prompt. Takes about a minute.
    private static func viaCodexImage(prompt: String, references: [Image], aspectRatio: String?) async throws -> Data {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-image-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var files: [String] = []
        for (index, image) in references.enumerated() {
            guard let data = Data(base64Encoded: image.data) else { continue }
            let name = "reference\(index + 1).\(image.mediaType.hasSuffix("png") ? "png" : "jpg")"
            try data.write(to: folder.appendingPathComponent(name))
            files.append(name)
        }
        var request = "Create an image and save it as image.png in the current folder, then reply with just: done.\n\n"
        request += "The image: \(prompt)"
        if let aspectRatio { request += "\n\nAspect ratio \(aspectRatio)." }
        if !files.isEmpty {
            request += "\n\nUse the attached \(files.count == 1 ? "image" : "images") (\(files.joined(separator: ", "))) as "
                + (files.count == 1 ? "the reference: edit or build on it as the description says." : "references.")
        }
        var env: [String: String] = ["PATH": ToolLocator.userPath, "LAMP_TOOL": ToolLocator.path(for: .codex) ?? "codex",
                                     "LAMP_PROMPT": request]
        for (index, file) in files.enumerated() { env["LAMP_FILE_\(index)"] = file }
        let imageArgs = files.indices.map { "-i \"$LAMP_FILE_\($0)\"" }.joined(separator: " ")
        let command = """
        "$LAMP_TOOL" exec --json --ignore-user-config --ignore-rules --skip-git-repo-check --ephemeral \\
          -c sandbox_mode="workspace-write" -c hooks={} -C "$PWD" \(imageArgs) -- "$LAMP_PROMPT"
        """
        var failure: String?
        _ = await Shell.run(command, cwd: folder, env: env) { line in
            for case .failed(let message) in Agent.parse(line, engine: .codex) { failure = message }
        }
        if let failure { throw Failure(message: Provider.friendlyError(failure)) }
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("image.png")), NSImage(data: data) != nil else {
            throw Failure(message: "ChatGPT Codex didn't make the picture. Check it's signed in (Lamp → Settings → Building).")
        }
        return data
    }

    private static func viaOpenRouter(prompt: String, images: [Image], system: String,
                                      model: String, json: Bool = false) async throws -> (String, Double) {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(KeyStore.openRouterKey ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Lamp", forHTTPHeaderField: "X-Title")
        var messages: [[String: Any]] = []
        if !system.trimmed.isEmpty { messages.append(["role": "system", "content": system]) }
        let content: [[String: Any]] = [["type": "text", "text": prompt]] + images.map {
            ["type": "image_url", "image_url": ["url": "data:\($0.mediaType);base64,\($0.data)"]]
        }
        messages.append(["role": "user", "content": content])
        var body: [String: Any] = ["model": model, "messages": messages, "usage": ["include": true]]
        if json {
            // Structured output: the model must return a JSON object, and gets room for a long one (a plan
            // with scripts in it can run to thousands of tokens; a cut-off reply is what breaks apps).
            body["response_format"] = ["type": "json_object"]
            body["max_tokens"] = 16_000
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Anthropic's safety classifier sometimes refuses an ordinary request (finish_reason "content_filter",
        // empty reply, HTTP 200): about 1 in 20 identical benign requests in others' measurements, and more
        // under bursts. It's random, so asking again gets the answer.
        var cost = 0.0
        for attempt in 0..<3 {
            let (data, response) = try await URLSession.shared.data(for: request)
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let choice = (obj["choices"] as? [[String: Any]])?.first
            cost += (obj["usage"] as? [String: Any])?["cost"] as? Double ?? 0
            guard status == 200, let choice else {
                let message = (obj["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(status)"
                throw Failure(message: Provider.friendlyError("\(status) \(message)"))
            }
            let text = (choice["message"] as? [String: Any])?["content"] as? String ?? ""
            if choice["finish_reason"] as? String == "content_filter" {
                if attempt < 2 { try await Task.sleep(for: .milliseconds(400 << attempt)); continue }
                throw Failure(message: "The AI provider's content filter cut the reply off. Try rewording the request.")
            }
            return (text, cost)
        }
        throw Failure(message: "The AI didn't answer.")
    }

    private static func stripFences(_ text: String) -> String {
        var t = text.trimmed
        if t.hasPrefix("```") {
            t = String(t.drop(while: { $0 != "\n" }).dropFirst())
            if let end = t.range(of: "```", options: .backwards) { t = String(t[..<end.lowerBound]) }
        }
        return t.trimmed
    }
}
