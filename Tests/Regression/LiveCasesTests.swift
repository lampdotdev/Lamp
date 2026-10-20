import XCTest
import CryptoKit
@testable import Lamp

/// Every case under Tests/LiveCases run through Lamp's own live reload: the verdict, the layout check, the spares,
/// the compile and the object rewrite (`LiveReload.verdict`, `LiveReload.put`), with the library handed to a process
/// built from the case's sources instead of to an open app (`LiveReload.deliver`), which then loads each change in
/// turn and prints what it sees. A case is a folder with the app's sources (`Main.swift`, whose `reload(n)` loads the
/// n-th change, and the rest), one `afterN/` folder per change with the files it rewrites, and `expect.txt`: the
/// verdicts Lamp gave and what the app printed, which is the record of which side each change lands on. The first
/// line of each print says what's wanted, so a difference reads as a change of behaviour, right or wrong. A
/// `keep-open` file says the person didn't press Reload after a refused change, so the next is judged against the
/// code still running.
///
/// Every case takes a build and a few compiles, so they run only when asked: `LAMP_LIVE_CASES=1` runs them all,
/// `LAMP_LIVE_CASES=name,name` some; `LAMP_LIVE_CASES_RECORD=1` writes each case's `expect.txt` instead of checking it.
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
        var failures: [String] = []
        for name in names {
            let got = try await Self.run(Self.casesFolder.appendingPathComponent(name))
            let expectation = Self.casesFolder.appendingPathComponent(name).appendingPathComponent("expect.txt")
            if record {
                try got.write(to: expectation, atomically: true, encoding: .utf8)
                continue
            }
            let expected = (try? String(contentsOf: expectation, encoding: .utf8)) ?? ""
            if got != expected { failures.append("\(name):\n--- expected\n\(expected)\n--- got\n\(got)") }
        }
        XCTAssertTrue(failures.isEmpty, "\(failures.count) of \(names.count) cases changed\n\n" + failures.joined(separator: "\n\n"))
    }

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
        try fm.createDirectory(at: Runtime.macFolder(project), withIntermediateDirectories: true)
        let live = LiveReload.folder(project)
        try fm.createDirectory(at: live, withIntermediateDirectories: true)
        try Template.livePerl.write(to: live.appendingPathComponent("live.pl"), atomically: true, encoding: .utf8)
        try copyLive(project)
        // The app, as a live build makes it, from the live copy.
        let sdk = try shell("/usr/bin/xcrun", ["--show-sdk-path"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let liveSources = LiveReload.sources(project)
        let files = swiftFiles(in: liveSources).map { liveSources.appendingPathComponent($0).path }
        let app = project.dir.appendingPathComponent("app").path
        do {
            _ = try shell("/usr/bin/xcrun", ["swiftc", "-module-name", project.exe, "-parse-as-library", "-Onone", "-enable-testing", "-D", "DEBUG", "-D", "LAMP_LIVE",
                                              "-target", "arm64-apple-macosx14.0", "-sdk", sdk] + files + ["-Xlinker", "-interposable", "-o", app])
        } catch {
            // A case whose app doesn't build is reported as such, and the rest still run.
            let errors = (error as NSError).localizedDescription.components(separatedBy: "\n").filter { $0.contains("error:") }.prefix(3)
            return "BUILD FAILED\n" + errors.joined(separator: "\n") + "\n"
        }
        LiveReload.markRunning(project)
        LiveSlots.clear(project)
        var report: [String] = []
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
            try copyLive(project)
            func reopen(_ why: String) throws {
                report.append("VERDICT \(number): REOPEN (\(LiveReload.readable(why)))")
                try why.write(to: live.appendingPathComponent("verdict\(number).txt"), atomically: true, encoding: .utf8)
                // The person pressed Reload: the app now runs this code, as the whole build installed it.
                guard !keepOpen else { return }
                LiveReload.markRunning(project, from: liveSources)
                LiveSlots.clear(project)
            }
            switch await LiveReload.verdict(project) {
            case .unchanged: report.append("VERDICT \(number): UNCHANGED")
            case .reopen(let why): try reopen(why)
            case .reload(let changed):
                var delivered: (library: URL, whole: Bool, retired: [String])?
                LiveReload.deliver = { library, _, _, whole, retired in delivered = (library, whole, retired); return nil }
                let outcome = await LiveReload.put(project, changed: changed, token: "x")
                LiveReload.deliver = nil
                switch outcome {
                case .reopen(let why): try reopen(why)
                case .went(let said):
                    guard let delivered else { report.append("VERDICT \(number): RELOAD (nothing to load)"); continue }
                    try fm.copyItem(at: delivered.library, to: live.appendingPathComponent("hot\(number).dylib"))
                    if delivered.whole { try Data().write(to: live.appendingPathComponent("whole\(number)")) }
                    try delivered.retired.joined(separator: ",").write(to: live.appendingPathComponent("retired\(number).txt"), atomically: true, encoding: .utf8)
                    report.append("VERDICT \(number): RELOAD" + (said.isEmpty ? "" : " (" + said.joined(separator: "; ") + ")"))
                }
            }
        }
        report.append("== run")
        let output = try shell(app, [project.dir.path], allowFailure: true)
        report += output.components(separatedBy: "\n").filter { !$0.hasPrefix("objc[") && !$0.isEmpty }
        return report.joined(separator: "\n") + "\n"
    }

    /// The live copy of the app's sources, as build.sh makes it (`Template.liveCopySteps`): the copy step's perl over
    /// each file, with spare places and final classes for the app's own.
    private static func copyLive(_ project: LampProject) throws {
        let fm = FileManager.default
        let sources = project.dir.appendingPathComponent("Sources"), live = LiveReload.sources(project)
        try? fm.removeItem(at: live)
        try fm.createDirectory(at: live, withIntermediateDirectories: true)
        let perl = LiveReload.folder(project).appendingPathComponent("live.pl").path
        let files = swiftFiles(in: sources)
        let names = try shell("/usr/bin/perl", [perl, "scan", "-own=LampSupport.swift,LampScene.swift"] + files.map { sources.appendingPathComponent($0).path })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        for file in files {
            let to = live.appendingPathComponent(file)
            try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: sources.appendingPathComponent(file), to: to)
            let own = ["LampSupport.swift", "LampHarness.swift"].contains((file as NSString).lastPathComponent)
            _ = try shell("/usr/bin/perl", [perl, "\(LiveSlots.count)", names, own ? "" : "sf", to.path])
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
        return "import Foundation\nimport CryptoKit\nimport MachO\nimport Observation\nimport SwiftUI\n" + install + text[start.lowerBound..<end.upperBound]
            .replacingOccurrences(of: "LampInstall.app + \"/.lamp/live/\"", with: "\"\(project.dir.path)/.lamp/live/\"")
            .replacingOccurrences(of: "LampRuntime.folder.appendingPathComponent(\"reloaded.txt\")", with: "URL(fileURLWithPath: \"\(Runtime.macFolder(project).path)/reloaded.txt\")")
            .replacingOccurrences(of: "private func load(", with: "func load(")
    }

    /// What a case's `Main.swift` calls to take the n-th change: the library Lamp made, loaded as the app loads one,
    /// or the verdict that kept it out.
    private static let harness = """
        import Foundation
        import CryptoKit
        @MainActor func reload(_ n: Int) {
            setvbuf(stdout, nil, _IONBF, 0)
            let folder = CommandLine.arguments[1], live = folder + "/.lamp/live/", path = live + "hot\\(n).dylib"
            if !FileManager.default.fileExists(atPath: path) {
                print("RELOAD \\(n): REOPEN " + ((try? String(contentsOf: URL(fileURLWithPath: live + "verdict\\(n).txt"), encoding: .utf8)) ?? "(no library and no verdict)").trimmingCharacters(in: .whitespacesAndNewlines))
                return
            }
            let whole = FileManager.default.fileExists(atPath: live + "whole\\(n)")
            let retired = ((try? String(contentsOf: URL(fileURLWithPath: live + "retired\\(n).txt"), encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",").map(String.init)
            let key = SymmetricKey(data: Data("x".utf8))
            let signature = HMAC<SHA256>.authenticationCode(for: Data(("reload\\n\\(path)" + (whole ? "\\nwhole" : "") + (retired.isEmpty ? "" : "\\nretired " + retired.joined(separator: ","))).utf8), using: key).map { String(format: "%02x", $0) }.joined()
            LampLive.shared.load(path, signature: signature, whole: whole, retired: retired)
            // "ok" or why not; not how many pointers were rebound, which is the toolchain's count, not the case's.
            let answer = ((try? String(contentsOf: URL(fileURLWithPath: folder + "/.lamp/runtime/reloaded.txt"), encoding: .utf8)) ?? "no answer").trimmingCharacters(in: .whitespacesAndNewlines)
            print("RELOAD \\(n)" + (whole ? " (whole)" : "") + ": " + (answer.hasPrefix("ok") ? "ok" : answer))
        }
        """

    private static func shell(_ executable: String, _ arguments: [String], allowFailure: Bool = false) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard allowFailure || process.terminationStatus == 0 else {
            throw NSError(domain: "LiveCasesTests", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: output])
        }
        return output
    }
}
