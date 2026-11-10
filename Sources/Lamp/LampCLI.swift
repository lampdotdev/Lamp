import Foundation

/// Lamp's core is lamp's command line (`cli/`: JavaScript with no dependencies, which also runs with Lamp's app
/// closed). What it does, Lamp's app has it do, rather than doing the same a second time in Swift. Each call is one run
/// of `cli/calls.mjs`: the call's name is its argument, what it's given is one JSON object on its input (never in its
/// arguments, which any process on the Mac can list), and its answer is the last line it prints (`call`). The many
/// small things, a request to a device, are asked of one run that stays (`ask`), so each doesn't wait for a program to
/// start.
///
/// It runs as Lamp itself, as adb and Gradle's own tools do, on what Lamp hands it from Lamp's own folders. It's never
/// pointed at an app's folder: what's there is the agent's, and is read on that folder's terms (`AppFile`) or run in
/// the app's sandbox before anything of it comes here.
enum LampCLI {
    struct Failure: LocalizedError {
        let message: String
        /// The kind of problem, where lamp's command line names one for Lamp's app to act on: a device that's "away",
        /// a certificate that "changed".
        var kind: String?
        /// For a device that's away: the connection's own word for how (ECONNRESET), and whether it ran out of time.
        var code: String?
        var timedOut = false
        /// The status a site gave when it turned the call down.
        var status: Int?
        var errorDescription: String? { message }
    }

    /// How lamp's command line is run: the program, what it's given before the call's name, and what's set for it.
    struct Launch {
        var tool: String
        var arguments: [String]
        var environment: [String: String] = [:]
    }

    /// Which copy of lamp's command line runs and on what, decided here alone; a test can put its own here.
    ///
    /// In Lamp's app it's the copy in the app (`build.sh` puts `cli/` in its Resources), on the runtime Lamp already
    /// carries: pi is built on Bun, and run with BUN_BE_BUN it is Bun itself, so Lamp ships no second runtime. Bun is
    /// told to fetch nothing and to read no .env file, both of which it would otherwise do by itself.
    /// A run from source (a test) has no app around it: the repository's copy, on the person's own Node.
    nonisolated(unsafe) static var launch: Launch? = found()

    private static func found() -> Launch? {
        let fm = FileManager.default
        if let script = Bundle.main.resourceURL?.appendingPathComponent("cli/calls.mjs"), fm.fileExists(atPath: script.path), let pi = Agent.executable {
            return Launch(tool: pi.path, arguments: ["--no-install", "--no-env-file", script.path], environment: ["BUN_BE_BUN": "1"])
        }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("cli/calls.mjs")
        guard fm.fileExists(atPath: source.path), let node = ToolLocator.path(named: "node") else { return nil }
        return Launch(tool: node, arguments: [source.path])
    }

    /// Has lamp's command line do `name` with what it's `given`, and gives back its answer. What it says the person
    /// can put right is thrown in its own words; a run that ends any other way is Lamp's own fault, and says so.
    static func call(_ name: String, _ given: [String: Any], timeout: TimeInterval = 300) async throws -> [String: Any] {
        guard let launch else { throw Failure(message: "Lamp's own tools are missing from Lamp itself.") }
        let input = try JSONSerialization.data(withJSONObject: given)
        // Run from its own folder, where nothing of the person's is: Bun reads settings from the folder it's started in.
        let home = launch.arguments.last.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
        let result = await Subprocess.run(launch.tool, launch.arguments + [name], cwd: home, env: launch.environment, mergeErrors: false,
                                          timeout: timeout, input: input)
        let answer = result.output.split(separator: "\n").last
            .flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        if let problem = answer?["problem"] as? String { throw Failure(message: problem) }
        if result.ok, let done = answer?["done"] as? [String: Any] { return done }
        let said = result.errors.split(separator: "\n").suffix(6).joined(separator: "\n")
        throw Failure(message: (result.timedOut ? "Lamp's own tools took too long." : "Lamp's own tools stopped before they answered.")
                      + (said.isEmpty ? "" : "\n\n" + said))
    }

    // MARK: The run that stays

