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
                                                         schema: schema, timeLimit: left)
            return (try await read(["plan": text], for: r), cost)
        }
    }

    /// One chat completion with tools, sent by lamp's command line (`openRouterChat`, cli/openrouter.mjs): the message
    /// with its tool calls, within the step's deadline, a content filter's cut-off asked again inside it.
    static func openRouterStep(_ body: [String: Any], until deadline: Date) async throws -> ([String: Any], Double) {
        let left = deadline.timeIntervalSinceNow
        guard left >= 1 else { throw OutOfTime() }
        let done = try await LampCLI.ask("openRouterChat", ["key": KeyStore.openRouterKey ?? "", "body": body, "seconds": left])
        if let message = done["message"] as? [String: Any] { return (message, done["cost"] as? Double ?? 0) }
        let trouble = done["trouble"] as? [String: Any] ?? [:]
        if trouble["kind"] as? String == "timeout" { throw OutOfTime(cost: trouble["cost"] as? Double ?? 0) }
        throw AppAI.openRouterFailure(trouble)
    }
}
