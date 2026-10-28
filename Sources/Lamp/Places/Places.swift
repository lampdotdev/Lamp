import Foundation

/// What each device can run, how a build gets onto it, and which make a game and an app on it get by default: one row
/// each. A build is one of two makes: **web**, a page shown by Lamp's host for the device's web engine (`PageHost`), or
/// **native**, the device's own code (Swift on Apple's, Kotlin on Android's, what an integration declares). A row claims
/// a make only once Lamp has a host or a recipe that builds it there (`PlacesTests`). Its defaults (`defaultMake`) are
/// what the agent picks when the person names no make: a make they name is theirs wherever a row runs it, and `made`
/// stays the agent's to give in every call, so a default never changes an app by itself.
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
    /// Which of Apple's families of device it is, where rows share a destination (`LampProject.family`), by the word it's
    /// named by: "ipad" is an iPad, "iphone" an iPhone, though both are the one row that runs them.
    var wordFamilies: [String: DeviceFamily] = [:]
    var families: Set<DeviceFamily> { Set(wordFamilies.values) }
    /// The row whose native app Lamp's build of it goes with, for now never alone: Lamp builds an Apple Watch app only
    /// beside an iPhone app. That's Lamp's recipe, not the device's limit.
    var comesWith: String? = nil
    /// Lamp's skills for designing what the device shows, offered to every app on it, whatever it is and however it's
    /// made (`Places.skills`): a TV's across-the-room design is the TV rows'.
    var skills: [String] = []
    /// Whether its `noWeb` is a gap of Lamp's own (the device shows pages, but Lamp has no host for one there yet) rather
    /// than something the device can't do, so "not yet" is never said as "can't".
    var noHostYet = false
    /// The same for its `noNative`: the device runs its own apps, but Lamp has no recipe that builds one there yet.
    var noRecipeYet = false
    /// The make a game, and an app, on this device alone get when the person names none (`defaultMake`): a game is a
    /// page on Lamp's game runtime wherever Lamp has a host for one; an app is the device's own code on a Mac, a phone or a
    /// tablet, and a page on a TV or a console. Always a make the row runs (`PlacesTests`).
    var gameDefault: Make = .web
    var appDefault: Make = .native
    /// What a game's page on it is told about it (`GamePage`), so the game names a key or a button the way the player's
    /// own does; nil when Lamp doesn't know, which a page there can't be built without.
    let input: Input?

    /// The device's input as a game's page is told it. Every field is a fact about the device; one left out is what a
    /// web view with a PC keyboard and no controller of its own has (`generic`).
    struct Input: Hashable, Codable {
        /// What its keyboard prints on a key whose name differs between keyboards, by the key's `KeyboardEvent.code`; a
        /// key not named here is called what a PC keyboard calls it.
        var keys: [String: String]? = nil
        /// The controller that comes with it, by its layout's id in `Controllers`: a game there starts on it, until the
        /// player takes up something else.
        var controller: String? = nil
        /// The one controller layout the device's host supports, by its id in `Controllers`: a game there names every
        /// controller's buttons by it, whatever the controller reports itself as. nil where the controller's own report
        /// says which it is.
        var layout: String? = nil

        static let generic = Input()
        /// A keyboard that may be anyone's (a page published to the web): each key keyboards name differently named
        /// both ways. The spaces around the slash don't break, so a keycap draws the name as one key.
        static let anyKeyboard = Input(keys: ["Enter": "Enter\u{A0}/\u{A0}Return", "Backspace": "Backspace\u{A0}/\u{A0}Delete",
                                              "AltLeft": "Alt\u{A0}/\u{A0}Option", "AltRight": "Alt\u{A0}/\u{A0}Option",
                                              "MetaLeft": "Win\u{A0}/\u{A0}⌘", "MetaRight": "Win\u{A0}/\u{A0}⌘"])
        static let apple = Input(keys: ["Enter": "Return", "Backspace": "Delete", "AltLeft": "Option", "AltRight": "Option",
                                        "MetaLeft": "⌘", "MetaRight": "⌘"])
    }

    func reach(_ make: Make) -> String? { make == .web ? web?.reach : native?.reach }
    func defaultMake(_ intent: AppIntent) -> Make { intent == .game ? gameDefault : appDefault }
    func runs(_ make: Make) -> Bool { reach(make) != nil }
}

