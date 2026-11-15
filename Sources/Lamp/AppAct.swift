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
/// shape, with nothing of their own to run. A turn stays on the route its first step took.
enum AppAct {
    /// How long a step may take on any route before its call is taken to have stopped answering: a guard, never a limit
    /// on a real answer, however long the model takes to write it. A turn has no time of its own unless the app gives
    /// it one, which the page sends as each step's `seconds` (`ACT_STEP_SECONDS` in lamp.js, `readStep` in cli/app-ai.mjs).
    static func turnSeconds(for route: AppAI.TextRoute) -> Double { 600 }

    struct Failure: Error, Equatable { let status: Int; let message: String }

    /// A step as lamp's command line checked it (`actStep`): what the other calls take, and `final`, `seconds`, `route`
    /// and `model` for this side.
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

    /// The route a turn's first step takes, or why there's none: the app's text route.
    @MainActor static func firstRoute(appModel: String?) -> Result<AppAI.TextRoute, Failure> {
        choose(AppAI.route(for: appModel))
    }

    static func choose(_ resolved: AppAI.TextRoute) -> Result<AppAI.TextRoute, Failure> {
        guard resolved.available else { return .failure(Failure(status: 501, message: AppAI.noTextRoute)) }
        return .success(resolved)
    }

    /// `LampAI.status(.act)`: what the probe and the first step would say, and where the turn's data would go.
    @MainActor static func status(appModel: String?) -> [String: Any] {
        switch firstRoute(appModel: appModel) {
        case .success(let route):
            return ["available": true, "route": route.label, "where": "remote"]
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
            case .success(let route):
                // A key OpenRouter refuses can't answer a step, as `/ai/status` says too.
                if AppAI.provider(of: route) == "openrouter", let refused = await OpenRouterKeyCheck.problem() {
                    return (200, ["act": false, "route": route.id, "why": refused], 0)
                }
                return (200, ["act": true, "route": route.id, "why": ""], 0)
            case .failure(let failure): return (200, ["act": false, "route": AppAI.route(for: appModel).id, "why": failure.message], 0)
            }
        }
        // A streamed step the page is following (`stream` on lamp.js's act): what it has that the page hasn't.
        if let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let id = body["follow"] as? String {
            return await LiveSteps.follow(id, have: Swift.max(0, body["have"] as? Int ?? 0))
        }
        let streamed = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["stream"] as? Bool == true
        let r: Request
        do { r = try await parse(data) } catch let failure as Failure { return (failure.status, ["error": failure.message], 0) } catch { return (500, ["error": error.localizedDescription], 0) }
        // The model the app asked for, when it can answer; else the app's own choice (`AppAI.textChoice`).
        let chosen = AppAI.textChoice(asked: r["model"] as? String, app: appModel)
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
            switch firstRoute(appModel: chosen) {
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
        // Streamed: each call goes to the page as soon as it's whole, and the page follows the step for the rest.
        if streamed {
            let (id, live) = LiveSteps.start()
            Task { @MainActor in live.finish(await answer(route, r, seconds: seconds, until: deadline, live: live)) }
            return await LiveSteps.follow(id, have: 0)
        }
        return await answer(route, r, seconds: seconds, until: deadline, live: nil)
    }

