import Foundation

/// A wish made of more than one app: a TV app with an iPhone app that controls it, say. No app of a wish leads, and any
/// of them can be added, replaced or taken away on the person's word, the wish keeping its name, chat and history. Each
/// app is in a folder of the wish's (`iPhone/`, `Mac/`, `TV/`), with its own `.lamp/meta.json`, build files, bundle id
/// and runtime folder, so it's built, opened, looked at and used exactly as an app of that kind is; a wish made before
/// that keeps its first app in its own folder (`LampProject.holdsApp`) until it's taken away. That folder is one more
/// place an app lives, not a role: the TV app of a wish is reached the same way from it or from `TV/`. What an app
/// doesn't have of its own is the wish's: the chat and its turns, the versions (one history for the whole folder), the
/// icon and the name. Lamp keeps an app in a folder of its own in `Store.projects` beside its wish
/// (`LampProject.partOf`), never on the desk.
///
/// What the agent knows follows the apps: a wish whose own folder holds an app has that kind's prompt, with one rule
/// naming the others; a wish whose apps are all in folders has the wish's prompt (`Agent.wishPrompt`). Each kind's rules
/// for an app in a folder are a skill of their own (`target-iphone`, …, `Parts.packs`), named with the request once the
/// wish has that app (`Skills.applying`), so a conversation reads a kind's rules only when its wish has one.
/// One of the apps a wish should have (`LampProject.apps`, kept in the wish's own meta.json beside what its folder
/// holds): its kind and, while it isn't made yet, what stops it ("this Mac can't build the iPhone app yet…"), so a quit
/// or a failure between asking for an app and making it loses neither.
struct WishApp: Codable, Hashable {
    var kind: Platform
    var needs: String? = nil
    /// For a game or a screen not made yet, where it's to be played or shown from the start (`LampProject.places`).
    var places: [Destination]? = nil
    /// The devices it was asked for, as they were named ("ipad"), which give the family Try On opens it on: kept whole
    /// while it waits, so it's made as asked whenever it's made (`AppTarget.waiting`). Nil in a list from before.
    var devices: [String]? = nil
    /// For a device's app, the integration it's for (`LampProject.integration`), which names its folder (Roku/).
    var integration: String? = nil

    /// The same app, now stopped by this (or no longer, for nil), and nothing else changed.
    func needing(_ problem: String?) -> WishApp {
        var app = self
        app.needs = problem
        return app
    }
}

enum Parts {
    /// The folder a part of this kind lives in, inside the wish's. A device's app lives in its integration's (Roku/),
    /// when it's said which.
    static func folder(for kind: Platform, integration: String? = nil) -> String {
        if let integration, let folder = kind.target.part?.folderFor?(DeviceApps.split(integration).integration) { return folder }
        return kind.target.part?.folder ?? kind.rawValue.prefix(1).uppercased() + kind.rawValue.dropFirst()
    }

    /// A part's id: its wish's, then its folder. Lamp's own ids are folder names, which never hold a dot, so no wish's
    /// id is ever a part's.
    static func id(wish: String, folder: String) -> String { wish + "." + folder.lowercased() }
    /// A part's instance: its wish's, kept through renames, then its folder.
    static func instance(wish: LampProject, folder: String) -> String { (wish.instance.isEmpty ? wish.id : wish.instance) + "." + folder }

    /// Every folder a part can be in.
    static var folders: Set<String> { Set(Targets.all.compactMap(\.part).flatMap(\.folders)) }

    /// The folder an app the wish asks for and doesn't have yet will be made in (`Store.addPart`): the one a shared file
    /// had it in, for one whose files are kept for it, else the one its kind gets. It's that app's name among the wish's
    /// apps from the start (`WishRooms.peer`), so what the others say to it while it waits still reaches it once made.
    static func folder(waiting app: WishApp, in wish: URL) -> String {
        Sharing.keptFolder(in: wish, for: app.kind) ?? folder(for: app.kind, integration: app.integration)
    }
    static func folder(waiting kind: Platform, in wish: URL) -> String { folder(waiting: WishApp(kind: kind), in: wish) }

