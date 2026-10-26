import Foundation

/// What each device can run, and how a build gets onto it: facts about devices, one row each, never a preference. A
/// build is one of two makes: **web**, a page shown by Lamp's host for the device's web engine (`PageHost`), or
/// **native**, the device's own code (Swift on Apple's, Kotlin on Android's, what an integration declares). Which make and which devices an app gets is the agent's choice; this table only says what
/// can exist, so a row claims a make only once Lamp has a host or a recipe that builds it there (`PlacesTests`).
///
/// The rows are shown to the agent as text (`forAgent`, in `make_app_for`'s description) and checked when it asks for
/// an app (`refusal`), so a device that can't run a make is refused with the row's reason before anything is built.
/// A device reached through an integration writes its own row in its JSON (`supports`, beside its `app`).
struct Place: Equatable {
    enum Make: String, CaseIterable {
        case web, native
    }

    /// The native code a row's native build is written in; rows of one code share it (one Swift code for the Mac, the
    /// iPhone, the Apple TV and Vision Pro).
    enum NativeCode: String {
        case apple, android, androidTV = "android-tv", integration
    }

    struct Native: Equatable {
        let code: NativeCode
        /// How a native build gets onto the device.
        let reach: String
    }

    /// A page's way onto the device: the host it's shown in, and how a build gets there.
    struct Web: Equatable {
        let host: PageHost
        let reach: String
    }

    let id: String
    let name: String
    /// How `make_app_for` and the naming call name it.
    let words: [String]
    /// Where its build opens.
    let destination: Destination
    /// The host a page is shown in there, and how a web build gets onto it; nil when there's none.
    let web: Web?
    let native: Native?
    /// Why it has no web build or no native build, said when one is asked for.
    var noWeb: String? = nil
    var noNative: String? = nil

    func reach(_ make: Make) -> String? { make == .web ? web?.reach : native?.reach }
    func runs(_ make: Make) -> Bool { reach(make) != nil }
}

/// Lamp's hosts for a page, one per web engine. Every kind whose app is a page (a three.js game, a screen) goes wherever
/// one of these is (`Places.pagePlaces`), from the same files, and nowhere else: a device with no web engine Lamp can
/// reach (the Apple TV, the Apple Watch, a Roku) has no row with a host, and a page there needs a native version.
enum PageHost: String, Equatable {
    /// WebKit, in an app of Lamp's around the page on the Mac, the iPhone and the iPad (LampPage.swift, with
    /// LampWebGame.swift or LampScreen.swift).
    case webKit
    /// Android's WebView, in an app of Lamp's around the page on phones, tablets, photo frames and TVs (`GameAndroid`): one
    /// app for all of them, on a TV's home screen as on a phone's.
    case androidWebView
    /// The TV's own browser engine, Tizen's on a Samsung and webOS's on an LG, in the TV app's package (`TVs`).
    case tvBrowser
    /// The integration's own host for its web apps (the Xbox's, WebView2: `WebHost`).
    case integration
}

enum Places {
    /// The devices Lamp knows without an integration, in the order they're shown.
    static let builtIn: [Place] = [
        Place(id: "mac", name: "This Mac", words: ["mac"], destination: .mac,
              web: .init(host: .webKit, reach: "right away: Lamp builds an app of its own around the page here"),
              native: .init(code: .apple, reach: "right away: Lamp builds it here")),
        Place(id: "iphone", name: "iPhone / iPad", words: ["iphone", "ipad"], destination: .ios,
              web: .init(host: .webKit, reach: "in an app of Lamp's around the page, the same way as a native app"),
              native: .init(code: .apple, reach: "in the simulator on this Mac, or on the person's own iPhone or iPad paired with this Mac, one device at a time")),
        Place(id: "watch", name: "Apple Watch", words: ["watch"], destination: .ios, web: nil,
              native: .init(code: .apple, reach: "with the iPhone app, onto the watch paired with that iPhone"),
              noWeb: "watchOS has no web view, so a page there needs a native version"),
        Place(id: "apple-tv", name: "Apple TV", words: ["apple-tv"], destination: .ios, web: nil,
              native: .init(code: .apple, reach: "in the Apple TV simulator on this Mac; Lamp can't put it on a real Apple TV yet"),
              noWeb: "tvOS has no web view, so a page there needs a native version"),
        Place(id: "vision-pro", name: "Vision Pro", words: ["vision-pro"], destination: .ios, web: nil,
              native: .init(code: .apple, reach: "in the Vision Pro simulator on this Mac; Lamp can't put it on a real Vision Pro yet"),
              noWeb: "Lamp has no host for a page on Vision Pro yet, so a page there needs a native version"),
        Place(id: "android", name: "Android phone / tablet", words: ["android"], destination: .android,
              web: .init(host: .androidWebView, reach: "in an app of Lamp's around the page, the same way as a native app"),
              native: .init(code: .android, reach: "in the Android emulator on this Mac, or on the person's own device with USB debugging, one device at a time")),
        Place(id: "android-tv", name: "Android TV / Google TV / Fire TV", words: ["android-tv"], destination: .androidTV,
              web: .init(host: .androidWebView, reach: "in the same app of Lamp's around the page as on Android phones, on the TV's home screen: in the TV emulator on this Mac, or on the person's TV over Wi‑Fi"),
              native: .init(code: .androidTV, reach: "in the TV emulator on this Mac, or Lamp installs it on each of the person's TVs over Wi‑Fi")),
        Place(id: "tv", name: "Samsung / LG TV", words: ["tv"], destination: .tv,
              web: .init(host: .tvBrowser, reach: "Lamp installs it on each of the person's TVs once it's set up for apps (in the TV preview on this Mac before that)"),
              native: nil, noNative: "Lamp makes no native apps for Samsung or LG TVs"),
    ]

