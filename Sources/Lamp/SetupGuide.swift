import Foundation

/// A device's setup step done for the person (Do It for Me), followed from a skill. The skill says in its frontmatter
/// which step of which device it does (`SetupGuides`), carries its steps as data (a `lamp-setup` block), and this runs
/// them. Nothing here knows any one maker: the steps say what to send, what to wait for and what to tell the person,
/// over a connection the skill names (`SetupConnections`): plain HTTP, sent the way a device integration's steps are,
/// or a socket protocol a maker publishes, written once in Swift for every guide that uses it.
///
/// Lamp says only what it saw happen, and that is kept here rather than left to each skill: a `confirm` claims nothing,
/// a `rejoin` says the device is back only once it saw it stop answering and answer again, and a `handoff` completes
/// nothing. A guide never marks one of the setup's own steps done: once it ends, the setup checks its step again
/// itself (`GuidedSetup.onFinish`).
struct SetupSteps {
    enum Kind: String { case connect, request, wait, confirm, rejoin, handoff }

    /// Something read from the device, in the shape of the connection it's read over.
    enum Check {
        /// A request over a socket, and the value at a dotted path in its answer ("apps.id": every app's id).
        case socket(uri: String, payload: [String: Any], json: String, equals: String?, contains: String?)
        /// Conditions as a device integration's step checks them (`Integration.Condition`): a request and a JSON or XML
        /// value in its answer, or a port that takes a connection.
        case http([Integration.Condition])
    }

    struct Step {
        let kind: Kind
        var doing: String?
        var ask: String?
        var done: String?
        var refused: String?
        var failed: String?
        var continueOnFailure = false
        /// For `request` over a socket.
        var uri: String?
        var payload: [String: Any] = [:]
        /// For `request` over HTTP: a device integration's actions.
        var run: [IntegrationAction] = []
        /// For `wait`: what must hold before the steps go on.
        var until: Check?
        /// For `request` and `rejoin`: what, when it holds, means the step has nothing left to do (the device's
        /// developer mode is on already), so a request isn't sent again and a restart isn't waited for.
        var unless: Check?
        var every: Double = 3
        var button: String?
        var link: (title: String, url: URL)?

        /// How many changes a `request` sends the device: one over a socket, each request but a GET over HTTP.
        var changes: Int { uri != nil ? 1 : run.filter { ($0.http?.method ?? "GET").uppercased() != "GET" }.count }
    }

    let connection: String
    /// What Lamp does and what the person does, in a line beside Do It for Me.
    var offer: String?
    /// For an HTTP connection: what the device answering means, for `connect` and `rejoin`.
    var reach: [Integration.Condition] = []
    let steps: [Step]