    /// Whether an app of this kind can be in this folder: one of Lamp's part folders for the kind's family, as an app
    /// changed in place within its family keeps the folder it was made in (an iPhone app made for the Mac too, in iPhone/).
    static func folder(_ folder: String, canHold kind: Platform) -> Bool {
        Targets.all.contains { $0.part?.folders.contains(folder) == true && $0.part?.family == kind.target.part?.family }
    }

    /// Where Lamp keeps its wishes (`Store.root`): a part's folder is always one of `folders`, inside a wish's folder here.
    static let appsRoot = Edition.supportFolder.appendingPathComponent("Apps")

    /// The word for a part in `look_at_app` and `use_app`'s `part`, and in what Lamp tells the agent.
    static func word(for kind: Platform) -> String { kind.target.part?.word ?? kind.rawValue }

    /// What a part is, in the agent's words: "the iPhone app".
    static func name(of kind: Platform) -> String { kind.target.identity.name }

    /// What one app of a wish is, in the agent's and the person's words: a device's app is named for its device ("the
    /// Roku app"), every other by its kind.
    static func name(of kind: Platform, integration: String?) -> String {
        guard kind.reaches(.device), !kind.addsPlaces, let device = integration.flatMap(Integrations.integration(_:))?.name else { return name(of: kind) }
        return "the \(device) app"
    }
    static func name(of app: LampProject) -> String { name(of: app.platform, integration: listedIntegration(of: app)) }
    static func name(of app: WishApp) -> String { name(of: app.kind, integration: app.integration) }

    /// An app's own menu in the chat's bar: "TV App", and a device's app by its device ("Roku App").
    static func menu(of app: LampProject) -> (name: String, symbol: String) {
        let menu: (name: String, symbol: String) = app.platform.target.part?.menu ?? ("App", "app")
        guard app.platform.target.part?.folderFor != nil, let device = DeviceApps.integration(for: app)?.name else { return menu }
        return (device + " App", menu.symbol)
    }

    /// `part` in `look_at_app` and `use_app` for one app of a wish: a device's app goes by its folder ("roku"), since
    /// "device" says nothing of which.
    static func word(of app: LampProject) -> String {
        if app.isPart, app.platform.target.part?.folderFor != nil { return app.dir.lastPathComponent.lowercased() }
        return listedIntegration(of: app).map { folder(for: app.platform, integration: $0).lowercased() } ?? word(for: app.platform)
    }

    /// The folders of a wish's other parts, found in its folder: one of Lamp's own part folders holding the scaffold of
    /// a kind that folder can hold (any kind of the same code: any of Apple's kinds in an Apple folder, since a part made
    /// for more devices is changed in place and keeps its folder; a TV app in TV/), at most one of each code. They're
    /// found from what the wish's versions keep (the scaffold), never from a list kept beside them, so a rename, an Undo
    /// or a restored version can't leave the two telling different stories: a part comes and goes with its files.
    static func folders(in wish: URL) -> [String] {
        var found: [String] = [], families: Set<String> = []
        for part in Targets.all.compactMap(\.part) {
            if let marked = part.marked {
                for folder in marked(wish) where !found.contains(folder) {
                    guard kindOfScaffold(in: wish.appendingPathComponent(folder), wish: wish)?.target.part?.family == part.family else { continue }
                    found.append(folder)
                }
                continue
            }
            for folder in part.folders {
                guard let kind = kindOfScaffold(in: wish.appendingPathComponent(folder), wish: wish),
                      kind.target.part?.family == part.family, families.insert(part.family).inserted else { continue }
                found.append(folder)
            }
        }
        return found
    }

