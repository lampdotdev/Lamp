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

    // MARK: What the copy reads

    @discardableResult
    private func git(_ command: String, in folder: URL) -> String {
        let run = TestShell.run("git -c user.name=Sam -c user.email=sam@example.com -c commit.gpgsign=false \(command)", in: folder)
        XCTAssertEqual(run.status, 0, run.output)
        return run.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func write(_ data: Data, _ path: String, in folder: URL) throws {
        let file = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
    }

    /// A request that adds a picture and a text bigger than what's laid out for reading: the copy has both whole, and the
    /// files as they were, once the clone they came from is gone. A link out of the request isn't followed.
    func testTheCopyHasTheRequestsFilesWholeAndAsTheyWere() async throws {
        let fm = FileManager.default
        let clone = root.appendingPathComponent("clone/bike-map")
        let outside = root.appendingPathComponent("secret.txt")
        try Data("not the request's".utf8).write(to: outside)
        try write(Data("let lanes = false\n".utf8), "Sources/App.swift", in: clone)
        git("init -q && git add -A && git commit -qm base", in: clone)
        let base = git("rev-parse HEAD", in: clone)
        let picture = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00]) + Data((0..<4096).map { UInt8($0 % 251) })
        try write(picture, "Assets/lanes.png", in: clone)
        try write(Data((String(repeating: "a lane on every street\n", count: 25_000) + "THE LAST LANE\n").utf8), "Notes/lanes.txt", in: clone)
        try write(Data("let lanes = true\n".utf8), "Sources/App.swift", in: clone)
        try fm.createSymbolicLink(atPath: clone.appendingPathComponent("Assets/peek.txt").path, withDestinationPath: outside.path)
        git("add -A && git commit -qm lanes", in: clone)
        let head = git("rev-parse HEAD", in: clone)
        let pull = BringIn.Pull(repo: "someone/bike-map", base: base, head: head, request: 12, from: "sam", leftOut: nil, checked: true)
        let request = SuggestedChanges.Request(number: 12, login: "sam", title: "Bike lanes", head: head, url: "https://github.com/someone/bike-map/pull/12")
        let laidOut = root.appendingPathComponent("laid-out")

        try await SuggestedChanges.layOutForCopy(pull, request: request, body: "Adds lanes.", tree: clone, into: laidOut)
        try fm.removeItem(at: root.appendingPathComponent("clone"))

        XCTAssertEqual(try? Data(contentsOf: laidOut.appendingPathComponent("latest/Assets/lanes.png")), picture)
        let diff = try String(contentsOf: laidOut.appendingPathComponent("changes.diff"), encoding: .utf8)
        XCTAssertGreaterThan(diff.utf8.count, 400_000)
        XCTAssertTrue(diff.contains("+THE LAST LANE"), "the whole change, not cut short")
        XCTAssertEqual(TestShell.run("git show \(base):Sources/App.swift", in: laidOut.appendingPathComponent("repo")).output, "let lanes = false\n")
        let link = laidOut.appendingPathComponent("latest/Assets/peek.txt").path
        XCTAssertNil(try? fm.destinationOfSymbolicLink(atPath: link))
        XCTAssertFalse(fm.fileExists(atPath: link))

        let copy = LampProject(id: "bikemapupdate", name: "Bike Map Update", exe: "BikeMapUpdate", dir: root.appendingPathComponent("copy"))
        try AppUpdates.place(laidOut, job: part(), in: copy)
        let placed = copy.dir.appendingPathComponent(AppUpdates.Job.folder)
        XCTAssertEqual(try? Data(contentsOf: placed.appendingPathComponent("latest/Assets/lanes.png")), picture)
        XCTAssertNil(try? fm.destinationOfSymbolicLink(atPath: placed.appendingPathComponent("latest/Assets/peek.txt").path))
        XCTAssertEqual(TestShell.run("git show \(base):Sources/App.swift", in: placed.appendingPathComponent("repo")).output, "let lanes = false\n")
    }

    /// Without the commit the request started from, nothing is laid out: no change is made up from what's missing.
    func testNothingIsLaidOutWithoutWhereTheRequestStarted() async throws {
        let clone = root.appendingPathComponent("clone/bike-map")
        try write(Data("let lanes = true\n".utf8), "Sources/App.swift", in: clone)
        git("init -q && git add -A && git commit -qm lanes", in: clone)
        let head = git("rev-parse HEAD", in: clone)
        let pull = BringIn.Pull(repo: "someone/bike-map", base: "1111111111111111111111111111111111111111", head: head, request: 12, from: "sam")
        let request = SuggestedChanges.Request(number: 12, login: "sam", title: "Bike lanes", head: head, url: "https://github.com/someone/bike-map/pull/12")
        let laidOut = root.appendingPathComponent("laid-out")
        do {
            try await SuggestedChanges.layOutForCopy(pull, request: request, body: "", tree: clone, into: laidOut)
            XCTFail("laid out a change with no start")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: laidOut.path))
    }

    // MARK: Asked again in the copy

    /// A part that failed is asked for again in the copy's chat in the person's own words. A turn that changed the copy
    /// settles it; one that only replied doesn't; one that asks waits, and the answer to that question settles it.
    func testAskingAgainInTheCopyCanFinishAFailedPart() {
        var job = part()
        XCTAssertEqual(AppUpdates.outcome(of: [QueuedMessage(text: AppUpdates.request(for: job))], job: job, end: .changed, errors: true, asking: false), .failed)
        XCTAssertEqual(AppUpdates.outcome(of: [QueuedMessage(text: "Try again")], job: job, end: .changed, errors: false, asking: false), .ready)
        XCTAssertNil(AppUpdates.outcome(of: [QueuedMessage(text: "Why did it fail?")], job: job, end: .replied, errors: false, asking: false))
        XCTAssertEqual(AppUpdates.outcome(of: [QueuedMessage(text: "Fix that build error")], job: job, end: .replied, errors: false, asking: true), .waiting)
        let asked = UUID()
        job.cards = [asked.uuidString]
        XCTAssertEqual(AppUpdates.outcome(of: [QueuedMessage(text: "The receipts folder", card: asked)], job: job, end: .changed, errors: false, asking: false), .ready)
        // An update's copy keeps its rule: Review Update… is how it's tried again, and a chat about something else there
        // doesn't settle it.
        let update = AppUpdates.Job(url: repo, base: job.base, target: job.target, wish: "bikemap")
        XCTAssertNil(AppUpdates.outcome(of: [QueuedMessage(text: "Try again")], job: update, end: .changed, errors: false, asking: false))
    }

    // MARK: What goes with the copy

    /// What the copy reads stays in the copy: a credit naming a file in it, even through a link out of it, takes
    /// nothing of it into the shared file the review and Update This App are made from.
    func testWhatTheCopyReadsNeverGoesWithIt() throws {
        let fm = FileManager.default
        let copy = LampProject(id: "bikemapupdate", name: "Bike Map Update", exe: "BikeMapUpdate", dir: root.appendingPathComponent("copy"))
        try write(Data("import SwiftUI\n".utf8), "Sources/App.swift", in: copy.dir)
        try write(Data("MIT License\n\nCopyright (c) Someone\n".utf8), "LICENSE", in: copy.dir)
        try write(Data("Fonts by others.\n".utf8), ".lamp/update/latest/NOTICE", in: copy.dir)
        try write(Data("let lanes = true\n".utf8), ".lamp/update/latest/Sources/App.swift", in: copy.dir)
        let outside = root.appendingPathComponent("outside")
        try write(Data("Not the copy's.\n".utf8), "NOTICE", in: outside)
        try fm.createSymbolicLink(atPath: copy.dir.appendingPathComponent(".lamp/update/latest/out").path, withDestinationPath: outside.path)
        try Template.saveMeta(copy)
        let source = Credits.Source(name: "Bike Map", author: "Someone", url: repo, commit: "1111111111111111111111111111111111111111", license: "MIT",
                                    licenseFile: "LICENSE", noticeFiles: [".lamp/update/latest/NOTICE", ".lamp/update/latest/out/NOTICE"])
        try Credits(upstream: [source]).encoded().write(to: copy.dir.appendingPathComponent(Credits.file))

        let file = try Sharing.export(copy)
        let work = file.deletingLastPathComponent()
        defer { try? fm.removeItem(at: work) }
        let listed = TestShell.run("/usr/bin/zipinfo", ["-1", file.path]).output
        XCTAssertTrue(listed.contains("LICENSE"), listed)
        XCTAssertFalse(listed.contains(".lamp"), listed)
        XCTAssertFalse(listed.contains("NOTICE"), listed)
    }
}

/// pi reaches each of Lamp's tools at a route of the gateway's; one the gateway doesn't serve fails every call with Not
/// found (`suggested_changes` did, so pi could never read or bring in a suggested change).
final class PiRouteTests: XCTestCase {
    func testTheGatewayServesEveryRoutePiIsGiven() {
        XCTAssertEqual(Set(Agent.piRoutes.values).subtracting(Store.gatewayPaths), [])
        XCTAssertEqual(Agent.piRoutes["LAMP_SUGGESTED_URL"], "/agent/suggested")
    }
}
