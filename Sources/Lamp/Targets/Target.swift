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

    var hasMac: Bool { target.places.contains(.mac) }
    var hasIOS: Bool { target.places.contains(.ios) }
    var hasAndroid: Bool { target.places.contains(.android) }
    var hasTV: Bool { target.places.contains(.tv) }
    /// Made for a device of the person's through its integration (`LampProject.integration`).
    var hasDevice: Bool { target.places.contains(.device) }
    /// Opens in more than one place, where Try On last put it (`LampProject.chosen`).
    var choosesPlace: Bool { target.places.count > 1 }
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
        /// Never one wish with other kinds: an Android app stands alone.
        let alone: Bool
        /// In a wish of more than one kind, the main one: what's on the TV is what the wish is about.
        var leads = false
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
        let rules: (_ folder: String) -> String
        /// One more rule for a wish that has it, at its root or as a part.
        var wishRule: String? = nil
        /// Whether a part's folder holds this kind, read without following a link.
        let isMade: (_ dir: URL, _ wish: URL) -> Bool
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
    static let all: [Target] = [.mac, .iphone, .universal, .android, .tv, .device]
    static let named = Dictionary(uniqueKeysWithValues: all.map { ($0.platform.rawValue, $0) })

    /// The kind a wish is when nothing says otherwise: a Mac app needs nothing more than Lamp has.
    static var fallback: Target { .mac }

    /// The order a folder or a list of devices is matched in: Lamp's Swift kinds, told apart by their Package.swift,
    /// once no kind with a mark of its own has claimed it.
    static var matchOrder: [Target] { all.filter { $0.recipe.language != .swift } + all.filter { $0.recipe.language == .swift } }

    /// The kinds that can be one wish with others, then those that stand alone: the order a sentence lists them in.
    static var listed: [Target] { all.filter { !$0.identity.devices.alone } + all.filter(\.identity.devices.alone) }

    static func owner(of word: String) -> Target? {
        matchOrder.first { $0.identity.devices.words.contains { $0.word == word } || $0.identity.devices.owns(word) }
    }

    /// The kind a folder is, read off what every version keeps.
    static func kind(of dir: URL) -> Platform? { matchOrder.first { $0.recipe.isMade(dir) }?.platform }

    // MARK: How the kinds are listed to models

    /// `make_app_for`'s devices (`{{DEVICES}}`): the kinds that can be one wish, then those that stand alone, and last
    /// what has no word of its own.
    static var toolDevices: String {
        let say = { (kinds: [Target]) in kinds.flatMap { $0.identity.devices.words.map(\.tool) } + kinds.compactMap(\.identity.devices.toolNote) }
        let alone = say(all.filter(\.identity.devices.alone))
        return say(all.filter { !$0.identity.devices.alone }).joined(separator: ", ") + (alone.isEmpty ? "" : "; " + alone.joined(separator: ", "))
    }

    /// "mac, iphone, watch, tv and android", for `make_app_for`'s answer to a list it can't make.
    static var toolWords: String { sentence(listed.flatMap { $0.identity.devices.words.map(\.word) }) }

    /// The naming call's devices: every kind's words, then the hints of those that stand alone, the rest's, and last
    /// the fallback's, which is what's left.
    static var namingDevices: String {
        let last = fallback.platform
        let hints = (all.filter(\.identity.devices.alone) + all.filter { !$0.identity.devices.alone && $0.platform != last } + [fallback])
            .compactMap(\.identity.devices.hint)
        return all.flatMap { $0.identity.devices.words.map(\.naming) }.joined(separator: ", ") + ". " + hints.joined(separator: "; ") + "."
    }

    /// The words a wish may be asked about (`AppName.candidates`), how it names each, and how it hears what Lamp makes.
    static var askedWords: [String] { all.compactMap(\.identity.devices.asked?.word) }
    static func asked(_ word: String) -> String? { all.first { $0.identity.devices.asked?.word == word }?.identity.devices.asked?.phrase }
    static var lampMakes: String { sentence(listed.compactMap(\.identity.devices.asked?.makes)) }

    private static func sentence(_ items: [String]) -> String {
        items.count < 2 ? items.joined() : items.dropLast().joined(separator: ", ") + " and " + items.last!
    }
}