    /// The kind of app the scaffold in a part's folder is, read without following a link (`AppFile`): the folder is the
    /// agent's to write.
    static func kindOfScaffold(in dir: URL, wish: URL) -> Platform? {
        Targets.matchOrder.first { $0.part?.isMade(dir, wish) == true }?.platform
    }

    /// Whether the parts Lamp has listed for a wish are what its files hold, folder by folder and kind by kind: an Undo
    /// of "for the Mac too" keeps the part's folder and changes what it holds.
    static func match(_ listed: [LampProject], filesOf wish: URL) -> Bool {
        let found = folders(in: wish).map { "\($0) \(kindOfScaffold(in: wish.appendingPathComponent($0), wish: wish).map(\.rawValue) ?? "")" }
        return found.sorted() == listed.map { "\($0.dir.lastPathComponent) \($0.platform.rawValue)" }.sorted()
    }

    /// A wish's other parts (`partFolders`), each with what its own meta.json keeps of where it opens. Who a part is
    /// comes from its wish and its folder, never from that file, which the agent could make name another app; and a
    /// part whose file is gone (its folder brought back by a restore, which keeps no `.lamp`) is still the part.
    static func load(_ wish: LampProject) -> [LampProject] {
        guard !wish.isPart else { return [] }
        return wish.partFolders.compactMap { folder -> LampProject? in
            let dir = wish.dir.appendingPathComponent(folder)
            guard let kind = kindOfScaffold(in: dir, wish: wish.dir), partKinds.contains(kind) else { return nil }
            let meta = AppFile.read(dir.appendingPathComponent(".lamp/meta.json"), in: wish)
                .flatMap { try? JSONDecoder().decode(ProjectMeta.self, from: $0) }
                .flatMap { $0.platform == kind ? $0 : nil }
            var part = LampProject(id: id(wish: wish.id, folder: folder), name: wish.name, exe: meta?.exe ?? wish.exe, dir: dir,
                                   instance: instance(wish: wish, folder: folder),
                                   platform: kind, family: meta?.family ?? .iphone,
                                   device: meta?.device, chosen: meta?.target ?? .mac, simulator: meta?.simulator, partOf: wish.id)
            // A game's or a screen's places are its own, kept in its meta.json, and its Xbox follows from them.
            if kind.addsPlaces {
                part.places = meta?.places
                part.engine = meta?.engine
                part.integration = GameKit.integration(for: part)
            }
            // A device's app is for the integration its code was written for, which its marker keeps with the code.
            if kind.reaches(.device), !kind.addsPlaces { part.integration = kind.target.recipe.integration(dir) ?? meta?.integration }
            return part
        }
    }

    /// A part family, or for a kind that's no part the kind itself: how an app's code is built and which kinds it can be
    /// changed into in place. It isn't which app of a wish it is: two devices' apps are one family and two apps (`key`).
    static func group(_ kind: Platform) -> String { kind.target.part?.family ?? kind.rawValue }

    /// Which app of a wish an entry of its list or a made app is: its code (`AppKinds.code`), so a Roku's app and an
    /// Xbox's are two apps of the wish, and an iPhone app made for the Mac too is still the one it was.
    static func key(of app: WishApp) -> String { AppKinds.code(of: app.kind, integration: app.integration) }
    static func key(of app: LampProject) -> String { AppKinds.code(of: app.platform, integration: listedIntegration(of: app)) }

    /// Whether a list entry is this app: of its code. A device's app listed with no integration, by a Lamp from before
    /// the list kept it, is whichever device's app the wish has, as it was then; a made app with no integration is never
    /// another device's.
    static func lists(_ entry: WishApp, _ kind: Platform, integration: String?) -> Bool {
        if key(of: entry) == AppKinds.code(of: kind, integration: integration) { return true }
        return entry.kind == .device && entry.integration == nil && kind == .device
    }
    static func lists(_ entry: WishApp, _ app: LampProject) -> Bool { lists(entry, app.platform, integration: listedIntegration(of: app)) }

