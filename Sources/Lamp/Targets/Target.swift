import Foundation

/// What an app is for: a kind of app Lamp makes, as meta.json names it ("mac", "iphone", "tv"…). Each kind is one
/// `Target` (Targets/), and what differs from kind to kind is read from it. An open set rather than an enum, so the
/// kinds aren't listed again wherever a switch would need them.
struct Platform: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String
    /// Only a kind Lamp has: anything else in a meta.json, a shared file or a chat line reads as nothing, as an
    /// unknown case of an enum did.
    init?(rawValue: String) {
        guard Targets.named[rawValue] != nil else { return nil }
        self.rawValue = rawValue
    }
    /// A target's own name for itself (`Platform.mac`), which `Targets.all` lists.
    init(kind: String) { rawValue = kind }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let kind = Platform(rawValue: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "No kind of app called \(raw)"))
        }
        self = kind
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Every kind there is was read through `init(rawValue:)`, which knows only listed kinds, or is a target's own
    /// constant: one missing from `Targets.all` is a mistake in Lamp, said at once rather than taken for a Mac app.
    var target: Target {
        guard let target = Targets.named[rawValue] else { preconditionFailure("\(rawValue) isn't in Targets.all") }
        return target
    }

    /// What an app made for these devices is ("mac", "iphone", "watch", "tv", a device integration's id): the kind that
    /// claims them. Nil for an empty list, a device Lamp doesn't make apps for, or devices of more than one kind
    /// (`Parts.kinds`).
    init?(devices: Set<String>) {
        guard let target = Targets.matchOrder.first(where: { $0.identity.devices.claims(devices) }) else { return nil }
        self = target.platform
    }

    /// Whether an app of this kind can open there at all. What an app has is the app's to say (`LampProject.hasMac`…):
    /// a kind whose places are given one at a time (a game, a screen) has only those it was given.
    func reaches(_ place: Destination) -> Bool { target.places.contains(place) }
    /// Opens in more than one place, where Try On last put it (`LampProject.chosen`).
    var choosesPlace: Bool { target.places.count > 1 }
    /// Its places are given one at a time, so each app of the kind says which it has (`LampProject.places`).
    var addsPlaces: Bool { target.startsAt != nil }
}

/// One kind of app, as the pieces that differ from kind to kind: how it's named and listed, what the agent is told,
/// how its files are made and read, what it is as a part of another kind's wish, and what this Mac needs to build it.
/// Where it opens is a `Destination`, whose running, looking and using Lamp already has: a kind that opens where another
/// does uses that. A new kind is a `Target` in a file of its own and a line in `Targets.all`.
struct Target {
    let platform: Platform
    /// Where it can open: the first unless Try On chose another (`LampProject.destination`).
    let places: [Destination]
    let identity: Identity
    let guidance: Guidance
    let recipe: Recipe
    /// Nil for a kind that's never one of a wish's other apps.
    let part: Part?
    let setup: Setup
    /// Where a new app of the kind opens, of its `places`, when the kind's places are given one at a time (a game, at
    /// home on the Mac until it's put somewhere else too: `LampProject.places`). Nil for all of them from the start.
    var startsAt: [Destination]? = nil
    /// Its app on the Mac and iOS is Lamp's own around the agent's page (a game's, a screen's), built from Lamp's files in
    /// release whenever they change: a change reopens it rather than going in live, and its copies always take the chat.
    var hostedByLamp = false
    /// A page in a web view of its own, whose Web/ goes into the app wherever it's built (the phone's Xcode project too).
    var showsPage: (LampProject) -> Bool = { _ in false }
    /// The folder of the apps folder its Mac copy is installed in, when it isn't the apps folder itself: a wish's apps
    /// are installed under its name, and a game or a screen beside its Mac app would take the Mac app's place there.
    var installFolder: String? = nil
    /// Its own SwiftUI builds for tvOS and visionOS too, so Try On offers the Apple TV and Vision Pro simulators.
    var otherSystems = false
    /// Its Mac half is built by Xcode for the person's Apple team, so it can't be built without one.
    var macSignedForTeam = false

