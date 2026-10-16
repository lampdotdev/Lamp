import XCTest
@testable import Lamp

/// Countdowns comes with four sample countdowns, and Clear Examples promises to keep the person's own. One they
/// edited and saved is theirs: it must survive Clear Examples, in the running app and after a relaunch, while the
/// untouched samples go. The starter's model and store are compiled with the support code Lamp writes into it and
/// run against a made-up home folder, so its saved data is real and nobody's own.
final class CountdownsExamplesTests: XCTestCase {
    func testAnEditedSampleSurvivesClearExamples() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folder = repo.appendingPathComponent("Resources/Starters/countdowns")
        let starter = try XCTUnwrap(Starters.parse(String(contentsOf: folder.appendingPathComponent("starter.md"), encoding: .utf8),
                                                   folder: folder))
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-countdowns-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        let project = try Template.draft(name: starter.name, in: work.appendingPathComponent("apps"))
        try Template.fill(project)
        try Starters.copy(starter, into: project)
        try Template.writeOwnedFiles(for: project)

        // The editor hands the store a copy of the countdown and saves it on Save; Cancel drops the copy, so a
        // sample edited and cancelled is never saved at all.
        let program = """
        import Foundation
        @main struct Check {
            @MainActor static func main() {
                let store = CountdownStore()
                var renamed = store.countdowns.first { $0.name == "Concert" }!
                renamed.name = "Concert with Sam"
                store.save(renamed)
                var moved = store.countdowns.first { $0.name == "Weekend away" }!
                moved.date = Calendar.current.date(byAdding: .day, value: 3, to: moved.date)!
                store.save(moved)
                var cancelled = store.countdowns.first { $0.name == "Half marathon" }!
                cancelled.name = "Marathon"
                store.clearExamples()
                print(store.countdowns.map(\\.name).sorted())
                print(CountdownStore().countdowns.map(\\.name).sorted())
            }
        }
        """
        try program.write(to: work.appendingPathComponent("check.swift"), atomically: true, encoding: .utf8)
        let sources = ["LampSupport.swift", "Countdown.swift", "CountdownStore.swift"]
            .map { "\"\(project.dir.appendingPathComponent("Sources/\($0)").path)\"" }.joined(separator: " ")
        let built = try run(Shell.compatibleSDK + "xcrun swiftc -parse-as-library -o check check.swift \(sources) 2>&1", in: work)
        XCTAssertEqual(built.status, 0, built.output)
        let home = work.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let ran = try run("CFFIXED_USER_HOME=\"\(home.path)\" ./check", in: work)
        XCTAssertEqual(ran.status, 0, ran.output)
        XCTAssertEqual(ran.output, """
        ["Concert with Sam", "Weekend away"]
        ["Concert with Sam", "Weekend away"]

        """)
    }

    private func run(_ command: String, in directory: URL) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = directory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
