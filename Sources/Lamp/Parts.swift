import Foundation

/// A wish made of more than one app: a TV app with an iPhone app that controls it, say. Its main part is the app at its
/// root, as every wish has; each other part is an app of its own kind in a folder of the wish's (`iPhone/`, `Mac/`,
/// `TV/`), with its own `.lamp/meta.json`, build files, bundle id and runtime folder, so it's built, opened, looked at
/// and used exactly as an app of that kind is. What a part doesn't have of its own is the wish's: the chat and its
/// turns, the versions (one history for the whole folder), the icon and the name. Lamp keeps a part in
/// `Store.projects` beside its wish (`LampProject.partOf`), never on the desk.
///
/// What the agent knows follows the parts: the wish's prompt is its main kind's, with one rule naming the other parts,
/// and each other part's rules are a skill of their own (`target-iphone`, …, `Parts.packs`), named with the request
/// once the wish has that part (`Skills.applying`), so a conversation reads a kind's rules only when its wish has one.
enum Parts {
    /// The folder a part of this kind lives in, inside the wish's.
    static func folder(for kind: Platform) -> String { kind.target.part?.folder ?? kind.rawValue.prefix(1).uppercased() + kind.rawValue.dropFirst() }

    /// A part's id: its wish's, then its folder. Lamp's own ids are folder names, which never hold a dot, so no wish's
    /// id is ever a part's.
    static func id(wish: String, folder: String) -> String { wish + "." + folder.lowercased() }
    /// A part's instance: its wish's, kept through renames, then its folder.
    static func instance(wish: LampProject, folder: String) -> String { (wish.instance.isEmpty ? wish.id : wish.instance) + "." + folder }

    /// Every folder a part can be in.
    static var folders: Set<String> { Set(partKinds.map(folder(for:))) }

    /// Where Lamp keeps its wishes (`Store.root`): a part's folder is always one of `folders`, inside a wish's folder here.
    static let appsRoot = Edition.supportFolder.appendingPathComponent("Apps")

    /// The word for a part in `look_at_app` and `use_app`'s `part`, and in what Lamp tells the agent.
    static func word(for kind: Platform) -> String { kind.target.part?.word ?? kind.rawValue }

    /// What a part is, in the agent's words: "the iPhone app".
    static func name(of kind: Platform) -> String { kind.target.identity.name }