    /// How Lamp names the kind, the devices it's for, and how it shows it.
    struct Identity {
        /// "the iPhone app": a part of a wish, a crash, a line about where it opens.
        let name: String
        /// For the prompts that describe the app to a model: "a Mac app".
        let phrase: String
        /// Kept as it was, so the counts carry on.
        let analytics: String
        /// What it's made for, when a wish becomes it ("iPhone and iPad"), with `whose` for a device of the person's.
        let made: (_ device: String?, _ whose: String) -> String
        let devices: Words
        let tryOnHelp: (LampProject) -> String
        /// Where the desk says it lives, or nil to read it from a Mac app's own code (`WishPlace`).
        let place: (LampProject) -> WishPlace?
    }

    /// The device words a kind is chosen by, which the naming call, `make_app_for` and an undecided wish list together
    /// (`Targets`).
    struct Words {
        /// "tv": in `make_app_for`'s description and in the naming call's list.
        let words: [(word: String, tool: String, naming: String)]
        /// More for `make_app_for`'s list, for what has no word of its own (a device integration's id).
        var toolNote: String? = nil
        /// The naming call's hint for when a wish is for it.
        let hint: String?
        let claims: (Set<String>) -> Bool
        /// A word of its own beyond `words` (an integration's id).
        var owns: (String) -> Bool = { _ in false }
        /// Listed apart from the kinds of a wish's apps, its hint before theirs: a device app, which is never one wish with
        /// other kinds, and a game and a screen, which are one wish with others only through their own word.
        let alone: Bool
        /// How a wish still to be told what it's for asks about it ("for the TV"), and how it hears what Lamp makes
        /// ("for Samsung and LG TVs"). Nil when it's never asked about.
        var asked: (word: String, phrase: String, makes: String)? = nil
    }

    /// What the agent is told about the kind.
    struct Guidance {
        let prompt: (LampProject) -> String
        /// What `make_app_for` answers with when an app becomes it.
        let changeRules: (LampProject) -> String
        let skills: () -> [String]
        /// The skills its prompt names in its own short rules rather than in its list (`Skills.named`).
        var named: [String] = []
        /// The AI line of an app with none of Lamp's, and what it has away from this Mac (`AIStatus`).
        var noAI: @MainActor (LampProject) -> String? = { _ in nil }
        let elsewhere: @MainActor (LampProject) -> String?
    }

    /// How the kind's files are written and read.
    struct Recipe {
        let language: Language
        let fill: (LampProject) throws -> Void
        /// Lamp's own files, written afresh before every build, and its building blocks, before every turn.
        let ownedFiles: (LampProject) throws -> Void
        let support: (LampProject) throws -> Void
        /// Whether a folder is this kind, read off what every version keeps.
        let isMade: (URL) -> Bool
        /// Whether the scaffold is written (`LampProject.scaffolded`).
        let scaffolded: (URL, LampProject) -> Bool
        /// What a build is made from, under the app's folder, and what else it depends on (`Runtime.fingerprint`).
        let sources: (LampProject) -> [String]
        var built: String? = nil
        var inputs: (LampProject) -> String? = { _ in nil }
        let builtURL: (LampProject) -> URL
        /// The file of Lamp's that marks a folder as this kind, taken away when it becomes another.
        var marker: String? = nil
        /// Its scaffold is written again whenever an app becomes this kind, even from the same code (a device app's is
        /// its integration's).
        var refills = false
        /// The integration a folder of this kind was written for.
        var integration: (URL) -> String? = { _ in nil }
        /// The kind whose files these are, with a mark of this one's own (an Android TV app is an Android app with a TV's
        /// manifest): a folder is asked whether it's this kind before it's asked whether it's that one.
        var refines: Platform? = nil
        /// Why it can't be shared as a file yet, or nil.
        let shareRefusal: String?
    }

    /// What a kind is as one of a wish's other apps, in a folder of the wish's (`Parts`).
    struct Part {
        let folder: String
        /// A wish has one part of a family; kinds of one family change into each other in place, in the same folder.
        let family: String
        /// `part` in `look_at_app` and `use_app`.
        let word: String
        let menu: (name: String, symbol: String)
        /// Its rules for the files in its folder; `alone` when it's its wish's only app, so nothing about the others.
        let rules: (_ folder: String, _ alone: Bool) -> String
        /// One more rule for a wish that has it, at its root or as a part.
        var wishRule: String? = nil
        /// Whether a part's folder holds this kind, read without following a link.
        let isMade: (_ dir: URL, _ wish: URL) -> Bool
        /// For a kind whose folder follows what it's made for rather than the kind alone (a device's app, its
        /// integration's: Roku/), the folder for that integration; nil for none it knows. `folder` is then the one used
        /// where nothing says which.
        var folderFor: ((_ integration: String) -> String?)? = nil
        /// Every other folder an app of the kind may be in: one per integration, for a device's app.
        var moreFolders: () -> [String] = { [] }
        /// The folders of a wish that hold an app of the kind whatever they're called now, found by its own mark: a
        /// device's app stays found when its integration's name (and so the folder a new one gets) changes. Each such
        /// folder names its own device, so more than one may be found while one replaces another.
        var marked: ((_ wish: URL) -> [String])? = nil
        /// Whether it joins the wish's room at Lamp's relay and so reaches the wish's other apps (`WishRooms`). One that
        /// can't yet is left out of the room's list, so the others never wait for it, and isn't counted among the apps
        /// that give the others `LampWish` (`Template.talksToOtherApps`).
        var joinsWish = true