    /// The steps in a skill's `lamp-setup` block, or why they can't be followed. `fields` are what the person types in
    /// the device's own setup, which an HTTP request may name (`{field:password}`) where a device integration's may.
    static func parse(skill body: String, fields: Set<String> = []) -> Result<SetupSteps, Problem> {
        guard let start = body.range(of: "```lamp-setup\n"),
              let end = body.range(of: "\n```", range: start.upperBound..<body.endIndex) else { return .failure(Problem("the skill has no lamp-setup block")) }
        let text = body[start.upperBound..<end.lowerBound]
        guard let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return .failure(Problem("its lamp-setup block isn't JSON")) }
        guard let connection = json["connection"] as? String, SetupConnections.known.contains(connection) else {
            return .failure(Problem("its connection isn't one Lamp has"))
        }
        let http = connection == SetupConnections.http
        var reach: [Integration.Condition] = []
        if http {
            guard case .success(.http(let conditions))? = check(json["reach"], http: true, fields: fields, at: "reach"), !conditions.isEmpty else {
                return .failure(Problem("an HTTP connection needs reach: what the device answering means"))
            }
            reach = conditions
        }
        guard let list = json["steps"] as? [[String: Any]], !list.isEmpty else { return .failure(Problem("it has no steps")) }
        var steps: [Step] = []
        for (index, item) in list.enumerated() {
            let number = index + 1
            guard let word = item["do"] as? String, let kind = Kind(rawValue: word) else { return .failure(Problem("step \(number) does nothing Lamp knows")) }
            var step = Step(kind: kind)
            step.doing = item["doing"] as? String
            step.ask = item["ask"] as? String
            step.done = item["done"] as? String
            step.refused = item["refused"] as? String
            step.failed = item["failed"] as? String
            step.continueOnFailure = item["continueOnFailure"] as? Bool ?? false
            step.every = max(1, item["every"] as? Double ?? 3)
            step.button = item["button"] as? String
            if let link = item["link"] as? [String: Any], let title = link["title"] as? String,
               let url = (link["url"] as? String).flatMap(URL.init(string:)), url.scheme == "https" { step.link = (title, url) }
            if http {
                if let run = item["run"] {
                    guard let data = try? JSONSerialization.data(withJSONObject: run),
                          let actions = try? JSONDecoder().decode([IntegrationAction].self, from: data) else {
                        return .failure(Problem("step \(number)'s run isn't a list of a device integration's actions"))
                    }
                    if let problem = actions.enumerated().lazy.compactMap({ actionProblem($1, at: "step \(number) run[\($0)]", fields: fields) }).first {
                        return .failure(Problem(problem))
                    }
                    step.run = actions
                }
            } else {
                step.uri = item["uri"] as? String
                step.payload = item["payload"] as? [String: Any] ?? [:]
            }
            for (key, at) in [("until", \Step.until), ("unless", \Step.unless)] as [(String, WritableKeyPath<Step, Check?>)] {
                switch check(item[key], http: http, fields: fields, at: "step \(number) \(key)") {
                case .success(let read)?: step[keyPath: at] = read
                case .failure(let problem)?: return .failure(problem)
                case nil: break
                }
            }
            switch kind {
            case .request where http ? step.run.isEmpty : step.uri == nil, .wait where step.until == nil:
                return .failure(Problem("step \(number) is missing what it sends or waits for"))
            case .confirm where step.ask == nil || step.button == nil:
                return .failure(Problem("step \(number) doesn't say what the person confirms"))
            case .rejoin where step.ask == nil || step.button == nil:
                return .failure(Problem("step \(number) doesn't say what the person does, or how they skip it"))
            // What the person does on the device, Lamp can't see: their button says they did it, and nothing is said done.
            case .confirm where step.done != nil:
                return .failure(Problem("step \(number) is a confirm, which can't say anything is done: Lamp doesn't see it"))
            // The guide's end hands the device back to the setup's own step, which completes only by its own check.
            case .handoff where step.done != nil || step.doing != nil || step.button != nil:
                return .failure(Problem("step \(number) is a handoff, which does nothing and says nothing is done"))
            case .handoff where index != list.count - 1:
                return .failure(Problem("step \(number) is a handoff, which can only be the last step"))
            // Presses are sent once (a failure part way hands the step back to the person, `GuidedSetup.unsure`), so a
            // request of several says what holds once they're done, and isn't sent at all when it already holds.
            case .request where http && step.unless == nil && step.changes > 1:
                return .failure(Problem("step \(number) sends the device more than one change, so it needs unless: what holds once it's done"))
            default: break
            }
            if kind != .wait, step.until != nil { return .failure(Problem("step \(number): only a wait has until")) }
            if kind != .request, kind != .rejoin, step.unless != nil { return .failure(Problem("step \(number): only a request or a rejoin has unless")) }
            steps.append(step)
        }
        return .success(SetupSteps(connection: connection, offer: json["offer"] as? String, reach: reach, steps: steps))
    }

    /// A check as the connection reads it: a list of conditions over HTTP, a request and a path over a socket.
    private static func check(_ value: Any?, http: Bool, fields: Set<String>, at: String) -> Result<Check, Problem>? {
        guard let value else { return nil }
        if http {
            guard let data = try? JSONSerialization.data(withJSONObject: value),
                  let conditions = try? JSONDecoder().decode([Integration.Condition].self, from: data) else {
                return .failure(Problem("\(at) isn't a list of a device integration's checks"))
            }
            for (n, condition) in conditions.enumerated() {
                // A guide reads the device: what the person typed and a vendor's sign-in are the setup's own steps.
                if condition.http == nil, condition.tcp == nil { return .failure(Problem("\(at)[\(n)] must ask the device, over http or tcp")) }
                if let problem = IntegrationCheck.conditionProblems(condition, at: "\(at)[\(n)]", fields: fields, steps: []).first {
                    return .failure(Problem(problem))
                }
            }
            return .success(.http(conditions))
        }
        guard let object = value as? [String: Any], let uri = object["uri"] as? String, let json = object["json"] as? String,
              (object["equals"] as? String == nil) != (object["contains"] as? String == nil) else {
            return .failure(Problem("\(at) needs a uri, a json path, and one of equals or contains"))
        }
        return .success(.socket(uri: uri, payload: object["payload"] as? [String: Any] ?? [:], json: json,
                                equals: object["equals"] as? String, contains: object["contains"] as? String))
    }

    /// Why a device integration's action can't be in a guide, held to the same rules as in an integration's step. A guide
    /// only asks the device and waits: a command, a tool or a sign-in is a setup step of its own, with its own approval.
    private static func actionProblem(_ action: IntegrationAction, at: String, fields: Set<String>) -> String? {
        if action.http == nil, action.wait == nil, action.probe == nil {
            return "\(at) can only be http, probe or wait: commands, tools and sign-ins are the device's own setup steps"
        }
        if action.http?.keep != nil || action.http?.restore != nil { return "\(at) keeps or puts back nothing: a guide only asks the device" }
        return IntegrationCheck.actionProblems(action, at: at, fields: fields, steps: [], inBridge: false).first
    }

    struct Problem: Error, Equatable {
        let reason: String
        init(_ reason: String) { self.reason = reason }
    }

    /// Every value at a dotted path in an answer, through arrays: "apps.id" reads each app's id.
    static func values(at path: String, in json: Any) -> [String] {
        var current: [Any] = [json]
        for key in path.split(separator: ".").map(String.init) {
            current = current.flatMap { node -> [Any] in
                let items = (node as? [Any]) ?? [node]
                return items.compactMap { ($0 as? [String: Any])?[key] }
            }
        }
        return current.flatMap { ($0 as? [Any]) ?? [$0] }.compactMap { $0 as? String }
    }
}

