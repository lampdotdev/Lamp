import Foundation
import AppKit
import Network

/// A tiny HTTP server on 127.0.0.1 that lets generated apps use Forge's AI
/// without ever seeing the key. Apps call it through `ForgeAI` (see Template.forgeSupportSwift).
final class Gateway: @unchecked Sendable {
    static let port: UInt16 = 47811

    struct Request {
        let method: String
        let path: String
        let headers: [String: String]   // lowercased names
        let body: Data
    }

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "dev.forge.gateway")
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
            self?.receive(connection, buffer: Data())
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, done, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = Self.parse(buffer) {
                Task {
                    let (status, json) = await self.handler(request)
                    self.respond(connection, status: status, json: json)
                }
            } else if done || error != nil || buffer.count > 40_000_000 {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    private func respond(_ connection: NWConnection, status: Int, json: [String: Any]) {
        let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
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
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let body = data[split.upperBound...]
        guard body.count >= length else { return nil }
        return Request(method: String(start[0]), path: String(start[1]), headers: headers, body: Data(body.prefix(length)))
    }
}

/// Runs an in-app AI request with whatever Forge is connected to.
enum AppAI {
    static let models: [(id: String, label: String, openRouter: String)] = [
        ("claude-fable-5-1", "Smartest, priciest (Claude Fable)", "anthropic/claude-fable-5.1"),
        ("opus", "Best at coding (Claude Opus)", "anthropic/claude-opus-5.5"),
        ("sonnet", "Faster & cheaper (Claude Sonnet)", "anthropic/claude-sonnet-5.5"),
        ("haiku", "Fastest, cheapest (Claude Haiku)", "anthropic/claude-haiku-4.5"),
    ]

    /// Sonnet: Haiku is cheaper but noticeably worse, so it's only used when someone picks it.
    static var defaultModel: (id: String, label: String, openRouter: String) { models.first { $0.id == "sonnet" }! }

    static var model: (id: String, label: String, openRouter: String) {
        let id = UserDefaults.standard.string(forKey: "appModel") ?? defaultModel.id
        return models.first { $0.id == id } ?? defaultModel
    }

    /// The text model for one app: its own choice (info panel), or the default from Settings.
    static func model(for choice: String?) -> (id: String, label: String, openRouter: String) {
        models.first { $0.id == choice } ?? model
    }

    struct Failure: Error { let message: String }

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

    /// `model` overrides the in-app model (an OpenRouter model ID), e.g. for Forge's own import review.
    /// `appModel` is an app's own text model (an id from `models`), when it has one.
    static func complete(prompt: String, images: [Image], system: String, json: Bool,
                         model: String? = nil, appModel: String? = nil) async throws -> (String, Double) {
        let chosen = Self.model(for: appModel)
        var system = system
        if json { system += "\n\nRespond with only valid JSON. No prose, no code fences." }
        let (text, cost): (String, Double)
        if Provider.hasKey {
            (text, cost) = try await viaOpenRouter(prompt: prompt, images: images, system: system,
                                                   model: model ?? chosen.openRouter)
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
            // No OpenRouter key: use the Claude Code, Codex or opencode sign-in that builds apps.
            (text, cost) = try await viaEngine(Builder.engine, prompt: prompt, images: images, system: system,
                                               model: chosen.id)
        } else {
            throw Failure(message: "Apps' AI features need an OpenRouter key, or a working builder. Set one up in Forge → Settings (⌘,).")
        }
        return (json ? stripFences(text) : text, cost)
    }

