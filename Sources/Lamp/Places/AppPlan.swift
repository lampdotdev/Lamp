import Foundation

/// A device as `make_app_for` or `remove_app` named it: the word it was given by ("ipad"), kept, its row in the table of
/// devices ("iphone"), which is what it can run, and the family of Apple's devices that word means in its row, if any.
struct DeviceWord: Hashable {
    let word: String
    let row: String
    let family: DeviceFamily?

    init?(_ word: String, in table: [Place] = Places.all) {
        let word = word.trimmed.lowercased()
        guard let place = Places.named(word, in: table) else { return nil }
        self.init(word: word, in: place)
    }

    init(word: String, in place: Place) {
        self.word = word
        row = place.id
        family = place.wordFamilies[word]
    }
}

/// What an app is for, as `make_app_for`'s `kind` says it: a game, or any other app. It's the agent's to say, never read
/// off the devices; how it's made (`Place.Make`) is said apart, so a game and an app may each be web or native.
enum AppIntent: String, CaseIterable {
    case game, app

    /// What an app of a wish is for, from what it's made as: a game is a game, any other kind (a screen made before
    /// included) an app.
    static func of(_ kind: Platform) -> AppIntent { kind == .game ? .game : .app }
}

/// What an app of a wish is to be, in the terms Lamp builds it in today: the kind, the devices it's for (as they were
/// asked for), the integration of a device's own app, the family of Apple's devices Try On opens it on, and for a game
/// or a screen the places it's played or shown. `code` is the key of what it's written in: two apps of one key are one
/// app, changed into each other in place.
struct AppTarget: Equatable {
    let kind: Platform
    let devices: [DeviceWord]
    var integration: String? = nil
    var places: [Destination]? = nil
    /// Asked for as a game (`make_app_for`'s `kind`), which a game made natively is only by this: its kind is the
    /// devices' own code, as any app's is.
    var game = false

    var code: String { AppKinds.code(of: kind, integration: integration) }
    var rows: Set<String> { Set(devices.map(\.row)) }
    /// The family Try On opens it on: the first device asked for that names one ("ipad" before "iphone" opens it on an
    /// iPad). Nil only when no device asked for names a family.
    var family: DeviceFamily? { devices.lazy.compactMap(\.family).first }

    /// As the wish's list keeps it while it waits, whole.
    var waiting: WishApp {
        WishApp(kind: kind, places: places, devices: devices.map(\.word), integration: integration, game: game && kind != .game ? true : nil)
    }
}

/// One app of a wish as the plan sees it: made, with its id and folder, or waiting to be made (on the wish's list,
/// stopped by this Mac's setup or not started yet), with what it is and the folder kept for it.
struct WishMember: Equatable {
    enum State: Equatable {
        case made(id: String, folder: String?)
        /// `folder`: the one kept for it (`WishApp.folder`), nil in a list from before the list kept folders.
        case waiting(folder: String?)
    }

    let state: State
    let target: AppTarget

    var isMade: Bool { if case .made = state { return true } else { return false } }
    var id: String? { if case .made(let id, _) = state { return id } else { return nil } }
    /// The app's own folder in the wish's, or nil for the app in the wish's own folder and one not made.
    var folder: String? { if case .made(_, let folder) = state { return folder } else { return nil } }
    /// The folder it's in or will be made in: "." for the app in the wish's own folder, nil for one waiting in a list
    /// from before the list kept folders.
    var slot: String? {
        switch state {
        case .made(_, let folder): folder ?? "."
        case .waiting(let folder): folder
        }
    }
}

/// What `make_app_for` or `remove_app` does to a wish, worked out before anything is touched, so what's done is what
/// was planned and the answer says what was done.
enum AppPlan: Equatable {
    /// The first app of a wish that has none, made or waiting.
    case add(AppTarget)
    /// One more app beside the wish's others, asked for with `another`: made only once the person has chosen
    /// "Add another app" on Lamp's own card (`AppAdditions`), never on the agent's word alone.
    case another(AppTarget)
    /// The app `make_app_for` named, made or waiting, given what's asked: changed in place, its folder, id and data kept.
    case update(WishMember, to: AppTarget)
    /// A made app taken away, reversibly: its files stay in the wish's versions and its data stays.
    case remove(WishMember)
    /// An app the wish was still to have, taken off its list.
    case cancel(WishMember)
}