/// Which skill does which setup step, from what each skill says of itself:
///
///     setup-for: roku              the row of the table of devices: a built-in one ("tv") or an integration's id
///     setup-system: Roku OS        the system the device reports; left out, any system the row's devices run
///     setup-step: developer-mode   the step of the device's own setup it does
///
/// A guide that names its system wins over one that doesn't; two that say the same are both left out, since Lamp can't
/// tell which is meant. Each one is checked as it's looked up, before anything is sent, against the setup it's for.
enum SetupGuides {
    struct Registration: Equatable {
        let skill: String
        let row: String
        let system: String?
        let step: String
    }

    /// The setup a guide runs in: its step ids, the fields its steps ask for, and whether it's a device integration's
    /// (the only setup whose devices an HTTP guide can reach, through `IntegrationRunner`'s rules).
    struct Host {
        let row: String
        let system: String
        let steps: Set<String>
        var fields: Set<String> = []
        var integration = false
    }

    static func registrations(_ skills: [String: Skills.Skill] = Skills.all) -> [Registration] {
        skills.values.compactMap { skill in
            guard let row = skill.meta["setup-for"], let step = skill.meta["setup-step"] else { return nil }
            return Registration(skill: skill.name, row: row, system: skill.meta["setup-system"], step: step)
        }.sorted { $0.skill < $1.skill }
    }

