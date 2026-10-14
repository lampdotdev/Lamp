import XCTest
@testable import Lamp

/// capabilities.json is the agent's to write, and a shared app's comes from its sender: only what passes each
/// field's check reaches Info.plist or the entitlements, and what Finder may hand an app never takes a kind of
/// file from the app that opens it.
final class OpensFromFinderTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    private func project(capabilities: String? = nil) throws -> LampProject {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-opens-test-\(UUID().uuidString)")
        self.root = root
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        if let capabilities { try capabilities.write(to: root.appendingPathComponent(Template.Capabilities.file), atomically: true, encoding: .utf8) }
        return LampProject(id: "folderpeek", name: "Folder Peek", exe: "FolderPeek", dir: root)
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
}