    /// The part of a wish (or the wish itself) a device word names: "iphone" is whichever has an iPhone, "mac" whichever
    /// runs on the Mac. Nil when none does, and the first when several do (`picks` has them all).
    static func pick(_ word: String, among apps: [LampProject]) -> LampProject? { picks(word, among: apps).first }

    /// Every app a word could mean, so a word that fits several ("device" beside a Roku's app and an Xbox's) is asked
    /// about rather than read as the first. An app's own word or folder comes first: beside a Mac app, a game also runs on
    /// the Mac, and "mac" is the Mac app; a device's app by its device or its folder ("roku") before its kind's word.
    static func picks(_ word: String, among apps: [LampProject]) -> [LampProject] {
        let word = word.trimmingCharacters(in: .whitespaces).lowercased()
        let own = apps.filter { $0.isPart && $0.dir.lastPathComponent.lowercased() == word
                                // A device's app by its device: "roku", wherever it is.
                                || listedIntegration(of: $0).map { DeviceApps.split($0).integration == word || folder(for: .device, integration: $0).lowercased() == word } == true }
        if !own.isEmpty { return own }
        let named = apps.filter { Parts.word(for: $0.platform) == word || folder(for: $0.platform).lowercased() == word }
        if !named.isEmpty { return named }
        let runsThere = { (app: LampProject) in
            switch word {
            case "mac": app.hasMac
            case "iphone", "ipad", "phone", "watch": app.hasIOS
            default: false
            }
        }
        // An app made for the device before a game or a screen that's also been put there (an app for both and a game).
        return [apps.first { runsThere($0) && !$0.platform.addsPlaces } ?? apps.first(where: runsThere)].compactMap { $0 }
    }

    // MARK: The apps a wish should have

    /// The apps a wish should have (`LampProject.apps`), as they are: the list its meta.json keeps, with what's made
    /// (the app in its own folder, each other found in its folder: `made`) taken as made whatever the list said, and listed when the
    /// list left it out (a wish from before wishes kept the list). An app made as another kind of the same code (the
    /// iPhone app that became one for both) counts as made; each device's app is its own entry.
    static func wanted(in wish: LampProject, parts: [LampProject]) -> [WishApp] {
        var apps = wish.apps
        for made in madeApps(in: wish, parts: parts) {
            apps = setting(WishApp(kind: made.platform, integration: listedIntegration(of: made)), in: apps)
        }
        return apps
    }

    /// The kinds a wish has made: the app in its own folder while it holds one, and each other found in its folder.
    static func made(in wish: LampProject, parts: [LampProject]) -> [Platform] { madeApps(in: wish, parts: parts).map(\.platform) }

    static func madeApps(in wish: LampProject, parts: [LampProject]) -> [LampProject] { (wish.holdsApp ? [wish] : []) + parts }

    /// The integration an app keeps on the wish's list: a device's app's, which names its folder. A game's Xbox is one of
    /// its places, not what it is.
    static func listedIntegration(of app: LampProject) -> String? {
        app.platform.reaches(.device) && !app.platform.addsPlaces ? app.integration : nil
    }

    /// The apps a wish should have and doesn't yet: each with what stops it (`needs`), or nothing when it's only not
    /// made yet (its turn hasn't started, or what stopped it was cleared for another try).
    static func waiting(in wish: LampProject, parts: [LampProject]) -> [WishApp] {
        let made = madeApps(in: wish, parts: parts)
        return wish.apps.filter { entry in !made.contains { lists(entry, $0) } }
    }

    /// The list once a part of this kind is made: every app the wish has, the one in its own folder included (a wish from
    /// before the list has none written), with this one in place of the entry of its code.
    static func listing(_ kind: Platform, integration: String? = nil, madeFor wish: LampProject, parts: [LampProject]) -> [WishApp] {
        setting(WishApp(kind: kind, integration: integration), in: wanted(in: wish, parts: parts))
    }