    /// The guide for one step of one device's setup: nil when no skill offers one, else its steps or why they can't run.
    static func find(_ step: String, in host: Host, skills: [String: Skills.Skill] = Skills.all) -> Result<SetupSteps, SetupSteps.Problem>? {
        let here = registrations(skills).filter { $0.row == host.row && $0.step == step }
        let exact = here.filter { $0.system == host.system }
        let chosen = exact.isEmpty ? here.filter { $0.system == nil } : exact
        guard let first = chosen.first else { return nil }
        if chosen.count > 1 { return .failure(.init("\(chosen.map(\.skill).joined(separator: " and ")) both do \(step)")) }
        guard host.steps.contains(step) else { return .failure(.init("\(first.skill) does \(step), which isn't a step of this setup")) }
        guard let skill = skills[first.skill] else { return nil }
        return SetupSteps.parse(skill: skill.body, fields: host.fields).flatMap { steps in
            steps.connection == SetupConnections.http && !host.integration
                ? .failure(.init("\(first.skill) speaks HTTP, which reaches only a device integration's devices")) : .success(steps)
        }
    }
}

/// How a skill's steps reach the device. Each connection says plainly why it failed, in one of four ways.
protocol SetupConnection: AnyObject {
    /// Lets Lamp in (the device may ask the person first), or for a connection with no pairing, finds it answering.
    func connect() async throws
    /// A `request` step's request.
    func send(_ step: SetupSteps.Step) async throws
    /// Whether a check holds now: false while the device answers otherwise; a device that doesn't answer throws.
    func holds(_ check: SetupSteps.Check) async throws -> Bool
    func close()
}

enum SetupConnectionError: Error, Equatable {
    /// The device said no to letting Lamp in.
    case refused
    /// The device didn't answer, or stopped answering. The only failure a restart is read from.
    case unreachable
    /// The device answers, but not to Lamp: its certificate isn't the one Lamp kept, or it turned the sign-in away.
    case rejected(String)
    /// The device answered with an error of its own.
    case failed(String)
}

/// The connections a skill's steps can name: HTTP, and the socket protocols makers publish.
enum SetupConnections {
    static let http = "http"
    static let sockets: Set<String> = ["webos-second-screen"]
    static var known: Set<String> { sockets.union([http]) }

    static func socket(_ name: String, address: String, id: String) -> SetupConnection? {
        switch name {
        case "webos-second-screen": WebOSSocket(address: address, keyURL: WebOSSocket.clientKeyURL(id))
        default: nil
        }
    }
}

/// A socket protocol's connection: one request and the device's answer, from which its steps are sent and read.
protocol SocketSetupConnection: SetupConnection {
    func request(_ uri: String, payload: [String: Any]) async throws -> [String: Any]
}

extension SocketSetupConnection {
    func send(_ step: SetupSteps.Step) async throws {
        _ = try await request(step.uri ?? "", payload: step.payload)
    }

    func holds(_ check: SetupSteps.Check) async throws -> Bool {
        guard case .socket(let uri, let payload, let json, let equals, let contains) = check else { throw SetupConnectionError.failed("that check isn't for this connection") }
        let values = SetupSteps.values(at: json, in: try await request(uri, payload: payload))
        if let equals { return values.contains { $0.caseInsensitiveCompare(equals) == .orderedSame } }
        if let contains { return values.contains { $0.localizedCaseInsensitiveContains(contains) } }
        return false
    }
}

/// A guide over plain HTTP, sent exactly as a device integration's steps are (`IntegrationRunner`): to the address the
/// device was found at, with the integration's certificate kept and its values filled.
final class HTTPSetupConnection: SetupConnection {
    private let runner: IntegrationRunner
    private let reach: [Integration.Condition]
    private var closed = false

    init(runner: IntegrationRunner, reach: [Integration.Condition]) {
        self.runner = runner
        self.reach = reach
    }

