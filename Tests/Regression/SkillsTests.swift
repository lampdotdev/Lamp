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
        XCTAssertEqual(Set(shipped.keys), ["scene-3d", "maps", "device-integrations", "android-design", "phone-controllers",
                                           "app-kinds", "menu-bar", "mac-widgets", "iphone-widgets", "apple-watch", "iphone-hardware",
                                           "building-blocks", "app-ai", "accounts", "app-intents", "share-extension", "finder-files",
                                           "scripting", "game", "game-ui", "2d-game", "icloud-sync", "wish-links", "device-control", "web-or-native",
                                           "3d-game", "web-app", "phone-pages", "tv-design", "lg-developer-mode",
                                           "roku-developer-mode", "more-apps", "github-projects", "assets", "web-game", "game-feel", "game-3d",
                                           "game-physics", "game-levels", "game-art", "game-live", "game-playtest"])
        for (name, skill) in shipped {
            XCTAssertFalse(skill.body.isEmpty, name)
            XCTAssertLessThanOrEqual(skill.description.count, 1024, name)
            XCTAssertNil(skill.name.range(of: #"[^a-z0-9-]"#, options: .regularExpression), name)
        }
        // The integrations' skill and the one on controlling the person's devices are named by the devices' rule, in every
        // prompt, rather than in the list, and how to build a page for phones by the phone-controllers skill and by an app
        // whose code has one; designing for a TV by the TV rows of the table (`Place.skills`), to an app on one, whatever
        // its kind; a device's setup step by the skill itself (`SetupGuides`), to Lamp's setup alone; the short guide to a new Mac game comes whole with make_app_for; every other one is offered to some prompt. How an app's copies and a wish's apps share data
        // is offered to every kind that carries `LampWish`, which is every kind but a device's.
        let everyOffered = [Platform.mac, .iphone, .universal, .android, .tv, .device].flatMap { Skills.offered($0) + Skills.named($0) }
        if Agent.Rules.scenes { XCTAssertEqual(Set(everyOffered), Set(shipped.keys).subtracting(["device-integrations", "device-control", "phone-pages", "tv-design", "web-game"])
                                                       .subtracting(SetupGuides.registrations(shipped).map(\.skill))) }
        XCTAssertTrue(shipped["phone-controllers"]!.body.contains("phone-pages skill"))
        // How an app is made and on which devices, games and their screens, 3D in a page, web apps, phones as controllers, and whether a
        // request is for one more app or a change to the one the wish has, and someone's project on GitHub, are offered to
        // every kind, first, whatever the app is now; so are the narrow skills a web game at home on the Mac names with
        // `make_app_for`, before it's made.
        let everywhere = ["web-or-native", "game", "game-ui", "2d-game", "3d-game", "game-feel", "game-3d", "game-physics", "game-levels", "game-art",
                          "game-live", "game-playtest", "assets", "web-app", "phone-controllers", "more-apps", "github-projects"]
        XCTAssertEqual(Skills.offered(.android), everywhere + ["android-design", "wish-links"])
        XCTAssertEqual(Skills.offered(.tv), everywhere + ["wish-links"])
        XCTAssertEqual(Skills.offered(.device), everywhere)
        XCTAssertEqual(Skills.offered(.iphone), everywhere + ["app-kinds", "iphone-hardware", "iphone-widgets", "apple-watch", "wish-links"])
        // An app for both has the Mac half's menu bar and the iPhone half's widgets, but no desktop widget or 3D.
        XCTAssertEqual(Skills.offered(.universal), everywhere + ["app-kinds", "menu-bar", "iphone-hardware", "iphone-widgets", "apple-watch", "wish-links"])
    }

    /// The Android prompt names its design skill, and the list it offers carries the skill's description.
    /// A no to AI holds for the app it was said in, and nowhere else: every engine's rules, the notes rule when Lamp's
    /// notes are on, and the app-ai skill keep it in that app's APP.md and still offer AI in other apps.
    func testANoToAIHoldsForThatAppAlone() {
        let rules = Agent.tryRules
        XCTAssertTrue(rules.contains("A no is for that app alone"), "the AI rule doesn't scope a no to its app")
        XCTAssertTrue(rules.contains("never in Lamp's notes about the person"), "a no could be saved where every app reads it")
        XCTAssertTrue(rules.contains("still offer it in other apps where it fits"), "a no could stop AI being offered anywhere")
        XCTAssertFalse(rules.contains("don't offer it again unless they bring it up"), "an unscoped \"never again\" is back")
        if Memory.isOn { XCTAssertTrue(rules.contains("A no to AI in one app isn't one of these")) }
        let skill = shipped["app-ai"]!.body.replacingOccurrences(of: "\n", with: " ")
        XCTAssertTrue(skill.contains("A no is for that app alone"), "the skill doesn't scope a no to its app")
        XCTAssertTrue(skill.contains("still offer it in other apps where it fits"))
    }

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

    /// What only some apps need (how each kind of app looks, the menu bar, widgets, the watch, the phone's hardware)
    /// is in skills: each prompt lists the ones it offers, names each where its short rule is, and no longer carries
    /// what they say.
    func testPromptsListTheSkillsInsteadOfCarryingThem() {
        let moved: [String: [String]] = [
            "app-kinds": ["LazyVGrid", "kAXFocusedUIElementAttribute", "nonactivatingPanel", "a spring animation"],
            "menu-bar": ["LampPanelWand", "LampMenuBar.openSettings", "dockIcon: true"],
            "mac-widgets": ["LampWidgetOnly", "lampWand(edgeToEdge", "LampWidget.perform"],
            "iphone-widgets": ["LAMP_WIDGET", "ControlWidgetButton", "Activity.request"],
            "apple-watch": ["LampWatched", "LampWorkout", "accessoryCorner"],
            "iphone-hardware": ["dailyTotals", "bonjourServices", "DataScannerViewController"],
        ]
        for (name, phrases) in moved {
            for phrase in phrases { XCTAssertTrue(shipped[name]!.body.contains(phrase), "\(name) says \(phrase)") }
        }
        let prompts: [(String, String, [String])] = [
            ("Mac", Agent.systemPrompt, Skills.offered(.mac)),
            ("iPhone", Agent.iPhonePrompt(for: .iphone), Skills.offered(.iphone)),
            ("Mac and iPhone", Agent.universalPrompt(for: .iphone), Skills.offered(.universal)),
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
    /// App Intents, share extensions, Finder, scripting, iCloud)
    /// is in skills each prompt names in a one-line rule, not in its list, and the prompts no longer carry it.
    func testPromptsNameTheSkillsTheirShortRulesStandFor() {
        let moved: [String: [String]] = [
            "building-blocks": ["LampFolderWatcher(folder)", "LampSchedule.daily(", "LampWeatherAttribution", "LampSpotlight.index", "lampBackground()", "accessories()"],
            "app-ai": ["SFSpeechRecognizer", "LampAI.when(", "decideEach", "requiresOnDeviceRecognition", "sanitizing"],
            "accounts": ["LampCalendar.events", "LampMail.inbox", "LampComputer.ask(", "Internet Accounts"],
            "app-intents": ["AppShortcutsProvider", "applicationName", "EntityQuery"],
            "share-extension": ["LampShareSheet", "LampShare.onReceive", "Edit Extensions"],
            "finder-files": ["\"opens\":", "bundlePath"],
            "scripting": ["sealed context"],
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

    /// A TV turn's prompt lists the phones' skill instead of carrying what the phone page's says, and a TV app with a
    /// page for phones, or a TV page using them, is told how to build one applies.
    func testTVPromptOffersThePhoneSkill() throws {
        let prompt = Agent.tvPrompt(skills: shipped)
        XCTAssertTrue(prompt.contains("  • phone-controllers: \(shipped["phone-controllers"]!.description)\n"))
        XCTAssertTrue(prompt.contains("the phone-controllers skill says what each choice needs. Open it first"))
        XCTAssertFalse(prompt.contains("LampController.connect"), "the phone page's instructions belong in the skill")
        XCTAssertTrue(shipped["phone-pages"]!.body.contains("LampController.connect"))
        XCTAssertTrue(shipped["phone-pages"]!.body.contains("Lamp.onPhonePage"))
        XCTAssertFalse(shipped["phone-controllers"]!.body.contains("LampController.connect"), "what to weigh, not how to build")

        let web = folder.appendingPathComponent("Web")
        try FileManager.default.createDirectory(at: web, withIntermediateDirectories: true)
        try "Lamp.controllers.start(); Lamp.phonePage();".write(to: web.appendingPathComponent("lamp.js"), atomically: true, encoding: .utf8)
        XCTAssertTrue(Skills.applying(to: app(.tv)).isEmpty, "Lamp's own lamp.js doesn't count")
        try "Lamp.controllers.onButton(function () {});".write(to: web.appendingPathComponent("game.js"), atomically: true, encoding: .utf8)
        XCTAssertEqual(Skills.applying(to: app(.tv)).map(\.name), ["phone-pages"])
        try FileManager.default.removeItem(at: web.appendingPathComponent("game.js"))
        let phone = folder.appendingPathComponent("Phone")
        try FileManager.default.createDirectory(at: phone, withIntermediateDirectories: true)
        try "<p>pad</p>".write(to: phone.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        XCTAssertEqual(Skills.applying(to: app(.tv)).map(\.because), ["it has a page for phones in Phone/"])
        // What the code has decides it, not the kind: any app with a page for phones is told, and one without isn't.
        XCTAssertEqual(Skills.applying(to: app(.mac)).filter { $0.name == "phone-pages" }.count, 1)
        try FileManager.default.removeItem(at: phone)
        XCTAssertTrue(Skills.applying(to: app(.mac)).filter { $0.name == "phone-pages" }.isEmpty, "no page for phones, nothing told")
    }

    /// Every kind's prompt, whatever the app is now, offers how an app is made, games, 3D in a page, web apps and phones
    /// as controllers, so the agent has their reasons for any request; and no prompt names the 2D skill they replace.
    func testEveryKindOffersTheSkillsForEveryChoice() throws {
        let kinds: [Platform] = [.mac, .iphone, .universal, .android, .androidTV, .tv, .game, .webApp, .screen, .device]
        for kind in kinds {
            XCTAssertEqual(Array(Skills.offered(kind).prefix(Skills.everywhere.count)), Skills.everywhere, kind.rawValue)
            XCTAssertEqual(Skills.offered(kind).filter(Skills.everywhere.contains).count, Skills.everywhere.count, "\(kind.rawValue) lists each once")
            XCTAssertFalse(Skills.named(kind).contains("games-2d"), kind.rawValue)
        }
        try FileManager.default.removeItem(at: folder.appendingPathComponent("Package.swift"))
        let prompts: [(String, String)] = [
            ("Mac", Agent.systemPrompt), ("iPhone", Agent.iPhonePrompt(for: .iphone)), ("Mac and iPhone", Agent.universalPrompt(for: .iphone)),
            ("TV", Agent.tvPrompt(skills: shipped)), ("game part", Agent.gamePrompt(part: "Game")), ("screen part", Agent.screenPrompt(part: "Screen")),
        ]
        for (kind, prompt) in prompts { XCTAssertFalse(prompt.contains("games-2d"), "\(kind) still names the old 2D skill") }
        let tv = Agent.tvPrompt(skills: shipped)
        for name in Skills.everywhere { XCTAssertTrue(tv.contains("  • \(name): \(shipped[name]!.description)\n"), "the TV prompt lists \(name)") }
    }

    /// An app on a TV is offered how to design for one, whichever kind it is and however it's made, listed once for all
    /// its TVs; an app on no TV isn't. A make_app_for that puts an app on a TV names the skill, once.
    func testAnAppOnATVIsOfferedItsDesign() {
        let line = "  • tv-design: \(shipped["tv-design"]!.description)\n"
        var game = app(.game)
        game.places = [.mac, .tv, .androidTV]
        var screen = app(.screen)
        screen.places = [.mac, .tv]
        for (what, project) in [("a game on TVs", game), ("a screen on a TV", screen), ("a native Android TV app", app(.androidTV)), ("a TV app", app(.tv))] {
            let offered = Skills.forDevices(of: project, from: shipped)
            XCTAssertEqual(offered.components(separatedBy: line).count - 1, 1, what)
        }
        var onTheMac = app(.game)
        onTheMac.places = [.mac]
        for project in [app(.mac), app(.iphone), app(.android), onTheMac] {
            XCTAssertEqual(Skills.forDevices(of: project, from: shipped), "", project.platform.rawValue)
        }
        // A wish's prompt is every app's: a Mac app in its own folder with a TV app beside it is offered it, once.
        XCTAssertEqual(Skills.forDevices(of: [app(.mac), app(.tv), screen], from: shipped).components(separatedBy: line).count - 1, 1)
        XCTAssertEqual(Skills.forDevices(of: [app(.mac), app(.iphone)], from: shipped), "")
        XCTAssertTrue(Skills.forNewDevices(["mac", "tv"], had: ["mac"]).contains("tv-design skill"))
        XCTAssertEqual(Skills.forNewDevices(["mac", "tv", "android-tv"], had: ["mac", "tv"]), "", "already on a TV")
        XCTAssertEqual(Skills.forNewDevices(["mac", "iphone"]), "")
    }

    /// A page on Lamp's game runtime, a page drawing with three.js or Phaser and Swift on SpriteKit each show the game
    /// skills apply; Lamp's own runtime, lamp.js, three.js and Phaser in Web/ don't count.
    private func game(on places: [Destination]) -> LampProject {
        var project = app(.game)
        project.places = places
        return project
    }

    func testAGamesCodeShowsTheGameSkillsApply() throws {
        let web = folder.appendingPathComponent("Web")
        try FileManager.default.createDirectory(at: web.appendingPathComponent("three/addons"), withIntermediateDirectories: true)
        try "import * as THREE from 'three'; // or phaser() from lamp-phaser.js".write(to: web.appendingPathComponent("lamp-game.js"), atomically: true, encoding: .utf8)
        try "import { x } from 'three'; // lamp-game.js".write(to: web.appendingPathComponent("three/addons/loader.js"), atomically: true, encoding: .utf8)
        try "/* lamp-game.js */".write(to: web.appendingPathComponent("lamp.js"), atomically: true, encoding: .utf8)
        try "import * as Phaser from 'phaser'; import { game } from './lamp-game.js';".write(to: web.appendingPathComponent("lamp-phaser.js"), atomically: true, encoding: .utf8)
        XCTAssertTrue(Skills.applying(to: game(on: [.mac, .ios])).filter { ["game", "2d-game", "3d-game"].contains($0.name) }.isEmpty, "Lamp's own files don't count")
        XCTAssertFalse(DeviceSupport.usesPhaser(game(on: [.mac, .ios]), page: "Web"), "Phaser goes into a page only once its own files use it")

        try "import * as THREE from 'three';\nimport { game } from './lamp-game.js';\n".write(to: web.appendingPathComponent("game.js"), atomically: true, encoding: .utf8)
        let found = Skills.applying(to: game(on: [.mac, .ios])).filter { ["game", "game-ui", "3d-game"].contains($0.name) }
        XCTAssertEqual(found.map(\.name), ["game", "game-ui", "3d-game"])
        XCTAssertEqual(found.first?.because, "its page runs on Lamp's game runtime")
        try "import * as Phaser from 'phaser';\nimport { phaser } from './lamp-phaser.js';\n".write(to: web.appendingPathComponent("game.js"), atomically: true, encoding: .utf8)
        XCTAssertEqual(Skills.applying(to: game(on: [.mac, .ios])).filter { ["game", "2d-game", "3d-game"].contains($0.name) }.map(\.name), ["game", "2d-game"])
        XCTAssertTrue(DeviceSupport.usesPhaser(game(on: [.mac, .ios]), page: "Web"))

        try FileManager.default.removeItem(at: web)
        try source("Scene.swift", "import SpriteKit\n")
        XCTAssertEqual(Skills.applying(to: app(.iphone)).filter { ["game", "game-ui"].contains($0.name) }.map(\.because), ["it's a SpriteKit game", "it's a SpriteKit game"])
    }

    /// A web game at home on the Mac starts from the guide and game-feel: its own code hints at game-3d, game-physics and
    /// 2d-game, never Lamp's runtime or the Phaser every such game draws with; the broad skills serve games elsewhere.
    func testAMacWebGamesCodeHintsAtTheNarrowSkillsOnly() throws {
        let web = folder.appendingPathComponent("Web")
        try FileManager.default.createDirectory(at: web.appendingPathComponent("rapier"), withIntermediateDirectories: true)
        try "import * as Phaser from 'phaser'; import { game } from './lamp-game.js';".write(to: web.appendingPathComponent("lamp-phaser.js"), atomically: true, encoding: .utf8)
        try "import RAPIER from '@dimforge/rapier3d-compat'; this.make.tilemap({})".write(to: web.appendingPathComponent("rapier/rapier.js"), atomically: true, encoding: .utf8)
        let mac = game(on: [.mac])
        XCTAssertTrue(GameKit.isMacWebGame(mac))
        XCTAssertTrue(Skills.applying(to: mac).filter { $0.name.contains("game") }.isEmpty, "Lamp's own files don't count")

        try "import * as Phaser from 'phaser';\nimport { phaser } from './lamp-phaser.js';\n".write(to: web.appendingPathComponent("game.js"), atomically: true, encoding: .utf8)
        XCTAssertEqual(Skills.applying(to: mac).filter { $0.name.contains("game") }.map(\.name), ["game-feel"], "Phaser alone is how every such game draws")

        try "import * as THREE from 'three';\nimport RAPIER from '@dimforge/rapier3d-compat';\nimport { game } from './lamp-game.js';\n".write(to: web.appendingPathComponent("game.js"), atomically: true, encoding: .utf8)
        XCTAssertEqual(Skills.applying(to: mac).filter { $0.name.contains("game") }.map(\.name), ["game-feel", "game-3d", "game-physics"])

        try "import { phaser } from './lamp-phaser.js';\nconst map = this.make.tilemap({ data, tileWidth: 64 });\n".write(to: web.appendingPathComponent("game.js"), atomically: true, encoding: .utf8)
        XCTAssertEqual(Skills.applying(to: mac).filter { $0.name.contains("game") }.map(\.name), ["game-feel", "2d-game"])
    }

    /// A web game at home on the Mac is looked at and played only when the person asks, in every set of rules it's
    /// given: made, changed later in the wish's own folder or in a folder of its own. A game played elsewhere too keeps
    /// playing it before it's done.
    func testAMacWebGamesRulesLeaveTryingItToThePerson() throws {
        let mac = game(on: [.mac]), both = game(on: [.mac, .ios])
        XCTAssertTrue(GameKit.isMacWebGame(mac))
        XCTAssertFalse(GameKit.isMacWebGame(both))
        let mandates = ["Play it as the person would before you finish", "before you say it's done, run that skill's check"]
        let asked = Agent.Rules.macWebGameChecks
        for (place, rules) in [("new", Agent.Rules.newMacGame(in: "Game", guide: "")), ("own folder", Agent.gamePrompt(for: mac)),
                               ("part", Parts.packs(for: [mac])[Parts.skill(of: mac)]?.body ?? ""), ("became a game", Agent.Rules.gameChange(mac))] {
            XCTAssertTrue(rules.contains(asked), place)
            for mandate in mandates { XCTAssertFalse(rules.contains(mandate), "\(place): \(mandate)") }
        }
        for (place, rules) in [("own folder", Agent.gamePrompt(for: both)), ("part", Parts.packs(for: [both])[Parts.skill(of: both)]?.body ?? "")] {
            XCTAssertFalse(rules.contains(asked), place)
            for mandate in mandates { XCTAssertTrue(rules.contains(mandate), "\(place): \(mandate)") }
        }
    }

    /// A page that runs none of the game's own code leaves its window empty with nothing to say why, so it's sent back
    /// as the code's problem. The page names its first module by any name, or writes it inline; Lamp's files don't count.
    func testAMacWebGamesPageMustRunItsOwnCode() throws {
        let web = folder.appendingPathComponent("Web")
        try FileManager.default.createDirectory(at: web, withIntermediateDirectories: true)
        let mac = game(on: [.mac])
        func page(_ body: String) throws -> String? {
            try "<!doctype html><head><script src=\"lamp.js\"></script><script type=\"importmap\">{}</script></head><body>\(body)</body>"
                .write(to: web.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
            return GameKit.entryProblem(of: web, project: mac)
        }
        try "export {};".write(to: web.appendingPathComponent("main.js"), atomically: true, encoding: .utf8)
        try "export {};".write(to: web.appendingPathComponent("lamp-game.js"), atomically: true, encoding: .utf8)
        XCTAssertNotNil(try page(""), "a page that runs nothing of the game's")
        XCTAssertNotNil(try page("<script type=\"module\" src=\"game.js\"></script>"), "a module that isn't there")
        XCTAssertNotNil(try page("<script type=\"module\" src=\"lamp-game.js\"></script>"), "Lamp's runtime isn't the game")
        XCTAssertNotNil(try page("<script src=\"main.js\"></script>"), "a classic script can't import the runtime")
        XCTAssertNil(try page("<script type=\"module\" src=\"./main.js?v=2\"></script>"))
        XCTAssertNil(try page("<script type='module'>import { phaser } from './lamp-phaser.js'; phaser({});</script>"))
    }

    /// A page with no module of its own at all is the code's problem too, not a page with nothing to check.
    func testAMacWebGamesPageWithNoModulesIsSentBack() async throws {
        let web = folder.appendingPathComponent("Web")
        try FileManager.default.createDirectory(at: web, withIntermediateDirectories: true)
        try "<!doctype html><head><script src=\"lamp.js\"></script></head><body></body>".write(to: web.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        let problem = await GameKit.codeProblem(game(on: [.mac]))
        XCTAssertTrue(problem?.contains("runs none of the game's code") == true, String(describing: problem))
    }

    /// `needs` names only the skills a new Mac web game can be handed, in one order whatever the agent's.
    func testNeedsTakesOnlyTheNarrowGameSkills() {
        XCTAssertEqual(try Skills.gameNeeds(nil).get(), [])
        XCTAssertEqual(try Skills.gameNeeds(["game-levels", "game-3d"]).get(), ["game-3d", "game-levels"])
        guard case .failure(let refusal) = Skills.gameNeeds(["game-3d", "game"]) else { return XCTFail("the broad skill isn't a need") }
        XCTAssertTrue(refusal.reason.contains("not game."), refusal.reason)
        guard case .failure = Skills.gameNeeds("game-3d") else { return XCTFail("a list, not a name") }
        XCTAssertEqual(Set(Skills.gameNeeds).subtracting(shipped.keys), [])
    }

    /// A skill made of sections of others shows each of them whole: a heading renamed where it comes from would leave a
    /// hole that nothing else notices.
    func testEverySectionASkillShowsIsThere() throws {
        let raw = Skills.load(from: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/skills"))
        var viewed = 0
        for (name, skill) in raw {
            guard let list = skill.meta["sections"] else { continue }
            for section in Skills.sectionNames(list) {
                XCTAssertNotNil(Skills.section(section, in: raw), "\(name): \(section)")
                viewed += 1
            }
            XCTAssertFalse(skill.body.contains("{{sections}}"), name)
        }
        XCTAssertEqual(viewed, 23)
        let feel = try XCTUnwrap(raw["game-feel"]).body
        XCTAssertTrue(feel.contains("## Fun\n\nA game is for fun"))
        // A web game at home on the Mac is played and judged only when the person asks: what the skills it's written
        // from carry is how to make it, and the checks are game-playtest's alone.
        for name in ["game-feel", "game-3d", "game-art", "game-physics", "game-levels"] {
            let body = try XCTUnwrap(raw[name]).body
            for check in ["## Playtesting", "## Check the real opening", "## Proof", "## Checking it", "critique", "before you finish"] {
                XCTAssertFalse(body.contains(check), "\(name): \(check)")
            }
        }
        let playtest = try XCTUnwrap(raw["game-playtest"]).body
        for check in ["## Playtesting", "## Check the real opening", "## Proof", "## Checking it", "**A critique:**"] { XCTAssertTrue(playtest.contains(check), check) }
        XCTAssertFalse(Skills.gameNeeds.contains("game-playtest"), "opened when asked, never handed")
        let physics = try XCTUnwrap(raw["game-physics"]).body
        XCTAssertTrue(physics.contains("**Whether a game needs it.**"))
        XCTAssertFalse(physics.contains("## What costs the most"), "a section ends at the next heading as high")
        let threeD = try XCTUnwrap(raw["game-3d"]).body
        XCTAssertTrue(threeD.contains("three.js runs in a page"), "the text before 3d-game's first section")
        XCTAssertFalse(threeD.contains("# 3D in a web page\n"), "without its title")
    }

    /// A TV app's page brings in three.js by the path of Lamp's copy as well as by the import map's name, in a module
    /// file of its own: either shows the 3d-game skill applies, and Lamp's copy in Web/three still doesn't.
    func testATVPagesThreeShowsThe3DGameSkillApplies() throws {
        let web = folder.appendingPathComponent("Web")
        try FileManager.default.createDirectory(at: web.appendingPathComponent("three"), withIntermediateDirectories: true)
        try "import * as THREE from './three.core.js';".write(to: web.appendingPathComponent("three/three.module.js"), atomically: true, encoding: .utf8)
        XCTAssertFalse(Skills.applying(to: app(.tv)).contains { $0.name == "3d-game" }, "Lamp's copy doesn't count")
        try "import * as THREE from './three/three.module.js';\n".write(to: web.appendingPathComponent("scene.mjs"), atomically: true, encoding: .utf8)
        XCTAssertEqual(Skills.applying(to: app(.tv)).filter { $0.name == "3d-game" }.map(\.because), ["its page draws with three.js"])
        try FileManager.default.removeItem(at: web.appendingPathComponent("scene.mjs"))
        try "<script type=\"module\">const { GLTFLoader } = await import('three/addons/loaders/GLTFLoader.js');</script>"
            .write(to: web.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        XCTAssertTrue(Skills.applying(to: app(.tv)).contains { $0.name == "3d-game" })
    }

    func testReadingASkill() {
        let (status, answer) = Skills.read(["name": "maps"], from: shipped)
        XCTAssertEqual(status, 200)
        XCTAssertEqual(answer["text"] as? String, shipped["maps"]!.body)

        let (missing, error) = Skills.read(["name": "3d"], from: shipped)
        XCTAssertEqual(missing, 400)
        XCTAssertEqual(error["error"] as? String, "There's no skill called \"3d\". The skills are: 2d-game, 3d-game, accounts, android-design, app-ai, app-intents, app-kinds, apple-watch, assets, building-blocks, device-control, device-integrations, finder-files, game, game-3d, game-art, game-feel, game-levels, game-live, game-physics, game-playtest, game-ui, github-projects, icloud-sync, iphone-hardware, iphone-widgets, lg-developer-mode, mac-widgets, maps, menu-bar, more-apps, phone-controllers, phone-pages, roku-developer-mode, scene-3d, scripting, share-extension, tv-design, web-app, web-game, web-or-native, wish-links.")
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