        /// Every folder an app of the kind may be in.
        var folders: [String] { [folder] + moreFolders().filter { $0 != folder } }
    }

    /// What this Mac needs to build the kind.
    struct Setup {
        /// A new wish taken as it: whether it can be made so now. False leaves the wish a Mac app with `later`.
        let canChoose: @MainActor (_ said: Bool, _ integration: String?) async -> Bool
        /// What this Mac lacks, as "this Mac can't build…", with the setup opened; `part` names it as a wish's part.
        let notReady: @MainActor (_ integration: String?, _ part: String?) async -> String?
        let later: SetupLater?
        /// A kind this Mac can always build.
        static let none = Setup(canChoose: { _, _ in true }, notReady: { _, _ in nil }, later: nil)
    }
}

/// What a kind's code is written in. Going to another, the app is written again in it: `make_app_for` names the old
/// code and what's left of it, and asks for the new.
struct Language: Equatable {
    let name: String
    let code: String
    let leftover: String
    let rewrite: (_ from: String, _ leftover: String) -> String
    static func == (a: Language, b: Language) -> Bool { a.name == b.name }

    static let swift = Language(name: "swift", code: "the Swift in Sources/", leftover: "Sources/, Package.swift and the other Swift-only files") {
        "Write the app again in Swift under Sources/ (the scaffold is there), reading \($0) for what it does, then delete \($1) with delete_file. "
    }
}

/// The chat's line when a wish read as a kind stays a Mac app because this Mac can't build it yet (`IPhoneSetupLine`):
/// what's needed, the setup it opens, and what's asked of the agent once that's done.
struct SetupLater {
    let symbol: String
    let needs: String
    let apps: String
    let request: String
    /// `done` once it's done, `cancelled` when the person closes it; `wanted` says whether the app still needs it.
    let open: @MainActor (_ wanted: @escaping @MainActor () -> Bool, _ cancelled: @escaping () -> Void, _ done: @escaping () -> Void) -> Void
}

/// Every kind of app Lamp makes, in the order they're listed: to the naming call, in `make_app_for`'s description, and
/// to a wish still to be told what it's for.
enum Targets {
    static let all: [Target] = [.mac, .iphone, .universal, .android, .androidTV, .tv, .game, .screen, .device]
    static let named = Dictionary(uniqueKeysWithValues: all.map { ($0.platform.rawValue, $0) })

    /// The kind a wish is when nothing says otherwise: a Mac app needs nothing more than Lamp has.
    static var fallback: Target { .mac }

    /// The order a folder or a list of devices is matched in, so each is read as the most particular kind it is: a kind
    /// made from another's files before that one, then the kinds with a mark of their own, and Lamp's Swift kinds, told
    /// apart by their Package.swift, once none of those has claimed it.
    static var matchOrder: [Target] { matchOrder(all) }
    static func matchOrder(_ kinds: [Target]) -> [Target] {
        let refining = kinds.filter { $0.recipe.refines != nil }, rest = kinds.filter { $0.recipe.refines == nil }
        return refining + rest.filter { $0.recipe.language != .swift } + rest.filter { $0.recipe.language == .swift }
    }

    /// The kinds that can be one wish with others, then those that stand alone: the order a sentence lists them in.
    static var listed: [Target] { all.filter { !$0.identity.devices.alone } + all.filter(\.identity.devices.alone) }

    static func owner(of word: String) -> Target? {
        matchOrder.first { $0.identity.devices.words.contains { $0.word == word } || $0.identity.devices.owns(word) }
    }

    /// The kind a folder is, read off what every version keeps.
    static func kind(of dir: URL) -> Platform? { matchOrder.first { $0.recipe.isMade(dir) }?.platform }
}
