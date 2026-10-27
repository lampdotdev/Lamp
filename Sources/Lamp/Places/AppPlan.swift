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

/// What an app of a wish is to be, in the terms Lamp builds it in today: the kind, the devices it's for (as they were
/// asked for), the integration of a device's own app, the family of Apple's devices Try On opens it on, and for a game
/// or a screen the places it's played or shown. `code` is the key of what it's written in: two apps of one key are one
/// app, changed into each other in place.
struct AppTarget: Equatable {
    let kind: Platform
    let devices: [DeviceWord]
    var integration: String? = nil
    var places: [Destination]? = nil

    var code: String { AppKinds.code(of: kind, integration: integration) }
    var rows: Set<String> { Set(devices.map(\.row)) }
    /// The family Try On opens it on: the first device asked for that names one ("ipad" before "iphone" opens it on an
    /// iPad). Nil only when no device asked for names a family.
    var family: DeviceFamily? { devices.lazy.compactMap(\.family).first }

    /// As the wish's list keeps it while it waits, whole.
    var waiting: WishApp {
        WishApp(kind: kind, places: places, devices: devices.map(\.word), integration: integration)
    }
}

/// One app of a wish as the plan sees it: made, with its id and folder, or waiting to be made (on the wish's list,
/// stopped by this Mac's setup or not started yet), with what it is.
struct WishMember: Equatable {
    enum State: Equatable {
        case made(id: String, folder: String?)
        case waiting
    }

    let state: State
    let target: AppTarget

    var isMade: Bool { if case .made = state { return true } else { return false } }
    var id: String? { if case .made(let id, _) = state { return id } else { return nil } }
    /// The app's own folder in the wish's, or nil for the app in the wish's own folder and one not made.
    var folder: String? { if case .made(_, let folder) = state { return folder } else { return nil } }
}

/// What `make_app_for` or `remove_app` does to a wish, worked out before anything is touched, so what's done is what
/// was planned and the answer says what was done.
enum AppPlan: Equatable {
    /// A new app of a code the wish has none of, beside its others.
    case add(AppTarget)
    /// The wish's app of this code, made or waiting, given what's asked: changed in place, its code and data kept.
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

    /// The kinds that show a page today, most particular first where two reach the same devices.
    private static let pageKinds: [Platform] = [.tv, .device, .game, .screen]

    /// What an app of this make on these devices is today, or why there's no such app. A native app is the kind of its
    /// rows' one code. A web app is the kind of page whose places reach every row: the wish's own when it has one that
    /// does, else the one that reaches the fewest other places, the first listed where two tie.
    static func target(_ make: Place.Make, on devices: [DeviceWord], existing: [WishMember] = [],
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
            if let integration { return .success(AppTarget(kind: .device, devices: devices, integration: integration)) }
            let fits = pageKinds.filter { $0 != .device && reached.isSubset(of: Set($0.target.places)) }
            let kept = existing.map(\.target.kind).first(where: fits.contains)
            guard let kind = kept ?? fits.filter({ $0 != .screen }).min(by: { $0.target.places.count < $1.target.places.count }) else { // a screen is only ever kept
                let reach = { (kind: Platform) in table.filter { $0.runs(.web) && kind.target.places.contains($0.destination) }.map(\.name).joined(separator: ", ") }
                return .failure(Refusal("Lamp can't put one web app on all of these yet: \(rows.map(\.name).joined(separator: ", ")). "
                    + pageKinds.filter { $0 != .device && $0.target.places.count > 1 }.map { "One web app goes on \(reach($0))" }.joined(separator: "; ")
                    + ". Give the devices one of them covers, and another app for the rest."))
            }
            // A page with places (a game, a screen) is at home on the Mac, and goes wherever else it's asked for.
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
            : AppTarget(kind: app.kind, devices: asked, integration: app.integration, places: app.places)
        return WishMember(state: .waiting, target: target)
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
    /// `make_app_for`: the app of the asked-for code changed, or a new one beside the others. Never a removal.
    /// `table` is the table of devices, every row Lamp has unless said.
    static func make(_ made: Place.Make, devices words: [String], in members: [WishMember],
                     table: [Place] = Places.all) -> Result<AppPlan, Refusal> {
        var devices: [DeviceWord] = []
        for word in words {
            guard let device = DeviceWord(word, in: table) else {
                return .failure(Refusal("Lamp knows no device \"\(word)\": `devices` are the words in the table of devices, "
                                        + table.flatMap(\.words).map { "\"\($0)\"" }.joined(separator: ", ") + "."))
            }
            if !devices.contains(device) { devices.append(device) }
        }
        let target: AppTarget
        switch AppKinds.target(made, on: devices, existing: members, in: table) {
        case .success(let found): target = found
        case .failure(let refusal): return .failure(refusal)
        }
        // A device's own app is one of the wish's apps beside the others, one per wish for now: another device's is never
        // made out of it (two integrations are two codes), and asked for while it's there, it waits for the old one to go.
        if target.kind == .device, let other = members.first(where: { $0.target.kind == .device && $0.target.code != target.code }) {
            return .failure(Refusal("A wish has one app for a device of its own for now, and this one has \(Parts.name(of: .device, integration: other.target.integration)). "
                                    + "If the person wants this device's app instead, take that one away with remove_app, then ask again."))
        }
        let same = members.filter { $0.target.code == target.code }
        if let member = same.first(where: \.isMade) ?? same.first { return .success(.update(member, to: target)) }
        return .success(.add(target))
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

    /// `remove_app`: a made app taken away, or a waiting one taken off the list. Never the wish's only made app.
    static func remove(_ named: String, in members: [WishMember], table: [Place] = Places.all,
                       describe: (WishMember) -> String) -> Result<AppPlan, Refusal> {
        let listed = members.map(describe).joined(separator: ", ")
        switch find(named, in: members, table: table) {
        case .none:
            return .failure(Refusal("The wish has no app \"\(named)\". Its apps: \(listed). Name one by its folder or a device it's on."))
        case .several(let found):
            return .failure(Refusal("\"\(named)\" is more than one of the wish's apps: \(found.map(describe).joined(separator: ", ")). Name one by its folder."))
        case .one(let member):
            guard member.isMade else { return .success(.cancel(member)) }
            guard members.filter(\.isMade).count > 1 else {
                return .failure(Refusal("\(describe(member)) is the wish's only app, so it stays. To make it something else, use make_app_for."))
            }
            return .success(.remove(member))
        }
    }
}