/// Today's recipes, read in the terms of the table of devices: which kind of app builds a make on some devices, and
/// which devices each kind of app a wish has is on. What a device can run, how it's named and which family a word means
/// are the table's (`Places`); this is only the legacy translation from rows to today's kinds, and goes once Lamp has one
/// host for every page and one recipe per native code.
enum AppKinds {
    /// The key of what an app is written in. Today's part families, and for a device's own app its integration, since
    /// two devices' apps are two codes.
    static func code(of kind: Platform, integration: String?) -> String {
        kind == .device ? "device:" + (integration.map { DeviceApps.split($0).integration } ?? "") : Parts.group(kind)
    }

    /// The kind that builds each native code today; Apple's code is a Mac app, an iPhone app or one for both, by where
    /// its rows open.
    private static func nativeKind(_ code: Place.NativeCode, opening: Set<Destination>) -> Platform {
        switch code {
        case .apple: opening.contains(.mac) ? (opening.contains(.ios) ? .universal : .mac) : .iphone
        case .android: .android
        case .androidTV: .androidTV
        case .integration: .device
        }
    }

    /// The native code a kind of app is written in, for the kinds that are native; nil for a page.
    private static func nativeCode(of kind: Platform) -> Place.NativeCode? {
        switch kind {
        case .mac, .iphone, .universal: .apple
        case .android: .android
        case .androidTV: .androidTV
        case .device: .integration
        default: nil
        }
    }

    /// What an app of this make and intent on these devices is today, or why there's no such app. A native app is the
    /// kind of its rows' one code, whichever intent it has: a game and an app are written in the same code. A web game is
    /// a web game on Lamp's game runtime (Phaser for 2D, three.js for 3D); a web app is a web app at home on the Mac that goes wherever a page goes,
    /// or a TV app where only Samsung or LG TVs are asked for, whose package is the TVs' own. `keeping` is the kind of the
    /// app being changed (`make_app_for`'s `app`), kept when it's a web app that still reaches every row: a screen made
    /// before stays one, with its origin and saves. The devices never choose between a game and an app.
    static func target(_ make: Place.Make, kind intent: AppIntent, on devices: [DeviceWord], keeping: Platform? = nil,
                       in table: [Place] = Places.all) -> Result<AppTarget, Refusal> {
        let ids = Set(devices.map(\.row))
        guard !ids.isEmpty else { return .failure(Refusal("`devices` lists every device the app is to be on: at least one.")) }
        if let refusal = Places.refusal(make: make, devices: ids, in: table) { return .failure(Refusal(refusal)) }
        let rows = table.filter { ids.contains($0.id) }
        let reached = Set(rows.map(\.destination))
        // One integration's device: its own app, whichever make it declares.
        let integration = rows.count == 1 && rows[0].destination == .device ? rows[0].id : nil
        switch make {
        case .native:
            let codes = Set(rows.compactMap(\.native?.code))
            guard codes.count == 1, let code = codes.first, code != .integration || integration != nil else {
                let byCode: [Place.NativeCode: [Place]] = Dictionary(grouping: table.filter { $0.native != nil }) { $0.native!.code }
                let groups: [String] = byCode.sorted { $0.key.rawValue < $1.key.rawValue }.map { code, rows in
                    rows.map(\.name).joined(separator: ", ") + (code == .integration ? " (each its own)" : "")
                }
                return .failure(Refusal("One native app is one code: " + groups.joined(separator: "; ") + ". Give the devices of one code, and call again for the others."))
            }
            // A device that only comes with another's app is built with it, though the devices stay as asked: the one
            // it comes with names no family it wasn't asked for.
            let with = Set(rows.compactMap(\.comesWith))
            let opening = reached.union(table.filter { with.contains($0.id) }.map(\.destination))
            return .success(AppTarget(kind: nativeKind(code, opening: opening), devices: devices, integration: integration))
        case .web:
            // An integration's device alone is its own web app, but for a game on one Lamp packages games' pages for.
            if let integration, !(intent == .game && GameKit.pageIntegrations.contains(integration)) {
                return .success(AppTarget(kind: .device, devices: devices, integration: integration))
            }
            // A page among other devices reaches an integration's only where Lamp packages it for that integration's host:
            // another integration's device, though it runs web apps of its own, isn't one of the page's places yet.
            if let other = rows.first(where: { $0.destination == .device && !GameKit.pageIntegrations.contains($0.id) }) {
                return .failure(Refusal("Lamp can't put a web app made for other devices on \(other.name) yet: its own web app is asked for "
                    + "with \(other.name) alone. Give the other devices without it, and call again for \(other.name)'s app."))
            }
            let kind: Platform
            switch intent {
            case .game: kind = .game
            case .app:
                if let keeping, [.webApp, .screen, .tv].contains(keeping), reached.isSubset(of: Set(keeping.target.places)) { kind = keeping }
                else if reached.isSubset(of: Set(Platform.tv.target.places)) { kind = .tv }
                else { kind = .webApp }
            }
            guard reached.isSubset(of: Set(kind.target.places)) else {
                let reach = table.filter { $0.runs(.web) && kind.target.places.contains($0.destination) }.map(\.name).joined(separator: ", ")
                return .failure(Refusal("Lamp can't put one web \(intent.rawValue) on all of these yet: \(rows.map(\.name).joined(separator: ", ")). "
                    + "One goes on \(reach)."))
            }
            // A page with places (a game, a web app) is at home on the Mac, and goes wherever else it's asked for.
            let places = kind.addsPlaces ? kind.target.places.filter { $0 == .mac || reached.contains($0) } : nil
            return .success(AppTarget(kind: kind, devices: devices, places: places))
        }
    }