    /// Where a page can open: every place one of Lamp's web hosts is, in the table's order, and last an integration's own
    /// host (the Xbox's). A kind whose app is a page takes these as its places, so a new host is a new place for every
    /// page at once.
    static let pagePlaces: [Destination] = {
        var places: [Destination] = []
        for place in builtIn where place.web != nil && !places.contains(place.destination) { places.append(place.destination) }
        return places + [.device]
    }()

    /// The words a page's places are given by (`make_app_for`'s `places`, the naming call's), each with where it opens:
    /// every row with a host, and the Xbox's words, whose integration hosts it.
    static var pageWords: [String: Destination] {
        var words: [String: Destination] = [:]
        for place in builtIn where place.web != nil { for word in place.words { words[word] = place.destination } }
        for word in [GameKit.xbox, GameKit.xboxKind, "xbox"] { words[word] = .device }
        return words
    }

    /// The screens across a room that have no web engine Lamp can reach (the Apple TV, and a device such as a Roku whose
    /// integration makes only native apps), said where a page's places are offered: a page there needs a native version.
    static var noPage: [Place] { all.filter { !$0.runs(.web) && ($0.id == "apple-tv" || $0.destination == .device) } }

    /// A page's places as the agent is told them (`make_app_for`'s `{{PAGE_PLACES}}`, a game's and a screen's rules): each
    /// place's words and device, then the screens across a room it can't go to, and why.
    static var pageList: String {
        let words = all.filter { $0.web != nil && $0.id != "mac" }.map { place in
            place.words.map { "\"\($0)\"" }.joined(separator: " or ") + " (\(place.name))"
        }
        let none = noPage.map(\.name)
        return words.joined(separator: ", ") + (none.isEmpty ? "" : ". " + sentence(none)
            + " \(none.count == 1 ? "has" : "have") no web engine, so a game or a screen can't go there: it needs a native version, an app of its own")
    }

    private static func sentence(_ items: [String]) -> String {
        items.count < 2 ? items.joined() : items.dropLast().joined(separator: ", ") + " and " + items.last!
    }

    /// Every row: the built-in devices, then each integration that declares apps, as its JSON says.
    static var all: [Place] { builtIn + Integrations.all().compactMap(row(for:)) }

    /// An integration's row: what its `supports` says, or what its `app` declares when it says nothing.
    static func row(for integration: Integration) -> Place? {
        guard let declared = integration.app?.declared else { return nil }
        let makes = supports(integration) ?? [declaredMake(declared)]
        let reach = "Lamp installs it on each of the person's \(integration.name) devices once it's set up"
        return Place(id: integration.id, name: integration.name, words: [integration.id], destination: .device,
                     web: makes.contains(.web) ? .init(host: .integration, reach: reach) : nil,
                     native: makes.contains(.native) ? .init(code: .integration, reach: reach) : nil,
                     noWeb: "it has no web engine Lamp can reach, so a page there needs a native version", noNative: "its integration declares no native app")
    }

    /// The makes an integration's `supports` names, or nil when it names none (or one Lamp doesn't know).
    static func supports(_ integration: Integration) -> Set<Place.Make>? {
        guard let words = integration.supports, !words.isEmpty else { return nil }
        let makes = Set(words.compactMap(Place.Make.init(rawValue:)))
        return makes.count == words.count ? makes : nil
    }

    /// What an integration's declared app is: a page when Lamp's web building blocks go in it or Lamp previews its
    /// page, the device's own code otherwise.
    static func declaredMake(_ declared: Integration.AppKind.Declared) -> Place.Make {
        declared.support?["web"] != nil || declared.preview != nil || declared.host != nil ? .web : .native
    }

    static func named(_ word: String) -> Place? {
        let word = word.trimmed.lowercased()
        return all.first { $0.id == word || $0.words.contains(word) }
    }

