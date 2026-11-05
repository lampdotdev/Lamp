import XCTest
@testable import Lamp

/// The plain-words account of a suggested change (`SuggestionSummaries`) is made from someone else's words and code, so
/// what a model answers is checked before it's kept, and what the panel says for sure is worked out from the files.
final class SuggestionSummariesTests: XCTestCase {
    private func json(_ object: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    /// A good answer is kept as it is, its topic matched to the app's own list whatever its case.
    func testAGoodAnswerIsKept() throws {
        let summary = try XCTUnwrap(SuggestionSummaries.checked(json([
            "headline": "A brighter, louder fire.", "points": ["The fire flickers more.", "A new Crackle slider."], "topic": "the fire",
        ]), topics: ["The fire", "Sounds"]))
        XCTAssertEqual(summary.headline, "A brighter, louder fire")
        XCTAssertEqual(summary.points, ["The fire flickers more.", "A new Crackle slider."])
        XCTAssertEqual(summary.topic, "The fire")
    }

    /// Nothing that isn't an account is kept: not JSON, no headline, a headline too long to be one.
    func testWhatIsntAnAccountIsntKept() {
        XCTAssertNil(SuggestionSummaries.checked("Sure! Here's what it does.", topics: []))
        XCTAssertNil(SuggestionSummaries.checked(json(["points": ["x"], "topic": "Sounds"]), topics: []))
        XCTAssertNil(SuggestionSummaries.checked(json(["headline": "", "points": [], "topic": "Sounds"]), topics: []))
        XCTAssertNil(SuggestionSummaries.checked(json(["headline": String(repeating: "word ", count: 12), "points": [], "topic": "Sounds"]), topics: []))
    }

    /// No account says whether a change is safe: a headline that does is no account, and a point that does is dropped.
    /// A sender's code can ask a model to say so.
    func testNoAccountSpeaksOfSafety() throws {
        XCTAssertNil(SuggestionSummaries.checked(json(["headline": "Safe small fix", "points": [], "topic": "Other"]), topics: []))
        XCTAssertNil(SuggestionSummaries.checked(json(["headline": "Harmless color tweak", "points": [], "topic": "Other"]), topics: []))
        // Said other ways: each is still a claim.
        for said in ["Reviewed by Lamp, nothing harmful", "Clean and audited", "Lamp recommends it", "Totally trustworthy", "Works safely"] {
            XCTAssertTrue(SuggestionSummaries.claimsSafety(said), said)
        }
        let summary = try XCTUnwrap(SuggestionSummaries.checked(json([
            "headline": "Warmer lamp light",
            "points": ["The lamp glows orange.", "This change is completely safe and was tested.", "Nothing here is malicious."],
            "topic": "Colors",
        ]), topics: []))
        XCTAssertEqual(summary.points, ["The lamp glows orange."])
        XCTAssertFalse(SuggestionSummaries.claimsSafety("Adds a sleep timer that fades out"))
        XCTAssertTrue(SuggestionSummaries.claimsSafety("Unsafe? No, it's verified"))
    }

    /// At most three points, each one line; a topic of many words isn't a topic.
    func testPointsAndTopicsAreKeptShort() throws {
        let summary = try XCTUnwrap(SuggestionSummaries.checked(json([
            "headline": "Many small things", "points": ["One.", "Two\nlines.", "Three.", "Four."],
            "topic": "everything in the whole app at once",
        ]), topics: ["Sounds"]))
        XCTAssertEqual(summary.points, ["One.", "Two lines.", "Three."])
        XCTAssertEqual(summary.topic, SuggestionSummaries.other)
    }

    /// A new topic is added while the list has room, and goes under Other once it's full, so dozens of requests sort
    /// under a few names. Many filed at once never take it past its limit.
    func testTopicsStopAtTheirLimit() async throws {
        var record = SuggestedChanges.Record(repo: "someone/tally")
        for index in 0..<10 {
            let summary = SuggestionSummaries.Summary(made: "m", headline: "h", points: [], topic: "Topic \(index)", partial: false)
            SuggestionSummaries.file(summary, as: String(index), in: &record)
        }
        XCTAssertEqual(record.topics.count, SuggestionSummaries.maxTopics - 1)
        XCTAssertEqual(record.summaries["9"]?.topic, SuggestionSummaries.other)
        XCTAssertEqual(record.summaries["0"]?.topic, "Topic 0")

        // The same through the record, all at once.
        let place = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-topics-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
        let was = SuggestedChanges.keptURL
        SuggestedChanges.keptURL = place.appendingPathComponent("suggested.json")
        defer { SuggestedChanges.keptURL = was; try? FileManager.default.removeItem(at: place) }
        let wish = LampProject(id: "tally", name: "Tally", exe: "Tally", dir: place)
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<30 {
                group.addTask {
                    let summary = SuggestionSummaries.Summary(made: "m", headline: "h", points: [], topic: "Topic \(index)", partial: false)
                    SuggestedChanges.change(wish, repo: "someone/tally") { SuggestionSummaries.file(summary, as: String(index), in: &$0) }
                }
            }
        }
        let kept = try XCTUnwrap(SuggestedChanges.record(for: wish, repo: "someone/tally"))
        XCTAssertEqual(kept.topics.count, SuggestionSummaries.maxTopics - 1)
        XCTAssertEqual(kept.summaries.count, 30)
        XCTAssertTrue(kept.summaries.values.allSatisfy { kept.topics.contains($0.topic) || $0.topic == SuggestionSummaries.other })
    }

