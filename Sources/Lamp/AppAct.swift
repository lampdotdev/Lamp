import Foundation

/// `/ai/act`, the model's side of `LampAI.act` in lamp.js: one step of an app's agent loop. The page runs its own tools
/// and keeps the turn; each request here carries the whole turn so far and gets back either the calls to make next or
/// the reply. Nothing is kept between steps, so any of the page's hosts can carry it and a lost request loses nothing.
///
/// What the model is told and how its answer is read and checked is lamp's command line's (cli/app-ai.mjs, through
/// `LampCLI`), the one copy, which lamp's own answers use too: the step as the page sent it (`actStep`), what its route
/// is asked (`actAsk`) and the answer read (`actRead`). What's Lamp's own is here: which route answers, its time, and
/// asking it. Every text route answers, each its own way, and each answer is read into the same calls-or-reply:
/// OpenRouter with its tool calling; Claude Code and Codex with a fresh run per step that must answer in the step's JSON
/// shape, with nothing of their own to run; a GGUF model on this Mac held to that shape by llama.cpp's
/// `response_format`; an MLX model with mlx_lm.server's tool calling where its version has it, otherwise asked for the
/// shape in words. A turn stays on the route its first step took.
enum AppAct {
    /// The turn's time on a route: OpenRouter answers a step in a few seconds; Claude Code and Codex start a program for
    /// every step, and a model on this Mac answers more slowly, so they get longer, never more than the step allows.
    static func turnSeconds(for route: AppAI.TextRoute) -> Double {
        if case .openRouter = route.kind { return 25 }
        return 60
    }

    struct Failure: Error, Equatable { let status: Int; let message: String }

    /// A step as lamp's command line checked it (`actStep`): what the other calls take, and `final`, `seconds` and
    /// `route` for this side.
    typealias Request = [String: Any]

    static func parse(_ data: Data) async throws -> Request {
        let done = try await LampCLI.ask("actStep", ["text": String(decoding: data, as: UTF8.self)])
        if let refused = done["refused"] as? [String: Any] {
            throw Failure(status: refused["status"] as? Int ?? 400, message: refused["error"] as? String ?? "That step can't be taken.")
        }
        guard let step = done["step"] as? Request else { throw Failure(status: 500, message: "Lamp couldn't read that step.") }
        return step
    }

    /// The model's answer, read and checked: `{calls}` or `{reply, ask, choices?}`, or the problem to ask again with.
    static func read(_ given: [String: Any], for r: Request) async throws -> Result<[String: Any], ParseProblem> {
        var given = given
        given["step"] = r
        let done = try await LampCLI.ask("actRead", given)
        if let answer = done["answer"] as? [String: Any] { return .success(answer) }
        return .failure(ParseProblem(done["problem"] as? String ?? "It couldn't be read."))
    }

    struct ParseProblem: Error { let reason: String; init(_ reason: String) { self.reason = reason } }

    // MARK: Routes

    /// Whether this route can take a step, and if not, the sentence the page gets.
    static func refusal(for route: AppAI.TextRoute) -> String? {
        route.available ? nil : AppAI.noTextRoute
    }

    /// The route a turn's first step takes, or why there's none. It's the app's text route, with one difference: an
    /// app set to a model on this Mac (by its own choice, Settings', or pi building with one) has its actions refused
    /// while that model can't answer, rather than sent to a service the person didn't choose for them.
    @MainActor static func firstRoute(appModel: String?) -> Result<AppAI.TextRoute, Failure> {
        let saved = appModel ?? UserDefaults.standard.string(forKey: "appModel")
        let piLocal = Builder.engine == .pi && Builder.piProvider == Builder.localProvider ? "local:\(Builder.piModel)" : nil
        return choose(wanted: wanted((saved ?? piLocal).map(AppAI.canonicalRoute), among: AppAI.allTextRoutes), resolved: AppAI.route(for: appModel))
    }