    /// The folders of a wish's other parts, found in its folder: one of Lamp's own part folders holding the scaffold of
    /// a kind that folder can hold (any kind of the same code: any of Apple's kinds in an Apple folder, since a part made
    /// for more devices is changed in place and keeps its folder; a TV app in TV/), at most one of each code. They're
    /// found from what the wish's versions keep (the scaffold), never from a list kept beside them, so a rename, an Undo
    /// or a restored version can't leave the two telling different stories: a part comes and goes with its files.
    static func folders(in wish: URL) -> [String] {
        var found: [String] = [], families: Set<String> = []
        for part in Targets.all.compactMap(\.part) {
            guard let kind = kindOfScaffold(in: wish.appendingPathComponent(part.folder), wish: wish),
                  kind.target.part?.family == part.family, families.insert(part.family).inserted else { continue }
            found.append(part.folder)
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
        return wish.partFolders.compactMap { folder in
            let dir = wish.dir.appendingPathComponent(folder)
            guard let kind = kindOfScaffold(in: dir, wish: wish.dir), partKinds.contains(kind) else { return nil }
            let meta = AppFile.read(dir.appendingPathComponent(".lamp/meta.json"), in: wish)
                .flatMap { try? JSONDecoder().decode(ProjectMeta.self, from: $0) }
                .flatMap { $0.platform == kind ? $0 : nil }
            return LampProject(id: id(wish: wish.id, folder: folder), name: wish.name, exe: meta?.exe ?? wish.exe, dir: dir,
                               instance: instance(wish: wish, folder: folder),
                               platform: kind, family: meta?.family ?? .iphone,
                               device: meta?.device, chosen: meta?.target ?? .mac, simulator: meta?.simulator, partOf: wish.id)
        }
    }

    /// The kinds a wish for these devices is made of: one main kind, and the others beside it as parts. The devices of
    /// one part family are one kind between them (Apple's: `Platform(devices:)`); a TV app is a kind of its own. The kind
    /// that leads a wish is the main one (a TV app: what's on the TV is what the wish is about and the rest reach it). An
    /// Android app, and a device with an integration that declares its apps, still stand alone (`Target.Words.alone`).
    /// Nil for a list Lamp can't make.
    static func kinds(for devices: Set<String>) -> (main: Platform, parts: [Platform])? {
        if let one = Platform(devices: devices) { return (one, []) }
        var byFamily: [String: Set<String>] = [:]
        for word in devices {
            guard let owner = Targets.owner(of: word) else { return nil }
            byFamily[owner.part?.family ?? owner.platform.rawValue, default: []].insert(word)
        }
        let kinds = byFamily.values.map { Platform(devices: $0) }
        guard kinds.count > 1, !kinds.contains(nil) else { return nil }
        let all = Targets.all.map(\.platform).filter { kinds.contains($0) }
        let leading = all.filter { $0.target.identity.devices.leads }
        guard all.allSatisfy({ !$0.target.identity.devices.alone }), leading.count == 1, let main = leading.first else { return nil }
        return (main, all.filter { $0 != main })
    }

    /// The part of a wish (or the wish itself) a device word names: "iphone" is whichever has an iPhone, "mac" whichever
    /// runs on the Mac. Nil when none does.
    static func pick(_ word: String, among apps: [LampProject]) -> LampProject? {
        let word = word.trimmingCharacters(in: .whitespaces).lowercased()
        return apps.first { app in
            switch word {
            case "mac": app.platform.hasMac
            case "iphone", "ipad", "phone", "watch": app.platform.hasIOS
            default: Parts.word(for: app.platform) == word || folder(for: app.platform).lowercased() == word
            }
        }
    }

    // MARK: What the agent is told

    /// The skill holding a kind's rules for a part of that kind.
    static func skill(for kind: Platform) -> String { "target-" + folder(for: kind).lowercased() }

    /// Every kind a part can be, each with its rules as a skill (`Skills.read` answers from these).
    static var partKinds: [Platform] { Targets.all.filter { $0.part != nil }.map(\.platform) }

    /// The rules for a part of each kind, as skills: the kind's own rules, for the files in its folder, without the
    /// ones about the wish as a whole, which the wish's prompt has. Made when asked, since some follow Lamp's settings.
    static var packs: [String: Skills.Skill] {
        var skills: [String: Skills.Skill] = [:]
        for kind in partKinds {
            let skill = skill(for: kind)
            skills[skill] = Skills.Skill(name: skill, description: "The rules for \(name(of: kind)) of a wish that has one beside its main app, in \(folder(for: kind))/: how it's written, built, tried and how it talks to the rest.",
                                        body: pack(for: kind))
        }
        return skills
    }

    static func pack(for kind: Platform) -> String { kind.target.part?.rules(folder(for: kind)) ?? "" }

    /// The rule the wish's own prompt gets when it has other parts: what they are, where, how to reach each with the
    /// tools, and to open each one's rules before changing it.
    static func rule(for wish: LampProject, parts: [LampProject]) -> String {
        guard !parts.isEmpty else { return "" }
        let listed = parts.map { "\(name(of: $0.platform)) in \($0.dir.lastPathComponent)/ (part \"\(word(for: $0.platform))\", its rules in the \(skill(for: $0.platform)) skill)" }
        return """

        - This wish is more than one app: \(name(of: wish.platform)), at the root as the rules above describe, and \
        \(listed.joined(separator: ", and ")). Each is an app of its own kind with its own build files, made to work \
        with the others, and each is the person's: build them together. Before you write or change one of them, open \
        its rules with `read_skill` (once per conversation) and follow them for the files in its folder; the rules \
        above are for the app at the root. `look_at_app` and `use_app` reach another part with `part` (left out, \
        they're for the app at the root): look at each part you changed before finishing.
        """ + Targets.all.filter { kind in ([wish] + parts).contains { $0.platform == kind.platform } }.compactMap(\.part?.wishRule).joined()
    }
}

extension Agent.Rules {
    /// The first lines of a part's rules (`Parts.pack`), in place of its kind's header.
    static func partHeader(_ kind: String, folder: String) -> String {
        """
        These are the rules for the part of the wish in \(folder)/: \(kind). Everything they say about "the app" is \
        about that part, and every path in them is inside \(folder)/ (its Sources/, its APP.md, its .lamp/runtime/). \
        Lamp writes its build files as it does at the root. The rules you were given first still hold for the wish as a \
        whole: how to ask, talk, use the shell and finish.
        """
    }

    /// How a Swift part reaches the wish's TV app: as a player of its `Lamp.controllers`, through `LampController`.
    static func partTalk(mac: Bool) -> String {
        """

        - When the wish has a TV app, this app talks to it with `LampController` from LampSupport.swift: \
        `let pad = LampController.connect()` joins the TV app as a player, as a phone's page would, over the home \
        Wi‑Fi, with nothing to pair or set up\(mac ? "" : ": the TV app connects straight to the phone, and Lamp on the Mac only introduces them"). \
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
    /// The prompt of a new wish that could be for more than one kind of device and didn't say which (`undecided`):
    /// no kind's rules yet, only what it takes to ask and to give the wish its kinds. `make_app_for`'s answer then
    /// carries the rules of every kind it was given (`Store.convert`), and the next request starts a conversation
    /// with that kind's prompt (`Store.decided`).
    static func undecidedPrompt(candidates: [String]) -> String {
        let named = candidates.compactMap(Parts.device).joined(separator: ", or ")
        return """
        You are Lamp's builder agent. The current directory is a new wish with nothing made for it yet. Lamp makes apps \
        \(Targets.lampMakes), and one wish can be more than \
        one of them, made to work together: a TV app with an iPhone app that controls it, a Mac app with its TV app. \
        This wish could be \(named.isEmpty ? "for more than one of them" : named), and it didn't say which, so nothing \
        is written until it's known.

        Rules:
        - Ask first, with `ask`: one question, in the person's words for their wish, whose answers are those devices \
        one by one and, when the wish could be on both, both together ("TV, Mac or both?"), the likeliest first. \
        Nothing else in the card, and change no files.
        - When the answer comes, call `make_app_for` with every device it chose (both of them for "both"); left to you, \
        take the first answer. If the person has said where it runs since, skip the question and call it straight \
        away. Its reply carries the rules for each kind, which take the place of these: follow them and build the wish \
        in the same request.
        """ + Rules.audience + Rules.begin
    }
}

extension Parts {
    /// A device the naming call or the agent names, in the words the undecided prompt says it with.
    static func device(_ word: String) -> String? {
        Targets.asked(word.lowercased())
    }
}