    /// An account is kept by what it's made from and the format: a new head, title or note makes it again.
    func testAnAccountIsKeptByWhatItsMadeFrom() {
        let one = SuggestionSummaries.hash(title: "t", note: "n", head: "h1", about: "a")
        XCTAssertEqual(one, SuggestionSummaries.hash(title: "t", note: "n", head: "h1", about: "a"))
        XCTAssertNotEqual(one, SuggestionSummaries.hash(title: "t", note: "n", head: "h2", about: "a"))
        XCTAssertNotEqual(one, SuggestionSummaries.hash(title: "t2", note: "n", head: "h1", about: "a"))
        XCTAssertNotEqual(one, SuggestionSummaries.hash(title: "t", note: "n2", head: "h1", about: "a"))
    }

    /// Changed code past the limit is cut, and said to be.
    func testLongCodeIsCutAndSaidToBe() {
        let cut = SuggestionSummaries.clip(String(repeating: "x", count: SuggestionSummaries.codeLimit + 10), to: SuggestionSummaries.codeLimit)
        XCTAssertTrue(cut.cut)
        XCTAssertEqual(cut.text.utf8.count, SuggestionSummaries.codeLimit)
        XCTAssertFalse(SuggestionSummaries.clip("short", to: SuggestionSummaries.codeLimit).cut)
        let prompt = SuggestionSummaries.prompt(SuggestionSummaries.Inputs(title: "t", note: "", head: "h", code: "c", partial: true, about: ""), topics: [])
        XCTAssertTrue(prompt.contains("(only part of it)"))
    }