    /// The list with one app set: in place of the entry of its code (or one a Lamp from before kept for it, `lists`), or
    /// added beside the others.
    static func setting(_ app: WishApp, in apps: [WishApp]) -> [WishApp] {
        var apps = apps
        if let index = apps.firstIndex(where: { key(of: $0) == key(of: app) })
            ?? apps.firstIndex(where: { lists($0, app.kind, integration: app.integration) }) { apps[index] = app } else { apps.append(app) }
        return apps
    }

    /// The request a wish's chat sends once the setup an app was waiting for is done, as the person would ask.
    static func request(for kind: Platform) -> String { "Add \(name(of: kind)) that goes with it now." }

    /// The line at the end of a request about the apps the wish should have and doesn't yet, so the agent tells the
    /// person rather than making them itself (Lamp makes each once this Mac can build it). Nothing when none wait.
    static func waitingLine(for wish: LampProject, parts: [LampProject]) -> String {
        let waiting = waiting(in: wish, parts: parts)
        guard !waiting.isEmpty else { return "" }
        return waiting.map { app in
            "- \(name(of: app)): " + (app.needs.map { "not made yet, since \($0.prefix(1).lowercased() + $0.dropFirst())" }
                                             ?? "Lamp makes it as soon as it can.")
        }.joined(separator: "\n")
    }

    // MARK: What the agent is told

    /// The skill holding a kind's rules for a part of that kind.
    static func skill(for kind: Platform) -> String { "target-" + folder(for: kind).lowercased() }

    /// The skill holding one app's rules: its kind's, and a device's app its own, by its folder ("target-device-roku"),
    /// since a wish can have apps for several devices, each with its device's rules.
    static func skill(of app: LampProject) -> String {
        guard app.isPart, app.platform.target.part?.folderFor != nil else { return skill(for: app.platform) }
        return skill(for: app.platform) + "-" + app.dir.lastPathComponent.lowercased()
    }

    /// Every kind a part can be, each with its rules as a skill (`Skills.read` answers from these).
    static var partKinds: [Platform] { Targets.all.filter { $0.part != nil }.map(\.platform) }

    /// The rules for a part of each kind, as skills: the kind's own rules, for the files in its folder, without the
    /// ones about the wish as a whole, which the wish's prompt has. Made when asked, since some follow Lamp's settings.
    /// A part the wish has (`parts`) is told of its own folder: an iPhone app made for the Mac too stays in iPhone/,
    /// not in the Apple/ an app for both is added in.
    static func packs(for parts: [LampProject] = []) -> [String: Skills.Skill] {
        var skills: [String: Skills.Skill] = [:]
        func add(_ skill: String, _ kind: Platform, _ part: LampProject?) {
            let folder = part?.dir.lastPathComponent ?? folder(for: kind)
            skills[skill] = Skills.Skill(name: skill, description: "The rules for \(part.map { name(of: $0) } ?? name(of: kind)) of a wish, in \(folder)/: how it's written, built, tried and how it talks to the rest.",
                                        body: pack(for: kind, in: folder, integration: part.flatMap(listedIntegration(of:))))
        }
        for kind in partKinds {
            let skill = skill(for: kind)
            let mine = parts.filter { $0.platform == kind }
            // Each device's app has its own skill; the kind's is that app's while it's the only one, as a conversation
            // from before may still ask for it, and says which is whose once there are several.
            for part in mine where self.skill(of: part) != skill { add(self.skill(of: part), kind, part) }
            if mine.count > 1, mine.allSatisfy({ self.skill(of: $0) != skill }) {
                let each = mine.map { "\(name(of: $0)) in \($0.dir.lastPathComponent)/: the \(self.skill(of: $0)) skill" }
                skills[skill] = Skills.Skill(name: skill, description: "Which skill has the rules for each of the wish's \(mine.count) apps of this kind.",
                                            body: "This wish has \(mine.count) apps of this kind, each with rules of its own: " + each.joined(separator: "; ")
                                                + ". Open the one for the app you're changing.")
            } else {
                add(skill, kind, mine.first)
            }
        }
        return skills
    }

