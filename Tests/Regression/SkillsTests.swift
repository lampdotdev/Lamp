import XCTest
@testable import Lamp

/// Skills: guidance the agent opens with `read_skill` instead of carrying it in the system prompt, and the line
/// Lamp adds to a request when an app's code shows a skill applies.
final class SkillsTests: XCTestCase {
    /// The skills as they ship, read from the repository (tests don't run inside Lamp's bundle).
    private let shipped = Skills.load(from: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/skills"))

    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("SkillsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func app(_ platform: Platform = .mac) -> LampProject {
        var project = LampProject(id: "world-\(UUID().uuidString)", name: "World", exe: "World", dir: folder)
        project.platform = platform
        return project
    }

    private func source(_ name: String, _ text: String) throws {
        try text.write(to: folder.appendingPathComponent("Sources/\(name)"), atomically: true, encoding: .utf8)
    }

    // MARK: - The skills Lamp ships

    /// Every skill a prompt can offer is in the bundle and reads as an Agent Skills file: a folder named as the
    /// skill, a one-line description within the format's limit, and instructions.
    func testEveryOfferedSkillShipsAndReads() {
        XCTAssertEqual(Set(shipped.keys), ["scene-3d", "maps", "chrome-sidebar", "device-integrations", "android-design", "phone-controllers"])
        for (name, skill) in shipped {
            XCTAssertFalse(skill.body.isEmpty, name)
            XCTAssertLessThanOrEqual(skill.description.count, 1024, name)
            XCTAssertNil(skill.name.range(of: #"[^a-z0-9-]"#, options: .regularExpression), name)
        }
        if Agent.Rules.scenes {
            // The integrations' skill is named by its own rule, in every prompt, rather than in the list, and Android's
            // design is offered to the Android prompt alone.
            XCTAssertEqual(Set(Skills.offered(mac: true, sidebar: true)), Set(shipped.keys).subtracting(["device-integrations", "android-design", "phone-controllers"]))
        }
        XCTAssertEqual(Skills.offered(mac: false, android: true), ["android-design"])
        XCTAssertEqual(Skills.offered(mac: false, tv: true), ["phone-controllers"])
        XCTAssertEqual(Skills.offered(mac: false), [])
        // The sidebar's page is offered wherever the prompt has the sidebar's rule, an app for both included.
        XCTAssertEqual(Skills.offered(mac: false, sidebar: true), ["chrome-sidebar"])
    }

    /// The Android prompt names its design skill, and the list it offers carries the skill's description.
    func testAndroidPromptOffersDesignSkill() {
        XCTAssertTrue(Agent.androidPrompt().contains("open the android-design skill"))
        let index = Skills.index(Skills.offered(mac: false, android: true), from: shipped)
        XCTAssertTrue(index.contains("  • android-design: \(shipped["android-design"]!.description)\n"))
    }

    /// The Mac prompt no longer carries what the 3D and map skills say, and their list names both.
    func testMacPromptListsSkillsInsteadOfCarryingThem() throws {
        try XCTSkipUnless(Agent.Rules.scenes, "3D scenes are offered only on macOS 15 or later")
        let prompt = Agent.systemPrompt
        let index = Skills.index(Skills.offered(mac: true), from: shipped)
        XCTAssertTrue(index.contains("`read_skill`"))
        XCTAssertTrue(index.contains("  • scene-3d: \(shipped["scene-3d"]!.description)\n"))
        XCTAssertTrue(index.contains("  • maps: \(shipped["maps"]!.description)\n"))
        XCTAssertFalse(prompt.contains("LampMesh"), "the 3D instructions belong in the skill")
        XCTAssertFalse(prompt.contains("Overpass"), "the map data instructions belong in the skill")
        XCTAssertTrue(shipped["scene-3d"]!.body.contains("LampMesh"))
        XCTAssertTrue(shipped["maps"]!.body.contains("Overpass"))
        XCTAssertFalse(Agent.iPhonePrompt(for: .iphone).contains("read_skill"))
    }

    /// A TV turn's prompt lists the phone page's skill instead of carrying what it says, and a TV app with a page for
    /// phones, or a TV page using them, is told the skill applies.
    func testTVPromptOffersThePhoneSkill() throws {
        let prompt = Agent.tvPrompt(skills: shipped)
        XCTAssertTrue(prompt.contains("  • phone-controllers: \(shipped["phone-controllers"]!.description)\n"))
        XCTAssertTrue(prompt.contains("Open the phone-controllers skill"))
        XCTAssertFalse(prompt.contains("LampController.connect"), "the phone page's instructions belong in the skill")
        XCTAssertTrue(shipped["phone-controllers"]!.body.contains("LampController.connect"))
        XCTAssertTrue(shipped["phone-controllers"]!.body.contains("Lamp.onPhonePage"))
        XCTAssertFalse(Agent.systemPrompt.contains("phone-controllers"), "only the TV prompt offers it")

        let web = folder.appendingPathComponent("Web")
        try FileManager.default.createDirectory(at: web, withIntermediateDirectories: true)
        try "Lamp.controllers.start(); Lamp.phonePage();".write(to: web.appendingPathComponent("lamp.js"), atomically: true, encoding: .utf8)
        XCTAssertTrue(Skills.applying(to: app(.tv)).isEmpty, "Lamp's own lamp.js doesn't count")
        try "Lamp.controllers.onButton(function () {});".write(to: web.appendingPathComponent("game.js"), atomically: true, encoding: .utf8)
        XCTAssertEqual(Skills.applying(to: app(.tv)).map(\.name), ["phone-controllers"])
        try FileManager.default.removeItem(at: web.appendingPathComponent("game.js"))
        let phone = folder.appendingPathComponent("Phone")
        try FileManager.default.createDirectory(at: phone, withIntermediateDirectories: true)
        try "<p>pad</p>".write(to: phone.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        XCTAssertEqual(Skills.applying(to: app(.tv)).map(\.because), ["it has a page for phones in Phone/"])
        XCTAssertTrue(Skills.applying(to: app(.mac)).filter { $0.name == "phone-controllers" }.isEmpty)
    }

    func testReadingASkill() {
        let (status, answer) = Skills.read(["name": "maps"], from: shipped)
        XCTAssertEqual(status, 200)
        XCTAssertEqual(answer["text"] as? String, shipped["maps"]!.body)

        let (missing, error) = Skills.read(["name": "3d"], from: shipped)
        XCTAssertEqual(missing, 400)
        XCTAssertEqual(error["error"] as? String, "There's no skill called \"3d\". The skills are: android-design, chrome-sidebar, device-integrations, maps, phone-controllers, scene-3d.")
    }

    func testParsing() {
        XCTAssertEqual(Skills.parse("---\nname: a\ndescription: Does a: when b.\n---\n\n# A\n\nBody.\n"),
                       Skills.Skill(name: "a", description: "Does a: when b.", body: "# A\n\nBody."))
        XCTAssertNil(Skills.parse("---\nname: a\n---\nBody"), "no description")
        XCTAssertNil(Skills.parse("name: a\ndescription: b\n"), "no frontmatter")
    }

    // MARK: - When an app's code shows a skill applies

    func testAppsCodeShowsWhichSkillsApply() throws {
        try XCTSkipUnless(Agent.Rules.scenes, "3D scenes are offered only on macOS 15 or later")
        try source("ContentView.swift", "import SwiftUI\nstruct ContentView: View { var body: some View { Text(\"Hi\") } }\n")
        XCTAssertTrue(Skills.applying(to: app()).isEmpty)

        // Lamp's own files may name anything; only the app's code counts.
        try source("LampSupport.swift", "import RealityKit\n// OpenStreetMap\n")
        XCTAssertTrue(Skills.applying(to: app()).isEmpty)

        try source("World.swift", "import SwiftUI\nimport RealityKit\n")
        XCTAssertEqual(Skills.applying(to: app()).map(\.name), ["scene-3d"])

        try source("Credits.swift", "Text(\"© OpenStreetMap contributors\")\n")
        XCTAssertEqual(Skills.applying(to: app()).map(\.name), ["scene-3d", "maps"])

        // An iPhone app is offered neither.
        XCTAssertTrue(Skills.applying(to: app(.iphone)).isEmpty)
    }

    @MainActor func testTheAgentIsToldOncePerConversation() throws {
        try XCTSkipUnless(Agent.Rules.scenes, "3D scenes are offered only on macOS 15 or later")
        let project = app()
        try source("ContentView.swift", "import SwiftUI\n")
        XCTAssertEqual(Skills.brief(for: project, engine: .pi, session: "one"), "", "nothing applies")
        Skills.delivered(to: project)

        try source("World.swift", "import RealityKit\n")
        let told = Skills.brief(for: project, engine: .pi, session: "one")
        XCTAssertTrue(told.contains("- scene-3d: its code uses RealityKit"), told)
        Skills.delivered(to: project)
        XCTAssertEqual(Skills.brief(for: project, engine: .pi, session: "one"), "", "already told")
        Skills.delivered(to: project)

        // A new conversation, another engine's, or one that was compacted is told again.
        XCTAssertFalse(Skills.brief(for: project, engine: .pi, session: "two").isEmpty)
        XCTAssertFalse(Skills.brief(for: project, engine: .claude, session: "c1").isEmpty)
        Skills.delivered(to: project)
        XCTAssertEqual(Skills.brief(for: project, engine: .claude, session: "c1"), "")
        _ = Skills.brief(for: project, engine: .claude, session: "c1")
        Skills.compacted(project)
        Skills.delivered(to: project)
        XCTAssertFalse(Skills.brief(for: project, engine: .claude, session: "c1").isEmpty)
    }

    /// A conversation that was told of a skill before a Lamp update changed it is asked to open it again, and
    /// only that skill: one that didn't change keeps "unless you already have it".
    @MainActor func testAConversationIsToldToReopenASkillLampChanged() throws {
        try XCTSkipUnless(Agent.Rules.scenes, "3D scenes are offered only on macOS 15 or later")
        let project = app()
        try source("World.swift", "import RealityKit\n")
        let before = shipped
        var after = shipped
        after["scene-3d"] = Skills.Skill(name: "scene-3d", description: shipped["scene-3d"]!.description,
                                         body: shipped["scene-3d"]!.body + "\n\nOne more thing found the hard way.")

        let first = Skills.brief(for: project, engine: .claude, session: "c", skills: before)
        XCTAssertTrue(first.contains("unless you already have it"), first)
        Skills.delivered(to: project)
        XCTAssertEqual(Skills.brief(for: project, engine: .claude, session: "c", skills: before), "")
        Skills.delivered(to: project)

        let updated = Skills.brief(for: project, engine: .claude, session: "c", skills: after)
        XCTAssertTrue(updated.contains("Lamp has changed scene-3d since this conversation was told of it: open it again"), updated)
        Skills.delivered(to: project)
        XCTAssertEqual(Skills.brief(for: project, engine: .claude, session: "c", skills: after), "")
        Skills.delivered(to: project)

        // Another skill coming to apply names both, and asks again only for what changed: nothing did.
        try source("Credits.swift", "Text(\"© OpenStreetMap contributors\")\n")
        let more = Skills.brief(for: project, engine: .claude, session: "c", skills: after)
        XCTAssertTrue(more.contains("- maps: ") && more.contains("unless you already have it"), more)
    }

    // MARK: - RequestNote, shared with what the agent is told about the app's AI

    @MainActor func testRequestNote() {
        let note = RequestNote(file: ".lamp/test-shown.json")
        let project = app()
        XCTAssertEqual(note.telling("a", for: project, engine: .pi, session: nil), .fresh)
        note.delivered(to: project, session: "s")
        XCTAssertEqual(note.telling("a", for: project, engine: .pi, session: "s"), .nothing)
        XCTAssertEqual(note.telling("b", for: project, engine: .pi, session: "s"), .changed)
        // Not answered, so not known: the change is still to be told.
        XCTAssertEqual(note.telling("b", for: project, engine: .pi, session: "s"), .changed)

        // Codex doesn't say when it compacts: after eight requests it's told again.
        XCTAssertEqual(note.telling("a", for: project, engine: .codex, session: "x"), .fresh)
        note.delivered(to: project, session: "x")
        for _ in 1..<8 {
            XCTAssertEqual(note.telling("a", for: project, engine: .codex, session: "x"), .nothing)
            note.delivered(to: project)
        }
        XCTAssertEqual(note.telling("a", for: project, engine: .codex, session: "x"), .fresh)
    }
}
