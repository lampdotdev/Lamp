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
    /// The in-app text models with an OpenRouter key (or Claude Code answering without one).
    static let anthropicModels: [(id: String, label: String, openRouter: String)] = [
        ("claude-fable-5-1", "Smartest, priciest (Claude Fable)", "anthropic/claude-fable-5.1"),
        ("opus", "Best at coding (Claude Opus)", "anthropic/claude-opus-5.5"),
        ("sonnet", "Faster & cheaper (Claude Sonnet)", "anthropic/claude-sonnet-5.5"),
        ("haiku", "Fastest, cheapest (Claude Haiku)", "anthropic/claude-haiku-4.5"),
    ]

    /// Without an OpenRouter key, Codex answers for apps with its own models, so those are the choices.
    static var answersViaCodex: Bool { !Provider.hasKey && Builder.engine == .codex }

    static var models: [(id: String, label: String, openRouter: String)] {
        guard answersViaCodex else { return anthropicModels }
        let codex = Builder.codexModels.dropFirst().map { (id: $0.id, label: $0.label, openRouter: "") }
        return codex.isEmpty ? [("", "Codex's default", "")] : Array(codex)
    }

    /// Sonnet: Haiku is cheaper but noticeably worse, so it's only used when someone picks it.
    static var defaultModel: (id: String, label: String, openRouter: String) {
        answersViaCodex ? models[0] : anthropicModels.first { $0.id == "sonnet" }!
    }

    static var model: (id: String, label: String, openRouter: String) {
        let id = UserDefaults.standard.string(forKey: "appModel") ?? defaultModel.id
        return models.first { $0.id == id } ?? defaultModel
    }

    /// The text model for one app: its own choice (info panel), or the default from Settings.
    static func model(for choice: String?) -> (id: String, label: String, openRouter: String) {
        models.first { $0.id == choice } ?? model
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
                         model: String? = nil, appModel: String? = nil) async throws -> (String, Double) {
        let chosen = Self.model(for: appModel)
        var system = system
        if json { system += "\n\nRespond with only valid JSON. No prose, no code fences." }
        var (text, cost) = try await dispatch(prompt: prompt, images: images, system: system, json: json, model: model, chosen: chosen)
        guard json else { return (text, cost) }
        // A JSON reply that doesn't parse (cut off, or wrapped in prose) is useless to the app: ask once more,
        // through the same provider, saying so, before giving up. Both attempts are billed, so the cost goes
        // with the failure too.
        var reply = stripFences(text)
        if !isJSON(reply) {
            let again = "\(prompt)\n\nYour previous reply was not valid JSON (it may have been cut off). Reply with the complete JSON only."
            do {
                let (retry, more) = try await dispatch(prompt: again, images: images, system: system, json: true, model: model, chosen: chosen)
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

    /// One request through whichever provider the app's AI is set up with.
    private static func dispatch(prompt: String, images: [Image], system: String, json: Bool, model: String?,
                                 chosen: (id: String, label: String, openRouter: String)) async throws -> (String, Double) {
        var (text, cost): (String, Double)
        if Provider.hasKey {
            (text, cost) = try await viaOpenRouter(prompt: prompt, images: images, system: system,
                                                   model: model ?? chosen.openRouter, json: json)
        } else if Builder.engine == .pi {
            // No OpenRouter key: use whatever builds apps.
            switch Builder.piProvider {
            case Builder.localProvider:
                let base = try await LocalModels.shared.ensureServer(for: Builder.piModel)
                (text, cost) = try await viaOpenAICompatible("\(base)/v1/chat/completions", key: nil,
                                                             prompt: prompt, images: images, system: system, model: Builder.piModel)
            case "ext-ollama", "ext-lmstudio":
                let port = Builder.piProvider == "ext-ollama" ? 11434 : 1234
                (text, cost) = try await viaOpenAICompatible("http://127.0.0.1:\(port)/v1/chat/completions", key: nil,
                                                             prompt: prompt, images: images, system: system, model: Builder.piModel)
            default:
                (text, cost) = try await viaPi(prompt: prompt, images: images, system: system)
            }
        } else if ToolLocator.path(for: Builder.engine) != nil {
            // No OpenRouter key: use the Claude Code or Codex sign-in that builds apps.
            (text, cost) = try await viaEngine(Builder.engine, prompt: prompt, images: images, system: system,
                                               model: chosen.id)
        } else {
            throw Failure(message: "Apps' AI features need an OpenRouter key, or a working builder. Set one up in Lamp → Settings (⌘,).")
        }
        return (text, cost)
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
    static let decisionModels: [(id: String, label: String, provider: String, model: String)] = [
        ("openrouter:jev-latest", "Jev via OpenRouter", "openrouter", "jev-latest"),
        ("typesafe:jev-latest", "Jev via TypeSafe", "typesafe", "jev-latest"),
        ("typesafe:jev-preview", "Jev preview via TypeSafe", "typesafe", "jev-preview"),
    ]

    static var decisionModel: (id: String, label: String, provider: String, model: String) {
        let saved = UserDefaults.standard.string(forKey: "decisionModel") ?? ""
        if let chosen = decisionModels.first(where: { $0.id == saved }) { return chosen }
        // Default to whichever key exists, preferring OpenRouter.
        return KeyStore.openRouterKey == nil && KeyStore.key(for: "typesafe") != nil ? decisionModels[1] : decisionModels[0]
    }

    /// Sends `state` and typed `questions` (TypeSafe's System One format) to the decision model.
    /// Returns the answers keyed like the questions, and the cost in USD.
    static func decide(state: Any, questions: [String: Any],
                       model appChoice: String? = nil) async throws -> ([String: Any], Double) {
        let choice = decisionModels.first { $0.id == appChoice } ?? decisionModel
        guard let key = KeyStore.key(for: choice.provider) else {
            // No decision model: a small text model answers the same questions in JSON instead.
            if canAnswer { return try await decideByText(state: state, questions: questions) }
            let name = choice.provider == "typesafe" ? "a TypeSafe" : "an OpenRouter"
            throw Failure(message: "Decisions need \(name) key. Add one in Lamp → Settings (⌘,) → AI.")
        }
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
        case .codex: (Builder.codexModels.first { $0.id == Builder.codexFastModel }?.label).map { "\($0) through Codex" } ?? "Codex"
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
        let (text, cost) = try await complete(prompt: prompt, images: [], system: system, json: true, appModel: fastModel)
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
        case .codex: "Codex, with your ChatGPT sign-in"
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
            throw Failure(message: "Codex didn't make the picture. Check it's signed in (Lamp → Settings → Building).")
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
