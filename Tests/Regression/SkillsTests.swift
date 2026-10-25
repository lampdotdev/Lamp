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
        // An app already made: a draft, or one still showing Lamp's placeholder, is new and told how the kinds look.
        try "// swift-tools-version:5.9\n".write(to: folder.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
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
        XCTAssertEqual(Set(shipped.keys), ["scene-3d", "maps", "chrome-sidebar", "device-integrations", "android-design", "phone-controllers",
                                           "app-kinds", "menu-bar", "mac-widgets", "iphone-widgets", "apple-watch", "iphone-hardware",
                                           "building-blocks", "app-ai", "accounts", "app-intents", "share-extension", "finder-files",
                                           "scripting", "games-2d", "icloud-sync", "wish-links"])
        for (name, skill) in shipped {
            XCTAssertFalse(skill.body.isEmpty, name)
            XCTAssertLessThanOrEqual(skill.description.count, 1024, name)
            XCTAssertNil(skill.name.range(of: #"[^a-z0-9-]"#, options: .regularExpression), name)
        }
        // The integrations' skill is named by its own rule, in every prompt, rather than in the list, and the one on how
        // a wish's apps share data by its rule in the prompt of a wish of several apps only; every other one is offered
        // to some prompt.
        let everyOffered = [Platform.mac, .iphone, .universal, .android, .tv, .device].flatMap { Skills.offered($0, sidebar: true) + Skills.named($0) }
        if Agent.Rules.scenes { XCTAssertEqual(Set(everyOffered), Set(shipped.keys).subtracting(["device-integrations", "wish-links"])) }
        XCTAssertEqual(Skills.offered(.android), ["android-design"])
        XCTAssertEqual(Skills.offered(.tv), ["phone-controllers"])
        XCTAssertEqual(Skills.offered(.device), [])
        XCTAssertEqual(Skills.offered(.iphone), ["app-kinds", "iphone-hardware", "iphone-widgets", "apple-watch"])
        // An app for both has the Mac half's menu bar and the iPhone half's widgets, but no desktop widget or 3D.
        XCTAssertEqual(Skills.offered(.universal), ["app-kinds", "menu-bar", "iphone-hardware", "iphone-widgets", "apple-watch"])
        // The sidebar's page is offered wherever the prompt has the sidebar's rule, an app for both included.
        XCTAssertEqual(Skills.offered(.universal, sidebar: true).last, "chrome-sidebar")
    }

    /// The Android prompt names its design skill, and the list it offers carries the skill's description.
    func testAndroidPromptOffersDesignSkill() {
        XCTAssertTrue(Agent.androidPrompt().contains("open the android-design skill"))
        let index = Skills.index(Skills.offered(.android), from: shipped)
        XCTAssertTrue(index.contains("  • android-design: \(shipped["android-design"]!.description)\n"))
    }

    /// The Mac prompt no longer carries what the 3D and map skills say, and their list names both.
    func testMacPromptListsSkillsInsteadOfCarryingThem() throws {
        try XCTSkipUnless(Agent.Rules.scenes, "3D scenes are offered only on macOS 15 or later")
        let prompt = Agent.systemPrompt
        let index = Skills.index(Skills.offered(.mac), from: shipped)
        XCTAssertTrue(index.contains("`read_skill`"))
        XCTAssertTrue(index.contains("  • scene-3d: \(shipped["scene-3d"]!.description)\n"))
        XCTAssertTrue(index.contains("  • maps: \(shipped["maps"]!.description)\n"))
        XCTAssertFalse(prompt.contains("LampMesh"), "the 3D instructions belong in the skill")
        XCTAssertFalse(prompt.contains("Overpass"), "the map data instructions belong in the skill")
        XCTAssertTrue(shipped["scene-3d"]!.body.contains("LampMesh"))
        XCTAssertTrue(shipped["maps"]!.body.contains("Overpass"))
    }

    /// What only some apps need (how each kind of app looks, the menu bar, widgets, the watch, the phone's hardware,
    /// the Chrome sidebar's details) is in skills: each prompt lists the ones it offers, names each where its short
    /// rule is, and no longer carries what they say.
    func testPromptsListTheSkillsInsteadOfCarryingThem() {
        let moved: [String: [String]] = [
            "app-kinds": ["LazyVGrid", "kAXFocusedUIElementAttribute", "nonactivatingPanel", "a spring animation"],
            "menu-bar": ["LampPanelWand", "LampMenuBar.openSettings", "dockIcon: true"],
            "mac-widgets": ["LampWidgetOnly", "lampWand(edgeToEdge", "LampWidget.perform"],
            "iphone-widgets": ["LAMP_WIDGET", "ControlWidgetButton", "Activity.request"],
            "apple-watch": ["LampWatched", "LampWorkout", "accessoryCorner"],
            "iphone-hardware": ["dailyTotals", "bonjourServices", "DataScannerViewController"],
            "chrome-sidebar": ["data-lamp-reads", "LampBrowser.pageChanged", "lamp.onMenu"],
        ]
        for (name, phrases) in moved {
            for phrase in phrases { XCTAssertTrue(shipped[name]!.body.contains(phrase), "\(name) says \(phrase)") }
        }
        BrowserBridge.testOverride = true
        defer { BrowserBridge.testOverride = nil }
        let prompts: [(String, String, [String])] = [
            ("Mac", Agent.systemPrompt, Skills.offered(.mac, sidebar: true)),
            ("iPhone", Agent.iPhonePrompt(for: .iphone), Skills.offered(.iphone)),
            ("Mac and iPhone", Agent.universalPrompt(for: .iphone), Skills.offered(.universal, sidebar: true)),
        ]
        for (kind, prompt, offered) in prompts {
            let index = Skills.index(offered, from: shipped)
            for name in moved.keys where offered.contains(name) {
                XCTAssertTrue(index.contains("  • \(name): \(shipped[name]!.description)\n"), "\(kind) lists \(name)")
                XCTAssertTrue(prompt.contains("the \(name) skill"), "\(kind) names \(name) where its rule is")
            }
            for (name, phrases) in moved {
                for phrase in phrases { XCTAssertFalse(prompt.contains(phrase), "\(kind) still carries \(name)'s \(phrase)") }
            }
        }
        XCTAssertEqual(Set(prompts.flatMap(\.2)).intersection(moved.keys), Set(moved.keys))
    }

    /// What every app might need but most requests don't (the building blocks' calls, AI in the app, the accounts,
    /// App Intents, share extensions, Finder, scripting, 2D games, iCloud)
    /// is in skills each prompt names in a one-line rule, not in its list, and the prompts no longer carry it.
    func testPromptsNameTheSkillsTheirShortRulesStandFor() {
        let moved: [String: [String]] = [
            "building-blocks": ["LampFolderWatcher(folder)", "LampSchedule.daily(", "LampWeatherAttribution", "LampSpotlight.index", "lampBackground()", "accessories()"],
            "app-ai": ["SFSpeechRecognizer", "LampAI.when(", "decideEach", "requiresOnDeviceRecognition", "sanitising"],
            "accounts": ["LampCalendar.events", "LampMail.inbox", "LampComputer.ask(", "Internet Accounts"],
            "app-intents": ["AppShortcutsProvider", "applicationName", "EntityQuery"],
            "share-extension": ["LampShareSheet", "LampShare.onReceive", "Edit Extensions"],
            "finder-files": ["\"opens\":", "bundlePath"],
            "scripting": ["sealed context"],
            "games-2d": ["SKPhysicsBody", "resizeFill"],
            "icloud-sync": ["LampSync.collection", "reproductive"],
        ]
        for (name, phrases) in moved {
            for phrase in phrases { XCTAssertTrue(shipped[name]!.body.contains(phrase), "\(name) says \(phrase)") }
        }
        let prompts: [(String, String, Platform)] = [
            ("Mac", Agent.systemPrompt, .mac),
            ("iPhone", Agent.iPhonePrompt(for: .iphone), .iphone),
            ("Mac and iPhone", Agent.universalPrompt(for: .iphone), .universal),
        ]
        for (kind, prompt, platform) in prompts {
            for name in Skills.named(platform) {
                XCTAssertNotNil(shipped[name], name)
                XCTAssertTrue(prompt.contains("the \(name) skill"), "\(kind) names \(name)")
            }
            for (name, phrases) in moved {
                for phrase in phrases { XCTAssertFalse(prompt.contains(phrase), "\(kind) still carries \(name)'s \(phrase)") }
            }
        }
        XCTAssertEqual(Set(prompts.flatMap { Skills.named($0.2) }), Set(moved.keys))
        // The Mac's permission rule and the theme rule stay whole in the prompt: they're policy the agent keeps
        // without first deciding that a skill applies.
        for (kind, prompt, platform) in prompts {
            XCTAssertTrue(prompt.contains("The theme follows the subject."), "\(kind) keeps the theme rule")
            if platform.reaches(.mac) { XCTAssertTrue(prompt.contains("`LampPermissionGate(.fullDiskAccess"), "\(kind) keeps the permission rule") }
        }
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
        XCTAssertEqual(error["error"] as? String, "There's no skill called \"3d\". The skills are: accounts, android-design, app-ai, app-intents, app-kinds, apple-watch, building-blocks, chrome-sidebar, device-integrations, finder-files, games-2d, icloud-sync, iphone-hardware, iphone-widgets, mac-widgets, maps, menu-bar, phone-controllers, scene-3d, scripting, share-extension, wish-links.")
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

        try source("Bar.swift", "LampMenuBar(\"Timer\", systemImage: \"timer\") { PanelView() }\n")
        XCTAssertEqual(Skills.applying(to: app()).map(\.name), ["menu-bar", "scene-3d", "maps"])
        try source("Steps.swift", "import CoreMotion\nlet steps = try await LampHealth.total(.steps)\n")
        XCTAssertEqual(Skills.applying(to: app(.iphone)).map(\.name), ["iphone-hardware"])
        XCTAssertFalse(Skills.applying(to: app()).map(\.name).contains("iphone-hardware"), "a Mac app isn't offered it")

        // A new app, still Lamp's placeholder, is about to be given its kind.
        try FileManager.default.removeItem(at: folder.appendingPathComponent("Package.swift"))
        XCTAssertEqual(Skills.applying(to: app(.iphone)).first?.name, "app-kinds")
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