    func connect() async throws {
        // A device that answers otherwise than the check says still answers: only silence is its being away.
        switch await runner.evaluate(reach) {
        case .holds, .waiting: return
        case .away: throw SetupConnectionError.unreachable
        case .rejected(let why): throw SetupConnectionError.rejected(why)
        }
    }

    func send(_ step: SetupSteps.Step) async throws {
        guard !closed else { throw CancellationError() }
        do { _ = try await runner.run(step.run) } catch { throw Self.reason(error) }
    }

    func holds(_ check: SetupSteps.Check) async throws -> Bool {
        guard !closed else { throw CancellationError() }
        guard case .http(let conditions) = check else { throw SetupConnectionError.failed("that check isn't for this connection") }
        switch await runner.evaluate(conditions) {
        case .holds: return true
        case .waiting: return false
        case .away: throw SetupConnectionError.unreachable
        case .rejected(let why): throw SetupConnectionError.rejected(why)
        }
    }

    func close() { closed = true }

    static func reason(_ error: Error) -> Error {
        switch error {
        case is CancellationError: error
        case let refusal as DeviceTLS.Refusal: SetupConnectionError.rejected(refusal.localizedDescription)
        case let rejected as IntegrationRunner.Rejected: SetupConnectionError.rejected(rejected.message)
        case is URLError: SetupConnectionError.unreachable
        case let failure as IntegrationRunner.Failure: SetupConnectionError.failed(failure.message)
        default: SetupConnectionError.failed(error.localizedDescription)
        }
    }
}

/// Runs one skill's steps for one device, and shows where they stand: what's done, what Lamp is doing, and what the
/// person does now. Closing the window or turning to another device cancels it (`cancel`).
///
/// The setup it runs in hands it the device and takes it back: from `start` until the steps end (`handedBack`), the
/// guide alone talks to the device, so the setup's own watch of its step is stopped (`holdsDevice`); once they end, the
/// setup checks its step again itself and shows whichever of its steps is left (`onFinish`). Doing it themselves
/// (`cancel`) gives the device back as well; failing doesn't, since Try Again goes on from the step that failed.
@MainActor
final class GuidedSetup: ObservableObject {
    struct Line: Identifiable, Equatable {
        /// Under way, done, or something the person does instead (what the device couldn't).
        enum State { case doing, done, note }
        let id = UUID()
        var text: String
        var state: State
    }

    @Published private(set) var lines: [Line] = []
    /// What the person does now.
    @Published private(set) var ask: String?
    /// A step the person confirms: its button, and a page that helps with it.
    @Published private(set) var button: String?
    @Published private(set) var link: (title: String, url: URL)?
    /// Why the steps stopped; Try Again goes on from the step that failed.
    @Published private(set) var failure: String?
    /// The steps ran to their end: the setup's own step is the person's again.
    @Published private(set) var handedBack = false
    @Published private(set) var running = false
    /// The setup's step the guide is for.
    private(set) var step: String?

    private var work: Task<Void, Never>?
    private var connection: SetupConnection?
    private var steps: SetupSteps?
    private var name = ""
    private var connect: (() -> SetupConnection?)?
    private var onFinish: (() -> Void)?
    /// Where Try Again goes on from.
    private var resumeAt = 0
    /// Whether Try Again can go on: not after a request of several changes failed part way.
    private var canRetry = true
    /// The step under way began sending its request, so a failure may have left part of it on the device.
    private var sending = false
    private var confirmed: CheckedContinuation<Void, Never>?
    /// The person said a `rejoin` step's restart isn't needed.
    private var skipped = false

    var started: Bool { running || !lines.isEmpty || failure != nil || handedBack }
    /// The guide speaks for the device now, and the setup leaves it alone.
    var holdsDevice: Bool { started && !handedBack }

    var state: SetupGuideView.State {
        SetupGuideView.State(lines: lines, ask: ask, button: button, link: link.map { .init(title: $0.title, url: $0.url) }, failure: failure,
                             canRetry: canRetry)
    }