    /// `integration`: a device's app's, read off its folder's marker, so its rules are its device's even when the
    /// folder's name no longer says which (an integration renamed since).
    static func pack(for kind: Platform, in folder: String? = nil, alone: Bool = false, integration: String? = nil) -> String {
        let folder = folder ?? self.folder(for: kind, integration: integration)
        if let integration, kind.reaches(.device), !kind.addsPlaces { return Agent.devicePrompt(part: folder, alone: alone, integration: integration) }
        return kind.target.part?.rules(folder, alone) ?? ""
    }

    /// The rule the wish's prompt gets when it's more than one app: what each is, where, how to reach each with the tools,
    /// and to open the rules of each in a folder of its own before changing it. The app in the wish's own folder, while
    /// it holds one (`LampProject.holdsApp`), is the one the prompt's own rules are for.
    static func rule(for wish: LampProject, parts: [LampProject]) -> String {
        // A wish that asks for apps it doesn't have yet is told how they'll share data from its first request, since its
        // first app is written to talk to them (`Template.talksToOtherApps`).
        let apps = (wish.holdsApp ? [wish] : []) + parts
        guard apps.count > 1 else { return Template.talksToOtherApps(wish) ? Agent.Rules.wishTalk : "" }
        let listed = apps.map { app in
            app.isPart ? "\(name(of: app)) in \(app.dir.lastPathComponent)/ (part \"\(word(of: app))\", its rules in the \(skill(of: app)) skill)"
                : "\(name(of: app)) in the wish's own folder (part \"\(word(of: app))\", the rules above)"
        }
        return """

        - This wish is \(apps.count) apps: \(listed.joined(separator: ", and ")). Each is an app of its own kind with its own \
        build files, made to work with the others, and each is the person's: none comes first, and any of them can be \
        added or changed (`make_app_for`) or taken away (`remove_app`) when the person asks. Before you write or change one in a folder of \
        its own, open its rules with `read_skill` (once per conversation) and follow them for the files in its folder. \
        `look_at_app` and `use_app` take `part` to say which app: look at each one you changed before finishing.
        """ + (Set(apps.map(\.platform).filter(WishRooms.joins).map(group)).count >= 2 ? Agent.Rules.wishTalk : "") + Targets.all.flatMap { kind in
            // A rule naming its device is said for each device's app; any other once for its kind.
            let rules = apps.filter { $0.platform == kind.platform }.compactMap { app in kind.part?.wishRule.map { deviceNamed($0, for: app) } }
            return rules.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        }.joined()
    }
}

extension Parts {
    /// A rule written for a device's app ({{DEVICE}}) with the app's device in it: "the Roku app".
    static func deviceNamed(_ rule: String, for app: LampProject) -> String {
        guard let device = listedIntegration(of: app).flatMap(Integrations.integration(_:))?.name else { return rule }
        return rule.replacingOccurrences(of: "{{A_DEVICE}}", with: "a " + device).replacingOccurrences(of: "{{DEVICE}}", with: device)
    }
}

extension Agent.Rules {
    /// The first lines of a part's rules (`Parts.pack`), in place of its kind's header.
    static func partHeader(_ kind: String, folder: String) -> String {
        """
        These are the rules for the part of the wish in \(folder)/: \(kind). Everything they say about "the app" is \
        about that part, and every path in them is inside \(folder)/ (its Sources/, its APP.md, its .lamp/runtime/). \
        Lamp writes its build files as it does for every app. The rules you were given first still hold for the wish as a \
        whole: how to ask, talk, use the shell and finish.
        """
    }

