import XCTest
@testable import Lamp

/// Part of someone's suggested change, prepared in a separate copy as an update of an adapted app is
/// (`Store.prepareSuggestion`): it's told apart from an update, and moves nothing that says the request came in.
final class SuggestionPartTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("lamp-suggestion-part-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private let repo = "https://github.com/someone/bike-map"
    private func part(_ wanted: String = "The bike lanes, not the night map") -> AppUpdates.Job {
        AppUpdates.Job(url: repo, base: "1111111111111111111111111111111111111111", target: "2222222222222222222222222222222222222222",
                       wish: "bikemap", suggestion: AppUpdates.Suggestion(number: 12, login: "sam", wanted: wanted))
    }

    /// Only the copy's own request finishes it: an update's request in its chat isn't it, nor is its request an update's.
    func testOnlyThePartsOwnRequestFinishesIt() {
        let job = part()
        XCTAssertNotEqual(AppUpdates.request(for: job), AppUpdates.request)
        XCTAssertTrue(AppUpdates.isUpdateTurn([QueuedMessage(text: AppUpdates.request(for: job))], job: job))
        XCTAssertFalse(AppUpdates.isUpdateTurn([QueuedMessage(text: AppUpdates.request)], job: job))
        let update = AppUpdates.Job(url: repo, base: job.base, target: job.target, wish: "bikemap")
        XCTAssertFalse(AppUpdates.isUpdateTurn([QueuedMessage(text: AppUpdates.request(for: job))], job: update))
    }

    /// Taking part of a request moves no credit to its head, even one naming the same repository: nothing may read it as
    /// the request brought in.
    func testAPartMovesNoCredit() {
        let source = Credits.Source(name: "Bike Map", author: "Someone", url: repo, commit: "1111111111111111111111111111111111111111", license: "MIT")
        let job = part()
        XCTAssertEqual(AppUpdates.accepted(job, in: Credits(upstream: [source])).upstream.first?.commit, source.commit)
        XCTAssertEqual(AppUpdates.credits(afterUpdating: Credits(upstream: [source]), with: Credits(), job: job).upstream.first?.commit, source.commit)
    }

    /// A copy whose job was written before parts existed is still an update; one with a part reads back as written.
    func testJobsReadBackWithAndWithoutAPart() throws {
        let copy = LampProject(id: "bikemapupdate", name: "Bike Map Update", exe: "BikeMapUpdate", dir: root)
        let folder = root.appendingPathComponent(AppUpdates.Job.folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"url":"https://github.com/someone/bike-map","base":"dcb453f","target":"13dd142","wish":"bikemap"}"#.utf8)
            .write(to: AppUpdates.Job.url(copy))
        XCTAssertNil(try XCTUnwrap(AppUpdates.Job.load(copy)).suggestion)
        try part().save(in: copy)
        XCTAssertEqual(AppUpdates.Job.load(copy), part())
    }

    /// What was laid out goes into the copy's .lamp beside the job, which is what keeps the copy from being opened.
    func testALaidOutPartIsPlacedWithItsJob() throws {
        let copy = LampProject(id: "bikemapupdate", name: "Bike Map Update", exe: "BikeMapUpdate", dir: root.appendingPathComponent("copy"))
        let laidOut = root.appendingPathComponent("laid-out")
        try FileManager.default.createDirectory(at: laidOut, withIntermediateDirectories: true)
        for name in ["about.md", "files.txt", "changes.diff"] { try Data(name.utf8).write(to: laidOut.appendingPathComponent(name)) }
        try AppUpdates.place(laidOut, job: part(), in: copy)
        let folder = copy.dir.appendingPathComponent(AppUpdates.Job.folder)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)), ["about.md", "files.txt", "changes.diff", "job.json"])
        XCTAssertFalse(AppUpdates.mayOpen(copy))
    }
}
