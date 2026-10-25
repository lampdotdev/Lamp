import XCTest
import CryptoKit
@testable import Lamp

/// Every case under Tests/LiveCases run through Lamp's own live reload: the verdict, the layout check, the spares,
/// the compile and the object rewrite (`LiveReload.verdict`, `LiveReload.put`), with the library handed to a process
/// built from the case's sources instead of to an open app (`LiveReload.deliver`). The process runs alongside, as
/// the app does: its `reload(n)` waits for the n-th change, loads the library when Lamp delivers it and answers,
/// which is what `put` commits on; when a change is refused the process is ended, the app rebuilt from the new code
/// and started again, as Reload does, unless the case says the person kept the app open (a `keep-open` file).
/// A case is a folder with the app's sources (`Main.swift`, which prints what it sees around each `reload(n)`, with
/// what's wanted in the print's words, and the rest), one `afterN/` folder per change with the files it rewrites,
/// and `expect.txt`: the verdicts Lamp gave and what the process printed, which is the record of which side each
/// change lands on. A difference reads as a change of behaviour, right or wrong.
///
/// Every case takes a build and a few compiles, so they run only when asked: `LAMP_LIVE_CASES=1` runs them all,
/// `LAMP_LIVE_CASES=name,name` some; `LAMP_LIVE_CASES_RECORD=1` writes each case's `expect.txt` instead of checking it.
/// The cases are independent, and the time is the compiler's, so several run at once (half the cores).
final class LiveCasesTests: XCTestCase {
    static let casesFolder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("LiveCases")

    @MainActor func testEveryCaseLandsWhereItDid() async throws {
        let wanted = ProcessInfo.processInfo.environment["LAMP_LIVE_CASES"] ?? ""
        try XCTSkipIf(wanted.isEmpty, "set LAMP_LIVE_CASES=1 (or a comma-separated list of cases) to run the live cases")
        let record = ProcessInfo.processInfo.environment["LAMP_LIVE_CASES_RECORD"] == "1"
        let chosen = Set(wanted.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        var names = try FileManager.default.contentsOfDirectory(atPath: Self.casesFolder.path).filter { !$0.hasPrefix(".") }.sorted()
        if wanted != "1" { names = names.filter(chosen.contains) }
        XCTAssertFalse(names.isEmpty, "no such case")
        // One delivery for every case at once, each case's by its folder.
        LiveReload.deliver = { library, project, _, whole, retired in
            // The case's own answer, nil included (the library went in); only a case with no process is an error.
            guard let deliver = Self.deliveries[project.dir.path] else { return "no process for the case" }
            return await deliver(library, whole, retired)
        }
        defer { LiveReload.deliver = nil }
        var results: [String: String] = [:]
        let width = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
        try await withThrowingTaskGroup(of: (String, String).self) { group in
            var waiting = names[...]
            for _ in 0..<min(width, names.count) { let name = waiting.removeFirst(); group.addTask { @MainActor in (name, try await Self.run(Self.casesFolder.appendingPathComponent(name))) } }
            while let (name, got) = try await group.next() {
                results[name] = got
                if let next = waiting.first { waiting.removeFirst(); group.addTask { @MainActor in (next, try await Self.run(Self.casesFolder.appendingPathComponent(next))) } }
            }
        }
        var failures: [String] = []
        for name in names {
            let got = results[name] ?? ""
            let expectation = Self.casesFolder.appendingPathComponent(name).appendingPathComponent("expect.txt")
            if record {
                try got.write(to: expectation, atomically: true, encoding: .utf8)
                continue
            }
            let expected = (try? String(contentsOf: expectation, encoding: .utf8)) ?? ""
            if Self.settled(got) != Self.settled(expected) { failures.append("\(name):\n--- expected\n\(expected)\n--- got\n\(got)") }
        }
        XCTAssertTrue(failures.isEmpty, "\(failures.count) of \(names.count) cases changed\n\n" + failures.joined(separator: "\n\n"))
    }

    /// What a case printed, without what timing alone decides: trailing spaces, blank lines, and a line said twice in
    /// a row (a copy whose window hadn't drawn yet printing the same empty reading the copy after it does).
    private static func settled(_ text: String) -> [String] {
        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = String(line.reversed().drop { $0 == " " }.reversed())
            if !trimmed.isEmpty, trimmed != lines.last { lines.append(trimmed) }
        }
        return lines
    }

    /// How each case's library reaches its process, by the case's folder.
    @MainActor private static var deliveries: [String: (URL, Bool, [String]) async -> String?] = [:]

