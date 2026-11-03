import XCTest
@testable import Lamp

/// What a new game's first draft rests on: the page's word that it has drawn, what the turn's end says of its window,
/// and knowing whether a run begins its conversation.
@MainActor final class FirstDraftTests: XCTestCase {
    func testAnEarlierLaunchsWordDoesNotAnswerThisOne() async {
        let frames = FirstFrames()
        frames.report(app: "game", launch: 1)
        let waiting = Task { @MainActor in await frames.wait(app: "game", launch: 2, limit: .milliseconds(100)) }
        await Task.yield()
        frames.report(app: "game", launch: 1)
        frames.report(app: "preview", launch: 2)
        let outcome = await waiting.value
        XCTAssertEqual(outcome, .timedOut)
    }

    func testThisLaunchsWordEndsTheWait() async {
        let frames = FirstFrames()
        let waiting = Task { @MainActor in await frames.wait(app: "game", launch: 2, limit: .seconds(30)) }
        await Task.yield()
        frames.report(app: "game", launch: 2)
        let outcome = await waiting.value
        XCTAssertEqual(outcome, .drawn)
    }

    func testWordThatCameBeforeTheWaitCounts() async {
        let frames = FirstFrames()
        frames.report(app: "game", launch: 7)
        let outcome = await frames.wait(app: "game", launch: 7, limit: .seconds(30))
        XCTAssertEqual(outcome, .drawn)
    }

    func testAPageThatNeverDrawsTimesOutOnce() async {
        let frames = FirstFrames()
        let outcome = await frames.wait(app: "game", launch: 1, limit: .milliseconds(30))
        XCTAssertEqual(outcome, .timedOut)
        frames.report(app: "game", launch: 1)   // nothing left to settle
        frames.end(app: "game")
    }

    /// A page's word that comes after the turn's wait ran out, but before Lamp asks to hear of it late, still counts; a word
    /// from another launch never does, and a late one runs once.
    func testAWordBetweenTheWaitAndTheLateWatchStillCounts() async {
        let frames = FirstFrames()
        let outcome = await frames.wait(app: "game", launch: 1, limit: .milliseconds(30))
        XCTAssertEqual(outcome, .timedOut)
        frames.report(app: "game", launch: 1)
        var ran = 0
        frames.whenDrawn(app: "game", launch: 1) { ran += 1 }
        XCTAssertEqual(ran, 1, "the word came already")

        frames.whenDrawn(app: "other", launch: 2) { ran += 1 }
        frames.report(app: "other", launch: 3)
        XCTAssertEqual(ran, 1, "another launch's word")
        frames.report(app: "other", launch: 2)
        frames.report(app: "other", launch: 2)
        XCTAssertEqual(ran, 2, "once")
    }

    /// A launch's word that came already, while its turn is still going, counts as on screen in that turn's own tally;
    /// after the turn's end it no longer changes the turn, whose lines are put right instead.
    func testALateFrameWithinItsTurnReachesTheTurnsTally() async {
        let frames = FirstFrames(), turn = Store.Turn()
        turn.began = Date()
        turn.outcomes.append(.opened)
        _ = await frames.wait(app: "game", launch: 7, limit: .milliseconds(20))
        frames.report(app: "game", launch: 7)
        var counted: Bool?
        frames.whenDrawn(app: "game", launch: 7) { counted = turn.drewLate(at: Date()) }
        XCTAssertEqual(counted, true)
        // The turn's end, as `runTurn` tallies it.
        turn.look.draftsDone = true
        let pace = Store.paceTally(began: turn.began, shown: turn.shown, outcomes: turn.outcomes)
        XCTAssertNotEqual(pace, Store.nothingShown)
        XCTAssertTrue(pace?.hasPrefix("First change on screen after") == true, String(describing: pace))

        let ended = Store.Turn()
        ended.look.draftsDone = true
        XCTAssertFalse(ended.drewLate(at: Date()), "after the turn's end")
        XCTAssertTrue(ended.shown.isEmpty)
    }

    func testStoppingOrClosingEndsTheWaitAsNeitherFrameNorTimeout() async {
        let frames = FirstFrames()
        let waiting = Task { @MainActor in await frames.wait(app: "game", launch: 1, limit: .seconds(30)) }
        await Task.yield()
        frames.end(app: "game")
        let outcome = await waiting.value
        XCTAssertEqual(outcome, .ended)
    }