    /// How a Swift part reaches the wish's other apps (`wishTalk`), and, when it fits, its TV app's game as a player of
    /// `Lamp.controllers` through `LampController`: one way the agent may choose, not a rule.
    static func partTalk(mac: Bool) -> String {
        wishTalk + """

        - When the wish has a TV app and this app steers it, choose what fits: plain `LampWish` messages do for a few \
        commands (a slideshow's next and back, a remote), and `LampController` from LampSupport.swift is one way \
        suited to game-style input (buttons held and let go, sticks, several players), which the TV app takes in \
        `Lamp.controllers`: `let pad = LampController.connect()` joins the TV app as a player, as a phone's page would, over the home \
        Wi‑Fi, with nothing to pair or set up: it goes the way `LampWish` reaches the TV app, so it goes on with Lamp \
        closed. \
        `pad.press("next")` taps a button, `pad.button("fire", down: true)` and `down: false` hold and let go, \
        `pad.axis("stick", x: 0.5, y: 0)` moves a stick (-1 to 1), and `pad.send(["volume": 4])` sends JSON of \
        16 KB at most; the TV app hears them in `Lamp.controllers`' onButton, onAxis and onMessage. Anything bigger \
        (a photo, a game, a song) goes with `pad.sendFile(data, name: "game.nes")`, up to 64 MB, which the TV app \
        gets in onFile; the transfer it returns is observable (`sent`, `progress`, `state`) and has `cancel()`, so \
        show its progress. `pad.onMessage { data in … }` and `pad.onFile { file in … }` hear what the TV app sends \
        back. `pad` is observable: show `pad.state` plainly (`.waiting` means the TV app isn't open: "Open it on the \
        TV"), and keep every control usable while it connects. \(mac ? "" : "In the simulator it reaches the TV preview on this Mac.")
        """
    }
}

extension Agent {
    /// The prompt of a new wish, with nothing made for it yet (`undecided`): no kind's rules, only what it takes to choose
    /// what it is and where it runs, which is the agent's to decide, asking only when the answer changes what's made.
    /// `devices` are the ones the request names (the naming call's, in the table's words). `make_app_for`'s answer then
    /// carries the rules of the app it made (`Store.convert`), and the next request starts a conversation with that
    /// kind's prompt (`Store.decided`).
    static func undecidedPrompt(candidates devices: [String]) -> String {
        let named = devices.compactMap { Places.named($0) }.map(\.name)
        return """
        You are Lamp's builder agent. The current directory is a new wish with nothing made for it yet. Before anything         is written, you decide what it is and where it runs, and give it its first app with `make_app_for`: the devices         the app is to be on, and whether it's made as a web page or as each device's own native code.         \(named.isEmpty ? "The request names no device." : "The request names: \(named.joined(separator: ", ")).")

        Rules:
        - Choose from the request and from what each device can run (the table in `make_app_for`'s description, and the         person's own devices Lamp knows of, below the request). Think about who will use it, on whose devices, how many,         which one matters most, and how the app gets onto each: a native app looks and does more, but each phone has to         be set up with this Mac, while a web app reaches the devices that run one the way the table says. Most wishes         that name nothing are for this Mac, made natively.
        - Ask with `ask` only when the answer really changes what you make, in one short question about people and         devices ("Just your phone, or your family's too?"), never "web or native". Nothing else in the card, and change         no files until it's answered. When it's clear, call `make_app_for` straight away.
        - A wish can be more than one app, made to work together (an iPhone app and its TV app): give the first with         `make_app_for`, then each other one the same way.
        - `make_app_for`'s reply carries the rules for the app it made, which take the place of these: follow them and         build the wish in the same request.
        """ + Rules.audience + Rules.begin
    }
}

extension Parts {
    /// What `make_app_for` would have said about an app Lamp made from the wish's list as a request began
    /// (`Store.makeWaitingParts`: its watch app, a game's places, its rules), with the app it's about.
    struct Made: Codable, Equatable {
        /// The app as it was made: who it is and what it was made for, never where Try On opens it (its family or the
        /// person's phone), which the person changes freely and which changes nothing the note says.
        struct App: Codable, Hashable {
            let id: String, folder: String?, instance: String, platform: Platform
            let places: [Destination]?, integration: String?