    /// The route chosen by id, as it stands. A model on this Mac that's been removed is in no list of routes, so it's
    /// made up here as one that can't answer, so that it's still known to be a model on this Mac.
    static func wanted(_ id: String?, among routes: [AppAI.TextRoute]) -> AppAI.TextRoute? {
        guard let id else { return nil }
        if let route = routes.first(where: { $0.id == id }) { return route }
        guard id.hasPrefix("local:") else { return nil }
        let model = String(id.dropFirst("local:".count))
        return AppAI.TextRoute(id: id, label: model, group: "Native Mac AI", name: model,
                               kind: .localModel(provider: "local", model: model), available: false)
    }

    static func choose(wanted: AppAI.TextRoute?, resolved: AppAI.TextRoute) -> Result<AppAI.TextRoute, Failure> {
        func local(_ route: AppAI.TextRoute) -> Bool { if case .localModel = route.kind { return true }; return false }
        if let wanted, local(wanted), !wanted.available, !(local(resolved) && resolved.available) {
            return .failure(Failure(status: 501, message: "This app is set to use \(wanted.name) on this Mac, which can't answer now. Choose it again, or another AI, in Lamp."))
        }
        guard resolved.available else { return .failure(Failure(status: 501, message: AppAI.noTextRoute)) }
        return .success(resolved)
    }

    /// `LampAI.status(.act)`: what the probe and the first step would say, and where the turn's data would go.
    @MainActor static func status(appModel: String?) -> [String: Any] {
        switch firstRoute(appModel: appModel) {
        case .success(let route):
            let local: Bool = { if case .localModel = route.kind { return true }; return false }()
            return ["available": true, "route": route.label, "where": local ? "onDevice" : "remote"]
        case .failure(let failure):
            return ["available": false, "where": "unknown", "reason": failure.message, "setup": "lamp"]
        }
    }

