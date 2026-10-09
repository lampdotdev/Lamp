import XCTest
@testable import Lamp

/// The agent's shell is confined (Sandbox), so it can't give the app it's testing a file the way Finder
/// does, and what the sandbox closes can read as missing rather than refused. `use_app`'s `open` is how it
/// hands one over, and the sandbox note says what failures to expect.
final class HandingFilesTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    /// Under the home folder, like a real app.
    private func project() throws -> (LampProject, URL) {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-handing-test-\(UUID().uuidString)")
        self.root = root
        let dir = root.appendingPathComponent("Apps/folderpeek")
        try fm.createDirectory(at: dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        return (LampProject(id: "folderpeek", name: "Folder Peek", exe: "FolderPeek", dir: dir), root)
    }

    /// An `open` is Lamp's to do and the rest the app's, in the order given.
    func testABatchIsSplitAroundEachOpen() {
        let steps = Store.useSteps([
            ["action": "click", "x": 10, "y": 10], ["action": "wait", "amount": 1],
            ["action": "open", "path": "Samples/Shots"],
            ["action": "open", "path": "/tmp/other"],
            ["action": "key", "key": "return"],
        ])
        let shape = steps.map { step -> String in
            switch step {
            case .open(let path): "open \(path)"
            case .drive(let run): "drive \(run.compactMap { $0["action"] as? String }.joined(separator: ","))"
            }
        }
        XCTAssertEqual(shape, ["drive click,wait", "open Samples/Shots", "open /tmp/other", "drive key"])
        XCTAssertTrue(Store.useSteps([["action": "open"]]).contains { if case .open("") = $0 { true } else { false } })
    }

    /// What may be handed to the app is what the file tools may touch: the app's folder and temporary
    /// folders freely, the person's files only if they say so, Lamp's own never.
    func testWhatMayBeHandedOverFollowsTheFileRule() throws {
        let (project, root) = try project()
        XCTAssertEqual(Privacy.verdict(tool: "open", path: "Samples/Shots", project: project), .allow)
        XCTAssertEqual(Privacy.verdict(tool: "open", path: NSTemporaryDirectory() + "shots", project: project), .allow)
        XCTAssertEqual(Privacy.verdict(tool: "open", path: root.appendingPathComponent("Desktop").path, project: project), .ask)
        // Not a read: the app can change what it's given, so even a system folder asks.
        XCTAssertEqual(Privacy.verdict(tool: "open", path: "/usr/share", project: project), .ask)
        guard case .deny = Privacy.verdict(tool: "open", path: Edition.supportFolder.appendingPathComponent("Apps/other").path, project: project) else {
            return XCTFail("Another app's folder was offered to this one")
        }
        let card = Privacy.explanation(tool: "open", path: "~/Desktop", project: project)
        XCTAssertEqual(card.explanation.summary, "Open ~/Desktop in Folder Peek")
        XCTAssertEqual(card.explanation.risk, "high")
    }

    /// One definition serves pi and the MCP endpoint, so this is what every engine is offered.
    func testEveryEngineIsOfferedOpen() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources/lamp-tools.json")
        let tools = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [[String: Any]])
        let use = try XCTUnwrap(tools.first { $0["name"] as? String == "use_app" })
        let schema = try XCTUnwrap(((use["inputSchema"] as? [String: Any])?["properties"] as? [String: Any])?["actions"] as? [String: Any])
        let properties = try XCTUnwrap((schema["items"] as? [String: Any])?["properties"] as? [String: Any])
        XCTAssertTrue(((properties["action"] as? [String: Any])?["enum"] as? [String] ?? []).contains("open"))
        XCTAssertNotNil(properties["path"])
        XCTAssertTrue((use["description"] as? String ?? "").contains("`open`"))
        XCTAssertTrue(Agent.tryRules.contains("`use_app`'s `open`"))
    }

    /// The failures the agent took for bugs in the app are named, with what to do instead.
    func testTheSandboxNoteNamesWhatFails() {
        for words in ["open -a App file", "-10820", "~/Library/Services", "installed copy", "closed to you", "`use_app`'s `open`"] {
            XCTAssertTrue(Agent.sandboxNote.contains(words), words)
        }
        XCTAssertTrue(Agent.systemPrompt.contains("Quick Action"))
        XCTAssertFalse(Agent.iPhonePrompt(for: .iphone).contains("Quick Action"))
    }

    /// What the note warns of: a file the sandbox closes doesn't always say so. PlistBuddy, which the agent
    /// used to read its Quick Action, reports it as not there.
    func testAClosedFileCanReadAsMissing() throws {
        let (project, root) = try project()
        let closed = root.appendingPathComponent("Services/Sort.workflow/Contents/document.wflow")
        try FileManager.default.createDirectory(at: closed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try XCTUnwrap(try? PropertyListSerialization.data(fromPropertyList: ["command": "open -a"], format: .xml, options: 0)).write(to: closed)
        let wrapped = try XCTUnwrap(Sandbox.wrap("/usr/libexec/PlistBuddy -c 'Print :command' \(Sandbox.quoted(closed.path)) 2>&1", for: project))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", wrapped]
        process.currentDirectoryURL = project.dir
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