            init(_ app: LampProject) {
                id = app.id
                folder = app.isPart ? app.dir.lastPathComponent : nil
                instance = app.instance
                platform = app.platform
                places = app.places
                integration = app.integration
            }
        }

        let app: App
        let said: [String]
    }

    private static func madeURL(_ wish: LampProject) -> URL { wish.dir.appendingPathComponent(".lamp/made-notes.json") }

    private static func made(in wish: LampProject) -> [Made] {
        AppFile.read(madeURL(wish), in: wish).flatMap { try? JSONDecoder().decode([Made].self, from: $0) } ?? []
    }

    private static func keep(_ notes: [Made], for wish: LampProject) {
        guard !notes.isEmpty, let data = try? JSONEncoder().encode(notes) else { return AppFolder.remove(madeURL(wish), in: wish.dir) }
        try? AppFolder.write(data, to: madeURL(wish), in: wish.dir)
    }

    /// Kept, in place of an earlier note about the same app, so it reaches the agent however many requests it takes.
    static func rememberMade(_ said: [String], about app: LampProject, in wish: LampProject) {
        guard !said.isEmpty else { return }
        keep(made(in: wish).filter { $0.app.id != app.id } + [Made(app: Made.App(app), said: said)], for: wish)
    }

    /// The notes about apps made from the list that the agent hasn't had yet, each only while its app is one of the
    /// wish's (`apps`) as it was made: gone with a version restored without it, or made for something else since, the
    /// note no longer holds. They stay until a request with them reaches the agent (`forgetMade`), as the note about
    /// going back does; `sent` is which went, so only those count as told.
    static func madeNote(for wish: LampProject, apps: [LampProject]) -> (text: String, sent: [Made]) {
        let present = Set(apps.map(Made.App.init))
        let sent = made(in: wish).filter { present.contains($0.app) }
        guard !sent.isEmpty else { return ("", []) }
        return ("\n\n---\nApps this wish was waiting for that Lamp has made (from Lamp, not part of the request above):\n\n"
                + sent.flatMap(\.said).joined(separator: "\n\n"), sent)
    }

    /// The notes a request carried, once it reached the agent.
    static func forgetMade(_ sent: [Made], for wish: LampProject) {
        guard !sent.isEmpty else { return }
        keep(made(in: wish).filter { !sent.contains($0) }, for: wish)
    }

    /// The note about `app`, which `make_app_for` has just told the agent about afresh.
    static func forgetMade(about app: LampProject, in wish: LampProject) {
        keep(made(in: wish).filter { $0.app.id != app.id }, for: wish)
    }

    /// The line at the end of a request about the apps the wish should have and doesn't yet, sent as `Skills.brief` is:
    /// once per conversation and again when it changes. Nothing while none wait.
    @MainActor static func brief(for project: LampProject, engine: Engine, session: String?) -> String {
        let line = waitingLine(for: project, parts: Store.shared.parts(of: project))
        guard note.telling(line, for: project, engine: engine, session: session) != .nothing, !line.isEmpty else { return "" }
        return "\n\n---\nApps this wish should have and doesn't yet (from Lamp, not part of the request above). Don't make them " +
            "yourself: Lamp makes each as soon as this Mac can build it, and the person has its setup a click away in the chat. " +
            "Build the rest, and say in a sentence what's waiting if the person asks about it:\n" + line
    }

    /// The agent answered, so the request and the line in it arrived.
    @MainActor static func delivered(to project: LampProject, session: String? = nil) { note.delivered(to: project, session: session) }

    /// The engine summed up its conversation, and the line may have gone with it.
    @MainActor static func compacted(_ project: LampProject) { note.compacted(project) }

    @MainActor private static let note = RequestNote(file: ".lamp/apps-shown.json")
}
