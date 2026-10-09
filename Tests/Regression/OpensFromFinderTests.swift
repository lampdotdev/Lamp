import XCTest
@testable import Lamp

/// A Mac app says what Finder may hand it (`opens` in about.json, beside its description) and Lamp declares it in the app's
/// Info.plist. Until it does, macOS hands the app nothing, and the agent's confined `open -a App file` fails
/// with an error that reads like a fault in the app.
final class OpensFromFinderTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    private func project(opens: String? = nil, platform: Platform? = nil) throws -> LampProject {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-opens-test-\(UUID().uuidString)")
        self.root = root
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        if let opens { try opens.write(to: root.appendingPathComponent(AppDescription.file), atomically: true, encoding: .utf8) }
        var project = LampProject(id: "folderpeek", name: "Folder Peek", exe: "FolderPeek", dir: root)
        if let platform { project.platform = platform }
        return project
    }

    func testFoldersFilesExtensionsAndTypes() {
        let types = AppDescription.documentTypes(for: ["folder", "file", ".PNG", "csv", "public.image", "lampthing", "png"])
        XCTAssertEqual(types.count, 1)
        XCTAssertEqual(types[0]["LSItemContentTypes"] as? [String],
                       ["public.folder", "public.data", "public.png", "public.comma-separated-values-text", "public.image"])
        // An extension macOS doesn't know is declared as the extension.
        XCTAssertEqual(types[0]["CFBundleTypeExtensions"] as? [String], ["lampthing"])
    }

    /// Declaring folders or pictures must never make the app what opens them on a double-click.
    func testTheAppIsOnlyEverAnAlternative() {
        let type = AppDescription.documentTypes(for: ["folder"])[0]
        XCTAssertEqual(type["LSHandlerRank"] as? String, "Alternate")
    }

    /// The file is the agent's to write, and what it read may have told it what to put there.
    func testNothingButNamesGetsThrough() throws {
        let odd = ["$(touch /tmp/x)", "a b", "</string><key>LSUIElement</key>", "", "..", "public.image\"", "x/y", String(repeating: "a", count: 40)]
        XCTAssertEqual(AppDescription.valid(opens: odd), [])
        XCTAssertTrue(AppDescription.documentTypes(for: odd).isEmpty)
        XCTAssertTrue(AppDescription.documentTypes(for: []).isEmpty)
        // Read from the file the same way, whatever else it holds, and never anything that isn't a list of names.
        XCTAssertEqual(AppDescription.opens(of: try project(opens: #"{"description": "A peek.", "opens": ["Folder", 7, "$(x)", ".png"]}"#)), ["folder", "png"])
        XCTAssertEqual(AppDescription.opens(of: try project(opens: #"{"opens": "folder"}"#)), [])
    }

    func testTheDeclarationIsWrittenAndTakenBack() throws {
        let project = try project(opens: #"{"opens": ["folder"]}"#)
        let app = project.dir.appendingPathComponent("build/FolderPeek.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist = app.appendingPathComponent("Contents/Info.plist")
        XCTAssertTrue(NSDictionary(dictionary: ["CFBundleIdentifier": "dev.lamp.app.folderpeek"]).write(to: plist, atomically: true))
        AppDescription.writeDocumentTypes(of: project, to: app)
        let written = try XCTUnwrap(NSDictionary(contentsOf: plist))
        XCTAssertEqual(((written["CFBundleDocumentTypes"] as? [[String: Any]])?.first?["LSItemContentTypes"] as? [String]), ["public.folder"])
        XCTAssertEqual(written["CFBundleIdentifier"] as? String, "dev.lamp.app.folderpeek")
        // An app that no longer opens anything stops being offered.
        try #"{"description": "A peek."}"#.write(to: project.dir.appendingPathComponent(AppDescription.file), atomically: true, encoding: .utf8)
        AppDescription.writeDocumentTypes(of: project, to: app)
        XCTAssertNil(try XCTUnwrap(NSDictionary(contentsOf: plist))["CFBundleDocumentTypes"])
    }

    /// The agent is given the installed copy's path, which its shell can open with and can't see, only for
    /// an app that has declared something.
    func testALookSaysHowToHandOverAFile() throws {
        let declared = try project(opens: #"{"opens": ["folder"]}"#)
        let hint = Store.handingHint(for: declared)
        XCTAssertTrue(hint.contains("open -g -a '\(declared.installedURL.path)'"), hint)
        XCTAssertEqual(Store.handingHint(for: try project()), "")
        XCTAssertEqual(Store.handingHint(for: try project(opens: #"{"opens": ["folder"]}"#, platform: .iphone)), "")
    }

    /// A shared app keeps what it opens: the sender's list rides in the file's manifest, is checked like the
    /// agent's, and Lamp writes the copy's about.json itself from what passed.
    func testASharedAppKeepsWhatItOpens() throws {
        let copy = try project()
        let unpacked = copy.dir.appendingPathComponent("unpacked")
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        let manifest = try JSONDecoder().decode(Sharing.Manifest.self, from: Data(
            #"{"format": 2, "name": "Folder Peek", "exportedAt": 0, "description": "A peek.", "opens": ["folder", "$(touch x)", "TXT"]}"#.utf8))
        let shared = Sharing.Package(name: "Folder Peek", description: manifest.description,
                                     opens: AppDescription.valid(opens: manifest.opens ?? []),
                                     folder: unpacked, sources: [], attachments: [], fileCount: 0)
        try Sharing.install(shared, into: copy)
        XCTAssertEqual(AppDescription.opens(of: copy), ["folder", "txt"])
        XCTAssertEqual(AppDescription.description(of: copy), "A peek.")
        XCTAssertEqual(AppDescription.documentTypes(for: AppDescription.opens(of: copy))[0]["LSHandlerRank"] as? String, "Alternate")
        // An update from a file that declares nothing takes the declaration away with it.
        try Sharing.install(Sharing.Package(name: "Folder Peek", folder: unpacked, sources: [], attachments: [], fileCount: 0), into: copy)
        XCTAssertEqual(AppDescription.opens(of: copy), [])
    }

    /// What the app opens is in its Info.plist, so changing it needs a build; its description doesn't.
    func testWhatItOpensCountsForARebuildAndTheDescriptionDoesNot() throws {
        let project = try project(opens: #"{"description": "A peek.", "opens": ["folder"]}"#)
        let before = Runtime.fingerprint(project)
        try #"{"description": "Shows a folder.", "opens": ["folder"]}"#.write(to: project.dir.appendingPathComponent(AppDescription.file), atomically: true, encoding: .utf8)
        XCTAssertEqual(Runtime.fingerprint(project), before)
        try #"{"description": "Shows a folder.", "opens": ["folder", "txt"]}"#.write(to: project.dir.appendingPathComponent(AppDescription.file), atomically: true, encoding: .utf8)
        XCTAssertNotEqual(Runtime.fingerprint(project), before)
    }

    func testTheAgentIsToldHowAndWhatFails() {
        XCTAssertTrue(Agent.systemPrompt.contains(#""opens": ["folder""#))
        XCTAssertTrue(Agent.systemPrompt.contains("Quick Action"))
        XCTAssertFalse(Agent.iPhonePrompt(for: .iphone).contains("Quick Action"))
        for words in ["-10820", "~/Library/Services", "installed", "closed to you", "`opens` in about.json"] {
            XCTAssertTrue(Agent.sandboxNote.contains(words), words)
        }
    }

    /// What the note warns of: a file the sandbox closes doesn't always say so. PlistBuddy, which the agent
    /// used to read its Quick Action, reports it as not there.
    func testAClosedFileCanReadAsMissing() throws {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-opens-test-\(UUID().uuidString)")
        root = home
        let dir = home.appendingPathComponent("Apps/folderpeek")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let project = LampProject(id: "folderpeek", name: "Folder Peek", exe: "FolderPeek", dir: dir)
        let closed = home.appendingPathComponent("Services/Sort.workflow/Contents/document.wflow")
        try fm.createDirectory(at: closed.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(NSDictionary(dictionary: ["command": "open -a"]).write(to: closed, atomically: true))
        let wrapped = try XCTUnwrap(Sandbox.wrap("/usr/libexec/PlistBuddy -c 'Print :command' \(Sandbox.quoted(closed.path)) 2>&1", for: project))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", wrapped]
        process.currentDirectoryURL = dir
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        XCTAssertTrue(output.contains("Doesn't Exist"), output)
        XCTAssertFalse(output.contains("open -a"), output)
    }
}