    func testOnlyATimelyCleanFrameIsSaidToBeOnScreen() {
        XCTAssertTrue(Store.draftWords(.content)?.contains("where the person sees it") == true)
        for window: Store.DraftWindow? in [nil, .pending, .blank, .noPicture, .timedOut(seconds: 180), .closed] {
            XCTAssertFalse(Store.draftWords(window)?.contains("where the person sees it") == true, "\(String(describing: window))")
        }
        XCTAssertNil(Store.draftWords(.stopped))
    }

    /// The turn's end says ready only for a draft whose window drew; anything else says what's known, and no draft at all
    /// is said to be ready as any other app.
    func testATurnsEndSaysReadyOnlyForAWindowThatDrew() {
        XCTAssertEqual(Store.draftLine("Game", nil, updated: false), "Game is ready")
        XCTAssertEqual(Store.draftLine("Game", .content, updated: true), "Game is updated")
        for window: Store.DraftWindow in [.pending, .timedOut(seconds: 180), .blank, .noPicture] {
            let line = Store.draftLine("Game", window, updated: false) ?? ""
            XCTAssertTrue(line.hasPrefix("Game is open, but"), "\(window): \(line)")
        }
        XCTAssertNil(Store.draftLine("Game", .closed, updated: false))
    }

    /// A first draft that drew one color, then a change the page said is on screen: the window counts as drawn from then,
    /// and the draft's watch, ending later, doesn't take that back.
    func testAChangeTheWindowShowedOutranksTheFirstDraftsVerdict() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("first-draft-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = Store(testingAt: root)
        let turn = Store.Turn()
        turn.look.draftOpen.insert("game")
        turn.look.draftKnown["game"] = .blank
        XCTAssertFalse(store.windowDrew("game", in: turn))
        store.pageShowedChange("game", in: turn)
        XCTAssertTrue(store.windowDrew("game", in: turn))
        store.recordDraft(.timedOut(seconds: 180), for: "game", in: turn)
        XCTAssertTrue(store.windowDrew("game", in: turn), "a later verdict of the first draft doesn't undo it")
        let other = Store.Turn()
        other.look.draftOpen.insert("game")
        store.recordDraft(.blank, for: "game", in: other)
        XCTAssertEqual(other.look.draftKnown["game"], .blank)
    }

    /// A page that never said the change is on screen: the wait lets the turn go on, but nothing counts it as shown.
    func testAShowThatRanOutIsNotSaidToBeShown() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("first-draft-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = Store(testingAt: root)
        let game = LampProject(id: "game", name: "Game", exe: "Game", dir: root)
        store.awaitShown(game, limit: .milliseconds(50))
        let ranOut = await store.untilShown(game)
        XCTAssertFalse(ranOut)
        store.awaitShown(game, limit: .seconds(5))
        let waiting = Task { @MainActor in await store.untilShown(game) }
        await Task.yield()
        store.pageShown(game)
        let shown = await waiting.value
        XCTAssertTrue(shown)
    }

