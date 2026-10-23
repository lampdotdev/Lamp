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
    static func folder(for kind: Platform) -> String {
        switch kind {
        case .mac: "Mac"
        case .iphone: "iPhone"
        case .universal: "Apple"
        case .tv: "TV"
        case .android: "Android"
        case .device: "Device"
        }
    }

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
    static func word(for kind: Platform) -> String {
        switch kind {
        case .mac: "mac"
        case .iphone, .universal: "iphone"
        case .tv: "tv"
        case .android: "android"
        case .device: "device"
        }
    }

    /// What a part is, in the agent's words: "the iPhone app".
    static func name(of kind: Platform) -> String {
        switch kind {
        case .mac: "the Mac app"
        case .iphone: "the iPhone app"
        case .universal: "the Mac and iPhone app"
        case .tv: "the TV app"
        case .android: "the Android app"
        case .device: "the device's app"
        }
    }

    /// A wish's other parts, read from their folders: each listed in the wish's meta.json and with a meta.json of its
    /// own. One whose folder is missing or unreadable (taken away by a version restored from before it) is left out.
    /// The meta.json files are in the wish's folder, which the agent writes: a part is only ever one of Lamp's own
    /// folders, holding the kind that folder is for, once.
    static func load(_ wish: LampProject) -> [LampProject] {
        guard !wish.isPart else { return [] }
        var seen: Set<String> = []
        return wish.partFolders.compactMap { folder in
            guard let kind = partKinds.first(where: { Parts.folder(for: $0) == folder }), seen.insert(folder).inserted else { return nil }
            let dir = wish.dir.appendingPathComponent(folder)
            guard let data = AppFile.read(dir.appendingPathComponent(".lamp/meta.json"), in: wish),
                  let meta = try? JSONDecoder().decode(ProjectMeta.self, from: data), meta.platform == kind else { return nil }
            // Who a part is comes from its wish, never from its own meta.json, which the agent could make name another app.
            return LampProject(id: id(wish: wish.id, folder: folder), name: wish.name, exe: meta.exe, dir: dir,
                               instance: instance(wish: wish, folder: folder),
                               platform: meta.platform ?? .mac, integration: meta.integration, family: meta.family ?? .iphone,
                               device: meta.device, chosen: meta.target ?? .mac, simulator: meta.simulator, partOf: wish.id)
        }
    }

    /// The kinds a wish for these devices is made of: one main kind, and the others beside it as parts. Apple's devices
    /// are one kind between them, one code (`Platform(devices:)`); a TV app and an Android app are each a kind of their
    /// own. With a TV among them the TV app is the main one, since what's on the TV is what the wish is about and the
    /// rest reach it. An Android app, and a device with an integration that declares its apps, still stand alone.
    /// Nil for a list Lamp can't make.
    static func kinds(for devices: Set<String>) -> (main: Platform, parts: [Platform])? {
        let apple = devices.intersection(["mac", "iphone", "watch"])
        guard devices.contains("tv"), !apple.isEmpty, devices.subtracting(apple) == ["tv"], let kind = Platform(devices: apple) else {
            return Platform(devices: devices).map { ($0, []) }
        }
        return (.tv, [kind])
    }

    /// The part of a wish (or the wish itself) a device word names: "iphone" is whichever has an iPhone, "mac" whichever
    /// runs on the Mac. Nil when none does.
    static func pick(_ word: String, among apps: [LampProject]) -> LampProject? {
        let word = word.trimmingCharacters(in: .whitespaces).lowercased()
        return apps.first { app in
            switch word {
            case "mac": app.platform.hasMac
            case "iphone", "ipad", "phone", "watch": app.platform.hasIOS
            case "tv": app.platform == .tv
            case "android": app.platform == .android
            default: Parts.word(for: app.platform) == word || folder(for: app.platform).lowercased() == word
            }
        }
    }

    // MARK: What the agent is told

    /// The skill holding a kind's rules for a part of that kind.
    static func skill(for kind: Platform) -> String { "target-" + folder(for: kind).lowercased() }

    /// Every kind a part can be, each with its rules as a skill (`Skills.read` answers from these).
    static let partKinds: [Platform] = [.iphone, .mac, .universal, .tv]

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

    static func pack(for kind: Platform) -> String {
        let folder = folder(for: kind)
        switch kind {
        case .mac: return Agent.prompt(platform: .mac, device: "Mac", sidebar: false, part: folder)
        case .iphone: return Agent.prompt(platform: .iphone, device: DeviceFamily.iphone.name, sidebar: false, part: folder)
        case .universal: return Agent.universalPrompt(for: .iphone, part: folder)
        case .tv: return Agent.tvPrompt(part: folder)
        case .android, .device: return ""
        }
    }

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
        """ + (wish.platform == .tv || parts.contains { $0.platform == .tv } ? Agent.Rules.tvParts : "")
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
        `let pad = LampController.connect()` joins the TV app as a player, as a phone's page would, through Lamp on \
        the person's Mac and the home Wi‑Fi, with nothing to pair or set up. `pad.press("next")` taps a button, \
        `pad.button("fire", down: true)` and `down: false` hold and let go, `pad.axis("stick", x: 0.5, y: 0)` moves \
        a stick (-1 to 1), and `pad.send(["volume": 4])` sends anything small; the TV app hears them in \
        `Lamp.controllers`' onButton, onAxis and onMessage. `pad.onMessage { data in … }` hears what it sends back. \
        `pad` is observable: show `pad.state` plainly (`.waiting` means the TV app isn't open: "Open it on the TV"), \
        and keep every control usable while it connects. \(mac ? "" : "In the simulator it reaches the TV preview on this Mac.")
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
        for this Mac, for iPhone and iPad, for Samsung and LG TVs and for Android phones, and one wish can be more than \
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
        switch word.lowercased() {
        case "mac": "for this Mac"
        case "iphone": "for iPhone and iPad"
        case "tv": "for the TV"
        case "android": "for an Android phone"
        default: nil
        }
    }
}
