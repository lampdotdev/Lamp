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
    /// The folder it's in, or for one still to be made the folder kept for it from the moment it was asked for
    /// (`Parts.newFolder`): who it is, since its id, instance and name among the wish's apps come from it (`Parts.id`).
    /// "." for the app in the wish's own folder. Nil in a list from before the list kept folders, whose entries are
    /// matched to the wish's apps by their code, as that list was (`Parts.lists`).
    var folder: String? = nil
    /// Asked for as a game though made in the devices' own code (a native game), so it's made as one when it's made;
    /// nil for any other.
    var game: Bool? = nil

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

    /// What marks a wish's own folder as only the wish's: its apps, if it has any, are each in a folder of their own, and
    /// the folder itself is never a draft to write an app into (`LampProject.holdsApp`). Kept with the wish's files, so a
    /// version restored from before it was marked brings back what the folder held then.
    static let wishOnly = ".lamp-wish"
    static let wishOnlyText = "A wish made with Lamp: each of its apps is in a folder of its own, and this folder holds none.\n"

    /// Whether a wish's own folder is marked as only the wish's: the mark a plain file, never a link.
    static func isWishOnly(_ dir: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(wishOnly).path))?[.type] as? FileAttributeType == .typeRegular
    }

    /// Every folder a part can be in.
    static var folders: Set<String> { Set(Targets.all.compactMap(\.part).flatMap(\.folders)) }

    /// The folder an app the wish asks for and doesn't have yet will be made in (`Store.addPart`): the one kept for it
    /// when it was asked for (`WishApp.folder`), else (a list from before it kept folders) the one a shared file had it
    /// in, for one whose files are kept for it, or the one its kind gets. It's that app's name among the wish's apps from
    /// the start (`WishRooms.peer`), so what the others say to it while it waits still reaches it once made.
    static func folder(waiting app: WishApp, in wish: URL) -> String {
        if let folder = app.folder, folder != "." { return folder }
        return Sharing.keptFolder(in: wish, for: app.kind) ?? folder(for: app.kind, integration: app.integration)
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
    /// One of several apps of a kind is told apart by what its folder adds to its kind's or device's ("Mac App 2" in
    /// Mac2/, "Roku App 2" in Roku2/), or by its folder when that's another name altogether.
    static func menu(of app: LampProject) -> (name: String, symbol: String) {
        var menu: (name: String, symbol: String) = app.platform.target.part?.menu ?? ("App", "app")
        let device = app.platform.target.part?.folderFor != nil ? DeviceApps.integration(for: app)?.name : nil
        if let device { menu.name = device + " App" }
        guard app.isPart else { return menu }
        let folder = app.dir.lastPathComponent
        let own = device != nil ? self.folder(for: app.platform, integration: listedIntegration(of: app)) : self.folder(for: app.platform)
        // An app in one of Lamp's own folders is named as it always was (an iPhone app made for the Mac too, in iPhone/).
        guard folder != own, !isOwnFolder(folder) else { return menu }
        let rest = folder.hasPrefix(own) ? String(folder.dropFirst(own.count)) : ""
        return (!rest.isEmpty && rest.allSatisfy(\.isNumber) ? menu.name + " " + rest : folder, menu.symbol)
    }

    /// `part` in `look_at_app` and `use_app` for one app of a wish: a device's app goes by its folder ("roku"), since
    /// "device" says nothing of which.
    static func word(of app: LampProject) -> String {
        if app.isPart, app.platform.target.part?.folderFor != nil || app.dir.lastPathComponent != folder(for: app.platform) {
            return app.dir.lastPathComponent.lowercased()
        }
        return listedIntegration(of: app).map { folder(for: app.platform, integration: $0).lowercased() } ?? word(for: app.platform)
    }

    /// The folders of a wish's other apps, found in its folder: each folder directly in it, by any name, that holds the
    /// scaffold of a kind that can be one of a wish's apps, read off the folder's own files (a Mac app in Mac2/ as in
    /// Mac/), as many of a kind as there are. The folder is the app: its id, instance and name among the wish's apps
    /// come from it. They're found from what the wish's versions keep (the scaffold), never from a list kept beside
    /// them, so a rename, an Undo or a restored version can't leave the two telling different stories: a part comes and
    /// goes with its files. A link is never followed, and what's the wish's own (its attachments, the source folders of
    /// the app in its own folder) is never an app's folder. Lamp's own folders come first, in the order its kinds are
    /// listed, then the rest by name.
    static func folders(in wish: URL) -> [String] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: wish.path)) ?? []).filter { name in
            guard !name.hasPrefix("."), !notAppFolders(in: wish).contains(name) else { return false }
            let values = try? wish.appendingPathComponent(name).resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return values?.isDirectory == true && values?.isSymbolicLink != true
        }
        let own = Targets.all.compactMap(\.part).flatMap(\.folders)
        let ordered = own.filter(names.contains) + names.filter { !own.contains($0) }.sorted()
        var found: [String] = []
        for folder in ordered where !found.contains(folder) {
            guard let kind = kindOfScaffold(in: wish.appendingPathComponent(folder), wish: wish), partKinds.contains(kind) else { continue }
            found.append(folder)
        }
        return found
    }

    /// What in a wish's folder is never one of its apps' folders: its attachments, and the folders the code of an app in
    /// the wish's own folder is in (Sources/, Watch/, web/…), which aren't Lamp's part folders.
    private static func notAppFolders(in wish: URL) -> Set<String> {
        let parts = Set(Targets.all.compactMap(\.part).flatMap(\.folders))
        // Each kind's fixed source folders, asked of no folder at all: a kind whose sources are whatever its folder holds
        // (a device's app) names none, so the folders beside its code that hold apps of their own are still those apps'.
        let nowhere = URL(fileURLWithPath: "/var/empty/lamp-no-app")
        let sources = Targets.all.flatMap { kind in kind.recipe.sources(LampProject(id: "", name: "", exe: "", dir: nowhere, platform: kind.platform)) }
            .filter { !parts.contains($0) }
        return Set(sources + [Attachments.folder, "Lamp"])
    }

    /// Whether a name can be a new app's folder: letters and digits only (no dot, space or slash), starting with a letter,
    /// and short, since it's the app's name among the wish's apps (`WishRooms.peer`) and part of its ids.
    static func isFolderName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, CharacterSet.letters.contains(first), name.count <= 32 else { return false }
        return name.unicodeScalars.allSatisfy { $0.isASCII && CharacterSet.alphanumerics.contains($0) }
    }

    /// The folder a new app of the wish is made in: `base` (its kind's, "Mac", or its device's, "Roku"), else the first
    /// of "Mac2", "Mac3"… that no app of the wish has, has had or is still to have, compared whatever the case, as the
    /// Mac's disks and a part's id (`id`) do. A folder that's there already, with an app or anything else in it, is never
    /// given: what's there would be written over. Nor is one an app was taken away from (`RemovedApp`), even for an app
    /// of the same kind: its id, data and devices' copies are that app's, and Undo puts it back there. Nor one kept for an
    /// app still to be made (`apps`), nor `skipping` (a shared wish's other apps on their way in). `base` itself is passed
    /// over while an app in the wish's own folder is, or was, of the same family, since that app is installed under the
    /// wish's name as the one in `base` would be (`LampProject.installedURL`).
    static func newFolder(_ base: String, in wish: LampProject, skipping: [String] = []) -> String {
        let base = isFolderName(base) ? base : "App"
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: wish.dir.path)) ?? []) + notAppFolders(in: wish.dir)
        let removed = RemovedApp.list(in: wish.dir)
        let taken = Set((names + wish.apps.compactMap(\.folder) + removed.compactMap(\.folder) + skipping).map { $0.lowercased() })
        // The app in the wish's own folder, now or taken away, installed where an app in its family's own folder would be.
        let family = Targets.all.first { $0.part?.folders.contains(base) == true }?.part?.family
        let root = Set((wish.hasScaffold ? [group(wish.platform)] : []) + removed.filter { $0.folder == nil }.map { group($0.platform) })
        if !(family.map(root.contains) ?? false), !taken.contains(base.lowercased()) { return base }
        return (2...).lazy.map { base + String($0) }.first { !taken.contains($0.lowercased()) }!
    }

    /// The folder an app still to be made from a list kept before folders were (`WishApp.folder` nil) is made in, and
    /// named by meanwhile: the one its shared files had, kept by an earlier Lamp, else its kind's, where free.
    static func legacySlot(for app: WishApp, in wish: LampProject) -> String {
        newFolder(Sharing.keptFolder(in: wish.dir, for: app.kind) ?? folder(for: app.kind, integration: app.integration), in: wish)
    }

    /// Whether this folder is one Lamp's kinds have always made apps in (Mac/, iPhone/, a device's Roku/): what a Lamp
    /// from before finds, and what an app's installed name doesn't need (`LampProject.installedURL`).
    static func isOwnFolder(_ folder: String) -> Bool { Set(Targets.all.compactMap(\.part).flatMap(\.folders)).contains(folder) }

    /// Whether a Lamp from before this one reads this wish's apps as they are: each in one of its kind's own folders, at
    /// most one of each family, a device's app among them (that Lamp kept one per wish and lists them by family). One
    /// that wouldn't is laid out as `NewerWish.layout` says, so that Lamp leaves it alone rather than taking it for one
    /// app, or a draft to write a new app into.
    static func readByEarlierLamp(_ wish: URL) -> Bool {
        var families: Set<String> = []
        for folder in folders(in: wish) {
            guard let kind = kindOfScaffold(in: wish.appendingPathComponent(folder), wish: wish), let part = kind.target.part,
                  // A web app is a kind such a Lamp doesn't know: it would find no app in its folder.
                  kind != .webApp else { return false }
            guard part.folderFor != nil || self.folder(folder, canHold: kind), families.insert(part.family).inserted else { return false }
        }
        return true
    }

    /// The same for a wish as Lamp holds it: its folders, and also every app on its list, made or still to be made,
    /// since a Lamp from before reads the list by code and would fold two entries of one family into one, or make an
    /// app waiting for Mac2/ in Mac/.
    static func readByEarlierLamp(_ wish: LampProject) -> Bool {
        guard readByEarlierLamp(wish.dir) else { return false }
        // A web app in the wish's own folder is a kind it doesn't know, and a wish with no app at all is one it would take
        // for a draft to write a new app into.
        if wish.holdsApp ? wish.platform == .webApp : folders(in: wish.dir).isEmpty && !wish.isPart { return false }
        var wish = wish
        wish.partFolders = folders(in: wish.dir)
        var families: Set<String> = []
        for app in wanted(in: wish, parts: load(wish)) {
            guard let part = app.kind.target.part else { continue }
            if let folder = app.folder, folder != "." {
                // A made device's app is found by its mark wherever it is; one still to be made, that Lamp makes in its
                // device's own folder, so it must be waiting for that one.
                if part.folderFor == nil, !self.folder(folder, canHold: app.kind) { return false }
                if part.folderFor != nil, !wish.partFolders.contains(folder),
                   folder != self.folder(for: app.kind, integration: app.integration) { return false }
            }
            guard families.insert(part.family).inserted else { return false }
        }
        return true
    }

    /// The app of the wish an app would be the same as if it were made `kind` in place: one with the same name among the
    /// wish's apps (`WishRooms.peer`), or installed in the same place while both are on the Mac. Only the app in the
    /// wish's own folder, or one in a folder of Lamp's own, can come to that, since their names follow their kind: a TV
    /// app in the wish's own folder made a Mac app beside a Mac app in Mac/ would be "mac" and the wish's name twice.
    @MainActor static func clash(changing app: LampProject, to kind: Platform, integration: String?, places: [Destination]?,
                      among apps: [LampProject], in wish: LampProject) -> LampProject? {
        var changed = app
        changed.platform = kind
        changed.integration = kind.reaches(.device) && !kind.addsPlaces ? integration : nil
        changed.places = kind.addsPlaces ? places : nil
        let peer = WishRooms.peer(changed, in: wish)
        // An app still to be made counts as the app it will be, in the folder kept for it.
        let waiting = Parts.waiting(in: wish, parts: apps.filter(\.isPart)).compactMap { entry -> LampProject? in
            let folder = entry.folder ?? self.folder(waiting: entry, in: wish.dir)
            guard folder != "." else { return nil }
            var app = LampProject(id: id(wish: wish.id, folder: folder), name: wish.name, exe: wish.exe, dir: wish.dir.appendingPathComponent(folder),
                                  platform: entry.kind, partOf: wish.id)
            app.places = entry.places
            app.integration = entry.integration
            return app
        }
        let apps = apps + waiting
        return apps.first { other in
            other.id != app.id && (WishRooms.peer(other, in: wish) == peer
                                   || other.hasMac && changed.hasMac && other.installedURL == changed.installedURL)
        }
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

    /// What a wish has one of: a part family, or for a kind that's no part the kind itself.
    static func group(_ kind: Platform) -> String { kind.target.part?.family ?? kind.rawValue }

    /// The part of a wish (or the wish itself) a word names, when it names one: nil when it names none or several
    /// (`picks` has them all, so a word that fits several is asked about, never read as the first).
    static func pick(_ word: String, among apps: [LampProject]) -> LampProject? {
        let found = picks(word, among: apps)
        return found.count == 1 ? found[0] : nil
    }

    /// Every app a word could mean, most particular first, stopping at the first way of naming that names any: an app's
    /// own folder ("mac2", "roku"), whatever its kind, and "." for the app in the wish's own folder; then a device's app
    /// by its device ("roku", wherever it is); then a kind's word or folder ("mac", "game"); then a device an app runs on
    /// ("iphone" is whichever has an iPhone). Beside a Mac app, a game also runs on the Mac, and "mac" is the Mac app.
    static func picks(_ word: String, among apps: [LampProject]) -> [LampProject] {
        let word = word.trimmingCharacters(in: .whitespaces).lowercased()
        let folder = apps.filter { $0.isPart ? $0.dir.lastPathComponent.lowercased() == word : word == "." }
        if !folder.isEmpty { return folder }
        let device = apps.filter { listedIntegration(of: $0).map { DeviceApps.split($0).integration == word } == true }
        if !device.isEmpty { return device }
        let named = apps.filter { Parts.word(for: $0.platform) == word || self.folder(for: $0.platform).lowercased() == word
                                  || listedIntegration(of: $0).map { self.folder(for: .device, integration: $0).lowercased() == word } == true }
        if !named.isEmpty { return named }
        let runsThere = { (app: LampProject) in
            switch word {
            case "mac": app.hasMac
            case "iphone", "ipad", "phone", "watch": app.hasIOS
            default: false
            }
        }
        // An app made for the device before a game or a screen that's also been put there (an app for both and a game).
        let made = apps.filter { runsThere($0) && !$0.platform.addsPlaces }
        return made.isEmpty ? apps.filter(runsThere) : made
    }

    /// The word that names this app alone among the wish's apps in `part`: its own (`word(of:)`) when that names no other,
    /// else its folder, or "." for the one in the wish's own folder.
    static func address(of app: LampProject, among apps: [LampProject]) -> String {
        let word = word(of: app)
        if picks(word, among: apps).map(\.id) == [app.id] { return word }
        return app.isPart ? app.dir.lastPathComponent.lowercased() : "."
    }

    /// Which app of a wish an app is on the wish's list (`WishApp.folder`): its folder, or "." for the one in the wish's
    /// own folder.
    static func listedFolder(of app: LampProject) -> String { app.isPart ? app.dir.lastPathComponent : "." }

    // MARK: The apps a wish should have

    /// The apps a wish should have (`LampProject.apps`), as they are: the list its meta.json keeps, with what's made
    /// (the app in its own folder, each other found in its folder: `made`) taken as made whatever the list said, and listed when the
    /// list left it out (a wish from before wishes kept the list). An app made as another kind of the same family (the
    /// iPhone app that became one for both) counts as made.
    static func wanted(in wish: LampProject, parts: [LampProject]) -> [WishApp] {
        var apps = wish.apps
        for made in madeApps(in: wish, parts: parts) {
            apps = setting(WishApp(kind: made.platform, integration: listedIntegration(of: made), folder: listedFolder(of: made)), in: apps)
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

    /// The list once a part is made in `folder`: every app the wish has, the one in its own folder included (a wish from
    /// before the list has none written), with this one in place of the entry for its folder.
    static func listing(_ kind: Platform, integration: String? = nil, folder: String, madeFor wish: LampProject, parts: [LampProject]) -> [WishApp] {
        setting(WishApp(kind: kind, integration: integration, folder: folder), in: wanted(in: wish, parts: parts))
    }

    /// Whether a list entry is this app: the entry for its folder. An entry from before the list kept folders is the app
    /// of its code, as that list had it: of its family and, for a device's app, for its device.
    static func lists(_ entry: WishApp, _ app: LampProject) -> Bool {
        if let folder = entry.folder { return folder.lowercased() == listedFolder(of: app).lowercased() }
        return listsByCode(entry, app.platform, integration: listedIntegration(of: app))
    }

    /// Whether an entry from before the list kept folders is an app of this kind and device.
    private static func listsByCode(_ entry: WishApp, _ kind: Platform, integration: String?) -> Bool {
        guard group(entry.kind) == group(kind) else { return false }
        guard let mine = integration, let theirs = entry.integration else { return true }
        return DeviceApps.split(theirs).integration == DeviceApps.split(mine).integration
    }

    /// The list with one app set: in place of the entry for its folder, or of one from before the list kept folders that
    /// was this app (`lists`), or added beside the others. An entry with no folder (a caller that names none) goes in
    /// place of the one of its code, as the list did before.
    static func setting(_ app: WishApp, in apps: [WishApp]) -> [WishApp] {
        var apps = apps
        let index = app.folder.map { folder in
            apps.firstIndex { $0.folder?.lowercased() == folder.lowercased() }
                ?? apps.firstIndex { $0.folder == nil && listsByCode($0, app.kind, integration: app.integration) }
        } ?? apps.firstIndex { listsByCode($0, app.kind, integration: app.integration) && $0.folder == nil }
        if let index { apps[index] = app } else { apps.append(app) }
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

    /// The skill holding one app's rules: its kind's while it's in its kind's own folder, else one of its own named for
    /// its folder ("target-mac-mac2", "target-device-roku"), since a wish can have several apps of a kind, each with its
    /// folder (and a device's app its device) in its rules.
    static func skill(of app: LampProject) -> String {
        guard app.isPart, app.dir.lastPathComponent != folder(for: app.platform) else { return skill(for: app.platform) }
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
            // Each app outside its kind's own folder has a skill of its own. The kind's is the app's in its kind's folder,
            // or the only app's (a conversation from before may still ask for it by the kind's name), and with several
            // and none in the kind's folder, says which skill is whose.
            for part in mine where self.skill(of: part) != skill { add(self.skill(of: part), kind, part) }
            if let own = mine.first(where: { self.skill(of: $0) == skill }) ?? (mine.count == 1 ? mine.first : nil) {
                add(skill, kind, own)
            } else if mine.count > 1 {
                let each = mine.map { "\(name(of: $0)) in \($0.dir.lastPathComponent)/: the \(self.skill(of: $0)) skill" }
                skills[skill] = Skills.Skill(name: skill, description: "Which skill has the rules for each of the wish's \(mine.count) apps of this kind.",
                                            body: "This wish has \(mine.count) apps of this kind, each with rules of its own: " + each.joined(separator: "; ")
                                                + ". Open the one for the app you're changing.")
            } else {
                add(skill, kind, nil)
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
            app.isPart ? "\(name(of: app)) in \(app.dir.lastPathComponent)/ (part \"\(address(of: app, among: apps))\", its rules in the \(skill(of: app)) skill)"
                : "\(name(of: app)) in the wish's own folder (part \"\(address(of: app, among: apps))\", the rules above)"
        }
        return """

        - This wish is \(apps.count) apps: \(listed.joined(separator: ", and ")). Each is an app of its own kind with its own \
        build files, made to work with the others, and each is the person's: none comes first, and any of them can be \
        added or changed (`make_app_for`) or taken away (`remove_app`) when the person asks, each named by its folder in their `app` ("." for \
        the one in the wish's own folder). Before you write or change one in a folder of \
        its own, open its rules with `read_skill` (once per conversation) and follow them for the files in its folder. \
        `look_at_app` and `use_app` take `part` to say which app: look at each one you changed before finishing.
        """ + (apps.filter { WishRooms.joins($0.platform) }.count >= 2 ? Agent.Rules.wishTalk : "") + Targets.all.flatMap { kind in
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
        16 KB at most; the TV app hears them in `Lamp.controllers`' onButton, onAxis and onMessage, and a game on Lamp's runtime reads buttons each frame from `f.phones`. Anything bigger \
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
        You are Lamp's builder agent. The current directory is a new wish with nothing made for it yet. Before anything         is written, you decide what it is and where it runs, and give it its first app with `make_app_for`: what it is (a game or an         app), the devices it's to be on, and whether it's made as a web page or as each device's own native code.         \(named.isEmpty ? "The request names no device." : "The request names: \(named.joined(separator: ", ")).")

        Rules:
        - Choose from the request and from what each device can run (the table in `make_app_for`'s description, and the         person's own devices Lamp knows of, below the request). When the person names no make, take the table's default: a game is web wherever Lamp has         a host for a page (the game skill says what it's drawn with), and native elsewhere; an app on one Mac, iPhone or iPad, or Android phone or         tablet is native, and on a TV or a console web; one app asked for across several devices is web where every one         takes a page. A make the person names is theirs wherever Lamp can build it, and devices Lamp found never add a         device or change the make by themselves. How it gets onto each device is the table's. Most wishes that name no         device are for this Mac: a game made web, any other app native.
        - Ask with `ask` only when the answer really changes what you make, in one short question about people and         devices ("Just your phone, or your family's too?"), never "web or native". Nothing else in the card, and change         no files until it's answered. When it's clear, call `make_app_for` straight away.
        - A wish can be more than one app, made to work together (an iPhone app and its TV app): give the first with         `make_app_for`; one more beside it only once the person chose that when you asked with `ask`, with `another` (the more-apps skill).
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
