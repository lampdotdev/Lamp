import XCTest
@testable import Lamp

/// What a wish's commands downloaded (`Fetched`): written down before the command runs, and every later command
/// checked against it. The model here is a stand-in whose answers depend only on what it is shown, so each test is
/// about what reaches it, in what order, and what the code does with no answer.
@MainActor
final class FetchedTests: XCTestCase {
    private var kept = Fetched.folder
    private let wish = "codec"

    override func setUp() async throws {
        kept = Fetched.folder
        Fetched.folder = FileManager.default.temporaryDirectory.appendingPathComponent("fetched-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: Fetched.folder)
        Fetched.folder = kept
    }

    nonisolated private static func noul(_ p: Double) -> [String: Any] { ["noul": p] }

    /// A model that reads the commands as a careful one would for these chains: curl fetches; a command naming a
    /// file an earlier one saved derives from it or runs it.
    nonisolated private static let reader: @Sendable ([String: Any], [String: Any]) async throws -> [String: Any] = { state, questions in
        let command = state["command"] as? String ?? ""
        let earlier = (state["earlier_downloads"] as? [String] ?? []).joined(separator: "\n")
        func mentioned(_ name: String) -> Bool { command.contains(name) && earlier.contains(name) }
        var answers: [String: Any] = ["fetches": noul(command.contains("curl") ? 0.95 : 0.02)]
        if questions["runsFetched"] != nil {
            let names = ["codec-data.bin", "helper"]
            let touches = names.contains(where: mentioned)
            let copies = touches && (command.hasPrefix("cp ") || command.hasPrefix("mv ") || command.hasPrefix("ln "))
            answers["derives"] = noul(copies ? 0.9 : 0.05)
            answers["runsFetched"] = noul(touches && !copies ? 0.9 : 0.05)
        }
        return answers
    }

    private func step(_ command: String, queue: Fetched.Queue, asked: @escaping @MainActor () -> Void = {},
                      decide: @escaping @Sendable ([String: Any], [String: Any]) async throws -> [String: Any] = FetchedTests.reader) async -> Fetched.Step {
        await Fetched.step(command, wish: wish, folder: "/Apps/codec", queue: queue, decide: decide,
                           ask: { asked(); return false }, decision: { true })
    }

    /// The chain a renamed program takes: fetched under a data name, copied to another, made executable, run.
    /// The copy is written down as the download was, so the two commands that follow it get the card.
    func testACopyOfADownloadIsCaughtWhenItIsMadeExecutableAndRun() async {
        let queue = Fetched.Queue()
        var cards = 0
        let fetch = await step("curl -sL https://example.net/codec-data.bin -o data/codec-data.bin", queue: queue) { cards += 1 }
        XCTAssertEqual(fetch, Fetched.Step(allowed: true, asked: false))
        let copy = await step("cp data/codec-data.bin helper", queue: queue) { cards += 1 }
        XCTAssertEqual(copy, Fetched.Step(allowed: true, asked: false))
        XCTAssertEqual(Fetched.records(of: wish).count, 2, "the copy is on the record before the next command is checked")
        let chmod = await step("chmod +x helper", queue: queue) { cards += 1 }
        let run = await step("./helper -i photo.png photo.webp", queue: queue) { cards += 1 }
        XCTAssertEqual([chmod.asked, run.asked], [true, true])
        XCTAssertEqual([chmod.allowed, run.allowed], [false, false], "refused on the card, they don't run")
        XCTAssertEqual(cards, 2)
    }

    /// Recording finishes before the next check starts, however long it takes: a command checked while an earlier one's
    /// answer is still on its way waits for it and is shown it.
    func testTheNextCommandWaitsForTheRecord() async {
        let queue = Fetched.Queue()
        let slow: @Sendable ([String: Any], [String: Any]) async throws -> [String: Any] = { state, questions in
            if (state["command"] as? String ?? "").contains("curl") { try await Task.sleep(for: .milliseconds(300)) }
            return try await FetchedTests.reader(state, questions)
        }
        async let fetch = step("curl -sL https://example.net/codec-data.bin -o data/codec-data.bin", queue: queue, decide: slow)
        try? await Task.sleep(for: .milliseconds(20))
        async let run = step("./data/codec-data.bin", queue: queue, decide: slow)
        let (first, second) = await (fetch, run)
        XCTAssertFalse(first.asked)
        XCTAssertTrue(second.asked, "the run was checked against the download that started before it")
    }

    /// No answer counts against the command: with nothing on the record it is written down as a possible download,
    /// and with something on the record it gets the card.
    func testWhenTheModelDoesNotAnswerTheCommandIsRecordedAndThenAsks() async {
        let queue = Fetched.Queue()
        let down: @Sendable ([String: Any], [String: Any]) async throws -> [String: Any] = { _, _ in throw URLError(.notConnectedToInternet) }
        let first = await step("make", queue: queue, decide: down)
        XCTAssertEqual(first, Fetched.Step(allowed: true, asked: false))
        XCTAssertEqual(Fetched.records(of: wish).map(\.sure), [false])
        var cards = 0
        let second = await step("ls", queue: queue, asked: { cards += 1 }, decide: down)
        XCTAssertTrue(second.asked)
        XCTAssertEqual(cards, 1)
    }

    /// An answer missing one question is no answer.
    func testAPartAnswerAsks() async {
        Fetched.record("curl -o data/codec-data.bin https://example.net/codec-data.bin", sure: true, for: wish)
        let outcome = await Fetched.check(command: "ls", folder: "/Apps/codec", against: Fetched.records(of: wish)) { _, _ in
            ["fetches": ["noul": 0.01], "derives": ["noul": 0.01]]
        }
        XCTAssertEqual(outcome, Fetched.Outcome(asks: true, records: true, sure: false))
    }

    /// Nothing is dropped for being old or many: a long record is checked in parts, every record in one of them,
    /// and one part that finds the command or doesn't answer is enough.
    func testEveryRecordIsCheckedHoweverManyThereAre() async {
        for n in 0..<95 { Fetched.record("curl -o data/file\(n).json https://example.net/\(n).json", sure: true, for: wish) }
        Fetched.record("curl -o data/codec-data.bin https://example.net/codec-data.bin", sure: true, for: wish)
        let seen = Seen()
        let outcome = await Fetched.check(command: "./data/codec-data.bin", folder: "/Apps/codec",
                                          against: Fetched.records(of: wish)) { state, questions in
            let earlier = state["earlier_downloads"] as? [String] ?? []
            await seen.add(earlier)
            return try await FetchedTests.reader(state, questions)
        }
        let shown = await seen.all
        XCTAssertEqual(shown.count, 96)
        let largest = await seen.largest
        XCTAssertLessThanOrEqual(largest, Fetched.batch)
        XCTAssertTrue(outcome.asks, "the download that matters was the last of 96")

        let oneDown = await Fetched.check(command: "ls data", folder: "/Apps/codec", against: Fetched.records(of: wish)) { state, questions in
            if (state["earlier_downloads"] as? [String] ?? []).contains(where: { $0.contains("file50") }) { throw URLError(.timedOut) }
            return try await FetchedTests.reader(state, questions)
        }
        XCTAssertTrue(oneDown.asks)
    }

    /// The record outlives Lamp (it's a file) and the wish: a deleted wish's downloads are checked for every other one.
    func testADeletedWishLeavesItsDownloadsToEveryOther() async {
        Fetched.record("curl -o /tmp/helper https://example.net/helper", sure: true, for: wish)
        Fetched.retire(wish)
        XCTAssertTrue(Fetched.records(of: wish).isEmpty)
        let other = Fetched.checkedAgainst(for: "another")
        XCTAssertEqual(other.map(\.command), ["curl -o /tmp/helper https://example.net/helper"])
        let outcome = await Fetched.check(command: "/tmp/helper", folder: "/Apps/another", against: other, decide: FetchedTests.reader)
        XCTAssertTrue(outcome.asks)
    }

    /// A record that can't be read stands for an unknown download, never for none.
    func testAnUnreadableRecordIsADownload() throws {
        try FileManager.default.createDirectory(at: Fetched.folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: Fetched.folder.appendingPathComponent("\(wish).json"))
        XCTAssertEqual(Fetched.records(of: wish).map(\.sure), [false])
    }

    /// A command that has to be written down and can't be doesn't run.
    func testACommandThatCantBeWrittenDownDoesntRun() async throws {
        Fetched.folder = URL(fileURLWithPath: "/dev/null/fetched")
        let step = await step("curl -o data/x https://example.net/x", queue: Fetched.Queue())
        XCTAssertEqual(step, Fetched.Step(allowed: false, asked: false, written: false))
    }
}

private actor Seen {
    var all: [String] = []
    var largest = 0
    func add(_ part: [String]) { all += part; largest = max(largest, part.count) }
}
