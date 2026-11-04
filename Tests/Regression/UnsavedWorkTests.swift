import XCTest
import Combine
@testable import Lamp

/// The person's chat, what's typed in its box and the files sent with it, when their files can't be written: each is
/// kept in memory, every chat and the desk say so (`Store.saveTrouble`), a full disk is told apart from other failures,
/// and the notice goes only once Try Again has written them.
@MainActor
final class UnsavedWorkTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-unsaved-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    private func setWritable(_ folder: URL, _ writable: Bool) throws {
        try FileManager.default.setAttributes([.posixPermissions: writable ? 0o755 : 0o555], ofItemAtPath: folder.path)
    }

    /// Waits for the chat queue's writes, then for what they told the main thread.
    private func settle(_ store: Store) async {
        store.flushChats()
        for _ in 0..<5 { try? await Task.sleep(for: .milliseconds(20)) }
    }

    func testAChatThatCantBeWrittenIsKeptAndSavedOnTryAgain() async throws {
        let wish = try Template.scaffold(name: "Tally", platform: .mac, in: root)
        let store = Store(testingAt: root)
        let project = try XCTUnwrap(store.current(wish))
        let lamp = project.dir.appendingPathComponent(".lamp")
        let chat = lamp.appendingPathComponent("chat.json")
        try setWritable(lamp, false)
        defer { try? setWritable(lamp, true) }

        store.log(project, .user, "Count my cups of tea")
        await settle(store)
        let trouble = try XCTUnwrap(store.saveTrouble, "a chat that wasn't written says so")
        XCTAssertFalse(trouble.diskFull, "a folder that can't be written isn't a full disk")
        XCTAssertEqual(trouble.text, ErrorMessages.chatNotSaved)
        XCTAssertFalse(FileManager.default.fileExists(atPath: chat.path))
        XCTAssertEqual(store.logs[project.id]?.last?.text, "Count my cups of tea", "kept in memory")

        store.retrySaving()
        await settle(store)
        XCTAssertNotNil(store.saveTrouble, "a try that fails again leaves the notice up")

        try setWritable(lamp, true)
        store.retrySaving()
        XCTAssertNotNil(store.saveTrouble, "not cleared before the write has landed")
        await settle(store)
        XCTAssertNil(store.saveTrouble)
        let saved = try JSONDecoder().decode([LogLine].self, from: Data(contentsOf: chat))
        XCTAssertEqual(saved.last?.text, "Count my cups of tea")
    }

    func testADraftThatCantBeWrittenKeepsItsWordsAndWhatItReplaces() async throws {
        let wish = try Template.scaffold(name: "Tally", platform: .mac, in: root)
        let store = Store(testingAt: root)
        let project = try XCTUnwrap(store.current(wish))
        let lamp = project.dir.appendingPathComponent(".lamp")
        try setWritable(lamp, false)
        defer { try? setWritable(lamp, true) }

        let replaced = UUID()
        store.saveDraft(Store.Draft(text: "Make it blue", replacing: replaced, setAsideText: "Earlier words"), for: project)
        store.flushDrafts()
        XCTAssertNotNil(store.saveTrouble)
        XCTAssertEqual(store.draft(for: project).text, "Make it blue", "kept in memory")

        try setWritable(lamp, true)
        store.retrySaving()
        XCTAssertNil(store.saveTrouble)
        func read(_ name: String) throws -> String { try String(contentsOf: lamp.appendingPathComponent(name), encoding: .utf8) }
        XCTAssertEqual(try read("draft.txt"), "Make it blue")
        XCTAssertEqual(try read("draft-replaces"), replaced.uuidString)
        XCTAssertEqual(try read("draft-set-aside.txt"), "Earlier words")
    }

    func testAFileThatCantBeCopiedGoesToItsMessageOnTryAgain() async throws {
        let wish = try Template.scaffold(name: "Tally", platform: .mac, in: root)
        let store = Store(testingAt: root)
        let project = try XCTUnwrap(store.current(wish))
        let attachments = project.dir.appendingPathComponent(Attachments.folder)
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("mockup.png")
        try Data([1, 2, 3]).write(to: file)
        try setWritable(attachments, false)
        defer { try? setWritable(attachments, true) }

        let saved = store.post([QueuedMessage(text: "Like this", attachments: [file])], to: project)
        XCTAssertEqual(saved, [])
        XCTAssertNotNil(store.saveTrouble)
        let line = try XCTUnwrap(store.logs[project.id]?.last)
        XCTAssertEqual(line.text, "Like this")
        XCTAssertNil(line.attachments)

        try setWritable(attachments, true)
        store.retrySaving()
        await settle(store)
        XCTAssertNil(store.saveTrouble)
        XCTAssertEqual(store.logs[project.id]?.first { $0.id == line.id }?.attachments, ["mockup.png"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: attachments.appendingPathComponent("mockup.png").path))
    }

    /// A file copied on Try Again belongs to its message only once the chat is written with it: until then the notice
    /// stays, and quitting asks.
    func testAFileCopiedOnTryAgainKeepsTheNoticeUntilItsChatIsWritten() async throws {
        let wish = try Template.scaffold(name: "Tally", platform: .mac, in: root)
        let store = Store(testingAt: root)
        let project = try XCTUnwrap(store.current(wish))
        let lamp = project.dir.appendingPathComponent(".lamp")
        let attachments = project.dir.appendingPathComponent(Attachments.folder)
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("mockup.png")
        try Data([1, 2, 3]).write(to: file)
        try setWritable(attachments, false)
        defer { try? setWritable(attachments, true); try? setWritable(lamp, true) }
        _ = store.post([QueuedMessage(text: "Like this", attachments: [file])], to: project)
        await settle(store)

        try setWritable(attachments, true)
        try setWritable(lamp, false)
        store.retrySaving()
        XCTAssertNotNil(store.saveTrouble, "the file is copied, but the chat naming it isn't written yet")
        await settle(store)
        XCTAssertNotNil(store.saveTrouble, "the chat naming the file couldn't be written")
        XCTAssertFalse(store.saveAllNow(), "quitting asks")

        try setWritable(lamp, true)
        XCTAssertTrue(store.saveAllNow())
        XCTAssertNil(store.saveTrouble)
        let saved = try JSONDecoder().decode([LogLine].self, from: Data(contentsOf: lamp.appendingPathComponent("chat.json")))
        XCTAssertEqual(saved.last?.attachments, ["mockup.png"])
    }

    /// The chat's write from before the file was recovered lands after Try Again: it doesn't hold the file, so the
    /// notice stays until the write that does has landed, and stays if that one fails.
    func testAnEarlierChatWriteDoesNotClearARecoveredFile() async throws {
        let wish = try Template.scaffold(name: "Tally", platform: .mac, in: root)
        let store = Store(testingAt: root)
        let project = try XCTUnwrap(store.current(wish))
        let lamp = project.dir.appendingPathComponent(".lamp")
        let attachments = project.dir.appendingPathComponent(Attachments.folder)
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("mockup.png")
        try Data([1, 2, 3]).write(to: file)
        try setWritable(attachments, false)
        defer { try? setWritable(attachments, true); try? setWritable(lamp, true) }
        _ = store.post([QueuedMessage(text: "Like this", attachments: [file])], to: project)
        // The chat's write lands on its queue; its word is still on the way to the main thread.
        store.flushChats()

        try setWritable(attachments, true)
        try setWritable(lamp, false)
        // Every value the notice takes from here on: it mustn't go, even for a moment.
        var shown: [Store.SaveTrouble?] = []
        let watching = store.$saveTrouble.dropFirst().sink { shown.append($0) }
        defer { watching.cancel() }
        store.retrySaving()
        await settle(store)
        XCTAssertFalse(shown.contains { $0 == nil }, "the write that landed was from before the file was in the chat")
        XCTAssertNotNil(store.saveTrouble, "the chat naming the file couldn't be written")

        try setWritable(lamp, true)
        store.retrySaving()
        await settle(store)
        XCTAssertNil(store.saveTrouble)
    }

    /// A wish not built yet is renamed by moving its folder to a new id: what it couldn't save goes with it.
    func testRenamingAWishKeepsWhatItCouldntSave() async throws {
        let draft = try Template.draft(name: "Untitled", in: root)
        let store = Store(testingAt: root)
        let project = try XCTUnwrap(store.current(draft))
        // A folder where the draft's file goes: only that write fails, and the rename itself goes through.
        let blocker = project.dir.appendingPathComponent(".lamp/draft.txt/kept")
        try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: true)
        store.saveDraft(Store.Draft(text: "Make it blue"), for: project)
        store.flushDrafts()
        XCTAssertNotNil(store.saveTrouble)

        let renamed = await store.performRename(project, to: "Tea Timer")
        XCTAssertNotEqual(renamed.id, project.id, "the folder moved to a new id")
        let newLamp = renamed.dir.appendingPathComponent(".lamp")
        XCTAssertNotNil(store.saveTrouble, "still unsaved after the rename")

        try FileManager.default.removeItem(at: newLamp.appendingPathComponent("draft.txt"))
        store.retrySaving()
        await settle(store)
        XCTAssertNil(store.saveTrouble)
        XCTAssertEqual(try String(contentsOf: newLamp.appendingPathComponent("draft.txt"), encoding: .utf8), "Make it blue")
    }

    /// Quitting while a chat's write is still on its queue: that write's word hasn't come back, so the chat is
    /// written again at once and its failure asks.
    func testQuittingDuringAChatWriteStillAsks() throws {
        let wish = try Template.scaffold(name: "Tally", platform: .mac, in: root)
        let store = Store(testingAt: root)
        let project = try XCTUnwrap(store.current(wish))
        let lamp = project.dir.appendingPathComponent(".lamp")
        try setWritable(lamp, false)
        defer { try? setWritable(lamp, true) }

        store.log(project, .user, "Count my cups of tea")
        store.flushChats()
        XCTAssertFalse(store.saveAllNow())
        XCTAssertNotNil(store.saveTrouble)
    }

    /// Quitting writes everything now and quits only once it's all on disk (the quit question's Retry). An earlier
    /// write's failure, told back after a later one landed, doesn't bring the notice back.
    func testQuittingSavesNowAndALateFailureDoesNotCountAgainstALaterSave() async throws {
        let wish = try Template.scaffold(name: "Tally", platform: .mac, in: root)
        let store = Store(testingAt: root)
        let project = try XCTUnwrap(store.current(wish))
        let lamp = project.dir.appendingPathComponent(".lamp")
        try setWritable(lamp, false)
        defer { try? setWritable(lamp, true) }

        store.log(project, .user, "Track my runs")
        store.saveDraft(Store.Draft(text: "and my swims"), for: project)
        XCTAssertFalse(store.saveAllNow(), "nothing can be written: the quit question is asked")
        XCTAssertNotNil(store.saveTrouble)

        // The queue's write fails, and its word is still on its way to the main thread when Retry writes at once.
        store.retrySaving()
        store.flushChats()
        try setWritable(lamp, true)
        XCTAssertTrue(store.saveAllNow(), "Retry with room quits")
        XCTAssertNil(store.saveTrouble)
        for _ in 0..<5 { try? await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNil(store.saveTrouble, "the earlier write's failure is older than the save that landed")
        XCTAssertEqual(try String(contentsOf: lamp.appendingPathComponent("draft.txt"), encoding: .utf8), "and my swims")
        let saved = try JSONDecoder().decode([LogLine].self, from: Data(contentsOf: lamp.appendingPathComponent("chat.json")))
        XCTAssertEqual(saved.last?.text, "Track my runs")
    }

    /// A real full disk: a small disk image filled to the last byte.
    func testAFullDiskIsToldApartAndTryAgainSavesOnceThereIsRoom() async throws {
        let image = root.appendingPathComponent("small.dmg"), mount = root.appendingPathComponent("volume")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        guard Self.hdiutil(["create", "-size", "40m", "-fs", "HFS+", "-volname", "LampFull", image.path]),
              Self.hdiutil(["attach", "-nobrowse", "-mountpoint", mount.path, image.path]) else {
            throw XCTSkip("couldn't make a disk image here")
        }
        defer { _ = Self.hdiutil(["detach", "-force", mount.path]) }

        let wish = try Template.scaffold(name: "Tally", platform: .mac, in: mount)
        let store = Store(testingAt: mount)
        let project = try XCTUnwrap(store.current(wish))
        let filler = mount.appendingPathComponent("filler")
        FileManager.default.createFile(atPath: filler.path, contents: nil)
        let handle = try FileHandle(forWritingTo: filler)
        let block = Data(count: 256 * 1024)
        while (try? handle.write(contentsOf: block)) != nil {}
        let byte = Data(count: 1)
        while (try? handle.write(contentsOf: byte)) != nil {}
        try handle.close()

        store.log(project, .user, String(repeating: "A long request. ", count: 2000))
        await settle(store)
        XCTAssertEqual(store.saveTrouble?.diskFull, true)
        XCTAssertEqual(store.saveTrouble?.text, ErrorMessages.chatNotSavedDiskFull)

        try FileManager.default.removeItem(at: filler)
        store.retrySaving()
        await settle(store)
        XCTAssertNil(store.saveTrouble)
        let saved = try JSONDecoder().decode([LogLine].self, from: Data(contentsOf: project.dir.appendingPathComponent(".lamp/chat.json")))
        XCTAssertEqual(saved.last?.text.hasPrefix("A long request."), true)
    }

    private static func hdiutil(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
