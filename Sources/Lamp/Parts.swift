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
}

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

    /// The folder an app the wish asks for and doesn't have yet will be made in (`Store.addPart`): the one a shared file
    /// had it in, for one whose files are kept for it, else the one its kind gets. It's that app's name among the wish's
    /// apps from the start (`WishRooms.peer`), so what the others say to it while it waits still reaches it once made.
    static func folder(waiting kind: Platform, in wish: URL) -> String {
        Sharing.keptFolder(in: wish, for: kind) ?? folder(for: kind)
    }

    /// Whether an app of this kind can be in this folder: one of Lamp's part folders for the kind's family, as an app
    /// changed in place within its family keeps the folder it was made in (an iPhone app made for the Mac too, in iPhone/).
    static func folder(_ folder: String, canHold kind: Platform) -> Bool {
        Targets.all.contains { $0.part?.folder == folder && $0.part?.family == kind.target.part?.family }
    }

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

    /// The kinds a wish for these devices is made of, in Lamp's order: the devices of one part family are one kind between
    /// them (Apple's: `Platform(devices:)`); a TV app and an Android app are each a kind of their own. No kind leads:
    /// what a wish does with the list is `plan`. A device with an
    /// integration that declares its apps still stands alone (`Target.Words.alone`). Nil for a list Lamp can't make.
    static func kinds(for devices: Set<String>) -> [Platform]? {
        if let one = Platform(devices: devices) { return [one] }
        var byFamily: [String: Set<String>] = [:]
        for word in devices {
            guard let owner = Targets.owner(of: word) else { return nil }
            byFamily[group(owner.platform), default: []].insert(word)
        }
        let kinds = byFamily.values.map { Platform(devices: $0) }
        guard kinds.count > 1, !kinds.contains(nil) else { return nil }
        let all = Targets.all.map(\.platform).filter { kinds.contains($0) }
        guard all.allSatisfy({ !$0.target.identity.devices.alone && $0.target.part != nil }) else { return nil }
        return all
    }

    /// What `make_app_for` does to a wish's apps (`apps`, as `Store.apps(of:)` has them) for the kinds listed: every app
    /// is treated alike, the one in the wish's own folder as much as any other. An app whose family is listed stays, its
    /// code kept, and is changed in place when listed as another kind of that family (an iPhone app that's to be for the
    /// Mac too); a family listed that the wish has no app of is added, in its own folder; an app whose family is left out
    /// is taken away. So "tv" added to a Mac wish keeps the Mac app and adds the TV app beside it, and "tv" alone for it
    /// replaces the Mac app with the TV app: the wish, its chat and its history stay.
    struct Plan: Equatable {
        /// Apps that stay, by id, each with the kind it's to be (its own, or another of its family).
        var keep: [String: Platform] = [:]
        var add: [Platform] = []
        var remove: [String] = []
    }

    /// Of the apps a plan takes away (`remove`, in order), those that stay for now: none while another app survives
    /// the request (`survivors`: those kept and those just added), else the first, so a wish always has an app.
    static func staying(of remove: [String], survivors: Int) -> [String] {
        survivors > 0 ? [] : Array(remove.prefix(1))
    }

    /// Whether `make_app_for`'s answer for an app that stays says nothing the agent needs: its kind was already right,
    /// with no more to do. One that goes on to say what to do about a watch app (`Store.changeKind`) says something.
    static func saysNothingNew(_ text: String) -> Bool { text.hasPrefix("It's already made for") && !text.contains("\n\n") }

    static func plan(_ kinds: [Platform], for apps: [LampProject]) -> Plan {
        var plan = Plan()
        for app in apps {
            if let wanted = kinds.first(where: { group($0) == group(app.platform) }) { plan.keep[app.id] = wanted }
            else { plan.remove.append(app.id) }
        }
        plan.add = kinds.filter { kind in !apps.contains { group($0.platform) == group(kind) } }
        return plan
    }

    /// What a wish has one of: a part family, or for a kind that's no part the kind itself.
    static func group(_ kind: Platform) -> String { kind.target.part?.family ?? kind.rawValue }

    /// The part of a wish (or the wish itself) a device word names: "iphone" is whichever has an iPhone, "mac" whichever
    /// runs on the Mac. Nil when none does.
    static func pick(_ word: String, among apps: [LampProject]) -> LampProject? {
        let word = word.trimmingCharacters(in: .whitespaces).lowercased()
        return apps.first { app in
            switch word {
            case "mac": app.hasMac
            case "iphone", "ipad", "phone", "watch": app.hasIOS
            default: Parts.word(for: app.platform) == word || folder(for: app.platform).lowercased() == word
            }
        }
    }

    // MARK: The apps a wish should have

    /// The apps a wish should have (`LampProject.apps`), as they are: the list its meta.json keeps, with what's made
    /// (the app in its own folder, each other found in its folder: `made`) taken as made whatever the list said, and listed when the
    /// list left it out (a wish from before wishes kept the list). An app made as another kind of the same family (the
    /// iPhone app that became one for both) counts as made.
    static func wanted(in wish: LampProject, parts: [LampProject]) -> [WishApp] {
        var apps = wish.apps
        for made in made(in: wish, parts: parts) {
            if let index = apps.firstIndex(where: { group($0.kind) == group(made) }) { apps[index] = WishApp(kind: made) }
            else { apps.append(WishApp(kind: made)) }
        }
        return apps
    }

    /// The kinds a wish has made: the app in its own folder while it holds one, and each other found in its folder.
    static func made(in wish: LampProject, parts: [LampProject]) -> [Platform] {
        (wish.holdsApp ? [wish.platform] : []) + parts.map(\.platform)
    }

    /// The apps a wish should have and doesn't yet: each with what stops it (`needs`), or nothing when it's only not
    /// made yet (its turn hasn't started, or what stopped it was cleared for another try).
    static func waiting(in wish: LampProject, parts: [LampProject]) -> [WishApp] {
        let made = Set(made(in: wish, parts: parts).map(group))
        return wish.apps.filter { !made.contains(group($0.kind)) }
    }

    /// The list once a part of this kind is made: every app the wish has, the one in its own folder included (a wish from
    /// before the list has none written), with this one in place of any of its family.
    static func listing(_ kind: Platform, madeFor wish: LampProject, parts: [LampProject]) -> [WishApp] {
        setting(WishApp(kind: kind), in: wanted(in: wish, parts: parts))
    }

    /// The list with one app set: in place of the one of its family, or added.
    static func setting(_ app: WishApp, in apps: [WishApp]) -> [WishApp] {
        var apps = apps
        if let index = apps.firstIndex(where: { group($0.kind) == group(app.kind) }) { apps[index] = app } else { apps.append(app) }
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
            "- \(name(of: app.kind)): " + (app.needs.map { "not made yet, since \($0.prefix(1).lowercased() + $0.dropFirst())" }
                                             ?? "Lamp makes it as soon as it can.")
        }.joined(separator: "\n")
    }

    // MARK: What the agent is told

    /// The skill holding a kind's rules for a part of that kind.
    static func skill(for kind: Platform) -> String { "target-" + folder(for: kind).lowercased() }

    /// Every kind a part can be, each with its rules as a skill (`Skills.read` answers from these).
    static var partKinds: [Platform] { Targets.all.filter { $0.part != nil }.map(\.platform) }

    /// The rules for a part of each kind, as skills: the kind's own rules, for the files in its folder, without the
    /// ones about the wish as a whole, which the wish's prompt has. Made when asked, since some follow Lamp's settings.
    /// A part the wish has (`parts`) is told of its own folder: an iPhone app made for the Mac too stays in iPhone/,
    /// not in the Apple/ an app for both is added in.
    static func packs(for parts: [LampProject] = []) -> [String: Skills.Skill] {
        var skills: [String: Skills.Skill] = [:]
        for kind in partKinds {
            let skill = skill(for: kind)
            let folder = parts.first { $0.platform == kind }?.dir.lastPathComponent ?? folder(for: kind)
            skills[skill] = Skills.Skill(name: skill, description: "The rules for \(name(of: kind)) of a wish, in \(folder)/: how it's written, built, tried and how it talks to the rest.",
                                        body: pack(for: kind, in: folder))
        }
        return skills
    }

    static func pack(for kind: Platform, in folder: String? = nil) -> String { kind.target.part?.rules(folder ?? self.folder(for: kind)) ?? "" }

    /// The rule the wish's prompt gets when it's more than one app: what each is, where, how to reach each with the tools,
    /// and to open the rules of each in a folder of its own before changing it. The app in the wish's own folder, while
    /// it holds one (`LampProject.holdsApp`), is the one the prompt's own rules are for.
    static func rule(for wish: LampProject, parts: [LampProject]) -> String {
        // A wish that asks for apps it doesn't have yet is told how they'll share data from its first request, since its
        // first app is written to talk to them (`Template.talksToOtherApps`).
        let apps = (wish.holdsApp ? [wish] : []) + parts
        guard apps.count > 1 else { return Template.talksToOtherApps(wish) ? Agent.Rules.wishTalk : "" }
        let listed = apps.map { app in
            app.isPart ? "\(name(of: app.platform)) in \(app.dir.lastPathComponent)/ (part \"\(word(for: app.platform))\", its rules in the \(skill(for: app.platform)) skill)"
                : "\(name(of: app.platform)) in the wish's own folder (part \"\(word(for: app.platform))\", the rules above)"
        }
        return """

        - This wish is \(apps.count) apps: \(listed.joined(separator: ", and ")). Each is an app of its own kind with its own \
        build files, made to work with the others, and each is the person's: none comes first, and any of them can be \
        added, replaced or taken away when the person asks (`make_app_for`). Before you write or change one in a folder of \
        its own, open its rules with `read_skill` (once per conversation) and follow them for the files in its folder. \
        `look_at_app` and `use_app` take `part` to say which app: look at each one you changed before finishing.
        """ + Agent.Rules.wishTalk + Targets.all.filter { kind in apps.contains { $0.platform == kind.platform } }.compactMap(\.part?.wishRule).joined()
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
    /// The prompt of a new wish that could be for more than one kind of device and didn't say which (`undecided`):
    /// no kind's rules yet, only what it takes to ask and to give the wish its kinds. `make_app_for`'s answer then
    /// carries the rules of every kind it was given (`Store.convert`), and the next request starts a conversation
    /// with that kind's prompt (`Store.decided`).
    static func undecidedPrompt(candidates: [String]) -> String {
        let named = candidates.compactMap(Parts.device).joined(separator: ", or ")
        return """
        You are Lamp's builder agent. The current directory is a new wish with nothing made for it yet. Lamp makes apps \
        \(Targets.lampMakes), and one wish can be more than \
        one of them, made to work together: a TV app with an iPhone app, a Mac app with its TV app. \
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

extension Parts {
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
