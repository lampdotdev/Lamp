import XCTest
@testable import Lamp

/// A download that `use_app` sets off in a page's app is said in its answer (`LampSaves` in LampSupport.swift): where it
/// went, its size and what a zip holds, so the builder needn't read the person's Downloads to know a Save worked. Only
/// once it has really ended is it said to be saved, a save still being written is said to be still saving, one that ends
/// after its batch answered is said in the next answer as from earlier, and nothing is said twice. A save is the batch's
/// that answered its panel, however late the download's panel came up.
@MainActor
final class UseAppSavesTests: XCTestCase {
    /// The app's half is cut out of the template, compiled into a small program and taken through a save's life, with
    /// real files: a zip made by the system's zip tool, the same zip cut short, and a file of plain text.
    func testASaveIsSaidOnceWhenItEndsAndAZipIsListed() throws {
        let support = Template.lampSupportSwift
        // Lamp waits for the app's answer as long beyond its actions as the app waits for a save.
        XCTAssertTrue(support.contains("static let wait = \(Template.useAppSaveWait)"))
        let start = try XCTUnwrap(support.range(of: "// begin LampSaves"))
        let end = try XCTUnwrap(support.range(of: "// end LampSaves", range: start.upperBound..<support.endIndex))
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-use-saves-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        // A made-up project in the shape of a block-coding app's: a zip of three files.
        for (name, text) in [("manifest.json", "{\"type\":\"word-blocks\"}"), ("projectbody.json", "{\"targets\":[]}"), ("icon.svg", "<svg/>")] {
            try text.write(to: work.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let zipped = TestShell.run("/usr/bin/zip -q -X Robot.llsp3 manifest.json projectbody.json icon.svg", in: work)
        XCTAssertEqual(zipped.status, 0, zipped.output)
        let whole = try Data(contentsOf: work.appendingPathComponent("Robot.llsp3"))
        try whole.prefix(whole.count - 30).write(to: work.appendingPathComponent("Cut.llsp3"))
        try "name,count\nbricks,4\n".write(to: work.appendingPathComponent("Parts.csv"), atomically: true, encoding: .utf8)

        let program = """
        import Foundation

        \(support[start.upperBound..<end.lowerBound])

        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        func say(_ lines: [String]) {
            print(lines.isEmpty ? "-" : lines.joined(separator: "\\n").replacingOccurrences(of: folder.path, with: "DIR"))
        }
        MainActor.assumeIsolated {
            // The person's own download, with no batch running, is none of the builder's business.
            say(LampSaves.began("Mine.zip") == nil ? ["person's own: not kept"] : ["person's own: kept"])

            // Batch two presses return in the panel (opened by an earlier batch, or after it answered): the download is
            // still being written when it answers.
            LampSaves.batch = "two"
            let robot = LampSaves.began("Robot.llsp3")
            LampSaves.chose(robot, folder.appendingPathComponent("Robot.llsp3"))
            say(["writing: \\(LampSaves.writing)"])
            say(LampSaves.news(for: "two"))
            say(LampSaves.news(for: "two"))
            LampSaves.batch = nil

            // It ends between batches: batch three says so, once.
            LampSaves.ended(robot, .saved)
            say(["writing: \\(LampSaves.writing)"])
            say(LampSaves.news(for: "three"))
            say(LampSaves.news(for: "three"))

            // Within one batch: a save canceled in its panel, one whose download failed, one that couldn't be put in place,
            // and two saved files that aren't whole zips.
            LampSaves.batch = "four"
            let canceled = LampSaves.began("Other.llsp3")
            LampSaves.ended(canceled, .canceled)
            let failed = LampSaves.began("Big.llsp3")
            LampSaves.chose(failed, folder.appendingPathComponent("Big.llsp3"))
            LampSaves.ended(failed, .failed("The network connection was lost."))
            let unmoved = LampSaves.began("Locked.llsp3")
            LampSaves.chose(unmoved, folder.appendingPathComponent("Locked.llsp3"))
            LampSaves.ended(unmoved, .notMoved("You don't have permission."))
            for name in ["Cut.llsp3", "Parts.csv"] {
                let save = LampSaves.began(name)
                LampSaves.chose(save, folder.appendingPathComponent(name))
                LampSaves.ended(save, .saved)
            }
            say(LampSaves.news(for: "four"))
            say(LampSaves.news(for: "four"))
            say([LampSaves.describe(folder.appendingPathComponent("Gone.llsp3"))])
        }
        """
        let code = work.appendingPathComponent("code")
        try FileManager.default.createDirectory(at: code, withIntermediateDirectories: true)
        try program.write(to: code.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        let built = TestShell.run(Shell.compatibleSDK + "xcrun swiftc -o saves main.swift 2>&1", in: code)
        XCTAssertEqual(built.status, 0, built.output)

        let ran = TestShell.run("./saves \(work.path)", in: code)
        XCTAssertEqual(ran.status, 0, ran.output)
        let size = whole.count, cut = whole.count - 30
        XCTAssertEqual(ran.output, """
        person's own: not kept
        writing: true
        Still saving DIR/Robot.llsp3: it isn't finished yet, so it isn't saved yet.
        -
        writing: false
        Saved (from an earlier use of the app): DIR/Robot.llsp3, \(size) bytes, a zip archive of 3 entries: manifest.json, projectbody.json, icon.svg
        -
        Not saved: the save panel for "Other.llsp3" was canceled.
        Not saved: the download of DIR/Big.llsp3 failed (The network connection was lost.).
        Not saved: the download of DIR/Locked.llsp3 finished but couldn't be put there (You don't have permission.).
        Saved: DIR/Cut.llsp3, \(cut) bytes, it starts like a zip archive but its list of files couldn't be read, so it may be cut short or damaged
        Saved: DIR/Parts.csv, 20 bytes, not a zip archive
        -
        DIR/Gone.llsp3 (Lamp couldn't inspect it)

        """)
    }
}