    /// A first draft's window that drew nothing within its watch, and draws after: the late frame is pictured as a timely
    /// one is. A picture of one color leaves it not ready; a picture of the game says it's on screen.
    func testALateFrameIsReadyOnlyWhenItsPictureShowsTheGame() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("first-draft-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func picture(_ name: String, game: Bool) throws -> URL {
            let width = 320, height = 180
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CocoaError(.fileWriteUnknown) }
            context.setFillColor(CGColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            if game {
                context.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1))
                context.fill(CGRect(x: 140, y: 70, width: 40, height: 40))
            }
            let url = dir.appendingPathComponent(name + ".png")
            guard let image = context.makeImage(), let file = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
            CGImageDestinationAddImage(file, image, nil)
            guard CGImageDestinationFinalize(file) else { throw CocoaError(.fileWriteUnknown) }
            return url
        }
        let blank = try picture("blank", game: false), game = try picture("game", game: true)
        XCTAssertTrue(GameKit.isBlank(blank))
        XCTAssertFalse(GameKit.isBlank(game))

        let store = Store.shared
        let saved = Store.draftPicture
        defer { Store.draftPicture = saved }
        func lateFrame(pictured: URL) async -> (Store.Turn, String) {
            let project = LampProject(id: "draft-late-" + UUID().uuidString, name: "Draft", exe: "Draft", dir: dir, platform: .game)
            Store.draftPicture = { _, _ in pictured }
            let turn = Store.Turn()
            turn.look.draftOpen.insert(project.id)
            let window = await store.watchDraft(project, launch: 7, in: turn, limit: 0.05)
            XCTAssertEqual(window, .timedOut(seconds: 0))
            store.recordDraft(window, for: project.id, in: turn)
            XCTAssertFalse(store.windowDrew(project.id, in: turn))
            store.firstFrames.report(app: project.id, launch: 7)
            // The late frame's picture is taken out of line: waited for here.
            for _ in 0..<100 where turn.look.draftKnown[project.id] == .timedOut(seconds: 0) { try? await Task.sleep(for: .milliseconds(20)) }
            store.firstFrames.forget(app: project.id)
            return (turn, project.id)
        }

        let (blankTurn, blankID) = await lateFrame(pictured: blank)
        XCTAssertEqual(blankTurn.look.draftKnown[blankID], .blank, "a late frame of one color isn't the game")
        XCTAssertFalse(store.windowDrew(blankID, in: blankTurn))

        let (gameTurn, gameID) = await lateFrame(pictured: game)
        XCTAssertEqual(gameTurn.look.draftKnown[gameID], .content, "a late frame that shows the game is on screen")
        XCTAssertTrue(store.windowDrew(gameID, in: gameTurn))
    }

    /// A first draft whose watch saw a frame of one color, and a later look whose picture shows the game: that picture is
    /// the newer word. A blank picture leaves the earlier word as it was.
    func testADraftThatLookedBlankThenShowsTheGameIsOnScreen() {
        let store = Store.shared, id = "draft-blank-" + UUID().uuidString
        let turn = Store.Turn()
        turn.look.draftOpen.insert(id)
        store.recordDraft(.blank, for: id, in: turn)
        XCTAssertFalse(store.windowDrew(id, in: turn))

        store.draftPictured(id, blank: true, in: turn)
        XCTAssertEqual(turn.look.draftKnown[id], .blank)
        store.draftPictured(id, blank: false, in: turn)
        XCTAssertTrue(store.windowDrew(id, in: turn), "a picture of the game clears the blank word")
    }

    /// Calls sent in one message on a part of the wish: the first to finish doesn't take the part from the others.
    func testAPartStaysHeldUntilTheLastCallOnItFinishes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("first-draft-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = Store(testingAt: root)
        let wish = LampProject(id: "wish", name: "Wish", exe: "Wish", dir: root)
        let part = LampProject(id: "part", name: "Part", exe: "Part", dir: root)
        let turn = Store.Turn()
        store.beginTurnForTest(turn, on: wish)
        var heldLater = false
        async let quick = store.underTurn(of: wish, part) { @MainActor in
            try? await Task.sleep(for: .milliseconds(20))
            return (200, [:])
        }
        async let slow = store.underTurn(of: wish, part) { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            heldLater = store.turnForTest(on: part) === turn
            return (200, [:])
        }
        _ = await (quick, slow)
        XCTAssertTrue(heldLater, "the slower call would find its turn gone, and stop")
        XCTAssertNil(store.turnForTest(on: part), "let go once the last has finished")
    }

    func testAConversationBeginsWhenPiHasNoRecordOfIt() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("first-draft-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let sessions = folder.appendingPathComponent(".lamp/pi-sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let project = LampProject(id: "game", name: "Game", exe: "Game", dir: folder)
        let id = "lamp-" + UUID().uuidString.lowercased()
        XCTAssertTrue(Agent.startsConversation(id, in: project), "an id alone is no conversation")
        try Data().write(to: sessions.appendingPathComponent("2026-11-02T10-00-00-000Z_\(id).jsonl"))
        XCTAssertFalse(Agent.startsConversation(id, in: project))
    }

    func testDefaultToolsAreSetBesideWhatElseTheSettingsSayAndReadBack() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("first-draft-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("settings.json")
        try #"{"compaction": {"enabled": true}, "lampCompactionStamp": "kept"}"#.write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(PiCompaction.setDefaultTools(["read", "tool_search"], in: folder))
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(saved["defaultTools"] as? [String], ["read", "tool_search"])
        XCTAssertEqual(saved["lampCompactionStamp"] as? String, "kept")
        XCTAssertNotNil(saved["compaction"])
        try "not json".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertFalse(PiCompaction.setDefaultTools(["read"], in: folder), "a run can't defer on settings it can't read")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "not json", "and they're left as they were")
    }
}

