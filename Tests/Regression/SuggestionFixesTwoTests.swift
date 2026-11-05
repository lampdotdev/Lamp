import XCTest
@testable import Lamp

/// More defects found in suggested changes, each shown by what it got wrong.
final class SuggestionFixesTwoTests: XCTestCase {
    private func folder() throws -> URL {
        let place = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-suggestion-fixes2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: place) }
        return place
    }

    private func sh(_ command: String, in dir: URL) throws {
        let ran = Subprocess.runBlocking("/bin/zsh", ["-c", command], cwd: dir, mergeErrors: true, timeout: 60)
        XCTAssertTrue(ran.ok, ran.output)
    }

    /// A try copies files git ignores too, so what it's pinned to covers them: changing one is a change.
    func testWhatATryIsPinnedToCoversFilesGitIgnores() async throws {
        let dir = try folder().appendingPathComponent("app")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        try "Resources/local.txt\n.lamp/\n".write(to: dir.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try "let a = 1\n".write(to: dir.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        try "one\n".write(to: dir.appendingPathComponent("Resources/local.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
        try sh("git init -q -b main && git add -A && git -c user.name=Lamp -c user.email=lamp@localhost commit -qm first", in: dir)
        let before = await SuggestionTrial.snapshot(of: dir)
        XCTAssertNotNil(before)
        try "two\n".write(to: dir.appendingPathComponent("Resources/local.txt"), atomically: true, encoding: .utf8)
        let after = await SuggestionTrial.snapshot(of: dir)
        XCTAssertNotNil(after)
        XCTAssertNotEqual(before, after, "an ignored file the try copies changed, and the fingerprint didn't")
    }

    /// An account kept from before headlines were held to six words isn't shown.
    func testAnAccountWithALongerHeadlineIsntShown() {
        var record = SuggestedChanges.Record(repo: "someone/tally")
        record.open = [SuggestedChanges.Request(number: 1, login: "sam", title: "t", head: "h", url: "u")]
        let made = SuggestionSummaries.hash(title: "t", note: "", head: "h", about: "a")
        record.summaries["1"] = .init(made: made, headline: "A brighter and much louder fire tonight", points: [], topic: "Other", partial: false)
        XCTAssertTrue(SuggestionSummaries.fresh(record, about: "a").isEmpty)
    }

    // MARK: Fresh to the app's description

    /// A project with its own record file, and the request it has.
    private func app(_ about: String) throws -> (project: LampProject, request: SuggestedChanges.Request) {
        let place = try folder()
        let was = (SuggestedChanges.keptURL, GitHubRepo.keptURL)
        SuggestedChanges.keptURL = place.appendingPathComponent("suggested.json")
        GitHubRepo.keptURL = place.appendingPathComponent("kept.json")
        addTeardownBlock { SuggestedChanges.keptURL = was.0; GitHubRepo.keptURL = was.1 }
        let dir = place.appendingPathComponent("app")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try about.write(to: dir.appendingPathComponent("APP.md"), atomically: true, encoding: .utf8)
        let project = LampProject(id: "app", name: "App", exe: "App", dir: dir, instance: "app-instance")
        GitHubRepo.keep(GitHubRepo.Repo(repo: "someone/app", url: "u", commit: "c"), for: project)
        let request = SuggestedChanges.Request(number: 1, login: "sam", title: "t", head: "h", url: "u")
        SuggestedChanges.change(project, repo: "someone/app") { $0.open = [request] }
        return (project, request)
    }

    /// An answer made from the app's description as it was isn't kept once APP.md is edited, and an account kept from
    /// before an edit stops showing at once.
    func testAnEditedDescriptionMakesAnAccountStale() throws {
        let (project, request) = try app("# App\nKeeps chores.\n")
        let made = SuggestionSummaries.hash(title: request.title, note: "", head: request.head, about: SuggestionSummaries.about(project))
        let summary = SuggestionSummaries.Summary(made: made, headline: "Blue flames", points: [], topic: "Other", partial: false)
        XCTAssertTrue(SuggestionSummaries.keep(summary, as: "1", in: project, repo: "someone/app"))
        XCTAssertEqual(SuggestionsPanel.shownRecord(for: project)?.summaries.keys.sorted(), ["1"])

        try "# App\nKeeps chores and errands.\n".write(to: project.dir.appendingPathComponent("APP.md"), atomically: true, encoding: .utf8)
        XCTAssertEqual(SuggestionsPanel.shownRecord(for: project)?.summaries.isEmpty, true, "shown from the old description")
        XCTAssertFalse(SuggestionSummaries.keep(summary, as: "1", in: project, repo: "someone/app"), "kept from the old description")
    }

    // MARK: Reachable

    /// An app whose requests are all set aside is still listed, so Put Back can be reached; it counts none as new.
    func testAnAppWithOnlySetAsideRequestsIsStillListed() {
        var record = SuggestedChanges.Record(repo: "someone/app")
        record.open = [SuggestedChanges.Request(number: 1, login: "sam", title: "t", head: "h", url: "u")]
        record.hidden["1"] = "h"
        XCTAssertTrue(record.isListed)
        XCTAssertEqual(record.newCount, 0)
        record.ended["1"] = .closed
        XCTAssertFalse(record.isListed)
    }

    // MARK: One at a time

    /// Summaries asked for at once are made one after another: the same request twice is asked about once, and no two
    /// questions are ever out at the same time, so the daily limit is checked against what's been spent.
    func testSummariesAreMadeOneAtATime() async throws {
        let (project, request) = try app("# App\n")
        let gh = project.dir.deletingLastPathComponent().appendingPathComponent("gh")
        try """
        #!/bin/zsh
        [[ "$*" == *files* ]] && { echo '{"filename":"a.swift","status":"modified","patch":"@@ -1 +1 @@"}'; exit 0 }
        [[ "$*" == *.head.sha* ]] && { echo h; exit 0 }
        exit 0
        """.write(to: gh, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gh.path)
        let suite = "lamp-summary-serial-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let wasDefaults = SuggestionSummaries.defaults
        SuggestionSummaries.defaults = defaults
        final class Count: @unchecked Sendable { let lock = NSLock(); var asked = 0, out = 0, most = 0 }
        let count = Count()
        SuggestionSummaries.answering = { _ in
            count.lock.withLock { count.asked += 1; count.out += 1; count.most = max(count.most, count.out) }
            try? await Task.sleep(for: .milliseconds(200))
            count.lock.withLock { count.out -= 1 }
            return AppAI.ToolFreeAnswer(text: #"{"headline": "Blue flames", "points": ["The flames are blue."], "topic": "The fire"}"#, cost: 0.01)
        }
        defer {
            SuggestionSummaries.answering = nil
            SuggestionSummaries.defaults = wasDefaults
            defaults.removePersistentDomain(forName: suite)
        }
        let others = (2...4).map { SuggestedChanges.Request(number: $0, login: "sam", title: "t\($0)", head: "h", url: "u") }
        SuggestedChanges.change(project, repo: "someone/app") { $0.open = [request] + others }
        await withTaskGroup(of: Bool.self) { group in
            for asked in [request, request, request] + others {
                group.addTask { await SuggestionSummaries.shared.make(for: asked, in: project, repo: "someone/app", gh: gh.path) }
            }
        }
        XCTAssertEqual(count.most, 1, "two questions were out at once")
        XCTAssertEqual(count.asked, 4, "the same request was paid for more than once")
        XCTAssertEqual(SuggestedChanges.record(for: project, repo: "someone/app")?.summaries.count, 4)
    }

    /// What a run that tried a tool, or whose version was stopped by another run's tool before it was kept, said is never
    /// kept: no account, and no note that it had none, so it's asked again once the engine can be trusted.
    func testAnAnswerFromAStoppedVersionIsNeverKept() async throws {
        let (project, request) = try app("# App\n")
        let gh = project.dir.deletingLastPathComponent().appendingPathComponent("gh")
        try """
        #!/bin/zsh
        [[ "$*" == *files* ]] && { echo '{"filename":"a.swift","status":"modified","patch":"@@ -1 +1 @@"}'; exit 0 }
        [[ "$*" == *.head.sha* ]] && { echo h; exit 0 }
        exit 0
        """.write(to: gh, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gh.path)
        let suite = "lamp-summary-stopped-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let wasDefaults = SuggestionSummaries.defaults
        SuggestionSummaries.defaults = defaults
        let version = "test-\(UUID().uuidString)"
        defer {
            SuggestionSummaries.answering = nil
            SuggestionSummaries.defaults = wasDefaults
            defaults.removePersistentDomain(forName: suite)
            var stopped = UserDefaults.standard.dictionary(forKey: "sideAnswerStopped") ?? [:]
            stopped["claude"] = (stopped["claude"] as? [String] ?? []).filter { $0 != version }
            UserDefaults.standard.set(stopped, forKey: "sideAnswerStopped")
        }
        let good = #"{"headline": "Blue flames", "points": ["The flames are blue."], "topic": "The fire"}"#
        // The run's answer comes back, but its version was stopped by another run's tool meanwhile.
        SuggestionSummaries.answering = { _ in
            SideAnswer.stop(.claude, version: version)
            return AppAI.ToolFreeAnswer(text: good, cost: 0, engine: .claude, version: version)
        }
        var made = await SuggestionSummaries.shared.make(for: request, in: project, repo: "someone/app", gh: gh.path)
        XCTAssertFalse(made)
        var record = try XCTUnwrap(SuggestedChanges.record(for: project, repo: "someone/app"))
        XCTAssertTrue(record.summaries.isEmpty)
        XCTAssertTrue(record.unexplained.isEmpty)

        // A run with no answer (tools offered, a tool tried, its list missing): nothing kept either.
        SuggestionSummaries.answering = { _ in nil }
        made = await SuggestionSummaries.shared.make(for: request, in: project, repo: "someone/app", gh: gh.path)
        XCTAssertFalse(made)
        record = try XCTUnwrap(SuggestedChanges.record(for: project, repo: "someone/app"))
        XCTAssertTrue(record.summaries.isEmpty)
        XCTAssertTrue(record.unexplained.isEmpty)

        // An engine's answer whose version still stands is kept.
        SuggestionSummaries.answering = { _ in AppAI.ToolFreeAnswer(text: good, cost: 0, engine: .claude, version: "test-good") }
        made = await SuggestionSummaries.shared.make(for: request, in: project, repo: "someone/app", gh: gh.path)
        XCTAssertTrue(made)
    }
}
