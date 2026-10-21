import XCTest
@testable import Lamp

/// How a test runs a program and waits for it. A wait with no deadline lets one stuck program (a helper server
/// nobody connects to, a port someone else holds, a prompt nobody answers) hang the whole suite with nothing said,
/// so every run here has one: past it, the program and everything it started are stopped (`Subprocess`, the same
/// way Lamp stops a tool it gave up on) and the test fails, naming the command and what it printed.
enum TestShell {
    /// Long enough for a compile or a small build; a test that needs longer says so.
    static let patience: TimeInterval = 300

    /// `command` in zsh, in `directory`, stdout and stderr together.
    @discardableResult
    static func run(_ command: String, in directory: URL? = nil, env: [String: String]? = nil,
                    timeout: TimeInterval = patience,
                    file: StaticString = #filePath, line: UInt = #line) -> (status: Int32, output: String) {
        run("/bin/zsh", ["-c", command], in: directory, env: env, timeout: timeout, file: file, line: line)
    }

    /// A program with its arguments, as the test would hand them to `Process`. `mergeErrors` false leaves stderr
    /// out of the output, for a listing read line by line.
    @discardableResult
    static func run(_ tool: String, _ arguments: [String], in directory: URL? = nil, env: [String: String]? = nil,
                    mergeErrors: Bool = true, timeout: TimeInterval = patience,
                    file: StaticString = #filePath, line: UInt = #line) -> (status: Int32, output: String) {
        let result = Subprocess.runBlocking(tool, arguments, cwd: directory, env: env, mergeErrors: mergeErrors, timeout: timeout)
        if result.timedOut {
            XCTFail("Stopped after \(Int(timeout)) seconds: \(([tool] + arguments).joined(separator: " "))\n\(result.output.suffix(2000))",
                    file: file, line: line)
        }
        return (result.timedOut ? -1 : result.status, result.output)
    }

    /// A process the test started itself (to talk to it, or to race it), waited for with a deadline. False, with
    /// the test failed and the process and its children stopped, when it outlasts it.
    @discardableResult
    static func wait(for process: Process, timeout: TimeInterval = patience,
                     file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        // Polled: off the main thread waitUntilExit() can wait forever for a process that has already gone.
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        guard process.isRunning else { return true }
        Subprocess.terminateTree(process)
        while process.isRunning { Thread.sleep(forTimeInterval: 0.02) }
        XCTFail("Stopped after \(Int(timeout)) seconds: \(process.executableURL?.path ?? "a process") \((process.arguments ?? []).joined(separator: " "))",
                file: file, line: line)
        return false
    }
}
