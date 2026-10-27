import Foundation

/// A device's setup step done for the person (Do It for Me), followed from a skill: the device table names the skill
/// (`Place.setupSkills`), the skill carries its steps as data (a `lamp-setup` block), and this runs them. Nothing here
/// knows any one maker: the steps say what to send, what to wait for and what to tell the person, and the connection
/// they go over is named by the skill (`SetupConnections`).
///
/// Lamp says only what it saw happen. What the device shows can be read back (it let Lamp in, an app is installed);
/// what the person does on it (a sign-in, a switch, a restart) they confirm themselves, and a dropped connection or a
/// timer is never taken for either.
struct SetupSteps {
    enum Kind: String { case connect, request, wait, confirm, rejoin, passphrase }

    struct Step {
        let kind: Kind
        var doing: String?
        var ask: String?
        var done: String?
        var refused: String?
        var failed: String?
        var continueOnFailure = false
        var uri: String?
        var payload: [String: Any] = [:]
        /// For `wait`: the path read from each answer ("apps.id": every app's id), and the value it must hold.
        var path: String?
        var contains: String?
        var every: Double = 3
        var button: String?
        var link: (title: String, url: URL)?
    }

    let connection: String
    let steps: [Step]

    /// The steps in a skill's `lamp-setup` block; nil when it has none or one can't be followed, with why.
    static func parse(skill body: String) -> Result<SetupSteps, Problem> {
        guard let start = body.range(of: "```lamp-setup\n"),
              let end = body.range(of: "\n```", range: start.upperBound..<body.endIndex) else { return .failure(Problem("the skill has no lamp-setup block")) }
        let text = body[start.upperBound..<end.lowerBound]
        guard let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return .failure(Problem("its lamp-setup block isn't JSON")) }
        guard let connection = json["connection"] as? String, SetupConnections.known.contains(connection) else {
            return .failure(Problem("its connection isn't one Lamp has"))
        }
        guard let list = json["steps"] as? [[String: Any]], !list.isEmpty else { return .failure(Problem("it has no steps")) }
        var steps: [Step] = []
        for (index, item) in list.enumerated() {
            guard let word = item["do"] as? String, let kind = Kind(rawValue: word) else { return .failure(Problem("step \(index + 1) does nothing Lamp knows")) }
            var step = Step(kind: kind)
            step.doing = item["doing"] as? String
            step.ask = item["ask"] as? String
            step.done = item["done"] as? String
            step.refused = item["refused"] as? String
            step.failed = item["failed"] as? String
            step.continueOnFailure = item["continueOnFailure"] as? Bool ?? false
            step.uri = item["uri"] as? String
            step.payload = item["payload"] as? [String: Any] ?? [:]
            if let until = item["until"] as? [String: Any] {
                step.path = until["path"] as? String
                step.contains = until["contains"] as? String
            }
            step.every = max(1, item["every"] as? Double ?? 3)
            step.button = item["button"] as? String
            if let link = item["link"] as? [String: Any], let title = link["title"] as? String,
               let url = (link["url"] as? String).flatMap(URL.init(string:)), url.scheme == "https" { step.link = (title, url) }
            switch kind {
            case .request where step.uri == nil, .wait where step.uri == nil || step.path == nil || step.contains == nil:
                return .failure(Problem("step \(index + 1) is missing what it sends or waits for"))
            case .confirm where step.ask == nil || step.button == nil:
                return .failure(Problem("step \(index + 1) doesn't say what the person confirms"))
            case .rejoin where step.ask == nil || step.button == nil:
                return .failure(Problem("step \(index + 1) doesn't say what the person does, or how they skip it"))
            default: break
            }
            steps.append(step)
        }
        return .success(SetupSteps(connection: connection, steps: steps))
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

/// How a skill's steps reach the device. Each connection says plainly why it failed, in one of three ways.
protocol SetupConnection: AnyObject {
    /// Lets Lamp in; the device may ask the person first.
    func connect() async throws
    /// One request and the device's answer.
    func request(_ uri: String, payload: [String: Any]) async throws -> [String: Any]
    func close()
}

enum SetupConnectionError: Error, Equatable {
    /// The device said no to letting Lamp in.
    case refused
    /// The device didn't answer, or stopped answering.
    case unreachable
    /// The device answered with an error of its own.
    case failed(String)
}

/// The connections a skill's steps can name, each one a protocol a maker publishes.
enum SetupConnections {
    static let known: Set<String> = ["webos-second-screen"]