    // MARK: What the agent is told

    /// The table as `make_app_for`'s description gives it (`{{PLACES}}`): one line per device.
    static var forAgent: String {
        all.map { place in
            let web = place.web.map { "web: \($0.reach)" } ?? "no web (\(place.noWeb ?? "none"))"
            let native = place.native.map { "native (\($0.code.rawValue) code): \($0.reach)" } ?? "no native (\(place.noNative ?? "none"))"
            return "\(place.name) [\(place.words.map { "\"\($0)\"" }.joined(separator: ", "))]: \(web); \(native)"
        }.joined(separator: ". ") + "."
    }

    /// The row a device of the person's is: what it can run.
    static func row(for device: Device) -> Place? {
        let id: String? = switch device.kind {
        case .iphone, .ipad: "iphone"
        case .watch: "watch"
        case .android: device.features.contains("tv") ? "android-tv" : "android"
        case .samsungTV, .lgTV: "tv"
        case .other: device.integration
        case .mac, .androidEmulator: nil
        }
        return id.flatMap { id in all.first { $0.id == id } }
    }

    /// The person's own devices Lamp knows of, each with its row, for the device line (`DeviceNote`): empty when it knows
    /// of none.
    static func known(_ devices: [Device]) -> String {
        let named = devices.compactMap { device in row(for: device).map { "\(device.name) (\($0.name))" } }
        guard !named.isEmpty else { return "" }
        return "The person's own devices Lamp knows of: " + named.joined(separator: ", ") + "."
    }

    // MARK: Checking a request

    /// Why an app of this make can't be on these devices, quoting each row that refuses it; nil when every one runs it.
    /// A word no row has is left to the caller, which already says what it doesn't know.
    static func refusal(make: Place.Make, devices: Set<String>) -> String? {
        let refused = devices.sorted().compactMap(named).filter { !$0.runs(make) }
        guard !refused.isEmpty else { return nil }
        return refused.map { place in
            let why = make == .web ? place.noWeb : place.noNative
            let other = make == .web ? place.native.map { "; it runs a native app: \($0.reach)" } : place.web.map { "; it runs a web app: \($0.reach)" }
            return "\(place.name) can't run a \(make.rawValue) app (\(why ?? "Lamp has no way to build one there"))\(other ?? "")."
        }.joined(separator: " ")
    }

    // MARK: Today's kinds in these terms

    /// What an app of a stored kind is: its make and the devices (rows) it's on. A kind's places beyond its home are
    /// given by their words (`Parts.AppAsked.places`); an integration's kind is that integration's row.
    static func model(of kind: Platform, places: Set<String> = [], integration: String? = nil) -> (make: Place.Make, devices: Set<String>) {
        let others = Set(places.compactMap { Places.named($0)?.id })
        switch kind {
        case .mac: return (.native, Set(["mac"]).union(others))
        case .iphone: return (.native, Set(["iphone"]).union(others))
        case .universal: return (.native, Set(["mac", "iphone"]).union(others))
        case .android: return (.native, ["android"])
        case .androidTV: return (.native, ["android-tv"])
        case .tv: return (.web, ["tv"])
        case .game, .screen: return (.web, Set(["mac"]).union(others))
        default:
            let id = integration.map { DeviceApps.split($0).integration }
            let row = id.flatMap { id in all.first { $0.id == id } }
            return (row?.runs(.web) == true ? .web : .native, Set([row?.id].compactMap { $0 }))
        }
    }

    /// The kinds Lamp has today that build this make on these devices, the most particular first. Web on the Mac (a
    /// game or a screen) is told apart by the folder's own mark, as it is now, not by its devices.
    static func kinds(make: Place.Make, devices: Set<String>) -> [Platform] {
        let apple: Set<String> = ["mac", "iphone", "watch", "apple-tv", "vision-pro"]
        switch make {
        case .native:
            if devices == ["android"] { return [.android] }
            if devices == ["android-tv"] { return [.androidTV] }
            if !devices.isEmpty, devices.isSubset(of: apple) {
                if devices.contains("mac") && devices.count > 1 { return [.universal] }
                return devices.contains("mac") ? [.mac] : [.iphone]
            }
            if devices.count == 1, let row = all.first(where: { $0.id == devices.first }), row.destination == .device { return [.device] }
            return []
        case .web:
            if devices == ["tv"] { return [.tv] }
            let reached = Set(devices.compactMap { word in all.first { $0.id == word }?.destination })
            return [Platform.game, .screen, .device].filter { kind in
                guard !devices.isEmpty, reached.isSubset(of: Set(kind.target.places)) else { return false }
                // A device app is one integration's, alone; a game and a screen are at home on the Mac.
                return kind == .device ? reached == [.device] && devices.count == 1 : true
            }
        }
    }
}
