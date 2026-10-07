import Foundation

/// One way to run a tool and wait for it. Output is read while the tool runs (a chatty tool can't fill the
/// pipe and hang), there's a deadline, and a tool that's cut short takes its whole process tree with it.
/// `Shell.run` is the streaming variant for the agent and the build; everything else goes through here.
enum Subprocess {
    struct Result {
        let status: Int32
        let output: String      // stdout, with stderr merged in unless asked apart
        let errors: String      // stderr when kept apart
        let timedOut: Bool
        var ok: Bool { status == 0 && !timedOut }
    }

    /// Runs `tool` and waits for it, off the caller's thread.
    static func run(_ tool: String, _ arguments: [String] = [], cwd: URL? = nil, env: [String: String]? = nil,
                    mergeErrors: Bool = true, timeout: TimeInterval? = 60) async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: runBlocking(tool, arguments, cwd: cwd, env: env, mergeErrors: mergeErrors, timeout: timeout))
            }
        }
    }

    /// The same, blocking the calling thread: for the few places that can't await (a value computed under a
    /// lock, a one-time migration). Still read while running and still bounded by the deadline.
    static func runBlocking(_ tool: String, _ arguments: [String] = [], cwd: URL? = nil, env: [String: String]? = nil,
                            mergeErrors: Bool = true, timeout: TimeInterval? = 60) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        if let cwd { process.currentDirectoryURL = cwd }
        if let env { process.environment = ProcessInfo.processInfo.environment.merging(env) { $1 } }
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = mergeErrors ? out : err
        do {
            try process.run()
        } catch {
            return Result(status: -1, output: "", errors: "Could not start \(tool): \(error.localizedDescription)", timedOut: false)
        }
        // Drained as it arrives, so neither pipe can fill while the tool runs, and what has arrived is kept
        // even if the pipe never closes (a child the tool left behind can hold it open).
        let output = Drain(out.fileHandleForReading)
        let errors = mergeErrors ? nil : Drain(err.fileHandleForReading)
        // Polled rather than waitUntilExit(), which off the main thread can wait forever for a process that
        // has already gone.
        let deadline = timeout.map { Date().addingTimeInterval($0) }
        var timedOut = false
        while process.isRunning {
            if let deadline, Date() >= deadline { timedOut = true; terminateTree(process); break }
            Thread.sleep(forTimeInterval: 0.02)
        }
        while process.isRunning { Thread.sleep(forTimeInterval: 0.02) }
        // The pipes close when the last holder goes: normally the tool itself. A child it left behind could
        // keep them open, so the wait for the rest of the output is bounded, and the readers are stopped
        // before the result is taken.
        let deadlineForOutput = Date().addingTimeInterval(2)
        output.finish(by: deadlineForOutput)
        errors?.finish(by: deadlineForOutput)
        return Result(status: process.terminationStatus, output: output.text, errors: errors?.text ?? "", timedOut: timedOut)
    }

    /// Reads a pipe as data arrives, on the file handle's own queue, into a buffer the result is taken from.
    private final class Drain: @unchecked Sendable {
        private let handle: FileHandle
        private let lock = NSLock()
        private var data = Data()
        private let closed = DispatchSemaphore(value: 0)

        init(_ handle: FileHandle) {
            self.handle = handle
            handle.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                guard let self else { return }
                if chunk.isEmpty {   // end of output
                    handle.readabilityHandler = nil
                    self.closed.signal()
                } else {
                    self.lock.withLock { self.data.append(chunk) }
                }
            }
        }

        /// Waits for the end of the output until `deadline`, then stops reading either way.
        func finish(by deadline: Date) {
            _ = closed.wait(timeout: .now() + max(0, deadline.timeIntervalSinceNow))
            handle.readabilityHandler = nil
        }

        var text: String { lock.withLock { String(decoding: data, as: UTF8.self) } }
    }

    // MARK: Stopping

    /// Stops a process and everything it started. Terminating only the shell leaves its children (the agent's
    /// build, a clone, an approval request waiting an hour) running and holding the output pipe open, so the
    /// turn would never end. Each gets a chance to quit cleanly, then whatever is left is killed. Returns the
    /// processes signaled, for a caller that has to wait for them to be gone (`alive`).
    @discardableResult
    static func terminateTree(_ process: Process) -> [pid_t] {
        guard process.isRunning else { return [] }
        let pids = [process.processIdentifier] + descendants(of: process.processIdentifier)
        shuttingDown.withLock { shuttingDownPids.formUnion(pids) }
        for pid in pids { kill(pid, SIGTERM) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            for pid in pids where kill(pid, 0) == 0 { kill(pid, SIGKILL) }
            shuttingDown.withLock { shuttingDownPids.subtract(pids) }
        }
        return pids
    }

    /// Whether any of these processes is still around (a zombie waiting to be reaped doesn't count).
    static func alive(_ pids: [pid_t]) -> Bool {
        pids.contains { pid in
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return false }
            return info.pbi_status != UInt32(SZOMB)
        }
    }

    /// Processes told to stop whose two seconds aren't up yet. A Stop followed by Quit has to wait for these
    /// too: the shell may have gone while a child that ignored the signal is still to be killed.
    static var stopping: [pid_t] { shuttingDown.withLock { Array(shuttingDownPids) } }

    /// Kills those outright, for when Lamp is about to exit and can't wait the two seconds for them.
    static func killStopping() {
        let pids = shuttingDown.withLock { let p = shuttingDownPids; shuttingDownPids = []; return p }
        for pid in pids where kill(pid, 0) == 0 { kill(pid, SIGKILL) }
    }

    private static let shuttingDown = NSLock()
    nonisolated(unsafe) private static var shuttingDownPids = Set<pid_t>()

    private static func descendants(of pid: pid_t) -> [pid_t] {
        var children = [pid_t](repeating: 0, count: 256)
        let bytes = Int32(children.count * MemoryLayout<pid_t>.size)
        let count = Int(proc_listchildpids(pid, &children, bytes))
        guard count > 0 else { return [] }
        let direct = Array(children.prefix(count))
        return direct + direct.flatMap { descendants(of: $0) }
    }
}