    static func make(_ name: String, address: String, id: String) -> SetupConnection? {
        switch name {
        case "webos-second-screen": WebOSSocket(address: address, keyURL: WebOSSocket.clientKeyURL(id))
        default: nil
        }
    }
}

/// Runs one skill's steps for one device, and shows where they stand: what's done, what Lamp is doing, and what the
/// person does now. Closing the window or turning to another device cancels it (`cancel`).
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
    /// Why the steps stopped; Try Again starts them over, and each is safe to do again.
    @Published private(set) var failure: String?
    /// The last step is the setup's own passphrase.
    @Published private(set) var atPassphrase = false
    @Published private(set) var running = false

    private var work: Task<Void, Never>?
    private var connection: SetupConnection?
    private var confirmed: CheckedContinuation<Void, Never>?
    /// The person said a `rejoin` step's restart isn't needed.
    private var skipped = false

    var started: Bool { !lines.isEmpty || failure != nil || atPassphrase }

    func start(_ steps: SetupSteps, name: String, connection: SetupConnection) {
        cancel()
        self.connection = connection
        running = true
        work = Task { await run(steps, name: name, connection: connection) }
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
        lines = []
        ask = nil
        button = nil
        link = nil
        failure = nil
        atPassphrase = false
        running = false
    }

    /// Waits for every step to settle, for tests.
    func finished() async { await work?.value }

    private func run(_ steps: SetupSteps, name: String, connection: SetupConnection) async {
        func fill(_ text: String?) -> String? { text?.replacingOccurrences(of: "{name}", with: name) }
        let unreachable = "\(name) isn't answering. Check it's on and on the same network as this Mac, then click Try Again."
        for step in steps.steps {
            guard !Task.isCancelled else { return }
            if step.kind == .passphrase {
                // The rest is the setup's own: nothing more goes to the device over this connection.
                connection.close()
                ask = fill(step.ask)
                atPassphrase = true
                break
            }
            if let doing = fill(step.doing) { lines.append(Line(text: doing, state: .doing)) }
            ask = fill(step.ask)
            do {
                var done = fill(step.done)
                switch step.kind {
                case .connect:
                    try await connection.connect()
                case .request:
                    _ = try await connection.request(step.uri!, payload: step.payload)
                case .wait:
                    while true {
                        let answer = try await connection.request(step.uri!, payload: step.payload)
                        if SetupSteps.values(at: step.path!, in: answer).contains(step.contains!) { break }
                        try await Task.sleep(for: .seconds(step.every))
                    }
                case .confirm:
                    button = step.button
                    link = step.link
                    await withCheckedContinuation { confirmed = $0 }
                case .rejoin:
                    // The device restarts (the person unplugs it, or it restarts by itself): Lamp carries on once it
                    // has seen it stop answering and answer again, and says it's back only then. The person's
                    // button skips a restart that isn't needed, and claims nothing.
                    skipped = false
                    button = step.button
                    link = step.link
                    var gone = false
                    var connected = false
                    while true {
                        do {
                            try await connection.connect()
                            connected = true
                            if gone { break }
                        } catch SetupConnectionError.unreachable {
                            gone = true
                            connected = false
                        }
                        // A skip goes on only with the device answering: the next step talks to it.
                        if skipped && connected { break }
                        try await Task.sleep(for: .seconds(step.every))
                    }
                    button = nil
                    link = nil
                    if skipped { done = nil }
                case .passphrase:
                    break
                }
                guard !Task.isCancelled else { return }
                settle(done, as: .done)
            } catch is CancellationError {
                return
            } catch SetupConnectionError.failed(let words) where step.continueOnFailure {
                guard !Task.isCancelled else { return }
                // The device couldn't do this one (a store that isn't there): the person is told how to do it
                // themselves, and the steps go on.
                settle(fill(step.failed) ?? words, as: .note)
            } catch {
                guard !Task.isCancelled else { return }
                let reason: String = switch error as? SetupConnectionError {
                case .refused: fill(step.refused) ?? "\(name) didn't let Lamp in. Click Try Again."
                case .failed(let words): fill(step.failed) ?? "\(name) couldn't do that: \(words)"
                case .unreachable, nil: unreachable
                }
                if lines.last?.state == .doing { lines.removeLast() }
                failure = reason
                ask = nil
                running = false
                connection.close()
                return
            }
        }
        running = false
    }

    /// The step's line: its done words in place of its doing words.
    private func settle(_ text: String?, as state: Line.State) {
        if lines.last?.state == .doing { lines.removeLast() }
        if let text { lines.append(Line(text: text, state: state)) }
        ask = nil
    }
}