    /// One step, end to end: the page's request, the route (pinned for the turn by its id once the first step chose
    /// it), the model, its answer checked. Returns the status, the JSON and what was billed.
    @MainActor static func step(_ data: Data, appModel: String?) async -> (Int, [String: Any], Double) {
        let started = Date()
        if let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], body["probe"] as? Bool == true {
            switch firstRoute(appModel: appModel) {
            case .success(let route): return (200, ["act": true, "route": route.id, "why": ""], 0)
            case .failure(let failure): return (200, ["act": false, "route": AppAI.route(for: appModel).id, "why": failure.message], 0)
            }
        }
        let r: Request
        do { r = try await parse(data) } catch let failure as Failure { return (failure.status, ["error": failure.message], 0) } catch { return (500, ["error": error.localizedDescription], 0) }
        let route: AppAI.TextRoute
        if let pinned = r["route"] as? String {
            // Read the way a saved choice is: Codex's route is named for its first model once Codex has listed them,
            // which its own first run does, so the id a turn started with may have moved on to that name.
            let pinned = AppAI.canonicalRoute(pinned)
            guard let same = AppAI.allTextRoutes.first(where: { $0.id == pinned }), same.available else {
                return (409, ["error": "The AI this turn started with can't answer now. Try again."], 0)
            }
            route = same
        } else {
            switch firstRoute(appModel: appModel) {
            case .success(let first): route = first
            case .failure(let failure): return (failure.status, ["error": failure.message], 0)
            }
        }
        if let refused = refusal(for: route) { return (501, ["error": refused], 0) }
        // One deadline for the whole step, from the seconds the page has left and never past the route's own: every
        // attempt below (a call asked for again, a content-filter retry, its wait) gets only what's left of it, none
        // starts once it has passed, and a Claude Code or Codex run still going then is stopped.
        let seconds = turnSeconds(for: route)
        let deadline = started.addingTimeInterval(Swift.min(r["seconds"] as? Double ?? 60, seconds))
        let tag = "outside-text-" + String(UUID().uuidString.prefix(8)).lowercased()
        var cost = 0.0
        var retry: String?
        // The only retry for an answer that can't be used: one more attempt with the reason. The adapters don't try
        // again by themselves, except OpenRouter's wait-and-retry when a provider's content filter cuts a reply off,
        // which stays inside the same deadline.
        for attempt in 0..<2 {
            do {
                let (answer, more) = try await ask(route, r, tag: tag, retry: retry, until: deadline)
                cost += more
                switch answer {
                case .success(let parsed):
                    var json = parsed
                    json["route"] = route.id
                    json["seconds"] = seconds
                    return (200, json, cost)
                case .failure(let problem):
                    // Asked once more with the reason; a second miss is a reply that says it couldn't, so the page
                    // never sees a call that doesn't fit.
                    if attempt == 0 { retry = problem.reason; continue }
                    return (200, ["reply": "I couldn't work out how to do that.", "ask": false, "route": route.id, "seconds": seconds,
                                  "trouble": problem.reason], cost)
                }
            } catch let late as OutOfTime {
                return (504, ["error": "This step ran out of time."], cost + late.cost)
            } catch let failure as AppAI.Failure {
                // A run stopped at the deadline says so in its own words; it's the step's time that ran out.
                if Date() >= deadline { return (504, ["error": "This step ran out of time."], cost + failure.cost) }
                return (502, ["error": failure.message], cost + failure.cost)
            } catch {
                if Date() >= deadline { return (504, ["error": "This step ran out of time."], cost) }
                return (502, ["error": "Couldn't reach the AI: \(error.localizedDescription)"], cost)
            }
        }
        return (502, ["error": "The AI didn't answer."], cost)
    }

    /// The step's deadline passed (or less than a second of it was left) before an attempt could start.
    struct OutOfTime: Error { var cost = 0.0 }

    /// mlx-lm passes the tools to the model's chat template, and reads its tool calls back, from this version on.
    static let mlxToolsSince = [0, 30, 4]

    static func mlxTakesTools(_ version: String?) -> Bool {
        guard let version else { return false }
        let parts = version.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        for (have, need) in zip(parts + [0, 0, 0], mlxToolsSince) where have != need { return have > need }
        return true
    }

    /// Whether this MLX model's calls come back as tool calls: the version must pass the tools on, and mlx-lm must have a
    /// parser for the model's chat template. Without one the server hands a call back as plain text, which would read
    /// as a finished reply, so such a model is asked for the JSON plan instead.
    static func mlxNativeTools(version: String?, model folder: URL?) -> Bool {
        guard mlxTakesTools(version), let folder else { return false }
        return LocalModels.mlxToolParser(in: folder) != nil
    }

    /// One attempt on the turn's route, its answer read but not yet asked again: the route's adapter.
    static func ask(_ route: AppAI.TextRoute, _ r: Request, tag: String, retry: String?, until deadline: Date) async throws -> (Result<[String: Any], ParseProblem>, Double) {
        func asked(_ way: String, model: String? = nil) async throws -> [String: Any] {
            var given: [String: Any] = ["step": r, "tag": tag, "way": way]
            if let retry { given["retry"] = retry }
            if let model { given["model"] = model }
            return try await LampCLI.ask("actAsk", given)
        }
        func plan(_ way: String) async throws -> (system: String, prompt: String, schema: [String: Any]) {
            let done = try await asked(way)
            return (done["system"] as? String ?? "", done["prompt"] as? String ?? "", done["schema"] as? [String: Any] ?? [:])
        }
        switch route.kind {
        case .openRouter(let model):
            let body = try await asked("chat", model: model)["body"] as? [String: Any] ?? [:]
            let (message, cost) = try await openRouterStep(body, until: deadline)
            return (try await read(["message": message], for: r), cost)
        case .engine(.pi, _):
            throw AppAI.Failure(message: AppAI.noTextRoute)
        case .engine(let engine, let model):
            let left = deadline.timeIntervalSinceNow
            guard left >= 1 else { throw OutOfTime() }
            let (system, prompt, schema) = try await plan("plan")
            let (text, cost) = try await AppAI.viaEngine(engine, prompt: prompt, images: [], system: system, model: model,
                                                         schema: schema, timeLimit: left, sealed: true)
            return (try await read(["plan": text], for: r), cost)
        case .localModel(_, let model):
            let base = try await LocalModels.shared.ensureServer(for: model)
            let left = deadline.timeIntervalSinceNow
            guard left >= 1 else { throw OutOfTime() }
            guard LocalModels.model(model)?.format == .mlx else {
                // llama.cpp holds the answer to the shape by itself. A model that thinks first (Qwen) is asked not to:
                // the schema leaves no room for the thinking, and a small model on this Mac can think past the
                // turn's minute before it gives the step's few lines. Templates without the switch ignore it.
                let (system, prompt, schema) = try await plan("plan")
                let (text, _) = try await AppAI.viaOpenAICompatible("\(base)/v1/chat/completions", key: LocalModels.apiKey, prompt: prompt, images: [],
                                                                    system: system, model: model, schema: schema, timeout: left,
                                                                    templateArgs: ["enable_thinking": false])
                return (try await read(["plan": text], for: r), 0)
            }
            if mlxNativeTools(version: LocalModels.mlxVersion, model: LocalModels.model(model)?.files.first) {
                var body = try await asked("chat")["body"] as? [String: Any] ?? [:]
                body["model"] = model
                if r["final"] as? Bool == true { body["tools"] = nil }
                return (try await read(["message": try await localChat(base, body, timeout: left)], for: r), 0)
            }
            // An older mlx-lm takes neither tools nor a schema: the shape is asked for in words and checked all the same.
            let (system, prompt, _) = try await plan("words")
            let (text, _) = try await AppAI.viaOpenAICompatible("\(base)/v1/chat/completions", key: LocalModels.apiKey, prompt: prompt, images: [],
                                                                system: system, model: model, timeout: left)
            return (try await read(["plan": text], for: r), 0)
        }
    }

    /// One chat completion with tools from a model server on this Mac: the message, with its tool calls.
    static func localChat(_ base: String, _ body: [String: Any], timeout: TimeInterval) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "\(base)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(LocalModels.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200, var message = (obj["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any] else {
            throw AppAI.Failure(message: (obj["error"] as? [String: Any])?["message"] as? String ?? "The local model didn't answer.")
        }
        // Reasoning models may wrap their thinking in <think>…</think>; only the answer is a reply.
        if let text = message["content"] as? String {
            message["content"] = text.replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
        }
        return message
    }

    /// One chat completion with tools. Its own call, not `viaOpenRouter`'s, since what comes back is the message
    /// with its tool calls rather than text. The content-filter retry is the same, inside the same deadline.
    static func openRouterStep(_ body: [String: Any], until deadline: Date) async throws -> ([String: Any], Double) {
        guard deadline.timeIntervalSinceNow >= 1 else { throw OutOfTime() }
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(KeyStore.openRouterKey ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Lamp", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        var cost = 0.0
        for attempt in 0..<3 {
            let left = deadline.timeIntervalSinceNow
            guard left >= 1 else { throw OutOfTime(cost: cost) }
            request.timeoutInterval = left
            let (data, response) = try await URLSession.shared.data(for: request)
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            cost += (obj["usage"] as? [String: Any])?["cost"] as? Double ?? 0
            guard status == 200, let choice = (obj["choices"] as? [[String: Any]])?.first else {
                throw AppAI.Failure(message: Provider.friendlyError(status: status, reply: obj, from: Provider.openRouter), cost: cost)
            }
            if choice["finish_reason"] as? String == "content_filter" {
                if attempt < 2 {
                    let wait = min(Double(400 << attempt) / 1000, max(0, deadline.timeIntervalSinceNow))
                    try await Task.sleep(for: .seconds(wait))
                    continue
                }
                throw AppAI.Failure(message: "The AI provider's content filter cut the reply off. Try rewording the request.", cost: cost)
            }
            return (choice["message"] as? [String: Any] ?? [:], cost)
        }
        throw AppAI.Failure(message: "The AI didn't answer.", cost: cost)
    }
}