    /// The step asked of its route, asked again once when its answer can't be used. With `live`, calls go out as they're
    /// written, and once one has gone the answer isn't asked again.
    @MainActor static func answer(_ route: AppAI.TextRoute, _ r: Request, seconds: Double, until deadline: Date, live: LiveSteps.Step?) async -> (Int, [String: Any], Double) {
        let tag = "outside-text-" + String(UUID().uuidString.prefix(8)).lowercased()
        var cost = 0.0
        var retry: String?
        // The only retry for an answer that can't be used: one more attempt with the reason. The adapters don't try
        // again by themselves, except OpenRouter's wait-and-retry when a provider's content filter cuts a reply off,
        // which stays inside the same deadline.
        for attempt in 0..<2 {
            do {
                let (answer, more) = try await ask(route, r, tag: tag, retry: retry, until: deadline, live: live)
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

    /// One attempt on the turn's route, its answer read but not yet asked again: the route's adapter.
    static func ask(_ route: AppAI.TextRoute, _ r: Request, tag: String, retry: String?, until deadline: Date,
                    live: LiveSteps.Step? = nil) async throws -> (Result<[String: Any], ParseProblem>, Double) {
        // A streamed answer's calls, heard as each is whole; what was released and held is read with the answer.
        let heard: (@Sendable ([String: Any]) -> Void)? = live.map { live in { event in if let call = event["call"] as? [String: Any] { live.add(call) } } }
        func streamedRead(_ done: [String: Any]) -> [String: Any] {
            guard live != nil else { return [:] }
            return ["released": done["released"] as? Int ?? 0, "held": done["held"] as? [Any] ?? []]
        }
        func asked(_ way: String, model: String? = nil) async throws -> [String: Any] {
            var given: [String: Any] = ["step": r, "tag": tag, "way": way]
            if let retry { given["retry"] = retry }
            if let model { given["model"] = model }
            return try await LampCLI.ask("actAsk", given)
        }
        func plan(_ way: String) async throws -> (system: String, prompt: String, schema: [String: Any], images: [AppAI.Image]) {
            let done = try await asked(way)
            // The pictures the tools' results showed (`LampAI.picture`), which the prompt names in order.
            let images = (done["images"] as? [[String: Any]] ?? []).compactMap { image -> AppAI.Image? in
                guard let type = image["media_type"] as? String, let data = image["data"] as? String else { return nil }
                return AppAI.Image(mediaType: type, data: data)
            }
            return (done["system"] as? String ?? "", done["prompt"] as? String ?? "", done["schema"] as? [String: Any] ?? [:], images)
        }
        switch route.kind {
        case .openRouter(let model):
            let body = try await asked("chat", model: model)["body"] as? [String: Any] ?? [:]
            let (done, cost) = try await openRouterStep(body, until: deadline, step: live == nil ? nil : r, onEvent: heard)
            return (try await read(["message": done["message"] ?? [:]].merging(streamedRead(done)) { $1 }, for: r), cost)
        case .engine(.pi, _):
            throw AppAI.Failure(message: AppAI.noTextRoute)
        case .engine(let engine, let model):
            let left = deadline.timeIntervalSinceNow
            guard left >= 1 else { throw OutOfTime() }
            let (system, prompt, schema, images) = try await plan("plan")
            let done = try await AppAI.engineAnswer(engine, prompt: prompt, images: images, system: system, model: model,
                                                    schema: schema, timeLimit: left, step: live == nil ? nil : r, onEvent: heard)
            return (try await read(["plan": done["text"] as? String ?? ""].merging(streamedRead(done)) { $1 }, for: r), 0)
        }
    }

    /// One chat completion with tools, sent by lamp's command line (`openRouterChat`, cli/openrouter.mjs): the message
    /// with its tool calls, within the step's deadline, a content filter's cut-off asked again inside it.
    static func openRouterStep(_ body: [String: Any], until deadline: Date, step: Request? = nil,
                               onEvent: (@Sendable ([String: Any]) -> Void)? = nil) async throws -> ([String: Any], Double) {
        let left = deadline.timeIntervalSinceNow
        guard left >= 1 else { throw OutOfTime() }
        var given: [String: Any] = ["key": KeyStore.openRouterKey ?? "", "body": body, "seconds": left]
        if let step { given["step"] = step }
        let done = try await LampCLI.ask("openRouterChat", given, onEvent: onEvent)
        if done["message"] is [String: Any] { return (done, done["cost"] as? Double ?? 0) }
        let trouble = done["trouble"] as? [String: Any] ?? [:]
        if trouble["kind"] as? String == "timeout" { throw OutOfTime(cost: trouble["cost"] as? Double ?? 0) }
        throw AppAI.openRouterFailure(trouble)
    }
}

/// Steps being streamed (`stream` on lamp.js's act), by id: each one's calls as they're released, and its answer once it's
/// done. The page asks for what's new (`follow`) until it has the answer; a step nobody follows for a few minutes is let go.
@MainActor enum LiveSteps {
    /// One streamed step. Its calls come from lamp's command line as events, off the main thread, in order.
    final class Step: @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [[String: Any]] = []
        private var done: (Int, [String: Any], Double)?
        var seen = Date()

        func add(_ call: [String: Any]) { lock.lock(); calls.append(call); lock.unlock() }
        func finish(_ answer: (Int, [String: Any], Double)) { lock.lock(); done = answer; lock.unlock() }
        func state() -> ([[String: Any]], (Int, [String: Any], Double)?) { lock.lock(); defer { lock.unlock() }; return (calls, done) }
    }

    private static var steps: [String: Step] = [:]

    static func start() -> (String, Step) {
        steps = steps.filter { Date().timeIntervalSince($0.value.seen) < 300 }
        let id = "st" + String(UUID().uuidString.prefix(12)).lowercased()
        let step = Step()
        steps[id] = step
        return (id, step)
    }

    /// What the page hasn't had (`have` calls in): waits for a new call or the answer, 50 seconds at most, so every way
    /// a page reaches Lamp carries it. The answer comes with the calls it adds (those held back as failures) and its cost.
    static func follow(_ id: String, have: Int) async -> (Int, [String: Any], Double) {
        guard let step = steps[id] else { return (404, ["error": "This step is over."], 0) }
        let have = Swift.max(0, have)
        step.seen = Date()
        let until = Date().addingTimeInterval(50)
        var (calls, done) = step.state()
        while calls.count <= have, done == nil, Date() < until {
            try? await Task.sleep(for: .milliseconds(100))
            (calls, done) = step.state()
        }
        let new = Array(calls.dropFirst(Swift.min(have, calls.count)))
        guard let (status, json, cost) = done else { return (200, ["stream": id, "more": true, "calls": new], 0) }
        steps[id] = nil
        var answer = json
        answer["stream"] = id
        answer["more"] = false
        answer["calls"] = new + (json["calls"] as? [[String: Any]] ?? [])
        return (status, answer, cost)
    }
}