    /// Asks the run of lamp's command line that stays (`calls.mjs --serve`) to do `name` with what it's `given`, and
    /// gives back its answer. It's started the first time something is asked and again if it ever ends, and it ends
    /// with Lamp: its input closes when Lamp does. Many may be asked at once; each is answered as it finishes. A task
    /// cancelled while it waits lets go of what it asked, there too. `onEvent` hears what the call says while it's
    /// under way (that it's waiting on the device).
    static func ask(_ name: String, _ given: [String: Any], onEvent: (@Sendable ([String: Any]) -> Void)? = nil) async throws -> [String: Any] {
        let line = try await kept.ask(name, given, onEvent: onEvent)
        let answer = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] ?? [:]
        if let done = answer["done"] as? [String: Any] { return done }
        if let problem = answer["problem"] as? String {
            throw Failure(message: problem, kind: answer["kind"] as? String, code: answer["code"] as? String, timedOut: answer["timedOut"] as? Bool ?? false,
                          status: answer["status"] as? Int)
        }
        let said = (answer["failed"] as? String)?.split(separator: "\n").prefix(2).joined(separator: "\n") ?? ""
        throw Failure(message: "Lamp's own tools couldn't do that." + (said.isEmpty ? "" : "\n\n" + said))
    }

    private static let kept = Kept()

    /// The run that stays: its input, and who is waiting for which answer.
    private final class Kept: @unchecked Sendable {
        private let lock = NSLock()
        /// One line at a time down the pipe: two written at once would arrive as one garbled line.
        private let writing = NSLock()
        private var process: Process?
        private var input: FileHandle?
        private var waiting: [Int: CheckedContinuation<Data, Error>] = [:]
        private var listening: [Int: @Sendable ([String: Any]) -> Void] = [:]
        private var last = 0
        private var unread = Data()
        private var complaints = Data()

        func ask(_ name: String, _ given: [String: Any], onEvent: (@Sendable ([String: Any]) -> Void)? = nil) async throws -> Data {
            let id = lock.withLock { () -> Int in
                last += 1
                if let onEvent { listening[last] = onEvent }
                return last
            }
            defer { lock.withLock { _ = listening.removeValue(forKey: id) } }
            var line = try JSONSerialization.data(withJSONObject: ["id": id, "call": name, "given": given])
            line.append(0x0A)
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                    let handle: FileHandle
                    do {
                        handle = try lock.withLock {
                            let handle = try running()
                            waiting[id] = continuation
                            return handle
                        }
                    } catch {
                        return continuation.resume(throwing: error)
                    }
                    if Task.isCancelled { return answer(id, .failure(CancellationError())) }
                    write(line, to: handle)
                }
            } onCancel: {
                // Whoever asked no longer wants it: the run lets go of it (a request under way is dropped), and the
                // wait ends here.
                if let handle = lock.withLock({ input }), let stop = try? JSONSerialization.data(withJSONObject: ["stop": id]) {
                    write(stop + Data([0x0A]), to: handle)
                }
                answer(id, .failure(CancellationError()))
            }
        }

        private func write(_ line: Data, to handle: FileHandle) {
            writing.withLock { try? handle.write(contentsOf: line) }
        }

        private func answer(_ id: Int, _ result: Result<Data, Error>) {
            lock.withLock { waiting.removeValue(forKey: id) }?.resume(with: result)
        }

        /// The run's input, starting the run when there's none. Called with the lock held.
        private func running() throws -> FileHandle {
            if let process, process.isRunning, let input { return input }
            guard let launch = LampCLI.launch else { throw Failure(message: "Lamp's own tools are missing from Lamp itself.") }
            let process = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
            process.executableURL = URL(fileURLWithPath: launch.tool)
            process.arguments = launch.arguments + ["--serve"]
            process.environment = ProcessInfo.processInfo.environment.merging(launch.environment) { $1 }
            process.currentDirectoryURL = launch.arguments.last.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr
            // A run that has ended makes a write fail; without this it would end Lamp with SIGPIPE.
            _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
            stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                if chunk.isEmpty { handle.readabilityHandler = nil } else { self?.heard(chunk) }
            }
            stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                guard let self, !chunk.isEmpty else { handle.readabilityHandler = nil; return }
                // Its last words, for when it ends without an answer.
                self.lock.withLock { self.complaints = (self.complaints + chunk).suffix(2000) }
            }
            process.terminationHandler = { [weak self] ended in self?.ended(ended) }
            do {
                try process.run()
            } catch {
                throw Failure(message: "Lamp's own tools couldn't start: \(error.localizedDescription)")
            }
            self.process = process
            self.input = stdin.fileHandleForWriting
            unread = Data()
            complaints = Data()
            return stdin.fileHandleForWriting
        }

        /// Each line is one answer, which says first whose it is: {"id":7,…
        private func heard(_ chunk: Data) {
            var lines: [Data] = []
            lock.withLock {
                unread.append(chunk)
                while let end = unread.firstIndex(of: 0x0A) {
                    lines.append(unread[unread.startIndex..<end])
                    unread = Data(unread[unread.index(after: end)...])
                }
            }
            for line in lines {
                let start = String(decoding: line.prefix(40), as: UTF8.self)
                guard start.hasPrefix("{\"id\":"), let id = Int(start.dropFirst(6).prefix { $0.isNumber }) else { continue }
                // What a call says while it's under way, before its answer.
                if let said = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any], let event = said["event"] as? [String: Any] {
                    lock.withLock { listening[id] }?(event)
                    continue
                }
                answer(id, .success(Data(line)))
            }
        }

        /// The run ended: nobody still waiting will hear from it, and the next thing asked starts another.
        private func ended(_ ended: Process) {
            let (left, said) = lock.withLock { () -> ([CheckedContinuation<Data, Error>], String) in
                guard process === ended else { return ([], "") }
                let left = Array(waiting.values)
                waiting = [:]
                process = nil
                input = nil
                return (left, String(decoding: complaints, as: UTF8.self).split(separator: "\n").suffix(4).joined(separator: "\n"))
            }
            for continuation in left {
                continuation.resume(throwing: Failure(message: "Lamp's own tools stopped before they answered." + (said.isEmpty ? "" : "\n\n" + said)))
            }
        }
    }
}
