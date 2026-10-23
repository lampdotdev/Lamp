import CryptoKit
import Foundation

/// Guidance the builder opens only when a request needs it, so the system prompt carries what nearly every
/// request uses and not what few do. Each skill is a folder in Resources/skills with a SKILL.md in the Agent
/// Skills format (a `name` and a `description`, then the instructions). The prompt lists each skill it offers
/// by name and description (`index`); the agent opens one with `read_skill`, the same tool for every engine,
/// and Lamp answers from the copy in its own bundle, so a skill changed in an update reaches a conversation
/// that began before it. When an app's code already shows a skill applies (it imports RealityKit), Lamp says
/// so with the request (`brief`) rather than leave it to the agent to notice.
enum Skills {
    struct Skill: Equatable {
        let name: String
        let description: String
        let body: String
    }

    /// Lamp's own skills, from its bundle.
    static let all: [String: Skill] = Bundle.main.resourceURL.map { load(from: $0.appendingPathComponent("skills")) } ?? [:]

    /// The skills `read_skill` answers: Lamp's own, and the rules of each kind of app a wish's other part can be
    /// (`Parts.packs`), which are made from the prompts' own rules rather than kept as files.
    static var readable: [String: Skill] { all.merging(Parts.packs) { own, _ in own } }

    /// Every skill in a folder of skill folders, by name. A folder whose SKILL.md can't be read is left out.
    static func load(from folder: URL) -> [String: Skill] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var skills: [String: Skill] = [:]
        for name in names {
            guard let text = try? String(contentsOf: folder.appendingPathComponent(name).appendingPathComponent("SKILL.md"), encoding: .utf8),
                  let skill = parse(text) else { continue }
            skills[skill.name] = skill
        }
        return skills
    }

    /// A SKILL.md: frontmatter between `---` lines with at least `name` and `description` on one line each,
    /// then the instructions.
    static func parse(_ text: String) -> Skill? {
        let lines = text.components(separatedBy: "\n")
        guard lines.first == "---", let close = lines.dropFirst().firstIndex(of: "---") else { return nil }
        var fields: [String: String] = [:]
        for line in lines[1..<close] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            fields[line[..<colon].trimmingCharacters(in: .whitespaces)] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard let name = fields["name"], !name.isEmpty, let description = fields["description"], !description.isEmpty else { return nil }
        return Skill(name: name, description: description,
                     body: lines[(close + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The skills a prompt offers, by the kind of app it's for. How each kind of app looks is for the apps that have
    /// a look of Lamp's kinds (Mac, iPhone, both). The menu bar is the Mac half's, a desktop widget a Mac app's alone
    /// (an app for both has the iPhone half's widgets), and the phone's hardware, its widgets and the watch the iPhone
    /// half's. 3D scenes need a Mac app on a Mac that can run RealityView, and a real place from map data is built as
    /// one. The Chrome sidebar's page is offered where the prompt has the sidebar's rule. An Android app's design is
    /// offered to its prompt alone, and a TV app's page for phones to the TV prompt. `device-integrations` isn't
    /// listed: every prompt's rule for devices (`Agent.deviceRules`) names it.
    static func offered(_ platform: Platform, sidebar: Bool = false) -> [String] {
        let kinds: [String] = switch platform {
        case .mac: ["app-kinds", "menu-bar", "mac-widgets"] + (Agent.Rules.scenes ? ["scene-3d", "maps"] : [])
        case .iphone: ["app-kinds", "iphone-hardware", "iphone-widgets", "apple-watch"]
        case .universal: ["app-kinds", "menu-bar", "iphone-hardware", "iphone-widgets", "apple-watch"]
        case .android: ["android-design"]
        case .tv: ["phone-controllers"]
        case .device: []
        }
        return kinds + (sidebar ? ["chrome-sidebar"] : [])
    }

    /// The skills a prompt names in its own short rules rather than in its list, so each costs the prompt one rule
    /// and not a rule and a line: the building blocks, AI in the app, the person's accounts, App Intents, share
    /// extensions, scripting and 2D games, for both kinds; Finder for apps with a Mac half; iCloud for apps with an
    /// iPhone half (a Mac app's prompt has no iCloud rule). The Mac's permissions and a change of subject stay whole
    /// in the prompt: their rules are policy the agent must keep without first deciding a skill applies.
    static func named(_ platform: Platform) -> [String] {
        let both = ["building-blocks", "app-ai", "accounts", "app-intents", "share-extension", "scripting", "games-2d"]
        return switch platform {
        case .mac: both + ["finder-files"]
        case .iphone: both + ["icloud-sync"]
        case .universal: both + ["finder-files", "icloud-sync"]
        case .android, .tv, .device: []
        }
    }

    /// The rule that lists a prompt's skills; empty when it offers none.
    static func index(_ names: [String], from skills: [String: Skill] = all) -> String {
        let listed = names.compactMap { skills[$0] }
        guard !listed.isEmpty else { return "" }
        return "- Skills: guidance kept out of these rules until it's needed. Before working on one of these, open it with `read_skill` and follow it:\n"
            + listed.map { "  • \($0.name): \($0.description)\n" }.joined()
    }

    /// `read_skill`, for every engine.
    static func read(_ arguments: [String: Any], from skills: [String: Skill] = readable) -> (Int, [String: Any]) {
        let name = (arguments["name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        guard let skill = skills[name] else {
            return (400, ["error": "There's no skill called \"\(name)\". The skills are: \(skills.keys.sorted().joined(separator: ", "))."])
        }
        return (200, ["text": skill.body])
    }

    // MARK: - Telling the agent a skill applies

    /// The skills an app's own code shows it uses, each with what showed it, among those its prompt offers. A new
    /// app (still Lamp's placeholder) is about to be given its kind, so it's told how the kinds look.
    /// A wish's other parts (`parts`) each bring their kind's rules, which apply as long as the wish has the part.
    static func applying(to project: LampProject, parts: [LampProject] = []) -> [(name: String, because: String)] {
        let offered = offered(project.platform, sidebar: BrowserBridge.enabled && project.platform.hasMac) + named(project.platform)
        var found: [(name: String, because: String)] = parts.map { part in
            (Parts.skill(for: part.platform), "this wish has \(Parts.name(of: part.platform)) in \(part.dir.lastPathComponent)/: its rules, for the files there (part \"\(Parts.word(for: part.platform))\" in look_at_app and use_app)")
        }
        if offered.contains("app-kinds"), !project.makesNoApp, Template.isScaffold(project) { found.append(("app-kinds", "it's a new app, still to be given its kind")) }
        if offered.contains("chrome-sidebar"), Template.hasSidebarPage(project) { found.append(("chrome-sidebar", "it has a sidebar page in Chrome")) }
        if offered.contains("menu-bar"), appSwift(of: project, matches: #"\bLampMenuBar\b"#) { found.append(("menu-bar", "its code uses LampMenuBar")) }
        if offered.contains("mac-widgets"), Template.hasWidget(project) { found.append(("mac-widgets", "it has a widget in Widget/")) }
        if offered.contains("iphone-widgets"), Template.hasWidget(project) { found.append(("iphone-widgets", "it has widgets or Live Activities in Widget/")) }
        if offered.contains("apple-watch"), Template.hasWatch(project) { found.append(("apple-watch", "it has an Apple Watch app in Watch/")) }
        if offered.contains("iphone-hardware"), appSwift(of: project, matches: phoneHardware) { found.append(("iphone-hardware", "its code uses the phone's hardware or Health")) }
        if offered.contains("scene-3d"), Template.usesScene(project) { found.append(("scene-3d", "its code uses RealityKit")) }
        if offered.contains("maps"), usesMapData(project) { found.append(("maps", "its code uses OpenStreetMap data")) }
        if offered.contains("phone-controllers"), let why = phonePageUse(project) { found.append(("phone-controllers", why)) }
        if offered.contains("building-blocks"), appSwift(of: project, matches: buildingBlocks) { found.append(("building-blocks", "its code uses Lamp's building blocks")) }
        if offered.contains("app-ai"), appSwift(of: project, matches: #"\bLampAI\.|\bimport (Vision|VisionKit|Speech|NaturalLanguage|SoundAnalysis|Translation)\b"#) { found.append(("app-ai", "its code uses AI")) }
        if offered.contains("accounts"), appSwift(of: project, matches: #"\b(LampCalendar|LampReminders|LampContacts|LampMail|LampComputer)\b|LampFolders\.synced"#) { found.append(("accounts", "its code reaches the person's accounts or other apps")) }
        if offered.contains("app-intents"), appSwift(of: project, matches: #"\bimport AppIntents\b"#) { found.append(("app-intents", "it has App Intents")) }
        if offered.contains("share-extension"), Template.hasShare(project) { found.append(("share-extension", "it has a share extension in Share/")) }
        if offered.contains("scripting"), appSwift(of: project, matches: #"\bLampScript\b"#) { found.append(("scripting", "its code uses LampScript")) }
        if offered.contains("games-2d"), appSwift(of: project, matches: #"\bimport SpriteKit\b"#) { found.append(("games-2d", "it's a SpriteKit game")) }
        if offered.contains("icloud-sync"), appSwift(of: project, matches: #"\bLampSync\b"#) { found.append(("icloud-sync", "its code uses LampSync")) }
        return found
    }

    /// What in an app's Swift shows it uses one of the blocks the building-blocks skill covers.
    static let buildingBlocks = #"\b(LampNotifications|LampSchedule|LampText|LampFolderWatcher|LampFolders|LampHotKey|LampLoginItem|LampClipboardWatcher|LampPhotos|LampLocation|LampWeather|LampMusic|LampSpotlight|LampHome|LampDropZone)\b|\.lampDropFiles|\.lampBackground|\.lampSpotlightOpen"#

    /// What in an app's Swift shows it uses what the iphone-hardware skill covers: Lamp's blocks for motion and
    /// Health, or the frameworks the skill names for the camera, scanning, Face ID, Bluetooth, nearby phones, NFC and AR.
    static let phoneHardware = #"\b(LampMotion|LampHealth|AVCaptureSession|DataScannerViewController|VNDocumentCameraViewController|LocalAuthentication|CoreBluetooth|MultipeerConnectivity|CoreNFC|CoreHaptics|ARKit)\b"#

    /// Whether some Swift of the app's own, in Sources/ and not Lamp's support files, matches a pattern.
    static func appSwift(of project: LampProject, matches pattern: String) -> Bool {
        let sources = project.dir.appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        return files.contains { file in
            file.pathExtension == "swift" && !["LampSupport.swift", Template.sceneSupportFile].contains(file.lastPathComponent)
                && ((try? String(contentsOf: file, encoding: .utf8))?.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil)
        }
    }

    /// Whether some Swift of the app's own fetches or shows OpenStreetMap data: the maps skill has it fetched
    /// from the Overpass API and credits "© OpenStreetMap contributors" on screen, so either is in the code.
    static func usesMapData(_ project: LampProject) -> Bool {
        appSwift(of: project, matches: #"OpenStreetMap|overpass-api|overpass\.|/api/interpreter"#)
    }

    /// What shows a TV app has a page for phones: a Phone/ folder, or its own web code using the phone page's address
    /// or phones as controllers (Lamp's own lamp.js names both, so it doesn't count).
    static func phonePageUse(_ project: LampProject) -> String? {
        let fm = FileManager.default
        if let page = try? fm.contentsOfDirectory(atPath: project.dir.appendingPathComponent(TVTemplate.phoneFolder).path),
           !page.isEmpty { return "it has a page for phones in Phone/" }
        let web = project.dir.appendingPathComponent(TVTemplate.webFolder)
        let files = fm.enumerator(at: web, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        let uses = files.contains { file in
            ["js", "html"].contains(file.pathExtension) && file.lastPathComponent != "lamp.js"
                && ((try? String(contentsOf: file, encoding: .utf8))?.range(of: #"Lamp\.(controllers|phonePage|onPhonePage)"#, options: .regularExpression) != nil)
        }
        return uses ? "its TV page uses phones as controllers or a second screen" : nil
    }

    /// Which version of a skill this is: a change to its instructions in a Lamp update changes it.
    static func revision(of name: String, in skills: [String: Skill] = readable) -> String {
        SHA256.hash(data: Data((skills[name]?.body ?? "").utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    /// The line at the end of a request naming the skills that apply to the app, sent as `AIStatus.brief` is:
    /// once per conversation and when it changes. Nothing when none apply. What's remembered as told includes
    /// each skill's revision, so a conversation that opened a skill before a Lamp update changed it is told to
    /// open it again rather than go on with the copy it has.
    @MainActor static func brief(for project: LampProject, engine: Engine, session: String?, skills: [String: Skill] = readable) -> String {
        let applying = applying(to: project, parts: Store.shared.parts(of: project))
        let now = applying.map { "- \($0.name): \($0.because)" }.joined(separator: "\n")
        let revisions = applying.map { "\($0.name)@\(revision(of: $0.name, in: skills))" }
        let told = note.lastTold(for: project, engine: engine, session: session)
        let telling = note.telling(now + "\nrevisions: " + revisions.joined(separator: " "), for: project, engine: engine, session: session)
        guard !now.isEmpty, telling != .nothing else { return "" }
        let toldRevisions = told?.components(separatedBy: "\n").last { $0.hasPrefix("revisions: ") }?
            .dropFirst("revisions: ".count).split(separator: " ").map(String.init) ?? []
        let updated = applying.map(\.name).filter { name in
            toldRevisions.contains { $0.hasPrefix(name + "@") } && !toldRevisions.contains(name + "@" + revision(of: name, in: skills))
        }
        let open = updated.isEmpty
            ? "Open each with `read_skill` before changing that part of the app, unless you already have it in this conversation"
            : "Open each with `read_skill` before changing that part of the app. Lamp has changed \(updated.joined(separator: " and ")) since this conversation was told of it: open it again, even if you have it, and follow the new one"
        return "\n\n---\nSkills that apply to this app (from Lamp, not part of the request above). \(open):\n\(now)"
    }

    /// The agent answered, so the request and the line in it arrived.
    @MainActor static func delivered(to project: LampProject, session: String? = nil) { note.delivered(to: project, session: session) }

    /// The engine summed up its conversation, and with it any skill it had opened.
    @MainActor static func compacted(_ project: LampProject) { note.compacted(project) }

    @MainActor private static let note = RequestNote(file: ".lamp/skills-shown.json")
}