    /// A made app as it reads back.
    static func member(of app: LampProject, in table: [Place] = Places.all) -> WishMember {
        WishMember(state: .made(id: app.id, folder: app.isPart ? app.dir.lastPathComponent : nil), target: target(of: app, in: table))
    }

    /// An app a wish is still to have, as its list keeps it: whole, as it was asked, or for a list from before that kept
    /// only its kind, as that kind opens.
    static func member(waiting app: WishApp, in table: [Place] = Places.all) -> WishMember {
        let asked = (app.devices ?? []).compactMap { DeviceWord($0, in: table) }
        let target = asked.isEmpty ? self.target(kind: app.kind, opening: app.places ?? app.kind.target.places, family: nil, integration: app.integration,
                                                companions: [], in: table)
            : AppTarget(kind: app.kind, devices: asked, integration: app.integration, places: app.places, game: app.game == true || app.kind == .game)
        return WishMember(state: .waiting(folder: app.folder), target: target)
    }

    private static func target(of app: LampProject, in table: [Place]) -> AppTarget {
        let opening = app.platform.addsPlaces ? (app.places ?? [.mac]) : app.platform.target.places
        let companions = Template.hasWatch(app) ? table.filter { $0.comesWith != nil }.map(\.id) : []
        return target(kind: app.platform, opening: opening, family: opening.contains(.ios) ? app.family : nil, integration: app.integration,
                      companions: companions, in: table)
    }

    /// The rows an app of this kind is on, from where it opens: of each destination, the rows of its code (or that show a
    /// page, for a page) and of its family where rows there differ by family, with the words that name that family, and
    /// the rows that come with it (`companions`) only when it has them.
    private static func target(kind: Platform, opening: [Destination], family: DeviceFamily?, integration: String?,
                               companions: [String], in table: [Place]) -> AppTarget {
        let code = nativeCode(of: kind)
        let device = integration.map { DeviceApps.split($0).integration }
        var devices: [DeviceWord] = []
        for row in table where opening.contains(row.destination) {
            // A device's own app is on its integration's devices; a page with a device among its places, on each that shows one.
            if row.destination == .device, let device, row.id != device { continue }
            if let code { guard row.native?.code == code else { continue } } else { guard row.runs(.web) else { continue } }
            if row.comesWith != nil, !companions.contains(row.id) { continue }
            if row.wordFamilies.isEmpty {
                devices.append(DeviceWord(word: row.words[0], in: row))
            } else if let word = row.wordFamilies.first(where: { $0.value == family })?.key {
                // The family it opens on comes first, so it's the family read back.
                devices.insert(DeviceWord(word: word, in: row), at: 0)
            } else if let word = row.wordFamilies.first(where: { $0.value == .iphone })?.key {
                // The row the kind is built for whichever other system it also opens on (an iPhone app on an Apple TV).
                devices.append(DeviceWord(word: word, in: row))
            }
        }
        return AppTarget(kind: kind, devices: devices, integration: kind == .device ? integration : nil,
                         places: kind.addsPlaces ? opening : nil)
    }
}