    /// One case: the app built from its sources as a live build, each change put in through Lamp, then the app run.
    @MainActor static func run(_ caseFolder: URL) async throws -> String {
        let fm = FileManager.default
        // Under the home folder, where the agent's sandbox (which the compiles run in) opens an app's folder.
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp live case-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let project = try Template.scaffold(name: "Case", in: root)
        let sources = project.dir.appendingPathComponent("Sources")
        for item in try fm.contentsOfDirectory(atPath: sources.path) { try fm.removeItem(at: sources.appendingPathComponent(item)) }
        // The case's own files, then Lamp's: the live parts of the support template, and the harness's `reload`.
        for file in swiftFiles(in: caseFolder) where !file.hasPrefix("after") {
            try fm.createDirectory(at: sources.appendingPathComponent(file).deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: caseFolder.appendingPathComponent(file), to: sources.appendingPathComponent(file))
        }
        try support(for: project).write(to: sources.appendingPathComponent("LampSupport.swift"), atomically: true, encoding: .utf8)
        try harness.write(to: sources.appendingPathComponent("LampHarness.swift"), atomically: true, encoding: .utf8)
        let runtime = Runtime.macFolder(project), live = LiveReload.folder(project), liveSources = LiveReload.sources(project)
        try fm.createDirectory(at: runtime, withIntermediateDirectories: true)
        try fm.createDirectory(at: live, withIntermediateDirectories: true)
        try Template.livePerl.write(to: live.appendingPathComponent("live.pl"), atomically: true, encoding: .utf8)
        try await copyLive(project)
        let app = project.dir.appendingPathComponent("app").path
        let sdk = try await shell("/usr/bin/xcrun", ["--show-sdk-path"]).trimmingCharacters(in: .whitespacesAndNewlines)
        // The app, as a live build makes it, from the live copy.
        func build() async throws -> String? {
            let files = swiftFiles(in: liveSources).map { liveSources.appendingPathComponent($0).path }
            do {
                _ = try await shell("/usr/bin/xcrun", ["swiftc", "-module-name", project.exe, "-parse-as-library", "-Onone", "-enable-testing", "-D", "DEBUG", "-D", "LAMP_LIVE",
                                                  "-target", "arm64-apple-macosx14.0", "-sdk", sdk] + files + ["-Xlinker", "-interposable", "-o", app])
                return nil
            } catch {
                // The compiler's first errors, by the file's path in the app (the case's folder is made anew each run).
                let errors = (error as NSError).localizedDescription.components(separatedBy: "\n").filter { $0.contains("error:") }.prefix(3)
                    .map { $0.replacingOccurrences(of: liveSources.path + "/", with: "") }
                return "BUILD FAILED\n" + errors.joined(separator: "\n")
            }
        }
        if let failed = try await build() { return failed + "\n" }
        LiveReload.markRunning(project)
        LiveSlots.clear(project)
        var report: [String] = []
        let output = Output()
        // The process, started with how many changes its binary already holds.
        var process = try start(app, project: project, from: 0, output: output)
        defer { end(process) }
        let keepOpen = fm.fileExists(atPath: caseFolder.appendingPathComponent("keep-open").path)
        let changes = try fm.contentsOfDirectory(atPath: caseFolder.path).filter { $0.hasPrefix("after") }.sorted { $0.count < $1.count || ($0.count == $1.count && $0 < $1) }
        for (n, change) in changes.enumerated() {
            let number = n + 1
            for file in swiftFiles(in: caseFolder.appendingPathComponent(change)) {
                let to = sources.appendingPathComponent(file)
                try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: to.path) { try fm.removeItem(at: to) }
                try fm.copyItem(at: caseFolder.appendingPathComponent(change).appendingPathComponent(file), to: to)
            }
            try await copyLive(project)
            // The process waits in `reload(n)` for the n-th change: a verdict releases it with no library.
            func tell(_ verdict: String) throws { try verdict.write(to: live.appendingPathComponent("verdict\(number).txt"), atomically: true, encoding: .utf8) }
            func refused(_ why: String) async throws {
                report.append("VERDICT \(number): REOPEN (\(LiveReload.readable(why)))")
                try tell(why)
                guard !keepOpen else { return }
                // The person pressed Reload: the whole build installs this code and the app opens again with it,
                // holding every change so far. Built from a fresh live copy, as build.sh makes one: the fit may have
                // rewritten the copy before the change was refused, and that copy is not what a whole build compiles.
                // Once it has said so and printed what it prints next, as a copy the person reloads goes on until the
                // click: until its output has held still for a second after the refusal (a window drawing first), up
                // to six seconds.
                let marker = "RELOAD \(number): REOPEN"
                var last = output.current, quiet = 0
                for _ in 0..<120 {
                    try await Task.sleep(for: .milliseconds(50))
                    let now = output.current
                    quiet = now.contains(marker) && now == last ? quiet + 1 : 0
                    last = now
                    if quiet >= 20 { break }
                }
                end(process)
                try await copyLive(project)
                if let failed = try await build() { output.add(failed + "\n"); return }
                LiveReload.markRunning(project, from: liveSources)
                LiveSlots.clear(project)
                LiveReload.forgetLibraries(project)
                process = try start(app, project: project, from: number, output: output)
            }
            switch await LiveReload.verdict(project) {
            case .unchanged:
                report.append("VERDICT \(number): UNCHANGED")
                try tell("unchanged")
            case .reopen(let why): try await refused(why)
            case .reload(let changed):
                let running = process
                deliveries[project.dir.path] = { library, whole, retired in
                    // Delivered as the app is sent it: the library under the change's name, its markers first, and the
                    // process's answer awaited, which is what Lamp commits on.
                    let answer = runtime.appendingPathComponent("reloaded.txt")
                    try? fm.removeItem(at: answer)
                    if whole { try? Data().write(to: live.appendingPathComponent("whole\(number)")) }
                    try? retired.joined(separator: ",").write(to: live.appendingPathComponent("retired\(number).txt"), atomically: true, encoding: .utf8)
                    let staged = live.appendingPathComponent("hot\(number).staging.dylib")
                    try? fm.copyItem(at: library, to: staged)
                    try? fm.moveItem(at: staged, to: live.appendingPathComponent("hot\(number).dylib"))
                    for _ in 0..<1200 {
                        if let read = try? String(contentsOf: answer, encoding: .utf8) {
                            // Its first line; the second names the library it answers.
                            let text = read.components(separatedBy: "\n")[0]
                            if text.hasPrefix("ok") { return nil }
                            return text.hasPrefix("failed: ") ? String(text.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines) : "the app couldn't take it"
                        }
                        if !running.isRunning { return "the app didn't answer" }
                        try? await Task.sleep(for: .milliseconds(50))
                    }
                    return "the app didn't answer"
                }
                let outcome = await LiveReload.put(project, changed: changed, token: "x")
                deliveries[project.dir.path] = nil
                switch outcome {
                case .went(let said): report.append("VERDICT \(number): RELOAD" + (said.isEmpty ? "" : " (" + said.joined(separator: "; ") + ")"))
                case .reopen(let why): try await refused(why)
                }
            }
        }
        // The process prints its last lines and ends; one that doesn't is ended.
        for _ in 0..<1200 where process.isRunning { try await Task.sleep(for: .milliseconds(50)) }
        end(process)
        try await Task.sleep(for: .milliseconds(100))
        report.append("== run")
        report += output.lines
        // A file by its path in the app: the case's folder is made anew each run, under this Mac's home folder.
        return (report.joined(separator: "\n") + "\n").replacingOccurrences(of: liveSources.path + "/", with: "")
            .replacingOccurrences(of: project.dir.path, with: "<app>")
    }

    /// The case's process, with the app's folder and how many changes its binary already holds; what it prints
    /// goes to `output`.
    private static func start(_ app: String, project: LampProject, from: Int, output: Output) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: app)
        process.arguments = [project.dir.path, String(from)]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil } else { output.add(String(decoding: data, as: UTF8.self)) }
        }
        try process.run()
        return process
    }

    private static func end(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        TestShell.wait(for: process, timeout: 10)
    }

    /// What the processes print, in order, whichever of them printed it.
    private final class Output: @unchecked Sendable {
        private let lock = NSLock()
        private var text = ""
        func add(_ more: String) { lock.withLock { text += more } }
        var current: String { lock.withLock { text } }
        var lines: [String] { lock.withLock { text.components(separatedBy: "\n").filter { !$0.hasPrefix("objc[") && !$0.isEmpty } } }
    }

    /// The live copy of the app's sources, as build.sh makes it (`Template.liveCopySteps`): the copy step's perl over
    /// each file, with spare places and final classes for the app's own.
    private static func copyLive(_ project: LampProject) async throws {
        let fm = FileManager.default
        let sources = project.dir.appendingPathComponent("Sources"), live = LiveReload.sources(project)
        try? fm.removeItem(at: live)
        try fm.createDirectory(at: live, withIntermediateDirectories: true)
        let perl = LiveReload.folder(project).appendingPathComponent("live.pl").path
        let files = swiftFiles(in: sources)
        await LiveSlots.noteByteStructs(project)
        let bytes = "-bytes=" + LiveReload.folder(project).appendingPathComponent(LiveSlots.byteStructsFile).path
        let names = try await shell("/usr/bin/perl", [perl, "scan", "-own=LampSupport.swift,LampScene.swift", bytes] + files.map { sources.appendingPathComponent($0).path })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for file in files {
            let to = live.appendingPathComponent(file)
            try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: sources.appendingPathComponent(file), to: to)
            let own = ["LampSupport.swift", "LampHarness.swift"].contains((file as NSString).lastPathComponent)
            _ = try await shell("/usr/bin/perl", [perl, "\(LiveSlots.count)", names, own ? "" : "sf", to.path])
        }
    }

    private static func swiftFiles(in folder: URL) -> [String] {
        let base = folder.standardizedFileURL.path + "/"
        let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        return items.filter { $0.pathExtension == "swift" }.map { String($0.standardizedFileURL.path.dropFirst(base.count)) }.sorted()
    }

    /// The live parts of the support template (`LampSpare`, the state box, the constants, `LampLive`), standing on
    /// their own: the app's folder is the case's, its token "x".
    private static func support(for project: LampProject) throws -> String {
        let template = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Lamp/Template.swift")
        let text = try String(contentsOf: template, encoding: .utf8)
        let start = try XCTUnwrap(text.range(of: "    struct LampSpare: Codable, Hashable, @unchecked Sendable {"))
        let live = try XCTUnwrap(text.range(of: "    @MainActor @Observable final class LampLive {"))
        let end = try XCTUnwrap(text.range(of: "\n    }\n", range: live.upperBound..<text.endIndex))
        let install = "enum LampInstall { static let token = \"x\", note = \"t\" }\n"
        return "import Combine\nimport Foundation\nimport CryptoKit\nimport MachO\nimport Observation\nimport SwiftUI\n" + install + text[start.lowerBound..<end.upperBound]
            .replacingOccurrences(of: "LampInstall.app + \"/.lamp/live/\"", with: "\"\(project.dir.path)/.lamp/live/\"")
            .replacingOccurrences(of: "LampRuntime.folder.appendingPathComponent(\"reloaded.txt\")", with: "URL(fileURLWithPath: \"\(Runtime.macFolder(project).path)/reloaded.txt\")")
            .replacingOccurrences(of: "private func load(", with: "func load(")
    }

    /// What a case's `Main.swift` calls to take the n-th change: it waits for Lamp to deliver the library or a
    /// verdict, loads the library as the app loads one and answers, or says why there was none. A change the
    /// process was built with (after a restart) is in it already.
    private static let harness = """
        import Foundation
        import CryptoKit
        @MainActor func reload(_ n: Int) {
            setvbuf(stdout, nil, _IONBF, 0)
            let folder = CommandLine.arguments[1], live = folder + "/.lamp/live/", path = live + "hot\\(n).dylib"
            let builtWith = Int(CommandLine.arguments.dropFirst(2).first ?? "0") ?? 0
            if n <= builtWith { print("RELOAD \\(n): in the restart"); return }
            let fm = FileManager.default, verdict = live + "verdict\\(n).txt", deadline = Date().addingTimeInterval(240)
            while !fm.fileExists(atPath: path), !fm.fileExists(atPath: verdict), Date() < deadline { usleep(50_000) }
            if !fm.fileExists(atPath: path) {
                let why = ((try? String(contentsOf: URL(fileURLWithPath: verdict), encoding: .utf8)) ?? "(no answer from Lamp)").trimmingCharacters(in: .whitespacesAndNewlines)
                print("RELOAD \\(n): " + (why == "unchanged" ? "UNCHANGED" : "REOPEN " + why))
                return
            }
            let whole = fm.fileExists(atPath: live + "whole\\(n)")
            let retired = ((try? String(contentsOf: URL(fileURLWithPath: live + "retired\\(n).txt"), encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",").map(String.init)
            let key = SymmetricKey(data: Data("x".utf8))
            let signature = HMAC<SHA256>.authenticationCode(for: Data(("reload\\n\\(path)" + (whole ? "\\nwhole" : "") + (retired.isEmpty ? "" : "\\nretired " + retired.joined(separator: ","))).utf8), using: key).map { String(format: "%02x", $0) }.joined()
            LampLive.shared.load(path, signature: signature, whole: whole, retired: retired)
            // "ok" or why not; not how many pointers were rebound, which is the toolchain's count, not the case's.
            let answer = ((try? String(contentsOf: URL(fileURLWithPath: folder + "/.lamp/runtime/reloaded.txt"), encoding: .utf8)) ?? "no answer").components(separatedBy: "\\n")[0]
            print("RELOAD \\(n)" + (whole ? " (whole)" : "") + ": " + (answer.hasPrefix("ok") ? "ok" : answer))
        }
        """

    /// Runs a program and gives its output, waiting off the main actor so other cases' work goes on meanwhile.
    private static func shell(_ executable: String, _ arguments: [String]) async throws -> String {
        // Off the caller's thread: TestShell blocks while it waits.
        let (status, output) = await Task.detached { TestShell.run(executable, arguments) }.value
        guard status == 0 else {
            throw NSError(domain: "LiveCasesTests", code: Int(status), userInfo: [NSLocalizedDescriptionKey: output])
        }
        return output
    }
}