    /// Runs `steps` for the setup's `step`, over a connection `connect` makes (again for Try Again).
    func start(_ steps: SetupSteps, name: String, step: String, connect: @escaping () -> SetupConnection?, onFinish: @escaping () -> Void) {
        cancel()
        self.steps = steps
        self.name = name
        self.step = step
        self.connect = connect
        self.onFinish = onFinish
        launch()
    }

    /// Goes on from the step that failed, over a new connection; what was seen before stays said.
    func retry() {
        guard failure != nil, canRetry, steps != nil else { return }
        failure = nil
        launch()
    }

    private func launch() {
        guard let steps, let connection = connect?() else {
            failure = "Lamp can't reach \(name) this way."
            return
        }
        self.connection = connection
        running = true
        let from = resumeAt
        work = Task { await run(steps, from: from, connection: connection) }
    }

    /// The person did what the step asked.
    func confirm() {
        skipped = true
        let waiting = confirmed
        confirmed = nil
        button = nil
        link = nil
        waiting?.resume()
    }

    func cancel() {
        work?.cancel()
        work = nil
        confirmed?.resume()
        confirmed = nil
        connection?.close()
        connection = nil
        steps = nil
        step = nil
        connect = nil
        onFinish = nil
        resumeAt = 0
        canRetry = true
        lines = []
        ask = nil
        button = nil
        link = nil
        failure = nil
        handedBack = false
        running = false
    }

    /// Waits for every step to settle, for tests.
    func finished() async { await work?.value }

    private func fill(_ text: String?) -> String? { text?.replacingOccurrences(of: "{name}", with: name) }

    private func run(_ steps: SetupSteps, from start: Int, connection: SetupConnection) async {
        // Going on after a failure, the connection is new: it's let in again first, quietly, as the steps before did.
        if start > 0, let earlier = steps.steps[..<start].last(where: { $0.kind == .connect }) {
            do { try await connection.connect() } catch {
                guard !(error is CancellationError), !Task.isCancelled else { return }
                return fail(error, at: start, words: earlier, connection: connection)
            }
        }
        for index in start..<steps.steps.count {
            let step = steps.steps[index]
            guard !Task.isCancelled else { return }
            if step.kind == .handoff {
                ask = fill(step.ask)
                break
            }
            if let doing = fill(step.doing) { lines.append(Line(text: doing, state: .doing)) }
            if step.kind != .rejoin { ask = fill(step.ask) }
            sending = false
            do {
                let done = try await perform(step, over: connection)
                guard !Task.isCancelled else { return }
                settle(done, as: .done)
            } catch is CancellationError {
                return
            } catch where sending && step.changes > 1 {
                guard !Task.isCancelled else { return }
                return unsure(step, error: error, connection: connection)
            } catch SetupConnectionError.failed(let words) where step.continueOnFailure {
                guard !Task.isCancelled else { return }
                // The device couldn't do this one (a store that isn't there): the person is told how to do it
                // themselves, and the steps go on.
                settle(fill(step.failed) ?? words, as: .note)
            } catch {
                guard !Task.isCancelled else { return }
                return fail(error, at: index, words: step, connection: connection)
            }
        }
        guard !Task.isCancelled else { return }
        // The device goes back to the setup, which checks its own step: nothing here says it's done.
        connection.close()
        self.connection = nil
        button = nil
        link = nil
        running = false
        handedBack = true
        onFinish?()
    }