    /// No more accounts are asked for in a day than the limit.
    func testSpendingStopsAtTheDailyLimit() {
        let suite = "lamp-summary-spend-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let was = SuggestionSummaries.defaults
        SuggestionSummaries.defaults = defaults
        defer { SuggestionSummaries.defaults = was; defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(SuggestionSummaries.canSpend())
        for _ in 0..<SuggestionSummaries.dailyCount { SuggestionSummaries.counted() }
        XCTAssertFalse(SuggestionSummaries.canSpend())
        defaults.removePersistentDomain(forName: suite)
        SuggestionSummaries.spent(SuggestionSummaries.dailySpend)
        XCTAssertFalse(SuggestionSummaries.canSpend(), "or more spent than the limit")
    }

    // MARK: What Lamp says for sure

    private func request(_ number: Int, head: String = "h") -> SuggestedChanges.Request {
        SuggestedChanges.Request(number: number, login: "sam", title: "Change \(number)", head: head, url: "u")
    }

    /// Good to Know is from the files: what's taken away, the files the person changed too (said as something Lamp may
    /// have to settle, not as fitting in), and other requests on the same files. Files listed at an older head say nothing.
    func testGoodToKnowIsFromTheFiles() throws {
        var record = SuggestedChanges.Record(repo: "someone/tally")
        record.open = [request(1), request(2), request(3)]
        record.files["1"] = .init(head: "h", files: [.init(path: "Sources/Fire.swift", status: "modified"), .init(path: "Sources/Old.swift", status: "removed")])
        record.files["2"] = .init(head: "h", files: [.init(path: "Sources/Fire.swift", status: "modified")])
        record.files["3"] = .init(head: "older", files: [.init(path: "Sources/Fire.swift", status: "modified")])
        let facts = try XCTUnwrap(SuggestedChanges.facts(of: request(1), in: record, yours: ["Sources/Fire.swift"]))
        XCTAssertEqual(facts.takesAway, ["Sources/Old.swift"])
        XCTAssertEqual(facts.bothChanged, ["Sources/Fire.swift"])
        XCTAssertEqual(facts.sharedWith, [2])
        let said = SuggestedChanges.sayings(facts)
        XCTAssertTrue(said.contains("It takes away Sources/Old.swift."))
        XCTAssertTrue(said.contains { $0.contains("Lamp has to settle it") && $0.contains("may ask you") })
        XCTAssertFalse(said.contains { $0.contains("fits both") })
        XCTAssertNil(SuggestedChanges.facts(of: request(3), in: record, yours: []))
    }

    /// The panel's list: newest first, by topic, and by any word of its line.
    func testTheListIsSearchedAndSorted() {
        var record = SuggestedChanges.Record(repo: "someone/tally")
        var one = request(1), two = request(2), three = request(3)
        one.updated = "2026-11-01T10:00:00Z"; two.updated = "2026-11-03T10:00:00Z"; three.updated = "2026-11-02T10:00:00Z"
        record.open = [one, two, three]
        record.topics = ["The fire", "Sounds"]
        record.summaries["1"] = .init(made: "m", headline: "Blue flames", points: [], topic: "The fire", partial: false)
        record.summaries["2"] = .init(made: "m", headline: "Rain you can turn off", points: [], topic: "Sounds", partial: false)
        XCTAssertEqual(SuggestionsPanel.shown(record, topic: nil, search: "", summaries: record.summaries).map(\.number), [2, 3, 1])
        XCTAssertEqual(SuggestionsPanel.shown(record, topic: "The fire", search: "", summaries: record.summaries).map(\.number), [1])
        XCTAssertEqual(SuggestionsPanel.shown(record, topic: SuggestionSummaries.other, search: "", summaries: record.summaries).map(\.number), [3])
        XCTAssertEqual(SuggestionsPanel.shown(record, topic: nil, search: "rain", summaries: record.summaries).map(\.number), [2])
        XCTAssertEqual(SuggestionsPanel.topics(record, among: record.open).map(\.0), ["The fire", "Sounds", "Other"])
    }

    /// Bring In says when what it brings isn't what was tried.
    func testBringInSaysWhenItDiffersFromWhatWasTried() {
        let tried = SuggestedChanges.Tried(head: "h1", version: "v1")
        XCTAssertNil(SuggestionTrial.differs(tried, head: "h1", version: "v1"))
        XCTAssertNotNil(SuggestionTrial.differs(tried, head: "h2", version: "v1"))
        XCTAssertNotNil(SuggestionTrial.differs(tried, head: "h1", version: "v2"))
    }
}