    /// One-shot pi call (no tools, no session) with the builder's provider and model. Covers every
    /// provider pi supports, including "My pi setup" subscriptions.
    private static func viaPi(prompt: String, images: [Image], system: String) async throws -> (String, Double) {
        guard Agent.executable != nil else { throw Failure(message: "Forge's AI builder is missing. Download Forge again.") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("forge-ai-\(UUID().uuidString)")
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
        env["FORGE_SYSTEM"] = system.isEmpty ? "You are a helpful assistant inside a Mac app." : system
        let fileArgs = files.indices.map { "\"@$FORGE_FILE_\($0)\"" }.joined(separator: " ")
        let command = """
        "$FORGE_PI" --mode json --provider "$FORGE_PROVIDER" --model "$FORGE_MODEL" --no-tools --no-session \\
          --no-extensions --no-skills --no-prompt-templates --no-context-files --no-approve \\
          --system-prompt "$FORGE_SYSTEM" -- \(fileArgs) "$FORGE_PROMPT"
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
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("forge-ai-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var files: [String] = []
        for (index, image) in images.enumerated() {
            guard let data = Data(base64Encoded: image.data) else { continue }
            let name = "image\(index).\(image.mediaType.hasSuffix("png") ? "png" : "jpg")"
            try data.write(to: folder.appendingPathComponent(name))
            files.append(name)
        }
        var env: [String: String] = ["PATH": ToolLocator.userPath, "FORGE_TOOL": ToolLocator.path(for: engine) ?? "",
                                     "FORGE_SYSTEM": system.isEmpty ? "You are a helpful assistant inside a Mac app." : system,
                                     "FORGE_PROMPT": prompt]
        for (index, file) in files.enumerated() { env["FORGE_FILE_\(index)"] = file }
        let command: String
        switch engine {
        case .claude:
            // Claude Code takes images by reading them, so it gets the Read tool and their names.
            if !files.isEmpty { env["FORGE_PROMPT"] = prompt + "\n\n(Images: " + files.joined(separator: ", ") + ". Read them.)" }
            env["FORGE_MODEL"] = model   // "haiku", "sonnet" or "opus": Claude Code's own aliases
            command = """
            "$FORGE_TOOL" -p "$FORGE_PROMPT" --output-format stream-json --verbose --no-session-persistence \\
              --restricted --strict-mcp-config --disable-slash-commands \\
              --tools \(files.isEmpty ? "''" : "Read --allowedTools Read") --model "$FORGE_MODEL" --system-prompt "$FORGE_SYSTEM"
            """
        case .codex:
            env["FORGE_CODEX_INSTRUCTIONS"] = "developer_instructions="
                + Agent.tomlString(env["FORGE_SYSTEM"]! + "\n\nAnswer directly. Don't run commands or change files.")
            let imageArgs = files.indices.map { "-i \"$FORGE_FILE_\($0)\"" }.joined(separator: " ")
            command = """
            "$FORGE_TOOL" exec --json --ignore-user-config --ignore-rules --skip-git-repo-check --ephemeral \\
              -s read-only -c hooks={} -c model_reasoning_effort="low" -c "$FORGE_CODEX_INSTRUCTIONS" \(imageArgs) -- "$FORGE_PROMPT"
            """
        case .opencode:
            env["FORGE_PROMPT"] = "Instructions (follow these):\n\(env["FORGE_SYSTEM"]!)\n\nRequest:\n\(prompt)"
            env["OPENCODE_CONFIG_CONTENT"] = #"{"permission":{"edit":"deny","bash":"deny","webfetch":"deny"}}"#
            let fileArgs = files.indices.map { "-f \"$FORGE_FILE_\($0)\"" }.joined(separator: " ")
            command = "\"$FORGE_TOOL\" run --format json \"$FORGE_PROMPT\" \(fileArgs)"
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
            let name = choice.provider == "typesafe" ? "a TypeSafe" : "an OpenRouter"
            throw Failure(message: "Decisions need \(name) key. Add one in Forge → Settings (⌘,) → AI.")
        }
        let endpoint = choice.provider == "typesafe" ? "https://api.typesafe.ai/v1/systemone"
                                                     : "https://openrouter.ai/api/v1/systemone"
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Forge", forHTTPHeaderField: "X-Title")
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

    /// Creates or edits an image with the image model from Settings, via OpenRouter's image API.
    /// `references` are input images to edit or combine. Returns PNG data and the cost in USD.
    static func image(prompt: String, references: [Image], aspectRatio: String?,
                      model appChoice: String? = nil) async throws -> (Data, Double) {
        guard Provider.hasKey else {
            throw Failure(message: "Forge needs an OpenRouter key before apps can use AI. Add one in Forge → Settings (⌘,).")
        }
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/images")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 240
        request.setValue("Bearer \(KeyStore.openRouterKey ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Forge", forHTTPHeaderField: "X-Title")
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

    private static func viaOpenRouter(prompt: String, images: [Image], system: String,
                                      model: String) async throws -> (String, Double) {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(KeyStore.openRouterKey ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Forge", forHTTPHeaderField: "X-Title")
        var messages: [[String: Any]] = []
        if !system.trimmed.isEmpty { messages.append(["role": "system", "content": system]) }
        let content: [[String: Any]] = [["type": "text", "text": prompt]] + images.map {
            ["type": "image_url", "image_url": ["url": "data:\($0.mediaType);base64,\($0.data)"]]
        }
        messages.append(["role": "user", "content": content])
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "messages": messages, "usage": ["include": true],
        ] as [String: Any])

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