/// Why a request can't be done, in the agent's words.
struct Refusal: Error, Equatable {
    let reason: String
    init(_ reason: String) { self.reason = reason }
}

/// `make_app_for` and `remove_app` as plans over a wish's apps (`WishMember`): typed in, checked against the table and
/// the wish's apps, and handed to `Store` to carry out as planned.
enum AppPlanner {
    /// What a `make_app_for` call is, read from its `app` and `another` before anything else: the first app of a wish
    /// with none, a change to the app `app` names, or one more app beside the wish's others. A wish with an app, made or
    /// still to be made, never gets another by default: a call that names none is refused, so a change of mind ("never
    /// mind, make it a timer instead") changes the app the wish has, and adding one is always asked for in so many
    /// words (`another`) and then chosen by the person (`AppAdditions`). Anything malformed is refused here, before
    /// anything is written. This is the one place the decision is made, for every caller.
    enum Mode: Equatable {
        case first
        case change(WishMember)
        case another
    }

    static func decide(app: Any?, another: Any?, in members: [WishMember]) -> Result<Mode, Refusal> {
        let adding: Bool
        switch another {
        case nil, is NSNull: adding = false
        case let flag as Bool: adding = flag
        default: return .failure(Refusal("`another` is true or left out. Nothing changed."))
        }
        let selector: String?
        switch app {
        case nil, is NSNull: selector = nil
        case let text as String:
            guard !text.trimmed.isEmpty else { return .failure(Refusal("`app` is an app's folder: \(folders(members)). Nothing changed.")) }
            selector = text.trimmed
        default: return .failure(Refusal("`app` is an app's folder, as text: \(folders(members)). Nothing changed."))
        }
        if selector != nil, adding {
            return .failure(Refusal("`app` changes an app the wish has; `another` adds a new one. Give one of them. Nothing changed."))
        }
        if let selector {
            switch select(selector, in: members) {
            case .one(let member): return .success(.change(member))
            case .several(let found):
                return .failure(Refusal("`app` \"\(selector)\" is more than one of the wish's apps (\(found.compactMap(\.slot).joined(separator: ", "))): give its folder. Nothing changed."))
            case .none:
                return .failure(Refusal("The wish has no app in \"\(selector)\"" + (members.isEmpty ? "." : ": `app` is one of \(folders(members)).") + " Nothing changed."))
            }
        }
        if adding || members.isEmpty { return .success(members.isEmpty ? .first : .another) }
        return .failure(Refusal("This wish already has \(members.count == 1 ? "an app" : "\(members.count) apps") (`app` \(folders(members))). "
            + "To change one, including when the person changed their mind or wants something else in its place, give its folder in `app`. "
            + "To add one more app of another kind beside it (an Android app beside a Mac app), ask the person first with `ask` and end your turn; give `another: true` only once they chose that. "
            + "Nothing changed."))
    }

    private static func folders(_ members: [WishMember]) -> String {
        let all = members.compactMap(\.slot).map { "\"\($0)\"" }
        return all.isEmpty ? "none yet" : all.joined(separator: ", ")
    }

