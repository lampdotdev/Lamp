import XCTest
@testable import Lamp

/// A shared app brings its widget: the widget's code travels in the file, is put before the same review as
/// the rest, and is written into the app that's made from it. No code reaches an app without the review.
final class SharingWidgetTests: XCTestCase {
    private var root: URL?
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
    private func handMade(format: Int = 3, _ files: [String: String]) throws -> URL {
        let stage = try XCTUnwrap(root ?? { root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("lamp-share-widget-\(UUID().uuidString)"); return root }()).appendingPathComponent("stage-\(UUID().uuidString)")
        for (path, text) in files { try write(text, to: path, in: stage) }
        try write("{\"format\":\(format),\"name\":\"Tally\",\"exportedAt\":\"2026-10-01T00:00:00Z\"}", to: "lamp-app.json", in: stage)
        let file = stage.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).lampapp")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zip.arguments = ["-c", "-k", "--norsrc", stage.path, file.path]
        try zip.run()
        zip.waitUntilExit()
        return file
    }

    // MARK: - There and back

    func testAWidgetTravelsWithItsApp() throws {
        let sender = try project()
        XCTAssertTrue(FileManager.default.fileExists(atPath: sender.dir.appendingPathComponent("Widget/LampWidgetSupport.swift").path))
        let package = try Sharing.open(try Sharing.export(sender))
        // The widget's code is in the file; Lamp's own file from that folder is not, like LampSupport.swift.
        XCTAssertTrue(package.hasWidget)
        XCTAssertEqual(package.sources.map { package.path(of: $0) }.sorted(), ["Sources/App.swift", "Sources/ContentView.swift", "Widget/Widget.swift"])

        let receiver = try Template.scaffold(name: "Tally Copy", in: try XCTUnwrap(root))
        try Sharing.install(package, into: receiver)
        XCTAssertEqual(try String(contentsOf: receiver.dir.appendingPathComponent("Widget/Widget.swift"), encoding: .utf8), Self.widgetCode)
        XCTAssertTrue(Template.hasWidget(receiver))
        // The receiving Mac builds it as its own: its own second program, its own port and secret.
        try Template.writeOwnedFiles(for: receiver)
        XCTAssertTrue(try String(contentsOf: receiver.dir.appendingPathComponent("Package.swift"), encoding: .utf8).contains("TallyCopyWidget"))
        XCTAssertNotEqual(Template.widgetToken(for: receiver), Template.widgetToken(for: sender))
        XCTAssertNotEqual(Template.widgetPort(for: receiver), Template.widgetPort(for: sender))
        XCTAssertTrue(Sharing.widgetToAdd("Tally").contains("Edit Widgets"))
    }

    func testOnlyAFileWithAWidgetAsksForANewerLamp() throws {
        func format(of file: URL) throws -> Int {
            let listing = Subprocess.runBlocking("/usr/bin/unzip", ["-p", file.path, "lamp-app.json"], timeout: 30).output
            return try XCTUnwrap((try JSONSerialization.jsonObject(with: Data(listing.utf8)) as? [String: Any])?["format"] as? Int)
        }
        XCTAssertEqual(try format(of: Sharing.export(try project("Tally", widget: true))), 3)
        // An app without a widget is the file it always was: a Lamp from before widgets opens it.
        XCTAssertEqual(try format(of: Sharing.export(try project("Plain", widget: false))), 2)
        XCTAssertEqual(Sharing.formatVersion, 3)
        // A file from a Lamp newer than this one is still turned away.
        XCTAssertThrowsError(try Sharing.open(try handMade(format: 4, ["Sources/App.swift": "let a = 1"])))
    }

    func testAnUpdateReplacesTheWidgetOrTakesItAway() throws {
        let sender = try project()
        let receiver = try Template.scaffold(name: "Mine", in: try XCTUnwrap(root))
        try write("let old = true\n", to: "Widget/Old.swift", in: receiver.dir)
        try Template.writeOwnedFiles(for: receiver)
        try Sharing.install(try Sharing.open(try Sharing.export(sender)), into: receiver, replacing: true)
        XCTAssertEqual(swiftFiles(in: receiver.dir.appendingPathComponent("Widget")), ["Widget.swift"])
        // The next file from the sender has no widget any more: neither has the app after it.
        try FileManager.default.removeItem(at: sender.dir.appendingPathComponent("Widget/Widget.swift"))
        let without = try Sharing.open(try Sharing.export(sender))
        XCTAssertFalse(without.hasWidget)
        try Sharing.install(without, into: receiver, replacing: true)
        XCTAssertFalse(Template.hasWidget(receiver))
    }

    // MARK: - The review

    func testTheWidgetsCodeIsReadByTheReviewLikeTheApps() throws {
        let sender = try project()
        try write("import Foundation\nfunc leak() { _ = URLSession.shared; let p = Process(); _ = p }\n", to: "Widget/Net.swift", in: sender.dir)
        let package = try Sharing.open(try Sharing.export(sender))
        let found = Sharing.inspect(package)
        XCTAssertEqual(found.files.map(\.name).sorted(), ["Sources/App.swift", "Sources/ContentView.swift", "Widget/Net.swift", "Widget/Widget.swift"])
        // Lamp's own checks see what the widget does...
        XCTAssertTrue(found.detected.contains { $0.patterns.contains("URLSession") })
        XCTAssertTrue(found.detected.contains { $0.patterns.contains("Process(") })
        // ...and the AI is given its code, named as the widget's, between the same markers.
        let request = Sharing.reviewRequest(name: package.name, about: found.about, files: found.files, boundary: "0123456789abcdef0123456789abcdef")
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
        let package = try Sharing.open(file)
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
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zip.arguments = ["-c", "-k", "--norsrc", stage.path, file.path]
        try zip.run()
        zip.waitUntilExit()
        XCTAssertThrowsError(try Sharing.open(file)) { error in
            XCTAssertEqual(error.localizedDescription, "This Lamp app file has code that isn't plain text, so Lamp can't check it.")
        }
    }
}
