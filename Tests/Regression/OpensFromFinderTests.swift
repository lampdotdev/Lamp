import XCTest
@testable import Lamp

/// A Mac app says what Finder may hand it (`opens` in capabilities.json) and Lamp declares it in the app's
/// Info.plist. Until it does, macOS hands the app nothing, and the agent's confined `open -a App file` fails
/// with an error that reads like a fault in the app. A shared app carries its capabilities, checked.
final class OpensFromFinderTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    private func project(capabilities: String? = nil, platform: Platform? = nil) throws -> LampProject {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-opens-test-\(UUID().uuidString)")
        self.root = root
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        if let capabilities { try capabilities.write(to: root.appendingPathComponent(Template.Capabilities.file), atomically: true, encoding: .utf8) }
        var project = LampProject(id: "folderpeek", name: "Folder Peek", exe: "FolderPeek", dir: root)
        if let platform { project.platform = platform }
        return project
    }

    /// One document type for each kind: macOS ignores a type's extensions once it names content types, so
    /// an extension it doesn't know can't share an entry with a type it does.
    func testEachKindIsItsOwnDocumentType() {
        let types = Template.Capabilities(opens: ["folder", "file", ".PNG", "csv", "public.image", "lampthing", "png"]).documentTypes
        XCTAssertEqual(types.compactMap { ($0["LSItemContentTypes"] as? [String])?.first },
                       ["public.folder", "public.data", "public.png", "public.comma-separated-values-text", "public.image"])
        XCTAssertEqual(types.count, 6)
        let unknown = types[5]
        XCTAssertEqual(unknown["CFBundleTypeExtensions"] as? [String], ["lampthing"])
        XCTAssertNil(unknown["LSItemContentTypes"])
    }

    /// Declaring folders or pictures must never make the app what opens them on a double-click.
    func testTheAppIsOnlyEverAnAlternative() {
        for type in Template.Capabilities(opens: ["folder", "png", "lampthing"]).documentTypes {
            XCTAssertEqual(type["LSHandlerRank"] as? String, "Alternate")
        }
    }

    /// The file is the agent's to write, and what it read may have told it what to put there.
    func testNothingButNamesGetsThrough() throws {
        let odd = ["$(touch /tmp/x)", "a b", "</string><key>LSUIElement</key>", "", "..", "public.image\"", "x/y", String(repeating: "a", count: 40)]
        XCTAssertEqual(Template.Capabilities(opens: odd).kinds, [])
        XCTAssertTrue(Template.Capabilities(opens: odd).documentTypes.isEmpty)
        XCTAssertTrue(Template.Capabilities().documentTypes.isEmpty)
        XCTAssertEqual(Template.Capabilities.load(try project(capabilities: #"{"opens": ["Folder", "$(x)", ".png"]}"#)).kinds, ["folder", "png"])
    }

    func testTheDeclarationIsWrittenAndTakenBack() throws {
        let project = try project(capabilities: #"{"opens": ["folder"]}"#)
        let app = project.dir.appendingPathComponent("build/FolderPeek.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist = app.appendingPathComponent("Contents/Info.plist")
        XCTAssertTrue(NSDictionary(dictionary: ["CFBundleIdentifier": "dev.lamp.app.folderpeek"]).write(to: plist, atomically: true))
        Template.Capabilities.load(project).apply(to: app)
        let written = try XCTUnwrap(NSDictionary(contentsOf: plist))
        XCTAssertEqual(((written["CFBundleDocumentTypes"] as? [[String: Any]])?.first?["LSItemContentTypes"] as? [String]), ["public.folder"])
        XCTAssertEqual(written["CFBundleIdentifier"] as? String, "dev.lamp.app.folderpeek")
        // An app that no longer opens anything stops being offered.
        Template.Capabilities().apply(to: app)
        XCTAssertNil(try XCTUnwrap(NSDictionary(contentsOf: plist))["CFBundleDocumentTypes"])
    }

    /// Every field of a sender's capabilities goes through the check the agent's own does, and only what
    /// passed is what the copy is given.
    func testOnlyWhatPassesEachCheckIsKept() {
        let sent = Template.Capabilities(healthkit: true, nfc: false, siri: nil, backgroundModes: ["audio", "root"],
                                         bonjourServices: ["_peek._tcp", "peek"], backgroundTasks: ["dev.lamp.refresh", "a b"],
                                         opens: ["folder", "$(touch x)", "TXT"])
        XCTAssertEqual(sent.checked, Template.Capabilities(healthkit: true, backgroundModes: ["audio"], bonjourServices: ["_peek._tcp"],
                                                           backgroundTasks: ["dev.lamp.refresh"], opens: ["folder", "txt"]))
        XCTAssertTrue(Template.Capabilities(nfc: false, backgroundModes: ["root"], opens: ["a b"]).isEmpty)
    }

    /// A shared app keeps what it declares: Lamp writes the copy's capabilities.json itself from what passed,
    /// and an update from a file that declares nothing takes the declaration away.
    func testASharedAppKeepsItsCapabilities() throws {
        let copy = try project()
        let unpacked = copy.dir.appendingPathComponent("unpacked")
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        let file = unpacked.appendingPathComponent(Template.Capabilities.file)
        try #"{"opens": ["folder", "$(touch x)", "TXT"], "healthkit": true, "backgroundModes": ["audio", "root"], "extra": 1}"#
            .write(to: file, atomically: true, encoding: .utf8)
        let shared = Sharing.Package(name: "Folder Peek", capabilities: Template.Capabilities.load(file).checked,
                                     folder: unpacked, sources: [], attachments: [], fileCount: 0)
        try Sharing.install(shared, into: copy)
        XCTAssertEqual(Template.Capabilities.load(copy), Template.Capabilities(healthkit: true, backgroundModes: ["audio"], opens: ["folder", "txt"]))
        let text = try String(contentsOf: copy.dir.appendingPathComponent(Template.Capabilities.file), encoding: .utf8)
        XCTAssertFalse(text.contains("touch") || text.contains("extra") || text.contains("root"), text)
        try Sharing.install(Sharing.Package(name: "Folder Peek", folder: unpacked, sources: [], attachments: [], fileCount: 0), into: copy)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.dir.appendingPathComponent(Template.Capabilities.file).path))
    }

    /// A file that declares capabilities says so by its number, so a Lamp from before asks to be updated
    /// instead of building the app without them; one that declares none still opens there.
    func testAFileWithCapabilitiesIsANewerKind() {
        XCTAssertEqual(Sharing.format(withWidget: false), 2)
        XCTAssertEqual(Sharing.format(withWidget: true), 3)
        XCTAssertEqual(Sharing.format(withWidget: false, capabilities: true), 4)
        XCTAssertEqual(Sharing.format(withWidget: true, capabilities: true), 4)
        XCTAssertEqual(Sharing.formatVersion, 4)
    }

    /// Changing what the app declares needs a build; its description doesn't.
    func testWhatItDeclaresCountsForARebuildAndTheDescriptionDoesNot() throws {
        let project = try project(capabilities: #"{"opens": ["folder"]}"#)
        let before = Runtime.fingerprint(project)
        try #"{"description": "Shows a folder."}"#.write(to: project.dir.appendingPathComponent(AppDescription.file), atomically: true, encoding: .utf8)
        XCTAssertEqual(Runtime.fingerprint(project), before)
        try #"{"opens": ["folder", "txt"]}"#.write(to: project.dir.appendingPathComponent(Template.Capabilities.file), atomically: true, encoding: .utf8)
        XCTAssertNotEqual(Runtime.fingerprint(project), before)
    }

    /// The agent is given the installed copy's path, which its shell can open with and can't see, only for
    /// an app that has declared something.
    func testALookSaysHowToHandOverAFile() throws {
        let declared = try project(capabilities: #"{"opens": ["folder"]}"#)
        let hint = Store.handingHint(for: declared)
        XCTAssertTrue(hint.contains("open -g -a '\(declared.installedURL.path)'"), hint)
        XCTAssertEqual(Store.handingHint(for: try project()), "")
        XCTAssertEqual(Store.handingHint(for: try project(capabilities: #"{"opens": ["folder"]}"#, platform: .iphone)), "")
    }

    func testTheAgentIsToldHowAndWhatFails() {
        XCTAssertTrue(Agent.systemPrompt.contains(#"{"opens": ["folder""#))
        XCTAssertTrue(Agent.systemPrompt.contains("Quick Action"))
        XCTAssertFalse(Agent.iPhonePrompt(for: .iphone).contains("Quick Action"))
        for words in ["-10820", "~/Library/Services", "installed", "closed to you", "`opens` in capabilities.json"] {
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
