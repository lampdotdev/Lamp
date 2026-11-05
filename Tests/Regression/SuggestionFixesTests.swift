import XCTest
@testable import Lamp

/// Defects found in suggested changes, each shown by what it got wrong.
final class SuggestionFixesTests: XCTestCase {
    private func folder() throws -> URL {
        let place = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-suggestion-fixes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: place) }
        return place
    }

    /// An app's APP.md that's a link elsewhere gives the summary nothing: what it points at never goes to a model.
    func testTheAppsDescriptionIsNeverReadThroughALink() throws {
        let place = try folder()
        let secret = place.appendingPathComponent("secret.txt")
        try "the person's private notes".write(to: secret, atomically: true, encoding: .utf8)
        let dir = place.appendingPathComponent("app")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("APP.md"), withDestinationURL: secret)
        let project = LampProject(id: "app", name: "App", exe: "App", dir: dir)
        XCTAssertEqual(SuggestionSummaries.about(project), "")
        try FileManager.default.removeItem(at: dir.appendingPathComponent("APP.md"))
        try "# App\nKeeps chores.\n".write(to: dir.appendingPathComponent("APP.md"), atomically: true, encoding: .utf8)
        XCTAssertEqual(SuggestionSummaries.about(project), "# App\nKeeps chores.\n", "a plain file is read")
    }

    /// The headline is held to the six words the model is asked for.
    func testAHeadlineIsSixWordsAtMost() throws {
        func answer(_ headline: String) -> String {
            String(decoding: try! JSONSerialization.data(withJSONObject: ["headline": headline, "points": [], "topic": "Other"]), as: UTF8.self)
        }
        XCTAssertNotNil(SuggestionSummaries.checked(answer("A brighter and much louder fire"), topics: []))
        XCTAssertNil(SuggestionSummaries.checked(answer("A brighter and much louder fire tonight"), topics: []))
    }

    /// A build still running in a try's folder (Lamp crashed mid-compile, or it was only signalled) is stopped and waited
    /// for before the folder goes, whatever started it.
    func testABuildLeftInATrysFolderIsStoppedBeforeItsTakenAway() throws {
        let place = try folder()
        let trial = place.appendingPathComponent("Trials/gen")
        let app = trial.appendingPathComponent("App")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        // Standing in for an orphaned compile: a process of its own, working in the copy, that ignores a polite ask.
        let build = Process()
        build.executableURL = URL(fileURLWithPath: "/bin/sh")
        build.arguments = ["-c", "trap '' TERM; while true; do sleep 1; done"]
        build.currentDirectoryURL = app
        try build.run()
        addTeardownBlock { if build.isRunning { kill(build.processIdentifier, SIGKILL) } }
        Thread.sleep(forTimeInterval: 0.3)
        SuggestionTrial.remove(trial, home: place.appendingPathComponent("home"))
        for _ in 0..<50 where build.isRunning { Thread.sleep(forTimeInterval: 0.1) }
        XCTAssertFalse(build.isRunning, "the build was left running")
        XCTAssertFalse(FileManager.default.fileExists(atPath: trial.path))
    }

    // MARK: Fresh accounts

    private func request(_ number: Int, head: String, title: String = "Change") -> SuggestedChanges.Request {
        SuggestedChanges.Request(number: number, login: "sam", title: title, head: head, url: "u")
    }

    /// An account is of the request as it was made: once the request has a new head or a new title, the old one isn't
    /// shown, and an answer that comes back after the request moved on isn't kept over it.
    func testAnAccountIsShownAndKeptOnlyForTheRequestAsItIs() {
        var record = SuggestedChanges.Record(repo: "someone/tally")
        record.open = [request(1, head: "h1")]
        let made = SuggestionSummaries.hash(title: "Change", note: "", head: "h1", about: "about")
        record.summaries["1"] = .init(made: made, headline: "Blue flames", points: [], topic: "Other", partial: false)
        XCTAssertEqual(SuggestionSummaries.fresh(record, about: "about").keys.sorted(), ["1"])
        XCTAssertTrue(SuggestionSummaries.fresh(record, about: "the app described again").isEmpty)

        // New commits: the account of h1 is no longer shown.
        record.open = [request(1, head: "h2")]
        XCTAssertTrue(SuggestionSummaries.fresh(record, about: "about").isEmpty)
        // A late answer worked out from h1 isn't filed now that the request is at h2.
        XCTAssertFalse(SuggestionSummaries.isCurrent(made, "1", in: record, about: "about"))
        XCTAssertTrue(SuggestionSummaries.isCurrent(SuggestionSummaries.hash(title: "Change", note: "", head: "h2", about: "about"), "1",
                                                    in: record, about: "about"))
        // Retitled at the same head: the same.
        record.open = [request(1, head: "h1", title: "Change, renamed")]
        XCTAssertTrue(SuggestionSummaries.fresh(record, about: "about").isEmpty)
    }

    // MARK: Codex

    /// Codex answers for summaries only as the run proven beside a turn launches it: the tested model, its catalog entry
    /// replaced, every tool feature off. The flags-only sealed launch is never what it gets.
    func testCodexSummariesGoTheProvenWay() throws {
        let route = SideAnswer.Route(engine: .codex, executable: "/usr/bin/true", configFolder: "/nonexistent", model: SideAnswer.testedCodexModel,
                                     system: "", path: "/usr/bin:/bin")
        let launch = try XCTUnwrap(SideAnswer.launch(route, prompt: "p", transcript: nil, folder: try folder()))
        let arguments = launch.arguments.joined(separator: " ")
        XCTAssertTrue(arguments.contains("model_catalog_json="))
        XCTAssertTrue(arguments.contains("--disable shell_tool"))
        XCTAssertTrue(arguments.contains("-m \(SideAnswer.testedCodexModel)"))
        XCTAssertFalse(SideAnswer.isTested(.codex, version: "0.0.1"), "an untested Codex gets no run")
    }
}
