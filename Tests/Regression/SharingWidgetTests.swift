import XCTest
@testable import Lamp

/// A shared app brings its widget: the widget's code travels in the file, is put before the same review as
/// the rest, and is written into the app that's made from it. No code reaches an app without the review.
final class SharingWidgetTests: XCTestCase {
    private var root: URL?
    override func setUp() { expectNoSharingFoldersLeft() }
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    private static let widgetCode = "import WidgetKit\n// shows the tally\nlet kind = \"tally\"\n"

    private func project(_ name: String = "Tally", widget: Bool = true) throws -> LampProject {
        let root = self.root ?? FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("lamp-share-widget-\(UUID().uuidString)")
        self.root = root
        let project = try Template.scaffold(name: name, in: root)
        if widget { try write(Self.widgetCode, to: "Widget/Widget.swift", in: project.dir) }
        try Template.writeOwnedFiles(for: project)   // Lamp's own file joins the widget's, as before any build
        return project
    }

    private func write(_ text: String, to path: String, in folder: URL) throws {
        let url = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func swiftFiles(in folder: URL) -> [String] {
        let all = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        return all.filter { $0.pathExtension == "swift" }.map { Sharing.relativePath(of: $0, in: folder) }.sorted()
    }

    /// A file made by hand, as a sender who isn't Lamp could make it.
    private func handMade(format: Int, _ files: [String: String]) throws -> URL {
        let stage = try XCTUnwrap(root ?? { root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("lamp-share-widget-\(UUID().uuidString)"); return root }()).appendingPathComponent("stage-\(UUID().uuidString)")
        for (path, text) in files { try write(text, to: path, in: stage) }
        try write("{\"format\":\(format),\"name\":\"Tally\",\"exportedAt\":\"2026-10-01T00:00:00Z\"}", to: "lamp-app.json", in: stage)
        let file = stage.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).lampapp")
        TestShell.run("/usr/bin/ditto", ["-c", "-k", "--norsrc", stage.path, file.path])
        return file
    }

    // MARK: - The review

    func testTheWidgetsCodeIsReadByTheReviewLikeTheApps() throws {
        let sender = try project()
        try write("import Foundation\nfunc leak() { _ = URLSession.shared; let p = Process(); _ = p }\n", to: "Widget/Net.swift", in: sender.dir)
        let package = try opened(try exported(sender))
        let found = Sharing.inspect(package)
        XCTAssertEqual(found.files.map(\.name).sorted(), ["Sources/App.swift", "Sources/ContentView.swift", "Widget/Net.swift", "Widget/Widget.swift"])
        // Lamp's own checks see what the widget does...
        XCTAssertTrue(found.detected.contains { $0.patterns.contains("URLSession") })
        XCTAssertTrue(found.detected.contains { $0.patterns.contains("Process(") })
        // ...and the AI is given its code, named as the widget's, between the same markers.
        let request = Sharing.reviewRequest(name: package.name, description: package.description, notes: found.about, files: found.files, boundary: "0123456789abcdef0123456789abcdef")
        XCTAssertTrue(request.prompt.contains("BEGIN file \"Widget/Widget.swift\"]\n\(Self.widgetCode)"))
        XCTAssertTrue(request.prompt.contains("BEGIN file \"Widget/Net.swift\"]"))
        XCTAssertTrue(request.system.contains("the files under Widget/"))
    }

    /// The point of the list the review and the install share: whatever a file is made to hold, no code is
    /// written into an app's folder that the review didn't have in front of it.
    func testNoCodeGetsInUnreviewed() throws {
        let file = try handMade(format: 2, [   // a file that says it has no widget, and brings one anyway
            "Sources/App.swift": "let a = 1\n",
            "Widget/Widget.swift": "let hidden = \"https://example.invalid\"\n",
            "Widget/Deep/More.swift": "let deeper = 1\n",
            "Widget/LampWidgetSupport.swift": "let pretendsToBeLamps = 1\n",
            "Widget/payload.sh": "#!/bin/sh\n",
            "Widget/notes.txt": "hello\n",
            "Elsewhere/Stray.swift": "let stray = 1\n",
            "build.sh": "#!/bin/sh\necho owned\n",
            "Package.swift": "// not Lamp's\n",
        ])
        let package = try opened(file)
        let reviewed = Set(Sharing.inspect(package).files.map(\.name))
        let receiver = try Template.scaffold(name: "Receiver", in: try XCTUnwrap(root))
        let ownBuild = try String(contentsOf: receiver.dir.appendingPathComponent("build.sh"), encoding: .utf8)
        try Sharing.install(package, into: receiver)

        // Every Swift file now in the app's two code folders, Lamp's own aside, was in front of the review.
        let installed = (swiftFiles(in: receiver.dir.appendingPathComponent("Sources")).map { "Sources/" + $0 }
            + swiftFiles(in: receiver.dir.appendingPathComponent("Widget")).map { "Widget/" + $0 })
            .filter { $0 != "Sources/LampSupport.swift" }
        XCTAssertEqual(installed.sorted(), ["Sources/App.swift", "Widget/Deep/More.swift", "Widget/Widget.swift"])
        XCTAssertTrue(Set(installed).isSubset(of: reviewed), "\(installed) vs \(reviewed)")
        XCTAssertTrue(reviewed.contains("Widget/Widget.swift"))
        // The widget folder holds nothing else from the file: no scripts, no notes, no stand-in for Lamp's own file.
        let inWidget = (FileManager.default.enumerator(at: receiver.dir.appendingPathComponent("Widget"), includingPropertiesForKeys: nil)?
            .compactMap { ($0 as? URL)?.lastPathComponent } ?? []).sorted()
        XCTAssertEqual(inWidget, ["Deep", "More.swift", "Widget.swift"])
        // Code outside the two folders goes nowhere, and what the build runs is still Lamp's.
        XCTAssertFalse(FileManager.default.fileExists(atPath: receiver.dir.appendingPathComponent("Elsewhere").path))
        XCTAssertEqual(try String(contentsOf: receiver.dir.appendingPathComponent("build.sh"), encoding: .utf8), ownBuild)
        // Lamp writes its own file into the widget's folder before building, whatever the sender's said.
        try Template.writeOwnedFiles(for: receiver)
        XCTAssertFalse(try String(contentsOf: receiver.dir.appendingPathComponent("Widget/LampWidgetSupport.swift"), encoding: .utf8).contains("pretendsToBeLamps"))
    }

    func testWidgetCodeThatIsntTextStopsTheFileFromOpening() throws {
        let stage = try XCTUnwrap(try project().dir.deletingLastPathComponent()).appendingPathComponent("stage-bin")
        try write("let a = 1\n", to: "Sources/App.swift", in: stage)
        try FileManager.default.createDirectory(at: stage.appendingPathComponent("Widget"), withIntermediateDirectories: true)
        try Data([0xff, 0xfe, 0x00, 0xd8]).write(to: stage.appendingPathComponent("Widget/Widget.swift"))
        try write("{\"format\":3,\"name\":\"Tally\",\"exportedAt\":\"2026-10-01T00:00:00Z\"}", to: "lamp-app.json", in: stage)
        let file = stage.deletingLastPathComponent().appendingPathComponent("bin.lampapp")
        TestShell.run("/usr/bin/ditto", ["-c", "-k", "--norsrc", stage.path, file.path])
        XCTAssertThrowsError(try Sharing.open(file)) { error in
            XCTAssertEqual(error.localizedDescription, "This Lamp app file has code that isn't plain text, so Lamp can't check it.")
        }
    }
}