    /// `make_app_for`: what `decide` reads from `app` and `another`, as a plan over the wish's apps: the first app, the
    /// app `app` names changed, or one more beside the others (two apps of one code, two Mac apps, are two apps, each in
    /// its own folder). Never a removal. `table` is the table of devices, every row Lamp has unless said.
    static func make(_ made: Place.Make, kind intent: AppIntent, devices words: [String], app: Any? = nil, another: Any? = nil,
                     in members: [WishMember], table: [Place] = Places.all) -> Result<AppPlan, Refusal> {
        // Which app is to change, if any, is found before anything else is read, so a call that names none changes nothing.
        let mode: Mode
        switch decide(app: app, another: another, in: members) {
        case .success(let decided): mode = decided
        case .failure(let refusal): return .failure(refusal)
        }
        var chosen: WishMember?
        if case .change(let member) = mode { chosen = member }
        var devices: [DeviceWord] = []
        for word in words {
            guard let device = DeviceWord(word, in: table) else {
                return .failure(Refusal("Lamp knows no device \"\(word)\": `devices` are the words in the table of devices, "
                                        + table.flatMap(\.words).map { "\"\($0)\"" }.joined(separator: ", ") + "."))
            }
            if !devices.contains(device) { devices.append(device) }
        }
        var target: AppTarget
        switch AppKinds.target(made, kind: intent, on: devices, keeping: chosen?.target.kind, in: table) {
        case .success(let found): target = found
        case .failure(let refusal): return .failure(refusal)
        }
        target.game = intent == .game
        // One more app is of a code the wish has none of, made or still to be made: two apps of one code (two Mac apps)
        // can't be in one wish yet, as sharing a wish and a request's repeated call can't tell them apart. A device's
        // own app is one per wish for now, whichever device's. Refused here, before any folder is found or anything
        // written.
        if mode == .another {
            if let same = members.first(where: { $0.target.code == target.code }) {
                let name = Parts.name(of: target.kind, integration: target.integration)
                return .failure(Refusal("This wish already has \(name)" + (same.slot.map { $0 == "." ? " (`app` \".\")" : " (`app` \"\($0)\")" } ?? "")
                    + ", and Lamp can't keep two apps of one kind in a wish yet. Nothing changed. To change that app, give its folder in `app`; "
                    + "tell the person in a sentence that a second one can't be added for now."))
            }
            if target.kind == .device, let other = members.first(where: { $0.target.kind == .device }) {
                return .failure(Refusal("A wish has one app for a device of its own for now, and this one has \(Parts.name(of: .device, integration: other.target.integration)). "
                                        + "Nothing changed. If the person wants this device's app instead, take that one away with remove_app, then ask again."))
            }
        }
        switch mode {
        case .change(let member): return .success(.update(member, to: target))
        case .another: return .success(.another(target))
        case .first: return .success(.add(target))
        }
    }

    /// The app `make_app_for`'s `app` names: its folder exactly, whatever the case ("Mac2"), or "." for the app in the
    /// wish's own folder. Nothing else: no kind, device or code stands for an app here, so asking for one never changes
    /// another. Folders are unique whatever the case (`Parts.newFolder`); two that aren't are asked about.
    static func select(_ selector: String, in members: [WishMember]) -> Found {
        let name = selector.trimmed.lowercased()
        guard !name.isEmpty, !name.contains("/"), name == "." || !name.hasPrefix(".") else { return .none }
        let found = members.filter { $0.slot?.lowercased() == name }
        switch found.count {
        case 0: return .none
        case 1: return .one(found[0])
        default: return .several(found)
        }
    }

    /// What `remove_app`'s `app` names, among the wish's apps, made and waiting.
    enum Found: Equatable {
        case one(WishMember)
        case several([WishMember])
        case none
    }

    /// An app by its folder or its own word first ("Game", "screen"), then by a device it's on ("tv", "ipad", "xbox-one").
    static func find(_ named: String, in members: [WishMember], table: [Place] = Places.all) -> Found {
        let name = named.trimmed.lowercased()
        guard !name.isEmpty else { return .none }
        // "." too: the app in the wish's own folder can be the last one taken away, by the name `make_app_for` gives it.
        if case .one(let member) = select(name, in: members) { return .one(member) }
        let own = members.filter { member in
            member.folder?.lowercased() == name || Parts.word(for: member.target.kind) == name
                || Parts.folder(for: member.target.kind).lowercased() == name || member.target.kind.rawValue == name
        }
        if own.count == 1 { return .one(own[0]) }
        if own.count > 1 { return .several(own) }
        guard let device = DeviceWord(name, in: table) else { return .none }
        let there = members.filter { $0.target.rows.contains(device.row) }
        switch there.count {
        case 0: return .none
        case 1: return .one(there[0])
        default: return .several(there)
        }
    }

    /// `remove_app`: a made app taken away, or a waiting one taken off the list. The wish's last app too: the wish stays,
    /// with its name, chat and history, and no app until `make_app_for` gives it its first again.
    static func remove(_ named: String, in members: [WishMember], table: [Place] = Places.all,
                       describe: (WishMember) -> String) -> Result<AppPlan, Refusal> {
        let listed = members.map(describe).joined(separator: ", ")
        switch find(named, in: members, table: table) {
        case .none:
            return .failure(Refusal("The wish has no app \"\(named)\". Its apps: \(listed). Name one by its folder or a device it's on."))
        case .several(let found):
            return .failure(Refusal("\"\(named)\" is more than one of the wish's apps: \(found.map(describe).joined(separator: ", ")). Name one by its folder."))
        case .one(let member):
            return .success(member.isMade ? .remove(member) : .cancel(member))
        }
    }
}