/// Lamp's hosts for a page, one per web engine. Every kind whose app is a page (a web game, a screen) goes wherever
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
              native: .init(code: .apple, reach: "right away: Lamp builds it here"), input: .apple),
        Place(id: "iphone", name: "iPhone / iPad", words: ["iphone", "ipad"], destination: .ios,
              web: .init(host: .webKit, reach: "in an app of Lamp's around the page, the same way as a native app"),
              native: .init(code: .apple, reach: "in the simulator on this Mac, or on the person's own iPhone or iPad paired with this Mac, one device at a time"),
              wordFamilies: ["iphone": .iphone, "ipad": .ipad], input: .apple),
        Place(id: "watch", name: "Apple Watch", words: ["watch"], destination: .ios, web: nil,
              native: .init(code: .apple, reach: "Lamp doesn't build a Watch app on its own yet: its Watch build goes with an iPhone app, onto the watch paired with that iPhone"),
              noWeb: "watchOS has no web view, so a page there needs a native version", comesWith: "iphone", gameDefault: .native, input: nil),
        Place(id: "apple-tv", name: "Apple TV", words: ["apple-tv"], destination: .ios, web: nil,
              native: .init(code: .apple, reach: "in the Apple TV simulator on this Mac; Lamp can't put it on a real Apple TV yet"),
              noWeb: "tvOS has no web view, so a page there needs a native version", wordFamilies: ["apple-tv": .appletv],
              skills: ["tv-design"], gameDefault: .native, input: nil),
        Place(id: "vision-pro", name: "Vision Pro", words: ["vision-pro"], destination: .ios, web: nil,
              native: .init(code: .apple, reach: "in the Vision Pro simulator on this Mac; Lamp can't put it on a real Vision Pro yet"),
              noWeb: "Lamp has no host for a page on Vision Pro yet, so a page there needs a native version", wordFamilies: ["vision-pro": .vision],
              noHostYet: true, gameDefault: .native, input: .apple),
        Place(id: "android", name: "Android phone / tablet", words: ["android"], destination: .android,
              web: .init(host: .androidWebView, reach: "in an app of Lamp's around the page, the same way as a native app"),
              native: .init(code: .android, reach: "in the Android emulator on this Mac, or on the person's own device with USB debugging, one device at a time"),
              input: .generic),
        Place(id: "android-tv", name: "Android TV / Google TV / Fire TV", words: ["android-tv"], destination: .androidTV,
              web: .init(host: .androidWebView, reach: "in the same app of Lamp's around the page as on Android phones, on the TV's home screen: in the TV emulator on this Mac, or on the person's TV over Wi‑Fi"),
              native: .init(code: .androidTV, reach: "in the TV emulator on this Mac, or Lamp installs it on each of the person's TVs over Wi‑Fi"),
              skills: ["tv-design"], appDefault: .web, input: .generic),
        Place(id: "tv", name: "Samsung / LG TV", words: ["tv"], destination: .tv,
              web: .init(host: .tvBrowser, reach: "Lamp installs it on each of the person's TVs once it's set up for apps (in the TV preview on this Mac before that)"),
              native: nil, noNative: "Lamp has no recipe for a native Samsung or LG TV app yet", skills: ["tv-design"],
              noRecipeYet: true, appDefault: .web, input: .generic),
    ]

    /// Where a page can open: every place one of Lamp's web hosts is, in the table's order, and last an integration's own
    /// host (the Xbox's). A kind whose app is a page takes these as its places, so a new host is a new place for every
    /// page at once.
    static let pagePlaces: [Destination] = {
        var places: [Destination] = []
        for place in builtIn where place.web != nil && !places.contains(place.destination) { places.append(place.destination) }
        return places + [.device]
    }()

    /// The rows a page can't go to, each with its own reason (`noWeb`, `noHostYet`): every row with no web host, built in
    /// or an integration's, said where a page's places are offered.
    static func noPage(in table: [Place] = all) -> [Place] { table.filter { !$0.runs(.web) } }

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
                     // The device's own words for what it runs, when it says, so a refusal is the real reason.
                     noWeb: integration.runs.map { $0 + ", so a page there needs a native version" } ?? "it has no web engine Lamp can reach, so a page there needs a native version", noNative: integration.runs ?? "its integration declares no native app",
                     // A device that doesn't say what it runs may well run its own apps: Lamp only has no recipe for one.
                     skills: integration.skills ?? [], noRecipeYet: integration.runs == nil,
                     // A console or a TV's own platform: a page wherever it takes one (the Xbox's), its own code otherwise (a Roku's).
                     gameDefault: makes.contains(.web) ? .web : .native, appDefault: makes.contains(.web) ? .web : .native,
                     input: integration.input)
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

    /// The skills the rows an app is on offer it, each once, in the table's order: what every app on a TV is offered
    /// for designing what it shows there, whichever kind it is and however it's made.
    static func skills(rows: Set<String>, in table: [Place] = all) -> [String] {
        var skills: [String] = []
        for place in table where rows.contains(place.id) { for skill in place.skills where !skills.contains(skill) { skills.append(skill) } }
        return skills
    }

    /// The make a game or an app on these devices gets when the person names none: one device's own default, and for
    /// one app across several, web where every one of them takes a page. Nil where they share no default (an app on a
    /// Mac and an Apple TV is native on both, an app on a Mac and a Samsung TV web on one and native on the other), so
    /// it's for the agent to say, or to ask, rather than read off the table.
    static func defaultMake(_ intent: AppIntent, devices: Set<String>, in table: [Place] = all) -> Place.Make? {
        let rows = devices.compactMap { named($0, in: table) }
        guard !rows.isEmpty else { return nil }
        if rows.count == 1 { return rows[0].defaultMake(intent) }
        if rows.allSatisfy({ $0.runs(.web) }) { return .web }
        let each = Set(rows.map { $0.defaultMake(intent) })
        return each.count == 1 ? each.first : nil
    }

    static func named(_ word: String, in table: [Place] = all) -> Place? {
        let word = word.trimmed.lowercased()
        return table.first { $0.id == word || $0.words.contains(word) }
    }

    // MARK: What the agent is told

    /// The table as `make_app_for`'s description gives it (`{{PLACES}}`): one line per device.
    static var forAgent: String {
        all.map { place in
            let web = place.web.map { "web: \($0.reach)" } ?? "no web (\(place.noWeb ?? "none"))"
            let native = place.native.map { "native (\($0.code.rawValue) code): \($0.reach)" } ?? "no native (\(place.noNative ?? "none"))"
            return "\(place.name) [\(place.words.map { "\"\($0)\"" }.joined(separator: ", "))]: \(web); \(native); "
                + "by default a game \(place.gameDefault.rawValue), an app \(place.appDefault.rawValue)"
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

    /// Why an app of this make can't be on these devices, quoting each row that refuses it, and saying which refusals are
    /// Lamp's own gaps rather than the device's (`noHostYet`, `noRecipeYet`); nil when every one runs it.
    /// A word no row has is left to the caller, which already says what it doesn't know.
    static func refusal(make: Place.Make, devices: Set<String>, in table: [Place] = all) -> String? {
        let refused = devices.sorted().compactMap { named($0, in: table) }.filter { !$0.runs(make) }
        guard !refused.isEmpty else { return nil }
        return refused.map { place in
            let why = make == .web ? place.noWeb : place.noNative
            let yet = make == .web ? place.noHostYet : place.noRecipeYet
            let other = make == .web ? place.native.map { "; it runs a native app: \($0.reach)" } : place.web.map { "; it runs a web app: \($0.reach)" }
            // A gap of Lamp's own is said as Lamp's, so the agent never tells the person their device can't do it.
            let refused = yet ? "Lamp can't build a \(make.rawValue) app for \(place.name) yet" : "\(place.name) can't run a \(make.rawValue) app"
            return "\(refused) (\(why ?? "Lamp has no way to build one there"))\(other ?? "")."
        }.joined(separator: " ")
    }
}