    /// Does one step, and gives back what's said once it's done: only what Lamp saw.
    private func perform(_ step: SetupSteps.Step, over connection: SetupConnection) async throws -> String? {
        switch step.kind {
        case .connect:
            try await connection.connect()
            return fill(step.done)
        case .request:
            // Already done (the device says so): nothing is sent, and nothing claims Lamp asked for it.
            if let unless = step.unless, try await connection.holds(unless) { return nil }
            sending = true
            try await connection.send(step)
            return fill(step.done)
        case .wait:
            while !(try await connection.holds(step.until!)) { try await Task.sleep(for: .seconds(step.every)) }
            return fill(step.done)
        case .confirm:
            button = step.button
            link = step.link
            await withCheckedContinuation { confirmed = $0 }
            // The person's click is all there is: Lamp didn't see it, so it says nothing is done.
            return nil
        case .rejoin:
            return try await rejoin(step, over: connection)
        case .handoff:
            return nil
        }
    }

    /// The device restarts (the person unplugs it, or it restarts by itself). Lamp looks before it asks, so a restart is
    /// never missed for being quick, and carries on once it has seen the device stop answering and answer again, the
    /// only time it says the device is back. A device that answers otherwise (its certificate changed, the sign-in turned
    /// away) hasn't gone anywhere: that stops the steps. What `unless` says, when it holds, means there's nothing to
    /// restart for, and the person's button skips a restart that isn't needed: both go on claiming nothing.
    private func rejoin(_ step: SetupSteps.Step, over connection: SetupConnection) async throws -> String? {
        skipped = false
        var gone = false
        var connected = false
        var asked = false
        defer {
            button = nil
            link = nil
        }
        while true {
            // Only the device not answering at all is its going away: `connect` alone says so.
            do {
                try await connection.connect()
                connected = true
            } catch SetupConnectionError.unreachable {
                gone = true
                connected = false
            }
            if connected {
                if gone { return skipped ? nil : fill(step.done) }
                // A port `unless` reads that isn't open (developer mode off) is the device answering otherwise: the
                // check doesn't hold, and nothing went away.
                if let unless = step.unless {
                    do { if try await connection.holds(unless) { return nil } } catch SetupConnectionError.unreachable {}
                }
            }
            if !asked {
                ask = fill(step.ask)
                button = step.button
                link = step.link
                asked = true
            }
            // A skip goes on only with the device answering: the next step talks to it.
            if skipped && connected { return nil }
            try await Task.sleep(for: .seconds(step.every))
        }
    }

    /// A request of several changes failed part way: Lamp can't tell which reached the device, so it sends none of them
    /// again. The step goes back to the person, with what it was for, and the setup checks its own step itself. A device
    /// that turned Lamp away says why (its certificate, the sign-in), since that's what the person has to fix.
    private func unsure(_ step: SetupSteps.Step, error: Error, connection: SetupConnection) {
        if lines.last?.state == .doing { lines.removeLast() }
        if case .rejected(let words)? = error as? SetupConnectionError {
            failure = words
        } else {
            failure = fill(step.failed) ?? "Lamp can't tell how much of that reached \(name), so it won't send it again. Finish this step on \(name) yourself."
        }
        canRetry = false
        ask = nil
        button = nil
        link = nil
        connection.close()
        self.connection = nil
        running = false
        handedBack = true
        onFinish?()
    }

    private func fail(_ error: Error, at index: Int, words step: SetupSteps.Step, connection: SetupConnection) {
        let reason: String = switch error as? SetupConnectionError {
        case .refused: fill(step.refused) ?? "\(name) didn't let Lamp in. Click Try Again."
        case .rejected(let words): words
        case .failed(let words): fill(step.failed) ?? "\(name) couldn't do that: \(words)"
        case .unreachable, nil: "\(name) isn't answering. Check it's on and on the same network as this Mac, then click Try Again."
        }
        if lines.last?.state == .doing { lines.removeLast() }
        failure = reason
        ask = nil
        button = nil
        link = nil
        running = false
        resumeAt = index
        connection.close()
        self.connection = nil
    }

    /// The step's line: its done words in place of its doing words.
    private func settle(_ text: String?, as state: Line.State) {
        if lines.last?.state == .doing { lines.removeLast() }
        if let text { lines.append(Line(text: text, state: state)) }
        ask = nil
    }
}
