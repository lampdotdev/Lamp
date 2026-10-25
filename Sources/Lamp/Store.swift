import SwiftUI
import LampSidebarKit
import CryptoKit
import Security
import AppKit
import Network
import LampFileLook

/// Where an app is built for and opened: this Mac, iOS (a simulator, or the person's phone, by
/// `LampProject.family` and `device`), Android (the emulator, or the person's device by `device`), a TV (the TV
/// preview, or the person's TV) or a device through its integration. Each kind says where it can open
/// (`Target.places`); a Mac app, an iPhone app or an Android app has one; an app for both has the one Try On last
/// chose. How Lamp builds, opens, looks at, uses and quits an app goes by this, so a kind that opens where another
/// does gets all of that.
enum Destination: String, Codable {
    case mac, ios, android, tv, device

    /// Where the person's own devices are found to open on (phones, Android devices, TVs), so Lamp looks for them as
    /// it starts when an app could open on one.
    var listsDevices: Bool { self == .ios || self == .android || self == .tv }
}

/// Which simulator an iOS app opens on. The app itself is built for iPhone and iPad together; Apple TV and Vision Pro
/// are the same SwiftUI app built for tvOS or visionOS when Try On points at one of them.
enum DeviceFamily: String, Codable {
    case iphone, ipad, appletv, vision
    var name: String {
        switch self {
        case .iphone: "iPhone"
        case .ipad: "iPad"
        case .appletv: "Apple TV"
        case .vision: "Apple Vision Pro"
        }
    }
    /// What the simulator runs, as people call it and as simctl names its runtimes.
    var os: String { self == .appletv ? "tvOS" : self == .vision ? "visionOS" : "iOS" }
    var runtimeKey: String { self == .appletv ? "SimRuntime.tvOS-" : self == .vision ? "SimRuntime.xrOS-" : "SimRuntime.iOS-" }
    /// The oldest version of it the apps are built for.
    var minimum: Int { self == .vision ? 1 : 17 }
    var symbol: String { self == .appletv ? "appletv" : self == .vision ? "visionpro" : self == .ipad ? "ipad" : "iphone" }
    /// Not iPhone and iPad: built for another SDK, from the same code (build.sh's LAMP_FAMILY).
    var isOtherOS: Bool { self == .appletv || self == .vision }
}

struct LampProject: Identifiable, Hashable {
    let id: String      // folder name; also used in lamp:// links
    let name: String    // display name
    let exe: String     // Swift target / executable name
    let dir: URL
    /// Where the app's folder really is: the folders above it worked out (they're Lamp's), the folder itself
    /// taken by its name. The agent may write at that name, so it can swap the folder for a link to anywhere,
    /// Lamp's own folder included; what is opened or trusted as the app's must never follow that link.
    var realDir: URL {
        let named = dir.standardizedFileURL
        // A part's folder is inside its wish's, which is the agent's to write: only the folders above the wish are
        // worked out, the wish's folder and the part's taken by their names (`AppFolder.way`).
        if partOf != nil {
            let wish = named.deletingLastPathComponent()
            return wish.deletingLastPathComponent().resolvingSymlinksInPath()
                .appendingPathComponent(wish.lastPathComponent).appendingPathComponent(named.lastPathComponent)
        }
        let way = AppFolder.way(to: named)
        return way.steps.reduce(way.above) { $0.appendingPathComponent($1) }
    }

    /// Who this app is, whatever its folder is called: given when it's made and kept through renames, so
    /// something started on a draft still finds the app it became, and a later draft that takes the same
    /// folder name is a different app. Apps from before it existed use their folder name.
    var instance: String = ""
    /// Made with New and not named yet. The first message names it.
    var untitled = false
    /// Made by a wish that came from the site (`Wish`): until it has a name it reads as their wish.
    var fromWish = false
    /// Started with "Help me find one": the agent asks about the person's days and writes a wish into the message
    /// box (`write_wish`). Nothing is named or built until that wish, or one of their own, is sent.
    var finding = false
    /// A device's setup conversation (`Store.setUpDevice`), by the device's id as it was found: no wish and no app.
    /// It's never named, scaffolded, built or saved, never on the desk, and the agent in it has only the tools for
    /// the device's integration.
    var deviceSetup: String?
    var platform: Platform = .mac
    /// A device app's integration (`Platform.device`), by its id: what it's made as and how it gets on the device. An
    /// app that's one of the integration's further kinds has the kind after a colon ("xbox-one:game", `DeviceApps.split`).
    var integration: String?
    /// The integration's own id, without the kind: what its devices are found by.
    var deviceIntegration: String? { integration.map { DeviceApps.split($0).integration } }
    var family: DeviceFamily = .iphone
    /// The person's own iPhone or iPad that Play puts the app on (Devices), instead of the simulator.
    var device: String?
    /// For an app made for both: where Try On last put it. Meaningless for the other kinds, which have one place.
    var chosen: Destination = .mac
    /// Where it has been given to open, of the places its kind can (`Target.places`), for a kind whose places are given
    /// one at a time (`Platform.addsPlaces`: a game, on the Mac first, then an iPhone or iPad and an Xbox when they're
    /// asked for). Nil for the kind's own start (`Target.startsAt`). Adding a place never changes what the app is.
    var places: [Destination]?
    /// For a kind written for one of several engines, which (a game's: "web", three.js, or "native", C++ on the kit),
    /// until its folder's own mark says so (`GameKit.engine`).
    var engine: String?
    /// iOS apps: the simulator chosen by name under Try On (its udid), or nil for Lamp's own pick of the family.
    var simulator: String?
    /// For a part of a wish (a TV app's iPhone app, say): the wish's id. A part is an app of its own kind in a folder
    /// of the wish's (`partFolders`, `Parts`), built, opened, looked at and used as any app of its kind is, but it has no
    /// chat, no history and no place on the desk of its own: the wish's turn works on it, the wish's versions keep it.
    var partOf: String?
    /// The folders of this wish's other parts, each an app of its own kind (`partOf`), beside the one at its root.
    var partFolders: [String] = []
    /// A new wish that could be for more than one kind of device, and didn't say which (the naming call's
    /// candidates, most likely first): nothing is written for it until the agent has asked and given it its kinds.
    var undecided: [String]?
    /// The apps this wish should have (`WishApp`, `Parts.wanted`): the one at its root and its other parts, each with
    /// what stops it while it isn't made yet. Kept in the wish's meta.json, so a quit or a failure between asking for
    /// an app and making it loses nothing. Empty for a wish from before wishes kept the list, which has what its folder holds.
    var apps: [WishApp] = []
    /// A new wish for a device Lamp can't make apps for yet: nothing is written for it until the agent has set the
    /// device up and given the wish its kind (`Store.convert`).
    var waitsForDevice = false
    /// Given its kinds in a turn begun without any (`undecided`): each engine's conversation began with the prompt for
    /// no kind, so it's forgotten once that turn ends, or at Lamp's next start if Lamp quit before it did.
    var decided = false
    var isPart: Bool { partOf != nil }

    /// The same app named, and for a draft moved: everything else it is (its kind, its other parts, whether it's still
    /// to be told what it's for, where it opens) comes along. Named, it's no longer untitled, a wish from the site or
    /// one being found.
    func named(_ name: String, id: String? = nil, exe: String? = nil, dir: URL? = nil) -> LampProject {
        LampProject(id: id ?? self.id, name: name, exe: exe ?? self.exe, dir: dir ?? self.dir, instance: instance,
                    deviceSetup: deviceSetup, platform: platform, integration: integration, family: family, device: device,
                    chosen: chosen, places: places, engine: engine, simulator: simulator, partOf: partOf, partFolders: partFolders, undecided: undecided,
                    apps: apps, waitsForDevice: waitsForDevice, decided: decided)
    }
    /// Where the app can open now: its kind's places, or for a kind whose places are given one at a time, those it was
    /// given (never empty: a meta.json can say anything, and the kind's start stands in for nothing).
    var openPlaces: [Destination] {
        let target = platform.target
        guard let start = target.startsAt else { return target.places }
        let given = (places ?? start).filter(target.places.contains)
        return given.isEmpty ? start : given
    }
    /// What the app can have, as its kind's `hasMac`…: a kind whose places are given one at a time has only those it
    /// was given, so a game played on the Mac alone asks nothing of iOS, and a TV app shown on its TV alone is no Mac app.
    var hasMac: Bool { openPlaces.contains(.mac) }
    var hasIOS: Bool { openPlaces.contains(.ios) }
    var hasAndroid: Bool { openPlaces.contains(.android) }
    var hasTV: Bool { openPlaces.contains(.tv) }
    var hasDevice: Bool { openPlaces.contains(.device) }
    /// Where the app is built for and opened now.
    var destination: Destination {
        let places = openPlaces
        return places.contains(chosen) ? chosen : places[0]
    }
    /// On iOS now: the simulator, or the person's phone. The rest of Lamp's phone work follows this, and an
    /// app for both goes through it only while that's where it opens.
    var onIOS: Bool { destination == .ios }
    /// An Android app: the emulator, or the person's own Android device (`device`, its adb serial).
    var onAndroid: Bool { destination == .android }
    /// A TV app: the TV preview on this Mac, or one of the person's TVs (`device`, its id in `TVs`).
    var onTV: Bool { destination == .tv }
    /// An app for a device of the person's that Lamp reaches through its integration (`device`, the device's id there).
    var onDevice: Bool { destination == .device }
    /// An app for both is registered with Apple under the person's team on the Mac too, so its one id
    /// carries the team everywhere, as a phone build's does (`deviceBundleID`).
    var bundleID: String {
        let plain = Edition.appBundlePrefix + id
        guard platform == .universal, !Devices.team.isEmpty else { return plain }
        return plain + "." + Devices.team.lowercased()
    }
    /// On a phone the app is registered with Apple under the person's team, so the id carries the team:
    /// another team may have registered the plain one for the same app name.
    func deviceBundleID(team: String) -> String { platform == .universal ? bundleID : bundleID + "." + team.lowercased() }
    /// An app for both keeps a build for each place, so checking one half never replaces the other's.
    var builtURL: URL { platform.target.recipe.builtURL(self) }
    /// Every successful build is copied here so it shows up in Spotlight and Launchpad.
    /// Where it's installed follows from its wish's name and its kind alone, nothing kept beside it, so a copy of the
    /// wish, a restore and its other apps coming and going never move it or put two apps in one place: wishes' names are
    /// unique, a wish has one app of each kind, and a game or a screen goes in a folder of its kind's (`installFolder`).
    var installedURL: URL {
        (platform.target.installFolder.map { Store.installDir.appendingPathComponent($0) } ?? Store.installDir)
            .appendingPathComponent("\(name).app")
    }
    /// Where a game or a screen was installed before it had a folder of its own (`Store.reload` moves it).
    var installedBeforeFolders: URL? { platform.target.installFolder.map { _ in Store.installDir.appendingPathComponent("\(name).app") } }
    /// What the app is called on screen. An unnamed one has only a stand-in name on disk ("Untitled", which
    /// its folder and everything that asks `untitled` go by), so the screen says what it is instead: a wish,
    /// theirs from the site or one still to be told. Nothing is an app until Lamp has made something; the
    /// name Lamp or the person gives it takes over everywhere at once.
    var title: String { !untitled ? name : fromWish ? "Your wish" : finding ? "Finding a wish" : "New wish" }
    var isDeviceSetup: Bool { deviceSetup != nil }
    /// Nothing here is an app yet, or ever: a wish being found, or a device's setup.
    var makesNoApp: Bool { finding || isDeviceSetup }
    /// False for a draft (Template.draft): a new app whose scaffold isn't written yet. A wish whose apps are all in
    /// folders of their own is no draft either, though its own folder holds no scaffold (`holdsApp`).
    var scaffolded: Bool { hasScaffold || !holdsApp }
    /// The folder holds the scaffold of an app of some kind.
    var hasScaffold: Bool { Targets.all.contains { $0.recipe.scaffolded(dir, self) } }
    /// Whether this folder is an app's: a part's always is, and a wish's is while it holds the app the wish began with
    /// (or is still to be made). A wish whose apps are all in folders of their own (that first app taken away or
    /// replaced) is only the wish: its name, chat, history and icon, with nothing of its own to build, open or quit.
    /// Read off its files each time, as its parts are, so an Undo that brings that app back has it again, and a copy of
    /// the wish made before its parts are listed is never taken for an app.
    var holdsApp: Bool { isPart || hasScaffold || Parts.folders(in: dir).isEmpty }
}

struct ProjectMeta: Codable {
    var name: String
    var exe: String
    var untitled: Bool?
    var platform: Platform?   // nil in apps made before iPhone apps existed: a Mac app
    var family: DeviceFamily?  // iOS apps: which simulator they open on; nil means iPhone
    var device: String?        // iOS apps: the person's own phone (its udid) that Play puts the app on, if any
    var target: Destination?   // apps for both: where Try On last put it; nil means the Mac
    var places: [Destination]? // LampProject.places
    var engine: String?        // LampProject.engine
    var simulator: String?     // iOS apps: the simulator chosen by name under Try On, if any
    var instance: String?      // LampProject.instance
    var wish: Bool?            // LampProject.fromWish
    var finding: Bool?         // LampProject.finding
    var deviceSetup: String?   // LampProject.deviceSetup
    var integration: String?   // LampProject.integration
    var undecided: [String]?   // LampProject.undecided
    var apps: [WishApp]?       // LampProject.apps: the apps the wish should have, and what each waits for
    var waitsForDevice: Bool?  // LampProject.waitsForDevice
    var decided: Bool?         // LampProject.decided
    var layout: Int?           // NewerWish.layout: said only by a wish whose own folder holds no app (`holdsApp`)
}

struct AppUsage: Codable {
    var calls = 0       // AI calls made by the app itself
    var cost = 0.0
    // Optional so usage.json files from before these were tracked still decode.
    var agentRuns: Int?
    var agentCost: Double?

    var totalCost: Double { cost + (agentCost ?? 0) }
}

struct LogLine: Identifiable, Codable, Equatable {
    /// `needsKey` is a setup offer from before offers named their capability: it was always about pictures.
    /// `drawIcon` offers to draw the app's icon in Image Playground; its text is the design it's for (`Icons.artKey`).
    /// `widget` is the card of an app that has a widget (`WidgetCard`): how to add it, then that it's there.
    /// `noted` is the receipt for a save of Lamp's notes (`NoteCard`).
    /// `ask` and `result` are the agent's own cards (`Talk`): questions to click through, and what a request
    /// made. Their text is the same in plain words.
    /// `iphoneSetup` says a first request that read as an iPhone app was made for the Mac, since this Mac can't
    /// build one yet, and offers the setup (`IPhoneSetupLine`); its text is the kind that was wanted.
    /// `progress` is the agent's line on how the work is going (`Talk`'s `progress`), folded with the turn's
    /// steps once it ends.
    /// `deviceStep` is a device's next setup step, drawn from its integration (`DeviceStepLine`); its text is the device's id.
    enum Kind: String, Codable { case user, agent, status, error, detail, tool, summary, needsKey, offer, noted, drawIcon, widget, ask, result, iphoneSetup, progress, reload, deviceStep }
    var id = UUID()
    let kind: Kind
    var text: String
    var attachments: [String]? = nil   // names in the app's Attachments/ folder
    var version: String? = nil         // for a request: the version it made
    var before: String? = nil          // for a request: the version the app was at when it was sent
    var replaced: String? = nil        // for a request sent again in other words: the request it took the place of
    var tookBack: [String]? = nil      // …and every request that left the chat for it, oldest first
    var retryPhone: String? = nil     // a phone install failure: retry this destination without the agent
    var offer: SetupOffer? = nil      // a setup offer: what it's about (its text is the reason)
    var ask: Talk.Ask? = nil          // the agent's questions, and what was clicked
    var fromCard: Bool? = nil         // for a request: it was clicked on the agent's card, which shows it
    var result: Talk.Result? = nil    // read from chats saved with a result card, which no longer shows
    var noted: NoteReceipt? = nil     // what a save of Lamp's notes changed, with Undo
    var pointed: PointedAt? = nil     // for a request: what was pointed at in the app, one of its attachments
    var midTurn: Bool? = nil          // for a request: the agent took it while working on the one before (Store.handOver)
    var byLamp: Bool? = nil           // for a request: Lamp sent it, not the person (`Store.fixCrash`); the line before says so
    var said: String? = nil           // for a command Lamp let run ("Ran: …"): what the agent said it was for (`AgentEvent.naming`)
    var at: Date? = nil               // when Lamp logged it, for how long a fold of steps took (`ChatItem.folds`); none in older chats
    var foldTitle: String? = nil      // for the first step of a fold: what the fold did, in a line (`StepTitles`)
    var failed: Bool? = nil           // for a step: it was tried and didn't work (`AgentEvent.ended`)
    var call: String? = nil           // for a command's row: the engine's id for its call, which its outcome comes back by
    var notRun: Bool? = nil           // for commands of one name gathered as one row (`ChatItem.items`): none of them ran
    var part: Int? = nil              // in a new app's first build: the part of the agent's plan it came in (`TurnProgress.chapter(for:)`)
    var plan: [String]? = nil         // for that build's summary: the plan's parts, which its chapters are named by (`Chapters`)

    /// A command's row stopped before it ran: by its own words, or, for commands gathered as one row, every one of them.
    var wasNotRun: Bool { notRun ?? text.hasPrefix(ChatLook.notRun) }

    /// The offer a setup card is about, for this line and for the older key card.
    var setupOffer: SetupOffer? {
        switch kind {
        case .offer: offer
        case .needsKey: SetupOffer(capability: .pictures)
        default: nil
        }
    }

    /// Where an offer stands in a chat: not made yet, made already, or made only as the card about the app's
    /// icon, which is answered (the person draws icons, or something draws them by Settings' choices) and
    /// folded away while the app's own pictures aren't. An offer that isn't about the icon then takes that
    /// card's place (the line at the index given).
    enum Standing: Equatable { case new, offered, replaces(Int) }
    static func standing(of offer: SetupOffer, in lines: [LogLine], iconAnswered: Bool) -> Standing {
        guard let index = lines.firstIndex(where: { $0.setupOffer == offer }) else { return .new }
        return iconAnswered && lines[index].setupOffer?.icon == true && offer.icon != true ? .replaces(index) : .offered
    }

    /// Whether a chat with these lines should get a line offering to draw the design `key`: not when it has
    /// one for that design already, nor when the card about the icon is there, which offers it itself.
    static func offersDrawing(_ key: String, after lines: [LogLine]) -> Bool {
        !lines.contains { $0.kind == .drawIcon && $0.text == key || $0.setupOffer?.icon == true }
    }

    /// What to do about offering to draw the design `key`: nothing (no built app yet, or it's offered
    /// already), hold it until the turn that has the app finishes, or put the line in the chat now.
    enum DrawingOffer: Equatable { case none, held, now }
    static func drawingOffer(_ key: String, after lines: [LogLine], built: Bool, inTurn: Bool) -> DrawingOffer {
        guard built, offersDrawing(key, after: lines) else { return .none }
        return inTurn ? .held : .now
    }

    /// Lamp knows where the app was before this request, so it can be changed and sent again from there.
    /// Not so for some requests from before that was noted.
    var canSendAgain: Bool { kind == .user && (before != nil || version != nil) }

    /// Hidden unless Agent Details is on.
    var isDetail: Bool { kind == .detail || kind == .tool || kind == .summary }

    /// "Worked for 4m 21s · $0.48", and "Worked for 4m 21s" when nothing was spent: a turn on a Claude or ChatGPT
    /// sign-in, or on this Mac's own model. Only OpenRouter's calls (pi's, and the pictures painted) cost money.
    static func workSummary(seconds: Double, cost: Double) -> String {
        let total = Int(seconds.rounded())
        let time = total < 60 ? "\(total)s" : "\(total / 60)m \(total % 60)s"
        return cost < 0.005 ? "Worked for \(time)" : String(format: "Worked for %@ · $%.2f", time, cost)
    }

    /// Older chats logged tool calls and run summaries as plain details, and named the engine in summaries.
    var upgraded: LogLine {
        guard kind == .detail || kind == .summary else { return self }
        if let match = text.firstMatch(of: #/^\S.* (?:done|error) · (\d+)s · \$([\d.]+)$/#),
           let seconds = Double(match.1), let cost = Double(match.2) {
            return LogLine(id: id, kind: .summary, text: Self.workSummary(seconds: seconds, cost: cost))
        }
        guard kind == .detail else { return self }
        if ToolCall(text).isKnown { return LogLine(id: id, kind: .tool, text: text) }
        return self
    }

    /// Reads an app's chat file a line at a time, so a line this Lamp can't read (a kind written by a newer Lamp,
    /// or a Lamp Dev built from another branch, sharing the same folder) costs that line and not the whole chat.
    /// The next save writes the chat without what was skipped, so the file as it was is kept beside it first, under
    /// a name nothing else uses (`chat.json.unreadable`, then `-2`…). When that copy can't be made (a full disk),
    /// `unkept` holds the file as it was, and nothing may write over it until `keepAside` has kept it.
    /// Nil when there is no file.
    static func readChat(_ file: URL) -> (lines: [LogLine], unkept: Data?)? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        let read = try? JSONDecoder().decode([Readable].self, from: data)
        let lines = read?.compactMap(\.line) ?? []
        let skipped = read == nil || lines.count < read!.count
        return (lines.map(\.upgraded), skipped && !keepAside(data, of: file) ? data : nil)
    }

    private struct Readable: Decodable {
        let line: LogLine?
        init(from decoder: Decoder) throws { line = try? LogLine(from: decoder) }
    }

    /// Keeps a chat file's bytes beside it, without overwriting any copy already there. True once they're kept.
    static func keepAside(_ data: Data, of file: URL) -> Bool {
        for n in 1... {
            let copy = file.deletingLastPathComponent()
                .appendingPathComponent(file.lastPathComponent + ".unreadable" + (n == 1 ? "" : "-\(n)"))
            // Without overwriting, which also refuses a link left where the copy goes.
            do { try data.write(to: copy, options: .withoutOverwriting); return true } catch {}
            if (try? Data(contentsOf: copy)) == data { return true }
            // Only a name already taken is worth trying the next one for; anything else (a full disk) fails them all.
            // (Looked at without following a link: a link there takes the name too.)
            if (try? FileManager.default.attributesOfItem(atPath: copy.path)) == nil { return false }
        }
        return false
    }
}

/// A message typed while the app was busy. It waits in the chat until the current work finishes.
struct QueuedMessage: Identifiable {
    let id = UUID()
    let text: String
    var attachments: [URL] = []
    /// The agent's card these answers were clicked on. The card shows them, so the chat doesn't say them
    /// again, and taking the message back before it's sent opens the card again (`Talk.unqueue`).
    var card: UUID? = nil
    /// Files already in the app's Attachments folder: those of a request that's sent again.
    var kept: [String] = []
    /// The request this one takes the place of, when it's one sent again in other words.
    var replaces: String? = nil
    /// Every request that left the chat when this one was sent, oldest first.
    var tookBack: [String] = []
    /// What was pointed at in the app, its picture going with the message besides `attachments`.
    var pointed: PointedAt? = nil
    /// The person pressed Send Now: it goes to the agent in the turn that's running (`Store.handOver`).
    var sendNow = false
    /// Lamp sent it on its own, to fix a crash (`Store.fixCrash`).
    var byLamp = false
    /// Lamp's own, carrying a paused request on once the person has pressed Reload (`Store.pause`): it waits in line
    /// until the held change is in, and so does everything sent behind it.
    var afterReload = false
}

extension QueuedMessage {
    /// A request waiting for setup, as it's kept across a relaunch. The card it answers is kept with it:
    /// without it the answer would come back as a message of its own under a card that already shows it,
    /// and taking it back would no longer open the card again.
    var saved: [String: Any] {
        var saved: [String: Any] = ["text": text, "attachments": attachments.map(\.path)]
        if let card { saved["card"] = card.uuidString }
        if byLamp { saved["byLamp"] = true }
        if afterReload { saved["afterReload"] = true }
        if let pointed, let picture = pointed.url {
            var target: [String: Any] = ["title": pointed.title, "picture": picture.path]
            if let detail = pointed.detail { target["detail"] = detail }
            saved["pointed"] = target
        }
        return saved
    }

    /// `ask` is what the card was called in a request kept by an earlier Lamp: read, so that an answer
    /// still waiting from then can be taken back and its card opens again.
    /// What was pointed at comes back only with its picture still on disk: without the picture the agent would be told
    /// of a part it can't see.
    init(saved: [String: Any], attachments: [URL]) {
        var pointed: PointedAt?
        if let target = saved["pointed"] as? [String: Any], let title = target["title"] as? String,
           let picture = target["picture"] as? String, FileManager.default.fileExists(atPath: picture) {
            pointed = PointedAt(title: title, detail: target["detail"] as? String, picture: picture)
        }
        self.init(text: saved["text"] as? String ?? "", attachments: attachments,
                  card: ((saved["card"] ?? saved["ask"]) as? String).flatMap(UUID.init(uuidString:)),
                  pointed: pointed, byLamp: saved["byLamp"] as? Bool ?? false, afterReload: saved["afterReload"] as? Bool ?? false)
    }
}

/// Whichever of two answers comes first (`Store.answer(of:within:)`): the other is dropped.
@MainActor
final class FirstAnswer<T> {
    var continuation: CheckedContinuation<T?, Never>?
    func give(_ answer: T?) {
        continuation?.resume(returning: answer)
        continuation = nil
    }
}

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var projects: [LampProject] = [] {
        didSet {
            syncLocalNetwork()   // the network listener follows which apps open on a phone
            DeskArrangement.shared.adopt(wishes)
        }
    }
    /// Wishes a newer Lamp laid out, shown on the desk and otherwise left alone (`NewerWish`).
    @Published private(set) var newerWishes: [NewerWish] = []
    /// Every app Lamp has, wherever it is in its wish: not a wish whose apps are all in folders of their own, which is
    /// only the wish (`holdsApp`).
    var everyApp: [LampProject] { projects.filter(\.holdsApp) }
    /// The wishes, without their other parts, which are reached through their wish and never listed on their own.
    var wishes: [LampProject] { projects.filter { !$0.isPart } }
    /// A wish's other parts, as they are now.
    func parts(of wish: LampProject) -> [LampProject] { projects.filter { $0.partOf == wish.id } }
    /// Every app of a wish: the one in its own folder while it holds one (`holdsApp`), then each in a folder of its own.
    /// The one place that knows where a wish's apps are.
    func apps(of wish: LampProject) -> [LampProject] { (wish.holdsApp ? [wish] : []) + parts(of: wish) }
    /// The key an app of a wish of several apps is given as it's put on its device (`WishKeys`), from its first build,
    /// while the others it asks for are still to be made; nil for an app on its own, which gets nothing of the wish's
    /// apps' link.
    func wishKey(for project: LampProject) -> Data? {
        guard Template.talksToOtherApps(project) else { return nil }
        return WishKeys.key(for: wish(of: project))
    }
    /// The wish a part belongs to, or the app itself when it's a wish.
    func wish(of project: LampProject) -> LampProject { project.partOf.flatMap { id in projects.first { $0.id == id } } ?? project }
    /// Who a line about where an app opens names: the wish, or for one of its several apps that app ("The iPhone app"),
    /// since every app of a wish has the wish's name.
    func placeName(_ project: LampProject) -> String {
        guard project.isPart || project.holdsApp && !parts(of: project).isEmpty else { return project.name }
        let name = Parts.name(of: project.platform)
        return name.prefix(1).uppercased() + name.dropFirst()
    }
    /// Play: the app in the wish's own folder and each of its other apps not open yet, each on the device chosen for it, so a TV app and
    /// the iPhone app that controls it come up together. Each app's own menu still opens it alone.
    func openWish(_ wish: LampProject) {
        if wish.holdsApp { openPrepared(wish) }
        for part in parts(of: wish) where !isOpen(part) { openPrepared(part) }
    }
    /// Stop: every app of the wish that's open.
    func quitWish(_ wish: LampProject) async {
        if wish.holdsApp { await quitApp(wish) }
        for part in parts(of: wish) where isOpen(part) { await quitApp(part) }
    }
    /// The wish whose chat window is in front; nil while the desk is (`LampWindows`).
    @Published var selection: String? {
        didSet { if selection != oldValue { markRead() } }
    }
    /// Apps whose chat finished a turn while you were looking elsewhere.
    @Published var unread: Set<String> = [] {
        didSet {
            Notifier.shared.setBadge(unread.count)
            for id in oldValue.subtracting(unread) { Notifier.shared.clear(id) }
        }
    }
    @Published var logs: [String: [LogLine]] = [:]
    @Published var busy: Set<String> = []
    @Published var queued: [String: [QueuedMessage]] = [:]
    /// The turn in progress for each app. A new app's first turn stays here after it finishes, until the next
    /// message, for its chapters (`Chapters.segments`).
    @Published var progress: [String: TurnProgress] = [:]
    /// Apps that are open right now, however they were started, so Lamp can offer to quit them.
    @Published var openApps: Set<String> = []
    /// The apps open on this Mac, and those open in a simulator or on a phone: an app for both can be in
    /// both at once, and its Play and Stop are for the place Try On points at (`isOpen`).
    @Published private(set) var openOnMac: Set<String> = []
    @Published private(set) var openOnIOS: Set<String> = []
    /// A choice in the chat's Try On waiting to open the app where it points (`Store.tryOn`), by app.
    var openingChosen: [String: UUID] = [:]

    /// Whether any app of a wish is open, so its Play is a Stop: the TV app may be closed while its iPhone app runs.
    func isWishOpen(_ wish: LampProject) -> Bool { isOpen(wish) || parts(of: wish).contains(where: isOpen) }

    /// Whether the app is open where it would open now: for an app for both, where Try On points.
    func isOpen(_ project: LampProject) -> Bool {
        guard project.platform.choosesPlace else { return openApps.contains(project.id) }
        // Anywhere but this Mac (the simulator, a phone, Android, a TV preview, a device) is recorded as one.
        return (project.destination == .mac ? openOnMac : openOnIOS).contains(project.id)
    }
    /// The apps whose widget the person has put on the desktop (`WidgetCard`), for their chats' cards.
    @Published var placedWidgets: Set<String> = []
    /// Which Lamp built each installed app (see BuildStamp). Missing for apps that aren't built yet.
    @Published var stamps: [String: BuildStamp] = [:]
    /// A wish from the site's link that came while the welcome is up, for the welcome to take (`take(wish:)`).
    @Published var arrivedWish: String?
    /// The wishes being written into a message box right now, by app (`Wish.Arrival`). The drafts hold them whole.
    @Published private(set) var arrivals: [String: Wish.Arrival] = [:]
    /// What writes each arriving wish in, by app: wishes from the site and from the agent's `write_wish` can be
    /// arriving in several chats at once, and one finishing or starting mustn't cut another short.
    private var wishWriting: [String: Task<Void, Never>] = [:]
    /// The new app the last such wish went into.
    private var wishApp: String?
    @Published private(set) var pendingSubmissions = PendingSubmissions()

    func beginSubmission(_ project: LampProject) -> UUID? {
        guard let current = current(project) else { return nil }
        return pendingSubmissions.begin(current.id)
    }

    func endSubmission(_ token: UUID) { pendingSubmissions.end(token) }
    @Published var setup = SetupCheck()
    /// Whether Lamp has really looked at setup yet, with the saved keys in. Before that `setup` can't be gone
    /// by: it starts out assuming everything is in place, and a look made before the keys are read finds no key.
    private let setupLook = FirstLook()
    /// The welcome finished this run. Normally the saved setting says so too, but `-onboarded NO` on the
    /// command line (for checking the welcome) keeps that setting from changing until Lamp quits.
    @Published var welcomeFinished = false
    @Published var usage: [String: AppUsage] = [:]
    @Published var icons: [String: NSImage] = [:]
    /// The icon's background chosen with the app's name, before its icon is designed: the blueprint shows it.
    @Published var iconColors: [String: String] = [:]
    /// The shared app whose review is up. When it goes, the next one kept from before setup gets its turn.
    @Published var pendingImport: PendingImport? {
        didSet { if pendingImport == nil, oldValue != nil { openWaitingImport() } }
    }

    /// A shell command an agent wants to run, or a file outside the app's folder it wants, waiting for the user
    /// (see ApprovalCard).
    struct PendingApproval: Identifiable {
        let id = UUID()
        let command: String
        /// A file request sets its own title; a command keeps this one.
        static let commandTitle = "Can the agent do this?"
        var title = commandTitle
        /// What the agent said the command is for, which goes on naming what it's doing once it's allowed.
        var said: String?
        let answer: CheckedContinuation<Bool, Never>
        var explanation: CommandExplanation?
        /// What the person asked for in this turn, which the card puts beside the step to weigh it against.
        var request: String?
        /// Why Lamp is asking rather than letting the step run, in the person's words (`Store.whyAsked`).
        var whyAsked: String?
    }

    /// What a command does and how risky it is, in plain words for people who don't read shell commands.
    struct CommandExplanation {
        let summary: String
        let risk: String     // "low", "medium" or "high"; empty when nothing rated it
        let why: String

        /// As the approval card shows it, in Lamp's window and in an app's sidebar.
        var look: ChatLook.Explanation { ChatLook.Explanation(summary: summary, risk: risk, why: why) }
    }
    @Published var approvals: [String: PendingApproval] = [:]   // project id → the command waiting
    private var approving: Set<String> = []                       // project ids between the queue check and the card
    private var lastReloadForToken = Date.distantPast
    private var computerUseRefused: Set<String> = []   // apps told once this launch that using other apps is off
    /// The app whose Rename… alert is showing.
    @Published var renaming: LampProject?
    /// The app whose icon is being made in Image Playground. It stays set after the sheet closes, since the
    /// picked picture can arrive after that.
    @Published var playgroundIcon: LampProject?
    @Published var showingPlayground = false
    /// The app whose Delete confirmation is showing.
    @Published var deleting: LampProject?
    /// The version whose Name… alert is showing.
    @Published var naming: VersionNaming?
    /// Bumped when a version is named, so open version lists reload.
    @Published var versionsRevision = 0
    /// For each app, the change Undo Last Change is offered under in its chat (`UndoOffer`), by the version it made.
    @Published private(set) var undoOffers: [String: String] = [:]
    private var undoOfferReads: [String: Int] = [:]
    /// One span of Lamp owning an app: a chat turn, a rebuild, an undo, an icon redesign. Everything that
    /// belongs to that span lives here and goes with it, so Stop, Delete and quit have one thing to cancel,
    /// and nothing has to be kept in step across a dozen dictionaries. `busy` is the set of apps that have
    /// one, for the interface.
    /// What became of one change: it went into the open app as it ran, it waits for the person's Reload, the app
    /// was closed and opened again for it, or it was opened with it (nobody had it open).
    enum ChangeOutcome { case live, held, reopened, opened }

    @MainActor final class Turn {
        var agent: Process?                 // the engine, while it runs
        /// Lamp ended the engine itself after it had answered (`endAfterAnswer`): its exit is no failure.
        var endedAfterAnswer = false
        var build: Process?                 // the app's build.sh, while it runs
        var stopped = false                 // the user pressed Stop (or deleted the app, or quit Lamp)
        /// Stop was pressed at some point in this turn. `stopped` is cleared once the agent has stopped, so the
        /// turn can go on; this stays, for what the turn's end reports (`Analytics`).
        var wasStopped = false
        /// The Mac app built but the last install couldn't put it in place or open it: logged, not a crash, so
        /// the turn still counts as a change. Kept so a new app's first run isn't counted when it never opened.
        var didNotOpen = false
        /// The app was opened and died straight away: a crash, as opposed to an open that never happened (a
        /// simulator missing, a Stop while it waited), which `install` reports in words too.
        var diedOnLaunch = false
        /// The person kept the app open when this turn's build asked it to quit: it isn't asked a second time
        /// in the turn, and the agent isn't shown the copy on screen as its work.
        var keptOpen = false
        /// The person took the app back while the agent was trying it (`Handover`): use_app is refused until
        /// their next message reaches the agent, so it doesn't reach for the app again under their hands.
        var tookOver = false
        /// The turn's last install put the change into the open app without reopening it: its end says the app
        /// is updated, not ready, whether that install was the agent's look or the turn's own.
        var updatedInPlace = false
        /// How each of the turn's changes reached the app, in order: told to the agent with its look and tallied at
        /// the turn's end, so what went in live and what waited can be seen and learned from.
        var outcomes: [ChangeOutcome] = []
        /// When the request began to be worked on, and when each of its changes reached the screen (went into the open
        /// app, or the app opened with it; not one waiting for Reload): the pace the person watching sees, tallied at
        /// the turn's end (`paceTally`) so the rule asking for it (`Agent.liveNote`) can be judged by what happens.
        var began = Date()
        var shown: [Date] = []
        /// Why the latest change couldn't go into the open app (LiveReload's reason, in words), for the agent's look.
        var reloadWhy: String?
        /// A live change took in the one that was waiting for Reload: the agent is told, since it was told to wait.
        var endedReloadWait = false
        /// The person pressed Reload while the agent worked, and the app reopened with the change that waited
        /// (`reloadInTurn`): the agent is told at its next look, since it was told the change waits for Reload.
        var reloadedByPerson = false
        /// That Reload was Lamp's, while the person was away: when the agent ends without having looked (so without
        /// hearing the change is in), it's carried on (`finish`).
        var reloadedWhileAway = false
        /// That reopen is under way, as `applying`: a build waits for it rather than ending it, since it's no compile
        /// of sources the agent has moved on from.
        var reloading = false
        /// The crash set aside earlier (`setAside`) that the request carries: what the agent saves comes after it has
        /// read it, so it goes into the app by itself as usual (`autoApply`). Not a crash set aside during the turn.
        var carriedSetAside: String?
        /// The turn's own looks at the agent's saved files (`autoApply`): the loop that watches for a save, the one
        /// change going in at the moment, which a build waits for, and how many went in since the agent last looked.
        var autoApply: Task<Void, Never>?
        var applying: Task<Void, Never>?
        var applyingSources = ""
        var autoApplied = 0
        /// The open app's layout being worked out ahead of the first change (`LiveReload.warm`).
        var warming: Task<Void, Never>?
        /// A build of Lamp's is under way (a look's, or the turn's end's): no change of the agent's is put in meanwhile.
        var building = false
        /// Nil for a simulator/Mac turn; false until the chosen phone acknowledges opening the app.
        var phoneReady: Bool?
        var allowAll = false                // "Allow all for this turn"
        /// What the checks made of each command this turn (`commandJudgment`): an agent runs the same build or
        /// look at a file again and again, and the answer can't differ while the request is the same.
        var judgments: [String: CommandRisk.Judgment] = [:]
        var approving = false               // between the queue check and the approval card
        var look = Look()                   // what the agent's look_at_app has done
        /// The watch on the turn's last launch: a look goes on once the app shows, so a death in its first seconds can
        /// come after the look's answer, and is told with the next look or use_app (`lateCrash`) or at the turn's end.
        var launches: [Runtime.LaunchWatch] = []
        var launch: Runtime.LaunchWatch? { launches.last }
        /// A new app's scaffold being built and opened as the turn starts (`showEarly`): a look and the turn's own
        /// build wait for it, since a turn has one build at a time.
        var early: Task<Void, Never>?
        var pendingName: String?            // a name the agent gave the version this request makes
        /// What the agent last said it's doing, in its own words (`AgentEvent.naming`): the name of the commands
        /// that follow, until it says something else.
        var naming: String?
        /// This turn's tool calls by the engine's id for them: the step each was logged as, and a command's text, so
        /// the step can say it failed once the call's outcome comes back (`AgentEvent.ended`).
        var calls: [String: (line: UUID, command: String?)] = [:]
        /// Whether the chat says each command from the engine's own output (`AgentRun.saysCommands`), for the run going now.
        var saysCommands = false
        /// The agent put its questions to the person this turn: the turn is over, whatever the agent does next.
        var asked = false
        /// The agent asked to see or use the app while its change waits for the person (Reload, or an app they kept
        /// open): the turn is over, whatever the agent does next, and the request goes on once the change is in
        /// (`Store.pause`).
        var paused = false
        /// The agent has been told, this turn, that its change waits for the person and that it may go on with what's
        /// left (`Store.held`); a look after that is it asking to see, which stops the turn. Cleared when the person's
        /// Reload puts the change in while the turn goes on (`reloadInTurn`).
        var toldHeld = false
        /// Lamp ended the agent because it went on working past its own questions, or past a change the person
        /// hasn't seen yet. Not a stop and not a failure.
        var endedOnQuestions = false
        var artCost = 0.0                   // what make_art's pictures cost, for the turn's summary
        var request: String?                // the user's words, for the command classifiers
        var messages: [String] = []         // each queued message this turn took, as sent, from the moment it took them
        /// Where the app was when the turn began: a request the agent takes while it works was sent from there too.
        var sentFrom: String?
        /// The chat lines of the requests the agent took while it worked (`handOver`), which go with the turn's
        /// own to the version it makes.
        var midTurn: [UUID] = []
        /// The chat lines of the requests the turn began with, which go to the engine as its request (`CatchUp`).
        var requests: [UUID] = []
        /// Requests handed to the engine that its output hasn't yet shown reaching the model (`received`).
        var handed: [UUID] = []
        /// The engine running now, which takes messages while it works; nil between runs.
        var steering: Engine?
        /// Claude Code's input, from its start until it has answered.
        var input: AgentInput?
        /// The engine is running a tool: a message written to it now reaches the model with the tool's result.
        var toolRunning = false
        /// Codex's model has been heard from in this run, so it has the run's request and an interrupt now is one
        /// Codex ends cleanly (`steer`). Its `turn.started` comes before the request is saved.
        var codexStarted = false
        /// Calls into Lamp being answered for this turn (an MCP tool, an approval): one may be under way before
        /// the engine's output says so.
        var answering = 0
        /// What Codex is in the middle of (commands, tool calls, edits, searches), by its ids.
        var codexActing: Set<String> = []
        /// The messages Codex's run was interrupted to pass on: they start its next run, in the same conversation.
        var codexCut: String?
        var claudeSession: String?          // Claude Code's conversation, as its own output says (Privacy.isOwnOutput)
        var writing: (line: UUID, unshown: String)?   // the message the agent is writing right now
        var titleRoute: StepTitles.TurnRoute?          // what builds the run going on, for its steps' titles
        var showingWritten = false
        /// The agent's token for this turn (Store.agentTokens): the only way to its routes.
        let agentToken = UUID().uuidString + UUID().uuidString

        var isWorking: Bool { agent != nil || build != nil }

        /// Stops what's running. Returns the processes signaled, for a caller that waits for them (quit).
        @discardableResult func cancel() -> [pid_t] {
            stopped = true
            wasStopped = true
            allowAll = false
            var pids: [pid_t] = []
            if let agent { pids += Subprocess.terminateTree(agent) }
            if let build { pids += Subprocess.terminateTree(build) }
            // A save being put in by itself stops too: before its compile it ends at once, and one already past
            // it finishes without a word (the app has the change, and nothing is said of it after Stop).
            autoApply?.cancel()
            applying?.cancel()
            return pids
        }
    }
    private var turns: [String: Turn] = [:]

    /// Whether the app's running turn took this message: one of those it was sent, together or alone, from the
    /// moment it took them (before its request is put together) until it ends.
    func isRunning(_ message: String, for project: LampProject) -> Bool { turns[project.id]?.messages.contains(message) ?? false }

    /// Takes the app for a span of work. Nil when something else has it.
    private func begin(_ project: LampProject) -> Turn? {
        guard turns[project.id] == nil else { return nil }
        let turn = Turn()
        turns[project.id] = turn
        agentTokens[turn.agentToken] = project.id
        busy.insert(project.id)
        undoOffers[project.id] = nil
        return turn
    }

    /// Works out again which change the chat offers Undo Last Change under: when a turn ends, and when a chat is
    /// shown. Only the latest look counts: one started earlier can end after it.
    func refreshUndoOffer(_ project: LampProject) {
        let read = undoOfferReads[project.id, default: 0] + 1
        undoOfferReads[project.id] = read
        Task {
            let offer = busy.contains(project.id) ? nil : await UndoOffer.version(for: project, chat: logs[project.id] ?? [], parts: parts(of: project))
            guard undoOfferReads[project.id] == read else { return }
            let shown = busy.contains(project.id) ? nil : offer
            if undoOffers[project.id] != shown { undoOffers[project.id] = shown }
        }
    }

    /// Gives the app back, without starting anything queued (see `finish`).
    /// A request's change the open app can't take as it runs: built and held (`Runtime.awaitReload`), with a Reload
    /// button in the app's title bar and a line in the chat that has one too. Closing the app installs it as well.
    private func awaitReload(_ project: LampProject, owner: Turn?) {
        let already = Runtime.waitsForReload(project)
        Runtime.awaitReload(project)
        _ = heldInstalls.mayInstall(project.id, running: true)
        Self.tellReload(project, on: true)
        dropUnderWay(project)
        let lines = logs[project.id] ?? []
        if !already || !lines.contains(where: { $0.kind == .reload }) { log(project, .reload, "") }
        refreshOpenApps()
    }

    /// The lines at the chat's end that said what was under way ("Building…", "Waiting for … to close…"): with the change
    /// waiting for Reload, nothing is, so they go. The details among them (why the app has to reopen) are only shown
    /// with Agent Details, and stay.
    private func dropUnderWay(_ project: LampProject) {
        guard var lines = logs[project.id] else { return }
        var index = lines.endIndex
        var removed = false
        while index > lines.startIndex, case let line = lines[index - 1],
              line.kind == .detail || (line.kind == .status && line.text.hasSuffix("…")) {
            index -= 1
            if line.kind != .detail { lines.remove(at: index); removed = true }
        }
        guard removed else { return }
        logs[project.id] = lines
        saveChat(project)
    }

    /// Shows or takes away the app's Reload button (`LampMagic.setReload`).
    static func tellReload(_ project: LampProject, on: Bool) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(Edition.notificationPrefix + "reloadReady." + project.id), object: nil,
            userInfo: ["on": on ? "1" : "0"], deliverImmediately: true)
    }

    /// The person pressed Reload, in the app or the chat: the waiting change goes in, by closing the app the usual way
    /// and opening it again where it was. Pressed while a request's agent works, it's done by that turn as soon as the
    /// agent is between steps (`reloadInTurn`); while any other work has the app, when that's done.
    func reloadWaiting(_ id: String) {
        // A wish's Reload is for whichever of its apps waits, its own or one of its other parts'; everything that says
        // whose turn it is and whether the person stopped or was asked is the wish's (`requestOwner`).
        let asked = projects.first { $0.id == id }
        let owner = asked.map { Self.requestOwner(of: $0, among: projects) }
        let id = owner?.id ?? id
        guard let owner, let project = waitingForReload(in: owner) else {
            reloadWhenFree.remove(id)
            _ = away.landed(id, stillWaits: false)   // put in meanwhile, by the app closing: nothing of Lamp's to carry on
            return
        }
        // Taken now, before anything queued can start: otherwise kept until the turn that has the app ends.
        guard begin(owner) != nil else { reloadWhenFree.insert(id); return }
        reloadWhenFree.remove(id)
        away.installs(id)
        // The Mac copy's change, wherever Try On points now (an app for both may have moved it to a phone since).
        var mac = project
        mac.chosen = .mac
        Task {
            _ = await install(mac, inFront: true, fresh: true, reload: true)
            // Lamp pressed it while the person was away, and the turn that left it is over (it ended asking for Reload,
            // paused, or the Reload was put off until its end): the agent goes on, as after a pause.
            if away.landed(id, stillWaits: waitingForReload(in: owner) != nil), away.carriesOn(id) { queueCarryOn(owner) }
            finish(owner)
        }
    }

    /// The one of a wish's apps whose change waits for Reload: its own, else one of its other parts'.
    private func waitingForReload(in wish: LampProject) -> LampProject? {
        guard let wish = current(wish) else { return nil }
        return Runtime.waitsForReload(wish) ? wish : parts(of: wish).first(where: Runtime.waitsForReload)
    }

    /// The person stepped away while a request's change waits for Reload: Lamp presses it for them, so the agent can
    /// go on. While they're at the Mac it stays theirs to press. A turn still at work puts the change in between its
    /// steps; once the turn is over (paused, the agent ending its reply asking for Reload, as models often do rather
    /// than look again, or the Reload put off until its end) the agent is carried on the way a pause is, decided
    /// when the change is in (`reloadWaiting`, `finish`), never after the person pressed Stop (`AwayReloads`).
    private func reloadIfAway() {
        // By the wish: a Stop or a question waiting in its chat holds its parts' Reloads too.
        let waiting = Array(Set(projects.filter(Runtime.waitsForReload).map { Self.requestOwner(of: $0, among: projects).id }))
        for id in away.toPress(waiting: waiting, idle: AwayReloads.secondsSinceInput) {
            guard let project = projects.first(where: { $0.id == id }) else { continue }
            log(project, .status, "Reloaded \(project.name) while you were away")
            reloadWaiting(id)
        }
    }
    private var away = AwayReloads()

    /// Reloads pressed while something else had the app: the agent's turn puts each in between its steps
    /// (`reloadInTurn`), other work when it's done, and the chat says so meanwhile (`ReloadLine.queued`), since
    /// nothing else would seem to happen.
    @Published private(set) var reloadWhenFree: Set<String> = []

    /// Whether reopening the app now would close it under the person: a request's turn, the Mac app open, and not a
    /// new app's first turn (nobody is using it yet, and its passes are built for the person to watch go in). Then
    /// Lamp asks with Reload rather than reopening it, for a change it can't put in as the app runs and for a look
    /// with `reopen` alike.
    private func asksBeforeReopening(_ project: LampProject, owner: Turn?) -> Bool {
        owner?.request != nil && isRunning(project) && !Template.isWidgetOnly(project) && progress[project.id]?.newApp != true
    }

    private func release(_ project: LampProject) {
        if let turn = turns.removeValue(forKey: project.id) { agentTokens[turn.agentToken] = nil }
        busy.remove(project.id)
    }

    /// Whether any app has an agent or a build going, for the question asked before quitting.
    var isWorking: Bool { turns.values.contains(where: \.isWorking) }

    /// Stops every agent and build, as when Lamp quits: otherwise they'd carry on without it. Returns the
    /// processes signaled, so quitting can wait until they're gone.
    func stopAll() -> [pid_t] {
        var pids: [pid_t] = []
        for project in projects {
            guard let turn = turns[project.id], turn.isWorking else { continue }
            endApprovals(for: project)
            pids += turn.cancel()
        }
        return pids + Subprocess.stopping
    }

    /// Whether the app still exists: a turn can outlive Delete by a moment, and mustn't write to the Trash.
    private func exists(_ project: LampProject) -> Bool { projects.contains { $0.id == project.id } }
    /// Apps whose versions are getting titles, so only one run at a time asks the model.
    private var titling: Set<String> = []

    /// What the agent's `look_at_app` tool has done during the current turn.
    struct Look {
        var inProgress = false
        /// Each app the last look at it built and opened, and how that launch went, by app: a wish's apps are looked
        /// at in one turn, and one's crash is no word on another.
        var installed: [String: Bool] = [:]
        var crashes: [String: String] = [:]
        /// A new app was shown to the person at this turn's first look that opened it: built in passes, it's watched
        /// as it takes shape rather than seen only at the end (`present`).
        var presented = false
        /// The same for a wish's other parts, by id: each is shown at its own first look.
        var presentedParts: Set<String> = []
        /// A look this turn has said what Try On is set to and what the device list returned (`Devices.tryOnNote`).
        var toldPhone = false
    }
    private var artInProgress: Set<String> = []
    /// Designs whose artwork couldn't be drawn, by `Icons.artKey`: their icons show the symbol, not the blueprint.
    private var artFailed: Set<String> = []
    /// Apps whose blueprint gives way to the symbol once the turn that has them ends (`artworkWontCome`).
    private var iconFallbackWhenFree: Set<String> = []
    private var pendingIconArt: Set<String> = []     // artwork finished during a turn, to apply after it
    private var heldInstalls = HeldInstalls()        // new icons waiting for their app to close
    private var heldDrawingOffers: Set<String> = []  // "Draw Icon…" wanted during a turn, to offer after it
    private var artApplied: [String: IconSpec] = [:] // the spec whose artwork the rendered icon includes
    private var iconDesigns: [String: Task<Void, Never>] = [:]   // icons designed from the first message
    /// Icons being prepared while the app goes on (after a change went into the open app): a copy waits for its icon.
    private var iconPreparations: [String: Task<Void, Never>] = [:]
    /// The last icon render asked for, by app: each waits for the one before, so two never write the same files.
    private var iconRenders: [String: Task<Void, Never>] = [:]
    private var tokens: [String: String] = [:]   // app token → project id, for the app's own routes (/ai…)
    /// The agent's token for the turn in progress → project id. Minted per turn and gone with it, so the agent's
    /// routes (/agent/…, /mcp) can't be reached with the app's token, which the app itself holds, nor after the
    /// turn ends. A leaked app token then buys AI calls as that app, and nothing more.
    private var agentTokens: [String: String] = [:]
    private var gateway: Gateway?

    nonisolated static let installDir = Edition.appsFolder

    let root: URL

    /// A Store over the wishes in `root` alone, for tests: none of Lamp's launch work (migration, keys, starters) runs.
    init(testingAt root: URL) {
        self.root = root
        reload()
    }

    private init() {
        root = Edition.supportFolder.appendingPathComponent("Apps")
        Migration.fromForge()
        AppsLink.ensure()
        // The keys are read off the main thread first; what needs them (pi's auth file, the setup check, the
        // views drawn meanwhile) follows once they're in.
        KeyStore.preload()
        NotificationCenter.default.addObserver(forName: KeyStore.loaded, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                Agent.syncKeyFile()   // keys an earlier Lamp left in pi's auth file come out of it
                self?.objectWillChange.send()
                Task { await self?.recheckSetup() }
            }
        }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
        for project in wishes where project.decided { settleDecided(project) }
        restoreWaiting()
        for project in projects { discardIfUnused(project.id) }
        // The wishes Lamp comes with don't count: they're there before the welcome is.
        Onboarding.settle(hasApps: projects.contains { !Starters.isStarter($0) })
        if !Onboarding.isDone { installStarters() }
        // Lamp opens on the desk (`WishDesk`), not on a wish's chat.
        selection = nil
        startGateway()
        watchOpenApps()
        // Asking for phones runs devicectl, so only for someone with iPhone apps; Try On asks again when it's opened.
        // This Mac's record is read either way, off the main thread, so the first request's note has it.
        if projects.contains(where: { $0.platform.target.places.contains(where: \.listsDevices) }) { refreshDevices(); refreshSimulators() }
        else { Task { thisMac = await Device.readThisMac() } }
        if !Provider.models.contains(where: { $0.id == UserDefaults.standard.string(forKey: "model") }) {
            UserDefaults.standard.set(Provider.model, forKey: "model")   // from the Claude Code era ("sonnet")
        }
        // The login shell's PATH, which every tool Lamp runs is given, and the person's own Claude Code and
        // Codex (running each copy found with --version to pick the newest) are looked for off the main thread
        // when Lamp keeps its engines current, before it decides whether it needs its own copy of one.
        EngineDownloads.shared.startKeepingCurrent()
        Task {
            LocalModels.shared.refresh()
            await recheckSetup()
        }
    }

    private var pollingSetup = false

    /// Re-checks setup. On a fresh Mac this opens Apple's installer straight away, then keeps
    /// checking in the background so setup finishes by itself once the tools are installed.
    func recheckSetup() async {
        // What Claude Code's and Codex's sign-ins are, for whether they can answer apps (`AppAI.resolve`).
        Task { await EngineSignIn.refresh() }
        let wasReady = setup.checked && setup.ready
        let keysRead = KeyStore.keysRead
        setup = await SetupCheck.run(keeping: setup).keeping(setup)
        // The look that counts. A shared app kept by an earlier one gets its turn now, if setup was in place all along.
        if keysRead, !setupLook.isDone {
            setupLook.done()
            openWaitingImport()
        }
        // During the welcome, Apple's installer waits for the step that explains it.
        if !setup.hasBuildTools && !setup.installRequested && Onboarding.isDone { requestBuildTools() }
        if !setup.hasBuildTools { pollSetup() }
        prepareStarters()   // the prebuilt ones need no build tools
        if setup.ready && !wasReady { await becameReady() }
    }

    func requestBuildTools() {
        SetupCheck.installBuildTools()
        setup.installRequested = true
        setup.installRequestedAt = Date()
        setup.installerSeen = false
        setup.backFromInstaller = false
        pollSetup()
    }

    /// Apple's installer opened or quit. Noted as it happens, since it can come and go between two looks.
    func installerChanged(open: Bool) {
        guard !setup.hasBuildTools, setup.installRequested else { return }
        setup.installerOpen = open
        setup.installerSeen = true
        if !open { Task { await recheckSetup() } }   // quit because it finished, or didn't
    }

    /// Lamp is back in front while Apple's installer is open: the person has been through its buttons.
    func cameBackFromInstaller() {
        guard !setup.hasBuildTools, setup.installRequested, SetupCheck.installerIsOpen() else { return }
        setup.backFromInstaller = true
    }

    /// Requests sent before setup finished (the welcome's first app) start now.
    private func becameReady() async {
        for project in projects where !(queued[project.id] ?? []).isEmpty { startQueued(project) }
        saveWaiting()
        openWaitingImport()
        await backfillIcons()
        resumeWaitingIcons()
    }

    private func pollSetup() {
        guard !pollingSetup else { return }
        pollingSetup = true
        Task {
            defer { pollingSetup = false }
            while !setup.hasBuildTools {
                try? await Task.sleep(for: .seconds(5))
                setup = await SetupCheck.run(keeping: setup).keeping(setup)
            }
            prepareStarters()
            if setup.ready { await becameReady() }
        }
    }

    var selected: LampProject? { projects.first { $0.id == selection } }

    /// Clears the "ready" dot for the app on screen. Also called when Lamp comes back to the front.
    func markRead() {
        if let selection, NSApp?.isActive ?? true { unread.remove(selection) }
    }

    /// Lamp is in front with this app's chat on screen.
    func isWatching(_ id: String?) -> Bool {
        id != nil && selection == id && NSApp.isActive
    }

    /// A wish as its folder says it is: its meta.json, and the other parts found beside it (`Parts.folders`). None for
    /// a wish a newer Lamp laid out (`NewerWish`), which this Lamp leaves alone.
    nonisolated static func readWish(at dir: URL) -> LampProject? {
        guard NewerWish.read(at: dir) == nil,
              let data = try? Data(contentsOf: dir.appendingPathComponent(".lamp/meta.json")),
              let meta = try? JSONDecoder().decode(ProjectMeta.self, from: data) else { return nil }
        let project = LampProject(id: dir.lastPathComponent, name: meta.name, exe: meta.exe, dir: dir,
                           instance: meta.instance ?? dir.lastPathComponent,
                           untitled: meta.untitled ?? false, fromWish: meta.wish ?? false, finding: meta.finding ?? false,
                           deviceSetup: meta.deviceSetup,
                           platform: meta.platform ?? .mac, integration: meta.integration, family: meta.family ?? .iphone,
                           device: meta.device, chosen: meta.target ?? .mac, places: meta.places, engine: meta.engine, simulator: meta.simulator,
                           partFolders: Parts.folders(in: dir), undecided: meta.undecided,
                           apps: meta.apps ?? [], waitsForDevice: meta.waitsForDevice ?? false, decided: meta.decided ?? false)
        // A game made before games were a kind of their own reads as one now, and is kept so.
        if let game = GameKit.migrated(project) {
            try? Template.saveMeta(game)
            return game
        }
        // The layout meta.json says follows the files, whatever took the app in the wish's own folder away or brought it
        // back (the agent's own git, say), so a Lamp from before such wishes always leaves one alone (`NewerWish`).
        if meta.layout != Template.layout(of: project) { try? Template.saveMeta(project) }
        return project
    }

    func reload() {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        newerWishes = dirs.compactMap(NewerWish.read)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let wishes = dirs.compactMap(Self.readWish)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        // Each wish's other parts follow it, as apps of their own kind in its folders (`Parts`). Set in one go: every
        // change to the list is acted on (the network listening, phones' sessions), and a list of the wishes alone, for
        // a moment, would end the game of every TV app whose phones are its wish's other apps.
        let found = wishes + wishes.flatMap(Parts.load)
        // A part whose files are gone (a restore, a folder the agent took away) that's still open on this Mac, kept by the
        // person over unsaved work, stays listed so its wish's menu can still quit it; it goes at the first read after
        // it's closed. Only taking a part away, deleting its wish or a restore that closed it forgets what Lamp keeps for
        // it (`forget`): a part's files missing for a moment mustn't cost its sign-ins.
        let kept = projects.filter { part in
            part.isPart && !found.contains { $0.id == part.id } && (part.partOf.map { id in found.contains { $0.id == id } } ?? false) && isRunning(part)
        }
        projects = found + kept

        for project in projects {
            tokens[Template.token(for: project)] = project.id
            // A part has no chat, usage or icon of its own: they're its wish's.
            if project.isPart { continue }
            if icons[project.id] == nil, let image = NSImage(contentsOf: Icons.previewURL(project)) {
                icons[project.id] = image
            }
        }
        // A game or a screen installed before its kind had a folder of its own in the apps folder moves there once: by its
        // own id only, so a Mac app of the wish installed under the same name stays.
        let fm = FileManager.default
        for project in projects where project.holdsApp {
            guard let before = project.installedBeforeFolders, !fm.fileExists(atPath: project.installedURL.path),
                  Bundle(url: before)?.bundleIdentifier == project.bundleID else { continue }
            try? fm.createDirectory(at: project.installedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.moveItem(at: before, to: project.installedURL)
        }
        // Not for a wish whose apps are all in folders of their own: its name's installed copy is a Mac app of it.
        for project in projects { stamps[project.id] = project.holdsApp ? BuildStamp.of(project) : nil }
        for project in projects where logs[project.id] == nil && !project.isPart {
            let lamp = project.dir.appendingPathComponent(".lamp")
            if let saved = LogLine.readChat(lamp.appendingPathComponent("chat.json")) {
                logs[project.id] = saved.lines
                if let unkept = saved.unkept { unkeptChats[project.id] = unkept }
            }
            if let data = try? Data(contentsOf: lamp.appendingPathComponent("usage.json")),
               let saved = try? JSONDecoder().decode(AppUsage.self, from: data) {
                usage[project.id] = saved
            }
        }
    }

    func log(_ project: LampProject, _ kind: LogLine.Kind, _ text: String, attachments: [String]? = nil, retryPhone: String? = nil,
             offer: SetupOffer? = nil, noted: NoteReceipt? = nil, said: String? = nil, failed: Bool = false, call: String? = nil) {
        // A part has no chat of its own: what's said of it (its build, its crash) is said in its wish's.
        if project.isPart {
            let wish = wish(of: project)
            if wish.id != project.id {
                log(wish, kind, text, attachments: attachments, retryPhone: retryPhone, offer: offer, noted: noted, said: said, failed: failed, call: call)
            }
            return
        }
        let line = chaptered(LogLine(kind: kind, text: text, attachments: attachments, retryPhone: retryPhone, offer: offer,
                                     noted: noted, said: said, at: Date(), failed: failed ? true : nil, call: call), in: project)
        let movedOn = line.part != nil && ChatItem.isStep(line)
            && logs[project.id]?.last(where: ChatItem.isStep).map { $0.part != line.part } == true
        logs[project.id, default: []].append(line)
        if kind == .status, text.hasSuffix("…") { note(text, for: project) }   // "Building…"
        // A first build's step in the next part closes the steps of the part before it, as something said would.
        if movedOn || ![.detail, .summary, .status, .tool].contains(kind) { closeSteps(project) }
        saveChat(project)
    }

    /// A line of a new app's first build, with the part of the plan it goes under in the chat (`Chapters`). The
    /// build's summary carries the plan's parts, so the chapters read the same once the turn is over and after a
    /// relaunch; what's logged after it (Lamp's own build and opening, a run to fix it) belongs to no part.
    private func chaptered(_ line: LogLine, in project: LampProject) -> LogLine {
        guard progress[project.id]?.newApp == true else { return line }
        var line = line
        if line.kind == .summary {
            if let plan = progress[project.id]?.plan, !plan.isEmpty, progress[project.id]?.chaptersClosed == false,
               TurnProgress.savesPlan(asked: turns[project.id]?.asked == true, in: logs[project.id] ?? []) {
                line.plan = plan.map(\.title)
            }
            progress[project.id]?.chaptersClosed = true
        } else {
            line.part = progress[project.id]?.chapter(for: line)
        }
        return line
    }

    /// A tool call's step in the agent's own words: what it gave this call, else, for Codex, the heading of its
    /// reasoning before it, which says what the work after it is for. A command's description (Claude Code's, pi's)
    /// names that command only: the file work after it is a step of its own, or a read would carry "Share the page"
    /// after the command that was to share it had failed.
    nonisolated static func stepName(of call: ToolCall, said: String?, naming: String?, engine: Engine) -> String? {
        let fileWork = [.read, .write, .edit, .search, .list, .delete].contains(call.action)
        return said ?? (engine == .codex && (call.action == .run || fileWork) ? naming : nil)
    }

    /// Marks a step that was tried and didn't work, so it says so in the chat and in its fold's line.
    func markFailed(_ line: UUID?, id: String?, command: String?, in project: LampProject) {
        guard var lines = logs[project.id] else { return }
        let failed = Self.failedRows(in: lines, line: line, id: id, command: command)
        guard !failed.isEmpty else { return }
        for index in failed { lines[index].failed = true }
        logs[project.id] = lines
        saveChat(project)
    }

    /// The lines a failed call marks: the call's own step, and a command's row ("Ran: …"), which Lamp logs apart from
    /// the call, when the command is let run or has run. The row is found by the engine's id for the call, which it
    /// carries when the approval or the engine's output said it: two calls of the same command in one message may each
    /// have a row, and only the call's own is its. A row that carries no id (an engine that didn't say it) is found by
    /// its command, the latest since the call, or since the request when the call isn't known, never one tied to another
    /// call. A command declined on the card has no row, and an older run of the same command keeps its own.
    nonisolated static func failedRows(in lines: [LogLine], line: UUID?, id: String?, command: String?) -> [Int] {
        let own = line.flatMap { line in lines.lastIndex { $0.id == line } }
        var rows = own.map { [$0] } ?? []
        if let id, let row = lines.lastIndex(where: { $0.kind == .status && $0.call == id }) { return rows + [row] }
        let since = own ?? lines.lastIndex { $0.kind == .user } ?? lines.startIndex
        if let command, let row = lines[since...].lastIndex(where: { $0.kind == .status && $0.call == nil && $0.text == "Ran: \(command)" }) {
            rows.append(row)
        }
        return rows
    }

    /// What each fold of a finished turn's steps did (`StepTitles`), put on the fold's first step. A line gone since
    /// (the chat went back to an earlier version) is passed over.
    func setFoldTitles(_ titles: [UUID: String], in project: LampProject) {
        guard !titles.isEmpty, var lines = logs[project.id] else { return }
        var changed = false
        for index in lines.indices {
            if let title = titles[lines[index].id], lines[index].foldTitle != title {
                lines[index].foldTitle = title
                changed = true
            }
        }
        guard changed else { return }
        logs[project.id] = lines
        saveChat(project)
    }

    /// Saves the chat a moment later, with whatever else is added meanwhile, away from the main thread. The file is
    /// the whole chat, and a turn adds a line for every step: written at once each time, a long chat's encoding held
    /// the main thread for milliseconds per line, many times a turn. Lines added within `chatSavePause` of each other
    /// go in one write; Lamp quitting writes what's waiting (`flushChats`), and so does anything that copies, moves
    /// or deletes the app's folder first (`settleChat`).
    private func saveChat(_ project: LampProject) {
        guard exists(project) else { return }
        chatsToSave.insert(project.id)
        guard !chatSaveScheduled else { return }
        chatSaveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.chatSavePause) { [weak self] in self?.writeChats() }
    }

    private static let chatSavePause: TimeInterval = 0.5
    /// One queue for every chat's file, so a later write of a chat never lands before an earlier one.
    private static let chatWrites = DispatchQueue(label: "dev.lamp.chat-writes", qos: .utility)
    private var chatsToSave: Set<String> = []
    /// Chat files holding lines this Lamp couldn't read, whose copy couldn't be made when they were read: each save
    /// tries the copy again and writes nothing until it's made (`LogLine.readChat`).
    private var unkeptChats: [String: Data] = [:]
    private var chatSaveScheduled = false

    private func writeChats() {
        chatSaveScheduled = false
        let ids = chatsToSave
        chatsToSave = []
        ids.forEach(writeChat)
    }

    /// Hands the chat as it is now to the writing queue. The lines are a copy, so the main thread goes on changing them.
    private func writeChat(_ id: String) {
        guard let project = projects.first(where: { $0.id == id }) else { return }
        let lines = logs[id] ?? []
        let file = project.dir.appendingPathComponent(".lamp/chat.json")
        if let unkept = unkeptChats[id] {
            guard LogLine.keepAside(unkept, of: file) else { return }
            unkeptChats[id] = nil
        }
        Self.chatWrites.async {
            guard let data = try? JSONEncoder().encode(lines) else { return }
            try? data.write(to: file, options: .atomic)
        }
    }

    /// Writes what's waiting of this chat now and waits until its file is written, before the app's folder is
    /// copied, moved or deleted: a write landing afterwards would go to a folder that's no longer the app's.
    private func settleChat(_ project: LampProject) {
        if chatsToSave.remove(project.id) != nil { writeChat(project.id) }
        Self.chatWrites.sync {}
    }

    /// Writes every chat that's waiting, for when Lamp quits.
    func flushChats() {
        writeChats()
        Self.chatWrites.sync {}
    }

    /// The message each app's agent is writing right now: its chat line, and text that has arrived but isn't
    /// in the chat yet.

    /// Adds a piece of the message the agent is writing, so it shows in the chat as it arrives. Pieces come
    /// twenty a second, and after a tool call the first few seconds' worth arrive all at once, so they go into
    /// the chat a few times a second rather than one by one: redrawing the chat for every piece keeps the
    /// main thread busy for seconds, and nothing shows until it has caught up. The message isn't saved
    /// until it's whole, since saving rewrites the chat's file.
    private func write(_ piece: String, for project: LampProject) {
        guard let turn = turns[project.id] else { return }
        guard turn.writing != nil else {
            guard !piece.trimmed.isEmpty else { return }
            let line = chaptered(LogLine(kind: .agent, text: String(piece.drop(while: \.isWhitespace)), at: Date()), in: project)
            logs[project.id, default: []].append(line)
            turn.writing = (line.id, "")
            closeSteps(project)
            // "Replying" only for words the chat shows as they come: after asking, what the agent says on its way out
            // is hidden (the card is the answer, `LogLine.visible`), so the line says it's working, as it would
            // with nothing known yet.
            noteAgent(turn.asked ? Activity.thinking : Self.replying, for: project)
            return
        }
        turn.writing?.unshown += piece
        guard !turn.showingWritten else { return }
        turn.showingWritten = true
        Task {
            try? await Task.sleep(for: .milliseconds(80))
            turn.showingWritten = false
            showWritten(for: project)
        }
    }

    /// Something said during a run closes the stretch of steps before it, which is titled now rather than when the
    /// turn ends (`StepTitles.closed(in:turn:)`).
    private func closeSteps(_ project: LampProject) {
        guard let route = turns[project.id]?.titleRoute else { return }
        StepTitles.closed(in: project, turn: route)
    }

    /// Ends Claude Code when it's still there a while after it answered, so the turn ends with its answer. With its
    /// input closed it exits at once, unless something it started in the background holds it open: Claude Code then
    /// waits for that and takes one more turn with what it found, which for a server never comes. Lamp turns
    /// background commands off (`Agent.run`), so this is for whatever else might; SIGTERM is how Claude Code's own
    /// documentation ends a run, and what the run still had going (its commands, what they started) ends with it, as
    /// with Stop.
    private func endAfterAnswer(_ process: Process, in turn: Turn) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.answeredGrace))
            guard turn.agent === process, process.isRunning, !turn.stopped else { return }
            turn.endedAfterAnswer = true
            Subprocess.terminateTree(process)
        }
    }

    /// How long Claude Code has to exit after it answered: it takes a moment to write its output and end.
    private static let answeredGrace: TimeInterval = 10

    /// What the live line says while the agent writes a message the chat shows.
    private static let replying = "Replying"

    /// Puts what has arrived of the message being written into its chat line.
    private func showWritten(for project: LampProject) {
        guard let turn = turns[project.id], let (line, unshown) = turn.writing, !unshown.isEmpty,
              let index = logs[project.id]?.lastIndex(where: { $0.id == line }) else { return }
        logs[project.id]?[index].text += unshown
        turn.writing?.unshown = ""
    }

    /// Updates what the app's turn is doing right now, for the activity line.
    /// `file` is the file being written or edited, when that's the step.
    private func note(_ activity: String, file: String? = nil, for project: LampProject) {
        // A step that changes nothing about what's being done (the agent's progress line).
        guard !activity.isEmpty else { return }
        // What Lamp does for a part (building it, opening it) is the activity of its wish's turn.
        if project.isPart, case let wish = wish(of: project), wish.id != project.id { return note(activity, file: file, for: wish) }
        guard let current = progress[project.id], current.activity != activity || current.currentFile != file else { return }
        progress[project.id]?.activity = activity
        progress[project.id]?.currentFile = file
    }

    /// The same, from what the agent's own output says it's doing. While Lamp looks at the app for it, the look's
    /// stages are what's going on ("Building…", "Opening…"): the engine reports the call a moment after the look has
    /// begun, and its one fixed word for it would stay over every stage of a look that can take minutes.
    private func noteAgent(_ activity: String, file: String? = nil, for project: LampProject) {
        guard turns[project.id]?.look.inProgress != true else { return }
        note(activity, file: file, for: project)
    }

    /// The installed app was built by an older Lamp and hasn't been rebuilt since.

    // MARK: - Drafts

    /// What's typed but not sent in an app's chat.
    struct Draft: Equatable {
        var text = ""
        var attachments: [URL] = []
        /// What was pointed at in the app, shown as its own pill in the box rather than among `attachments`.
        var pointed: PointedAt?
        /// The request in the chat this takes the place of when it's sent (see `sendAgain`).
        var replacing: UUID?
        /// What was in the message box before that request was taken back into it, put back if it isn't
        /// sent again after all.
        var setAsideText = ""
        var setAsideAttachments: [URL] = []
        var setAsidePointed: PointedAt?

        /// Something to send: words, files, or what was pointed at.
        var isEmpty: Bool { text.trimmed.isEmpty && attachments.isEmpty && pointed == nil }

        /// This draft with a wish from the site as its words: all of the wish at once, and everything else
        /// the draft holds (files dropped into the box) kept.
        func taking(wish: String) -> Draft {
            var draft = self
            draft.text = wish
            return draft
        }

        /// Only clear input that is still exactly the captured request. An idea, edit or late file added
        /// while setup was open belongs to the next draft, even though the earlier request was sent.
        func afterSubmission(_ captured: Draft, sent: Bool) -> Draft {
            guard sent else { return self }
            if self == captured { return Draft() }
            var kept = self
            if kept.replacing == captured.replacing {
                kept.replacing = nil
                kept.setAsideText = ""
                kept.setAsideAttachments = []
                kept.setAsidePointed = nil
            }
            return kept
        }
    }

    private var drafts: [String: Draft] = [:]
    /// Changes made outside the current editor must reach whichever chat view is now on screen, even
    /// when a submission begins and finishes in the same event (as it does for Mac apps).
    @Published private(set) var draftUpdates: [String: UUID] = [:]

    func updateDraft(_ draft: Draft, for project: LampProject) {
        saveDraft(draft, for: project)
        draftUpdates[project.id] = UUID()
    }

    /// Tells every chat view of the app to take up its saved draft: what was typed in one editor (the wand's
    /// app's sidebar, `Sidebar`) reaches the other.
    func announceDraft(of project: LampProject) {
        draftUpdates[project.id] = UUID()
    }

    /// A drop can finish loading after its original chat view has gone away. Add its files to the
    /// latest saved input rather than writing that view's old words and replacement state back.
    func attach(_ files: [URL], to project: LampProject) {
        guard let current = current(project), !files.isEmpty else { return }
        var latest = draft(for: current)
        latest.attachments.append(contentsOf: files)
        updateDraft(latest, for: current)
    }

    /// What was pointed at in the app goes with the message being written, in place of anything pointed at before.
    func point(at pointed: PointedAt, in project: LampProject) {
        guard let current = current(project) else { return }
        var latest = draft(for: current)
        latest.pointed = pointed
        updateDraft(latest, for: current)
    }

    /// Each app keeps its own draft, so it's still there after switching apps. The text also survives a
    /// restart (.lamp/draft.txt), and so do the request it replaces and the text that was set aside for it;
    /// attached files are only remembered while Lamp runs, so after a restart a replaced request has the
    /// files it was sent with.
    func draft(for project: LampProject) -> Draft {
        if let draft = drafts[project.id] { return draft }
        let lamp = project.dir.appendingPathComponent(".lamp")
        let text = try? String(contentsOf: lamp.appendingPathComponent("draft.txt"), encoding: .utf8)
        let id = (try? String(contentsOf: lamp.appendingPathComponent("draft-replaces"), encoding: .utf8)).flatMap(UUID.init)
        guard let line = (logs[project.id] ?? []).first(where: { $0.id == id && $0.canSendAgain }) else {
            return Draft(text: text ?? "")
        }
        let setAside = try? String(contentsOf: lamp.appendingPathComponent("draft-set-aside.txt"), encoding: .utf8)
        let (attachments, pointed) = line.draftAttachments(in: project)
        return Draft(text: text ?? "", attachments: attachments, pointed: pointed, replacing: line.id, setAsideText: setAside ?? "")
    }

    func saveDraft(_ draft: Draft, for project: LampProject) {
        drafts[project.id] = draft
        // Written to disk a moment after typing stops, not on every keystroke.
        draftWrites[project.id]?.cancel()
        draftWrites[project.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.writeDraft(for: project)
        }
    }

    /// Writes every draft that's waiting for its pause, for when Lamp quits.
    func flushDrafts() {
        for project in projects where draftWrites[project.id] != nil {
            draftWrites[project.id]?.cancel()
            writeDraft(for: project)
        }
    }

    private var draftWrites: [String: Task<Void, Never>] = [:]

    private func writeDraft(for project: LampProject) {
        draftWrites[project.id] = nil
        guard exists(project), let draft = drafts[project.id] else { return }
        let file = project.dir.appendingPathComponent(".lamp/draft.txt")
        if draft.text.isEmpty {
            try? FileManager.default.removeItem(at: file)
        } else {
            try? draft.text.write(to: file, atomically: true, encoding: .utf8)
        }
        let replaces = project.dir.appendingPathComponent(".lamp/draft-replaces")
        if let id = draft.replacing {
            try? id.uuidString.write(to: replaces, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: replaces)
        }
        let setAside = project.dir.appendingPathComponent(".lamp/draft-set-aside.txt")
        if draft.replacing != nil, !draft.setAsideText.isEmpty {
            try? draft.setAsideText.write(to: setAside, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: setAside)
        }
    }

    func handle(url: URL) {
        if url.isFileURL && url.pathExtension == "lampapp" {
            importApp(from: url)
            return
        }
        if let wish = Wish.from(link: url) { return take(wish: wish) }
        guard url.scheme == Edition.urlScheme,
              let slug = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "app" })?.value else { return }
        // An app's sidebar, started while Lamp wasn't open: Lamp listens for it, and its own window stays put.
        if url.host == "sidebar" { return MagicPanel.shared.opening(slug) }
        // The app's Reload button, pressed while Lamp wasn't running (`LampMagic.Opener.reload`).
        if url.host == "reload" { return reloadWaiting(slug) }
        showChat(slug)
    }

    /// A wish the site's link brought (`Wish`). During the welcome it goes to the first-app box; after it, into
    /// the message box of a new app, written in a word at a time as the site writes. It is never sent from
    /// here: any web page can open such a link, so the person reads it and presses Send.
    func take(wish: String) {
        NSApp.activate()
        guard Onboarding.isDone || welcomeFinished else { arrivedWish = wish; return }
        // A second link goes into the app the first one made, while nothing has been sent there: a page that
        // keeps opening links can't fill Lamp with apps. Whatever was still being written in is there whole.
        for writer in wishWriting.values { writer.cancel() }
        wishWriting = [:]
        arrivals = [:]
        if let id = wishApp, let earlier = projects.first(where: { $0.id == id }), earlier.untitled, nothingAsked(of: id) {
            showChat(id)
        } else {
            create(fromSite: true)
        }
        guard let project = selected else { return }
        wishApp = project.id
        writeIn(wish, for: project)
    }

    /// Puts a wish in an app's message box, written in a word at a time. The draft is the whole wish at once,
    /// with whatever else it already held (a file dropped there): only the box's showing of it is written in,
    /// so Send at any moment sends all of it.
    func writeIn(_ wish: String, for project: LampProject) {
        wishWriting.removeValue(forKey: project.id)?.cancel()
        let whole = draft(for: project).taking(wish: wish)
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return updateDraft(whole, for: project) }
        arrivals[project.id] = Wish.Arrival(wish)
        updateDraft(whole, for: project)
        let id = project.id
        wishWriting[id] = Task {
            let steps = Wish.steps(wish)
            let pace = Wish.pace(words: steps.count)
            for step in steps {
                guard !Task.isCancelled, arrivals[id] != nil else { return }
                arrivals[id]?.advance(to: step)
                try? await Task.sleep(for: pace)
            }
            guard !Task.isCancelled else { return }
            arrivals[id] = nil
            wishWriting[id] = nil
        }
    }

    /// The box's text changed under an arriving wish, or it was sent: the writing is over.
    func endArrival(for id: String) {
        wishWriting.removeValue(forKey: id)?.cancel()
        if arrivals[id] != nil { arrivals[id] = nil }
    }

    /// Nothing has been asked of this app yet: no line in its chat, no turn running, and no request waiting
    /// on setup or in line. A request can be on its way with none of the first two (`beginSubmission`, `queued`).
    private func nothingAsked(of id: String) -> Bool {
        Self.nothingAsked(lines: logs[id]?.count ?? 0, busy: busy.contains(id), pending: pendingSubmissions.contains(id),
                          queued: queued[id] != nil)
    }

    nonisolated static func nothingAsked(lines: Int, busy: Bool, pending: Bool, queued: Bool) -> Bool {
        lines == 0 && !busy && !pending && !queued
    }

    /// A wish's chat in front, ready to type, where it is now: beside its Mac app when that's open with its chat in it,
    /// else in Lamp's panel beside whatever shows the wish, or on its own (`ChatPanel`). Lamp's window is the desk only.
    func showChat(_ id: String) {
        reload()
        offerStarterChanges(id, after: 0.5)
        selection = id
        if SidebarServer.shared.isConnected(id), let project = projects.first(where: { $0.id == id }),
           !macCopies(of: project).isEmpty, MagicPanel.runningCopiesTakeTheChat(project) {
            return MagicPanel.shared.openChat(in: project)
        }
        ChatPanel.show(id)
    }

    /// The wish an open chat window shows, following it to wherever its first request moved it. Its own id
    /// first: a new wish takes the folder name ("untitled") the last one was moved away from, and `moved` still
    /// points that name at the earlier wish.
    func project(following id: String) -> LampProject? {
        projects.first { $0.id == id } ?? moved[id].flatMap { to in projects.first { $0.id == to } }
    }

    /// A wish's chat window closed: a new wish nothing was asked of goes with it.
    func closedChat(_ id: String) {
        if let project = project(following: id) { discardIfUnused(project.id) }
    }

    // MARK: - Actions

    /// New: an untitled app, straight into its chat. Its first message names it and designs its icon.
    /// A Mac app until the intro says otherwise (`setKind`).
    func create(fromWelcome: Bool = false, fromSite: Bool = false, from desk: DeskStart? = nil) {
        // A draft: its scaffold waits for the first build (`materialize`), so the intro can still change its kind.
        lookForDevicesForWish()
        let project: LampProject
        do {
            project = try Template.draft(name: uniqueName("Untitled"), untitled: true, fromWish: fromSite,
                                         finding: desk == .finding, in: root)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        reload()
        showChat(project.id)
        Analytics.capture(.appCreated, ["source": fromSite ? "site" : fromWelcome ? "welcome" : desk?.rawValue ?? "new_app"])
    }

    /// How a wish was started on Lamp's desk (`WishDesk`).
    enum DeskStart: String { case typed = "desk", spoken = "desk_spoken", finding = "desk_finding" }

    /// A wish made on the desk goes straight to its chat, sent as if typed there (`SidebarServer.send`), so it goes
    /// through the same setup checks and lands in the same place.

    func wish(_ text: String, attachments: [URL] = [], spoken: Bool = false) {
        guard !text.trimmed.isEmpty || !attachments.isEmpty else { return }
        create(from: spoken ? .spoken : .typed)
        guard let project = selected else { return }
        updateDraft(Draft(text: text.trimmed, attachments: attachments), for: project)
        SidebarServer.shared.send(project)
    }

    /// Set Up… on a device Lamp doesn't know: a new wish whose first request asks the builder to write the device's
    /// integration (`device_integration`), with what the device said of itself. Like finding a wish, nothing is named,
    /// scaffolded or built until a wish for the device is sent.
    func setUpDevice(_ device: Device) {
        // One conversation per device: Set Up… again goes back to it, where it was left.
        if let earlier = projects.first(where: { $0.deviceSetup == device.id }) { return showChat(earlier.id) }
        let project: LampProject
        do {
            project = try Template.draft(name: "Set Up \(device.name)", deviceSetup: device.id, in: root)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        reload()
        showChat(project.id)
        updateDraft(Draft(text: Agent.deviceSetupRequest(device)), for: project)
        SidebarServer.shared.send(project)
    }

    /// A device's setup conversation follows its device from the address it was found at to the id an integration
    /// gives it, whichever look finds it that way (the integration's own, or any later one), so the setup window's
    /// Ask About Setup… and Set Up… lead back to it.
    func linkSetupConversations(to found: [Device]) {
        var changed = false
        for project in projects {
            guard let id = project.deviceSetup, id.hasPrefix("found:"),
                  let device = found.first(where: { $0.integration != nil && $0.address == String(id.dropFirst("found:".count)) }),
                  !projects.contains(where: { $0.deviceSetup == device.id }) else { continue }
            var linked = project
            linked.deviceSetup = device.id
            try? Template.saveMeta(linked)
            changed = true
        }
        if changed { reload() }
    }

    /// What a device's setup conversation may not do: everything that looks at, opens, builds or changes an app,
    /// since there is none. Only the integration, the skills, the notes and the chat's own cards are left.
    static func deviceSetupRefusal(route: String, request: Gateway.Request) -> (Int, [String: Any])? {
        let refusal = (400, ["error": "This conversation sets up a device; no app is made here. Write or fix the device's integration with device_integration, and tell the person to make a wish on Lamp's desk for anything to put on it."] as [String: Any])
        switch route {
        case "/agent/look", "/agent/use", "/agent/kind", "/agent/art", "/agent/versions", "/agent/versions/name", "/agent/versions/restore",
             "/agent/setup", "/agent/connectors":
            return refusal
        case "/agent/talk":
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            return body?["tool"] as? String == "write_wish" ? refusal : nil
        case "/mcp":
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any]
            guard body?["method"] as? String == "tools/call",
                  let name = (body?["params"] as? [String: Any])?["name"] as? String else { return nil }
            let allowed: Set<String> = ["device_integration", "read_skill", "ask", "progress", "read_notes", "save_notes"]
            guard !allowed.contains(name), !FileTools.names.contains(name) else { return nil }
            return (200, ["jsonrpc": "2.0", "id": body?["id"] ?? NSNull(),
                          "result": ["content": [["type": "text", "text": refusal.1["error"] as! String]], "isError": true]])
        default:
            return nil
        }
    }

    /// `device_integration`: the builder hands Lamp an integration. Lamp checks it and answers with what's wrong, or
    /// keeps it, looks for its devices now, and puts the next step of each one found that isn't set up in the chat.
    func agentIntegration(_ arguments: [String: Any], for project: LampProject) async -> (Int, [String: Any]) {
        let given = arguments["integration"]
        let data: Data?
        if let text = given as? String { data = Data(text.utf8) }
        else if let object = given, JSONSerialization.isValidJSONObject(object) { data = try? JSONSerialization.data(withJSONObject: object) }
        else { data = nil }
        guard let data else { return (400, ["error": "`integration` must be the integration as a JSON object."]) }
        let (kept, problems) = Integrations.submit(data)
        guard let integration = kept else {
            return (400, ["error": "Lamp didn't take the integration. Fix these and call device_integration again:\n" + problems.map { "- " + $0 }.joined(separator: "\n")])
        }
        let scan = Integrations.Scan(answers: await DeviceProbe.ssdp("ssdp:all", seconds: 2))
        var found: [Device] = []
        for address in await Integrations.addresses(for: integration, scan: scan) {
            if let device = await Integrations.identify(integration, at: address) { found.append(device) }
        }
        linkSetupConversations(to: found)
        // In the list at once, for the card below; the next look for devices keeps them while they answer.
        for device in found { devices.removeAll { $0.id == device.id }; devices.append(device) }
        refreshDevices()
        var text = "Lamp kept the \(integration.name) integration."
        if found.isEmpty {
            text += " No \(integration.name) answered on the network just now, by what find and identity say. If the person's is on, check those against the device's documentation; otherwise it's set up once it's found, from Settings → Building → Your Devices."
        }
        for device in found {
            let shown = (logs[project.id] ?? []).contains { $0.kind == .deviceStep && $0.text == device.id }
            if let step = Integrations.next(for: device) {
                if !shown { log(project, .deviceStep, device.id) }
                text += " Found \(device.name) (\(device.line)); its next step, \"\(step.title)\", is a card in the chat, which the person follows. It isn't set up until they have, so don't say it is, and don't repeat its steps in your words."
            } else {
                text += " Found \(device.name) (\(device.line)), already set up."
            }
        }
        return (200, ["text": text])
    }

    /// "Help me find one": a new wish whose first request asks the agent to find it with the person, in the
    /// chat, through its cards (`Agent.findRules`).
    func findWish() {
        create(from: .finding)
        guard let project = selected else { return }
        updateDraft(Draft(text: Agent.findingRequest), for: project)
        SidebarServer.shared.send(project)
    }

    /// The desk's window in front.
    func showDesk() {
        NSApp.activate()
        LampWindows.showDesk()
    }

    /// What's typed in the desk's wish bar and not sent: kept here, so going to a wish's chat and back keeps it.
    @Published var deskDraft = "" {
        didSet { if oldValue.isEmpty, !deskDraft.isEmpty { lookForDevicesForWish() } }
    }

    /// Goes up to put the cursor in the desk's wish bar (New Wish).
    @Published var deskFocusRequest = 0

    /// New Wish: the desk, ready to type.
    func newWish() {
        showDesk()
        deskFocusRequest += 1
    }

    /// Writes a draft's scaffold and makes its first version, before anything builds it. Nil, after saying so,
    /// when that fails: the app is left a draft (no Package.swift, which is what marks it set up), so the next
    /// request or Rebuild & Open writes it all again rather than building half a scaffold with no history.
    private func materialize(_ project: LampProject) async -> LampProject? {
        guard !project.scaffolded else { return project }
        var problem: String?
        do {
            try Template.fill(project)
            if !(await initRepo(project, message: "Scaffold")) { problem = "Lamp couldn't save the app's first version." }
        } catch {
            problem = error.localizedDescription
        }
        guard let problem else { return project }
        try? FileManager.default.removeItem(at: project.dir.appendingPathComponent("Package.swift"))
        try? FileManager.default.removeItem(at: project.dir.appendingPathComponent(DeviceApps.marker))
        log(project, .error, "Couldn't set up the app: \(problem) Try again in a moment.")
        return nil
    }

    /// What a new app is made as, worked out from its first request (`AppName.suggest`) before anything is built:
    /// nobody is asked to choose. A kind the person didn't say is only taken when this Mac can build it now
    /// (Xcode for an iPhone app; a team too for an app for both), else it's a Mac app, which needs neither, and
    /// the chat says so with the setup a button away (`IPhoneSetupLine`). One they said is taken either way, and
    /// the build says what's missing. A line in the chat says what it'll be unless it's a Mac app, and the person
    /// changes it by asking (`convert`, the agent's `make_app_for`).
    func chooseKind(_ project: LampProject, _ kind: Platform, said: Bool, watch: Bool = false, integration: String? = nil,
                    parts: [Platform] = [], places: [Destination]? = nil, engine: GameKit.Engine? = nil) async -> LampProject {
        guard !project.scaffolded, kind != project.platform || integration != project.integration else { return project }
        // A game is at home on the Mac, and played from the start wherever else the wish named (an Xbox: Lamp asks for
        // its tools only when it first goes there).
        // A screen is the same: at home on the Mac, shown from the start wherever else the wish named.
        if kind.addsPlaces {
            setKind(project, kind, places: places, engine: engine)
            guard let chosen = current(project) else { return project }
            let elsewhere = chosen.openPlaces.filter { $0 != .mac }
            let (what, verb) = kind == .screen ? ("a screen", "show") : ("a game", "play")
            log(chosen, .status, elsewhere.isEmpty ? "Making this as \(what) for your Mac."
                : "Making this as \(what) for your Mac, to \(verb) on \(GameKit.spoken(elsewhere)) too.")
            return chosen
        }
        // Not asked for and not buildable here yet: a Mac app, with the setup a button away (the kind's own check).
        guard await kind.target.setup.canChoose(said, integration) else {
            log(project, .iphoneSetup, kind.rawValue)
            return project
        }
        setKind(project, kind, integration: integration)
        guard let chosen = current(project) else { return project }
        if kind != Targets.fallback.platform {
            let devices = kind.target.identity.made(DeviceApps.integration(for: chosen)?.name, "your")
            let with = parts.map { ", with \(Parts.name(of: $0)) to go with it" }.joined()
            log(chosen, .status, watch ? "Making this for \(devices), and Apple Watch\(with)." : "Making this for \(devices)\(with).")
        }
        return chosen
    }

    /// Which of a wish's kinds is made first, in the wish's own folder, when nothing is written for it yet (a new wish,
    /// or one still to be told what it's for): no kind leads, so the first in Lamp's order, unless this Mac can't build
    /// that one yet and can another (a TV app with an iPhone app, on a Mac without Xcode: the TV app is made now and the
    /// iPhone app waits with its setup a click away, rather than the whole wish waiting). Nil for no kinds.
    private func firstKind(among kinds: [Platform], integration: String?) async -> Platform? {
        guard kinds.count > 1 else { return kinds.first }
        for kind in kinds where await kind.target.setup.canChoose(false, integration) { return kind }
        return kinds.first
    }

    /// A new wish whose request could be for more than one kind of device: it's kept a draft, with nothing written,
    /// and the agent asks which (`Agent.undecidedPrompt`) and gives it its kinds with `make_app_for` (`convert`).
    private func setUndecided(_ project: LampProject, _ candidates: [String]) -> LampProject {
        guard !project.scaffolded, let index = projects.firstIndex(where: { $0.id == project.id }) else { return project }
        var changed = projects[index]
        changed.undecided = candidates
        guard (try? Template.saveMeta(changed)) != nil else { return project }
        projects[index] = changed
        return changed
    }

    /// Adds a part of another kind to a wish (`Parts`): a folder of its own inside the wish's, with its meta.json and
    /// its kind's scaffold, which the wish's next version keeps. Nil, after saying why in `problem`, when this Mac can't
    /// build that kind yet or the folder can't be made.
    /// `setup` says the problem is this Mac's (the kind's tools aren't here), which its setup fixes; any other is said
    /// and not tried again by itself.
    /// `places`: for a game or a screen, where it's played or shown from the start, beside the Mac.
    func addPart(_ kind: Platform, to wish: LampProject, family: DeviceFamily? = nil, folder given: String? = nil,
                 places: [Destination]? = nil) async -> (part: LampProject?, problem: String?, setup: Bool) {
        guard let wish = current(wish), !wish.isPart else { return (nil, "Lamp can't find the wish.", false) }
        if let have = parts(of: wish).first(where: { $0.platform == kind }) { return (have, nil, false) }
        guard Parts.partKinds.contains(kind) else { return (nil, "Lamp can't make \(Parts.name(of: kind)) as a part of another wish yet.", false) }
        if let problem = await kind.target.setup.notReady(nil, Parts.name(of: kind)) { return (nil, problem, true) }
        // Files a shared wish brought for this part while this Mac couldn't make it: they go in over the scaffold, with
        // the family the file gave the part, unless the caller gives one.
        let kept = Sharing.kept(in: wish.dir, for: kind).flatMap { $0.package.platform == kind ? $0 : nil }
        // A part from a shared file is made in the folder it had there (`given`, or the one kept with its files), which
        // is its name among the wish's apps (`WishRooms.peer`): an iPhone app made for the Mac too stays the "iphone"
        // the others talk to, rather than coming in as the "apple" none of them knows.
        let folder = [given, kept?.folder].compactMap { $0 }.first { Parts.folder($0, canHold: kind) } ?? Parts.folder(for: kind)
        let dir = wish.dir.appendingPathComponent(folder)
        // The wish's folder is the agent's: what's there under the part's name must be a plain folder or nothing.
        if let type = (try? FileManager.default.attributesOfItem(atPath: dir.path))?[.type] as? FileAttributeType, type != .typeDirectory {
            return (nil, "\(folder)/ in the wish's folder isn't a folder: delete it first.", false)
        }
        do {
            try AppFolder.createDirectory(dir.appendingPathComponent(".lamp"), in: wish.dir)
            var part = LampProject(id: Parts.id(wish: wish.id, folder: folder), name: wish.name, exe: wish.exe, dir: dir,
                                   instance: Parts.instance(wish: wish, folder: folder), platform: kind,
                                   family: family ?? kept?.package.family ?? .iphone, partOf: wish.id)
            if kind.addsPlaces, let places {
                part.places = places
                part.integration = GameKit.integration(for: part)
            }
            try Template.saveMeta(part)
            try Template.fill(part)
            if let kept {
                try Sharing.install(kept.package, into: part)
                Sharing.forgetKept(in: wish.dir, for: kind)
            }
        } catch {
            return (nil, "Lamp couldn't make \(Parts.name(of: kind)): \(error.localizedDescription)", false)
        }
        setApps(wish, Parts.listing(kind, madeFor: wish, parts: parts(of: wish)))
        reload()
        return (projects.first { $0.id == Parts.id(wish: wish.id, folder: folder) }, nil, false)
    }

    /// Takes one of a wish's apps away, whichever it is: quit wherever it's open, what Lamp keeps for it forgotten
    /// (`forget`), and its files gone from the wish's folder (the wish's versions still have them). An app in a folder of
    /// its own goes with its folder. The one in the wish's own folder takes its files with it and leaves what's the
    /// wish's: its chat, meta.json and the rest of `.lamp/` but the app's runtime, its history, icon, description and
    /// attachments, and its other apps' folders; from then on every app of the wish is in a folder of its own
    /// (`holdsApp`). Never the last app, so a wish always has one.
    private func takeAway(_ app: LampProject) async -> Bool {
        guard let app = current(app), let wish = projects.first(where: { $0.id == (app.partOf ?? app.id) }),
              apps(of: wish).count > 1, await quit(app, for: turns[wish.id]) else { return false }
        // The wish no longer should have it: taken away, it isn't made again at the next turn. Only here: a restore has
        // already given the wish the list its version had (`Versions.restoreFiles`), which forgetting leaves alone.
        setApps(wish, wish.apps.filter { Parts.group($0.kind) != Parts.group(app.platform) })
        await settleFiles(wish)
        await forget(app)
        if app.isPart {
            AppFolder.remove(app.dir, in: wish.dir)
        } else {
            let fm = FileManager.default
            let kept = Set([".lamp", ".git", ".gitignore", "icon.json", AppDescription.file, Attachments.folder] + Parts.folders(in: wish.dir))
            for name in (try? fm.contentsOfDirectory(atPath: wish.dir.path)) ?? [] where !kept.contains(name) {
                AppFolder.remove(wish.dir.appendingPathComponent(name), in: wish.dir)
            }
            for name in ["runtime", "live"] { AppFolder.remove(wish.dir.appendingPathComponent(".lamp/" + name), in: wish.dir) }
        }
        reload()
        refreshOpenApps()
        return true
    }

    /// What Lamp keeps for an app of a wish that's gone (taken away, Undone, or its wish deleted), beyond its files: its
    /// place on the wish's list, its installed copy and widget's process, its copies on the person's devices, its phone
    /// build and signing folders, its sign-ins, and, for one in a folder of its own, its place in Lamp's lists. The same
    /// for every app of a wish, the one in its own folder too. Its data goes with its wish's (`trashData`, whose id it
    /// starts with); its files are the caller's to remove.
    private func forget(_ app: LampProject) async {
        let fm = FileManager.default
        // Not the wish's list: taking the app away takes it off (`takeAway`), and a restore has already given the wish
        // the list its version had (`Versions.restoreFiles`), which may still ask for this app while it waits to be made.
        // A build of it that waited for it to close goes in no more: quitting it to take it away would put it back.
        heldInstalls.installed(app.id)
        Runtime.releaseBuild(app)
        if app.hasMac {
            await WidgetProcess.end(for: app)
            // A wish's apps are installed under its name, so another of its Mac apps may be there: one of the apps it
            // has now (`everyApp`), never what a wish whose first app went still says of it.
            let shared = everyApp.contains { $0.id != app.id && $0.hasMac && $0.installedURL == app.installedURL }
            if !shared, fm.fileExists(atPath: app.installedURL.path) { try? fm.trashItem(at: app.installedURL, resultingItemURL: nil) }
        }
        if app.hasDevice {
            while installingApps.contains(app.id) { try? await Task.sleep(for: .milliseconds(300)) }
            await DeviceApps.removeEverywhere(app, among: devices)
            try? fm.removeItem(at: DeviceApps.buildFolder(for: app))
        }
        try? fm.removeItem(at: Devices.buildFolder(for: app))
        try? fm.removeItem(at: Devices.signingFolder(for: app))
        AppSecrets.forget(app: app.instance)
        // What its page saved in the TV preview, the values its wish's apps shared included.
        if app.platform.target.places.contains(where: [.tv, .device].contains) { TVPreview.forget(app) }
        simulatorApps[app.id] = nil
        stamps[app.id] = nil
        guard app.isPart else { return }
        queued[app.id] = nil
        projects.removeAll { $0.id == app.id }
        tokens = tokens.filter { $0.value != app.id }
    }

    /// A draft's kind: a draft only says what it will be, so this is a change to that, made while its first
    /// request is under way (`chooseKind`), before anything is written for it.
    private func setKind(_ project: LampProject, _ platform: Platform, integration: String? = nil, places: [Destination]? = nil,
                         engine: GameKit.Engine? = nil) {
        guard !project.scaffolded, let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        var changed = projects[index]
        changed.platform = platform
        changed.integration = platform.reaches(.device) ? integration : nil
        changed.places = platform.addsPlaces ? places : nil
        // A game on an Xbox is the Xbox's game kind there.
        if platform.addsPlaces {
            changed.engine = platform == .game ? engine?.rawValue : nil
            changed.integration = GameKit.integration(for: changed)
        }
        // Choosing what to make doesn't need installed tools. Send checks the selected simulator
        // before building and explains the next setup action without blocking this draft's picker.
        if !platform.reaches(.ios) { changed.device = nil }
        // An app for both starts on the Mac, where its first build is seen; Try On moves it.
        changed.chosen = .mac
        guard changed != projects[index], (try? Template.saveMeta(changed)) != nil else { return }
        projects[index] = changed
    }

    @discardableResult
    /// A wish's first version, saved as every other is (`Versions.commitAll`), so it carries the wish's list of apps:
    /// Undo back to it gives back an app the wish waits for (a shared file's part this Mac can't build yet, say).
    func initRepo(_ project: LampProject, message: String) async -> Bool {
        guard await Versions.git("git init -q", cwd: project.dir) == 0 else { return false }
        return await Versions.commitAll("-qm \"$LAMP_MESSAGE\"", in: project.dir, env: ["LAMP_MESSAGE": message]) == .saved
    }

    /// Which simulator an iPhone & iPad app opens in. Takes effect at its next open; the app is quit first
    /// so the other device gets a fresh launch.
    /// Which of the person's own phones Play puts the app on, or nil for the simulator. The agent keeps
    /// looking at the simulator either way, since the phone's screen can't be photographed from here.
    /// Which of the person's own phones Play puts the app on, or nil for a simulator, of `family` when given:
    /// one change, so a choice made from the Mac or from the other simulator lands whole. The iPhone copy is
    /// quit when it has to be opened afresh on another simulator; an app for both's Mac copy stays open (each
    /// copy keeps its pictures in its own folder, `Runtime.folder`).
    /// `simulator` names one simulator for the app's looks and opens (`Simulator.choices`); leaving it out
    /// keeps the one chosen, and `.some(nil)` goes back to Lamp's own pick of the family.
    func setDevice(_ project: LampProject, _ udid: String?, family: DeviceFamily? = nil, simulator: String?? = nil) {
        let family = family ?? project.family
        // A game not played on an iPhone or iPad yet is given them, as Try On's own "Play on iPhone and iPad Too" does.
        if project.platform.addsPlaces, !project.openPlaces.contains(.ios) {
            addPlace(project, .ios, family: family)
            return
        }
        let moving = project.platform.choosesPlace && project.destination != .ios
        let newSimulator = simulator ?? project.simulator
        let otherSimulator = newSimulator != project.simulator
        guard project.hasIOS, project.device != udid || project.family != family || moving || otherSimulator,
              begin(project) != nil else { return }
        clearPhoneRetry(project)
        var changed = project
        changed.device = udid
        changed.family = family
        changed.chosen = .ios
        changed.simulator = newSimulator
        try? Template.saveMeta(changed)
        if let index = projects.firstIndex(where: { $0.id == project.id }) { projects[index] = changed }
        syncLocalNetwork()
        let name = devices.first(where: { $0.udid == udid })?.name
        let said = name.map { "\(placeName(changed)) will open on \($0) from now on. Press Play to put it there." }
            ?? "\(placeName(changed)) will open on the \(simulatorName(changed)) simulator from now on."
        // A new place for the iPhone copy (another simulator, a phone, or back from a phone) retires the copy on
        // the old one, so Play and Stop are about the one chosen; an app for both's Mac copy stays open.
        let otherTarget = project.device != udid || (udid == nil && (project.family != family || otherSimulator))
        guard otherTarget else {
            log(changed, .status, said)
            finish(changed)
            return
        }
        Task {
            await quit(project, only: .ios)
            log(changed, .status, said)
            finish(changed)
        }
    }

    /// Which Android device an Android app opens on: the person's own, by its serial, or nil for the emulator.
    /// The copy on the old one is closed, so Play and Stop are about the one chosen.
    func setAndroidDevice(_ project: LampProject, _ serial: String?) {
        // A game has Android among its places, and may be pointed at another of them now.
        let reaches = project.onAndroid || (GameKit.isGame(project) && project.openPlaces.contains(.android))
        guard reaches, project.device != serial || !project.onAndroid, begin(project) != nil else { return }
        var changed = project
        changed.device = serial
        changed.chosen = .android
        try? Template.saveMeta(changed)
        if let index = projects.firstIndex(where: { $0.id == project.id }) { projects[index] = changed }
        syncLocalNetwork()   // the device reaches Lamp's gateway over the Wi‑Fi
        let name = devices.first(where: { $0.udid == serial })?.name
        let said = name.map { "\(changed.name) will open on \($0) from now on. Press Play to put it there." }
            ?? "\(changed.name) will open in the emulator from now on."
        Task {
            await quit(project)
            log(changed, .status, said)
            finish(changed)
        }
    }

    /// Which TV a TV app goes on when the person presses Play, by its id in `TVs`, or nil for the preview alone. A TV
    /// not set up yet is set up first (`TVSetup`), and chosen once it's ready.
    func setTVDevice(_ project: LampProject, _ id: String?) {
        // A screen has TVs among its places, and may be pointed at one of them now.
        let reaches = project.onTV || (project.platform.addsPlaces && project.openPlaces.contains(.tv))
        guard reaches, project.device != id || !project.onTV else { return }
        let choose = { [self] in
            guard let current = current(project), begin(current) != nil else { return }
            var changed = current
            changed.device = id
            changed.chosen = .tv
            try? Template.saveMeta(changed)
            if let index = projects.firstIndex(where: { $0.id == current.id }) { projects[index] = changed }
            let name = devices.first(where: { $0.udid == id })?.name
            log(changed, .status, name.map { "\(placeName(changed)) will go on \($0) when you press Play." } ?? "\(placeName(changed)) will open in the TV preview from now on.")
            finish(changed)
            refreshOpenApps()
            syncLocalNetwork()   // the TV reaches Lamp's gateway over the Wi‑Fi
        }
        if let id { TVSetup.shared.perform(id, then: choose) } else { choose() }
    }

    /// Which of the person's devices a device app goes on (`DeviceApps`), by its id as its integration found it. One not
    /// set up yet is set up first, in its setup window, and chosen once it's ready.
    func setDeviceAppDevice(_ project: LampProject, _ id: String) {
        // A game has the Xbox among its places, and may be pointed at another of them now.
        let reaches = project.onDevice || (project.platform.addsPlaces && project.openPlaces.contains(.device))
        guard reaches, let device = devices.first(where: { $0.id == id }) else { return }
        let choose = { [self] in
            guard let current = current(project), current.device != id || !current.onDevice, begin(current) != nil else { return }
            var changed = current
            changed.device = id
            changed.chosen = .device
            try? Template.saveMeta(changed)
            if let index = projects.firstIndex(where: { $0.id == current.id }) { projects[index] = changed }
            log(changed, .status, "\(changed.name) will go on \(device.name) when you press Play.")
            finish(changed)
        }
        DeviceSetupWindow.show(device, then: choose)
    }

    /// Back to a simulator from a phone, as one change: the family is set on the project as it is after
    /// the phone is forgotten, not on the copy the menu held.
    func setSimulator(_ project: LampProject, _ family: DeviceFamily) {
        guard Self.opens(project, on: family) else { return }
        setDevice(project, nil, family: family, simulator: .some(nil))
    }

    /// One simulator by name, from Try On's list.
    func setSimulator(_ project: LampProject, _ choice: Simulator.Choice) {
        guard Self.opens(project, on: choice.family) else { return }
        setDevice(project, nil, family: choice.family, simulator: .some(choice.udid))
    }

    /// Whether an app can open on a simulator of this family: Apple TV and Vision Pro take an app's own SwiftUI code built
    /// for them, never a game's or a screen's host, which is iOS's.
    static func opens(_ project: LampProject, on family: DeviceFamily) -> Bool {
        !family.isOtherOS || project.platform.target.otherSystems
    }

    /// Every simulator Try On can offer, looked up when the menu opens.
    @Published var simulators: [Simulator.Choice] = []

    func refreshSimulators() {
        Task { simulators = await Simulator.choices() }
    }

    /// The simulator an iOS app opens on, as the person would call it: the one chosen by name, or the family.
    func simulatorName(_ project: LampProject) -> String {
        project.simulator.flatMap { udid in simulators.first { $0.udid == udid }?.name } ?? project.family.name
    }

    /// The person's iPhones, iPads and Apple Watches (`Device`), for Try On, Settings → Building and the agent's
    /// note. Looked up when the list is wanted (opening the menu) and at startup; a phone that's gone stays
    /// chosen, and Play says so.
    @Published var devices: [Device] = []
    /// This Mac as a device, read when the list is, so the agent's note never waits for it.
    @Published var thisMac: Device?

    /// What Try On shows beside Play: the simulator's kind, or the chosen phone's name, or this Mac.
    func tryOnName(_ project: LampProject) -> String {
        if project.onDevice, GameKit.isGame(project) {
            return DeviceApps.device(for: project, among: devices)?.name ?? "Xbox"
        }
        if project.onDevice {
            let name = DeviceApps.integration(for: project)?.name ?? "Device"
            return DeviceApps.device(for: project, among: devices)?.name ?? (project.device == nil ? "Choose a \(name)" : "Your \(name)")
        }
        if project.onTV {
            guard let id = project.device else { return "TV Preview" }
            return devices.first(where: { $0.udid == id })?.name ?? "Your TV"
        }
        if project.onAndroid {
            guard let serial = project.device else { return "Emulator" }
            return devices.first(where: { $0.udid == serial })?.name ?? "Your device"
        }
        guard project.onIOS else { return "My Mac" }
        guard let udid = project.device else { return simulatorName(project) }
        return devices.first(where: { $0.udid == udid })?.name ?? "Your phone"
    }

    /// An app for both, back on this Mac: Try On's "My Mac". Its next open is a Mac build; the iOS copy stays
    /// open, and Stop quits it once Try On points there again.
    /// Gives a game a place to be played besides those it has (an iPhone or iPad, an Xbox), and points Try On there so
    /// the person sees it: the same game, never another kind (`setPlaces`).
    func addPlace(_ project: LampProject, _ place: Destination, family: DeviceFamily? = nil) {
        guard let current = current(project), !current.openPlaces.contains(place), begin(current) != nil else { return }
        Task {
            let said = await setPlaces(current, current.openPlaces + [place], family: family)
            // A place refused is said in the chat, where the click was: setPlaces says only what it changed.
            if self.current(current)?.openPlaces == current.openPlaces { log(current, .status, said) }
            finish(self.current(current) ?? current)
        }
    }

    /// The places a game is played from now on: the Mac always, its home, and each other one given. A place given is
    /// where it opens next; a copy on a place taken away is quit. What each new place needs (Xcode and a simulator for
    /// an iPhone, the console's tools and the Xbox itself) is asked for when the game first goes there, not now. Returns
    /// what changed, in words for the agent, or why nothing did.
    func setPlaces(_ project: LampProject, _ wanted: [Destination], family: DeviceFamily? = nil) async -> String {
        guard let current = current(project), current.platform.addsPlaces else { return "Lamp can't find the game." }
        let target = current.platform.target
        // A game in C++, made before three.js games, is played on the Xbox alone.
        if GameKit.isGame(current), GameKit.engine(current) == .native, wanted.filter({ $0 != .mac }) != [.device] {
            return "This game is written in C++ for the Xbox, and is played there alone. A three.js game, a new wish, plays everywhere."
        }
        // A game's and a screen's home is the Mac, kept whatever's asked (a C++ game's is the Xbox alone, above).
        let native = GameKit.isGame(current) && GameKit.engine(current) == .native
        let places = native ? [.device] : target.places.filter { $0 == .mac || wanted.contains($0) }
        let added = places.filter { !current.openPlaces.contains($0) }, gone = current.openPlaces.filter { !places.contains($0) }
        guard !added.isEmpty || !gone.isEmpty || family.map({ $0 != current.family }) == true else {
            return "It's already \(current.platform == .screen ? "shown" : "played") on \(GameKit.spoken(places))."
        }
        if places.contains(.device), Integrations.integration(GameKit.xbox) == nil { return "This copy of Lamp has no way to reach an Xbox." }
        for place in gone where place == .ios { await quit(current, only: .ios) }
        guard let now = self.current(current), let index = projects.firstIndex(where: { $0.id == now.id }) else { return "Lamp can't find the game." }
        var changed = now
        changed.places = places
        changed.integration = GameKit.integration(for: changed)
        if let family { changed.family = family }
        if let place = added.last {
            changed.chosen = place
            // Where it goes in that place is chosen afresh: the simulator, and the only Xbox found until one is chosen.
            changed.device = nil
            changed.simulator = place == .ios ? nil : changed.simulator
        } else if family != nil, places.contains(.ios) {
            changed.chosen = .ios
        } else if !places.contains(changed.chosen) {
            changed.chosen = places[0]
        }
        do { try Template.saveMeta(changed) } catch { return "Lamp couldn't save the change: \(error.localizedDescription)" }
        projects[index] = changed
        syncLocalNetwork()
        var said: [String] = []
        let screen = changed.platform == .screen
        if !added.isEmpty { said.append("\(changed.name) \(screen ? "shows" : "plays") on \(GameKit.spoken(added)) too now.") }
        if !gone.isEmpty { said.append("\(changed.name) isn't \(screen ? "shown" : "played") on \(GameKit.spoken(gone)) any more.") }
        log(changed, .status, said.joined(separator: " "))
        if added.contains(.device), DeviceApps.device(for: changed, among: devices) == nil { refreshDevices() }
        return said.joined(separator: " ")
    }

    /// The places an app could be given and hasn't yet, for Try On's "… Too": none for a C++ game, which is the Xbox's.
    static func placesToAdd(_ project: LampProject) -> [Destination] {
        guard project.platform.addsPlaces, !(GameKit.isGame(project) && GameKit.engine(project) == .native) else { return [] }
        return project.platform.target.places.filter { !project.openPlaces.contains($0) }
    }

    func setMac(_ project: LampProject) {
        guard project.platform.choosesPlace, project.hasMac, project.destination != .mac, begin(project) != nil else { return }
        var changed = project
        changed.chosen = .mac
        try? Template.saveMeta(changed)
        if let index = projects.firstIndex(where: { $0.id == project.id }) { projects[index] = changed }
        syncLocalNetwork()
        log(changed, .status, "\(changed.name) will open on this Mac from now on.")
        finish(changed)
    }

    /// Pairs a plugged-in phone that hasn't trusted this Mac yet, then lists again. Told in the app's chat,
    /// where the person is looking, as the Try On menu is the app's.
    /// Settings → Building pairs with no app open: then nothing is said in a chat, and the row says where it got.
    func pairDevice(_ device: Device, for project: LampProject?) {
        guard !pairing.contains(device.udid) else { return }
        pairing.insert(device.udid)
        if let project { log(project, .status, "Look at \(device.name): tap Trust when it asks, and enter its passcode.") }
        Task {
            defer { pairing.remove(device.udid) }
            // The chat may have moved meanwhile: a first message renames a new app under a new id.
            @MainActor func tell(_ kind: LogLine.Kind, _ text: String) {
                if let project, let now = current(project) { log(now, kind, text) }
            }
            do {
                try await Devices.pair(device.udid)
                devices = await Devices.list()
                guard let paired = devices.first(where: { $0.udid == device.udid }), paired.paired else {
                    // Paired, as far as devicectl said, but not in the list now: unplugged, or the listing
                    // failed. Not a word about Developer Mode until the phone is seen again.
                    tell(.status, "\(device.name) said yes, but it isn't in the list now. Plug it in, unlock it and choose Look for Devices Again under Try On.")
                    return
                }
                if paired.developerMode {
                    tell(.status, "\(device.name) is paired with this Mac. Choose it under Try On and press Play.")
                } else {
                    tell(.status, "\(device.name) is paired with this Mac. Now turn on Developer Mode on it (Settings → Privacy & Security → Developer Mode; the phone restarts), then choose it under Try On.")
                }
            } catch {
                tell(.error, error.localizedDescription)
                devices = await Devices.list()
            }
        }
    }

    /// Phones being paired right now, so the menu doesn't offer it twice.
    @Published var pairing: Set<String> = []

    /// Whether a look for devices is going on, so what asked for it can say so: it takes a few seconds and most often
    /// finds the same devices, which without a sign looked like nothing happened.
    @Published private(set) var lookingForDevices = false
    /// Counts looks, so only the latest one's findings are kept: an earlier one that ends later is out of date.
    private var deviceLook = 0
    /// When the last look ended, so a new wish doesn't look again within a moment of one (`lookForDevicesForWish`).
    private var devicesLookedAt: Date?

    func refreshDevices() {
        deviceLook += 1
        let look = deviceLook
        lookingForDevices = true
        Task {
            defer {
                if look == deviceLook {
                    lookingForDevices = false
                    devicesLookedAt = Date()
                }
            }
            // Apple's devices, Android's when Android's tools are here (adb is one of them), and the TVs on the network.
            async let apple = Devices.list()
            async let android = Adb.devices()
            async let tvs = TVs.devices()
            let kits = await apple + android + tvs
            // What integrations find, and what's on the network that nothing Lamp has knows, after the kits' own.
            let found = kits + (await Integrations.devices(known: Set(kits.compactMap(\.address))))
            guard look == deviceLook else { return }
            if found != devices { devices = found }
            linkSetupConversations(to: found)
            let mac = await Device.readThisMac()
            if mac != thisMac { thisMac = mac }
        }
    }

    /// A new wish may be for one of the person's devices ("tetris on my TV", "something for my Roku"), so one is
    /// looked for as a wish begins: when something is typed in the desk's bar, when a new wish is made, and as its
    /// first request is named. A look from the last two minutes does.
    func lookForDevicesForWish() {
        guard !lookingForDevices else { return }
        if let at = devicesLookedAt, Date().timeIntervalSince(at) < 120 { return }
        refreshDevices()
    }

    /// The devices a new wish's naming call is told of (`AppName.suggest`): the look going on is waited for, a few
    /// seconds at most, since the wish waits on it; one that takes longer leaves what the last look found.
    func devicesForWish() async -> [Device] {
        lookForDevicesForWish()
        // Checked every fifth of a second rather than awaited: the look's own task can't be cut short, and waiting on
        // it in a group would wait for it to end, however long that took.
        let until = Date().addingTimeInterval(5)
        while lookingForDevices, Date() < until { try? await Task.sleep(for: .milliseconds(200)) }
        return devices
    }

    /// An untitled app you left without ever using is deleted, so trying New leaves nothing behind.
    /// Words in its message box count as using it: they're kept, like a draft in any other app.
    private func discardIfUnused(_ id: String) {
        guard let project = projects.first(where: { $0.id == id }), project.untitled, nothingAsked(of: id),
              draft(for: project).text.trimmed.isEmpty,
              !FileManager.default.fileExists(atPath: project.builtURL.path) else { return }
        settleChat(project)
        try? FileManager.default.removeItem(at: project.dir)
        projects.removeAll { $0.id == id }
    }

    /// Nothing has happened in the app but its scaffold, so it can still change its folder and executable name.
    private func isPristine(_ project: LampProject) async -> Bool {
        var output: [String] = []
        let status = await Versions.git("test $(git rev-list --count HEAD) -eq 1 && git status --porcelain -- . ':!\(Attachments.folder)'",
                                     cwd: project.dir) { output.append($0) }
        return status == 0 && output.allSatisfy { $0.trimmed.isEmpty }
    }

    /// Renames an app. Before any work happens it is scaffolded afresh under the new name, so its folder,
    /// executable and bundle ID match. After that only the display name changes: the bundle ID stays,
    /// so the app keeps its settings and data. Returns the app as it is now.
    func rename(_ project: LampProject, to name: String) async {
        // A wish still being found has no name to give: the wish it becomes names it (`startQueued`), and a
        // rename now would end the finding before the wish is.
        guard !project.makesNoApp, begin(project) != nil else { return }
        finish(await performRename(project, to: name))
    }

    /// Renames while the app is marked busy, so nothing else starts on it meanwhile.
    private func performRename(_ project: LampProject, to rawName: String) async -> LampProject {
        let name = rawName.trimmed.filter { !"\"\\<>&/:".contains($0) && !$0.isNewline }
        guard !name.isEmpty, name != project.name || project.untitled,
              let current = projects.first(where: { $0.id == project.id }) else { return project }
        let unique = uniqueName(name, ignoring: current.id)
        if !current.scaffolded {
            return renameDraft(current, to: unique)
        }
        // Made again from Lamp's scaffold, a wish would leave its other parts' folders behind.
        if current.partFolders.isEmpty, await isPristine(current) {
            return await rescaffold(current, as: unique)
        }

        let renamed = await giveName(unique, to: current)
        // Every app of the wish carries its name.
        for dir in [current.dir] + parts(of: current).map(\.dir) { Self.retitle(dir, from: current.name, to: unique) }
        // Lamp's own files carry the name: written under the new one before the version is saved, so the next build
        // doesn't leave the app unsaved, and going back to this version brings them back as they go with its name.
        try? Template.writeOwnedFiles(for: renamed)
        for part in Parts.load(renamed) { try? Template.writeOwnedFiles(for: part) }
        // A version of its own even when no file named the app, carrying both names, so Undo gives the old one back.
        _ = await Versions.save(current, message: "Rename to \(unique)",
                                trailer: Versions.nameTrailers(from: current.name, to: unique), allowEmpty: true)
        reload()
        log(renamed, .status, "Renamed to \(unique)")
        return renamed
    }

    /// The app under another name in Lamp: its meta.json, and its installed copy moved to the new name. The bundle ID
    /// stays, so it keeps its settings and data. Its other parts take the wish's name as Lamp reads them again.
    private func giveName(_ name: String, to current: LampProject) async -> LampProject {
        let renamed = current.named(name)
        try? Template.saveMeta(renamed)
        // Every app of the wish is installed under its name, so each installed copy goes with it: the wish's own app's,
        // and each in a folder of its own's (`installedURL`).
        let moves = [(current.installedURL, renamed.installedURL)]
            + (current.isPart ? [] : parts(of: current).map { ($0.installedURL, $0.named(name).installedURL) })
        let fm = FileManager.default
        for (from, to) in moves where from != to && fm.fileExists(atPath: from.path) && !fm.fileExists(atPath: to.path) {
            try? fm.moveItem(at: from, to: to)
            _ = await Shell.run(Self.lsregister + " -f \"$LAMP_APP\"", cwd: current.dir, env: ["LAMP_APP": to.path]) { _ in }
        }
        return renamed
    }

    /// The name a restore to `target` gives back (`Versions.name(at:in:)`), when it isn't the app's name now: an Undo of
    /// a rename, or going back to a version from before one. Unique among the other apps, as a rename's is.
    private func renaming(_ project: LampProject, to target: AppVersion, in versions: [AppVersion]) -> (from: String, to: String)? {
        guard let name = Versions.name(at: target, in: versions), name != project.name else { return nil }
        return (project.name, uniqueName(name, ignoring: project.id))
    }

    /// After a restore that gave a name back, the app under that name.
    private func takeName(_ renaming: (from: String, to: String)?, _ restored: LampProject) async -> LampProject {
        guard let renaming, let now = current(restored) else { return restored }
        let renamed = await giveName(renaming.to, to: now)
        reload()
        return current(renamed) ?? renamed
    }

    /// The old name in window titles and APP.md. Anything subtler is left for the agent.
    private static func retitle(_ dir: URL, from old: String, to new: String) {
        let fm = FileManager.default
        let sources = dir.appendingPathComponent("Sources")
        let files = (fm.enumerator(at: sources, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "LampSupport.swift" }
        // Read as `AppFile` reads: written back in place, a file read through a link would bring what it leads to
        // into the app's folder.
        for file in files {
            guard let text = AppFile.text(file, inFolder: dir) else { continue }
            let updated = text.replacingOccurrences(of: "\"\(old)\"", with: "\"\(new)\"")
            if updated != text { try? updated.write(to: file, atomically: true, encoding: .utf8) }
        }
        let appMd = dir.appendingPathComponent("APP.md")
        if let text = AppFile.text(appMd, inFolder: dir), text.hasPrefix("# \(old)\n") {
            try? ("# \(new)\n" + text.dropFirst(old.count + 3)).write(to: appMd, atomically: true, encoding: .utf8)
        }
    }

    /// What of `.lamp` a copy takes: what the app is (its notes, its model choices, its icon's artwork, the
    /// pictures and titles of the versions it shares). Not its chat, cost, engine conversations or secrets:
    /// the copy is an app of its own, and those are made afresh when it first needs them.
    private static let duplicatedState = [".lamp/notes.md", ".lamp/models.json", ".lamp/art",
                                          ".lamp/versions", ".lamp/version-titles.json"]

    /// Makes a copy of an app to try a variation on: "<name> copy", with the same code, history and
    /// icon artwork on a different background, so the two tell apart at a glance. Then builds it.
    func duplicate(_ project: LampProject) async {
        guard project.scaffolded, !project.untitled, begin(project) != nil else { return }
        let fm = FileManager.default
        let name = uniqueName("\(project.name) copy")
        let exe = Template.identifier(from: name)
        let slug = Template.freeSlug(for: exe, in: root)
        // Everything it is comes along (its kind, where it opens, a game's places and engine, the apps the wish should
        // have and what each waits for): the copy is the same wish under another name and identity.
        var copy = project.named(name, id: slug, exe: exe, dir: root.appendingPathComponent(slug))
        copy.instance = UUID().uuidString
        copy.decided = false
        do {
            try fm.createDirectory(at: copy.dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
            // Everything at the top but what a build makes again (Lamp's own files are rewritten before it).
            for item in try fm.contentsOfDirectory(atPath: project.dir.path) where ![".lamp", "build", ".build"].contains(item) {
                try fm.copyItem(at: project.dir.appendingPathComponent(item), to: copy.dir.appendingPathComponent(item))
            }
            // Each other app of the wish the same way: what its build makes, its runtime and its conversations stay
            // behind, and its meta.json, which says where it opens, comes along.
            for part in parts(of: project) {
                let folder = copy.dir.appendingPathComponent(part.dir.lastPathComponent)
                for made in [".lamp", "build", ".build"] { try? fm.removeItem(at: folder.appendingPathComponent(made)) }
                try fm.createDirectory(at: folder.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
                let meta = part.dir.appendingPathComponent(".lamp/meta.json")
                if fm.fileExists(atPath: meta.path) { try fm.copyItem(at: meta, to: folder.appendingPathComponent(".lamp/meta.json")) }
            }
            for path in Self.duplicatedState where fm.fileExists(atPath: project.dir.appendingPathComponent(path).path) {
                try fm.copyItem(at: project.dir.appendingPathComponent(path), to: copy.dir.appendingPathComponent(path))
            }
            try Template.saveMeta(copy)
            for dir in [copy.dir] + parts(of: project).map({ copy.dir.appendingPathComponent($0.dir.lastPathComponent) }) {
                Self.retitle(dir, from: project.name, to: name)
            }
            if let spec = Icons.load(project) {
                var recolored = spec
                recolored.background = otherBackground(than: spec).name
                // The same artwork, filed under the new background so the copy's icon finds it. A glass design is
                // made of the background's shades, so it takes the new background's hue.
                if let glass = GlassArt.load(from: Icons.glassURL(copy, spec: spec)) {
                    let hue = Icons.background(named: recolored.background).bottom
                    try? Icons.save(GlassArt(design: glass.design.recolored(to: hue), paintings: glass.paintings),
                                    for: copy, spec: recolored)
                } else if fm.fileExists(atPath: Icons.artURL(copy, spec: spec).path) {
                    try? fm.copyItem(at: Icons.artURL(copy, spec: spec), to: Icons.artURL(copy, spec: recolored))
                }
                Icons.save(recolored, for: copy)
            }
            // Lamp's own files as the copy's build writes them, so its first version is what it builds and
            // it starts with nothing unsaved; its other apps' too.
            try Template.writeOwnedFiles(for: copy)
            if let read = Store.readWish(at: copy.dir) { for part in Parts.load(read) { try Template.writeOwnedFiles(for: part) } }
        } catch {
            try? fm.removeItem(at: copy.dir)
            finish(project)
            NSAlert(error: error).runModal()
            return
        }
        // Listed before the original is given back, so a second Duplicate can't choose the same name.
        reload()
        finish(project)
        guard begin(copy) != nil else { return }
        _ = await Versions.commitAll("-qm \"$LAMP_MESSAGE\"", in: copy.dir, env: ["LAMP_MESSAGE": "Copy of \(project.name)"])
        if let spec = Icons.load(copy) { await renderIcon(copy, spec: spec) }
        finish(copy)
        showChat(copy.id)
        log(copy, .status, "A copy of \(project.name). Building it now…")
        await run(copy)
        await rebuildParts(of: current(copy) ?? copy)
    }

    /// A background for a copy's icon: not the one it was copied from, as light or dark as that one so the
    /// artwork and symbol still sit well on it, and where possible one no other app with the same icon uses.
    private func otherBackground(than spec: IconSpec) -> Icons.Background {
        let current = Icons.background(named: spec.background)
        let candidates = Icons.backgrounds.filter { $0.name != current.name && $0.isLight == current.isLight }
        let taken = Set(projects.compactMap(Icons.load).filter { $0.subject == spec.subject }.map(\.background))
        let fresh = candidates.filter { !taken.contains($0.name) }
        return (fresh.isEmpty ? candidates : fresh).randomElement() ?? current
    }

    /// Replaces an untouched app with a fresh scaffold under its new name, carrying over its chat and queue.
    private func rescaffold(_ old: LampProject, as name: String) async -> LampProject {
        let fm = FileManager.default
        let project: LampProject
        do {
            // The same app under its new name: it keeps its identity, so a snapshot from before still finds it.
            var made = try Template.scaffold(name: name, platform: old.platform, family: old.family, instance: old.instance, in: root)
            // Where it opens comes along too: the device it was put on, and the simulator chosen by name.
            made.device = old.device
            made.chosen = old.chosen
            made.simulator = old.simulator
            try Template.saveMeta(made)
            project = made
        } catch {
            NSAlert(error: error).runModal()
            return old
        }
        settleChat(old)
        for path in [".lamp/chat.json", ".lamp/usage.json", ".lamp/notes.md", ".lamp/share-id", Attachments.folder, Sharing.Assets.folder] {
            let from = old.dir.appendingPathComponent(path)
            if fm.fileExists(atPath: from.path) {
                try? fm.copyItem(at: from, to: project.dir.appendingPathComponent(path))
            }
        }
        await initRepo(project, message: "Scaffold")
        await quit(old)
        await WidgetProcess.end(for: old)
        try? fm.removeItem(at: old.installedURL)
        try? fm.removeItem(at: Devices.buildFolder(for: old))
        try? fm.removeItem(at: Devices.signingFolder(for: old))
        // Lines logged while the copy was made and the old app quit are written to the new folder instead.
        await settleFiles(old)
        settleChat(old)
        try? fm.removeItem(at: old.dir)

        if let device = old.device {   // the phone chosen before the first message stays chosen
            var kept = project
            kept.device = device
            try? Template.saveMeta(kept)
        }
        follow(old, to: project)
        saveChat(project)
        return project
    }

    /// A draft has no files yet to name after the app, so renaming it is moving its folder to match.
    private func renameDraft(_ old: LampProject, to name: String) -> LampProject {
        let exe = Template.identifier(from: name)
        let slug = exe.lowercased() == old.id ? old.id : Template.freeSlug(for: exe, in: root)
        let project = old.named(name, id: slug, exe: exe, dir: root.appendingPathComponent(slug))
        do {
            if slug != old.id {
                settleChat(old)
                try FileManager.default.moveItem(at: old.dir, to: project.dir)
            }
            try Template.saveMeta(project)
        } catch {
            log(old, .error, "Couldn't rename the app: \(error.localizedDescription)")
            return old
        }
        follow(old, to: project)
        return project
    }

    /// Carries what Lamp holds for an app over to the id it has now.
    private func follow(_ old: LampProject, to project: LampProject) {
        guard old.id != project.id else {
            reload()
            return
        }
        // Rewritten so every entry points straight at the latest id: a slug that comes free and is used
        // again (A → B → A) would otherwise close a loop. Nothing points at the new id afterwards.
        for (from, to) in moved where to == old.id { moved[from] = project.id }
        moved = moved.filter { $0.key != project.id }
        moved[old.id] = project.id
        pendingSubmissions.move(from: old.id, to: project.id)
        if let draft = drafts.removeValue(forKey: old.id) { drafts[project.id] = draft }
        draftWrites.removeValue(forKey: old.id)?.cancel()
        logs[project.id] = logs.removeValue(forKey: old.id)
        if chatsToSave.remove(old.id) != nil { chatsToSave.insert(project.id) }
        // The chat file moved with the folder, still holding what wasn't copied: its saves stay held back.
        unkeptChats[project.id] = unkeptChats.removeValue(forKey: old.id)
        usage[project.id] = usage.removeValue(forKey: old.id)
        queued[project.id] = queued.removeValue(forKey: old.id)
        if let turn = turns.removeValue(forKey: old.id) {   // the rename itself is a turn: it moves with the app
            turns[project.id] = turn
            agentTokens[turn.agentToken] = project.id
            busy.remove(old.id)
            busy.insert(project.id)
        }
        if unread.remove(old.id) != nil { unread.insert(project.id) }
        tokens = tokens.filter { $0.value != old.id }
        reload()
        ChatPanel.moved(old.id, to: project.id)
        if selection == old.id { selection = project.id }
    }

    /// Where an app's chat went when its first message rescaffolded it under a new id, so something started
    /// on the old app (pairing a phone, say) can still speak in the right chat.
    private var moved: [String: String] = [:]

    /// The app as it is now, following any rescaffold since `project` was taken (one step: `moved` always
    /// points straight at the latest id).
    func current(_ project: LampProject) -> LampProject? {
        // The app itself, under whatever folder it has now; the folder's id only for apps from before
        // instances existed, and the signpost for a snapshot of an app that moved since.
        if !project.instance.isEmpty, let same = projects.first(where: { $0.instance == project.instance }) { return same }
        return projects.first { $0.id == moved[project.id] ?? project.id }
    }

    /// Display names must be unique: each app installs as "<name>.app" in the apps folder (Edition.appsFolder).
    private func uniqueName(_ name: String, ignoring id: String? = nil) -> String {
        // A wish's other parts carry its name, and are no other app holding it.
        // A newer Lamp's wish keeps its name too: its installed copy is found by it.
        let taken = Set(projects.filter { $0.id != id && ($0.partOf == nil || $0.partOf != id) }.map { $0.name.lowercased() }
                        + newerWishes.map { $0.name.lowercased() })
        let base = name.trimmed
        var candidate = base
        var n = 2
        while taken.contains(candidate.lowercased()) {
            candidate = "\(base) \(n)"
            n += 1
        }
        return candidate
    }

    // MARK: - Sharing

    func chooseImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.lampApp]
        panel.message = "Choose a Lamp app someone shared with you"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importApp(from: url)
    }

    /// Puts the app's .lampapp file on the clipboard with its picture, ready to paste into a message: a chat
    /// shows the picture large beside the file, where the file alone is a blank document.
    func canShare(_ project: LampProject) -> Bool { project.scaffolded }

    func copyAppFile(_ project: LampProject) {
        guard canShare(project) else { return }
        Task { await copyAppFile(project, icon: Sharing.sharedIcon(of: project)) }
    }

    private func copyAppFile(_ project: LampProject, icon: Data?) {
        do {
            let file = try Self.sharedFile(of: project, icon: icon)
            // Two files, as Finder copies them, so every app that takes a pasted file takes both.
            let items = ([Self.sharePicture(for: file), file].compactMap { $0 }) as [NSURL]
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(items)
            log(project, .status, "\(project.name) is copied with its picture. Paste it into a message to send it.")
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// The picture sent with a shared app (`ShareCard`), written beside its file as "<name>.png". It's drawn from
    /// the finished file, so it can show nothing the file doesn't already carry: the name and the icon.
    nonisolated static func sharePicture(for file: URL) -> URL? {
        guard let look = LampFile(contentsOf: file), let png = ShareCard.png(look) else { return nil }
        let picture = file.deletingPathExtension().appendingPathExtension("png")
        // Written whole: another share of the same wish may be writing the same picture.
        return (try? png.write(to: picture, options: .atomic)) == nil ? nil : picture
    }

    /// The app's .lampapp, written where it outlives the paste or the drop that hands it on: another app may
    /// read it after Lamp has moved on.
    nonisolated static func sharedFile(of project: LampProject, at file: URL? = nil, icon: Data? = nil) throws -> URL {
        sharing.lock()
        defer { sharing.unlock() }
        let exported = try Sharing.export(project, icon: icon)
        let file = file ?? sharedFolder.appendingPathComponent(exported.lastPathComponent)
        let fm = FileManager.default
        defer { try? fm.removeItem(at: exported.deletingLastPathComponent()) }
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        // The new file is first put whole on the same disk as the old one, which stays as it was if that fails
        // (a full disk), and then takes the old one's place in one step: whatever was handed the old file (a paste,
        // the picker, a drop) finds a file there at every moment.
        let nearby = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: file, create: true)
        defer { try? fm.removeItem(at: nearby) }
        let staged = nearby.appendingPathComponent(file.lastPathComponent)
        try fm.moveItem(at: exported, to: staged)
        if fm.fileExists(atPath: file.path) {
            _ = try fm.replaceItemAt(file, withItemAt: staged)
        } else {
            try fm.moveItem(at: staged, to: file)
        }
        return file
    }

    /// One shared file is made at a time. Shares of one wish go to the same file, so two at once could leave the
    /// copy that began first, or trip over each other putting it in place. Made one after the other, the file left
    /// is the one that read the app last. Nothing made under it waits for the main
    /// thread, which may be waiting here.
    nonisolated private static let sharing = NSLock()

    nonisolated static var sharedFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Forge/Shared", isDirectory: true)
    }

    func chooseExport(_ project: LampProject) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.lampApp]
        panel.nameFieldStringValue = "\(project.name).lampapp"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            _ = try Self.sharedFile(of: project, at: destination)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    struct PendingImport: Identifiable {
        let id = UUID()
        let package: Sharing.Package
        var review: ImportReview?
        /// The app already here that this file is another version of, if any: the choice is then Update or Keep Both.
        var existing: LampProject?
    }

    /// The app on this Mac that a shared file is a version of: the one it was shared from, or the copy made
    /// by opening an earlier file from it.
    func existingCopy(of package: Sharing.Package) -> LampProject? {
        guard let identity = package.identity else { return nil }
        // Only an app of the same kind: a file that's an iPhone app doesn't replace the Mac app it began as.
        // A wish whose apps are all in folders of their own travels with the first of them at the file's root, so it isn't
        // the copy of a file by that app's kind: it's opened as a new wish.
        return projects.first { $0.holdsApp && $0.platform == package.platform && $0.hasScaffold && Sharing.identity(of: $0, create: false) == identity }
    }

    /// Opens a shared `.lampapp`. Its review (fixed checklist + AI check) opens only when setup is really done
    /// and the welcome is over, so that an AI agent is there to check the app before it runs. Until then the
    /// file is kept, and its review opens by itself once the person is through setup.
    func importApp(from file: URL) {
        NSApp.activate()
        Task {
            // A file that launched Lamp arrives before Lamp has looked at setup: the look is waited for, so
            // the same file on the same Mac always goes the same way.
            await setupLook.wait()
            guard reviewsCanOpen else {
                let alert = NSAlert()
                alert.messageText = "Finish setting up Lamp first"
                if waitingImport.keep(file) {
                    alert.informativeText = waitingImport.count > 1
                        ? "Lamp will open your shared apps as soon as it can build them."
                        : "Lamp will open the shared app as soon as it can build it."
                } else {
                    alert.informativeText = "Then open the shared app again."
                }
                alert.runModal()
                return
            }
            review(file)
        }
    }

    /// Setup is in place (Apple's tools and an AI agent) and the person is through the welcome.
    private var reviewsCanOpen: Bool {
        WaitingImport.reviewsCanOpen(setupReady: setupLook.isDone && setup.ready, welcomeOver: Onboarding.isDone || welcomeFinished)
    }

    /// Unpacks a shared app and shows its review.
    private func review(_ file: URL) {
        // The newest request wins: a file opened while an earlier one is still unpacking, or a Cancel
        // meanwhile, makes the earlier result unwanted when it arrives.
        let request = UUID()
        importRequest = request
        if let previous = pendingImport { try? FileManager.default.removeItem(at: previous.package.folder) }
        pendingImport = nil
        Task {
            // Unpacking is a process and some file reads: off the main actor, so Lamp stays responsive.
            let package: Sharing.Package
            do {
                package = try await Task.detached { try Sharing.open(file) }.value
            } catch {
                guard importRequest == request else { return }
                importRequest = nil
                NSAlert(error: error).runModal()
                openWaitingImport()   // one that can't be opened doesn't hold up the ones kept after it
                return
            }
            guard importRequest == request else { try? FileManager.default.removeItem(at: package.folder); return }
            let pending = PendingImport(package: package, existing: existingCopy(of: package))
            pendingImport = pending
            let review = await Sharing.review(package)
            if pendingImport?.id == pending.id { pendingImport?.review = review }
        }
    }

    private var importRequest: UUID?

    private var waitingImport: WaitingImport { WaitingImport(folder: waitingFiles) }

    /// Shared apps opened before setup was done get their reviews once the person is through setup, one at a
    /// time in the order they were opened: called when setup becomes ready, when the welcome ends, and when a
    /// review closes.
    /// Whether a shared app is now being looked at, waiting or not.
    @discardableResult func openWaitingImport() -> Bool {
        guard pendingImport == nil, importRequest == nil else { return true }
        let file = waitingImport.take(setupReady: setupLook.isDone && setup.ready, welcomeOver: Onboarding.isDone || welcomeFinished)
        if let file { review(file) }
        return file != nil
    }

    func cancelImport() {
        importRequest = nil
        if let pending = pendingImport { try? FileManager.default.removeItem(at: pending.package.folder) }
        pendingImport = nil
    }

    func confirmImport() {
        guard let pending = pendingImport else { return }
        importRequest = nil
        pendingImport = nil
        finishImport(pending.package)
    }

    /// Update: the app already here takes the file's code, files, description and icon, in place, so it keeps
    /// its name, its data, its permissions and its chat. What it was until now is saved as a version first
    /// (changes not yet saved included), so Versions can bring it back; without that, nothing is replaced.
    func confirmUpdate() {
        guard let pending = pendingImport else { return }
        guard let project = pending.existing.flatMap({ existing in projects.first { $0.id == existing.id } }),
              begin(project) != nil else {
            let alert = NSAlert()
            alert.messageText = "“\(pending.existing?.name ?? pending.package.name)” is busy right now"
            alert.informativeText = "Try again when it's done, or keep both."
            alert.runModal()
            return
        }
        importRequest = nil
        pendingImport = nil
        showChat(project.id)
        Task {
            defer { finish(project) }
            let package = pending.package
            defer { try? FileManager.default.removeItem(at: package.folder) }
            let before = "Before updating from a shared file"
            var kept = await Versions.head(project) == nil ? await initRepo(project, message: before) : true
            if kept, await Versions.hasUnsavedChanges(project) { kept = await Versions.save(project, message: before) }
            guard kept else {
                log(project, .error, Self.updateFailed)
                return
            }
            // Replaced files that can't be kept as a version go back to the one just saved, so the app's
            // files, its versions and the installed app never disagree.
            // The icon's pictures are outside the versions, so they're set aside here and put back by hand.
            // Pictures that can't be set aside aren't risked: nothing is replaced.
            let fm = FileManager.default
            let art = project.dir.appendingPathComponent(".lamp/art")
            let artBefore = package.folder.appendingPathComponent("art-before-update")
            let hadArt = fm.fileExists(atPath: art.path)
            if hadArt {
                do { try fm.copyItem(at: art, to: artBefore) } catch {
                    log(project, .error, Self.updateFailed)
                    return
                }
            }
            // The wish's list of apps and the files kept for one it can't make yet are outside the versions too: set
            // aside the same way, and put back with the rest.
            let appsBefore = project.apps
            let waiting = project.dir.appendingPathComponent(Sharing.waitingFolder)
            let waitingBefore = package.folder.appendingPathComponent("waiting-before-update")
            let hadWaiting = fm.fileExists(atPath: waiting.path)
            if hadWaiting {
                do { try fm.copyItem(at: waiting, to: waitingBefore) } catch {
                    log(project, .error, Self.updateFailed)
                    return
                }
            }
            /// False when the icon's pictures couldn't be returned; the ones there are then left alone.
            func putBack() async -> Bool {
                _ = await Versions.git("git restore --staged --worktree -- . && git clean -fdq -e .lamp -- . ':!\(Attachments.folder)'", cwd: project.dir) { _ in }
                try? fm.removeItem(at: waiting)
                if hadWaiting { try? fm.copyItem(at: waitingBefore, to: waiting) }
                guard hadArt else {
                    try? fm.removeItem(at: art)
                    return true
                }
                // The copy is made beside the folder first, so the old pictures are never the only ones removed.
                let returning = art.deletingLastPathComponent().appendingPathComponent("art-returning")
                try? fm.removeItem(at: returning)
                do {
                    try fm.copyItem(at: artBefore, to: returning)
                    _ = try fm.replaceItemAt(art, withItemAt: returning)
                    return true
                } catch {
                    try? fm.removeItem(at: returning)
                    return false
                }
            }
            let newArtwork: Bool
            do {
                newArtwork = try Sharing.install(package, into: project, replacing: true)
                let notIn = await installParts(of: package, into: project)
                guard notIn.isEmpty else { throw Sharing.ImportError("\(notIn.joined(separator: ", ")) couldn't be put in place.") }
            } catch {
                let iconBack = await putBack()
                // A part the file brought, or changed in kind, goes back with the files (`followRestored`), and the list
                // after that, since forgetting a part takes it out of the list too.
                await followRestored(project)
                setApps(project, appsBefore)
                print("Update \(project.name) from a shared file failed: \(error)")
                log(project, .error, Self.updateFailed + (iconBack ? "" : Self.updateChangedIcon))
                return
            }
            if await Versions.hasUnsavedChanges(project) {
                guard await Versions.save(project, message: "Updated from a shared file") else {
                    let iconBack = await putBack()
                    await followRestored(project)
                    setApps(project, appsBefore)
                    log(project, .error, Self.updateFailed + (iconBack ? "" : Self.updateChangedIcon))
                    return
                }
                Versions.rememberUpdate(project)
                versionsRevision += 1
            } else if !newArtwork {
                log(project, .status, "You already have this version.")
                return
            }
            // The same code with a new icon picture still gets built, which is what draws and installs the icon.
            log(project, .status, "Updated from a shared file. Building it now…")
            if await build(project) == nil {
                await installReportingCrash(project)
            } else {
                log(project, .error, ErrorMessages.appDoesNotBuild)
            }
            await rebuildParts(of: current(project) ?? project, onlyChanged: true)
        }
    }

    /// An update that didn't happen, in the chat: the app is untouched or was put back, whatever the cause.
    private static let updateFailed = "Lamp couldn't update this app. It's just as it was."
    private static let updateChangedIcon = " Only its icon may have changed."

    private func finishImport(_ package: Sharing.Package) {
        let project: LampProject
        do {
            project = try Template.scaffold(name: uniqueName(package.name), platform: package.platform, family: package.family, in: root)
            try Sharing.install(package, into: project)
            // The copy is the same app as the sender's: the next file shared from theirs can update it. A
            // second copy made beside one that's already here (Keep Both), or beside one of another kind, is an
            // app of its own.
            if let identity = package.identity,
               !projects.contains(where: { $0.id != project.id && Sharing.identity(of: $0, create: false) == identity }) {
                Sharing.setIdentity(identity, of: project)
            }
        } catch {
            try? FileManager.default.removeItem(at: package.folder)
            NSAlert(error: error).runModal()
            return
        }

        reload()
        showChat(project.id)
        log(project, .status, "Imported from a shared file. Building it now…")
        Task {
            defer { try? FileManager.default.removeItem(at: package.folder) }
            // The wish's other apps, each made in its folder as `make_app_for` makes one and given the file's code. One
            // this Mac can't build yet stays on the wish's list, with its setup a click away, and is made once it can.
            // A part whose files couldn't be put in place, or kept for later, fails the import as a whole: the wish just
            // made goes, and the file can be opened again, rather than a wish missing an app with no way to get it.
            let notIn = await installParts(of: package, into: project)
            guard notIn.isEmpty else {
                await delete(current(project) ?? project)
                let alert = NSAlert()
                alert.messageText = "Lamp couldn't open “\(package.name)”"
                alert.informativeText = "\(notIn.joined(separator: ", ")) couldn't be put in place. Nothing was kept; open the file again to try once more."
                alert.runModal()
                return
            }
            _ = await initRepo(project, message: "Imported from a shared file")
            await run(project)
            await rebuildParts(of: current(project) ?? project)
        }
    }

    /// A shared wish's other apps into a wish here, each part the file carries going into the part of its family: one the
    /// wish has of the same kind takes the file's code in place of its own (`replacing`, keeping the rest); one of
    /// another kind of the family (the Mac app that's now for the iPhone too) is changed in place as `make_app_for`
    /// changes one (`convert`), keeping its folder and so its data; one the wish doesn't have is made (`addPart`). One
    /// this Mac can't make yet keeps its files with the wish (`Sharing.keep`) and goes in once it can. A part the wish
    /// has and the file doesn't is left as it is. Returns the apps whose files couldn't be put in place, or kept, so an
    /// update can put the whole wish back and a fresh import can say so.
    private func installParts(of package: Sharing.Package, into wish: LampProject) async -> [String] {
        var notIn: [String] = []
        func failed(_ kind: Platform) {
            let name = Parts.name(of: kind)
            notIn.append(name.prefix(1).uppercased() + name.dropFirst())
        }
        for part in package.parts {
            guard let wish = current(wish) else { return [Parts.name(of: part.package.platform)] }
            let kind = part.package.platform
            var had = parts(of: wish).first { Parts.group($0.platform) == Parts.group(kind) }
            if let have = had, have.platform != kind {
                let (status, changed) = await convert(have, to: kind)
                guard status == 200, let text = changed["text"] as? String, !text.hasPrefix("Not yet"), !text.hasPrefix("Nothing changed") else {
                    log(wish, .error, "\(Parts.name(of: have.platform)) couldn't be made \(Parts.name(of: kind)): " + (changed["text"] as? String ?? changed["error"] as? String ?? ""))
                    failed(kind)
                    continue
                }
                had = current(have)
            }
            let target: LampProject
            if let had {
                target = had
            } else {
                let (made, problem, setup) = await addPart(kind, to: wish, family: part.package.family, folder: part.folder)
                guard let made else {
                    do { try Sharing.keep(part, in: wish.dir) } catch {
                        log(wish, .error, "Lamp couldn't keep \(Parts.name(of: kind))'s files: \(error.localizedDescription)")
                        failed(kind)
                    }
                    recordNeeds(problem ?? "Lamp couldn't make it.", for: kind, of: wish, setup: setup)
                    continue
                }
                target = made
            }
            do { try Sharing.install(part.package, into: target, replacing: had != nil) } catch {
                log(wish, .error, "Lamp couldn't put \(Parts.name(of: kind))'s files in place: \(error.localizedDescription)")
                failed(kind)
            }
        }
        return notIn
    }

    /// Sends a message, or queues it while the app is busy. Everything queued goes out together
    /// as the next turn, so several quick follow-ups cost one agent run and one rebuild.
    func send(_ prompt: String, attachments: [URL] = [], pointed: PointedAt? = nil, answering card: UUID? = nil, to project: LampProject) {
        // Waiting for setup, or for the person's Reload (`pause`), can outlast this run, and the files may be
        // temporary (a pasted screenshot, the picture of what was pointed at): copies are kept, so the request still
        // has them after a relaunch.
        var message = QueuedMessage(text: prompt, attachments: attachments, pointed: pointed)
        if !setup.ready || queueWaitsForReload(in: project) { message = keptForLater(message) }
        let files = message.attachments, pointed = message.pointed
        // Typed while a card waits, the message is its answer, even if it has to wait behind the agent's
        // turn: the card folds as it's sent, so it can't be answered a second time by a click meanwhile.
        var card = card
        if card == nil, let open = Talk.open(in: logs[project.id] ?? []),
           let index = logs[project.id]?.firstIndex(where: { $0.id == open.id }) {
            logs[project.id]?[index].ask?.typed = true
            card = open.id
            saveChat(project)
        }
        queued[project.id, default: []].append(QueuedMessage(text: prompt, attachments: files, card: card, pointed: pointed))
        startQueued(project)
        saveWaiting()
    }

    /// Requests waiting for setup (the welcome's first app, while Apple's tools install), kept on disk so
    /// quitting meanwhile doesn't lose them: they come back on the next launch and start once setup is done.
    private static let waitingKey = "waitingRequests"

    /// Where waiting requests' files are kept until their build starts.
    private var waitingFiles: URL { root.deletingLastPathComponent().appendingPathComponent("Waiting") }

    /// A waiting message with copies of its files, the picture of what it points at included, where they aren't copies
    /// already: one that was queued before its line turned out to wait across a relaunch (the pause came after it).
    private func keptForLater(_ message: QueuedMessage) -> QueuedMessage {
        var kept = message
        let waiting = waitingFiles.standardizedFileURL.path
        kept.attachments = message.attachments.map { $0.standardizedFileURL.path.hasPrefix(waiting) ? $0 : keepForLater([$0])[0] }
        if let picture = message.pointed?.url, !picture.standardizedFileURL.path.hasPrefix(waiting) {
            kept.pointed?.picture = keepForLater([picture])[0].path
        }
        return kept
    }

    /// Each file gets a folder of its own, so two with the same name (two "Dropped image.png") both keep a copy.
    private func keepForLater(_ files: [URL]) -> [URL] {
        files.map { file in
            let folder = waitingFiles.appendingPathComponent(UUID().uuidString)
            let copy = folder.appendingPathComponent(file.lastPathComponent)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return (try? FileManager.default.copyItem(at: file, to: copy)) != nil ? copy : file
        }
    }

    private func saveWaiting() {
        let waiting = queued.filter { Self.keptAcrossRelaunch($0.value, setupReady: setup.ready) }.mapValues { messages in
            messages.map(\.saved)
        }
        if waiting.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.waitingKey)
        } else {
            UserDefaults.standard.set(waiting, forKey: Self.waitingKey)
        }
    }

    /// Which waiting messages are kept across a relaunch: every queue while setup isn't done, and a queue paused for
    /// Reload (`pause`), whose held build outlives Lamp too, so the request carries on after the Reload whenever it
    /// comes and nothing typed behind it is lost.
    static func keptAcrossRelaunch(_ messages: [QueuedMessage], setupReady: Bool) -> Bool {
        !messages.isEmpty && (!setupReady || messages.contains(where: \.afterReload))
    }

    /// Brings back requests that were waiting for setup, or for Reload, when Lamp last quit. Kept files no waiting
    /// request needs any more (its build has started, or it was taken back) are cleared out.
    private func restoreWaiting() {
        var kept = Set<String>()
        if let waiting = UserDefaults.standard.dictionary(forKey: Self.waitingKey) as? [String: [[String: Any]]] {
            for (id, messages) in waiting where projects.contains(where: { $0.id == id }) {
                queued[id] = messages.map { message in
                    let files = (message["attachments"] as? [String] ?? []).filter { FileManager.default.fileExists(atPath: $0) }
                    kept.formUnion(files.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path })
                    let restored = QueuedMessage(saved: message, attachments: files.map(URL.init(fileURLWithPath:)))
                    if let picture = restored.pointed?.url { kept.insert(picture.deletingLastPathComponent().path) }
                    return restored
                }
            }
        }
        kept.formUnion(waitingImport.keptFolders)
        let folders = (try? FileManager.default.contentsOfDirectory(at: waitingFiles, includingPropertiesForKeys: nil)) ?? []
        for folder in folders where !kept.contains(folder.path) { try? FileManager.default.removeItem(at: folder) }
    }

    /// The version label for a request without words: what was sent.
    static func label(attachments names: [String]) -> String {
        "Sent \(names.count == 1 ? names[0] : "\(names.count) files")"
    }

    static func label(for line: LogLine) -> String {
        line.text.isEmpty ? label(attachments: line.attachments ?? []) : line.text
    }

    /// The apps a wish should have, written to its meta.json (`LampProject.apps`), so what it waits for outlives a quit.
    /// Nothing for a part, whose wish keeps the list.
    @discardableResult
    func setApps(_ project: LampProject, _ apps: [WishApp]) -> LampProject {
        guard let index = projects.firstIndex(where: { $0.id == project.id }), !projects[index].isPart else { return project }
        projects[index].apps = apps
        try? Template.saveMeta(projects[index])
        return projects[index]
    }

    /// The apps a wish should have and doesn't yet, made now where this Mac can: each not yet tried (its first turn, or
    /// its setup just done). One this Mac can't build yet keeps what stops it in the wish's list, with the setup a click
    /// away in the chat, and is tried again once that's done or the agent asks for it again, not at every turn, since
    /// the check opens the setup's window.
    private func makeWaitingParts(of wish: LampProject) async {
        guard let wish = current(wish), !wish.isPart else { return }
        for app in Parts.waiting(in: wish, parts: parts(of: wish)) where app.needs == nil {
            let (part, problem, setup) = await addPart(app.kind, to: wish, places: app.places)
            if let part { log(wish, .status, "\(wish.name) has \(Parts.name(of: part.platform)) to go with it now.") }
            else if let problem { recordNeeds(problem, for: app.kind, of: wish, setup: setup) }
        }
    }

    /// What stops one of a wish's apps being made, kept with the app in the wish's list, and said once in the chat. For
    /// this Mac's setup (`setup`) the line has it a click away, and the setup window the check opened is followed, so
    /// finishing it there adds the app; anything else (a folder in the way) is said as an error, and the app waits for
    /// the agent to ask for it again once the person has dealt with it, never for a setup that's already done, which
    /// would ask again at once, turn after turn.
    private func recordNeeds(_ problem: String, for kind: Platform, of wish: LampProject, setup: Bool) {
        guard let wish = current(wish) else { return }
        setApps(wish, Parts.setting(WishApp(kind: kind, needs: problem), in: wish.apps))
        let line = IPhoneSetupLine.lineText(kind, part: true)
        if setup, kind.target.setup.later != nil {
            if !(logs[wish.id] ?? []).contains(where: { $0.kind == .iphoneSetup && $0.text == line }) { log(wish, .iphoneSetup, line) }
            IPhoneSetupLine.follow(wish, wanted: kind, part: true)
        } else {
            log(wish, .error, "T\(Parts.name(of: kind).dropFirst()) isn't made yet: \(problem)")
        }
    }

    /// The setup one of a wish's apps was waiting for is done (`IPhoneSetupLine`): what stopped it is cleared, so the
    /// next turn makes it, and the request that asks for it is sent.
    func retryWaitingApp(_ kind: Platform, of wish: LampProject) {
        guard let wish = current(wish), let app = wish.apps.first(where: { Parts.group($0.kind) == Parts.group(kind) }) else { return }
        let cleared = setApps(wish, Parts.setting(WishApp(kind: app.kind), in: wish.apps))
        send(Parts.request(for: app.kind), to: cleared)
    }

    /// The first message bootstraps the app: it names an untitled app, then designs the icon
    /// while the agent builds the first version. Returns the app as it is now.
    private func bootstrap(_ project: LampProject, brief: String) async -> LampProject {
        var project = project
        // A draft named before its first request (in its intro) is still asked about, for what it runs on.
        if project.untitled || !project.scaffolded {
            let suggestion = await AppName.suggest(for: brief, devices: await devicesForWish())
            progress[project.id]?.sketch = suggestion?.sketch ?? []
            progress[project.id]?.naming = false
            if let suggestion, let candidates = suggestion.undecided {
                // Nothing points one way: the agent asks first, and nothing is written until it's answered.
                project = setUndecided(project, candidates)
            } else if let suggestion, let kind = await firstKind(among: suggestion.kinds, integration: suggestion.integration) {
                let parts = suggestion.kinds.filter { Parts.group($0) != Parts.group(kind) }
                project = await chooseKind(project, kind, said: suggestion.kindSaid, watch: suggestion.watch, integration: suggestion.integration,
                                           parts: parts, places: suggestion.places[kind], engine: suggestion.engine)
                // The wish's other apps are kept in its list from here, and made once its first app is written
                // (`startQueued`, `makeWaitingParts`), each in its own folder. So are they when the first couldn't be made
                // as it was read (this Mac can't build it yet, so it's a Mac app with the setup a click away): what's
                // missing holds back only the app that needs it.
                let rest = parts.filter { Parts.group($0) != Parts.group(project.platform) }
                if !rest.isEmpty {
                    project = setApps(project, [WishApp(kind: project.platform)] + rest.map { WishApp(kind: $0, places: suggestion.places[$0]) })
                }
            }
            if project.untitled, let name = suggestion?.name { project = await performRename(project, to: name) }
            if suggestion?.forOtherDevice == true, let index = projects.firstIndex(where: { $0.id == project.id }) {
                projects[index].waitsForDevice = true
                try? Template.saveMeta(projects[index])
                project = projects[index]
            }
            if let color = suggestion?.color, Icons.load(project) == nil { iconColors[project.id] = color }
        }
        if Icons.load(project) == nil {
            let designing = project
            let color = iconColors[project.id]
            iconDesigns[project.id] = Task {
                let spec = await Icons.design(for: designing, brief: brief, background: color)
                if Icons.load(designing) == nil {
                    Icons.save(spec, for: designing)
                    await renderIcon(designing, spec: spec)
                    // The artwork takes a minute or two; the build takes longer. Started now, it's usually
                    // there by the time the app first opens, instead of swapping in afterwards.
                    upgradeIconArt(designing)
                }
                iconDesigns[designing.id] = nil
            }
        }
        return project
    }

    /// The waiting messages Send Now would hand over: those not already on their way, in the order they were sent.
    func waitingToSend(in project: LampProject) -> [QueuedMessage] {
        (queued[project.id] ?? []).filter { !$0.sendNow }
    }

    /// Whether the waiting messages can be sent to the agent in the turn that's running (Send Now). They go as one
    /// group, so every one of them must be able to: each is a plain request. An answer to a card or a request sent
    /// again changes what the turn is for, and so does anything while a wish is being found or once the agent has
    /// asked its questions; then they all wait for the next turn.
    func canSendNow(in project: LampProject) -> Bool {
        let waiting = waitingToSend(in: project)
        guard !waiting.isEmpty, let turn = turns[project.id], !turn.asked, !turn.paused, !turn.stopped,
              current(project)?.finding == false else { return false }
        return waiting.allSatisfy { $0.card == nil && $0.replaces == nil && $0.tookBack.isEmpty && !$0.afterReload }
    }

    /// Send Now: every waiting message goes to the agent at its next step, in the order they were sent, if it still
    /// has one; otherwise they start the next turn as any waiting messages do. `latest` is the message the button
    /// was under: a button drawn for a group that has since gone (sent, taken back) or grown sends nothing, so a
    /// late click can't send messages the person never saw it offered for.
    func sendNow(in project: LampProject, latest: UUID) {
        guard canSendNow(in: project), waitingToSend(in: project).last?.id == latest, var waiting = queued[project.id]
        else { return }
        for index in waiting.indices { waiting[index].sendNow = true }
        queued[project.id] = waiting
        steer(project)
    }

    func unqueue(_ message: QueuedMessage, from project: LampProject) {
        // A first request waiting for setup has no chat yet: it can still be taken back.
        guard var waiting = queued[project.id] else { return }
        var lines = logs[project.id] ?? []
        let reopened = Talk.unqueue(message, from: &waiting, lines: &lines)
        queued[project.id] = waiting
        if reopened {
            logs[project.id] = lines
            saveChat(project)
        }
        saveWaiting()
    }

    /// Where a request for an app goes: its own chat, or for a wish's other part its wish's, whose turn works on every
    /// part (`underTurn`). A part has no conversation, prompt or history of its own, so a turn of its own would build
    /// on rules it doesn't have and save in a folder that isn't a repository.
    nonisolated static func requestOwner(of project: LampProject, among projects: [LampProject]) -> LampProject {
        guard let wish = project.partOf else { return project }
        return projects.first { $0.id == wish } ?? project
    }

    private func startQueued(_ project: LampProject) {
        // A part's request (Lamp's own, to carry on after its Reload) is its wish's.
        let owner = Self.requestOwner(of: project, among: projects)
        if owner.id != project.id {
            if let waiting = queued.removeValue(forKey: project.id) {
                // Lamp's own request to carry on stays first, and only once; the rest wait after what the wish has.
                var mine = queued[owner.id] ?? []
                if waiting.contains(where: \.afterReload), !mine.contains(where: \.afterReload) {
                    mine.insert(contentsOf: waiting.filter(\.afterReload).prefix(1), at: 0)
                }
                queued[owner.id] = mine + waiting.filter { !$0.afterReload }
                saveWaiting()
            }
            return startQueued(owner)
        }
        guard setup.ready, let messages = queued[project.id], !messages.isEmpty,
              Self.startsNow(messages, changeHeld: holdsAnyBuild(project)),
              let owner = begin(project) else { return }
        queued[project.id] = nil
        saveWaiting()
        // The request Lamp paused goes on: the chat says why the agent is back at work, since its own request is
        // hidden, as a crash fix's is (`byLamp`).
        if messages.first?.afterReload == true { log(project, .status, ChatLook.carryingOn) }
        owner.messages = messages.map(\.text)
        // A wish being found isn't named by its opening request or by answers to the agent's cards: the wish
        // the agent writes into the box (or one of the person's own) names it when it's sent.
        let spoken = (logs[project.id] ?? []).contains { $0.kind == .user }
        let names = project.isDeviceSetup ? false
            : project.finding ? spoken && project.untitled && !messages.contains { $0.card != nil } : !spoken
        let first = names
        let stillFinding = project.makesNoApp && !names
        // Still a new app until a request has made its first version: after the agent only asked questions,
        // the answers start the build and get its chapters. An imported app has already been built. Not
        // while a wish is being found: there's nothing to build yet.
        let newApp = Template.isScaffold(project) && !hasVersions(project) && (!project.makesNoApp || names)
        progress[project.id] = TurnProgress(newApp: newApp)
        // Only the first message names the app (bootstrap). A later one, after the agent only asked questions,
        // finds it untitled if that naming failed, and mustn't show a naming that isn't happening.
        progress[project.id]?.naming = first && project.untitled
        let kind = project.platform.target.identity.analytics
        if newApp && first {
            Analytics.capture(.appFirstRequest, ["kind": kind, "has_attachments": messages.contains { !$0.attachments.isEmpty }])
        }
        let started = Date()
        Task {
            var project = project
            let saved = post(messages, to: project)
            let asked = (logs[project.id] ?? []).filter { $0.kind == .user }.suffix(messages.count).map(\.id)
            if first {
                let untitled = project
                let words = messages.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n")
                let brief = words.isEmpty
                    ? "An app made from the attached file\(saved.count == 1 ? "" : "s"): \(saved.joined(separator: ", "))"
                    : words
                project = await bootstrap(project, brief: brief)
                if project.finding, let found = current(project) {
                    // Found: from here it's a wish like any other.
                    var plain = found
                    plain.finding = false
                    try? Template.saveMeta(plain)
                    reload()
                    project = current(project) ?? project
                }
                if project.id != untitled.id { progress[project.id] = progress.removeValue(forKey: untitled.id) }
            }
            var worked = false
            var result = TurnResult(end: .failed, watched: true)
            defer {
                // A new app's bar stays, showing the result; a later turn's activity line goes away. So does a
                // new app's bar when the agent only asked questions: nothing was built, and the answers bring it back.
                if newApp {
                    let seconds = Int(Date().timeIntervalSince(started))
                    switch result.end {
                    case .changed where !owner.didNotOpen: Analytics.capture(.appFirstRun, ["kind": kind, "seconds": seconds])
                    case .replied: Analytics.capture(.appFirstReplied, ["kind": kind, "seconds": seconds])
                    default:
                        Analytics.capture(.appFirstFailed, ["kind": kind, "seconds": seconds, "stopped": owner.wasStopped,
                                                            "did_not_open": owner.didNotOpen])
                    }
                }
                if newApp && result.end != .replied {
                    progress[project.id]?.finish(worked: worked && turns[project.id]?.phoneReady != false, opened: !owner.didNotOpen)
                } else if newApp, Talk.open(in: logs[project.id] ?? []) != nil {
                    // The agent asked through its card: the app's bar says it's waiting while the person
                    // answers, and the build that follows starts on it.
                    progress[project.id]?.wait()
                } else {
                    progress[project.id] = nil
                }
                if selection != project.id || !NSApp.isActive { unread.insert(project.id) }
                // Messages queued meanwhile start the next turn straight away; tell the user once it's all done.
                // Lamp's own request waiting for Reload starts nothing by itself: the person is told as after any turn.
                if !owner.stopped, !result.watched, (queued[project.id] ?? []).allSatisfy(\.afterReload) { notify(project, after: result.end) }
                finish(project)
            }
            // Named now, so the scaffold is written under its name. If it can't be, the turn ends here, failed.
            // Not while a wish is still being found: the agent only asks, and the wish it finds may be for the
            // iPhone, which a scaffold already written as a Mac app would rule out.
            if !stillFinding, !(current(project) ?? project).waitsForDevice, project.undecided == nil {
                guard let ready = await materialize(project) else { return }
                project = ready
                await makeWaitingParts(of: project)
                project = current(project) ?? project
                if newApp { showEarly(project, in: owner) }
            }
            // Where the app is as the turn starts, so the request can be changed and sent again from here.
            if let head = await Versions.head(project) {
                mark(asked, sentFrom: head, in: project)
                owner.sentFrom = head
            }
            result = await turn(messages, attachments: saved, asked: asked, on: project)
            // The scaffold's early build is the turn's until it's settled, whichever way the turn ended (a question, a
            // failure, a Stop): released before it, the next turn's build could run beside it on the same files.
            await owner.early?.value
            worked = result.end != .failed
        }
    }

    /// A wish given its kinds in a turn begun without any (`decided`): each engine's conversation began with the prompt
    /// for no kind, so it's forgotten now the turn is over, and the flag with it. Also at Lamp's start, for a wish whose
    /// turn Lamp quit in the middle of.
    private func settleDecided(_ project: LampProject) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }), projects[index].decided else { return }
        for engine in Engine.allCases { Self.forgetConversation(of: projects[index], engine: engine) }
        projects[index].decided = false
        try? Template.saveMeta(projects[index])
    }

    /// Posts a notification for a turn that ended while the user was looking elsewhere.
    /// Nothing for a turn the user stopped: it ends without an error.
    private func notify(_ project: LampProject, after end: TurnEnd) {
        guard turns[project.id]?.stopped != true else { return }
        let turnLines = (logs[project.id] ?? []).reversed().prefix { $0.kind != .user }
        // An error wins: even a turn that otherwise worked (say, the app couldn't be installed) needs the user.
        if let error = turnLines.first(where: { $0.kind == .error }) {
            Notifier.shared.post(for: project, subtitle: "Needs your attention", body: error.text)
            return
        }
        let reply = turnLines.first { $0.kind == .agent }.map { Self.plain($0.text) }
        switch end {
        case .changed:
            Notifier.shared.post(for: project, subtitle: "Your change is ready", body: reply ?? "It's built and open.")
        case .replied:
            Notifier.shared.post(for: project, subtitle: "Replied", body: reply ?? "")
        case .failed:
            break
        }
    }

    /// An agent reply without its Markdown, short enough for a notification.
    private static func plain(_ markdown: String) -> String {
        let text = markdown
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: #"(?m)^#+\s*"#, with: "", options: .regularExpression)
            .split(whereSeparator: \.isNewline).joined(separator: " ")
        return text.count > 240 ? String(text.prefix(239)) + "…" : text
    }

    /// Marks the app idle again, then starts anything queued while it was busy.
    private func finish(_ project: LampProject) {
        settleDecided(project)
        if let turn = turns[project.id], turn.reloadedWhileAway, turn.reloadedByPerson, away.carriesOn(project.id) {
            queueCarryOn(project)
        }
        endApprovals(for: project)   // a card nobody can answer any more, from a request that raced the agent's end
        // Artwork that arrived during the turn, for an icon that was installed without it: applied now, still
        // owning the app, so nothing else builds or installs meanwhile. With more work queued, the next
        // install picks the artwork up itself.
        // Its other apps too: the wish's own look may have drawn the artwork already while a part still shows the blueprint.
        if pendingIconArt.contains(project.id), (queued[project.id] ?? []).isEmpty, let spec = Icons.load(project),
           artApplied[project.id] != spec || parts(of: project).contains(where: { artApplied[$0.id] != spec }) {
            pendingIconArt.remove(project.id)
            Task {
                await applyIconArt(project, spec: spec)
                release(project)
                if reloadWhenFree.contains(project.id) { reloadWaiting(project.id) }
                fixHeldCrashes(project)
                offerHeldDrawing(project)
                startQueued(project)
                installHeldIcons(for: [project.id])
            }
            return
        }
        release(project)
        if reloadWhenFree.contains(project.id) { reloadWaiting(project.id) }
        if iconFallbackWhenFree.remove(project.id) != nil, let spec = Icons.load(project) {
            Task { await artworkWontCome(project, spec: spec, failed: false) }
        }
        fixHeldCrashes(project)
        offerHeldDrawing(project)
        startQueued(project)
        refreshUndoOffer(project)
        // An icon that was waiting for the app to close, when the app closed while this had it: the moment
        // it closed came and went with the app taken, so it's looked at again now the app is free. A wish's turn held
        // its other apps too.
        installHeldIcons(for: Set([project.id] + parts(of: project).map(\.id)))
    }

    /// The offer to draw the icon that was wanted while the turn had the app, made now it's over: the last
    /// thing the turn leaves in the chat, under the reply and "… is ready". It's worked out afresh, since
    /// the icon may have been drawn or designed again meanwhile, or the choice of what draws icons changed.
    private func offerHeldDrawing(_ project: LampProject) {
        guard heldDrawingOffers.remove(project.id) != nil, exists(project) else { return }
        upgradeIconArt(project)
    }

    /// Renders the icon with its artwork and installs it, when there's a built app to install it into;
    /// otherwise the artwork waits in the cache for the first successful build.
    private func applyIconArt(_ project: LampProject, spec: IconSpec) async {
        await renderIcon(project, spec: spec)
        await iconToParts(of: project, spec: spec)
        guard hasMacBuild(project) else { return }
        log(project, .status, await installIcon(project) ? "New icon artwork is in."
            : "New icon artwork is in. \(project.name) gets it the next time it closes.")
    }

    /// Whether the app is open on this Mac.
    private func isRunning(_ project: LampProject) -> Bool { !macCopies(of: project).isEmpty }

    /// Every copy of the app open on this Mac: by its id, and by where Lamp installs it. One found only by its
    /// place has another id: built before the app's id changed, or by Lamp with other settings (after a fresh
    /// start, or for an app of the same name since deleted). It's still in the way: replacing its files under it
    /// is what `HeldInstalls` never does, and macOS brings it forward instead of opening the new one.
    func macCopies(of project: LampProject) -> [NSRunningApplication] {
        let place = project.installedURL.standardizedFileURL.resolvingSymlinksInPath()
        // By its place only for an app that has a Mac copy there: a wish's Mac app in a folder of its own is installed
        // under the wish's name too, which a wish whose first app went still has. Its own id is its alone.
        return NSWorkspace.shared.runningApplications.filter { app in
            !app.isTerminated && (app.bundleIdentifier == project.bundleID
                || project.holdsApp && project.hasMac && app.bundleURL?.standardizedFileURL.resolvingSymlinksInPath() == place)
        }
    }

    /// Puts the build, with the icon as it is now, in the apps folder, unless the app is open: then it waits
    /// for the app to close (HeldInstalls says why a running app is never replaced). False when it waits.
    @discardableResult
    private func installIcon(_ project: LampProject) async -> Bool {
        // An app that is only its widget is never something the person has open: when it's running, it's
        // out of sight, waiting to say the widget was placed. It's quit like a build quits an app, gets
        // its icon, and goes back to waiting, so nobody is told to close an app they can't see.
        let watching = Template.isWidgetOnly(project) && isRunning(project)
        if watching { await quit(project) }
        // What's built may be a change that crashed the app (`setAside`), or one whose crash macOS hasn't reported yet
        // (a watch still on it, `watchAfterReload`): it waits, and goes in when the watch ends with nothing set aside
        // (`endWatch`) or another change replaces the one that was.
        guard heldInstalls.mayInstall(project.id, running: isRunning(project) || setAsideChanges[project.id] != nil
                                      || reloadWatches[project.id] != nil) else { return false }
        // A build that waited goes in now the app is closed: its data is copied first, as `install` does.
        let held = Runtime.holdsBuild(project)
        if held { await DataSnapshots.take(project) }
        do {
            try await deploy(project)
            if held { await DataSnapshots.wentIn(project) }
            // A build that waited for the app to close goes in the same way, and is the app's stamp from now on.
            if Runtime.holdsBuild(project) {
                Runtime.releaseBuild(project)
                stamps[project.id] = BuildStamp.read(project.installedURL)
            }
        } catch {}
        if watching { await watchWidget(of: project) }
        // The change is in: a request paused for it goes on (`pause`), once the app is given back.
        startQueued(project)
        return true
    }

    /// Apps that are closed get the icon that was waiting for them: asked when an app closes, and again
    /// whenever an app is given back (`finish`), since an app that closed while a turn had it couldn't be
    /// installed then, and a turn that only replied, was stopped or failed installs nothing itself. Owning
    /// the app meanwhile, like any install.
    private func installHeldIcons(for candidates: Set<String>) {
        // Only an app that's closed and has a build is taken: giving it back asks here again, so taking one
        // with nothing to install would go round for ever.
        let due = heldInstalls.due(amongClosed: candidates) { id in
            guard let project = projects.first(where: { $0.id == id }) else { return false }
            // Not while an app for both points at iOS: its build there isn't the Mac app's, and what waits is
            // for the Mac. It stays waiting, and goes in when Try On is back on this Mac.
            // Nor while a change that just went into it is watched: its going may be that change's crash, whose build
            // mustn't replace the version the person had (`setAside`).
            return !project.onIOS && !isRunning(project) && FileManager.default.fileExists(atPath: project.builtURL.path)
                && reloadWatches[id] == nil && setAsideChanges[id] == nil
        }
        for project in projects where due.contains(project.id) {
            guard begin(project) != nil else { continue }
            Task {
                // Installed or not, the wait ends here (`mayInstall`), so the app being given back finds nothing due.
                await installIcon(project)
                finish(project)
            }
        }
    }

    /// Puts the messages in the chat and their files in Attachments/. Returns the saved file names.
    private func post(_ messages: [QueuedMessage], to project: LampProject) -> [String] {
        var saved: [String] = []
        for message in messages {
            var names = message.kept + Attachments.save(message.attachments, to: project)
            // The picture of what was pointed at is one of the request's files, and the line says which.
            var pointed = message.pointed
            if let picture = pointed?.url {
                let folder = project.dir.appendingPathComponent(Attachments.folder).standardizedFileURL
                let name = picture.standardizedFileURL.deletingLastPathComponent() == folder
                    ? picture.lastPathComponent : Attachments.save([picture], to: project).first
                pointed?.picture = name ?? ""
                if let name { if !names.contains(name) { names.append(name) } } else { pointed = nil }
            }
            log(project, .user, message.text, attachments: names.isEmpty ? nil : names)
            if let pointed, let last = logs[project.id]?.indices.last {
                logs[project.id]?[last].pointed = pointed
                saveChat(project)
            }
            if let card = message.card, Talk.shows(logs[project.id]?.first { $0.id == card }), let last = logs[project.id]?.indices.last {
                logs[project.id]?[last].fromCard = true
                saveChat(project)
            }
            if message.byLamp, let last = logs[project.id]?.indices.last {
                logs[project.id]?[last].byLamp = true
                saveChat(project)
            }
            if message.replaces != nil || !message.tookBack.isEmpty, let last = logs[project.id]?.indices.last {
                logs[project.id]?[last].replaced = message.replaces
                logs[project.id]?[last].tookBack = message.tookBack.isEmpty ? nil : message.tookBack
                saveChat(project)
            }
            saved += names
        }
        return saved
    }

    /// How a turn ended: the app changed, the agent only replied, or there's no working app
    /// (the agent couldn't run or was stopped, or the app won't build or open).
    enum TurnEnd { case changed, replied, failed }

    struct TurnResult {
        var end: TurnEnd
        /// The user had this app's chat on screen, so there's nothing to notify about.
        var watched: Bool
    }

    /// What the agent is told of a request that is only files, with no words.
    private static func onlyFiles(_ count: Int) -> String {
        """
        The user sent only the attached file\(count == 1 ? "" : "s"), with no message. Work out what \
        they most likely want from it: a screenshot or mockup usually means "make the app look or work like \
        this" (or, if it shows this app, "fix what's wrong here"); a document or data file usually means \
        "use this in the app". If it's clear, do it. If it could mean several different things, ask one \
        short question instead of guessing.
        """
    }

    /// One turn of the loop: agent edits → build (agent fixes failures) → commit → relaunch.
    /// `asked` are the chat lines of the requests, which are linked to the version the turn makes.
    private func turn(_ messages: [QueuedMessage], attachments saved: [String], asked: [UUID],
                      on started: LampProject) async -> TurnResult {
        // The agent may change what the app is made for (`make_app_for`) while it works: after each of its runs,
        // the rest of the turn goes on with the app as Lamp now has it, so its build is for the new kind.
        var project = started
        guard let owner = turns[project.id] else { return TurnResult(end: .failed, watched: true) }
        // A request of the person's own: a Stop they pressed earlier no longer keeps Lamp from carrying on.
        if messages.contains(where: { !$0.byLamp }) { away.personAsked(project.id) }
        // Once, when the turn is over: its own build and install, and any run that fixes a crash, come after the agent's.
        owner.began = Date()
        defer {
            if let tally = Self.outcomeTally(owner.outcomes, name: project.name) { log(project, .detail, tally) }
            if let pace = Self.paceTally(began: owner.began, shown: owner.shown, outcomes: owner.outcomes) { log(project, .detail, pace) }
        }
        var prompt = messages.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n")
        // Attachments with no words: usually a screenshot or mockup meaning "like this", or a file to use.
        if prompt.isEmpty { prompt = Self.onlyFiles(saved.count) }

        let files = Attachments.inline(saved, in: project).map { "\(Attachments.folder)/\($0)" }
        // After a request is sent again the build on disk is still of the code that was just taken back, so
        // its picture and its crashes say nothing about the files the agent has now.
        let sentAgain = messages.contains { $0.replaces != nil || !$0.tookBack.isEmpty }
        let pointed = asked.compactMap { id in logs[project.id]?.first { $0.id == id }?.pointed }
        let notes = Attachments.note(for: saved) + PointedAt.note(for: pointed) + Versions.note(for: project)
            + (sentAgain ? "" : Runtime.crashNote(for: project) + Runtime.screenshotNote(for: project))
        // A crash the agent hasn't heard of goes with the request, and counts as told only once the request has reached
        // the agent, like the note about going back: a run that never started leaves it for the next request.
        let carried = setAsideChanges[project.id].flatMap { $0.told ? nil : $0.crash }
        let crashAside = carried.map { "\n\nNote from Lamp: a change saved earlier crashed the open app. \($0)\nFix the cause as part of this request." } ?? ""
        turns[project.id]?.request = prompt
        turns[project.id]?.requests = asked
        turns[project.id]?.carriedSetAside = carried
        let ran = await runAgent(prompt + notes + crashAside, files: files, sendsRequest: true, on: project)
        project = current(project) ?? project
        if let carried, let last = asked.last, Self.reachedAgent(last, in: logs[project.id] ?? []),
           setAsideChanges[project.id]?.crash == carried {
            setAsideChanges[project.id]?.told = true
        }
        // The note about going back is the agent's only word of it, so it's kept until the agent has had it:
        // a turn that failed before reaching the agent leaves it for the next one.
        if let last = asked.last, Self.reachedAgent(last, in: logs[project.id] ?? []) { Versions.forgetNote(for: project) }
        guard ran else {
            return TurnResult(end: .failed, watched: isWatching(project.id))
        }
        // The agent asked: nothing is built or saved in this turn, even if a file was written in the moment
        // before Lamp ended it. That holds whether or not the card still waits: an answer clicked while the
        // agent was finishing is only in line, and the agent hasn't had it. Its turn picks up from here.
        if owner.asked {
            return TurnResult(end: .replied, watched: isWatching(project.id))
        }
        // Still finding the wish, or setting up a device: there's no app to build or save, whatever the agent did.
        if project.makesNoApp {
            return TurnResult(end: .replied, watched: isWatching(project.id))
        }
        // A new app the agent didn't touch: it only replied (say, with questions about a vague request).
        // There's nothing worth building or opening yet; the answers start the first build.
        if !hasVersions(project), await !agentChangedFiles(project) {
            return TurnResult(end: .replied, watched: isWatching(project.id))
        }
        // Only build when something changed: not after a question, and not again when the agent's last
        // look already built and opened exactly this code.
        try? await writeOwnFiles(project, all: false)
        var changed = Runtime.sourcesChanged(project)
        if changed, owner.paused {
            // A file written in the moment before Lamp ended the agent: built once, with no run of the agent to fix it
            // (nothing it did could be seen). One that doesn't build is neither saved nor installed, as after any
            // build that fails, and its errors go to the agent with the request that carries on after Reload.
            if let errors = await build(project) {
                carry(errors, into: project)
                log(project, .error, ErrorMessages.buildFailed)
                return TurnResult(end: .failed, watched: isWatching(project.id))
            }
        } else if changed {
            guard await buildFixingErrors(project) else {
                return TurnResult(end: owner.asked ? .replied : .failed, watched: isWatching(project.id))
            }
            project = current(project) ?? project   // a fix may have changed what it's made for
        }
        // The wish's apps in folders of their own as the one in its own folder: each one the agent changed is built, and its errors go back to
        // the agent the same way, before the version is saved, so the version holds what every app of the wish builds.
        var changedParts: Set<String> = []
        // A fix the agent makes for one app may change another (a message both read), so the apps are looked at again
        // until every one's files are what it was last built from, and only then is the version saved.
        for _ in 0..<3 {
            for part in parts(of: project) {
                // One the agent took away while fixing another is no longer the wish's.
                guard let part = current(part) else { continue }
                guard let built = await asPartOf(project, part, { () async -> Bool in
                    try? await self.writeOwnFiles(part, all: false)
                    guard Runtime.sourcesChanged(part) else { return true }
                    changedParts.insert(part.id)
                    guard owner.paused else { return await self.buildFixingErrors(part) }
                    guard let errors = await self.build(part) else { return true }
                    self.carry("\(self.placeName(part)), in \(part.dir.lastPathComponent)/:\n\(errors)", into: project)
                    self.log(project, .error, ErrorMessages.buildFailed)
                    return false
                }) else { continue }
                guard built else { return TurnResult(end: owner.asked ? .replied : .failed, watched: isWatching(project.id)) }
                project = current(project) ?? project
            }
            guard Runtime.needsBuild(project) else { break }
            changed = true
            if owner.paused {
                if let errors = await build(project) {
                    carry(errors, into: project)
                    log(project, .error, ErrorMessages.buildFailed)
                    return TurnResult(end: .failed, watched: isWatching(project.id))
                }
            } else {
                guard await buildFixingErrors(project) else {
                    return TurnResult(end: owner.asked ? .replied : .failed, watched: isWatching(project.id))
                }
                project = current(project) ?? project
            }
            guard parts(of: project).contains(where: Runtime.needsBuild) else { break }
        }
        // Fixes that went on changing each other's apps: nothing is saved or opened over code some app wasn't built from.
        // Code that went into the open app counts as built: its whole build goes on after the turn.
        if Runtime.needsBuild(project) || parts(of: project).contains(where: Runtime.needsBuild) {
            log(project, .error, ErrorMessages.buildFailed)
            return TurnResult(end: .failed, watched: isWatching(project.id))
        }
        // Opening the app brings it in front of Lamp, so whether the user was watching is decided first.
        let watched = isWatching(project.id)
        // Nothing is committed when the agent changed no files.
        let label = owner.messages.filter { !$0.isEmpty }.joined(separator: "\n\n").nilIfEmpty
            ?? Self.label(attachments: saved)
        let saving = await Versions.commitAll("-qm \"$LAMP_PROMPT\"", in: project.dir, env: ["LAMP_PROMPT": label])
        var committed = saving == .saved
        // Said once the turn's last save is known: a fix for a crash on launch saves again, and may get through.
        var unsaved = saving == .failed
        let edited = changed || !changedParts.isEmpty || committed
        // Each app of the wish is opened or shown as the turn left it, and a crash on launch is that app's own.
        var crashes: [String: String] = [:]
        crashes[project.id] = await settle(project, changed: changed, owner: owner)
        for part in parts(of: project) {
            guard let part = current(part) else { continue }
            if let crash = await asPartOf(project, part, { await self.settle(part, changed: changedParts.contains(part.id), owner: owner) }) ?? nil {
                crashes[part.id] = crash
            }
        }
        // Like build errors, a crash on launch goes back to the agent. The fix joins this turn's commit,
        // so Undo still reverts the whole change.
        for _ in 0..<2 where !crashes.isEmpty && !owner.stopped {
            log(project, .status, "Fixing the crash…")
            let crashed = ([project] + parts(of: project)).filter { crashes[$0.id] != nil }
            guard await runAgent(crashRequest(crashed, crashes), on: project) else { return TurnResult(end: .failed, watched: watched) }
            project = current(project) ?? project
            // It asked instead of fixing: the turn waits for the answer here, as it does after any question.
            if owner.asked { return TurnResult(end: .replied, watched: watched) }
            // What the fix changed is built and opened, whichever app it's in (a shared type, say), with the apps that
            // crashed; a part the fix took away is gone from the list.
            let fixing = ([project] + parts(of: project)).filter { crashes[$0.id] != nil || Runtime.sourcesChanged($0) }
            for app in fixing {
                guard let app = current(app) else { continue }
                guard await asPartOf(project, app, { await self.buildFixingErrors(app) }) ?? true else {
                    return TurnResult(end: owner.asked ? .replied : .failed, watched: watched)
                }
            }
            project = current(project) ?? project
            let commit = committed ? "-q --amend --no-edit" : "-qm 'Fix a crash on launch'"
            switch await Versions.commitAll(commit, in: project.dir) {
            case .saved: (committed, unsaved) = (true, false)
            case .failed: unsaved = true
            case .nothingToSave: break
            }
            crashes = [:]
            for app in fixing {
                guard let app = current(app), !owner.stopped else { continue }
                if let crash = await asPartOf(project, app, { await self.install(app) }) ?? nil { crashes[app.id] = crash }
            }
        }
        // The change is in the app either way. Without a version of its own it can't be gone back to by
        // itself, and the person should know that rather than find it out from Undo.
        if unsaved { log(project, .error, ErrorMessages.versionNotSaved) }
        for app in [project] + parts(of: project) where crashes[app.id] != nil {
            log(project, .error, ErrorMessages.quitsAfterLaunch(app.isPart ? placeName(app) : project.name))
        }
        // After the crash fixes, which amend the commit, so the name and the links stay on the version that's kept.
        if committed || turns[project.id]?.pendingName != nil, let head = await Versions.head(project) {
            if let name = turns[project.id]?.pendingName {
                turns[project.id]?.pendingName = nil
                await Versions.name(project, head, name)
            }
            if committed {
                link(asked + owner.midTurn, to: head, in: project)
                // Not of a copy the person kept open: it's the version before this one.
                if crashes[project.id] == nil, !owner.keptOpen { keepPicture(of: project, version: head) }
                titleVersions(project, limit: 1)
            }
            versionsRevision += 1
        }
        let failed = !crashes.isEmpty || owner.stopped || owner.phoneReady == false
        // Not over an app that couldn't be put in place or opened either: that isn't a failed turn, but the
        // card would say it's ready next to the line saying it didn't open.
        // A new app that opened in a window of its own: its chat goes on beside it from now on.
        if !failed, edited, !owner.didNotOpen, !owner.keptOpen { Task { await MagicPanel.shared.handOff(project) } }
        return TurnResult(end: failed ? .failed : edited ? .changed : .replied, watched: watched)
    }

    /// An app of the turn's wish as the turn leaves it: one the agent changed is installed and opened; one a look opened
    /// is shown (or put on the device chosen for it), unless it died in its first seconds. What's known of a crash on
    /// launch, or nil.
    private func settle(_ project: LampProject, changed: Bool, owner: Turn) async -> String? {
        // After Stop nothing more is opened, and an install Stop cut short is no crash for the agent to fix.
        guard !owner.stopped else { return nil }
        let name = project.isPart ? placeName(project) : project.name
        if changed {
            let crash = await install(project)
            // A device app that couldn't go on its device (not set up, not on the network) didn't crash: the chat
            // already says why, with the step that fixes it, and there's nothing in the code to fix.
            return project.onDevice || owner.stopped ? nil : crash
        }
        guard let turn = turns[project.id], turn.look.installed[project.id] == true else { return nil }
        // The look went on once the app showed: a death in its first seconds is known by now, or in a moment. One the
        // agent was never told of is a crash on launch even when a later launch came through: it may come again.
        // A launch Lamp itself closed and replaced isn't waited for: only a crash report would make its going a
        // death, and the wait for one that never comes would hold up the turn for nothing.
        for watch in turn.launches where !watch.told && watch.app == project.id {
            if await watch.wentAway(), !watch.retired { _ = await watch.verdict() }
        }
        let untold = lateCrash(of: turn, app: project.id)
        if let crash = turn.look.crashes[project.id] ?? untold { return crash }
        // An app for both pointed at the iPhone goes to the simulator or the phone, even with its Mac copy open.
        if !project.onIOS, let app = macCopies(of: project).first {
            // The look opened it behind the user's windows. Now it's theirs: it shows itself, as when it's
            // opened again. An app that lives in the menu bar opens its panel (see LampWindows).
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name(Edition.notificationPrefix + "showWindow"), object: project.bundleID, userInfo: nil, deliverImmediately: true)
            app.activate()
            log(project, .status, "\(name) is \(owner.updatedInPlace ? "updated" : "ready")")
        } else if project.onDevice, let run = deviceRuns[project.id], deviceRunBuilt[project.id] == Runtime.builtFingerprint(project) {
            // The look put it on the device already, as it is now. One that went to the preview on this Mac
            // didn't, so the change goes on the device below.
            log(project, .status, "\(name) is open on \(run.device.name).")
        } else if !isOnChosenPhone(project) {
            let crash = await install(project)
            return project.onDevice || owner.stopped ? nil : crash
        }
        return nil
    }

    /// What the agent is asked after apps of the wish died on launch: a wish's one app as ever, each of several by name
    /// and folder, each with what's known of its crash.
    private func crashRequest(_ apps: [LampProject], _ crashes: [String: String]) -> String {
        if apps.count == 1, let app = apps.first, !app.isPart, parts(of: app).isEmpty, let crash = crashes[app.id] {
            return "The app builds, but it quit right after launching. Find the cause and fix it.\n\n\(crash)"
        }
        let each = apps.compactMap { app in
            crashes[app.id].map { (app.isPart ? "\(placeName(app)), in \(app.dir.lastPathComponent)/," : "\(placeName(app)), in the wish's own folder,") + " builds, but it quit right after launching.\n\n\($0)" }
        }
        return each.joined(separator: "\n\n") + "\n\nFind the cause and fix it."
    }

    /// Work on one of a wish's other apps under the wish's turn, as a part's look is (`underTurn`), so everything that
    /// asks which turn has the app finds it. The wish's own app is worked on as it is. Nil when the part is busy with a
    /// turn of its own (opened from its menu), which builds and opens it itself.
    private func asPartOf<T>(_ wish: LampProject, _ app: LampProject, _ work: () async -> T) async -> T? {
        guard app.id != wish.id, let turn = turns[wish.id] else { return await work() }
        guard turns[app.id] == nil || turns[app.id] === turn else { return nil }
        // Held already (a look within, or an outer hold): left as it was found.
        let before = turns[app.id]
        turns[app.id] = turn
        defer { if turns[app.id] === turn { turns[app.id] = before } }
        return await work()
    }

    /// Whether any request has made a version of this app yet (its messages are linked to the versions they made).
    private func hasVersions(_ project: LampProject) -> Bool {
        (logs[project.id] ?? []).contains { $0.kind == .user && $0.version != nil }
    }

    /// Whether the agent changed any of the app's files this turn. Lamp's own writes don't count: it
    /// regenerates LampSupport.swift, designs the icon (icon.json) while the agent works, and saves the
    /// request's attachments before the agent starts.
    private func agentChangedFiles(_ project: LampProject) async -> Bool {
        var output = ""
        let ignored = "':!Sources/LampSupport.swift' ':!\(Template.sceneSupportPath)' ':!\(Template.widgetFolder)/\(Template.widgetSupportFile)' ':!\(Template.shareFolder)/\(Template.shareSupportFile)' ':!icon.json' ':!\(Attachments.folder)'"
            + Template.watchSupportPaths.map { " ':!\($0)'" }.joined()
        _ = await Versions.git("git status --porcelain -- . \(ignored)", cwd: project.dir) {
            output += $0
        }
        return !output.trimmed.isEmpty
    }

    /// Builds the app, sending compiler errors back to the agent up to three times. False when it still doesn't
    /// build, or when the agent asked the person something instead (`Turn.asked`).
    private func buildFixingErrors(_ started: LampProject) async -> Bool {
        await turns[started.id]?.early?.value
        var project = current(started) ?? started
        var errors = await build(project)
        // The person's Apple account or tools that aren't on this Mac yet, not the code: build has said so, with the
        // window that fixes it, and the agent has nothing to fix.
        func isTheAccount() -> Bool {
            errors != nil && [macMembershipProblem(project), androidToolsProblem(project), gameToolsProblem(project)].contains(errors)
        }
        for _ in 0..<3 where errors != nil && !isTheAccount() {
            // A build the user stopped (or whose app they deleted) isn't a problem for the agent to fix.
            guard turns[project.id]?.stopped != true, exists(project) else { return false }
            log(project, .status, "Fixing a problem…")
            // A part's errors go to its wish's agent, which has the wish's conversation, with the part's name and folder.
            let which = project.isPart ? "\(placeName(project)), in \(project.dir.lastPathComponent)/," : "The app"
            guard await runAgent("\(which) failed to build. Fix these compiler errors:\n\n\(errors!)",
                                 on: wish(of: project)) else { return false }
            project = current(project) ?? project
            // Asking ends the turn while fixing as well: no build, and no further try, under a card that
            // hasn't been answered. Whoever called says the turn is waiting, not that it failed.
            if turns[project.id]?.asked == true { return false }
            errors = await build(project)
        }
        guard turns[project.id]?.stopped != true, exists(project) else { return false }
        if errors != nil, !isTheAccount() {
            log(project, .error, ErrorMessages.buildFailed)
        }
        return errors == nil
    }

    /// The Mac half of an app for both is signed for the person's team, so one that keeps data in iCloud
    /// can't be built there on a free account (`Devices.membershipProblem`). Nil anywhere else.
    private func macMembershipProblem(_ project: LampProject) -> String? {
        project.platform == .universal && !project.onIOS ? Devices.membershipProblem(for: project, on: "this Mac") : nil
    }

    /// Returns false when the agent couldn't run at all (bad key, no credit, …), after telling the user why.
    /// `sendsRequest`: this run carries the turn's own request, not a repair Lamp asks for after it (a build's
    /// errors, a crash), which an engine switched to meanwhile needs the turn's messages for (`CatchUp`).
    private func runAgent(_ prompt: String, files: [String] = [], sendsRequest: Bool = false, on project: LampProject) async -> Bool {
        // A turn started at launch (one waiting from before) may come before the look for the person's own
        // Claude Code or Codex has finished: it waits for it rather than finding no copy.
        if Builder.engine != .pi, EngineInstall.path(for: Builder.engine) == nil, !EngineInstall.hasLooked {
            await EngineInstall.lookForPersonsCopies()
        }
        if let problem = Builder.problem() {
            log(project, .error, "\(problem) Open Lamp → Settings (⌘,) to fix it.")
            return false
        }
        let engine = Builder.engine
        // What builds this turn, as it starts, for the titles of its steps after it (`StepTitles`).
        let titleRoute = StepTitles.TurnRoute.current
        if engine == .pi && Builder.piProvider == Builder.localProvider {
            do {
                try await LocalModels.shared.ensureServer(for: Builder.piModel)
            } catch {
                log(project, .error, error.localizedDescription)
                return false
            }
        }
        let started = Date()
        var cost = 0.0
        var failure: String?
        // Guard against runaway agents (small local models can loop): stop after the same step 6 times
        // in a row, or 150 tool calls in one turn.
        var lastTool = ""
        var repeats = 0
        var toolCalls = 0
        // The tool call the model is writing at the moment, for the activity shown to the user.
        var streamingTool = ""
        var streamingArguments = ""
        // Whether the agent has answered at all: the request, with any word on the notes in it, got through.
        var answered = false
        guard let turn = turns[project.id] else { return false }   // only inside a turn (startQueued)
        turn.titleRoute = titleRoute
        // One turn can run the agent several times (fixing build errors, a crash on launch): each run's summary
        // shows only the pictures painted during it.
        let artBefore = turn.artCost
        turn.stopped = false
        let sessionFile = Self.sessionFile(for: project, engine: engine)
        // After the stopped mark is cleared, so a Stop pressed while the file is written is seen by the check below.
        // Every app of the wish: the agent may read or change any of them.
        try? await writeOwnFiles(project, all: false)
        for part in parts(of: project) { try? await writeOwnFiles(part, all: false) }
        // What the agent is told about the app's AI follows the sign-ins as they are. Checking them can take a
        // while, and Stop pressed meanwhile has no agent to end yet: if the turn was stopped or replaced, or the
        // app deleted, during the wait, the agent isn't started.
        await EngineSignIn.refresh()
        guard turns[project.id] === turn, !turn.stopped, exists(project) else {
            if turn.stopped, exists(project) {
                turn.stopped = false
                log(project, .status, "Stopped. Any changes made so far are kept; press Undo to discard them.")
            }
            return false
        }
        if sendsRequest { followPromptShape(project) }
        // A conversation the copy of the engine Lamp runs can't resume (one kept by the other copy, Lamp's or
        // the person's, not found to bring over) is forgotten, and the request starts a new one rather than failing.
        var session = engine == .pi ? Self.piSession(for: project) : Self.savedSession(sessionFile)
        if engine != .pi, let saved = session, !EngineInstall.carryOver(session: saved, for: engine) {
            try? FileManager.default.removeItem(at: sessionFile)
            session = nil
        }
        // What was said in the chat since this engine's conversation last ran (with another engine, or in one
        // that was ended) goes with the request, so switching engines doesn't lose the conversation.
        let missed = CatchUp.note(for: project, engine: engine, session: session, chat: logs[project.id] ?? [],
                                  turn: turn.requests, sendsRequest: sendsRequest)
        var run = Agent.run(prompt: prompt + missed, files: files, project: project, offered: offers(in: project),
                            session: session, token: turn.agentToken)
        turn.saysCommands = run.saysCommands
        // Held strongly: it lives only while the engine runs. (A weak capture here, in a closure kept in a
        // variable rather than passed straight to `Shell.run`, came back nil and dropped every line.)
        let onLine: @MainActor (String) -> Void = { [self] line in
            for event in Agent.parseLine(line) {
                // A tool is running from the call until the model is heard from again.
                switch event {
                case .tool: turn.toolRunning = true
                case .text, .textPiece, .step, .finished: turn.toolRunning = false
                default: break
                }
                // The model has been heard from, so Codex has saved the request (the run's own, or messages passed on).
                if engine == .codex, !turn.codexStarted {
                    switch event {
                    case .acting, .text:
                        turn.codexStarted = true
                        received(project)
                    default: break
                    }
                }
                // Not the engine saying it passed a message of the person's on: that isn't the model answering.
                if case .raw = event {} else if case .failed = event {} else if case .received = event {} else { answered = true }
                // The model carrying on after a failed attempt means the engine recovered from it (pi sends again
                // after a dropped connection, after compacting a conversation that overflowed, and after its
                // extension drops the pictures of a request that was too big: lamp-tools.ts), so that attempt is
                // no longer the turn's failure. Lamp's own reasons for stopping the model stand: the process is
                // being ended, and what it had already printed can still arrive.
                if let text = failure, !text.hasPrefix("The model ") {
                    switch event {
                    case .text, .textPiece, .tool, .step: failure = nil
                    default: break
                    }
                }
                switch event {
                case .textPiece(let piece):
                    write(piece, for: project)
                case .text(let text):
                    // The whole message. It takes the place of what was shown of it while it was written.
                    // What the agent last said it was doing is over: the steps after this message are the message's.
                    turn.naming = nil
                    let written = turn.writing?.line
                    turn.writing = nil
                    // The message is written: what comes next isn't known yet, so the line no longer says "Replying"
                    // while the agent thinks. A step the engine already reported in the same reply keeps its words.
                    if progress[project.id]?.activity == Self.replying { noteAgent(Activity.thinking, for: project) }
                    if let line = written, let index = logs[project.id]?.lastIndex(where: { $0.id == line }) {
                        logs[project.id]?[index].text = text
                        saveChat(project)
                    } else {
                        log(project, .agent, text)
                    }
                    // Between Codex's steps: a message waiting to be passed on can go now.
                    if engine == .codex { steer(project) }
                case .step(let tool):
                    if !tool.isEmpty { endIfOver(turn, before: tool) }
                    // The model has finished writing the file it was streaming. One that writes every file in a
                    // single reply has them all carried out only once the reply ends, so without this the
                    // checklist would sit still and then tick at once.
                    let streamed = TurnProgress.call(tool: streamingTool, partialArguments: streamingArguments)
                    if let file = TurnProgress.file(changedBy: streamed) { progress[project.id]?.wrote(file) }
                    // Likewise the plan, which a model may send in the same reply as every file: shown once it's
                    // written rather than once the reply ends, so the list is there to tick as the files come.
                    if streamingTool == "plan",
                       let arguments = try? JSONSerialization.jsonObject(with: Data(streamingArguments.utf8)) as? [String: Any],
                       arguments["parts"] != nil {
                        progress[project.id]?.plan = PlanPart.parts(from: arguments)
                        progress[project.id]?.tickWrittenParts()
                    }
                    streamingTool = tool
                    streamingArguments = ""
                    noteAgent(TurnProgress.activity(tool: tool, partialArguments: ""), for: project)
                case .stepArgs(let piece):
                    // The file name is among the first arguments; the rest is the file itself.
                    guard streamingArguments.count < 600 || streamingTool == "plan" else { break }
                    streamingArguments += piece
                    let call = TurnProgress.call(tool: streamingTool, partialArguments: streamingArguments)
                    noteAgent(TurnProgress.activity(for: call), file: TurnProgress.file(changedBy: call), for: project)
                case .plan(let parts):
                    progress[project.id]?.plan = parts
                    progress[project.id]?.tickWrittenParts()
                case .compacted:
                    Memory.compacted(project)
                    AIStatus.compacted(project)
                    Skills.compacted(project)
                    DeviceNote.compacted(project)
                    WishNote.compacted(project)
                    Parts.compacted(project)
                case .naming(let words):
                    turn.naming = words.nilIfEmpty
                    if let words = turn.naming { noteAgent(words, for: project) }
                case .tool(let text, let fullCall, let said, let id, let command):
                    let call = ToolCall(text)
                    let named = Self.stepName(of: call, said: said, naming: turn.naming, engine: engine)
                    log(project, .tool, text, said: named)
                    if let id, let line = logs[project.id]?.last?.id { turn.calls[id] = (line, command) }
                    endIfOver(turn, before: call.name)
                    noteAgent(named ?? TurnProgress.activity(for: call), file: TurnProgress.file(changedBy: call), for: project)
                    if let file = TurnProgress.file(changedBy: call) { progress[project.id]?.wrote(file) }
                    toolCalls += 1
                    // Compared in full: six different searches of one file all read "grep cache.json".
                    repeats = fullCall == lastTool ? repeats + 1 : 1
                    lastTool = fullCall
                    if repeats >= 6 || toolCalls > 150, failure == nil {
                        failure = repeats >= 6
                            ? "The model got stuck repeating the same step, so Lamp stopped it."
                            : "The model made over 150 changes in one go, so Lamp stopped it."
                        if let process = turn.agent { Subprocess.terminateTree(process) }
                    }
                    steer(project)
                case .cost(let amount): cost += amount
                case .failed(let text):
                    // Codex saying the turn Lamp interrupted didn't finish: it goes on in the next run.
                    if turn.codexCut != nil { break }
                    if engine == .pi, Agent.isRequestTooLarge(text), failure.map(Agent.isRequestTooLarge) != true {
                        log(project, .status, Agent.droppingPictures)
                    }
                    failure = text
                case .raw(let text): log(project, .detail, text)
                case .received:
                    received(project)
                case .acting(let id, let started):
                    if started { turn.codexActing.insert(id) } else { turn.codexActing.remove(id); steer(project) }
                case .ended(let id, let failed):
                    if failed, let call = turn.calls[id] { markFailed(call.line, id: id, command: call.command, in: project) }
                case .ran(let command, let refused, let failed, let id):
                    // A command Codex ran is said in the chat as a command Lamp let run is, by the name the agent gave
                    // it; one its reviewer refused is the same step, marked only when it's opened (`ChatLook.ranCommand`).
                    // A run whose commands each come to Lamp's card says nothing here: the others' don't either. Its
                    // row was logged as the card let it run, and says so if it failed.
                    guard turn.saysCommands else {
                        if failed { markFailed(nil, id: id, command: command, in: project) }
                        break
                    }
                    log(project, .status, (refused ? ChatLook.notRun : "Ran: ") + command, said: turn.naming, failed: failed, call: id)
                case .finished:
                    // Claude Code has answered. A message sent from now on is the next request.
                    turn.input?.close()
                    turn.input = nil
                    if let process = turn.agent { endAfterAnswer(process, in: turn) }
                case .session(let id):
                    if engine == .claude { turn.claudeSession = id }
                    if engine != .pi {
                        try? id.write(to: sessionFile, atomically: true, encoding: .utf8)
                        Memory.delivered(to: project, session: id)
                        AIStatus.delivered(to: project, session: id)
                        Skills.delivered(to: project, session: id)
                        DeviceNote.delivered(to: project, session: id)
                        WishNote.delivered(to: project, session: id)
                        Parts.delivered(to: project, session: id)
                    }
                }
            }
        }
        var status: Int32
        while true {
            let input = run.opening.map { opening in
                let input = AgentInput()
                input.write(opening)
                return input
            }
            turn.input = input
            turn.steering = engine
            turn.autoApply?.cancel()
            if turn.warming == nil, let current = current(project), isRunning(current) { turn.warming = warmLive(current) }
            turn.autoApply = autoApply(project, in: turn)
            turn.endedAfterAnswer = false
            status = await Shell.run(run.command, cwd: project.dir, env: run.env, input: input,
                                     started: { turn.agent = $0 }, onLine: onLine)
            if turn.endedAfterAnswer { status = 0 }
            turn.autoApply?.cancel()
            turn.autoApply = nil
            await turn.applying?.value
            // Codex was interrupted to be given the person's messages (`steer`): it goes on in the same
            // conversation with them, unless the turn was stopped or ended meanwhile, or Lamp stopped the model.
            guard let message = turn.codexCut else { break }
            turn.codexCut = nil
            turn.agent = nil
            turn.codexStarted = false
            turn.codexActing = []
            // Codex exits with an error on a turn it was asked to end; that's not this turn's failure.
            if failure?.hasPrefix("The model ") != true { (status, failure) = (0, nil) }
            // Not when the engine was changed in Settings meanwhile: this conversation is Codex's.
            guard !turn.stopped, !turn.endedOnQuestions, failure == nil, Builder.engine == engine,
                  let id = Self.savedSession(sessionFile), exists(project) else { break }
            run = Agent.run(prompt: Agent.carryOn(message), files: [], project: current(project) ?? project,
                            offered: offers(in: project), session: id, token: turn.agentToken)
            // The setting may have changed since the turn began, and with it whether Lamp's hook says each command.
            turn.saysCommands = run.saysCommands
        }
        turn.agent = nil
        turn.codexStarted = false
        turn.codexActing = []
        turn.input = nil
        turn.steering = nil
        turn.toolRunning = false
        takeBackHanded(project)
        if answered { Memory.delivered(to: project); AIStatus.delivered(to: project); Skills.delivered(to: project); DeviceNote.delivered(to: project); WishNote.delivered(to: project); Parts.delivered(to: project) }
        endApprovals(for: project)
        // A message cut short (the run was stopped, or failed) keeps what was written of it.
        showWritten(for: project)
        turn.writing = nil
        // Pictures are already in the app's building cost (recordArt); the summary shows them with the rest.
        log(project, .summary, LogLine.workSummary(seconds: Date().timeIntervalSince(started), cost: cost + turn.artCost - artBefore))
        // The folds the run's messages didn't close get their lines now, never waited on.
        StepTitles.start(for: project, turn: titleRoute)
        recordAgent(project, cost: cost)
        if turn.stopped {
            turn.stopped = false
            log(project, .status, "Stopped. Any changes made so far are kept; press Undo to discard them.")
            return false
        }
        // Ended by Lamp on the agent's own questions: the engine's exit says nothing went wrong.
        if turn.endedOnQuestions { return true }
        if let failure, failure.hasPrefix("The model ") {
            log(project, .error, failure + " Try again, or pick a stronger model in Settings.")
            return false
        }
        if status != 0 && failure == nil { failure = "\(engine.title) exited with status \(status)" }
        guard let failure else { return true }
        log(project, .detail, failure)
        // Claude Code's auto permission mode isn't offered on every account or model: fall back to asking
        // before every command, remember that, and run the turn again.
        let lower = failure.lowercased()
        if engine == .claude, CommandApproval.current.isAutomatic, !CommandApproval.claudeAutoUnavailable,
           lower.contains("auto"), lower.contains("mode") || lower.contains("permission") {
            CommandApproval.claudeAutoUnavailable = true
            log(project, .status, "Claude's auto mode isn't available, so Lamp will ask before every command.")
            return await runAgent(prompt, files: files, sendsRequest: sendsRequest, on: project)
        }
        // A request too big to send, which the engine couldn't shrink (Claude Code and Codex don't in Lamp's
        // non-interactive runs; pi's extension drops pictures and tries once more before this is reached):
        // every later request would be too big too, so the conversation ends here and the next request starts
        // a fresh one. The notes (Memory) and the app's AI status are told again to the new conversation.
        if Agent.isRequestTooLarge(failure) {
            Self.forgetConversation(of: project, engine: engine)
            log(project, .error, Agent.conversationTooLarge)
            return false
        }
        log(project, .error, Provider.friendlyError(failure, from: Provider.name(of: engine)))
        return false
    }

    /// A waiting message the person sent with Send Now goes to the agent in the same turn: the engine gives it to
    /// the model after the tools it is running, before the model goes on. Any other waiting message is the next
    /// request, as before. pi asks for them after each of its turns (`/agent/steer`, lamp-tools.ts); Claude Code is
    /// written to while a tool runs (`steer`). Each goes into the chat as it's handed over, and is a request of this
    /// turn (its version is the turn's) once the engine's output shows the model has it (`received`); until then
    /// it can still go back in line. Returns what the agent is sent, nil when nothing can go.
    private func handOver(_ project: LampProject) -> String? {
        // Nothing more while a handover is unconfirmed: a receipt confirms everything handed over, so one that
        // never arrived could otherwise be counted by the next one's receipt instead of going back in line.
        guard let turn = turns[project.id], turn.agent != nil, turn.steering != nil, !turn.asked, !turn.paused, !turn.stopped,
              turn.handed.isEmpty, current(project)?.finding == false, let waiting = queued[project.id] else { return nil }
        let taken = waiting.filter { $0.sendNow && $0.card == nil && $0.replaces == nil && $0.tookBack.isEmpty && !$0.afterReload }
        guard !taken.isEmpty else { return nil }
        let rest = waiting.filter { message in !taken.contains { $0.id == message.id } }
        queued[project.id] = rest.isEmpty ? nil : rest
        saveWaiting()
        let saved = post(taken, to: project)
        guard var chat = logs[project.id] else { return nil }
        let lines = chat.indices.filter { chat[$0].kind == .user }.suffix(taken.count)
        for index in lines {
            chat[index].midTurn = true
            if let head = turn.sentFrom { chat[index].before = head }
        }
        logs[project.id] = chat
        saveChat(project)
        turn.handed += lines.map { chat[$0].id }
        let words = taken.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n")
        return (words.isEmpty ? Self.onlyFiles(saved.count) : words)
            + Attachments.note(for: saved, inlined: false) + PointedAt.note(for: lines.compactMap { chat[$0].pointed })
            + Agent.midTurnNote
    }

    /// The engine's output shows the model has the requests handed to it: from now on they're the turn's.
    private func received(_ project: LampProject) {
        guard let turn = turns[project.id], !turn.handed.isEmpty else { return }
        let lines = logs[project.id] ?? []
        turn.midTurn += turn.handed
        turn.messages += turn.handed.compactMap { id in lines.first { $0.id == id }?.text }
        turn.handed = []
        turn.tookOver = false   // they've had their say since: what they asked may be to try it again
    }

    /// Requests handed to an engine that ended without giving them to the model (it failed, was stopped, or Lamp's
    /// answer never reached it) leave the chat and wait at the front of the line again, as the next request.
    private func takeBackHanded(_ project: LampProject) {
        guard let turn = turns[project.id], !turn.handed.isEmpty, var chat = logs[project.id] else { return }
        let handed = Set(turn.handed)
        turn.handed = []
        let again = chat.filter { handed.contains($0.id) }.map {
            QueuedMessage(text: $0.text, kept: $0.attachments ?? [], pointed: $0.pointed?.waiting(in: project))
        }
        chat.removeAll { handed.contains($0.id) }
        logs[project.id] = chat
        saveChat(project)
        queued[project.id, default: []].insert(contentsOf: again, at: 0)
    }

    /// Claude Code takes the person's messages on its input: written while a tool runs, a message is there when
    /// the tool's result is, and the model reads both before it goes on.
    ///
    /// Codex's `exec` reads nothing once it has started, so its run is interrupted and the next one resumes the
    /// conversation with the messages (`runAgent`). The interrupt is Codex's own (SIGINT, as Ctrl-C would be):
    /// it ends the turn, records that in the conversation and exits, so the next run has everything the model
    /// did up to then. It comes only between the things Codex does, never during a command, an edit, a tool call
    /// or a search, nor while Lamp answers a call from it (a tool, an approval), so nothing is left half done;
    /// what the model was thinking or writing then is lost, and it answers again in the next run.
    private func steer(_ project: LampProject) {
        guard let turn = turns[project.id] else { return }
        switch turn.steering {
        case .claude:
            guard turn.toolRunning, let input = turn.input, let message = handOver(project) else { return }
            input.write(Agent.claudeMessage(message))
        case .codex:
            guard turn.codexStarted, turn.codexActing.isEmpty, turn.answering == 0, turn.codexCut == nil, !turn.approving,
                  approvals[project.id] == nil, let process = turn.agent,
                  let codex = Subprocess.descendant(of: process, named: "codex"),
                  let message = handOver(project) else { return }
            turn.codexCut = message
            kill(codex, SIGINT)
            note("Reading your message", for: project)
            // Codex ends a turn within a moment. One that hasn't gone after a while is ended as Stop would end it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
                if turn.agent === process { Subprocess.terminateTree(process) }
            }
        default:
            return
        }
    }

    /// Asking ends the turn, and so does asking to see a change the person hasn't seen yet (`pause`). The tool says
    /// so, and an agent that goes on to another step anyway (it has been seen to ask and then build the app without
    /// waiting, and to be told its change waits for Reload and then say the result was in, never having seen it) is
    /// ended here, the way a runaway one is: what it would build is a guess at the answer, under a card the person
    /// hasn't answered yet, or at an app it can't see until they press Reload.
    private func endIfOver(_ turn: Turn, before tool: String) {
        guard Self.endsAgent(asked: turn.asked, paused: turn.paused, before: tool), !turn.endedOnQuestions,
              let process = turn.agent else { return }
        turn.endedOnQuestions = true
        // Codex is ended with its own interrupt, as `steer` does, so it records the turn it was in before it exits
        // and resumes with the look's answer in its conversation; ended outright it loses what it hadn't saved.
        if turn.steering == .codex, let codex = Subprocess.descendant(of: process, named: "codex") {
            kill(codex, SIGINT)
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
                if turn.agent === process { Subprocess.terminateTree(process) }
            }
        } else {
            Subprocess.terminateTree(process)
        }
    }

    /// Whether a tool call ends the agent's turn: any after it asked, other than the ask itself, and any at all once
    /// its change waits for the person. Said once, here, so the three engines are held to the same rule.
    static func endsAgent(asked: Bool, paused: Bool, before tool: String) -> Bool {
        paused || (asked && ToolCall(tool).action != .ask)
    }

    /// A look or `use_app` while the agent's change waits for the person (Reload, or an app they kept open; an app
    /// they're using is never reopened under them). The first time in a turn the agent is told and goes on with what's
    /// left, since a person who comes back later would rather find the work done than a turn that stopped at its
    /// first held change (`Agent.lookRules`); a look after that, or any `use_app`, is the agent asking to see or try
    /// an app that doesn't show its change, so the turn stops there (`pause`): the agent says it needs to see the
    /// change, and goes on after Reload.
    private func held(_ turn: Turn, in project: LampProject, note: String, using: Bool = false) -> (Int, [String: Any]) {
        if Self.stopsToSee(told: turn.toldHeld, using: using) {
            return pause(turn, in: project, saying: Self.seeNote(reloadOffered: Runtime.waitsForReload(project)), status: using ? 409 : 200)
        }
        turn.toldHeld = true
        return (200, ["text": note])
    }

    /// Whether a look or `use_app` on a held change stops the turn: a look once the agent has been told the change
    /// waits, and `use_app` always, since nothing can be tried in an app that doesn't show the change. Said once,
    /// here, so the three engines are held to the same rule.
    static func stopsToSee(told: Bool, using: Bool) -> Bool { told || using }

    /// The agent asked to see its change and can't until the person has pressed Reload: the turn is over whatever it
    /// does next (`endIfOver`), and Lamp's own request to carry on waits in line behind the Reload (`afterReload`),
    /// so the agent looks at its change before more is done to it. The person's own messages typed meanwhile wait in
    /// the same line: nothing reloads the app but the button (or Lamp, once they're away: `reloadIfAway`), and nothing
    /// is changed that they can't see.
    private func pause(_ turn: Turn, in project: LampProject, saying text: String, status: Int = 200) -> (Int, [String: Any]) {
        turn.paused = true
        queueCarryOn(project)
        return (status, [status == 200 ? "text" : "error": text])
    }

    /// Lamp's own request to carry on after the held change is in (`Agent.afterReload`), first in line.
    private func queueCarryOn(_ project: LampProject) {
        let project = Self.requestOwner(of: project, among: projects)
        guard !(queued[project.id] ?? []).contains(where: \.afterReload) else { return }
        // Messages queued before it keep copies of their files too, now that the line outlives a relaunch.
        queued[project.id] = [QueuedMessage(text: Agent.afterReload, byLamp: true, afterReload: true)]
            + (queued[project.id] ?? []).map(keptForLater)
        saveWaiting()
    }

    /// The request paused for Reload is over: the person went another way (Undo, an earlier version, the request sent
    /// again in other words), and carrying it on would do work on a change they just backed out of.
    private func dropPausedRequest(_ project: LampProject) {
        guard queued[project.id]?.contains(where: \.afterReload) == true else { return }
        queued[project.id]?.removeAll(where: \.afterReload)
        if queued[project.id]?.isEmpty == true { queued[project.id] = nil }
        saveWaiting()
    }

    /// A file the agent wrote after the pause didn't build: its errors go with the request that carries on after
    /// Reload, in place of "carry on", since nothing of it was saved or installed.
    private func carry(_ errors: String, into project: LampProject) {
        guard let index = queued[project.id]?.firstIndex(where: \.afterReload) else { return }
        let text = Agent.afterReload + "\n\nA file you changed after your last look didn't build, so it wasn't saved or " +
            "installed: the app has the change from that look, not this one. Fix these compiler errors first:\n\n" + errors
        queued[project.id]?[index] = QueuedMessage(text: text, byLamp: true, afterReload: true)
        saveWaiting()
    }

    /// Whether the waiting messages wait for the person's Reload (`pause`): the chats say so under them.
    func queueWaitsForReload(in project: LampProject) -> Bool {
        !Self.startsNow(queued[project.id] ?? [], changeHeld: holdsAnyBuild(project))
    }

    /// Whether the waiting messages may start a turn now: not while the first of them carries a paused request on
    /// and the change it waits for is still held from the app (`pause`); the person's Reload, or the app closing,
    /// puts the change in and lets them go.
    /// A change held from the wish's own app or from one of its other parts: the request that carries on after a part's
    /// Reload waits for that Reload as one after the wish's does.
    private func holdsAnyBuild(_ project: LampProject) -> Bool {
        Runtime.holdsBuild(project) || parts(of: project).contains(where: Runtime.holdsBuild)
    }

    static func startsNow(_ messages: [QueuedMessage], changeHeld: Bool) -> Bool {
        !(messages.first?.afterReload == true && changeHeld)
    }

    /// Ends the engine's conversation for an app: the next request starts a new one, and is told what every
    /// new conversation is told.
    /// A wish's conversations began with the prompt of the app in its own folder, or with the wish's own when its apps
    /// are all in folders (`Agent.wishPrompt`), and Claude Code and Codex keep the one they began with. Once that's
    /// changed (its first app taken away, or brought back by a restore), they're forgotten as a request starts, and it
    /// starts one with the prompt that fits, told the chat so far (`CatchUp`), as a wish given its kinds is (`decided`).
    /// The wish's prompt for one app holds that app's rules, so it's told by that app's kind too: a TV app replaced by an
    /// Android app is a prompt of its own. Conversations from before this was kept began with the app's.
    private func followPromptShape(_ project: LampProject) {
        guard !project.isPart, !project.makesNoApp else { return }
        let file = project.dir.appendingPathComponent(".lamp/prompt-for")
        let parts = parts(of: project)
        // A game's or a screen's own prompt once told it to list its places among `devices`; they're `places` now, so a
        // conversation that began before that starts again with the rules that say so.
        let now = project.holdsApp ? (project.platform.addsPlaces ? "app places" : "app")
            : parts.count == 1 ? "wish " + parts[0].platform.rawValue : "wish"
        guard (AppFile.text(file, in: project)?.trimmed ?? "app") != now else { return }
        for engine in Engine.allCases { Self.forgetConversation(of: project, engine: engine) }
        try? now.write(to: file, atomically: true, encoding: .utf8)
    }

    private static func forgetConversation(of project: LampProject, engine: Engine) {
        let file = engine == .pi ? project.dir.appendingPathComponent(".lamp/pi-session") : sessionFile(for: project, engine: engine)
        try? FileManager.default.removeItem(at: file)
        Memory.compacted(project)
        AIStatus.compacted(project)
        Skills.compacted(project)
        DeviceNote.compacted(project)
        WishNote.compacted(project)
        Parts.compacted(project)
    }

    /// One pi conversation per app, so the agent remembers earlier requests, including ones that were undone.
    private static func piSession(for project: LampProject) -> String {
        let url = project.dir.appendingPathComponent(".lamp/pi-session")
        if let id = Template.ownSecret(at: url, in: project) { return id }
        let id = "lamp-" + UUID().uuidString.lowercased()
        try? id.write(to: url, atomically: true, encoding: .utf8)
        return id
    }

    /// External engines report their own conversation ids; Lamp keeps one per engine per app.
    private static func sessionFile(for project: LampProject, engine: Engine) -> URL {
        project.dir.appendingPathComponent(".lamp/session-\(engine.rawValue)")
    }

    /// An engine's conversation id as Lamp kept it. It goes to the engine, and to its environment, so it's read as
    /// `AppFile` reads and only as engines write them.
    private static func savedSession(_ url: URL) -> String? {
        let folder = url.deletingLastPathComponent().deletingLastPathComponent()
        return Template.ownSecret(at: url, in: LampProject(id: folder.lastPathComponent, name: "", exe: "", dir: folder))
    }

    /// Deletes an app: quits it, stops its agent, and moves its source and built app to the Trash.
    func delete(_ project: LampProject) async {
        stop(project)
        iconDesigns.removeValue(forKey: project.id)?.cancel()
        // Its other parts close first, each the way it closes (a Mac part may ask about unsaved work and be kept open):
        // a part left running would answer for a folder in the Trash, with no wish to quit it from.
        let parts = parts(of: project)
        for part in parts {
            guard await quit(part) else {
                log(project, .status, ErrorMessages.notDeleted(project.name))
                return
            }
        }
        guard await quit(project) else {
            log(project, .status, ErrorMessages.notDeleted(project.name))
            return
        }
        stop(project)   // anything begun while the app was asking about unsaved work
        // Its widget's process too: in the Trash it would go on running, and answer for an app made later
        // under the same name.
        await WidgetProcess.end(for: project)
        // A device app is taken off the devices Lamp put it on, and Lamp's packages of it go.
        if project.holdsApp, project.onDevice {
            // An install already under way runs to its end (Stop ends no request mid-upload, and a device may take minutes
            // to say how it went), so it's let finish before its package is taken off again; its own requests and polls
            // are bounded, so this ends.
            while installingApps.contains(project.id) { try? await Task.sleep(for: .milliseconds(300)) }
            await DeviceApps.removeEverywhere(project, among: devices)
            try? FileManager.default.removeItem(at: DeviceApps.buildFolder(for: project))
        }
        let fm = FileManager.default
        if fm.fileExists(atPath: project.installedURL.path) {
            try? fm.trashItem(at: project.installedURL, resultingItemURL: nil)
        }
        await settleFiles(project)
        settleChat(project)
        do {
            try fm.trashItem(at: project.dir, resultingItemURL: nil)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        Self.trashData(of: project)
        for part in parts { await forget(part) }
        try? fm.removeItem(at: Devices.buildFolder(for: project))
        try? fm.removeItem(at: Devices.signingFolder(for: project))
        // Its sign-ins too: an app made later under the same name is another app, and starts disconnected.
        AppSecrets.forget(app: project.instance)
        if project.platform.target.places.contains(where: [.tv, .device].contains) { TVPreview.forget(project) }
        WishKeys.forget(project)
        projects.removeAll { $0.id == project.id }
        logs[project.id] = nil
        unkeptChats[project.id] = nil
        usage[project.id] = nil
        queued[project.id] = nil
        icons[project.id] = nil
        crashesAfterRelease[project.id] = nil
        release(project)
        unread.remove(project.id)
        tokens = tokens.filter { $0.value != project.id }
        // A wish deleted from its chat leaves the person on the desk.
        if selection == project.id { selection = nil }
    }

    /// What the app kept on this Mac goes with it, so an app made later under the same name starts empty rather
    /// than opening this one's data: its data folder (`LampStore.folder`, under the plain id), and anything under
    /// an id it was signed as (the plain id and a team after it, also from before it was made for the Mac alone),
    /// to the Trash like the rest. Its settings (UserDefaults) are written into the data folder first and cleared
    /// only once that copy is written.
    private static func trashData(of project: LampProject) {
        let fm = FileManager.default
        let library = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let support = library.appendingPathComponent("Application Support")
        let plain = Edition.appBundlePrefix + project.id
        let data = support.appendingPathComponent(plain)
        let isThisApp = { (name: String) in name == plain || name.hasPrefix(plain + ".") }
        let preferences = (try? fm.contentsOfDirectory(atPath: library.appendingPathComponent("Preferences").path)) ?? []
        let domains = Set(preferences.filter { $0.hasSuffix(".plist") }.map { String($0.dropLast(6)) }.filter(isThisApp)
                          + [plain, project.bundleID])
        for id in domains.sorted() {
            guard let settings = UserDefaults.standard.persistentDomain(forName: id), !settings.isEmpty else { continue }
            let copy = data.appendingPathComponent("Settings \(id).plist")
            guard (try? fm.createDirectory(at: data, withIntermediateDirectories: true)) != nil,
                  (settings as NSDictionary).write(to: copy, atomically: true) else {
                print("Delete \(project.name): couldn't keep a copy of its settings (\(id)), so they stay")
                continue
            }
            UserDefaults.standard.removePersistentDomain(forName: id)
        }
        for name in ((try? fm.contentsOfDirectory(atPath: support.path)) ?? []).filter(isThisApp) {
            try? fm.trashItem(at: support.appendingPathComponent(name), resultingItemURL: nil)
        }
    }

    // MARK: - Approvals

    /// Commands confined for Claude Code's classifier to judge (`format=claude-confine`), by what they became, with
    /// what the agent wrote and said they were for, so its card and the chat show the agent's words.
    private var confinedCommands: [String: (original: String, said: String?, call: String?)] = [:]

    /// The latest request per app, so the decision model can judge commands against what the user asked for.

    /// Applies Settings → Building → "Ask before running commands" to one command.
    /// `sandboxed`: the command will run confined to the app (Sandbox), so where it looks isn't in question.
    /// `said` is what the agent said the command is for, which names it in the chat (`LogLine.said`).
    private func approveCommand(_ command: String, for project: LampProject, escalated: Bool, shell: Bool = true, sandboxed: Bool,
                                said: String? = nil, call: String? = nil) async -> Bool {
        switch CommandApproval.current {
        case .never:
            log(project, .status, "Ran: \(command)", said: said, call: call)
            return true
        case .risky where !escalated:
            let judgment = await commandJudgment(command, for: project, aboutRequest: !sandboxed)
            // A command the sandbox confines can only change the app's own folder (Sandbox), so only one the
            // checks find risky asks: one they're merely unsure of, or that doesn't seem to match the request
            // (looking for the app's process while fixing it), runs. Asking about those was most of the cards,
            // nearly all of them allowed. A check that couldn't be made at all goes to the in-app model's rating:
            // the sandbox leaves the network open, so it isn't the only guard, but a "low" there runs it.
            if judgment.verdict == .run || (sandboxed && judgment.verdict == .unsure && judgment.judged) {
                log(project, .status, "Ran: \(command)", said: said, call: call)
                return true
            }
            // A risky verdict always has its reason; if one were ever missing, the card still comes up as flagged.
            let flagged = judgment.verdict == .risky ? judgment.reason ?? .reachesBeyond : nil
            let allowed = await requestApproval(for: project, command: command, shell: shell, sandboxed: sandboxed, flagged: flagged,
                                                said: said)
            if allowed, shell { log(project, .status, "Ran: \(command)", said: said, call: call) }
            return allowed
        case .risky where shell:
            // Claude Code's own classifier judged it and asked: the person decides, with no second check of
            // Lamp's and no rating that runs it on a "low".
            return await requestApproval(for: project, command: command, shell: shell, sandboxed: sandboxed, said: said,
                                         mayRunOnRating: false)
        default:
            // A command allowed on the card is a step like any other, by the name the agent gave it, whichever engine
            // asked, as one that needed no card is.
            let allowed = await requestApproval(for: project, command: command, shell: shell, sandboxed: sandboxed, said: said)
            if allowed, shell { log(project, .status, "Ran: \(command)", said: said, call: call) }
            return allowed
        }
    }

    /// Whether a command is plainly fine, for every engine: the decision model's answers (CommandRisk),
    /// against the user's request when `aboutRequest`. No decision model available → not plainly fine.
    /// A command judged once in a turn isn't sent again for the same request; one the model couldn't judge is.
    private func commandJudgment(_ command: String, for project: LampProject, aboutRequest: Bool) async -> CommandRisk.Judgment {
        let turn = turns[project.id]
        let request = turn?.request ?? ""
        let key = [aboutRequest ? request : "", project.dir.path, command].joined(separator: "\u{0}")
        if let known = turn?.judgments[key] { return known }
        let judgment = await CommandRisk.judge(command: command, request: request, folder: project.dir.path,
                                               aboutRequest: aboutRequest) { state, questions in
            try await AppAI.decide(state: state, questions: questions).0
        }
        if judgment.judged { turn?.judgments[key] = judgment }
        return judgment
    }

    /// Applies Settings → Building → Permissions and Privacy to one of the agent's file tools, about to touch `path`: pi's own
    /// tools ask through its extension, Codex's come from Lamp's MCP endpoint. The reason is for the agent.
    private func fileAccess(tool: String, path: String, for project: LampProject) async -> (allowed: Bool, reason: String?) {
        switch Privacy.verdict(tool: tool, path: path, project: project) {
        case .allow: return (true, nil)
        case .deny(let reason): return (false, reason)
        case .ask:
            let card = Privacy.explanation(tool: tool, path: path, project: project)
            let allowed = await requestApproval(for: project, command: card.command,
                                                title: "The agent wants a file outside this app's folder",
                                                explanation: card.explanation)
            return (allowed, allowed ? "Approved in Lamp."
                : "The user didn't allow that. It's outside the app's folder; work with what's inside it, or say what you need and why.")
        }
    }

    /// Asks the in-app AI model to describe a command for a non-technical person: what it does, and its risk.
    private func explain(_ command: String, for project: LampProject, sandboxed: Bool = false) async -> CommandExplanation? {
        await CommandRisk.rating(command: command, request: turns[project.id]?.request ?? "",
                                 building: "\(project.platform.target.identity.phrase) called \"\(project.name)\"") { prompt, system in
            try await AppAI.complete(prompt: prompt, images: [], system: system, json: true).0
        }
    }

    /// Waits for the user to allow or deny a shell command. One request per app at a time; others queue.
    /// There's no timeout: commands wait until the user answers, stops the turn, or the turn ends.
    /// `flagged`: the check that found the command risky; the card gives that check's reason rather than
    /// call it low risk. Under "Only when risky", a shell command nothing flagged that the in-app model rates
    /// low runs without the card (`CommandRisk.runsOnRating`).
    func requestApproval(for project: LampProject, command: String, title: String? = nil,
                         explanation given: CommandExplanation? = nil, shell: Bool = true, sandboxed: Bool = false,
                         flagged: CommandRisk.Reason? = nil, said: String? = nil, mayRunOnRating: Bool = true) async -> Bool {
        guard !command.trimmed.isEmpty else { return false }
        if turns[project.id]?.allowAll == true {
            log(project, .detail, "Ran (allowed for this turn): \(command)")
            return true
        }
        // One request per app at a time, from here on: a second one waits, including through the
        // explanation below, so two can't both put up a card for the same slot.
        while approvals[project.id] != nil || turns[project.id]?.approving == true { try? await Task.sleep(for: .milliseconds(200)) }
        guard let turn = turns[project.id], turn.agent != nil else { return false }   // the agent is gone: nobody to answer for
        turn.approving = true
        defer { turn.approving = false }
        // The rating comes first when it could spare the card: a command the checks left to it, or that Claude
        // Code asked about itself, runs on a "low". It gets a few seconds (`ratingWait`); a slower one comes to
        // the card, which offers Allow and Deny at once and still runs the command if the "low" arrives after.
        let ratingDecides = shell && title == nil && flagged == nil && CommandApproval.current == .risky && mayRunOnRating
        var given = given
        var asked = false   // the in-app model's answer is in, or none came
        var late: Task<CommandExplanation?, Never>?
        if ratingDecides, given == nil {
            note("Checking a command", for: project)
            let rating = Task { await explain(command, for: project, sandboxed: sandboxed) }
            if let answer = await Self.answer(of: rating, within: Self.ratingWait) { (given, asked) = (answer, true) } else { late = rating }
            guard turn.agent != nil else { return false }
        }
        // The setting is read again: it may have changed while the rating was worked out.
        if ratingDecides, CommandApproval.current == .risky, CommandRisk.runsOnRating(given, flagged: flagged) {
            // The caller says it ran, as for an Allow.
            log(project, .detail, "Ran without asking (\(given?.risk ?? "") risk): \(given?.summary ?? "")")
            note(said ?? "Running a command", for: project)   // as after an Allow, so "Checking a command" doesn't stay
            return true
        }
        NSApp.requestUserAttention(.informationalRequest)
        note(title == nil ? "Waiting for your OK to run a command" : "Waiting for your OK", for: project)
        let lateRating = late
        return await withCheckedContinuation { continuation in
            // Asked already and nothing came back: the card says so rather than wait for an answer that isn't coming.
            var pending = PendingApproval(command: command, answer: continuation,
                                          explanation: given?.raised(for: flagged) ?? (asked ? .unexplained(flagged: flagged) : nil))
            if let title { pending.title = title }
            pending.request = turn.request
            pending.whyAsked = Self.whyAsked(file: title != nil, flagged: flagged)
            pending.said = said
            approvals[project.id] = pending
            // Explain it while the card is up; until this arrives the card says it's working it out.
            if given == nil, !asked { Task {
                let rating: CommandExplanation?
                if let lateRating { rating = await lateRating.value } else { rating = await explain(command, for: project, sandboxed: sandboxed) }
                guard approvals[project.id]?.id == pending.id else { return }
                if ratingDecides, CommandApproval.current == .risky, CommandRisk.runsOnRating(rating, flagged: flagged) {
                    log(project, .detail, "Ran without asking (\(rating?.risk ?? "") risk): \(rating?.summary ?? "")")
                    answerApproval(for: project, allow: true)
                    return
                }
                approvals[project.id]?.explanation = rating?.raised(for: flagged) ?? .unexplained(flagged: flagged)
            } }
        }
    }

    /// How long a command waits for the in-app model's rating before its card comes up without it.
    static let ratingWait: Duration = .seconds(10)

    /// The task's answer, or nil when it isn't in within `limit`; the task carries on either way.
    static func answer<T>(of task: Task<T, Never>, within limit: Duration) async -> T? {
        let first = FirstAnswer<T>()
        return await withCheckedContinuation { continuation in
            first.continuation = continuation
            Task { @MainActor in first.give(await task.value) }
            Task { @MainActor in try? await Task.sleep(for: limit); first.give(nil) }
        }
    }

    /// Why the card is up, for How to Decide: a file outside the app, a check that flagged the step, the setting that
    /// asks about every command, or a step the checks couldn't be sure stays inside the app. Each is said as it is,
    /// so a low-risk command asked about because of the setting isn't described as reaching past the app.
    nonisolated static func whyAsked(file: Bool, flagged: CommandRisk.Reason?, always: Bool = CommandApproval.current == .always) -> String {
        if file { return "The agent works inside this app's folder by itself. A file outside it is yours to share or not." }
        if flagged != nil {
            return "The agent works on this app by itself, and stops for your OK when a step could reach past it. Lamp's check found that this one could."
        }
        if always {
            return "You chose to be asked before every command the agent runs. You can change that in Settings → Building."
        }
        return "The agent works on this app by itself, and stops for your OK when Lamp can't be sure a step stays inside it. This is one of those."
    }

    func answerApproval(for project: LampProject, allow: Bool, allowAll: Bool = false) {
        guard let pending = approvals.removeValue(forKey: project.id) else { return }
        if allowAll { turns[project.id]?.allowAll = true }
        log(project, .detail, (allow ? "Allowed: " : "Denied: ") + pending.command)
        let command = allow && pending.title == PendingApproval.commandTitle
        note(command ? pending.said ?? "Running a command" : "Thinking", for: project)
        pending.answer.resume(returning: allow)
    }

    /// Ends the approvals of one agent run: anything still waiting is denied. "Allow all for this turn" lasts
    /// the turn (its compile and crash fixes are further agent runs), so it resets in finish() and stop().
    private func endApprovals(for project: LampProject) {
        answerApproval(for: project, allow: false)
    }

    /// Stops the agent working on an app, and the build if one is going.
    func stop(_ project: LampProject) {
        // A turn still owns the app while awaiting a device check, even without a running subprocess.
        guard let turn = turns[project.id], !turn.stopped else { return }
        endApprovals(for: project)   // a command waiting for approval counts as denied
        if away.personStopped(project.id) { reloadWhenFree.remove(project.id) }
        turn.cancel()
        setAsideChanges[project.id]?.afterStop = true   // no fix starts by itself after Stop (`fixHeldCrash`)
        // A part the wish's Undo or restore is rebuilding, under a hold of its own.
        for part in parts(of: project) where rebuildingFor[part.id] == project.id { stop(part) }
    }

    /// Opens the installed app, or brings it to the front if it's running. Only builds when there's
    /// nothing installed yet (or the installed copy was deleted).
    func open(_ project: LampProject) async {
        // Only the wish, its apps all in folders of their own: each of them opens.
        guard project.holdsApp else { openWish(project); return }
        // Lamp can't tell whether a device app is still open on its device, so Open always puts it there.
        if project.onDevice {
            await run(project)
            return
        }
        if project.onTV {
            // The preview alone: open already, it comes forward; a TV chosen gets the app put on it (Play).
            if project.device == nil, TVPreview.isOpen(project), !Runtime.sourcesChanged(project) { TVPreview.bringForward(project); return }
            await run(project)
            return
        }
        if project.onAndroid {
            if await isAndroidRunning(project) {
                await Emulator.bringForward()
                return
            }
            if FileManager.default.fileExists(atPath: project.builtURL.path), !Runtime.sourcesChanged(project), !Template.androidWishOutdated(project) {
                guard begin(project) != nil else { return }
                defer { finish(project) }
                await installReportingCrash(project)
            } else {
                await run(project)
            }
            return
        }
        if project.onIOS {
            // Running already: bring the simulator forward. Otherwise build (if needed) and launch.
            let toSimulator = project.device == nil
            if toSimulator, let running = simulatorApps[project.id], Simulator.isRunning(pid: running.pid), simulatorLeases[running.udid] == project.id { await Simulator.show(running.udid); return }
            // An app for both reuses a build only when it was made for this place from this code (the
            // place is part of the fingerprint), else it's built again.
            if FileManager.default.fileExists(atPath: project.builtURL.path), stamps[project.id]?.isOutdated(for: project) != true,
               !(project.platform == .universal && Runtime.sourcesChanged(project)) {
                guard begin(project) != nil else { return }
                defer { finish(project) }
                await installReportingCrash(project)
            } else {
                await run(project)
            }
            return
        }
        // Built by an older Lamp: rebuild it first, so it gets this Lamp's fixes and building blocks.
        // Not while it's running (that would quit it under the user); if the build fails, the old one opens.
        if stamps[project.id]?.isOutdated(for: project) == true, !busy.contains(project.id),
           macCopies(of: project).isEmpty {
            if await updateForThisForge(project) { return }
        }
        // Its App Intents or its share extension were left out for want of a team to sign it for, and there is one
        // now: built again, since the build that left them out has none to put back.
        let intentsBack = await Self.intentsCanComeBack(project)
        let shareBack = await Self.shareCanComeBack(project)
        if intentsBack || shareBack, !busy.contains(project.id),
           macCopies(of: project).isEmpty {
            if await updateForThisForge(project, because: "Signing \(project.name) for your Apple team…") { return }
        }
        if let running = macCopies(of: project).first {
            // Ask the app to show a window (opening a new one if all were closed); see LampWindows. The app
            // says when it has: a window, or the panel of an app that lives in the menu bar, which isn't an
            // ordinary window and wouldn't be found below.
            let acknowledged = Acknowledgement(name: Edition.notificationPrefix + "windowShown", object: project.bundleID)
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name(Edition.notificationPrefix + "showWindow"), object: project.bundleID, userInfo: nil, deliverImmediately: true)
            running.activate()
            // Whatever the app did with that (an app built before the listener existed ignores it; one that
            // replaced New Window can't open one), something has to be on screen: if there's nothing, relaunch it.
            let shown = await acknowledged.wait(seconds: 1.5)
            guard !running.isTerminated else { return }   // it's relaunching itself (LampWindows.relaunch)
            guard !shown, !Self.hasWindow(running.processIdentifier) else { return noteOpened(true, for: project) }
            // Only if it goes when asked: one that doesn't may hold something, and is left as it is.
            let asked = Date()
            guard await AppQuit.close(running, id: project.id, runtime: Runtime.macFolder(project),
                                      stopped: { Date().timeIntervalSince(asked) > 15 }) else { return }
        }
        // A build that waited for the app to close, and didn't get in then (Lamp wasn't running): it goes in now.
        if Runtime.holdsBuild(project) {
            await run(project)
            return
        }
        guard FileManager.default.fileExists(atPath: project.installedURL.path),
              !(project.platform == .universal && Runtime.sourcesChanged(project)) else {
            await run(project)
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.arguments = ["-LampInFront", "YES"]   // see install
        do {
            _ = try await NSWorkspace.shared.openApplication(at: project.installedURL, configuration: config)
            noteOpened(true, for: project)
        } catch {
            log(project, .error, ErrorMessages.openFailed(error.localizedDescription))
            noteOpened(false, for: project)
        }
        refreshOpenApps()
    }

    /// The sidebar in Chrome chose an app that isn't open: it opens as last built, behind the page the person is on.
    /// Not while Lamp is building it, and only one try at a time while the app comes up.
    func openForSidebar(_ project: LampProject) {
        guard !busy.contains(project.id), macCopies(of: project).isEmpty,
              FileManager.default.fileExists(atPath: project.installedURL.path),
              openingForSidebar.insert(project.id).inserted else { return }
        Task {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            _ = try? await NSWorkspace.shared.openApplication(at: project.installedURL, configuration: config)
            refreshOpenApps()
            try? await Task.sleep(for: .seconds(15))
            openingForSidebar.remove(project.id)
        }
    }
    private var openingForSidebar: Set<String> = []

    /// The agent's `use_app` tool: hands its clicks, typing and keys to the open app, which performs them on its
    /// own front window (LampDriver in LampSupport), then reports what happened with a fresh picture.
    private func use(_ project: LampProject, request body: Data) async -> (Int, [String: Any]) {
        withLateCrash(await useNow(project, request: body), of: project)
    }

    /// A death in the first seconds of a launch a look went on from (`Runtime.LaunchWatch`), said once, ahead of the
    /// agent's next look or use_app; the turn's end takes it as a crash on launch too (`turn.look.crashes`).
    private func withLateCrash(_ result: (Int, [String: Any]), of project: LampProject) -> (Int, [String: Any]) {
        guard let turn = turns[project.id] else { return result }
        let note: String
        if let crash = lateCrash(of: turn) {
            note = "Note from Lamp: the app quit a few seconds after it was last opened, so it isn't running.\n\n\(crash)"
        } else if let aside = untoldSetAside(project) {
            note = "Note from Lamp: your last saved change crashed the app. \(aside)\nFix the cause; the next change you save goes in again."
        } else { return result }
        var (status, answer) = result
        if status == 200 { answer["text"] = note + "\n\n" + (answer["text"] as? String ?? "") }
        else { answer["error"] = note + "\n\n" + (answer["error"] as? String ?? "") }
        return (status, answer)
    }

    /// What's known of the deaths the turn's launches saw and nobody has been told of yet; they're told from here on.
    /// A look may have opened the app again since one of them (seeing it gone), so each launch is asked, not just
    /// the last; only each app's last one is what that app does now (`turn.look.crashes`). A wish's apps share its
    /// turn, so a death is said with the app it was, when that isn't the one at the root.
    private func lateCrash(of turn: Turn, app: String? = nil) -> String? {
        let untold = turn.launches.filter { $0.ended && $0.crash != nil && !$0.told && (app == nil || $0.app == app) }
        guard !untold.isEmpty else { return nil }
        for watch in untold {
            watch.told = true
            if turn.launches.last(where: { $0.app == watch.app }) === watch { turn.look.crashes[watch.app] = watch.crash }
        }
        return untold.compactMap { watch in
            watch.crash.map { crash in projects.first { $0.id == watch.app && $0.isPart }.map { "\(placeName($0)):\n\(crash)" } ?? crash }
        }.joined(separator: "\n\n")
    }

    private func useNow(_ project: LampProject, request body: Data) async -> (Int, [String: Any]) {
        guard let turn = turns[project.id], turn.agent != nil else { return (409, ["error": "Lamp isn't working on this app right now."]) }
        if turn.tookOver { return (200, ["text": Self.tookOverNote]) }
        guard let request = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let actions = request["actions"] as? [[String: Any]], !actions.isEmpty,
              let json = (try? JSONSerialization.data(withJSONObject: actions)).map({ String(decoding: $0, as: UTF8.self) }) else {
            return (400, ["error": "use_app needs a list of actions."])
        }
        if request["sidebar"] as? Bool == true {
            guard BrowserBridge.enabled, project.hasMac, !project.onIOS else { return (200, ["text": Self.noSidebar]) }
            // The sidebar is the open copy's too, so it's kept from the agent on the same terms as its windows (below).
            if Runtime.holdsBuild(project), isRunning(project) {
                return held(turn, in: project, note: Runtime.waitsForReload(project) ? reloadNote(for: project) : Self.keptOpenNote, using: true)
            }
            guard !macCopies(of: project).isEmpty else {
                return (200, ["text": "The app isn't open. Call look_at_app with sidebar first: it builds the app and opens it."])
            }
            return await BrowserPreview.use(project, actions: actions, page: request["page"] as? String, selection: request["selection"] as? String)
        }
        // A game is played in the preview, wherever else it's played: the same moves give the same frames.
        if GameKit.isGame(project) { return await useOnGame(project, actions: actions) }
        // A screen is used in the TV preview, wherever it's shown.
        if ScreenKit.isScreen(project) { return await useOnTV(project, actions: actions, json: json) }
        if project.onIOS { return await useOnSimulator(project, actions: actions, json: json) }
        if project.onAndroid { return await useOnAndroid(project, actions: actions, json: json) }
        if project.onTV { return await useOnTV(project, actions: actions, json: json) }
        if project.onDevice { return await useOnDeviceApp(project, actions: actions, json: json) }
        // Not in the copy the person kept open: what it holds is theirs, and it isn't the agent's change.
        if Runtime.holdsBuild(project), isRunning(project) {
            return held(turn, in: project, note: Runtime.waitsForReload(project) ? reloadNote(for: project) : Self.keptOpenNote, using: true)
        }
        guard let app = macCopies(of: project).first else {
            return (200, ["text": "The app isn't open. Call look_at_app first: it builds the app and opens it."])
        }
        // An app that can't be stopped part way (built before `LampDriver.Handover`) is rebuilt first: the person
        // is shown Stop, and it has to work.
        guard Self.binary(of: project, contains: "lampUseAppSignature"), Self.binary(of: project, contains: "lampUseAppStop") else {
            return (200, ["text": "The open app was built before use_app could do this. Call look_at_app to rebuild it, then try again."])
        }
        let readsScreen = Self.binary(of: project, contains: Self.screenTextMarker)
        if !readsScreen, actions.contains(where: { ($0["target"] as? String)?.isEmpty == false }) {
            return (200, ["text": "The open app was built before use_app could act on things by name. Call look_at_app to rebuild it, then try again."])
        }
        let id = UUID().uuidString
        let printed = Runtime.logSize(project)
        let asked = Date()
        // In plain sight, with the person's Stop: Lamp's Stop and Esc reach the app as a signed stop; their own
        // click or key in the app is seen by the app itself, which ends the batch and answers at once.
        var stoppedAt: Date?
        let trial = Handover(label: "\(Self.lampName) is trying \(project.name)") {
            stoppedAt = Date()
            Self.signal(project, "useAppStop", ["id": id], signedAs: "lampUseAppStop", over: "stop\n\(id)")
        }
        if let window = Handover.frontWindow(of: app.processIdentifier) { trial.show(window: window) }
        // Where each action is about to happen and how long until it does, from the app (`LampDriver.aimed`), for
        // Lamp's cursor to be there first: sent during the pause before the action, so nothing waits for the cursor.
        let steps = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(Edition.notificationPrefix + "useAppStep.\(project.id)"), object: nil, queue: .main) { note in
            guard let text = note.object as? String,
                  let step = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any], step["id"] as? String == id else { return }
            let window = (step["window"] as? Int).map { CGWindowID($0) }
            let doing = step["doing"] as? String, press = step["press"] as? Bool ?? false
            let due = step["in"] as? Double ?? Template.useAppLead   // an app built before it said: it waits the lead
            MainActor.assumeIsolated {
                if let window { trial.show(window: window) }
                guard let x = step["x"] as? Double, let y = step["y"] as? Double else { return }   // the window alone, at the start
                Task { await trial.aim(at: CGPoint(x: x, y: y), doing: doing, press: press, due: due) }
            }
        }
        defer {
            DistributedNotificationCenter.default().removeObserver(steps)
            trial.end()
        }
        // SwiftUI takes a click for a tap gesture only in the active app's key window (macOS 27), so a batch that
        // clicks brings the app in front, as a real click would. Only over Lamp, whose chat the person is watching:
        // never over another app they're using, where their typing would land in this one.
        if NSApp.isActive, !app.isActive, actions.contains(where: { ["click", "double_click", "drag"].contains($0["action"] as? String ?? "") }) {
            app.activate()
            try? await Task.sleep(for: .milliseconds(300))
            // Stop pressed meanwhile reached an app that had no batch yet to stop, so the batch isn't sent at all.
            if trial.tookOver {
                if !turn.tookOver {
                    turn.tookOver = true
                    log(project, .status, Self.stoppedByYou)
                }
                return (200, ["text": "Stopped: the person took the app over before anything was done.\n\n" + Self.tookOverNote])
            }
        }
        // Signed with the app's token rather than carrying it: distributed notifications reach every process.
        Self.signal(project, "useApp", ["actions": json, "id": id], signedAs: "lampUseAppSignature", over: "\(id)\n\(json)")
        // Waits, and keys held down (a Mac app's `key` with `amount`), each up to 10 seconds, as the app takes them;
        // and, per action, the pause after it and the lead apps built before the spot was sent ahead give the
        // cursor before every one (0.45 s): such an app isn't rebuilt while it's open, and still has to answer.
        let waits = actions.reduce(0.0) { total, action in
            switch action["action"] as? String {
            case "wait": total + min(action["amount"] as? Double ?? 1, 10)
            case "key": total + min(max(action["amount"] as? Double ?? 0, 0), 10)
            default: total
            }
        }
        let wait = Double(actions.count) * (0.4 + 0.45) + waits + 5
        // Once stopped, the app answers at once; one inside a dialog of its own can't until that closes, and isn't waited for.
        let answer = await Runtime.useReport(of: project, id: id, waiting: wait) {
            !app.isTerminated && (stoppedAt.map { Date().timeIntervalSince($0) < 2 } ?? true)
        }
        // Their own click or key in the app stopped it there: the pill says the app is theirs, as for Stop.
        if answer?.stopped == true { trial.take() }
        // Asked again after the reads below: they take a moment, and Stop may come during them.
        func tookOver() -> Bool {
            guard trial.tookOver else { return false }
            if !turn.tookOver {
                turn.tookOver = true
                log(project, .status, Self.stoppedByYou)
            }
            return true
        }
        guard let report = answer?.report else {
            if tookOver() {
                return (200, ["text": "Stopped: the person took the app over before it answered.\n\n" + Self.tookOverNote])
            }
            guard app.isTerminated else {
                return (200, ["text": "The app didn't answer. It may have no window open, or it may be stuck."])
            }
            return (200, ["text": "The app quit or crashed while doing that.\n\n" + (await Runtime.launchReport(project))])
        }
        var text = "What happened:\n\(report)"
        // The agent may have edited the code since: what it's clicking is the app from before those edits.
        if Runtime.sourcesChanged(project) {
            text += "\n\nThis is the app as last built: it doesn't have the changes you've made to the code since. " +
                "Call look_at_app to build and open them."
        }
        // The front window in words goes wherever its picture does: what's on it is the same thing either way.
        if Privacy.sharesPictures, readsScreen, let words = await Runtime.screenText(of: project, since: asked) { text += "\n\n" + words }
        if tookOver() { text += "\n\n" + Self.tookOverNote }
        text += Privacy.sharesPictures
            ? "\n\nPictures of its windows follow, frontmost first. The screen as text is the first picture's, and x and y for the next use_app are pixels in it."
            : "\n\n" + Privacy.picturesOff
        if !Privacy.sharesLog { text += " " + Privacy.logOff }
        if Privacy.sharesLog, let lines = Runtime.log(of: project, from: printed) { text += "\n\nWhat it printed meanwhile:\n\(lines)" }
        return (200, ["text": text, "screenshots": Self.agentPictures(Runtime.pictures(of: project), in: project)])
    }

    /// `look_at_app` with `sidebar`: the app is built and opened as for any look, then its sidebar in Chrome is
    /// drawn by Lamp (BrowserPreview) in place of its windows, beside the page the agent names.
    private func lookAtSidebar(_ project: LampProject, page: String?, reopen: Bool = false) async -> (Int, [String: Any]) {
        guard BrowserBridge.enabled, project.hasMac, !project.onIOS else { return (200, ["text": Self.noSidebar]) }
        let window = await look(at: project, reopen: reopen)
        guard window.0 == 200, !macCopies(of: project).isEmpty else { return window }
        // What's open isn't the agent's change (or not the fresh launch it asked for) while it waits for the person:
        // that's what the agent must hear, not a report of the old copy's sidebar.
        if let text = window.1["text"] as? String, [Self.askedToReopenNote, Self.keptOpenNote].contains(text) || text.hasPrefix(Self.reloadNoteStart) { return window }
        var (status, sidebar) = await BrowserPreview.look(project, page: page)
        // The window beside it, so the sidebar's items are judged against the app's, not on their own.
        if Privacy.sharesPictures, let pictures = window.1["screenshots"] as? [String], let front = pictures.first {
            sidebar["screenshots"] = ((sidebar["screenshots"] as? [String]) ?? []) + [front]
            sidebar["text"] = (sidebar["text"] as? String ?? "") + "\n\nThe app's front window follows it: the sidebar is a part of this app, so " +
                "compare the two: each item in the sidebar shows what the window shows of it (its picture or symbol, its facts, in the same order and grouping), in Apple's own look with the window's tint."
        }
        return (status, sidebar)
    }
    private static let noSidebar = "Only a Mac app has a sidebar in Chrome, and only while Apps in Chrome is on in Lamp's Settings → Experimental."

    /// What the agent hears once the person has taken the app back, and from then on when it calls use_app.
    static let tookOverNote = "The person took the app over while you were trying it, so use_app is off until their next message. " +
        "Don't try to use the app again. Finish what you were doing, and tell them in a sentence what's left for them to try."

    /// The chat's line when the person took the app back from Lamp.
    static let stoppedByYou = "Trying it: stopped by you"

    /// The app's name as the person knows it, for "Lamp is trying …".
    private static let lampName = "Lamp"

    /// A request to the open app, signed with its token (`Template.token`): only Lamp knows it, and distributed
    /// notifications reach every process, so the token itself never travels.
    private static func signal(_ project: LampProject, _ name: String, _ info: [String: String], signedAs key: String, over text: String) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(Edition.notificationPrefix + "\(name).\(project.id)"), object: nil,
            userInfo: info.merging([key: signature(over: text, token: Template.token(for: project))]) { $1 }, deliverImmediately: true)
    }

    static func signature(over text: String, token: String) -> String {
        HMAC<SHA256>.authenticationCode(for: Data(text.utf8), using: SymmetricKey(data: Data(token.utf8))).map { String(format: "%02x", $0) }.joined()
    }

    /// A line every app that writes its screen as text (`LampScreen` in LampSupport.swift) has in its binary.
    private static let screenTextMarker = "The screen as text, in reading order"

    /// `use_app` for an iPhone app: Lamp drives the simulator through the Mac's accessibility system
    /// (Simulator.Driver), then a fresh picture of the screen follows the report.
    private func useOnSimulator(_ project: LampProject, actions: [[String: Any]], json: String) async -> (Int, [String: Any]) {
        guard let running = simulatorApps[project.id], Simulator.isRunning(pid: running.pid) else {
            return (200, ["text": "The app isn't open. Call look_at_app first: it builds the app and opens it in the simulator."])
        }
        // The owner, before any wait; and one Lamp app per simulator, so actions can't land on another's screen.
        guard let owner = turns[project.id] else { return (409, ["error": "Lamp isn't working on this app right now."]) }
        if owner.tookOver { return (200, ["text": Self.tookOverNote]) }
        guard simulatorLeases[running.udid] == project.id else {
            return (200, ["text": "Another of the user's apps has taken this simulator since. Call look_at_app to open this app again."])
        }
        if let other = simulatorApps.first(where: { $0.key != project.id && $0.value.udid == running.udid && Simulator.isRunning(pid: $0.value.pid) }),
           let name = projects.first(where: { $0.id == other.key })?.name {
            return (200, ["text": "Another of the user's apps, \(name), is open on the same simulator, so the screen may not be this app's. Ask the user to quit it, or wait and try again."])
        }
        guard Simulator.Driver.isAllowed else {
            Simulator.Driver.ask()
            log(project, .status, "To try iPhone apps for you, Lamp needs to be allowed to control this computer. System Settings is open: drag Lamp into the list there, or switch it on.")
            return (200, ["text": "Lamp isn't allowed to control the simulator yet. The user has just been asked to allow it (System Settings → " +
                          "Privacy & Security → Accessibility). Say so to the user in plain words, and try again on their next request."])
        }
        let screen: Simulator.Driver.Screen
        switch await Simulator.Driver.screen(of: running.udid, owner: "\(project.id):\(running.pid)") {
        case .success(let found): screen = found
        case .failure(let trouble): return (200, ["text": trouble.message(viewer: Simulator.viewerName(), device: project.family.name)])
        }
        guard let data = json.data(using: .utf8), let decoded = try? JSONDecoder().decode([Simulator.Driver.Action].self, from: data) else {
            return (400, ["error": "use_app needs a list of actions."])
        }
        let printed = Runtime.logSize(project)
        let picture = Runtime.folder(project).appendingPathComponent("screenshot.png")
        // In plain sight, with the person's Stop, Esc, or their own tap or key in the simulator ending it.
        let trial = Handover(label: "\(Self.lampName) is trying it on \(project.family.name)", finger: true, simulator: screen.pid)
        if let window = Handover.frontWindow(of: screen.pid, containing: CGPoint(x: screen.rect.midX, y: screen.rect.midY)) {
            trial.show(window: window)
        }
        defer { trial.end() }
        let report = await Simulator.Driver.perform(decoded, on: screen, picture: picture, aim: { point, doing, press in
            await trial.aim(at: point, doing: doing, press: press)
        }, tookOver: { trial.tookOver }) { [weak self] in
            guard let self, exists(project), turns[project.id] === owner, !owner.stopped, !trial.tookOver else { return false }
            // Still this app's screen: it's running, the device is still leased to this project (a launch by
            // another project takes the lease before anything else), and no other app of Lamp's is running there.
            guard simulatorLeases[running.udid] == project.id, simulatorApps[project.id]?.pid == running.pid, Simulator.isRunning(pid: running.pid) else { return false }
            return !simulatorApps.contains { $0.key != project.id && $0.value.udid == running.udid && Simulator.isRunning(pid: $0.value.pid) }
        }
        if let data = try? JSONSerialization.data(withJSONObject: ["id": UUID().uuidString, "report": report]) {
            try? data.write(to: Runtime.folder(project).appendingPathComponent("use.json"))
        }
        // Asked again after the reads below: they take a moment, and Stop may come during them.
        func tookOver() -> Bool {
            guard trial.tookOver else { return false }
            if !owner.tookOver {
                owner.tookOver = true
                log(project, .status, Self.stoppedByYou)
            }
            return true
        }
        guard Simulator.isRunning(pid: running.pid) else {
            var text = "What happened:\n\(report)\n\nThe app quit or crashed while doing that."
            if tookOver() { text += "\n\n" + Self.tookOverNote }
            if Privacy.sharesLog, let tail = Runtime.logTail(project) { text += "\n\nLast lines it printed:\n" + tail }
            return (200, ["text": text])
        }
        var text = "What happened:\n\(report)"
        if Runtime.sourcesChanged(project) {
            text += "\n\nThis is the app as last built: it doesn't have the changes you've made to the code since. " +
                "Call look_at_app to build and open them."
        }
        // The screen in words goes wherever its picture does: what's on it is the same thing either way.
        // Asked again after the read: it takes a moment, and the setting can be turned off meanwhile.
        let words = Privacy.sharesPictures ? await Simulator.Driver.screenText(on: screen) : nil
        if Privacy.sharesPictures, let words { text += "\n\n" + words }
        if tookOver() { text += "\n\n" + Self.tookOverNote }
        text += Privacy.sharesPictures
            ? "\n\nA picture of the iPhone's screen follows. Points for the next use_app are pixels in it."
            : "\n\n" + Privacy.picturesOff
        if !Privacy.sharesLog { text += " " + Privacy.logOff }
        if Privacy.sharesLog, let lines = Runtime.log(of: project, from: printed) { text += "\n\nWhat it printed meanwhile:\n\(lines)" }
        return (200, ["text": text, "screenshots": Self.agentPictures([picture], in: project)])
    }

    /// `look_at_app` and `use_app` for agents that take tools over MCP (Claude Code and Codex): one streamable-HTTP
    /// endpoint speaking JSON-RPC, with no sessions or streams, that answers each request on the spot. Pictures go
    /// back as image content, so the model sees the windows just as pi's version shows them.
    /// `fileTools` adds `read`, `ls`, `find` and `grep` to the list, for Codex, which has none of its own;
    /// pi and Claude Code keep theirs.
    private func mcp(_ body: Data, for project: LampProject, fileTools: Bool) async -> (Int, [String: Any]) {
        guard let message = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let method = message["method"] as? String else {
            return (400, ["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Not a JSON-RPC request."]])
        }
        let id = message["id"] ?? NSNull()
        func reply(_ result: [String: Any]) -> (Int, [String: Any]) { (200, ["jsonrpc": "2.0", "id": id, "result": result]) }
        switch method {
        case "initialize":
            return reply(["protocolVersion": "2025-03-26", "capabilities": ["tools": [:]],
                          "serverInfo": ["name": "forge", "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"]])
        case "ping":
            return reply([:])
        case "tools/list":
            let tools = Self.mcpTools.filter { Memory.isOn || !Memory.tools.contains($0["name"] as? String ?? "") }
            return reply(["tools": tools + (fileTools ? FileTools.definitions : [])])
        case "tools/call":
            let params = message["params"] as? [String: Any] ?? [:]
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            if FileTools.names.contains(name) { return reply(await file(name, arguments, for: project)) }
            let (status, answer): (Int, [String: Any])
            switch name {
            case "look_at_app":
                (status, answer) = await lookCall(arguments, for: project)
            case "use_app":
                (status, answer) = await useCall(arguments, for: project)
            case "plan":
                // pi's plan reaches the chat's chapters through its event stream (Agent.parseLine); here it's set directly.
                progress[project.id]?.plan = PlanPart.parts(from: arguments)
                progress[project.id]?.tickWrittenParts()
                (status, answer) = (200, ["text": "The user can see the plan."])
            case "delete_file":
                (status, answer) = Self.deleteFile(arguments["path"] as? String ?? "", in: project)
            case "list_versions": (status, answer) = await versions("", [:], of: project)
            case "name_version": (status, answer) = await versions("/name", arguments, of: project)
            case "restore_version": (status, answer) = await versions("/restore", arguments, of: project)
            case "read_notes", "save_notes": (status, answer) = notes(name, arguments, for: project)
            case "read_skill": (status, answer) = Skills.read(arguments, from: Skills.readable(parts: parts(of: project)))
            case "make_art": (status, answer) = await makeArt(arguments, for: project)
            case "offer_setup": (status, answer) = agentOffer(arguments, for: project)
            case "make_app_for": (status, answer) = await agentKind(arguments, for: project)
            case "connectors": (status, answer) = Connectors.answer(arguments, for: project)
            case "device_integration": (status, answer) = await agentIntegration(arguments, for: project)
            case "ask", "progress", "write_wish": (status, answer) = talk(name, arguments, for: project)
            default:
                return (200, ["jsonrpc": "2.0", "id": id, "error": ["code": -32602, "message": "Unknown tool \(name)."]])
            }
            if status != 200 {
                return reply(["content": [["type": "text", "text": answer["error"] as? String ?? "Lamp couldn't do that."]], "isError": true])
            }
            var content: [[String: Any]] = [["type": "text", "text": answer["text"] as? String ?? ""]]
            for picture in Self.pictureData(answer["screenshots"] as? [String] ?? [], in: project) {
                content.append(["type": "image", "data": picture["data"] ?? "", "mimeType": picture["mimeType"] ?? "image/png"])
            }
            return reply(["content": content])
        default:
            // Notifications (initialized, cancelled) are acknowledged without a body; unknown requests get an error.
            if message["id"] == nil { return (202, [:]) }
            return (200, ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found: \(method)"]])
        }
    }

    /// One of the file tools, as an MCP tool result. Where it points is checked first, by the rule pi's file
    /// tools follow; a call that names no path works in the app's own folder.
    private func file(_ tool: String, _ arguments: [String: Any], for project: LampProject) async -> [String: Any] {
        func failed(_ message: String) -> [String: Any] { ["content": [["type": "text", "text": message]], "isError": true] }
        let given = (arguments["path"] as? String)?.nilIfEmpty ?? "."
        let (allowed, reason) = await fileAccess(tool: tool, path: given, for: project)
        guard allowed else { return failed(reason ?? "Lamp couldn't do that.") }
        let path = Privacy.resolved(given, in: project.dir)
        // Off the main thread: a search can read thousands of files.
        let result = await Task.detached { () -> Result<FileTools.Reply, FileTools.Failure> in
            do {
                return .success(try FileTools.run(tool, path: path, arguments: arguments, folder: project.dir,
                                                  hidden: { Privacy.hides($0, project: project) }))
            } catch let failure as FileTools.Failure {
                return .failure(failure)
            } catch {
                return .failure(FileTools.Failure(message: error.localizedDescription))
            }
        }.value
        switch result {
        case .failure(let failure): return failed(failure.message)
        case .success(let found):
            var content: [[String: Any]] = [["type": "text", "text": found.text]]
            if let image = found.image {
                content.append(["type": "image", "data": image.data.base64EncodedString(), "mimeType": image.mimeType])
            }
            return ["content": content]
        }
    }

    /// The agent's `delete_file`: one file inside the app's folder, never Lamp's own files, never through a
    /// link that leads out. The same rules as pi's version in lamp-tools.ts.
    static func deleteFile(_ path: String, in project: LampProject) -> (Int, [String: Any]) {
        let root = project.realDir
        let target = URL(fileURLWithPath: path, relativeTo: project.dir).standardizedFileURL
        let relative = target.path.hasPrefix(root.path + "/") || target.path.hasPrefix(project.dir.path + "/")
            ? String(target.path.dropFirst((target.path.hasPrefix(root.path + "/") ? root.path : project.dir.path).count + 1)) : ""
        guard !relative.isEmpty else { return (400, ["error": "Only files inside the app's folder can be deleted."]) }
        // Compared without regard to case: the Mac's usual file system treats "package.swift" as the same file.
        let protected = [".lamp", ".git", ".build", "build", ".gitignore", "Package.swift", "build.sh", "Sources/LampSupport.swift", Template.sceneSupportPath,
                         Template.widgetFolder + "/" + Template.widgetSupportFile, Template.shareFolder + "/" + Template.shareSupportFile] + Template.watchSupportPaths
        let lowered = relative.lowercased()
        if protected.contains(where: { lowered == $0.lowercased() || lowered.hasPrefix($0.lowercased() + "/") }) 
            // An Android app's building blocks are Lamp's while it is one; made into a Swift app, the agent clears app/ away.
            || (project.platform.target.recipe.language == .kotlin && Template.isAndroidSupport(relative))
            // A TV's or a device app's building blocks are Lamp's too (`DeviceSupport`).
            || DeviceSupport.isSupport(relative, in: project) {
            return (400, ["error": "\(relative) belongs to Lamp and can't be deleted."])
        }
        let fm = FileManager.default
        guard let attributes = try? fm.attributesOfItem(atPath: target.path) else { return (404, ["error": "There's no file at \(relative)."]) }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            return (400, ["error": "\(relative) isn't a file. Only single files can be deleted."])
        }
        // A folder on the way that is really a link could lead outside the app's folder.
        let folder = target.deletingLastPathComponent().resolvingSymlinksInPath().path
        guard folder == root.path || folder.hasPrefix(root.path + "/") else {
            return (400, ["error": "Only files inside the app's folder can be deleted."])
        }
        do { try fm.removeItem(at: target) } catch { return (500, ["error": "Couldn't delete \(relative): \(error.localizedDescription)"]) }
        return (200, ["text": "Deleted \(relative)."])
    }

    /// `ask`, `progress` and `write_wish`, for every engine: pi's extension posts them to `/agent/talk`, Claude
    /// Code and Codex call them over MCP.
    func talk(_ tool: String, _ arguments: [String: Any], for project: LampProject) -> (Int, [String: Any]) {
        guard let turn = turns[project.id] else { return (409, ["error": "Lamp isn't working on this app right now."]) }
        switch tool {
        case "ask":
            switch Talk.ask(from: arguments) {
            case .failure(let trouble): return (400, ["error": trouble.text])
            case .success(let ask):
                // Asked again before the person answered (the agent thought better of its questions): the
                // card that's showing stays as it is. A card that changed under the pointer would be worse
                // than a question worded the first way.
                // The same once the first was answered in words while this turn was still ending: the
                // agent hasn't had that answer yet, and a new card would be asking over it.
                if turn.asked || Talk.open(in: logs[project.id] ?? []) != nil { return (200, ["text": Talk.alreadyAsked]) }
                logs[project.id, default: []].append(chaptered(LogLine(kind: .ask, text: ask.text, ask: ask, at: Date()), in: project))
                closeSteps(project)
                // A new app's bar says it waits for an answer in the same moment the questions arrive, not when
                // the turn ends a little later.
                if progress[project.id]?.newApp == true { progress[project.id]?.asking = true }
                turn.asked = true
                away.questionAsked(project.id)   // no carry-on of Lamp's over a card waiting for its answer
                saveChat(project)
                return (200, ["text": Talk.asked])
            }
        case "progress":
            switch Talk.progress(from: arguments, after: logs[project.id] ?? []) {
            case .failure(let trouble): return (400, ["error": trouble.text])
            case .success(nil): return (200, ["text": Talk.saidAlready])
            case .success(let text?):
                logs[project.id, default: []].append(chaptered(LogLine(kind: .progress, text: text, at: Date()), in: project))
                closeSteps(project)
                // A new phase: the file work after it isn't what the last command or heading was for.
                turns[project.id]?.naming = nil
                saveChat(project)
                return (200, ["text": Talk.told])
            }
        case "write_wish":
            // Only for a wish being found: one the person told is already theirs, and a box they're typing in
            // isn't the agent's to fill.
            guard project.finding else {
                return (400, ["error": "`write_wish` is only for helping someone find a wish. Build what they asked for."])
            }
            guard let wish = Wish.tidy(arguments["wish"] as? String), Talk.words(in: wish) <= Talk.Words.wish else {
                return (400, ["error": "Give the wish in `wish`, \(Talk.Words.wish) words at most."])
            }
            writeIn(wish, for: project)
            return (200, ["text": "The wish is in their message box, for them to change and send. End your reply now, with one short sentence at most."])
        default:
            return (400, ["error": "Unknown tool \(tool)."])
        }
    }

    /// A card's answers, chosen by clicking: noted on the card, then sent as the person's message.
    func answer(_ line: LogLine, with answers: [String], in project: LampProject) {
        guard var lines = logs[project.id], let ask = Talk.give(answers, to: line.id, in: &lines) else { return }
        logs[project.id] = lines
        saveChat(project)
        send(Talk.message(for: ask, answers: answers), answering: line.id, to: project)
    }

    /// What an app is after its files were put back to a version: its kind (`followRestoredKind`), and for a wish
    /// its other parts, which come and go with their files. One the version doesn't have is quit and forgotten
    /// (`forget`); one it brings back is taken in again, with its toolbar menu and its `part` for the tools.
    @discardableResult
    func followRestored(_ project: LampProject) async -> LampProject {
        // The app in the wish's own folder as it was before the restore, which is what's open and installed.
        let before = current(project) ?? project
        let wish = followRestoredKind(project)
        guard !wish.isPart else { return wish }
        // A version whose apps are all in folders of their own takes the app in the wish's own folder away, as
        // `make_app_for` does: quit as any app is, then forgotten, whether or not the person kept it open (its files are
        // gone, so it can't be built again). Lamp knew it as an app until now by its installed copy (`stamps`).
        if !wish.holdsApp, stamps[wish.id] != nil {
            let closed = await quit(before, for: turns[wish.id])
            await forget(before)
            if !closed { log(wish, .status, "T\(Parts.name(of: before.platform).dropFirst()) is still open. It's no longer one of the wish's apps.") }
        }
        guard !Parts.match(parts(of: wish), filesOf: wish.dir) else { return wish }
        let found = Parts.folders(in: wish.dir)
        var keptOpen: [LampProject] = []
        for part in parts(of: wish) where !found.contains(part.dir.lastPathComponent) {
            // Forgotten only once it's closed: one the person kept open (unsaved work) stays listed, with its menu to
            // quit it from (`reload`).
            if await quit(part, for: turns[wish.id]) { await forget(part) } else { keptOpen.append(part) }
        }
        reload()
        for part in keptOpen { log(wish, .status, "T\(Parts.name(of: part.platform).dropFirst()) is still open. It goes once it's closed.") }
        return current(wish) ?? wish
    }

    /// After a restore, the app in Lamp's list is what the restored version was made for, as `Versions.restoreFiles`
    /// wrote it to meta.json: an Undo of `make_app_for` puts the kind back with the code.
    /// The app as it is after the restore, for whatever builds it next.
    @discardableResult
    private func followRestoredKind(_ project: LampProject) -> LampProject {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return project }
        let kind = Template.platform(fromPackageIn: project.dir)
        // A device app's code also says which device it's for: restoring between two such kinds changes that too.
        var integration = kind?.target.recipe.integration(project.dir)
        // A game's Xbox is one of its places, which meta.json keeps and no version holds: it stays across a restore.
        if let kind, kind.addsPlaces { var placed = projects[index]; placed.platform = kind; integration = GameKit.integration(for: placed) }
        // The wish's list is the one the restore wrote with the version's files (`Versions.restoreFiles`), not the one
        // Lamp held before it.
        if !projects[index].isPart, let saved = Self.readWish(at: project.dir) { projects[index].apps = saved.apps }
        if let kind, projects[index].platform != kind || projects[index].integration != integration {
            let was = projects[index].platform
            projects[index].platform = kind
            projects[index].integration = integration
            if !kind.reaches(.ios) { projects[index].device = nil }
            if !projects[index].apps.contains(where: { $0.kind == kind }) {
                projects[index].apps = Parts.setting(WishApp(kind: kind), in: projects[index].apps.filter { Parts.group($0.kind) != Parts.group(was) })
            }
            try? Template.saveMeta(projects[index])
            refreshOpenApps()
        }
        return projects[index]
    }

    /// `make_app_for`: the person asked for the wish on other devices, and the agent asks Lamp to make it so. The wish
    /// becomes the apps listed, one per family, every app of it treated alike (`Parts.plan`): one whose family is listed
    /// stays, its code kept, changed in place only inside its family (an iPhone app that's to be for the Mac too); a
    /// family it has no app of is added in a folder of its own; one whose family is left out is taken away, the app in
    /// the wish's own folder as much as any other. So "tv" added to a Mac wish keeps the Mac app and adds the TV app
    /// beside it, and "tv" alone replaces the Mac app with a TV app, the wish keeping its name, chat and history. What
    /// this Mac can't build yet holds back only that app: the rest are made, and it waits on the wish's list with its
    /// setup. An app is never taken away while nothing would be left: it stays until what replaces it is made.
    private func agentKind(_ arguments: [String: Any], for project: LampProject) async -> (Int, [String: Any]) {
        let devices = Set((arguments["devices"] as? [String] ?? []).map { $0.trimmed.lowercased() })
        let places = Set((arguments["places"] as? [String] ?? []).map { $0.trimmed.lowercased() })
        guard var wish = current(project), !wish.isPart else { return (404, ["error": "Lamp can't find the wish."]) }
        // `devices` are the wish's apps, every one; a game's or a screen's places are given apart, in `places`.
        guard let asked = Parts.asked(devices, places: places) else {
            if Parts.asked(devices) != nil {
                return (400, ["error": "`places` is where the wish's game is played (\"iphone\" or \"ipad\", \"android\", \"xbox-one\") or its screen is " +
                              "shown (\"iphone\" or \"ipad\", \"tv\", \"xbox-one\"), beside the Mac, and only with \"game\" or \"screen\" in `devices`."])
            }
            let others = DeviceApps.kinds().map(\.id)
            return (400, ["error": "`devices` must list one or more of \(Targets.toolWords)"
                          + (others.isEmpty ? "." : ", or one of \(others.joined(separator: ", ")) alone.")])
        }
        let kinds = asked.kinds
        // The words each app is made from: for a game or a screen its places, for every other app the list.
        let words = { (kind: Platform) in kind.addsPlaces ? (asked.places[kind] ?? []).union([kind.rawValue]) : devices }
        let placesOf = { (kind: Platform) in kind.addsPlaces ? GameKit.places(for: words(kind), of: kind) : nil }
        var said: [String] = []
        // A wish with nothing made yet (still to be told what it's for, or held for its device) is made as a new wish
        // is: its first app in its own folder, the first of its kinds this Mac can build now, so answered "TV and iPhone"
        // on a Mac without Xcode it's made as the TV app and the iPhone app waits with its setup.
        if !wish.scaffolded {
            guard let first = await firstKind(among: kinds, integration: devices.first) else { return (400, ["error": "`devices` lists nothing Lamp can make."]) }
            let (status, answer) = await changeKind(arguments, devices: words(first), kind: first, for: wish)
            guard status == 200, let text = answer["text"] as? String, !text.hasPrefix("Not yet"), !text.hasPrefix("Nothing changed"),
                  let made = current(wish) else { return (status, answer) }
            wish = made
            said.append(text)
        }
        let apps = apps(of: wish)
        let plan = Parts.plan(kinds, for: apps)
        // The wish should have these from now on; what each one that can't be made yet needs is kept as it's found.
        setApps(wish, kinds.map { WishApp(kind: $0, places: placesOf($0)) })
        // Each app that stays as another kind of its family is changed in place.
        for app in apps {
            guard let kind = plan.keep[app.id] else { continue }
            // A game stays a game, a screen a screen: what's given for it are its places.
            if kind == app.platform, kind.addsPlaces {
                let (status, answer) = await kindPlaces(words(kind), for: app)
                let text = answer["text"] as? String ?? answer["error"] as? String ?? ""
                if status == 200, text.hasPrefix("It's already") { continue }
                said.append(apps.count > 1 || !plan.add.isEmpty ? "For \(Parts.name(of: kind)) in \(folderWords(app)): " + text : text)
                continue
            }
            let (status, answer) = await changeKind(arguments, devices: words(kind), kind: kind, for: app)
            let text = answer["text"] as? String ?? answer["error"] as? String ?? ""
            if status == 200, Parts.saysNothingNew(text) { continue }
            said.append(app.isPart || !parts(of: wish).isEmpty || !plan.add.isEmpty ? "For \(Parts.name(of: app.platform)) in \(folderWords(app)): " + text : text)
        }
        // Each family the wish has no app of yet is added in its own folder.
        var added = 0
        for kind in plan.add {
            let (part, problem, setup) = await addPart(kind, to: wish)
            guard let part else {
                recordNeeds(problem ?? "Lamp couldn't make it.", for: kind, of: wish, setup: setup)
                said.append("Not yet for \(Parts.name(of: kind)): \(problem ?? "Lamp couldn't make it.") Lamp keeps it on the wish's list and makes it " +
                            "once that's done. Build the rest; what it was to do may go another way meanwhile if one works now, your choice. " +
                            "Tell the person in a sentence.")
                continue
            }
            added += 1
            log(wish, .status, "\(wish.name) has \(Parts.name(of: kind)) now.")
            // A game or a screen is at home on the Mac, and goes wherever else it was given, with what that allows.
            if kind.addsPlaces, let places = placesOf(kind) {
                let placed = await setPlaces(part, places)
                if !placed.hasPrefix("It's already"), current(part) != nil { said.append(placed) }
                if let now = current(part) { said.append(kind == .screen ? Agent.Rules.screenPlaces(now) : Agent.Rules.gamePlaces(now)) }
            }
            said.append("Done: the wish has \(Parts.name(of: kind)) now, in \(part.dir.lastPathComponent)/, with its scaffold written. Build it in this " +
                        "request, made to work with the rest. `look_at_app` and `use_app` reach it with `part` \"\(Parts.word(for: kind))\". " +
                        "Its rules, for the files in \(part.dir.lastPathComponent)/:\n\n" + Parts.pack(for: kind))
        }
        // Each app left out goes, once the wish has another: one left with nothing beside it stays until what replaces it is made.
        let stays = Parts.staying(of: apps.map(\.id).filter(plan.remove.contains), survivors: apps.count - plan.remove.count + added)
        for app in apps where plan.remove.contains(app.id) {
            guard let app = current(app) else { continue }
            let name = Parts.name(of: app.platform)
            guard !stays.contains(app.id) else {
                setApps(wish, Parts.setting(WishApp(kind: app.platform), in: current(wish)?.apps ?? []))
                said.append("\(name.prefix(1).uppercased() + name.dropFirst()) stays for now: it's the only app the wish has until the rest can be made, " +
                            "and Lamp takes it away then if you ask again with make_app_for. Tell the person in a sentence.")
                continue
            }
            let gone = await takeAway(app)
            if gone { log(wish, .status, "\(wish.name) no longer has \(name).") }
            // The rules this conversation began with were that app's, when it was the one in the wish's own folder.
            let rules = app.isPart ? "" : " What your instructions said about it no longer applies: every app of the wish is in a folder of its own now, with its own rules."
            said.append(gone ? "Lamp took \(name) away, as asked; the wish's versions still have it." + rules
                        : "\(name) is still there: the person kept it open. Tell them it has to close first.")
        }
        guard !said.isEmpty else { return (200, ["text": "It's already made for these devices."]) }
        return (200, ["text": said.joined(separator: "\n\n")])
    }

    /// Where an app of a wish is, for what Lamp tells the agent: its folder, or the wish's own.
    private func folderWords(_ app: LampProject) -> String { app.isPart ? app.dir.lastPathComponent + "/" : "the wish's own folder" }

    /// `make_app_for` on a game or a screen: the places it's played or shown from now on, the same code everywhere, with
    /// what each place asks of it (for a game, the budget of the weakest, which the request's device line carries from now on).
    private func kindPlaces(_ devices: Set<String>, for game: LampProject) async -> (Int, [String: Any]) {
        // Only the places it can be on reach here (`Parts.asked`).
        let words = devices.subtracting(["game", "screen"])
        let kind = game.platform
        if kind == .screen {
            let said = await setPlaces(game, GameKit.places(for: words, of: kind), family: words.contains("ipad") && !words.contains("iphone") ? .ipad : nil)
            guard let now = current(game) else { return (404, ["error": "Lamp can't find the screen."]) }
            return (200, ["text": said + " It's the same page everywhere, laid out at 1920x1080 and scaled to each screen, so nothing in Web/ changes for it. " +
                          Agent.Rules.screenPlaces(now) + " Try it as before; `look_at_app` with `on_device` opens it where Try On points now."])
        }
        // "ipad" alone is a wish to see it on an iPad: the simulator it opens on is one.
        let family: DeviceFamily? = words.contains("ipad") && !words.contains("iphone") ? .ipad : nil
        let said = await setPlaces(game, GameKit.places(for: words), family: family)
        guard let now = current(game) else { return (404, ["error": "Lamp can't find the game."]) }
        return (200, ["text": said + " It's the same game everywhere: the kit gives each place its screen, controls and sound, so nothing in Game/ " +
                      "changes for it. " + Agent.Rules.gamePlaces(now) + " Try it as before; `look_at_app` with `on_device` opens it where Try On points now."])
    }

    /// One app of a wish made the kind `make_app_for` asked, inside its family (`convert`), and what to do about a watch
    /// app, which is the iPhone app's wherever it is.
    private func changeKind(_ arguments: [String: Any], devices: Set<String>, kind: Platform, for project: LampProject) async -> (Int, [String: Any]) {
        // Asked before the change: once an app isn't for the iPhone, its Watch/ no longer counts as a watch app.
        let hadWatch = current(project).map(Template.hasWatch) ?? false
        let (status, answer) = await convert(project, to: kind, integration: kind.reaches(.device) && !kind.addsPlaces ? devices.first : nil)
        guard status == 200, let text = answer["text"] as? String, !text.hasPrefix("Not yet"), !text.hasPrefix("Nothing changed"),
              let now = current(project) else { return (status, answer) }
        // A game made now is played on the places listed beside the Mac.
        if kind.addsPlaces {
            let said = await setPlaces(now, GameKit.places(for: devices, of: kind))
            return (200, ["text": text + (said.hasPrefix("It's already") ? "" : "\n\n" + said)])
        }
        // The watch app is code in Watch/, the agent's to write or take away: Lamp says which, and names the skill
        // that says how, which the prompt this turn began with may not offer.
        let watch = devices.contains("watch") && kind.reaches(.ios)
        guard kind.reaches(.ios) || hadWatch else { return (status, answer) }
        let folder = now.isPart ? now.dir.lastPathComponent + "/Watch/" : "Watch/"
        if watch, !Template.hasWatch(now) {
            return (200, ["text": text + "\n\nThen add its Apple Watch app in \(folder): open the apple-watch skill with `read_skill` first, and follow it."])
        }
        if !watch, hadWatch || Template.hasWatch(now) {
            return (200, ["text": text + "\n\nThen take its Apple Watch app away: delete the files in \(folder) with delete_file."])
        }
        return (200, answer)
    }

    /// Makes an app for other devices: a Mac app for the iPhone too, say. The kind is the app's (meta.json), and
    /// Lamp's own files follow it (`Template.writeOwnedFiles`); the app's code is the agent's to adapt, so the
    /// answer carries the rules for the new kind, which stay in the conversation for later requests. The app's
    /// data stays put: on a Mac it's kept under the app's plain id whatever it's signed as (`LampStore.folder`),
    /// and its settings (UserDefaults, kept under the signed id) are copied across when that id changes. Every
    /// copy is quit first, since the next build is signed as something else, which macOS sees as a new app:
    /// permissions given to the old one are asked for again, once.
    func convert(_ project: LampProject, to kind: Platform, integration: String? = nil) async -> (Int, [String: Any]) {
        guard let current = current(project), let index = projects.firstIndex(where: { $0.id == project.id }) else {
            return (404, ["error": "Lamp can't find the app."])
        }
        let words = kind.target.identity.made(integration.flatMap(Integrations.integration)?.name, "the person's")
        guard kind != current.platform || (kind.reaches(.device) && integration != current.integration) || current.undecided != nil
        else { return (200, ["text": "It's already made for \(words)."]) }
        if let problem = await kind.target.setup.notReady(integration, nil) {
            return (200, ["text": "Not yet: \(problem) Nothing changed. If what the person wants can be made well another way that needs none of it " +
                          "(other devices with make_app_for, or another way of doing the same thing), you may choose that now and tell them in a sentence " +
                          "what you made and what the setup would add; otherwise tell them in a sentence, and that you'll make the change when they ask again once it's done."])
        }
        // Every copy closes first, the turn's own answer included: one kept open (the person kept unsaved work)
        // would go on as an app Lamp no longer knows by its id.
        guard await quit(current, for: turns[project.id]) else {
            return (200, ["text": "Nothing changed: the person kept \(current.name) open on this Mac, where it asked about unsaved work. " +
                          "Tell them it has to close first, and that you'll make the change when they ask again."])
        }
        var changed = current
        changed.platform = kind
        changed.integration = kind.reaches(.device) && !kind.addsPlaces ? integration : nil
        changed.places = nil
        // A wish held for its device has nothing written yet: given its kind, it's made now, scaffold and first version,
        // so the agent builds on it in this request as it would on any new wish.
        let undecided = current.undecided != nil
        let fresh = (current.waitsForDevice || undecided) && !current.scaffolded
        changed.undecided = nil
        changed.waitsForDevice = false
        // Its conversation began with no kind's rules: the next request starts one with them (`finish`).
        if undecided { changed.decided = true }
        // The app is this kind now in the wish's list, in place of what it was.
        changed.apps = Parts.setting(WishApp(kind: kind), in: current.apps.filter { Parts.group($0.kind) != Parts.group(current.platform) })
        // Where it opens next: where it's newly made for, so the person sees the change.
        changed.chosen = current.platform == .mac && !undecided ? .ios : .mac
        if !kind.reaches(.ios) { changed.device = nil }
        do { try Template.saveMeta(changed) } catch { return (500, ["error": "Lamp couldn't save the change: \(error.localizedDescription)"]) }
        projects[index] = changed
        if fresh {
            guard let made = await materialize(changed) else {
                return (500, ["error": "Lamp couldn't set up the app for \(words). Tell the person in a sentence; it says why in the chat."])
            }
            changed = made
        }
        if changed.scaffolded {
            do { try Template.writeOwnedFiles(for: changed) } catch {
                return (500, ["error": "Lamp couldn't write the build files for it: \(error.localizedDescription)"])
            }
        }
        // The Mac copy's data, from an app for both built before its data had a fixed place (`LampStore.folder`):
        // moved there now, while Lamp still knows the id it was kept under.
        if current.hasMac {
            let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            let fixed = support.appendingPathComponent(Edition.appBundlePrefix + current.id)
            let signed = support.appendingPathComponent(current.bundleID)
            if signed != fixed, FileManager.default.fileExists(atPath: signed.path), !FileManager.default.fileExists(atPath: fixed.path) {
                try? FileManager.default.moveItem(at: signed, to: fixed)
            }
        }
        if current.hasMac, kind.reaches(.mac), current.bundleID != changed.bundleID {
            _ = await Shell.run("/usr/bin/defaults export \"$LAMP_OLD\" - | /usr/bin/defaults import \"$LAMP_NEW\" -", cwd: changed.dir,
                                env: ["LAMP_OLD": current.bundleID, "LAMP_NEW": changed.bundleID]) { _ in }
        }
        syncLocalNetwork()
        log(changed, .status, "\(changed.name) is made for \(words) now.")
        let rules = kind.target.guidance.changeRules(changed)
        // To or from another code the app is written over again in that language: the scaffold of the new kind is put
        // in beside what's there, for the agent to move the app into. A device app is the device's own language, so
        // going to one always is.
        let (before, after) = (current.platform.target, kind.target)
        if before.recipe.language != after.recipe.language || after.recipe.refills, current.scaffolded {
            try? Template.fill(changed)
        }
        // What marks a folder as the old kind (a version restored later reads its kind off it) goes with the kind,
        // before the next version is saved.
        if kind != current.platform, let marker = before.recipe.marker { AppFolder.remove(changed.dir.appendingPathComponent(marker), in: changed.dir) }
        if current.platform == .game, kind != .game { GameKit.remove(from: changed) }
        if current.platform == .screen, kind != .screen { ScreenKit.remove(from: changed) }
        let (old, new) = (before.recipe.language, after.recipe.language)
        let rewrite = fresh || old == new ? "" : new.rewrite(old.code, old.leftover)
        if undecided {
            return (200, ["text": "Done: \(changed.name) is made for \(words), and its scaffold is written. These are your rules from now " +
                          "on, in place of the ones you began with; build the wish now, in this request:\n\n" + Agent.kindPrompt(for: changed)])
        }
        return (200, ["text": "Done: \(changed.name) is made for \(words) from now on, and that replaces what your instructions said " +
                      "about what it runs on. Adapt its code now, in this request, and build it before you finish. " + rewrite +
                      (kind.reaches(.mac) && kind.reaches(.ios) && !kind.target.hostedByLamp ? "Put what only one platform has under `#if os(macOS)` or `#if os(iOS)`. " : "") +
                      "What applies now:\n" + rules.replacingOccurrences(of: "{{DEVICE}}", with: changed.family.name)])
    }

    /// Whether one of a wish's apps goes on an iPhone, so what it does away from this Mac can be set up.
    nonisolated static func hasPhoneApp(_ wish: LampProject, parts: [LampProject]) -> Bool { ([wish].filter(\.holdsApp) + parts).contains { $0.hasIOS } }

    /// `offer_setup`: the agent asks Lamp to offer the person a way to set up a capability, with its reason.
    private func agentOffer(_ arguments: [String: Any], for project: LampProject) -> (Int, [String: Any]) {
        guard let capability = (arguments["capability"] as? String).flatMap(Capability.init(rawValue:)) else {
            return (400, ["error": "`capability` must be text, decisions, pictures or browser."])
        }
        if capability == .browser && (!BrowserBridge.enabled || !project.hasMac) {
            return (400, ["error": "A sidebar in Chrome is only for a Mac app, while Apps in Chrome is on in Lamp's Settings → Experimental."])
        }
        let away = arguments["away"] as? Bool == true
        // Any app of the wish may be the one on the phone: a TV app's iPhone app is a part, not the app at its root.
        guard !away || (Self.hasPhoneApp(project, parts: parts(of: project)) && capability != .browser) else {
            return (400, ["error": "`away` is only for iPhone apps."])
        }
        let why = (arguments["why"] as? String)?.trimmed ?? ""
        guard !why.isEmpty else { return (400, ["error": "Say in `why` what the person would get."]) }
        return (200, ["text": offerSetup(project, SetupOffer(capability: capability, away: away ? true : nil), because: why, fromAgent: true)])
    }

    /// `read_notes` and `save_notes`, for every engine. A save that changed what the notes say leaves a
    /// receipt in the chat (`NoteReceipt`): what Lamp keeps about someone is shown to them when it's kept.
    private func notes(_ tool: String, _ arguments: [String: Any], for project: LampProject) -> (Int, [String: Any]) {
        let place = tool == "save_notes" ? Memory.place(arguments, project) : nil
        let before = place.map(Memory.read)
        let (status, answer) = Memory.call(tool, arguments, for: project)
        guard status == 200, let place, let before else { return (status, answer) }
        let receipt = NoteReceipt(about: place.name, before: before, after: Memory.read(place))
        guard !receipt.isEmpty else { return (status, answer) }
        log(project, .noted, "", noted: receipt)
        return (200, ["text": "Saved. Lamp showed the person what you noted, in the chat: don't repeat it in your reply."])
    }

    /// Undo on a receipt: takes that save back out of the notes, and has the agent told so it isn't noted
    /// again. Returns what went wrong, in words for the person.
    func undoNote(_ line: UUID, in project: LampProject) -> String? {
        guard let index = logs[project.id]?.firstIndex(where: { $0.id == line }),
              var receipt = logs[project.id]?[index].noted, receipt.undone != true else { return nil }
        let place: Memory.Place = receipt.about == "you" ? .you : .app(project)
        do {
            // What was taken back on other receipts stays out: this save may have replaced one of those lines.
            // The person's notes are shared by every app, so any chat may hold such a receipt.
            let chats = receipt.about == "you" ? Array(logs.values) : [logs[project.id] ?? []]
            let rejected = chats.joined().compactMap(\.noted).filter { $0.undone == true && $0.about == receipt.about }.flatMap(\.added)
            try Memory.save(receipt.takenBack(from: Memory.read(place), rejected: Set(rejected)), in: place)
        } catch {
            return "Lamp couldn't take that back. Try again, or change it in Settings."
        }
        Memory.tookBack(receipt.added, from: place, in: project)
        receipt.undone = true
        logs[project.id]?[index].noted = receipt
        saveChat(project)
        return nil
    }

    /// `make_art`: a picture for the app to show, painted in its icon's style and saved in Assets/, the folder
    /// that's bundled with the app. The reply shows it to the agent, which judges it as it would a look.
    private func makeArt(_ arguments: [String: Any], for project: LampProject) async -> (Int, [String: Any]) {
        // Finding what paints and painting both wait, long enough to outlast the turn: the turn that asked is
        // taken now, and a picture is dropped unless that same turn is still going when it arrives, so it can't
        // land in a later request, an earlier version, or a deleted app.
        guard let owner = turns[project.id] else { return (409, ["error": "Lamp isn't working on this app right now."]) }
        func stillAsked() -> Bool { exists(project) && turns[project.id] === owner && !owner.stopped }
        let subject = (arguments["subject"] as? String)?.trimmed ?? ""
        guard !subject.isEmpty else { return (400, ["error": "Say in `subject` what the picture shows."]) }
        // Into the Assets/ of the app it's for, which `part` names as it does for a look.
        let (app, refusal) = target(arguments, in: project)
        guard let app else { return (400, ["error": refusal ?? "No such app."]) }
        let folder = app.isPart ? app.dir.lastPathComponent + "/Assets/" : "Assets/"
        var name = (arguments["name"] as? String)?.trimmed ?? ""
        if !name.lowercased().hasSuffix(".png") { name += ".png" }
        guard name.count > 4, !name.contains("/"), !name.hasPrefix(".") else {
            return (400, ["error": "`name` is a file name such as glass.png, without folders."])
        }
        let scene = arguments["scene"] as? Bool == true
        let aspect = arguments["aspect"] as? String ?? "1:1"
        guard ["1:1", "4:3", "3:4", "16:9", "9:16"].contains(aspect) else {
            return (400, ["error": "`aspect` is one of 1:1, 4:3, 3:4, 16:9 or 9:16."])
        }
        let unavailable = "Nothing on this Mac can make pictures yet, so none was made. Use SF Symbols in the app's palette " +
            "instead. Lamp has offered the user a way to set pictures up; don't mention it yourself."
        let because = "Nothing on this Mac can draw pictures yet. Set up one of the ways below and Lamp will paint \(project.name) its pictures and a proper icon."
        let route = await AppAI.imageRoute()
        guard stillAsked() else { return (409, ["error": "The request was stopped, so no picture was made."]) }
        guard route != nil else {
            offerSetup(project, SetupOffer(capability: .pictures), because: because)
            return (200, ["text": unavailable])
        }
        do {
            let (png, cost) = try await Icons.generateAppArt(subject: subject, tint: Icons.load(project)?.tint,
                                                             scene: scene, aspect: aspect)
            recordArt(project, cost: cost)
            owner.artCost += cost
            guard stillAsked() else {
                return (409, ["error": "The request was stopped before the picture was ready, so it wasn't saved."])
            }
            guard let url = artDestination(name, in: app) else {
                return (400, ["error": "\(folder)\(name) can't be written: Assets or the file leads outside the app's folder."])
            }
            try png.write(to: url, options: .atomic)
            let size = NSBitmapImageRep(data: png).map { " (\($0.pixelsWide)×\($0.pixelsHigh) pixels)" } ?? ""
            let around = scene ? "" : ", transparent around the object"
            return (200, ["text": "Saved \(folder)\(name)\(size)\(around). Show it with LampAssets.image(\"\(name)\"). It follows.",
                          "screenshots": [Previews.forAgent(url, in: project)?.path].compactMap { $0 }])
        } catch let failure as AppAI.Failure where failure.needs == .pictures {
            offerSetup(project, SetupOffer(capability: .pictures), because: because)
            return (200, ["text": unavailable])
        } catch {
            if let failure = error as? AppAI.Failure, failure.cost > 0 {   // billed even though it failed
                recordArt(project, cost: failure.cost)
                owner.artCost += failure.cost
            }
            return (502, ["error": "Couldn't make the picture: \(error.localizedDescription)"])
        }
    }

    /// Where `make_art` may write a picture: Assets/ in the app's own folder, made if needed. This runs in Lamp,
    /// outside the agent's sandbox and file checks, so neither the folder nor an existing file may be a link
    /// that leads anywhere else; nil when either does.
    private func artDestination(_ name: String, in project: LampProject) -> URL? {
        let fm = FileManager.default
        let root = project.realDir
        let folder = project.dir.appendingPathComponent("Assets")
        if let type = (try? fm.attributesOfItem(atPath: folder.path))?[.type] as? FileAttributeType {
            guard type == .typeDirectory else { return nil }
        } else if (try? fm.createDirectory(at: folder, withIntermediateDirectories: false)) == nil {
            return nil
        }
        let resolved = folder.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.path == root.appendingPathComponent("Assets").path else { return nil }
        let url = resolved.appendingPathComponent(name)
        if let type = (try? fm.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType, type != .typeRegular { return nil }
        return url
    }

    /// The tools every engine gets: Resources/lamp-tools.json, the one place their names, descriptions and schemas live,
    /// with what only Lamp's code knows filled in (`{{DEVICES}}`, each kind's own: `Targets.toolDevices`). That's done
    /// once, to the file's own text: the MCP endpoint serves it, and pi's extension (lamp-tools.ts) reads it from
    /// `toolsFile`, so both get the same rendering.
    nonisolated static let toolsJSON: Data = {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("lamp-tools.json"), let data = try? Data(contentsOf: url),
              let quoted = try? JSONSerialization.data(withJSONObject: [Targets.toolDevices], options: .withoutEscapingSlashes) else {
            assertionFailure("lamp-tools.json is missing from the app")
            return Data("[]".utf8)
        }
        let devices = String(decoding: quoted.dropFirst(2).dropLast(2), as: UTF8.self)
        return Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "{{DEVICES}}", with: devices).utf8)
    }()
    // `label` is pi's: MCP clients see name, description and inputSchema.
    static let mcpTools: [[String: Any]] = ((try? JSONSerialization.jsonObject(with: toolsJSON)) as? [[String: Any]] ?? [])
        .map { tool in tool.filter { $0.key != "label" } }
    /// `toolsJSON` as pi's extension reads it, written once per launch to Lamp's own pi folder.
    nonisolated static let toolsFile: URL? = {
        let url = URL(fileURLWithPath: Agent.configDir).appendingPathComponent("lamp-tools.json")
        guard (try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)) != nil,
              (try? toolsJSON.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }()

    /// Whether the installed app's binary contains a string, which says which Lamp features it was built with.
    static func binary(of project: LampProject, contains marker: String) -> Bool {
        let binary = project.installedURL.appendingPathComponent("Contents/MacOS/\(project.exe)")
        guard let data = try? Data(contentsOf: binary, options: .alwaysMapped) else { return false }
        return data.range(of: Data(marker.utf8)) != nil
    }

    /// Whether the installed app was built with LampWindows (its binary contains the message name).
    /// One distributed notification, awaited with a time limit.
    private final class Acknowledgement: @unchecked Sendable {
        private let observer: NSObjectProtocol

        init(name: String, object: String) {
            let lock = NSLock()
            var flag = false
            observer = DistributedNotificationCenter.default().addObserver(forName: Notification.Name(name), object: object, queue: nil) { _ in
                lock.lock(); flag = true; lock.unlock()
            }
            check = { lock.lock(); defer { lock.unlock() }; return flag }
        }
        private let check: () -> Bool

        deinit { DistributedNotificationCenter.default().removeObserver(observer) }

        func wait(seconds: Double) async -> Bool {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                if check() { return true }
                try? await Task.sleep(for: .milliseconds(100))
            }
            return check()
        }
    }

    /// Whether a process has a normal window on screen (window list metadata needs no permission).
    private static func hasWindow(_ pid: pid_t) -> Bool {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
    }

    /// Rebuilds the app from its code, reinstalls it and relaunches it.
    /// Rebuilds an app made by an older Lamp and opens it. False if it didn't build, leaving the old one in place.
    private func updateForThisForge(_ project: LampProject, because reason: String? = nil) async -> Bool {
        guard begin(project) != nil else { return false }
        defer { finish(project) }
        log(project, .status, reason ?? "Updating \(project.name) for this version of Lamp…")
        guard await build(project) == nil else {
            log(project, .status, "Couldn't update \(project.name), so it opened as it was")
            return false
        }
        await installReportingCrash(project)
        return true
    }

    // MARK: - Starters

    /// The wishes Lamp comes with (`Starters`), copied onto the desk on the first launch. Saved as their first
    /// version and built afterwards (`prepareStarters`), once Apple's tools are there: git is one of them.
    private func installStarters() {
        guard !UserDefaults.standard.bool(forKey: Starters.installedKey) else { return }
        UserDefaults.standard.set(true, forKey: Starters.installedKey)
        let made = Starters.bundled.compactMap(add(starter:))
        guard !made.isEmpty else { return }
        reload()
        startersInstall = Task {
            // Drawn only for a starter shipped without its icon: the others' are on the desk already.
            for project in made where !Starters.hasShippedIcon(project) {
                if let spec = Icons.load(project) { await renderIcon(project, spec: spec) }
            }
        }
    }
    private var startersInstall: Task<Void, Never>?

    /// One starter put on the desk from Lamp's bundle, as on the first launch: its files in a new app, saved as
    /// its first version and built by `prepareStarters`. The caller reloads the desk. Nil when it couldn't be
    /// written, and then nothing of it is left.
    func add(starter: Starters.Starter) -> LampProject? {
        do {
            let project = try Template.draft(name: uniqueName(starter.name), platform: starter.kind, in: root)
            do {
                try Template.fill(project)
                try Starters.copy(starter, into: project)
                try Template.writeOwnedFiles(for: project)   // again, now it's known whether it has a widget
                // A copy deleted after its build failed leaves its folder name free for this one, which is built afresh.
                unpreparedStarters.remove(project.id)
                return project
            } catch {
                try? FileManager.default.removeItem(at: project.dir)
                throw error
            }
        } catch {
            NSLog("Lamp couldn't add the wish \(starter.name): \(error.localizedDescription)")
            return nil
        }
    }

    /// A starter put back on the desk after the first launch (Starter wishes' Add): added, shown on the desk, and
    /// saved and built out of sight like the first launch's (`prepareStarters`).
    @discardableResult func put(starter: Starters.Starter) -> LampProject? {
        guard let added = add(starter: starter) else { return nil }
        reload()
        guard let project = current(added) else { return nil }
        if !Starters.hasShippedIcon(project), let spec = Icons.load(project) {
            Task { await renderIcon(project, spec: spec) }
        }
        prepareStarters()
        return project
    }

    /// A starter's chat begins with what it offers to change first (`Starters.card`), added a moment after the chat
    /// is first shown, beside the app or in Lamp's window, so it arrives there rather than being there already.
    /// Once: a chat in which anything has been said is left as it is. Lamp's own lines about building the app (one
    /// built again for a newer Lamp before its chat was ever opened: "Updating … for this version of Lamp…", "… is
    /// ready") aren't a conversation, so the card still comes, under them.
    func offerStarterChanges(_ id: String, after delay: Double) {
        guard Self.nothingSaid(in: logs[id] ?? []), let project = projects.first(where: { $0.id == id }), Starters.isStarter(project),
              let starter = Starters.starter(of: project), let card = Starters.card(for: starter),
              offeringStarter.insert(id).inserted else { return }
        Task {
            try? await Task.sleep(for: .seconds(delay))
            offeringStarter.remove(id)
            guard let current = current(project), Self.nothingSaid(in: logs[id] ?? []) else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { logs[id, default: []].append(card) }
            saveChat(current)
        }
    }
    private var offeringStarter: Set<String> = []

    /// Whether a chat holds nothing but Lamp's own lines about building and opening the app: no request, no word
    /// from the agent, no card.
    private static func nothingSaid(in lines: [LogLine]) -> Bool {
        lines.allSatisfy { [.status, .detail, .error].contains($0.kind) }
    }

    /// Starters being built for the first time, out of sight: their icons spin on the desk.
    @Published private(set) var preparing: Set<String> = []
    /// Starters used while they were still being built: each opens when its build is done.
    @Published var openWhenReady: Set<String> = []
    private var preparingStarters = false
    /// Starters whose first build failed this time: not tried again until Lamp next starts, and opening one
    /// shows its chat, which has the failure.
    private var unpreparedStarters: Set<String> = []

    /// Builds the starters nobody has opened yet, one at a time, as soon as Apple's tools are there, so each
    /// opens at once when used. One that's being waited for goes first.
    func prepareStarters() {
        guard canPrepare(), !preparingStarters else { return }
        preparingStarters = true
        Task {
            defer { preparingStarters = false }
            await startersInstall?.value
            // Their first versions need git, one of Apple's tools; a prebuilt starter made ready before them gets
            // its first version when they arrive.
            if setup.hasBuildTools { await saveStartersFirstVersions() }
            // Each once: one that couldn't be made ready without the tools waits for them, not for this loop.
            // Known by instance, not folder: a starter deleted and added back meanwhile takes the same folder
            // name, and is a new one to build.
            var tried: Set<String> = []
            while let next = nextStarterToPrepare(excluding: tried) {
                tried.insert(next.instance)
                // Again for each: one put back on the desk meanwhile gets its first version before its build.
                if setup.hasBuildTools { await saveStartersFirstVersions() }
                await prepare(next)
            }
        }
    }

    /// Each starter's first version, "From Lamp", which Undo and Versions go back to: made once Apple's tools are
    /// there, since git is one of them, and tried again on a later launch for one where it didn't take.
    private func saveStartersFirstVersions() async {
        for project in projects where Starters.isStarter(project)
            && !FileManager.default.fileExists(atPath: project.dir.appendingPathComponent(".git").path) {
            if !(await initRepo(project, message: "From Lamp")) {
                try? FileManager.default.removeItem(at: project.dir.appendingPathComponent(".git"))
                NSLog("Lamp couldn't save the first version of \(project.name)")
            }
        }
    }

    /// A starter that's never been built and that nothing else is working on.
    func needsPreparing(_ project: LampProject) -> Bool {
        Starters.isStarter(project) && !unpreparedStarters.contains(project.id) && !busy.contains(project.id)
            && !FileManager.default.fileExists(atPath: project.installedURL.path)
    }

    /// Whether some starter can be made ready now: any, once Apple's build tools are there, and before then the
    /// ones Lamp came with already built (`PrebuiltStarters`).
    func canPrepare(_ project: LampProject? = nil) -> Bool {
        if setup.hasBuildTools { return true }
        if let project { return PrebuiltStarters.has(project) }
        return projects.contains { needsPreparing($0) && PrebuiltStarters.has($0) }
    }

    private func nextStarterToPrepare(excluding tried: Set<String> = []) -> LampProject? {
        let waiting = projects.filter { needsPreparing($0) && canPrepare($0) && !tried.contains($0.instance) }
        return waiting.first { openWhenReady.contains($0.id) } ?? waiting.first
    }

    /// A starter's first build and install, without opening it and without a word in its chat: its chat stays
    /// empty for the person's first change. A failure stays in the chat, for the agent that is asked to fix it.
    private func prepare(_ project: LampProject) async {
        guard begin(project) != nil else { return }
        preparing.insert(project.id)
        let before = Set((logs[project.id] ?? []).map(\.id))
        var made = false
        // The copy Lamp came with when it's what this build would make, so the starter is ready at once.
        var ready = PrebuiltStarters.install(into: project)
        // Without Apple's tools there's no build: a starter whose prebuilt copy couldn't be used waits for them.
        let canBuild = setup.hasBuildTools
        if !ready, canBuild { ready = await build(project) == nil }
        if ready {
            await prepareIcon(project)
            do {
                try await deploy(project)
                heldInstalls.installed(project.id)
                Runtime.releaseBuild(project)
                stamps[project.id] = BuildStamp.read(project.installedURL)
                made = true
            } catch {
                log(project, .error, ErrorMessages.installFailed(error.localizedDescription))
            }
        }
        // Only what the build said goes: the card its chat may have been given meanwhile stays.
        if made, let lines = logs[project.id] {
            logs[project.id] = lines.filter { before.contains($0.id) || $0.kind == .ask }
            saveChat(project)
        }
        if !made, canBuild { unpreparedStarters.insert(project.id) }
        preparing.remove(project.id)
        finish(project)
        guard openWhenReady.remove(project.id) != nil, let current = current(project) else { return }
        if made { open(fromDesk: current) } else { showChat(current.id) }
    }

    func run(_ project: LampProject) async {
        // Only the wish, its apps all in folders of their own: each is built and opened as itself (`rebuildParts`).
        guard project.holdsApp else { return }
        guard begin(project) != nil else { return }
        defer { finish(project) }
        guard let project = await materialize(project) else { return }
        let errors = await build(project)
        if errors == nil {
            await installReportingCrash(project)
        } else if errors != macMembershipProblem(project) {
            log(project, .error, ErrorMessages.appDoesNotBuild)
        }
    }

    /// The wish's other apps after its own, each built and opened as `run` does it, under a hold of its own so a crash
    /// on launch is fixed as that app's (`fixHeldCrash`, through its wish): a copy's first build, Undo and every restore
    /// change the whole wish, and no app of it comes first. `onlyChanged` leaves out a part whose files are what its
    /// last build was made from. One busy with a turn of its own, and every part after a Stop, are left alone.
    private func rebuildParts(of wish: LampProject, onlyChanged: Bool = false) async {
        for part in parts(of: wish) {
            guard turns[wish.id]?.stopped != true, let part = current(part) else { return }
            if onlyChanged, !Runtime.sourcesChanged(part) { continue }
            rebuildingFor[part.id] = wish.id
            await run(part)
            rebuildingFor[part.id] = nil
        }
    }
    /// The wish each part being rebuilt by `rebuildParts` belongs to, so Stop in the wish's chat reaches it.
    private var rebuildingFor: [String: String] = [:]

    /// Goes back to the version before the current one. Like any restore, this is itself a new version.
    /// `change` is the version Undo Last Change in the chat was offered under: when the app has moved on from it
    /// since, nothing is undone, rather than a change the person wasn't looking at.
    func undo(_ project: LampProject, change: String? = nil) async {
        guard begin(project) != nil else { return }
        defer { finish(project) }
        dropPausedRequest(project)
        let versions = await Versions.list(project)
        let unsaved = await Versions.hasUnsavedChanges(project)
        if let change, unsaved || versions.first?.id != change || Versions.undoTarget(in: versions)?.undoing.id != change {
            log(project, .status, "The app has changed since, so nothing was undone")
            return
        }
        // A turn that was stopped, or never got the app building, leaves its changes unsaved: Undo discards those first.
        if let current = versions.first, unsaved {
            _ = await Versions.restoreFiles(project, to: current)
            let restored = await followRestored(project)
            log(restored, .status, "Discarded the unfinished change")
            if await build(restored) == nil { await installReportingCrash(restored) }
            await rebuildParts(of: restored, onlyChanged: true)
            return
        }
        let undo = Versions.undoTarget(in: versions)
        let renaming = undo.flatMap { self.renaming(project, to: $0.target, in: versions) }
        guard let (undoing, target) = undo,
              await Versions.restore(project, to: target, message: "Undid “\(undoing.label)”",
                                     trailer: "Lamp-Undid: \(undoing.id)", renaming: renaming) else {
            log(project, .status, "Nothing to undo")
            return
        }
        let restored = await takeName(renaming, await followRestored(project))
        Versions.remember(restored, restoredTo: target.label, from: target.date)
        log(restored, .status, "Undid “\(undoing.label)”")
        await rebuild(restored, restoredFrom: target)
    }

    /// Brings back an earlier version's files as a new version, so the restore can be undone too.
    func restore(_ project: LampProject, to version: AppVersion) async {
        guard begin(project) != nil else { return }
        defer { finish(project) }
        dropPausedRequest(project)
        let renaming = self.renaming(project, to: version, in: await Versions.list(project))
        guard await Versions.restore(project, to: version, message: Versions.restoredMessage(to: version), renaming: renaming) else {
            log(project, .status, "The app is already like “\(version.label)”")
            return
        }
        let restored = await takeName(renaming, await followRestored(project))
        Versions.remember(restored, restoredTo: version.label, from: version.date)
        log(restored, .status, Versions.restoredMessage(to: version))
        await rebuild(restored, restoredFrom: version)
    }

    /// Goes back to the version a request in the chat made, or to the one before it.
    func restore(_ project: LampProject, toVersionOf line: LogLine, before: Bool) async {
        let versions = await Versions.list(project)
        guard let made = line.version.flatMap({ id in versions.first { $0.id == id } }),
              let target = before ? made.parent.flatMap({ id in versions.first { $0.id == id } }) : made else { return }
        await restore(project, to: target)
    }

    /// Sends a request again in other words, from where the app was when it was first sent. The app's files
    /// go back to that point (as a new version, like any restore, so what came later is still in Versions),
    /// the request and everything after it leave the chat, and the new words go out as an ordinary turn.
    /// The agent keeps its conversation, as it does after Undo, and is told what was taken back: the three
    /// engines can't all be wound back to an earlier message, and a note works the same for each of them.
    /// `attachments` are the files to send with it: the request's own, already in the app's folder, and any added.
    /// False when the app couldn't be taken back, and nothing was sent.
    func sendAgain(_ line: LogLine, as text: String, attachments: [URL], pointed: PointedAt? = nil, in project: LampProject) async -> Bool {
        guard busy.insert(project.id).inserted else { return false }
        defer { finish(project) }   // which starts the turn queued below
        dropPausedRequest(project)
        let versions = await Versions.list(project)
        // Requests from before Lamp noted where they were sent from: the version one made follows that point.
        let start = line.before ?? line.version.flatMap { id in versions.first { $0.id == id }?.parent }
        guard let target = start.flatMap({ id in versions.first { $0.id == id } }),
              await Versions.restoreFiles(project, to: target),
              let chat = logs[project.id], let index = chat.firstIndex(where: { $0.id == line.id }) else {
            log(project, .error, ErrorMessages.restoreFailed)
            return false
        }
        await followRestored(project)
        if await Versions.save(project, message: Versions.restoredMessage(to: target)), let head = await Versions.head(project) {
            Versions.copyPicture(in: project, from: target.id, to: head)
            versionsRevision += 1
        }
        // Requests that went out together made one change, so the ones just before this one go out with it again:
        // those sent at once, and, for one the agent took while it worked, the requests of its turn before it.
        var first = index
        var midTurn = line.midTurn == true
        while first > chat.startIndex, chat[first - 1].kind == .user || midTurn {
            first -= 1
            if chat[first].kind == .user { midTurn = chat[first].midTurn == true }
        }
        // They keep what they had taken back themselves: it's the chat's only record of it.
        var again = chat[first..<index].filter { $0.kind == .user }.map {
            QueuedMessage(text: $0.text, kept: $0.attachments ?? [], replaces: $0.replaced, tookBack: $0.tookBack ?? [],
                          pointed: $0.pointed?.waiting(in: project))
        }
        let folder = project.dir.appendingPathComponent(Attachments.folder).standardizedFileURL
        let own = attachments.filter { $0.standardizedFileURL.deletingLastPathComponent() == folder }
        // What the agent is told was taken back is the first request leaving the chat that it actually had:
        // this one, or, when this one's own turn never reached it (the model couldn't be reached, say), the
        // first after it that did. When none did, this one was only standing in for an earlier request, or
        // for nothing, and sending it again takes back what it was taking back.
        let had = chat[index...].first { $0.kind == .user && Self.reachedAgent($0.id, in: chat) }
        let replaces = had.map { Self.label(for: $0) } ?? line.replaced
        // Everything that leaves the chat with it is something the user decided against (for the suggested
        // next message), along with what those had taken back in their turn. Not a request that never got
        // through: that one is only being tried again.
        let gone = chat[index...].filter { $0.kind == .user }.flatMap { request in
            (request.tookBack ?? []) + (Self.reachedAgent(request.id, in: chat) ? [Self.label(for: request)] : [])
        }.filter { $0 != text }
        again.append(QueuedMessage(text: text, attachments: attachments.filter { !own.contains($0) },
                                   kept: own.map(\.lastPathComponent), replaces: replaces, tookBack: gone, pointed: pointed))
        logs[project.id] = Array(chat[..<first])
        saveChat(project)
        progress[project.id] = nil   // a new app's chapters belong to the request that's gone
        if let replaces { Versions.remember(project, tookBack: replaces) }
        queued[project.id, default: []].insert(contentsOf: again, at: 0)
        return true
    }

    /// Whether the agent got as far as answering a request or working on it: something of its own follows the
    /// request in the chat before the next one. A turn that failed first leaves only Lamp's lines there.
    static func reachedAgent(_ request: UUID, in chat: [LogLine]) -> Bool {
        guard let index = chat.firstIndex(where: { $0.id == request }) else { return false }
        return chat[(index + 1)...].drop { $0.kind == .user }.prefix { $0.kind != .user }
            .contains { $0.kind == .agent || $0.kind == .tool }
    }

    /// After a restore: the new version looks like the old one, so it starts with its picture until the app
    /// takes a fresh one.
    private func rebuild(_ project: LampProject, restoredFrom version: AppVersion) async {
        guard let head = await Versions.head(project) else { return }
        Versions.copyPicture(in: project, from: version.id, to: head)
        versionsRevision += 1
        if await build(project) == nil {
            await installReportingCrash(project)
            keepPicture(of: project, version: head)
        }
        await rebuildParts(of: project, onlyChanged: true)
    }

    /// Chats from before requests were linked to versions: matches each request to the version whose
    /// message is its text, in order. Requests that made no change, or went out together, stay unlinked.
    func linkOldRequests(_ project: LampProject) async {
        guard var chat = logs[project.id], chat.contains(where: { $0.kind == .user && $0.version == nil }) else { return }
        func plain(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        let versions = await Versions.list(project).reversed()
        let linked = Set(chat.compactMap(\.version))
        var index = chat.startIndex
        var links: [UUID: String] = [:]
        for version in versions where !linked.contains(version.id) {
            let message = plain(version.message)
            guard let match = chat[index...].firstIndex(where: {
                $0.kind == .user && $0.version == nil && plain(Self.label(for: $0)) == message
            }) else { continue }
            chat[match].version = version.id
            links[chat[match].id] = version.id
            index = chat.index(after: match)
        }
        // The chat may have moved on while the versions were read: lines added, and a reply being written
        // grows in place. So the links go into the chat as it is now, line by line, never the copy back over it.
        guard !links.isEmpty, var current = logs[project.id] else { return }
        for index in current.indices where current[index].version == nil {
            if let version = links[current[index].id] { current[index].version = version }
        }
        logs[project.id] = current
        saveChat(project)
    }

    /// Gives the newest versions without one a short title from what changed, one at a time. Runs on its
    /// own, so the Versions panel reloading as titles arrive doesn't cancel it.
    func titleVersions(_ project: LampProject, limit: Int = 40) {
        guard titling.insert(project.id).inserted else { return }
        Task {
            defer { titling.remove(project.id) }
            for version in await Versions.list(project).prefix(limit) where version.title == nil && !version.isLampNote {
                guard let title = await VersionTitles.make(for: version, in: project) else { return }
                VersionTitles.save(title, for: version.id, in: project)
                versionsRevision += 1
            }
        }
    }

    /// Apps from before pictures were kept: the current version gets the picture of the current build.
    func fillCurrentPicture(_ project: LampProject, current: AppVersion) async {
        guard !FileManager.default.fileExists(atPath: Versions.pictureURL(in: project, for: current.id).path),
              let screenshot = Runtime.currentScreenshot(of: project), !busy.contains(project.id),
              await !Versions.hasUnsavedChanges(project) else { return }
        Versions.savePicture(screenshot, in: project, for: current.id)
        versionsRevision += 1
    }

    /// Links requests in the chat to the version they made.
    private func link(_ lines: [UUID], to version: String, in project: LampProject) {
        guard var chat = logs[project.id] else { return }
        for index in chat.indices where lines.contains(chat[index].id) { chat[index].version = version }
        logs[project.id] = chat
        saveChat(project)
    }

    /// Notes on requests the version the app was at when they were sent.
    private func mark(_ lines: [UUID], sentFrom version: String, in project: LampProject) {
        guard var chat = logs[project.id] else { return }
        for index in chat.indices where lines.contains(chat[index].id) { chat[index].before = version }
        logs[project.id] = chat
        saveChat(project)
    }

    /// Keeps the picture the app takes of itself shortly after opening, to show with its version.
    private func keepPicture(of project: LampProject, version: String) {
        Task {
            for _ in 0..<40 {
                if let screenshot = Runtime.currentScreenshot(of: project) {
                    Versions.savePicture(screenshot, in: project, for: version)
                    versionsRevision += 1
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    /// Shows the Name… alert for the version the app is at now.
    func nameCurrentVersion(of project: LampProject) async {
        guard let current = await Versions.list(project).first else { return }
        naming = VersionNaming(project: project, version: current)
    }

    func name(_ version: AppVersion, of project: LampProject, as name: String) async {
        await Versions.name(project, version.id, name)
        versionsRevision += 1
    }

    /// Returns nil on success, or the tail of the compiler output on failure.
    /// Lamp's own files in an app (`Template.writeOwnedFiles`, or only LampSupport.swift), written away from the main
    /// thread. Filling in the support file's template copies several hundred kilobytes once for each placeholder and
    /// asks the system for this Mac's network name, which held the main thread, and so the chat, for about a tenth of
    /// a second at every agent run and build. An app's writes go one after another and are remembered
    /// (`fileWrites`), so deleting or remaking its folder waits for them (`settleFiles`): one finishing afterwards
    /// would make parts of the folder again.
    private func writeOwnFiles(_ project: LampProject, all: Bool) async throws {
        // A device's setup conversation has no app for Lamp's files to be part of, nor has a wish whose apps are all in
        // folders of their own.
        if project.isDeviceSetup || !project.holdsApp { return }
        let before = fileWrites[project.id]
        let write = Task.detached(priority: .userInitiated) {
            _ = await before?.result
            if all { try Template.writeOwnedFiles(for: project) } else { try Template.writeSupport(for: project) }
        }
        fileWrites[project.id] = write
        defer { if fileWrites[project.id] == write { fileWrites[project.id] = nil } }
        try await write.value
    }
    private var fileWrites: [String: Task<Void, Error>] = [:]

    /// Waits for Lamp's own files being written in the app's folder, before the folder is deleted or made again: the
    /// latest write, and again for any started while waiting (a look the agent asked for meanwhile). The caller goes
    /// on to the folder without waiting for anything else, so nothing can start in between.
    private func settleFiles(_ project: LampProject) async {
        var waited: Task<Void, Error>?
        while let write = fileWrites[project.id], write != waited {
            _ = await write.result
            waited = write
        }
    }

    /// `inPlace` false builds the whole app without first putting the change into the open one: a look that reopens
    /// the app installs the whole build anyway.
    private func build(_ project: LampProject, inPlace: Bool = true) async -> String? {
        // The open app glows while its change is built, until it goes in (`reloadInPlace`) or the install that
        // follows settles otherwise; a build that fails lets it go here.
        let glowing = exists(project) && AppTransition.begin(project)
        let problem = await buildNow(project, inPlace: inPlace)
        if glowing, problem != nil { AppTransition.end(project) }
        return problem
    }

    private func buildNow(_ project: LampProject, inPlace: Bool) async -> String? {
        guard exists(project) else { return "The app was deleted." }
        // Only the wish, its apps all in folders of their own: nothing to build here.
        guard project.holdsApp else { return nil }
        // A save of the agent's being put in finishes first: both write the live copy. One that hasn't reached the
        // compiler yet, for sources the agent has moved on from, gives way to this build, which takes the newer ones.
        let owner = turns[project.id]
        owner?.building = true
        defer { owner?.building = false }
        if let owner, let applying = owner.applying, !owner.reloading, owner.applyingSources != Runtime.fingerprint(project) { applying.cancel() }
        await owner?.applying?.value
        await owner?.warming?.value
        log(project, .status, "Building…")
        // A device app whose kind takes the icon gets it in the package Lamp sends, drawn from the icon as it is now:
        // its install comes after the package is made, so the icon is brought up to date first, not there.
        if project.onDevice, !DeviceSupport.icons(for: project).isEmpty { await prepareIcon(project) }
        // Lamp's own files first, and no build without them: the build runs build.sh and Package.swift.
        do {
            try await writeOwnFiles(project, all: true)
        } catch {
            let problem = "Lamp couldn't write the app's build files: \(error.localizedDescription)"
            log(project, .error, problem)
            return problem
        }
        // Stop pressed, or the app deleted, while they were written: there's no build yet for Stop to end.
        guard exists(project) else { return "The app was deleted." }
        if let owner, owner.stopped || turns[project.id] !== owner { return "Stopped." }
        // Taken before the build, so an edit made while it runs still counts as a change afterwards.
        let fingerprint = Runtime.fingerprint(project)
        // A TV app has nothing to compile: its files are copied where the preview and the packages read them.
        if project.onTV {
            do {
                _ = try await TVs.stage(project)
                Runtime.markBuilt(project, from: fingerprint)
                return nil
            } catch {
                log(project, .detail, "Build failed:\n" + error.localizedDescription)
                return error.localizedDescription
            }
        }
        // A device app's build is its integration's package step, in the app's sandbox; Lamp keeps the package it made.
        if project.onDevice {
            // A game's tools aren't here: said once for a request, with the window that gets them open.
            if let problem = gameToolsProblem(project) {
                let said = (logs[project.id] ?? []).reversed().prefix { $0.kind != .user }.contains { $0.kind == .error && $0.text == problem }
                if !said { log(project, .error, problem); WindowsSetup.shared.show() }
                return problem
            }
            note("Building…", for: project)
            do {
                try await DeviceApps.build(project, started: { [weak self] in self?.turns[project.id]?.build = $0 })
                turns[project.id]?.build = nil
                Runtime.markBuilt(project, from: fingerprint)
                return nil
            } catch {
                turns[project.id]?.build = nil
                log(project, .detail, "Build failed:\n" + error.localizedDescription)
                return error.localizedDescription
            }
        }
        var output: [String] = []
        // An app for both is built for where Try On points; its Mac build is Xcode's, signed for the team.
        let universal = project.platform == .universal
        if universal, !project.onIOS, Devices.team.isEmpty {
            let problem = "The Mac build of an app for both is signed for your Apple team, and none is chosen yet. Choose it in Settings → Building, then try again."
            log(project, .error, problem)
            return problem
        }
        // Android's tools aren't here: nothing to build with, said once for a request, with the window to get them open.
        if let problem = androidToolsProblem(project) {
            let said = (logs[project.id] ?? []).reversed().prefix { $0.kind != .user }.contains { $0.kind == .error && $0.text == problem }
            if !said { log(project, .error, problem); AndroidSetup.shared.show() }
            return problem
        }
        // Xcode would get as far as signing and fail there: said first, in the person's words, and once for
        // a request, however many times the request tries to build.
        if let problem = macMembershipProblem(project) {
            let said = (logs[project.id] ?? []).reversed().prefix { $0.kind != .user }.contains { $0.kind == .error && $0.text == problem }
            if !said { log(project, .error, problem) }
            return problem
        }
        let game = GameKit.isGame(project)
        // A game's shaders are compiled with a tool Lamp fetches the first time, a small download with nothing to accept.
        if game, GameKit.engine(project) == .native {
            do { try await GameKit.toolsForApple() } catch {
                log(project, .error, error.localizedDescription)
                return error.localizedDescription
            }
        }
        let command = universal || game || ScreenKit.hostsOnApple(project) ? "./build.sh \(project.onIOS ? "ios" : project.onAndroid ? "android" : "mac")" : "./build.sh"
        // An Android app's build is Gradle's, with Google's tools where Lamp put them (`AndroidTools.environment`).
        var env: [String: String] = universal ? ["LAMP_TEAM": Devices.team]
            : project.onAndroid ? AndroidTools.buildEnvironment.merging(game ? WindowsTools.buildEnvironment : [:]) { $1 }
            : game && GameKit.engine(project) == .native ? WindowsTools.buildEnvironment : [:]
        // The open app takes the change first, when it can (LiveReload): a few seconds, where the whole build
        // takes several more. That build goes on afterwards, for the app to be installed from when it closes.
        // An iOS app Try On points at an Apple TV or a Vision Pro is the same code built for tvOS or visionOS.
        if project.onIOS, project.family.isOtherOS { env["LAMP_FAMILY"] = project.family.rawValue }
        if inPlace, await reloadBeforeBuilding(project, command: command, env: env, fingerprint: fingerprint) { return nil }
        // Said again: a change that couldn't go into the open app left the line on putting it in, through the whole build.
        note("Building…", for: project)
        await awaitLiveBuild(of: project)
        liveBuildFailed.remove(project.id)
        if LiveReload.eligible(project) { env["LAMP_LIVE"] = "1"; LiveSlots.expireGiveUps(project, appOpen: !macCopies(of: project).isEmpty) }   // a change can go into the open app (LiveReload)
        // What else goes into the app as this build starts, kept with what it compiled once it has built.
        let inputs = env["LAMP_LIVE"] == "1" ? LiveReload.inputs(project) : nil
        let status = await Self.buildSparing(command, for: project, env: env,
                                             started: { [weak self] in self?.turns[project.id]?.build = $0 }) { output = $0 }
        turns[project.id]?.build = nil
        guard exists(project) else { return "The app was deleted." }
        guard status != 0 else {
            if let inputs { LiveReload.noteBuilt(project, inputs: inputs) }
            Runtime.markBuilt(project, from: fingerprint)
            BuildStamp.write(for: project)   // deploy signs the app afterwards
            return nil
        }
        let tail = output.suffix(40).joined(separator: "\n")
        log(project, .detail, "Build failed:\n" + tail)
        return tail
    }

    /// Builds the app, and for a live build makes sure the live copy's spare places and final classes are never what
    /// keeps it from building: if they are, the structs' initializers are written again without the spares and the
    /// build tried once more; if that doesn't do, it's built without them from now on, so the agent only ever sees
    /// errors in its own code. Both are judged, since one output may hold both kinds of error; the build is tried
    /// again if either gave up. `done` gets the last build's output.
    static func buildSparing(_ command: String, for project: LampProject, env: [String: String],
                             started: (@MainActor (Process) -> Void)? = nil,
                             done: ([String]) -> Void) async -> Int32 {
        var output: [String] = []
        defer { done(output) }
        var status = await runBuild(command, for: project, env: env, started: started) { output.append($0) }
        if status != 0, env["LAMP_LIVE"] == "1", LiveSlots.brokeBuild(output.joined(separator: "\n")), await LiveSlots.addMemberwise(project) {
            output = []
            status = await runBuild(command, for: project, env: env, started: started) { output.append($0) }
        }
        if status != 0, env["LAMP_LIVE"] == "1", case let text = output.joined(separator: "\n"),
           case let spares = LiveSlots.brokeBuild(text) && LiveSlots.giveUp(project),
           case let finals = LiveSlots.brokeFinal(text, project: project) && LiveSlots.giveUpFinal(project), spares || finals {
            output = []
            status = await runBuild(command, for: project, env: env, started: started) { output.append($0) }
            // Failing without them too, the errors were the agent's own code: the compiler prints the lines around
            // an error, spares included, so its words alone can't tell. A give-up kept then would hold every later
            // change for Reload, since the open app has the spares the copy no longer does.
            if status != 0 {
                if spares { LiveSlots.takeBack("no-spares", for: project) }
                if finals { LiveSlots.takeBack("no-final", for: project) }
            }
        }
        return status
    }

    /// Runs the app's build.sh. It's Lamp's file, written just before, but in the agent's folder: a command the agent
    /// left running can put its own there in between, and Package.swift and the code it compiles are the agent's
    /// anyway. So the build runs as the agent's commands do, in the app's sandbox (`Sandbox.run`), and only what it
    /// made is taken further, by Lamp, from a copy (`deploy`), which is where anything is signed for the person's team.
    static func runBuild(_ command: String, for project: LampProject, env: [String: String],
                         started: (@MainActor (Process) -> Void)? = nil,
                         onLine: @escaping @MainActor (String) -> Void) async -> Int32 {
        // Which structs the app reads as bytes, for the live copy's spares: worked out only when its raw-memory code changed.
        if env["LAMP_LIVE"] == "1" { await LiveSlots.noteByteStructs(project) }
        return await Sandbox.run(Shell.compatibleSDK + command, for: project, env: env, started: started, onLine: onLine)
    }

    /// A new app's bar that has already said how its turn ended follows what happens to the app afterwards
    /// (Play, a rebuild, opening the copy that's installed), as it does for a phone: it never goes on saying
    /// the app didn't open beside one that has, or the reverse.
    private func noteOpened(_ opened: Bool, for project: LampProject) {
        if progress[project.id]?.finished != nil { progress[project.id]?.unopened = !opened }
        if opened { warmLive(project) }
    }

    /// What the open app's types hold, worked out as soon as the app is open (`LiveReload.warm`), so the compiler's
    /// slow first read of a session is over before the agent's first save rather than in front of it. One at a time
    /// per app; each goes when it's done, and a later open starts another only when there's something to work out.
    private var warmings: [String: Task<Void, Never>] = [:]
    @discardableResult private func warmLive(_ project: LampProject) -> Task<Void, Never>? {
        guard LiveReload.eligible(project) else { return nil }
        if let warming = warmings[project.id] { return warming }
        let warming = Task { [weak self] in
            let began = Date()
            await LiveReload.warm(project)
            guard let self else { return }
            warmings[project.id] = nil
            let took = Date().timeIntervalSince(began)
            if took > 2 { log(project, .detail, "Worked out what the open app holds, ahead of the next change, in \(Int(took.rounded())) s.") }
        }
        warmings[project.id] = warming
        return warming
    }

    /// The whole builds running after a change went into the open app, by app: a build waits for the one before.
    private var liveBuilds: [String: Task<Void, Never>] = [:]
    /// Apps whose whole build after an early change failed: build/ holds the version before it, which isn't
    /// installed in its place. Cleared by the next build.
    private var liveBuildFailed: Set<String> = []
    /// Apps whose change went in before their build: the install that follows the build has nothing to do.
    private var reloadedBeforeBuild: Set<String> = []
    /// What each running whole build after an early change was started from: its process, to end it when a newer
    /// change makes it stale, and the fingerprint of the sources it builds, to tell when nothing changed since.
    private var liveBuildRuns: [String: (process: Process?, fingerprint: String)] = [:]
    /// Whole builds ended because a newer change replaced them: what they leave in build/ isn't installed.
    private var liveBuildsSuperseded: Set<String> = []

    /// Waits for the whole build after an early change, which can take a minute: meanwhile the turn says it's
    /// building, not that the change is going in, which was said seconds before and is done.
    private func awaitLiveBuild(of project: LampProject) async {
        guard let whole = liveBuilds[project.id] else { return }
        note("Building…", for: project)
        await whole.value
    }

    /// Ends the whole build after an earlier change, and waits for it to be gone, since the next build writes the
    /// same folders. What it left in build/ is the version before the change, or half of it, so until another
    /// whole build is done the app is treated as one whose whole build failed: never installed from it.
    private func supersedeLiveBuild(of project: LampProject) async {
        guard let whole = liveBuilds[project.id] else { return }
        liveBuildsSuperseded.insert(project.id)
        liveBuildFailed.insert(project.id)
        // Not started yet (the process is handed over as it starts): it runs, briefly, and ends at its first check.
        if let process = liveBuildRuns[project.id]?.process { Subprocess.terminateTree(process) }
        await whole.value
    }

    /// While the agent works on an open Mac app, each change it saves is put into the app by itself a moment after
    /// the saving pauses, by the quick path a look takes (`reloadBeforeBuilding`): the person watches the app take
    /// each piece as it's written, rather than when the agent chooses to look, or all at once at the end. Only a
    /// change that can go in live goes in this way; one that needs a reopen is left alone, for the turn's end to
    /// build and hold for Reload once, with everything else. The sources are read every two seconds and a state is
    /// tried once it has held still for a reading, and only once: what didn't go in isn't tried again until it changes.
    private func autoApply(_ project: LampProject, in turn: Turn) -> Task<Void, Never> {
        Task { [weak self] in
            var seen = "", tried = "", seenAt = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                // Reload pressed while the agent works goes in here, between its steps, inside this turn.
                if let self, !Task.isCancelled, reloadWhenFree.contains(project.id), turns[project.id] === turn {
                    await reloadInTurn(project, turn)
                    continue
                }
                guard let self, !Task.isCancelled, turns[project.id] === turn, !turn.stopped, turn.agent != nil,
                      !turn.look.inProgress, !turn.building, !turn.keptOpen, turn.applying == nil,
                      let current = current(project), LiveReload.eligible(current),
                      isRunning(current), !Runtime.waitsForReload(current),
                      // A change that crashed the app waits for the agent to hear of it: what it saves meanwhile may crash it again.
                      setAsideChanges[project.id]?.told != false
                          || turn.carriedSetAside == setAsideChanges[project.id]?.crash else { continue }
                let now = Runtime.fingerprint(current)
                // Still being written: wait for a reading with nothing new in it.
                if now != seen { seen = now; seenAt = Date(); continue }
                guard now != tried, Runtime.sourcesChanged(current) else { continue }
                tried = now
                let saved = seenAt
                turn.applyingSources = now
                turn.applying = Task { [weak self] in
                    guard let self else { return }
                    defer { turn.applying = nil }
                    let waited = Date()
                    await turn.warming?.value
                    let warmWait = Date().timeIntervalSince(waited)
                    try? await writeOwnFiles(current, all: false)
                    guard turns[project.id] === turn, !turn.stopped, exists(current) else { return }
                    let universal = current.platform == .universal
                    let command = universal ? "./build.sh mac" : "./build.sh"
                    let env: [String: String] = universal ? ["LAMP_TEAM": Devices.team] : [:]
                    let glowing = AppTransition.begin(current)
                    let went = await reloadBeforeBuilding(current, command: command, env: env, fingerprint: now)
                    // Stopped meanwhile: whatever went in stays in, and the turn that's over says nothing of it.
                    guard turns[project.id] === turn, !turn.stopped else { reloadedBeforeBuild.remove(current.id); return }
                    if went {
                        // What a look's install would note of a change that went in; the look reads it from here.
                        reloadedBeforeBuild.remove(current.id)
                        turn.updatedInPlace = true
                        turn.outcomes.append(.live)
                        turn.reloadWhy = nil
                        turn.autoApplied += 1
                        // A step, not the turn's end: "is updated" is said once the request is done, and here the
                        // agent is still at work on it.
                        log(current, .status, "Put the change into \(current.name)")
                        log(current, .detail, "The change went in \(Int(Date().timeIntervalSince(saved).rounded())) s after it was saved"
                            + (warmWait > 1 ? ", \(Int(warmWait.rounded())) s of them waiting for the warm-up." : "."))
                    } else {
                        // Nothing went in, and the whole build of an earlier change may have been ended for this
                        // one: until the next build nothing is installed from build/.
                        liveBuildFailed.insert(current.id)
                        if glowing { AppTransition.end(current) }
                    }
                }
                await turn.applying?.value
            }
        }
    }

    /// Reload pressed while a request's agent works on the app (`reloadWaiting`): the change held for it goes in as soon
    /// as the agent is between steps (no look, build, change going in or call into Lamp under way), by the turn that
    /// owns the app, so the person sees the held pass within seconds rather than when the request is done. The agent
    /// hears it with its next look (`Turn.reloadedByPerson`), since it was told the change waits for Reload.
    private func reloadInTurn(_ project: LampProject, _ turn: Turn) async {
        guard !turn.stopped, turn.agent != nil, !turn.look.inProgress, !turn.building, !turn.keptOpen, turn.applying == nil,
              turn.answering == 0, let wish = current(project) else { return }
        reloadWhenFree.remove(project.id)
        // The wish's own app, or the part of it whose change waits.
        guard let current = waitingForReload(in: wish) else { away.dropped(project.id); return }   // a live change put it in
        away.installs(project.id)
        turn.reloading = true
        turn.applying = Task { [weak self] in
            defer { turn.applying = nil; turn.reloading = false }
            guard let self else { return }
            // The Mac copy's change, wherever Try On points now (an app for both may have moved it to a phone since).
            var mac = current
            mac.chosen = .mac
            _ = await install(mac, inFront: true, fresh: true, reload: true, saysReady: false)
            // Lamp's, while the person was away, with the turn over meanwhile: the agent never heard the change is in.
            let lamps = away.landed(project.id, stillWaits: Runtime.waitsForReload(current))
            if lamps, turns[project.id] !== turn, away.carriesOn(project.id) { queueCarryOn(wish) }
            // A request paused for this Reload (`pause`) goes on once the app is given back: here when the turn is
            // already over, else when it ends (`finish`).
            startQueued(wish)
            guard turns[project.id] === turn, !Runtime.waitsForReload(current) else { return }
            turn.reloadedByPerson = true
            turn.reloadedWhileAway = lamps
            turn.toldHeld = false
            log(current, .status, "Reopened \(current.name) with the change")
        }
        await turn.applying?.value
    }

    /// The quick path: refresh the live copy only (build.sh with LAMP_LIVE_COPY), and when the change can go in,
    /// compile just its files and put them into the open app; then build the whole app in the background, for
    /// its install when it closes. False, having changed nothing in the open app, when any of it can't be done:
    /// the build goes on the usual way, and its install decides.
    private func reloadBeforeBuilding(_ project: LampProject, command: String, env: [String: String], fingerprint: String) async -> Bool {
        reloadedBeforeBuild.remove(project.id)
        guard LiveReload.eligible(project), !macCopies(of: project).isEmpty, Self.binary(of: project, contains: "reloaded.txt"),
              !isSetAside(project) else { return false }
        // The open app already runs these sources, and their whole build is on its way: nothing more to do.
        if liveBuilds[project.id] != nil, liveBuildRuns[project.id]?.fingerprint == fingerprint {
            reloadedBeforeBuild.insert(project.id)
            return true
        }
        // A whole build of earlier sources is stale: only the newest change's build is ever installed, and waiting for
        // it held this change back by as long as it had left. It's ended, and whatever comes next builds the whole app.
        await supersedeLiveBuild(of: project)
        liveBuildFailed.remove(project.id)
        var copy = env
        copy["LAMP_LIVE"] = "1"
        copy["LAMP_LIVE_COPY"] = "1"
        guard await Self.runBuild(command, for: project, env: copy) { _ in } == 0,
              // A save being put in by itself gives way here to a build of Lamp's for newer sources (`buildNow`).
              !Task.isCancelled,
              await reloadInPlace(project, inFront: false, saysWhy: false) else { return false }
        reloadedBeforeBuild.insert(project.id)
        await DataSnapshots.wentIn(project)
        // It crashed the app meanwhile (`setAside`): nothing of it is built for installing.
        guard setAsideChanges[project.id] == nil else { reloadedBeforeBuild.remove(project.id); return false }
        // Nothing to install until the whole build is done: the copy in build/ is the one before this change. Only
        // then do these sources count as built, so a Lamp quit meanwhile builds them again (`recoverUnfinishedBuild`).
        LiveReload.installed(project)
        heldInstalls.installed(project.id)
        LiveReload.startedBuilding(project, from: fingerprint)
        var full = env
        full["LAMP_LIVE"] = "1"
        liveBuildRuns[project.id] = (nil, fingerprint)
        liveBuilds[project.id] = Task { [weak self] in
            var output: [String] = []
            let status = await Self.runBuild(command, for: project, env: full,
                                             started: { [weak self] in self?.liveBuildRuns[project.id]?.process = $0 }) { output.append($0) }
            guard let self else { return }
            self.liveBuilds[project.id] = nil
            self.liveBuildRuns[project.id] = nil
            LiveReload.finishedBuilding(project)
            // Ended for a newer change, whose own build follows: not a failure, and nothing of it counts as built.
            if self.liveBuildsSuperseded.remove(project.id) != nil { return }
            guard let current = self.current(project) else { return }
            if status == 0 {
                Runtime.markBuilt(current, from: fingerprint)
                BuildStamp.write(for: current)
                LiveReload.awaitInstall(current)
                // Waiting for the app to close; closed already (while this built), it goes in now.
                _ = self.heldInstalls.mayInstall(current.id, running: true)
                if !self.isRunning(current) { self.installHeldIcons(for: [current.id]) }
            } else {
                self.liveBuildFailed.insert(project.id)
                // The whole code was checked before the change went in, so this is rare: said in the chat, and
                // built again (with its errors for the agent) at the next request or look.
                Runtime.forgetBuilt(current)
                self.log(current, .detail, "Building all of \(current.name) after the change went in failed; it's built again next time:\n"
                         + output.suffix(30).joined(separator: "\n"))
            }
        }
        return true
    }

    /// Puts the change just built into the open Mac app, when it was built live and the change can go in that
    /// way (`LiveReload.verdict`). True when it went in: the app is updated where it is, and the build is held,
    /// to be installed when the app closes. False sends the change the usual way, by reopening the app. `saysWhy`
    /// false keeps why it couldn't go in out of the chat: the try before the build is followed by the install's,
    /// which asks again and says it, so the chat said it twice.
    private func reloadInPlace(_ project: LampProject, inFront: Bool, saysWhy: Bool = true) async -> Bool {
        // The change went in before the build (`reloadBeforeBuilding`): only the word that it did is left to say.
        // Closed since, the app is installed the usual way, from the whole build once it's done.
        if reloadedBeforeBuild.remove(project.id) != nil {
            // The glow this build began has nothing more to show: the change went in before it (by itself, as the
            // agent saved it, when this is a look's build of the same code), and the light crossed then. Without
            // this it was renewed until the turn ended.
            AppTransition.end(project)
            // Only the copy that took it: one opened again while the whole build ran starts from what was installed,
            // and is installed from the whole build as any other.
            if let app = macCopies(of: project).first, LiveReload.tookChanges(project, pid: app.processIdentifier, launched: app.launchDate) {
                if inFront {
                    app.activate()
                    log(project, .status, "\(project.name) is updated")
                }
                return true
            }
            await awaitLiveBuild(of: project)
            return false
        }
        guard LiveReload.eligible(project), let app = macCopies(of: project).first,
              Self.binary(of: project, contains: "reloaded.txt"), !isSetAside(project) else { return false }
        // The open copy isn't the one earlier changes went into (opened again since, outside Lamp): it runs what was
        // installed, which the change is judged against now.
        if !LiveReload.tookChanges(project, pid: app.processIdentifier, launched: app.launchDate) {
            LiveReload.backToInstalled(project)
        }
        var changed: [String]
        switch await LiveReload.verdict(project) {
        case .reload(let files): changed = files
        // The open app already runs these sources (a change that went in before its build, or one only of its files,
        // which a live build reads from the app's folder): it draws again, so a new picture shows.
        case .unchanged:
            LiveReload.redraw(project, token: Template.token(for: project))
            return true
        case .reopen(let why):
            turns[project.id]?.reloadWhy = LiveReload.readable(why)
            if saysWhy { log(project, .detail, "\(project.name) has to reopen for this change: \(LiveReload.readable(why)).") }
            return false
        }
        // The open app's data as its old code left it, before the new code can touch it.
        await DataSnapshots.take(project)
        note("Updating \(project.name) in place…", for: project)
        // Watched from before it's sent: a change can crash the app as it loads, before the app answers.
        let watch = watchAfterReload(project, app: app, fingerprint: Runtime.fingerprint(project))
        switch await LiveReload.put(project, changed: changed, token: Template.token(for: project)) {
        case .reopen(let why):
            // Gone as it took the change: what the watch makes of that (a crash sets the change aside) is waited
            // for, so whoever asked finds it done (`installNow`).
            if app.isTerminated { await watch.task.value; return false }
            endWatch(project, watch.token)
            turns[project.id]?.reloadWhy = why
            if saysWhy { log(project, .detail, "\(project.name) has to reopen for this change: \(why).") }
            return false
        case .went(let said):
            for line in said { log(project, .detail, line + " without reopening \(project.name).") }
            LiveReload.noteProcess(project, pid: app.processIdentifier, launched: app.launchDate)
        }
        // A change that went in replaces one set aside before it.
        setAsideChanges[project.id] = nil
        if reloadWatches[project.id]?.token == watch.token { reloadWatches[project.id]?.until = Date().addingTimeInterval(Self.crashWatch) }
        AppTransition.land(project)
        turns[project.id]?.shown.append(Date())
        // The live library was made from the same sources as a build waiting for Reload, so that change is in too:
        // nothing is held from the app any more (the app's Reload button and the chat's line go, and `use_app` is
        // allowed again), and the agent hears it, since `reloadNote` told it to wait. Here, not at the install: a
        // look's change goes in before its build (`reloadBeforeBuilding`), and the look would otherwise still find
        // the wait and say to press Reload. The build still goes in when the app closes (`awaitInstall`).
        if Runtime.waitsForReload(project) || Runtime.holdsBuild(project) {
            Runtime.releaseBuild(project)
            Self.tellReload(project, on: false)
            turns[project.id]?.endedReloadWait = true
        }
        LiveReload.awaitInstall(project)
        _ = heldInstalls.mayInstall(project.id, running: true)
        noteOpened(true, for: project)
        if inFront {
            app.activate()
            log(project, .status, "\(project.name) is updated")
        }
        refreshOpenApps()
        return true
    }

    /// The safety net under a live change: if the app crashes as the change goes in, or in the half minute after, the
    /// change didn't suit it, and it's set aside (`setAside`). Only a crash, which leaves macOS's report: an app quit on
    /// purpose (its Quit, Lamp's Stop) stays closed. Begun before the change is sent and lasting until it's answered,
    /// then for `crashWatch` more; a newer change's watch takes over from it.
    private func watchAfterReload(_ project: LampProject, app: NSRunningApplication, fingerprint: String) -> (token: UUID, task: Task<Void, Never>) {
        let since = Date(), token = UUID()
        reloadWatches[project.id] = (token, nil)
        // The turn the change went in under: a Stop pressed in it holds however late the report comes, after the
        // turn has ended or another has begun.
        let origin = turns[project.id]
        let task = Task { [weak self] in
            while let watch = self?.reloadWatches[project.id], watch.token == token, (watch.until ?? .distantFuture) > Date() {
                guard app.isTerminated else {
                    try? await Task.sleep(for: .milliseconds(500))
                    continue
                }
                // macOS writes the report after the process is gone, sometimes ten seconds or more later, and the
                // crash is this watch's alone to answer (`appEnded` leaves it), so it waits as long as that does.
                var crash: String?
                for _ in 0..<60 where crash == nil {
                    crash = Runtime.crash(of: project, since: since)
                    if crash == nil { try? await Task.sleep(for: .milliseconds(500)) }
                }
                if let crash { await self?.setAside(project, crash: crash, fingerprint: fingerprint, afterStop: origin?.wasStopped == true) }
                break
            }
            self?.endWatch(project, token)
        }
        return (token, task)
    }

    /// How long after a change went into the open app a crash is taken for the change's.
    private static let crashWatch: TimeInterval = 30

    /// A watch is over: the app's close it held back gets what was waiting for it (`installHeldIcons`).
    private func endWatch(_ project: LampProject, _ token: UUID) {
        guard reloadWatches[project.id]?.token == token else { return }
        reloadWatches[project.id] = nil
        installHeldIcons(for: [project.id])
    }

    /// Each open app's watch on the change last put into it (`watchAfterReload`), and until when it lasts: nil while
    /// the change is still going in. While one lasts, the app's going is the watch's to answer, and nothing waiting for
    /// it to close is installed: that may be the build of the very change that crashed it.
    private var reloadWatches: [String: (token: UUID, until: Date?)] = [:]

    /// A change that crashed the open app, by the sources it was made from, and what the agent is told of it.
    struct SetAside {
        let fingerprint: String
        let crash: String
        /// The agent has heard of it: from its look, use_app or the turn's end, a fix Lamp started, or the note on
        /// the next request (`turn`). Set only once one of those has it.
        var told = false
        /// Stop was pressed in the turn it crashed under: no fix starts by itself; the next request carries it.
        var afterStop = false
    }
    private var setAsideChanges: [String: SetAside] = [:]

    /// Whether the app's sources are those of a change that crashed it, which aren't put into it again.
    private func isSetAside(_ project: LampProject) -> Bool {
        setAsideChanges[project.id]?.fingerprint == Runtime.fingerprint(project)
    }

    /// A change put into the open app crashed it. The copy in the apps folder, the last version the person had
    /// working, opens again on the same data (what was unsaved in the crashed copy went with it), nothing of the change
    /// is installed, and the person is told. The agent hears of it with its next look or use_app, or at the turn's end,
    /// which tries its fix as a crash on launch is (`installNow`); after a turn that never told it, a fix starts
    /// (`fixHeldCrash`). Until it has heard, no save of its is put into the app by itself (`autoApply`).
    private func setAside(_ project: LampProject, crash: String, fingerprint: String, afterStop: Bool) async {
        guard let project = current(project) else { return }
        // Its whole build, finished or not, isn't what the app is: ended, and nothing of it counts as built or waits to
        // be installed.
        await supersedeLiveBuild(of: project)
        liveBuildFailed.insert(project.id)
        reloadedBeforeBuild.remove(project.id)
        Runtime.forgetBuilt(project)
        LiveReload.installed(project)
        heldInstalls.installed(project.id)
        LiveReload.backToInstalled(project)
        // A build held for Reload is older than the change, or is it: either way the version opened again is what
        // the person has, and Reload would put the crash back in.
        if Runtime.holdsBuild(project) {
            Runtime.releaseBuild(project)
            Self.tellReload(project, on: false)
            reloadWhenFree.remove(project.id)
            away.dropped(project.id)
        }
        setAsideChanges[project.id] = SetAside(fingerprint: fingerprint, crash: "It crashed as the change went into the open app, "
            + "so Lamp set the change aside and opened the app as it was last installed, which doesn't have the changes "
            + "that went into it live since then: they're still in the code and go in again with the next change.\n\n" + crash,
            // After Stop, nothing more is done for the request, a fix included: the person says what's next.
            afterStop: afterStop || turns[project.id]?.wasStopped == true)
        log(project, .error, ErrorMessages.setAside(project.name))
        log(project, .detail, crash)
        if !isRunning(project), FileManager.default.fileExists(atPath: project.installedURL.path) {
            let config = NSWorkspace.OpenConfiguration()
            config.arguments = ["-LampInFront", "YES"]   // see install
            do {
                _ = try await NSWorkspace.shared.openApplication(at: project.installedURL, configuration: config)
                noteOpened(true, for: project)
            } catch {
                log(project, .error, ErrorMessages.openFailed(error.localizedDescription))
                noteOpened(false, for: project)
            }
            refreshOpenApps()
        }
        if turns[project.id] == nil { fixHeldCrash(project) }
    }

    /// The change set aside, for the agent, once.
    private func untoldSetAside(_ project: LampProject) -> String? {
        guard let aside = setAsideChanges[project.id], !aside.told else { return nil }
        setAsideChanges[project.id]?.told = true
        return aside.crash
    }

    /// Installs and opens the app. Returns what's known about the failure if it died straight away.
    /// `inFront` is false for the agent's looks, which shouldn't pull the app in front of the user mid-turn.
    /// `fresh` closes an open Mac app and opens it again even when the change could go into it as it runs.
    /// `early` returns as soon as the app has shown itself rather than once its first seconds have passed: for a look,
    /// which tells of a death after that with its next answer (`lateCrash`).
    /// `saysReady` false keeps "… is ready" out of the chat, for a reopen in the middle of a request (`reloadInTurn`),
    /// whose end says what the request came to.
    /// `onDevice`: a look the agent asked to see on the device itself, which a kind with a preview otherwise opens there.
    private func install(_ project: LampProject, inFront: Bool = true, fresh: Bool = false, reload: Bool = false,
                         early: Bool = false, saysReady: Bool = true, onDevice: Bool = false) async -> String? {
        let crash = await installNow(project, inFront: inFront, fresh: fresh, reload: reload, early: early, saysReady: saysReady, onDevice: onDevice)
        // Whatever didn't put the change into the open app (it waits for Reload, was kept open, reopened, failed)
        // lets the glow go; a reopened copy gets the light once its window is up (`AppTransition.landWhenShown`).
        AppTransition.end(project)
        return crash
    }

    private func installNow(_ project: LampProject, inFront: Bool, fresh: Bool, reload: Bool, early: Bool, saysReady: Bool, onDevice: Bool) async -> String? {
        guard exists(project), project.holdsApp else { return nil }
        // The turn this install belongs to, taken before the icon wait: a Stop during it can end the turn
        // and start the next one's, which must not inherit this launch.
        let owner = turns[project.id]
        if project.onDevice {
            await prepareIcon(project)
            guard let owner, turns[project.id] === owner, !owner.stopped else { return "The app was stopped before it opened." }
            // The agent's looks go to the preview on this Mac when the device's kind has one; Play puts it on the device.
            if !inFront, !onDevice, let folder = DeviceApps.previewFolder(for: project) { return await openDevicePreview(project, folder: folder) }
            return await installOnDeviceApp(project, inFront: inFront, owner: owner)
        }
        if project.onTV {
            await prepareIcon(project)
            guard let owner, turns[project.id] === owner, !owner.stopped else { return "The app was stopped before it opened." }
            return await installOnTV(project, inFront: inFront)
        }
        if project.onAndroid {
            await prepareIcon(project)
            guard let owner, turns[project.id] === owner, !owner.stopped else { return "The app was stopped before it opened." }
            let problem = await installOnAndroid(project, owner: owner, inFront: inFront)
            upgradeIconArt(project)
            return problem
        }
        if project.onIOS {
            await prepareIcon(project)
            guard let owner, turns[project.id] === owner, !owner.stopped else { return "The app was stopped before it opened." }
            // The person's own phone gets the app when they press Play or a change is finished; the agent's
            // looks (not in front) stay on the simulator, which is the only screen Lamp can see.
            let problem = if inFront, let udid = project.device {
                await installOnDevice(project, owner: owner, udid: udid)
            } else {
                await installOnSimulator(project, owner: owner, inFront: inFront, early: early)
            }
            // As for a Mac app below: the artwork asked for while the icon was designed, before there was
            // an app, is asked for again now there is one (an icon drawn by hand is only offered then).
            upgradeIconArt(project)
            // As on the Mac: the widget is built, and adding it to the home screen is the person's to do.
            // Only for a widget to add: Live Activities alone show by themselves and aren't among the widgets.
            if problem == nil, Template.hasHomeScreenWidget(project), WidgetCard.isNeeded(after: logs[project.id] ?? []) { log(project, .widget, "") }
            return problem
        }
        // In a new app's first turn its chat may already be beside it (`present`): whatever this install comes to (the
        // app open again, a crash, a failed install, a pass that took its window away), the chat is still somewhere.
        defer { if progress[project.id]?.newApp == true { Task { await MagicPanel.shared.keepChatInSight(project) } } }
        // An app gone while a change that went into it is watched may have crashed with it, which macOS can take
        // seconds to report: what the watch makes of it decides what's installed (`setAside`), so it's waited for.
        while reloadWatches[project.id] != nil, !isRunning(project) { try? await Task.sleep(for: .milliseconds(250)) }
        // A change that can go into the open app goes in there, keeping what's on screen; the build waits to be
        // installed until the app closes (LiveReload).
        // The icon isn't part of such a change, so it doesn't wait for it: it's drawn meanwhile, ready for the next copy.
        if !fresh, await reloadInPlace(project, inFront: inFront) {
            owner?.updatedInPlace = true
            owner?.outcomes.append(.live)
            owner?.reloadWhy = nil
            await DataSnapshots.wentIn(project)
            prepareIconMeanwhile(project)
            return nil
        }
        // A change that crashed the open app as it went in isn't installed over the version the person has back. Its
        // crash is the answer, as a crash on launch is: the turn's end has the agent fix it, a look tells it. Not when
        // a fresh start is asked for: the crash may have been the change's going in, which a fresh start doesn't do.
        if !fresh, !reload, isSetAside(project), let crash = untoldSetAside(project) ?? setAsideChanges[project.id]?.crash {
            return crash
        }
        await prepareIcon(project)
        // A whole build after an early change may still be writing build/: what's installed is what it makes,
        // and nothing when it failed (build/ is the version before the change).
        await awaitLiveBuild(of: project)
        if liveBuildFailed.contains(project.id) {
            let problem = "\(project.name) couldn't be built as a whole after its last change, so it wasn't installed. It's built again with the next request."
            log(project, .error, problem)
            return problem
        }
        // A request's change the open app can't take as it runs doesn't close it under the person: it waits for
        // them to press Reload, in the app's title bar or the chat (`awaitReload`). Open App, Undo and Reload itself
        // ask for the reopen, and an app that's closed just gets the build. Not in a new app's first turn: nobody is
        // using it yet, and it's built in passes for the person to watch each one go in (`present`), so it reopens.
        if !reload, asksBeforeReopening(project, owner: owner) {
            awaitReload(project, owner: owner)
            owner?.outcomes.append(.held)
            return nil
        }
        // Asked once in a turn: a second build in it leaves the app the person kept open alone.
        let asked = owner?.keptOpen == true && isRunning(project)
        let wasOpen = isRunning(project)
        // The new copy is put together and signed in Lamp's own folder while the old one is still open, so the app is
        // closed only for the swap. Nothing of the installed copy is touched until it has closed.
        var staged: SignedCopy?
        if !asked {
            note("Installing \(project.name)…", for: project)
            do {
                staged = try await stageSigned(project)
            } catch {
                log(project, .error, ErrorMessages.installFailed(error.localizedDescription))
                owner?.didNotOpen = true
                noteOpened(false, for: project)
                return nil
            }
        }
        guard !asked, let copy = staged, await quit(project, for: owner, only: .mac) else {
            staged?.discard()
            // The person kept the app open, with whatever it holds. It isn't replaced under them (HeldInstalls
            // says what that breaks, too): the build waits, and goes in when the app closes.
            // Kept open after Reload was pressed, or when Undo, a restore or Rebuild & Open asked it to close: the
            // Reload button is there for when they're ready, as after a request's change.
            if reload || (owner?.request == nil && !Template.isWidgetOnly(project)) { awaitReload(project, owner: owner); return nil }
            Runtime.holdBuild(project)
            _ = heldInstalls.mayInstall(project.id, running: true)
            if !asked { log(project, .status, ErrorMessages.stayedOpen(project.name)) }
            owner?.keptOpen = true
            owner?.didNotOpen = true
            noteOpened(false, for: project)
            refreshOpenApps()
            return nil
        }
        guard exists(project) else { copy.discard(); return nil }   // deleted while its old copy was quitting
        // The old copy glowed while this was built, or this is the change it held for Reload (its glow let go when
        // the change was held): the new copy, with the change, shows it going in.
        let glowed = AppTransition.isGlowing(project.id) || reload
        owner?.didNotOpen = false
        owner?.updatedInPlace = false
        do {
            WidgetCard.forget(project)
            // With the old copy closed, its data is quiet: copied before the new one opens on it.
            await DataSnapshots.take(project)
            try await swapIn(copy, for: project)
            await DataSnapshots.wentIn(project)
            heldInstalls.installed(project.id)
            Runtime.releaseBuild(project)
        } catch {
            log(project, .error, ErrorMessages.installFailed(error.localizedDescription))
            owner?.didNotOpen = true
            noteOpened(false, for: project)
            return nil
        }
        // An app with a widget gets its card, once: the widget is built, and adding it is the person's to do.
        if project.platform == .mac, Template.hasWidget(project), WidgetCard.isNeeded(after: logs[project.id] ?? []) { log(project, .widget, "") }
        // An app that is only its widget is never opened in front of anyone: there's nothing to see. It runs
        // out of sight to tell Lamp when the widget has been placed, and quits by itself.
        if Template.isWidgetOnly(project) {
            await watchWidget(of: project)
            // In place is all there is to it: a card that said it didn't get there says so no longer.
            noteOpened(true, for: project)
            if inFront { log(project, .status, "\(project.name) is ready") }
            upgradeIconArt(project)
            refreshOpenApps()
            stamps[project.id] = BuildStamp.read(project.installedURL)
            return nil
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = inFront
        // An app that lives in the menu bar opens its panel, so there's something to see (LampMenuBar).
        if inFront { config.arguments = ["-LampInFront", "YES"] }
        note("Opening \(project.name)…", for: project)
        var crash: String?
        do {
            let opened = Date()
            let app = try await NSWorkspace.shared.openApplication(at: project.installedURL, configuration: config)
            let watch = watchLaunch(project, owner: owner, opened: opened, crashOnly: true, alive: { !app.isTerminated }) {
                await Runtime.launchReport(project)
            }
            // A look goes on once the app has pictured its window; anything else waits its first seconds out, since what
            // it does next (a fix at the turn's end, the chat's "ready") depends on how they went.
            if early ? await watch.untilShown(project) : await watch.verdict() != nil {
                watch.told = true
                crash = watch.crash
            } else {
                noteOpened(true, for: project)
                owner?.outcomes.append(wasOpen ? .reopened : .opened)
                owner?.shown.append(Date())
                if inFront, saysReady { log(project, .status, "\(project.name) is ready") }
                if glowed { AppTransition.landWhenShown(project, app: app) }
            }
        } catch {
            log(project, .error, ErrorMessages.openFailed(error.localizedDescription))
            owner?.didNotOpen = true
            noteOpened(false, for: project)
        }
        upgradeIconArt(project)
        refreshOpenApps()
        stamps[project.id] = BuildStamp.read(project.installedURL)
        return crash
    }

    /// The iPhone counterpart of `install`: the built app goes into the booted simulator and is launched there,
    /// with what it prints going to the same log the Mac apps use. Returns what's known if it died at once.
    /// Opens a TV app in the TV preview, or, when Play asked for it with a TV chosen under Try On, packages it and puts it
    /// on that TV. Nil when it's open; else what went wrong.
    private func installOnTV(_ project: LampProject, inFront: Bool) async -> String? {
        let staged = TVs.stagingFolder(for: project).appendingPathComponent("web")
        if inFront, let id = project.device {
            guard let record = TVs.record(id) else {
                let problem = "Lamp can't find the TV chosen under Try On on the network. Turn it on, or choose the TV preview."
                log(project, .error, problem)
                return problem
            }
            // What the staged copy was made from, taken before the upload: an edit meanwhile isn't on the TV.
            let stagedFrom = Runtime.builtFingerprint(project)
            let say: @Sendable (String) -> Void = { [weak self] text in Task { @MainActor in self?.note(text, for: project) } }
            // The app opened by this install asks for its token, which isn't in its package, and a wish's app for its
            // wish's key: that claim is open again once the app is open, since an install can take longer than it lasts.
            DeviceSupport.Claims.shared.open(project.id, from: record.address)
            let claimsKey = Template.talksToOtherApps(project)
            if claimsKey { WishClaims.shared.open(project.id, from: record.address) }
            do {
                if record.isSamsung { try await TVs.installSamsung(project, staged: staged, on: record, say: say) }
                else { try await TVs.installLG(project, staged: staged, on: record, say: say) }
                if claimsKey { WishClaims.shared.renew(project.id, from: record.address) }
                Runtime.putOnTV(project, tv: record.id, staged: stagedFrom)
                log(project, .status, "\(project.name) is open on \(record.name).")
                return nil
            } catch {
                log(project, .error, error.localizedDescription)
                return error.localizedDescription
            }
        }
        note("Opening \(project.name) in the TV preview…", for: project)
        let problem = await TVPreview.show(project, staged: staged, inFront: inFront)
        refreshOpenApps()
        syncLocalNetwork()   // its phone page reaches phones over the Wi‑Fi
        return problem
    }

    /// `look_at_app` for a TV app: the preview pictured at half the TV's size and read as text, with what it printed.
    private func lookOnTV(_ project: LampProject, turn: Turn, changed: Bool, reopen: Bool) async -> (Int, [String: Any]) {
        let device = previewDevice(project)
        var summary = "The app is open in the \(device) preview on this Mac."
        // A device app's preview may show an older build than the last one: a look on the device builds without opening it here.
        let stale = project.hasDevice && previewBuilt[project.id] != Runtime.builtFingerprint(project)
        if changed || stale || !TVPreview.isOpen(project) || reopen {
            // A screen not pointed at a TV opens in the preview by itself; its install is its Mac or iPad app's.
            let problem = ScreenKit.isScreen(project) && !project.onTV ? await openDevicePreview(project, folder: TVTemplate.webFolder)
                : await install(project, inFront: false, early: true)
            turn.look.installed[project.id] = true
            if let problem { return (200, ["text": "The app didn't open in the \(device) preview on this Mac.\n\n\(problem)"]) }
            summary = changed ? "The app was opened again in the \(device) preview on this Mac with your changes." : "The app was opened again in the \(device) preview on this Mac, so it started fresh."
        } else {
            summary = "The app is open in the \(device) preview on this Mac with your latest code; nothing needed opening again."
        }
        note("Looking at \(project.name)", for: project)
        if progress[project.id]?.newApp == true, !turn.look.presented {
            turn.look.presented = true
            TVPreview.bringForward(project)
        }
        var screenshots: [URL] = []
        let picture = Runtime.folder(project).appendingPathComponent("screenshot.png")
        let taken = await TVPreview.picture(project)
        if let taken, (try? AppFolder.write(taken.png, to: picture, in: project.dir)) != nil { screenshots = [picture] }
        var text = summary + " " + Self.notTheDevice(device) + " It shows the 1920×1080 page at half size: a pixel in the picture is two of the page's. "
            + (screenshots.isEmpty ? "No picture of it could be taken." : Privacy.sharesPictures ? "A picture of the \(device) preview follows. Points for use_app are pixels in it." : Privacy.picturesOff)
        if let taken, !screenshots.isEmpty, Privacy.sharesPictures {
            text += " " + TVPreview.takenNote(taken)
            if !taken.moving { text += " " + TVPreview.stillNote }
        }
        if !Privacy.sharesLog { text += " " + Privacy.logOff }
        if Privacy.sharesPictures { text += "\n\n" + TVPreview.text(await TVPreview.items(project)) }
        if Privacy.sharesLog, let tail = Runtime.logTail(project) { text += "\n\nWhat the \(device) preview's console printed:\n\(tail)" }
        return (200, ["text": text, "screenshots": Self.agentPictures(screenshots, in: project)])
    }

    /// Said with every look at a preview: one at a TV's size reads like the TV itself (or the Xbox), and the agent would
    /// tell the person how the app runs on a device it has never seen.
    static func notTheDevice(_ device: String) -> String {
        "This is the \(device) preview, a window on this Mac, not the person's \(device): it runs in this Mac's browser, so what it shows, its speed "
            + "included, is the preview's" + (device == "TV" ? "." : ", and Play puts the app on the \(device) itself.")
    }

    /// `use_app` for a TV app: the remote's keys and clicks on the preview, the screen read between them.
    private func useOnTV(_ project: LampProject, actions: [[String: Any]], json: String) async -> (Int, [String: Any]) {
        let device = previewDevice(project)
        guard TVPreview.isOpen(project) else { return (200, ["text": "The app isn't open. Call look_at_app first: it opens the app in the \(device) preview."]) }
        guard let owner = turns[project.id] else { return (409, ["error": "Lamp isn't working on this app right now."]) }
        if owner.tookOver { return (200, ["text": Self.tookOverNote]) }
        guard let data = json.data(using: .utf8), let decoded = try? JSONDecoder().decode([Simulator.Driver.Action].self, from: data) else {
            return (400, ["error": "use_app needs a list of actions."])
        }
        // In plain sight, with Stop and Esc, and the person's own click or key in the preview taking it back.
        // Taking over is remembered for the turn the moment it happens, whatever this call is waiting on then.
        let trial = Handover(label: "\(Self.lampName) is trying it in the \(device) preview", lampWindow: TVPreview.window(project)) { [weak self] in
            guard let self, !owner.tookOver else { return }
            owner.tookOver = true
            log(project, .status, Self.stoppedByYou)
        }
        if let window = TVPreview.window(project) { trial.show(window: CGWindowID(window.windowNumber)) }
        defer { trial.end() }
        let report = await TVPreview.perform(decoded, on: project) { [weak self] in
            guard let self else { return false }
            return exists(project) && turns[project.id] === owner && !owner.stopped && !trial.tookOver && TVPreview.isOpen(project)
        }
        var text = "What happened in the \(device) preview on this Mac, not on the person's \(device):\n\(report)"
        if owner.tookOver { return (200, ["text": text + "\n\n" + Self.tookOverNote]) }
        if Runtime.sourcesChanged(project) {
            text += "\n\nThis is the app as last opened: it doesn't have the changes you've made to the code since. Call look_at_app to open them."
        }
        var screenshots: [URL] = []
        let picture = Runtime.folder(project).appendingPathComponent("screenshot.png")
        if Privacy.sharesPictures {
            text += "\n\n" + TVPreview.text(await TVPreview.items(project))
            let taken = await TVPreview.picture(project)
            if let taken, (try? AppFolder.write(taken.png, to: picture, in: project.dir)) != nil { screenshots = [picture] }
            text += "\n\nA picture of the \(device) preview follows. Points for the next use_app are pixels in it."
            if let taken, !screenshots.isEmpty {
                text += " " + TVPreview.takenNote(taken)
                if !taken.moving { text += " " + TVPreview.stillNote }
            }
        }
        if Privacy.sharesLog, let tail = Runtime.logTail(project) { text += "\n\nWhat the \(device) preview's console printed:\n" + tail }
        // Taken back during the reads above: the agent is told now, not at its next call.
        if owner.tookOver { text += "\n\n" + Self.tookOverNote }
        return (200, ["text": text, "screenshots": Self.agentPictures(screenshots, in: project)])
    }

    /// Device apps put on a device since Lamp opened, by app: the device, and the log read from it.
    private var deviceRuns: [String: DeviceApps.Run] = [:]
    /// Devices an app is being put on now, by id.
    private var installingOn: Set<String> = []
    /// Apps being put on a device now, by id: deleting one waits for that to settle before taking it off again.
    private var installingApps: Set<String> = []
    /// What each device app's run on its device was built from, so a look that went to the preview on this Mac isn't
    /// taken for the device having the change.
    private var deviceRunBuilt: [String: String] = [:]

    /// The device a device app goes on now: the one chosen, or the only one its integration finds, looked for again
    /// when the list hasn't got it yet.
    private func deviceForApp(_ project: LampProject) async -> Device? {
        if let device = DeviceApps.device(for: project, among: devices), device.connected { return device }
        guard let integration = DeviceApps.integration(for: project) else { return nil }
        let scan = Integrations.Scan(answers: await DeviceProbe.ssdp("ssdp:all", seconds: 2))
        var found: [Device] = []
        for address in await Integrations.addresses(for: integration, scan: scan) {
            if let device = await Integrations.identify(integration, at: address) { found.append(device) }
        }
        for device in found { devices.removeAll { $0.id == device.id }; devices.append(device) }
        return DeviceApps.device(for: project, among: devices)
    }

    /// Puts a device app on the person's device and opens it there, through its integration's bridge. A device not set
    /// up yet gets its next step in the chat instead. Nil when it's open; else what went wrong.
    /// A device app opened in the preview on this Mac, from a copy of its kind's preview folder (`TVs.stage`, as a TV
    /// app's): what the agent looks at and plays. Its LampAI reaches Lamp through the preview, as a TV app's does.
    private func openDevicePreview(_ project: LampProject, folder: String) async -> String? {
        let device = previewDevice(project)
        do {
            let built = Runtime.builtFingerprint(project)
            let staged = try await TVs.stage(project, folder: folder)
            previewBuilt[project.id] = built
            note("Opening \(project.name) in the \(device) preview…", for: project)
            let problem = await TVPreview.show(project, staged: staged, inFront: false, device: device)
            refreshOpenApps()
            return problem
        } catch {
            log(project, .error, error.localizedDescription)
            return error.localizedDescription
        }
    }

    /// Which build each device app's preview on this Mac was opened from, as `deviceRunBuilt` is for the device.
    private var previewBuilt: [String: String] = [:]

    /// What a preview on this Mac stands in for, as the person calls it: a TV, or a device app's device ("Xbox").
    private func previewDevice(_ project: LampProject) -> String {
        project.onTV || ScreenKit.isScreen(project) ? "TV" : DeviceApps.integration(for: project)?.name ?? "device"
    }

    private func installOnDeviceApp(_ project: LampProject, inFront: Bool, owner: Turn) async -> String? {
        let name = DeviceApps.integration(for: project)?.name ?? "device"
        guard let device = await deviceForApp(project) else {
            let problem = project.device == nil
                ? "Lamp hasn't found exactly one \(name) on your network. Turn yours on, then choose it under Try On."
                : "Lamp can't find the \(name) chosen under Try On on your network. Make sure it's on."
            log(project, .error, problem)
            return problem
        }
        if let step = Integrations.next(for: device) {
            // The card goes under the latest request, where the person is reading: one left further up, from setting the
            // device up before, would be out of sight, and two would show the same step twice.
            let lines = logs[project.id] ?? []
            let lastRequest = lines.lastIndex { $0.kind == .user } ?? -1
            if !lines.indices.contains(where: { $0 > lastRequest && lines[$0].kind == .deviceStep && lines[$0].text == device.id }) {
                logs[project.id]?.removeAll { $0.kind == .deviceStep && $0.text == device.id }
                log(project, .deviceStep, device.id)
            }
            // Nothing runs while the card waits for the person; once its last step passes, the app goes on the device.
            DeviceSetupModel.for(device).then = { [weak self] in
                guard let self, let now = current(project) else { return }
                Task { await self.run(now) }
            }
            return "\(device.name) isn't set up for apps yet. Its next step, \"\(step.title)\", is a card in the chat for the person to follow."
        }
        // One app at a time goes on a device: a second waits for the first, then takes the device from it.
        while installingOn.contains(device.id) { try? await Task.sleep(for: .milliseconds(300)) }
        installingOn.insert(device.id)
        installingApps.insert(project.id)
        defer { installingOn.remove(device.id); installingApps.remove(project.id) }
        let stillWanted: @MainActor () -> Bool = { [weak self] in self?.turns[project.id] === owner && !owner.stopped }
        guard stillWanted() else { return "Stopped." }
        // The device is this app's from the upload on: every run there (another wish's, or this one's last) is over,
        // so a look or a key in flight for it stops rather than reaching what replaces it.
        for (id, other) in deviceRuns where id == project.id || other.device.id == device.id {
            other.end()
            deviceRuns[id] = nil
        }
        refreshOpenApps()
        note("Putting \(project.name) on \(device.name)…", for: project)
        try? AppFolder.write(Data(), to: Runtime.logURL(project), in: project.dir)
        let file = try? AppFolder.appendHandle(Runtime.logURL(project), in: project.dir)
        do {
            let built = Runtime.builtFingerprint(project)
            let run = try await DeviceApps.install(project, on: device, log: file, stillWanted: stillWanted)
            guard stillWanted() else { run.end(); return "Stopped." }
            deviceRuns[project.id] = run
            deviceRunBuilt[project.id] = built
            refreshOpenApps()
            if inFront { log(project, .status, "\(project.name) is open on \(device.name).") }
            return nil
        } catch {
            if (error as? DeviceTLS.Refusal) == .changed || error.localizedDescription == DeviceTLS.Refusal.changed.localizedDescription {
                // Only the person can tell a reset device from another posing as it: the reconnect card goes in the chat,
                // and once they've reconnected and set it up again, the app goes on it.
                let model = DeviceSetupModel.for(device)
                model.noteCertificateChanged()
                logs[project.id]?.removeAll { $0.kind == .deviceStep && $0.text == device.id }
                log(project, .deviceStep, device.id)
                model.then = { [weak self] in
                    guard let self, let now = current(project) else { return }
                    Task { await self.run(now) }
                }
                return "\(device.name) shows another certificate than the one Lamp set it up with, so nothing was sent to it. A card in the chat lets the person reconnect it."
            }
            log(project, .error, error.localizedDescription)
            return error.localizedDescription
        }
    }

    /// `look_at_app` for a device app: put on the device when it changed, then the device's own picture of its screen,
    /// what it answered to the install and what the app printed.
    /// A kind with a preview is looked at there unless the look asks for the device itself (`on_device`), which is how its
    /// real speed and log are seen.
    private func lookOnDeviceApp(_ project: LampProject, turn: Turn, changed: Bool, reopen: Bool, onDevice: Bool = false) async -> (Int, [String: Any]) {
        if DeviceApps.previewFolder(for: project) != nil, !onDevice { return await lookOnTV(project, turn: turn, changed: changed, reopen: reopen) }
        let name = DeviceApps.integration(for: project)?.name ?? "device"
        var summary: String
        // What the device runs may be older than what was built since: a look in the preview builds without putting it there.
        let stale = deviceRunBuilt[project.id] != Runtime.builtFingerprint(project)
        if changed || stale || deviceRuns[project.id] == nil || reopen {
            let problem = await install(project, inFront: false, early: true, onDevice: true)
            turn.look.installed[project.id] = true
            if let problem {
                return (200, ["text": "The app isn't on the \(name).\n\n\(problem)\n\nWhen it's a step for the person, say in a sentence that "
                              + "their \(name) needs it first and that the card in the chat shows how, then end: don't repeat the steps."])
            }
            summary = changed ? "Lamp put the app on the \(name) with your changes and opened it." : "Lamp opened the app on the \(name) again, so it started fresh."
        } else {
            summary = "The app is open on the \(name) with your latest code; nothing needed putting on it again."
        }
        guard let run = deviceRuns[project.id] else { return (200, ["text": summary]) }
        note("Looking at \(project.name)", for: project)
        var text = summary + " " + (await deviceAppPicture(project, run: run))
        if let answer = run.installAnswer, !answer.isEmpty { text += "\n\nWhat the \(name) answered when the app was put on it:\n\(answer)" }
        if !Privacy.sharesLog { text += " " + Privacy.logOff }
        if Privacy.sharesLog, let kept = try? await DeviceApps.log(project, on: run.device) {
            // The app's own log, read from the device: what a game logged, and how it kept to its frames.
            let tail = kept.split(separator: "\n", omittingEmptySubsequences: false).suffix(60).joined(separator: "\n").trimmed
            text += tail.isEmpty ? "\n\nIt has logged nothing yet." : "\n\nWhat it logged on the \(name):\n\(tail)"
        } else if Privacy.sharesLog, let tail = Runtime.logTail(project, lines: 60) { text += "\n\nWhat it printed (the device's log):\n\(tail)" }
        let picture = Runtime.folder(project).appendingPathComponent("screenshot.png")
        return (200, ["text": text, "screenshots": Self.agentPictures(FileManager.default.fileExists(atPath: picture.path) ? [picture] : [], in: project)])
    }

    /// Takes the device's picture of its screen into the app's runtime folder, and says what it is.
    private func deviceAppPicture(_ project: LampProject, run: DeviceApps.Run) async -> String {
        let device = run.device
        let picture = Runtime.folder(project).appendingPathComponent("screenshot.png")
        AppFolder.remove(picture, in: project.dir)
        guard Privacy.sharesPictures else { return Privacy.picturesOff }
        do {
            let data = try await DeviceApps.picture(project, on: device)
            // Another app put on the device while the picture was taken would be in it: it isn't this app's screen.
            guard deviceRuns[project.id] === run else { return "\(device.name) shows another app now, so no picture of this one could be taken." }
            guard let png = DeviceApps.png(data), (try? AppFolder.write(png.data, to: picture, in: project.dir)) != nil else {
                return "\(device.name)'s picture of its screen couldn't be read."
            }
            return "A picture of \(device.name)'s whole screen follows, \(png.width)×\(png.height) pixels, as the device took it."
        } catch {
            return "No picture of the screen could be taken: \(error.localizedDescription)"
        }
    }

    /// `use_app` for a device app: the remote's keys, pressed through the integration's bridge, and waits; then the
    /// screen again.
    private func useOnDeviceApp(_ project: LampProject, actions: [[String: Any]], json: String) async -> (Int, [String: Any]) {
        if DeviceApps.previewFolder(for: project) != nil { return await useOnTV(project, actions: actions, json: json) }
        let name = DeviceApps.integration(for: project)?.name ?? "device"
        guard let run = deviceRuns[project.id] else { return (200, ["text": "The app isn't on the \(name). Call look_at_app first: it puts it there and opens it."]) }
        guard let owner = turns[project.id] else { return (409, ["error": "Lamp isn't working on this app right now."]) }
        let keys = DeviceApps.keys(for: project)
        guard !keys.isEmpty, DeviceApps.integration(for: project)?.bridge?.use != nil else {
            return (200, ["text": "Lamp can't press the \(name)'s keys: its integration doesn't say how."])
        }
        var report: [String] = []
        for action in actions {
            guard turns[project.id] === owner, !owner.stopped else { report.append("Stopped."); break }
            guard deviceRuns[project.id] === run else { report.append("Another app was put on the \(name) meanwhile, so nothing more was pressed."); break }
            let kind = action["action"] as? String ?? ""
            if kind == "wait" {
                let seconds = min(max(action["amount"] as? Double ?? 1, 0.2), 10)
                try? await Task.sleep(for: .seconds(seconds))
                report.append("Waited \(seconds.formatted()) s.")
            } else if kind == "key", let key = (action["key"] as? String)?.lowercased() {
                do {
                    try await DeviceApps.press(key, in: project, on: run.device)
                    report.append("Pressed \(key).")
                    // The device draws what the key did before the next one, as a person's pace would let it.
                    try? await Task.sleep(for: .milliseconds(400))
                } catch {
                    report.append("Couldn't press \(key): \(error.localizedDescription)")
                    break
                }
            } else {
                report.append("\(kind.isEmpty ? "That" : kind) isn't something a \(name) does: only `key` (\(keys.joined(separator: ", "))) and `wait`.")
                break
            }
        }
        try? await Task.sleep(for: .seconds(1))
        var text = "What happened:\n" + report.joined(separator: "\n")
        if Runtime.sourcesChanged(project) {
            text += "\n\nThis is the app as last put on the \(name): it doesn't have the changes you've made to the code since. Call look_at_app to put them there."
        }
        guard deviceRuns[project.id] === run else { return (200, ["text": text + "\n\nThe \(name) shows another app now. Call look_at_app to put this one back."]) }
        text += "\n\n" + (await deviceAppPicture(project, run: run))
        if Privacy.sharesLog, let tail = Runtime.logTail(project) { text += "\n\nWhat it printed:\n" + tail }
        let picture = Runtime.folder(project).appendingPathComponent("screenshot.png")
        return (200, ["text": text, "screenshots": Self.agentPictures(FileManager.default.fileExists(atPath: picture.path) ? [picture] : [], in: project)])
    }

    // MARK: Games in the preview

    /// `look_at_app` for a game: built for the preview on this Mac and played from its start for two
    /// seconds, untouched; with `motion`, a frame every half second.
    private func lookAtGame(_ project: LampProject, turn: Turn, motion: Bool) async -> (Int, [String: Any]) {
        // The preview needs none of the console's tools, wherever Try On points.
        if let problem = await buildGamePreview(project, owner: turn) { return (200, ["text": problem]) }
        let script = motion ? (1...4).flatMap { [GameKit.Hold(frames: 30).line, "shot m\($0)"] } : [GameKit.Hold(frames: 120).line, "shot look"]
        GameKit.plays[project.id] = script
        let said = motion ? "Lamp played the game in the preview from its start for two seconds, no one touching the controller; a frame every half second follows, oldest first."
            : "Lamp played the game in the preview from its start for two seconds, no one touching the controller; the last frame follows."
        return await playGame(project, script: script, owner: turn, said: said, pictures: Set(script.filter { $0.hasPrefix("shot ") }.map { String($0.dropFirst(5)) }))
    }

    /// `use_app` for a game: the controller's moves added to the play so far, and the whole of it played
    /// again from the start with the code as it is now.
    private func useOnGame(_ project: LampProject, actions: [[String: Any]]) async -> (Int, [String: Any]) {
        guard let owner = turns[project.id] else { return (409, ["error": "Lamp isn't working on this app right now."]) }
        guard let play = GameKit.plays[project.id] else { return (200, ["text": "Call look_at_app first: it builds the preview and starts a play there."]) }
        let shots = play.filter { $0.hasPrefix("shot ") }.count
        let moves = GameKit.script(for: actions, startingAt: shots)
        if let problem = moves.problem { return (200, ["text": problem]) }
        if let problem = await buildGamePreview(project, owner: owner) { return (200, ["text": problem]) }
        let script = play + moves.lines
        GameKit.plays[project.id] = script
        let mine = Set(moves.lines.filter { $0.hasPrefix("shot ") }.map { String($0.dropFirst(5)) })
        let said = "What happened, played again from the start in the preview with the moves before these:\n" + moves.said.joined(separator: "\n")
            + "\n\nA picture at the end of each follows, oldest first (the last four at most)."
        return await playGame(project, script: script, owner: owner, said: said, pictures: mine)
    }

    /// The preview's build, or what stops it, in the words the agent is given.
    private func buildGamePreview(_ project: LampProject, owner: Turn) async -> String? {
        note("Building…", for: project)
        do {
            // A three.js game has nothing to compile: its page is copied where the preview reads it.
            if GameKit.engine(project) == .web { _ = try await GameKit.stageWeb(project) }
            else { try await GameKit.build(project, for: .preview, started: { [weak self] in self?.turns[project.id]?.build = $0 }) }
            turns[project.id]?.build = nil
        } catch {
            turns[project.id]?.build = nil
            return GameKit.engine(project) == .web ? error.localizedDescription
                : "The game doesn't build yet. Fix these compiler errors:\n\n" + error.localizedDescription
        }
        guard turns[project.id] === owner, !owner.stopped else { return "Stopped." }
        return nil
    }

    private func playGame(_ project: LampProject, script: [String], owner: Turn, said: String, pictures wanted: Set<String>) async -> (Int, [String: Any]) {
        note("Playing \(project.name)", for: project)
        let played: GameKit.Played
        do {
            played = GameKit.engine(project) == .web ? try await GameKit.playWeb(project, script: script)
                : try await GameKit.play(project, script: script, started: { [weak self] in self?.turns[project.id]?.build = $0 })
            turns[project.id]?.build = nil
        } catch {
            turns[project.id]?.build = nil
            return (200, ["text": error.localizedDescription])
        }
        guard turns[project.id] === owner, !owner.stopped else { return (200, ["text": "Stopped."]) }
        // What the game logged is its log, for the person's Agent Details as much as the agent.
        try? AppFolder.write(played.printed.joined(separator: "\n") + "\n", to: Runtime.logURL(project), in: project.dir)
        var text = said
        if let stats = played.stats { text += "\n\nThe preview's count: \(stats)" }
        // It names the game's sound files and comes from what the preview printed: the agent's only when the log is.
        if Privacy.sharesLog, let sound = played.sound { text += "\n\nThe preview's sound, mixed but not played: \(sound)" }
        if !Privacy.sharesLog { text += " " + Privacy.logOff }
        else { text += played.printed.isEmpty ? "\n\nThe game logged nothing." : "\n\nWhat the game logged:\n" + played.printed.suffix(40).joined(separator: "\n") }
        let pictures = Privacy.sharesPictures ? Array(played.pictures.filter { wanted.contains($0.deletingPathExtension().lastPathComponent) }.suffix(4)) : []
        if !Privacy.sharesPictures { text += " " + Privacy.picturesOff }
        else if pictures.isEmpty { text += "\n\nNo picture came out of the preview." }
        else { text += "\n\n\(pictures.count == 1 ? "The picture is" : "The pictures are") 1920x1080, as the game is drawn everywhere, drawn on this Mac out of sight: where it's played draws the same frames slower or faster." }
        return (200, ["text": text, "screenshots": Self.agentPictures(pictures, in: project)])
    }

    /// One Android app as opened: where it runs (the emulator's or the device's serial), its process on the device,
    /// and the log Lamp reads from it. `alive` is kept by a watch that asks the device for the process every couple
    /// of seconds, since the log reader doesn't end when the app does.
    @MainActor final class AndroidRun {
        let serial: String
        let pid: Int32
        var log: Process?
        var alive = true
        var watch: Task<Void, Never>?
        init(serial: String, pid: Int32, log: Process?) { self.serial = serial; self.pid = pid; self.log = log }
        func end() {
            alive = false
            watch?.cancel()
            if let log, log.isRunning { log.terminate() }
        }
    }
    /// The Android apps open now, by project.
    private var androidApps: [String: AndroidRun] = [:]

    /// The app is open in Lamp's emulator (not on the person's own Android device), for its chat to go beside it.
    func isOpenInEmulator(_ project: LampProject) -> Bool { androidApps[project.id]?.serial.hasPrefix("emulator-") == true }
    /// Which project each Android device's screen belongs to: the last launched there. A look or `use_app` by
    /// another project whose app is still alive in the background is refused the screen, as the simulator's
    /// leases do it.
    private var androidLeases: [String: String] = [:]
    /// The screen density of the device each Android app is open on, for its pictures (`Adb.screenshot`).
    private var androidDensities: [String: Int] = [:]
    /// Projects whose next Android launch starts fresh rather than where the person was (a look with `reopen`).
    private var androidFresh: Set<String> = []

    /// The launch in progress on each Android device, for the next one to wait for: as on a simulator, launches
    /// on one device go one after another, so two apps can't be racing onto the same screen.
    private var androidWork: [String: Task<Void, Never>] = [:]

    /// Puts an Android app on the device Try On points at (the person's own, or the emulator, started when it
    /// isn't running) and opens it, with its log read into the app's log. Nil when it's open; else what went wrong.
    private func installOnAndroid(_ project: LampProject, owner: Turn, inFront: Bool) async -> String? {
        func stillOwns() -> Bool { exists(project) && turns[project.id] === owner && !owner.stopped }
        let serial: String
        do {
            if let chosen = project.device {
                let found = await Adb.devices().first { $0.udid == chosen }
                guard let found, found.adbState == "device" else {
                    let problem = found.map { Adb.advice(for: $0.name, state: $0.adbState) }
                        ?? "Lamp can't see the Android device chosen under Try On. Plug it in and unlock it, or choose the emulator."
                    log(project, .error, problem)
                    return problem
                }
                serial = chosen
                androidDensities[project.id] = found.density
            } else {
                note("Starting the Android emulator…", for: project)
                serial = try await Emulator.start(show: inFront)
                if androidDensities[project.id] == nil {
                    androidDensities[project.id] = (await Adb.getprop(on: serial))["density"].flatMap { Int($0) }
                }
            }
        } catch {
            let problem = error.localizedDescription
            log(project, .error, problem)
            return problem
        }
        guard stillOwns() else { return "The app was deleted or stopped before it opened." }
        let previous = androidWork[serial]
        let mine = Task<String?, Never> { [self] in
            await previous?.value
            guard stillOwns() else { return "The app was deleted or stopped before it opened." }
            return await launchOnAndroid(project, owner: owner, serial: serial, inFront: inFront)
        }
        androidWork[serial] = Task { _ = await mine.value }
        return await mine.value
    }

    /// The launch itself, once the device is this project's turn: the device's screen is leased to it from here, and
    /// every wait asks again whether it still is.
    private func launchOnAndroid(_ project: LampProject, owner: Turn, serial: String, inFront: Bool) async -> String? {
        let package = Template.androidPackage(for: project)
        func stillOwns() -> Bool {
            exists(project) && turns[project.id] === owner && !owner.stopped && androidLeases[serial] == project.id
        }
        do {
            note("Opening \(project.name) on \(project.device == nil ? "the emulator" : "your device")…", for: project)
            retireLaunches(of: project)
            androidApps[project.id]?.end()
            // One Lamp app per device: another project's app there is closed first, so the screen is this app's.
            for (other, run) in androidApps where other != project.id && run.serial == serial {
                if let theirs = projects.first(where: { $0.id == other }) {
                    retireLaunches(of: theirs)
                    await Adb.stop(Template.androidPackage(for: theirs), on: serial)
                }
                run.end()
                androidApps[other] = nil
            }
            androidLeases[serial] = project.id
            // Where the person was goes with the change: the running copy saves its state, and the new one opens from it.
            let fresh = androidFresh.remove(project.id) != nil
            var kept = false
            if !fresh, await Adb.pid(of: package, on: serial) != nil { kept = await Adb.saveState(package, on: serial) }
            try await Adb.install(project.builtURL, package: package, on: serial)
            await Adb.tellApp(Template.androidInstallValues(for: project, onDevice: project.device != nil, wishKey: wishKey(for: project)), package: package, on: serial)
            guard stillOwns() else { return "The app was deleted or stopped before it opened." }
            Runtime.startLog(project)
            // State the new code can't take may end it at once, before or after it's seen running; the app has used
            // the state up by then, so it opens fresh.
            var pid: Int32
            if kept {
                let restored = try? await Adb.launch(package, on: serial)
                if let restored, !(await Adb.quitSoon(restored, package: package, on: serial)) {
                    pid = restored
                } else {
                    log(project, .detail, "The app couldn't open where it was after the change, so it was opened fresh.")
                    Runtime.startLog(project)
                    pid = try await Adb.launch(package, on: serial)
                }
            } else {
                pid = try await Adb.launch(package, on: serial)
            }
            let logcat = (try? AppFolder.appendHandle(Runtime.logURL(project), in: project.dir)).flatMap { try? Adb.logcat(pid: pid, on: serial, log: $0) }
            let run = AndroidRun(serial: serial, pid: pid, log: logcat)
            androidApps[project.id] = run
            // Often in the first seconds, when a crash on launch would show and the launch watch is judging it.
            run.watch = Task { [weak self] in
                var polls = 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(polls < 10 ? 500 : 2000))
                    polls += 1
                    guard let self, androidApps[project.id] === run else { return }
                    if await Adb.pid(of: package, on: serial) != pid {
                        run.end()
                        refreshOpenApps()
                        return
                    }
                }
            }
            if inFront, project.device == nil { await Emulator.bringForward() }
            let opened = Date()
            // The verdict asks the device once more as the window ends, since the watch's reading may be half a second old.
            _ = watchLaunch(project, owner: owner, opened: opened, alive: { run.alive }, confirm: {
                guard run.alive else { return false }
                let there = await Adb.pid(of: package, on: serial) == pid
                if !there { run.end() }
                return there
            }, report: {
                Runtime.logTail(project, lines: 40) ?? "The app quit right after opening, and printed nothing."
            })
            refreshOpenApps()
            return nil
        } catch {
            let problem = error.localizedDescription
            log(project, .error, problem)
            return problem
        }
    }

    /// `look_at_app` for an Android app: the app built, put on the emulator or the device, pictured with adb and
    /// read as text, with what it logged.
    private func lookOnAndroid(_ project: LampProject, turn: Turn, changed: Bool, reopen: Bool) async -> (Int, [String: Any]) {
        var summary = "The app built and is running."
        let running = await isAndroidRunning(project)
        if changed || !running || reopen {
            if reopen { androidFresh.insert(project.id) }
            let crash = await install(project, inFront: false, early: true)
            turn.look.installed[project.id] = true
            turn.look.crashes[project.id] = crash
            if let crash { return (200, ["text": "The app \(changed ? "built" : "is built"), but it didn't open.\n\n\(crash)"]) }
            if !changed { summary = "The app is running your latest code; it was reopened without rebuilding." }
            if reopen { summary = "The app was closed and opened again, so it started fresh." }
        } else {
            summary = "The app is running your latest code; nothing needed rebuilding."
        }
        note("Looking at \(project.name)", for: project)
        guard let open = androidApps[project.id] else { return (200, ["text": summary + " It isn't open now."]) }
        try? await Task.sleep(for: Self.simulatorFirstScreen)
        var screenshots: [URL] = []
        let picture = Runtime.folder(project).appendingPathComponent("screenshot.png")
        if let data = await Adb.screenshot(on: open.serial, density: androidDensities[project.id]),
           (try? AppFolder.write(data, to: picture, in: project.dir)) != nil { screenshots = [picture] }
        let place = project.device == nil ? "the Android emulator (\(AndroidTools.avdName))" : "the person's Android device"
        var text = summary + " It's open on \(place). " + (screenshots.isEmpty ? "No picture of the screen could be taken."
            : Privacy.sharesPictures ? "A picture of its screen follows. Points for use_app are pixels in it." : Privacy.picturesOff)
        if !Privacy.sharesLog { text += " " + Privacy.logOff }
        if Privacy.sharesPictures, let screen = await Adb.screen(on: open.serial, density: androidDensities[project.id]) { text += "\n\n" + screen.text }
        if Privacy.sharesLog, let tail = Runtime.logTail(project) { text += "\n\nWhat it logged:\n\(tail)" }
        return (200, ["text": text, "screenshots": Self.agentPictures(screenshots, in: project)])
    }

    /// Open, still this project's screen (no other app of Lamp's launched on that device since), and alive on the device.
    private func isAndroidRunning(_ project: LampProject) async -> Bool {
        guard let open = androidApps[project.id], open.alive, androidLeases[open.serial] == project.id else { return false }
        return await Adb.pid(of: Template.androidPackage(for: project), on: open.serial) == open.pid
    }

    /// Why an Android app can't be built now, or nil: Google's tools aren't on this Mac yet.
    /// What keeps a C++ game from being built for the Xbox on this Mac (the console's tools), or nil.
    private func gameToolsProblem(_ project: LampProject) -> String? {
        guard GameKit.isGame(project), project.onDevice, GameKit.engine(project) == .native else { return nil }
        return WindowsTools.problem
    }

    private func androidToolsProblem(_ project: LampProject) -> String? {
        guard project.onAndroid, !AndroidTools.isReady else { return nil }
        return "Android's tools aren't on this Mac yet. Download them in the Android Setup window (also under Settings → Building), then try again."
    }

    /// `use_app` for an Android app: the actions carried out with adb, the screen read between them.
    private func useOnAndroid(_ project: LampProject, actions: [[String: Any]], json: String) async -> (Int, [String: Any]) {
        guard let open = androidApps[project.id], await isAndroidRunning(project) else {
            return (200, ["text": "The app isn't open. Call look_at_app first: it builds the app and opens it."])
        }
        guard let owner = turns[project.id] else { return (409, ["error": "Lamp isn't working on this app right now."]) }
        guard let data = json.data(using: .utf8), let decoded = try? JSONDecoder().decode([Simulator.Driver.Action].self, from: data) else {
            return (400, ["error": "use_app needs a list of actions."])
        }
        let density = androidDensities[project.id]
        let screen = await Adb.screen(on: open.serial, density: density)
        // On the emulator, in plain sight as on the iPhone's simulator: its window glows, Lamp's fingertip goes to
        // each spot, and the person's Stop, Esc, or own click in the window ends it. A look leaves the emulator hidden
        // so as not to pull it in front mid-turn, so trying the app brings its window back, without taking the
        // keyboard. A device of the person's has nothing of it on the Mac's screen to show.
        let scale = Adb.scale(density: density)
        var shown: Emulator.Glass?
        if open.serial == Emulator.serial, let size = await Adb.displaySize(on: open.serial) {
            await Emulator.unhide()
            shown = await Emulator.glass(size: CGSize(width: size.width / scale, height: size.height / scale))
        }
        let glass = shown
        // Driving the emulator needs no permission, so none is asked for just to hear Esc: without it the pill offers
        // Stop, and the person's own click in the emulator still takes it back.
        let trial = glass.map { Handover(label: "\(Self.lampName) is trying it on Android", finger: true, simulator: $0.pid,
                                         escape: Simulator.Driver.isAllowed) }
        if let glass { trial?.show(window: glass.window) }
        defer { trial?.end() }
        let report = await Adb.perform(decoded, on: open.serial, density: density, screen: screen, aim: { point, doing, press in
            guard let trial, let spot = glass?.point(point) else { return }
            await trial.aim(at: spot, doing: doing, press: press)
        }, tookOver: { trial?.tookOver == true }) { [weak self] in
            guard let self, exists(project), turns[project.id] === owner, !owner.stopped, trial?.tookOver != true else { return false }
            // Whether the app still runs is asked of the device, and Stop or the person's click may come meanwhile.
            guard await isAndroidRunning(project) else { return false }
            return turns[project.id] === owner && !owner.stopped && trial?.tookOver != true
        }
        // Asked again after the reads below: they take a moment, and Stop may come during them.
        func tookOver() -> Bool {
            guard trial?.tookOver == true else { return false }
            if !owner.tookOver {
                owner.tookOver = true
                log(project, .status, Self.stoppedByYou)
            }
            return true
        }
        var text = "What happened:\n\(report)"
        guard await isAndroidRunning(project) else {
            text += "\n\nThe app quit or crashed while doing that."
            if tookOver() { text += "\n\n" + Self.tookOverNote }
            if Privacy.sharesLog, let tail = Runtime.logTail(project) { text += "\n\nLast lines it logged:\n" + tail }
            return (200, ["text": text])
        }
        if Runtime.sourcesChanged(project) {
            text += "\n\nThis is the app as last built: it doesn't have the changes you've made to the code since. Call look_at_app to build and open them."
        }
        var screenshots: [URL] = []
        let picture = Runtime.folder(project).appendingPathComponent("screenshot.png")
        if Privacy.sharesPictures {
            if let after = await Adb.screen(on: open.serial, density: density, mayWake: { trial?.tookOver != true }) { text += "\n\n" + after.text }
            if let data = await Adb.screenshot(on: open.serial, density: density),
               (try? AppFolder.write(data, to: picture, in: project.dir)) != nil { screenshots = [picture] }
            text += "\n\nA picture of the screen follows. Points for the next use_app are pixels in it."
        }
        if tookOver() { text += "\n\n" + Self.tookOverNote }
        if Privacy.sharesLog, let tail = Runtime.logTail(project) { text += "\n\nLast lines it logged:\n" + tail }
        return (200, ["text": text, "screenshots": Self.agentPictures(screenshots, in: project)])
    }

    private func installOnSimulator(_ project: LampProject, owner: Turn, inFront: Bool, early: Bool) async -> String? {
        guard let udid = Simulator.device(project.family, preferring: project.simulator) else {
            let problem = "No \(project.family.name) simulator with iOS \(Simulator.minimumIOS) or later is installed. Open Xcode once and add one in Settings → Components."
            log(project, .error, problem)
            return problem
        }
        // `owner` is the turn the app belongs to, taken by `install` before anything waited: Delete or Stop
        // can come during any of the waits, and then nothing more is written or launched for it (not even by
        // a later turn of the same app, which would have a launch of its own).
        // Launches on one device go one after another: a launch already under way finishes (and is then
        // closed, below) before the next starts, so two apps can't be racing onto the same screen.
        let previous = simulatorWork[udid]
        let mine = Task<String?, Never> { [self] in
            await previous?.value
            guard turns[project.id] === owner, !owner.stopped else { return "The app was stopped before it opened." }
            return await launchOnSimulator(project, owner: owner, udid: udid, inFront: inFront, early: early)
        }
        simulatorWork[udid] = Task { _ = await mine.value }
        return await mine.value
    }

    /// How long a look gives an app it just opened in the simulator to draw its first screen before picturing it.
    private static let simulatorFirstScreen: Duration = .milliseconds(1500)

    /// Watches a launch's first seconds (`Runtime.LaunchWatch`) as the turn's last launch, and says in the chat when the
    /// app dies in them, `report` giving what's known of it.
    /// `crashOnly` is for a Mac app, which leaves a crash report: a going after the opener went on, or while Lamp was
    /// closing the app, counts only with one, since the person or Lamp may have closed an app that works. Without
    /// one (the simulator), a going while Lamp closed the app is Lamp's doing.
    private func watchLaunch(_ project: LampProject, owner: Turn?, opened: Date, crashOnly: Bool = false,
                             alive: @escaping @MainActor () -> Bool, confirm: (@MainActor () async -> Bool)? = nil,
                             report: @escaping @MainActor () async -> String) -> Runtime.LaunchWatch {
        let watch = Runtime.LaunchWatch(opened: opened, alive: alive, confirm: confirm) { [weak self] late, retired in
            if retired, !crashOnly { return nil }
            if late || retired, crashOnly {
                // macOS writes the report after the process is gone, sometimes ten seconds or more later.
                var crashed = false
                for _ in 0..<40 where !crashed {
                    crashed = Runtime.crashed(project, since: opened)
                    if !crashed { try? await Task.sleep(for: .milliseconds(500)) }
                }
                guard crashed else { return nil }
            }
            owner?.diedOnLaunch = true
            self?.log(project, .status, "\(project.name) quit right after opening. Looking at why…")
            let crash = await report()
            self?.log(project, .detail, crash)
            return crash
        }
        watch.app = project.id
        owner?.launches.append(watch)
        return watch
    }

    /// The launch in progress on each simulator, for the next one to wait for.
    private var simulatorWork: [String: Task<Void, Never>] = [:]

    private func launchOnSimulator(_ project: LampProject, owner: Turn, udid: String, inFront: Bool, early: Bool) async -> String? {
        // The device is this project's from here: the driver acts only while the lease is held.
        let before = simulatorLeases[udid]
        simulatorLeases[udid] = project.id
        func stillOwns() -> Bool { exists(project) && turns[project.id] === owner && !owner.stopped && simulatorLeases[udid] == project.id }
        // A launch that doesn't come off gives the device back to whoever had it, so their look_at_app can
        // carry on (and theirs rechecks the lease, so it reopens the app if need be).
        func giveBack(_ message: String) -> String {
            if simulatorLeases[udid] == project.id { simulatorLeases[udid] = before.flatMap { simulatorApps[$0] != nil ? $0 : nil } }
            return message
        }
        let simulator = await Simulator.name(of: udid) ?? project.family.name
        note("Opening \(project.name) on the \(simulator) simulator…", for: project)
        await finishSimulatorBundle(project)
        do {
            try await Simulator.boot(udid, show: inFront)
            retireLaunches(of: project)
            await Simulator.terminate(project.bundleID, on: udid)
            try await Simulator.install(project.builtURL, on: udid)
            if let key = wishKey(for: project) { await Simulator.tellApp(wishKey: key, bundleID: project.bundleID, on: udid) }
            guard stillOwns() else { return giveBack("The app was deleted or stopped before it opened.") }
            // One Lamp app per simulator: another project's app on this device is closed first, so what the
            // simulator shows is always the app being worked on (and that app's use_app batch, if any, stops).
            for (other, launched) in simulatorApps where other != project.id && launched.udid == udid {
                if let theirs = projects.first(where: { $0.id == other }) {
                    retireLaunches(of: theirs)
                    await Simulator.terminate(theirs.bundleID, on: udid)
                }
                simulatorApps[other] = nil
            }
            guard stillOwns() else { return giveBack("The app was deleted or stopped before it opened.") }
            Runtime.startLog(project)
            await Simulator.Driver.forget(project.id)
            let pid = try await Simulator.launch(project.bundleID, on: udid, log: Runtime.logURL(project))
            // The same could have happened during the launch itself: then the app just started belongs to
            // nobody, and is stopped before anything records it.
            guard stillOwns() else {
                await Simulator.terminate(project.bundleID, on: udid)
                return giveBack("The app was deleted or stopped before it opened.")
            }
            simulatorApps[project.id] = (udid, pid)
            let watch = watchLaunch(project, owner: owner, opened: Date(), alive: { Simulator.isRunning(pid: pid) }) { [weak self] in
                if self?.simulatorApps[project.id]?.pid == pid { self?.simulatorApps[project.id] = nil }
                self?.refreshOpenApps()
                var crash = "The app quit right after launching."
                if Privacy.sharesLog, let tail = Runtime.logTail(project) { crash += "\n\nLast lines it printed:\n" + tail }
                return crash
            }
            // Nothing in the simulator says when the app has drawn its first screen: a look goes on after a moment for
            // that, and hears of a death after it from the watch; anything else waits the first seconds out.
            if early ? await watch.settle(Self.simulatorFirstScreen) : await watch.verdict() != nil {
                watch.told = true
                return watch.crash
            }
            // The desk's picture of it, as a Mac app takes its own once its window settles.
            Task { _ = await Simulator.screenshot(on: udid, to: Runtime.previewURL(project)) }
            await openWatchApp(project, phone: udid, live: stillOwns)
            if inFront {
                // The Simulator was opened before the install; by now it may be behind Lamp again, and "ready"
                // should mean the app is in front of the person, not somewhere to be found.
                await Simulator.show(udid)
                log(project, .status, "\(project.name) is ready on the \(simulator) simulator")
            }
        } catch {
            // A failure to boot, install or launch is reported like a crash: the agent must hear about it.
            log(project, .error, ErrorMessages.openFailed(error.localizedDescription))
            refreshOpenApps()
            return giveBack("Couldn't open the app in the simulator: \(error.localizedDescription)")
        }
        refreshOpenApps()
        stamps[project.id] = BuildStamp.read(project.builtURL)
        return nil
    }

    /// The app's Apple Watch app, when its build carries one, put on the watch simulator paired with the
    /// iPhone's and opened there, so the two talk as they would on the person's wrist. What goes wrong here is
    /// a line in the chat, never a crash for the agent to fix: the iPhone app is open and the watch is extra.
    /// `live` says the launch is still the turn's, as the iPhone's launch checks it: Stop or Delete during a
    /// wait leaves nothing more installed, and a watch app started meanwhile is closed again.
    private func openWatchApp(_ project: LampProject, phone: String, live: () -> Bool) async {
        let watchApp = Template.watchAppURL(in: project.builtURL, of: project)
        guard FileManager.default.fileExists(atPath: watchApp.path) else { return }
        let found = await Simulator.pairedWatch(of: phone)
        guard live() else { return }
        guard let watch = found else {
            // Said once a session for each app, not at every launch.
            if watchHintShown.insert(project.id).inserted {
                log(project, .status, "To see the watch app, add watchOS in Xcode → Settings → Components; Lamp then opens it on an Apple Watch simulator.")
            }
            return
        }
        let id = Template.watchBundleID(project.bundleID)
        do {
            try await Simulator.boot(watch, show: false)
            await Simulator.terminate(id, on: watch)
            guard live() else { return }
            try await Simulator.install(watchApp, on: watch)
            guard live() else { return }
            _ = try await Simulator.launch(id, on: watch, log: Runtime.folder(project).appendingPathComponent("watch-log.txt"))
            if !live() { await Simulator.terminate(id, on: watch) }
        } catch {
            if live() { log(project, .status, "The watch app didn't open: \(error.localizedDescription)") }
        }
    }

    private var watchHintShown: Set<String> = []

    /// Retry the phone operation alone: an account or device problem is never sent to the coding agent.
    func retryPhone(_ project: LampProject, udid: String) async {
        guard let current = projects.first(where: { $0.id == project.id }), current.device == udid,
              let owner = begin(current) else { return }
        defer { finish(current) }
        _ = await installOnDevice(current, owner: owner, udid: udid)
    }

    private func clearPhoneRetry(_ project: LampProject) {
        guard var lines = logs[project.id], lines.contains(where: { $0.retryPhone != nil }) else { return }
        for index in lines.indices { lines[index].retryPhone = nil }
        logs[project.id] = lines
        saveChat(project)
    }

    /// Builds the app for the person's own phone with Xcode and puts it there (Devices). Signing is Xcode's
    /// automatic kind for the team chosen in Settings, so the first time can take a while while Xcode
    /// registers the phone and makes a certificate. What the app prints comes back to its log, as on the
    /// simulator. Returns a plain message when it couldn't be done, which the chat shows.
    private func installOnDevice(_ project: LampProject, owner: Turn, udid: String) async -> String? {
        func stillOwns() -> Bool { exists(project) && turns[project.id] === owner && !owner.stopped }
        func failed(_ message: String, output: String = "") {
            guard stillOwns() else { return }
            if !output.isEmpty { log(project, .detail, output) }
            log(project, .error, message, retryPhone: udid)
        }
        owner.phoneReady = false
        if progress[project.id]?.finished != nil { progress[project.id]?.failed = true }
        clearPhoneRetry(project)
        let team = Devices.team
        // The code as it's staged, kept once it's on the phone, so a turn that changes nothing doesn't put it there again.
        let build = Runtime.fingerprint(project)
        // Recheck after the person unlocks, trusts or restarts the phone; the menu's snapshot may be stale.
        devices = await Devices.list()
        guard stillOwns() else { return nil }
        let device = devices.first(where: { $0.udid == udid })
        if let problem = Devices.problem(device, team: team) {
            failed(problem)
            return nil
        }
        let name = device?.name ?? "your phone"
        if let problem = Devices.membershipProblem(for: project, on: name, team: team) {
            failed(problem)
            return nil
        }
        do {
            try await Devices.stage(project, team: team, wishKey: wishKey(for: project), started: { owner.build = $0 })
            owner.build = nil
            // Where the phone's project and builds were kept before, inside the app's folder. An app for both
            // still builds its Mac half there.
            if project.platform == .iphone { try? FileManager.default.removeItem(at: project.dir.appendingPathComponent(".lamp/device")) }
        } catch let error as Devices.LinkedFiles {
            owner.build = nil
            failed(error.localizedDescription)
            return nil
        } catch {
            owner.build = nil
            failed("Lamp couldn't get the app ready for \(name). Click Retry. If it fails again, ask Lamp to fix it and include the error from Agent Details.", output: error.localizedDescription)
            return nil
        }
        guard stillOwns() else { return nil }
        log(project, .status, "Building for \(name)…")
        var output: [String] = []
        let app: URL
        do {
            let build = try await Devices.build(project, team: team, destination: "id=\(udid)", started: { owner.build = $0 }) { output.append($0) }
            guard stillOwns() else { owner.build = nil; return nil }
            app = try await Devices.signedCopy(of: build, for: project, team: team, destination: "id=\(udid)",
                                               started: { owner.build = $0 }) { output.append($0) }
            owner.build = nil
        } catch {
            owner.build = nil
            let failure = PhoneFailure(stage: .build, output: output.joined(separator: "\n"))
            failed(failure.message, output: failure.output.isEmpty ? error.localizedDescription : failure.output)
            return nil
        }
        guard stillOwns() else { return nil }
        log(project, .status, "Putting \(project.name) on \(name)…")
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        do {
            // What's on the phone is about to change, whether or not the launch after it works.
            onPhone[project.id] = nil
            try await Devices.install(app, on: udid)
            guard stillOwns() else { return nil }
            deviceApps[project.id]?.terminate()
            deviceApps[project.id] = nil
            Runtime.startLog(project)
            log(project, .status, "Opening \(project.name) on \(name)…")
            let attached = try await Devices.launch(project.deviceBundleID(team: team), on: udid, log: Runtime.logURL(project),
                                                    started: { owner.build = $0 }, cancelled: { !stillOwns() })
            owner.build = nil
            guard stillOwns() else { Subprocess.terminateTree(attached); return nil }
            deviceApps[project.id] = attached
            onPhone[project.id] = PhoneBuild(udid: udid, build: build)
            owner.phoneReady = true
            if progress[project.id]?.finished != nil { progress[project.id]?.failed = false }
            attached.terminationHandler = { _ in Task { @MainActor in Store.shared.refreshOpenApps() } }
            log(project, .status, "\(project.name) is ready on \(name)")
            offerAwaySetup(project)
        } catch {
            owner.build = nil
            if let failure = error as? PhoneFailure { failed(failure.message, output: failure.output) }
            else if !(error is CancellationError) {
                let failure = PhoneFailure(stage: .launch, output: error.localizedDescription)
                failed(failure.message, output: failure.output)
            }
        }
        refreshOpenApps()
        return nil
    }

    /// For each app on a phone, the devicectl process attached to it: ending the process ends the app.
    private var deviceApps: [String: Process] = [:]

    /// For each app, the phone Lamp last put it on and the code it put there (`Runtime.fingerprint`).
    private struct PhoneBuild: Equatable { let udid: String; let build: String }
    private var onPhone: [String: PhoneBuild] = [:]

    /// The code as it is now is on the phone chosen under Try On.
    private func isOnChosenPhone(_ project: LampProject) -> Bool {
        guard project.onIOS, let udid = project.device else { return false }
        return onPhone[project.id] == PhoneBuild(udid: udid, build: Runtime.fingerprint(project))
    }

    /// Finishes the bundle build.sh made, the way `deploy` finishes a Mac app's: the reasons iOS shows when
    /// the app first asks for the microphone, photos or calendar (without which it's killed on the spot), the
    /// icon, and the files attached in Lamp's chat, which LampAssets finds next to the executable. Then the
    /// bundle is signed again, ad hoc, which is all the simulator asks for.
    private func finishSimulatorBundle(_ project: LampProject) async {
        let fm = FileManager.default
        let app = project.builtURL
        Self.setInstallValues(for: project, in: app.appendingPathComponent("Info.plist"), root: project.dir)
        var script = """
            P="$LAMP_APP/Info.plist"
            plutil -replace CFBundleName -string "$LAMP_NAME" "$P" && \\
            plutil -replace CFBundleDisplayName -string "$LAMP_NAME" "$P"

            """
        // Every usage description, from the one list, so apps made before a reason was added get it too.
        for (key, text) in Template.iosUsageDescriptions {
            let reason = text.replacingOccurrences(of: "{{NAME}}", with: project.name).replacingOccurrences(of: "'", with: "'\\''")
            script += "plutil -replace \(key) -string '\(reason)' \"$P\"\n"
        }
        // What the agent declared in capabilities.json: background work in Info.plist, the rest as
        // entitlements the ad hoc signature carries (the simulator checks them for Health and the like).
        let capabilities = Template.Capabilities.load(project)
        var lists = capabilities.lists
        // An app of a wish of several is found by the wish's other apps on the network, and finds them, by Bonjour.
        if Template.talksToOtherApps(project), !(lists["NSBonjourServices"] ?? []).contains(Template.wishServiceType) {
            lists["NSBonjourServices", default: []].append(Template.wishServiceType)
        }
        for (key, names) in lists.sorted(by: { $0.key < $1.key }) {
            if let json = try? JSONSerialization.data(withJSONObject: names), let text = String(data: json, encoding: .utf8) {
                script += "plutil -replace \(key) -json '\(text)' \"$P\"\n"
            }
        }
        // Its entitlements are in the binary already (build.sh), where the simulator reads them: a signature
        // that claimed them would be refused, so the signature below claims none.
        // The container's name, for LampSync to read; taken back when no longer declared.
        if let container = capabilities.container(for: project) {
            script += "plutil -replace LampICloudContainer -string '\(container.replacingOccurrences(of: "'", with: "'\\''"))' \"$P\"\n"
        } else {
            script += "{ plutil -remove LampICloudContainer \"$P\" 2>/dev/null || true; }\n"
        }
        // iOS reads icons by name and scale from the bundle itself when told to in Info.plist: the home screen
        // sizes for iPhone (60pt at 2x and 3x) and iPad (76pt and 83.5pt at 2x), all cut from the one square.
        if fm.fileExists(atPath: Icons.squareURL(project).path) {
            let sizes = [("AppIcon60x60@2x", 120), ("AppIcon60x60@3x", 180), ("AppIcon76x76@2x", 152), ("AppIcon83.5x83.5@2x", 167)]
            for (name, pixels) in sizes {
                script += "sips -z \(pixels) \(pixels) \"$LAMP_ICON\" --out \"$LAMP_APP/\(name).png\" >/dev/null && \\\n"
            }
            script += """
                plutil -replace CFBundleIcons -json '{"CFBundlePrimaryIcon":{"CFBundleIconFiles":["AppIcon60x60"]}}' "$P" && \\
                plutil -replace 'CFBundleIcons~ipad' -json '{"CFBundlePrimaryIcon":{"CFBundleIconFiles":["AppIcon60x60","AppIcon76x76","AppIcon83.5x83.5"]}}' "$P"

                """
        }
        // The bundle is the build's, in the agent's folder, so what works on it runs in the app's sandbox: a
        // plist or an icon there that leads elsewhere leads nowhere.
        _ = await Sandbox.run(script, for: project,
                              env: ["LAMP_APP": app.path, "LAMP_NAME": project.name, "LAMP_ICON": Icons.squareURL(project).path]) { _ in }
        Sharing.Assets.adopt(in: project)
        // The bundle and the files copied into it are the agent's, so neither is reached through a link.
        let assets = project.dir.appendingPathComponent(Sharing.Assets.folder)
        AppFolder.remove(app.appendingPathComponent(Attachments.folder), in: project.dir)
        AppFolder.remove(app.appendingPathComponent(Sharing.Assets.folder), in: project.dir)
        if fm.fileExists(atPath: assets.path) {
            try? AppFolder.copy(assets, to: app.appendingPathComponent(Sharing.Assets.folder), in: project.dir)
        }
        // The watch app's icon: watchOS takes one only from a compiled asset catalog, so Xcode's own compiler makes
        // it from the same square as the iPhone's, and Info.plist names it.
        if fm.fileExists(atPath: app.appendingPathComponent("Watch").path), fm.fileExists(atPath: Icons.squareURL(project).path) {
            let work = project.dir.appendingPathComponent(".lamp/watch-icon")
            try? Template.writeWatchIconCatalog(at: work.appendingPathComponent("Icon.xcassets"), icon: AppFile.read(Icons.squareURL(project), in: project), in: project.dir)
            _ = await Sandbox.run("""
                for watch in "$LAMP_APP"/Watch/*.app(N); do
                  xcrun actool "$LAMP_WORK/Icon.xcassets" --compile "$watch" --platform watchsimulator --minimum-deployment-target 10.0 \\
                    --app-icon AppIcon --output-partial-info-plist "$LAMP_WORK/partial.plist" >/dev/null 2>&1 && \\
                  plutil -replace CFBundleIcons -json '{"CFBundlePrimaryIcon":{"CFBundleIconName":"AppIcon"}}' "$watch/Info.plist"
                done
                """, for: project, env: ["LAMP_APP": app.path, "LAMP_WORK": work.path]) { _ in }
        }
        // A widget extension inside is signed first, as Xcode does: the app's signature then seals it. The watch
        // app the same way, its complications before it.
        _ = await Sandbox.run("""
            xattr -cr "$LAMP_APP"
            for widget in "$LAMP_APP"/PlugIns/*.appex(N); do codesign --force -s - "$widget"; done
            for watch in "$LAMP_APP"/Watch/*.app(N); do
              for extension in "$watch"/PlugIns/*.appex(N); do codesign --force -s - "$extension"; done
              codesign --force -s - "$watch"
            done
            codesign --force -s - "$LAMP_APP"
            """, for: project, env: ["LAMP_APP": app.path]) { _ in }
    }

    /// iPhone apps running in the simulator: which simulator each was launched on, and its process id.
    private var simulatorApps: [String: (udid: String, pid: Int32)] = [:]

    /// The simulator an app is open in now, for its chat to go beside (`ChatPanel`).
    func simulatorDevice(of project: LampProject) -> String? { simulatorApps[project.id]?.udid }
    /// Which project each simulator belongs to right now: taken before a launch's first wait, so two launches
    /// on one device can't both go ahead, and checked before every action the driver takes.
    private var simulatorLeases: [String: String] = [:]

    /// For Open App, Undo, a restore and a rebuild, where no agent is running to fix a crash. Each of them holds the
    /// app while it installs, so the fix waits for it to let go (`fixHeldCrash`, from `finish`).
    private func installReportingCrash(_ project: LampProject) async {
        let owner = turns[project.id]
        guard let crash = await install(project), owner?.stopped != true else { return }
        // Only an app that opened and died is worth a fix; one that never opened says why in the chat already.
        if owner?.diedOnLaunch == true { crashesAfterRelease[project.id] = crash }
        // A TV, an Android device or another device that didn't take the app has said why already: it never opened, so
        // it didn't crash.
        else if project.onTV || project.onAndroid || project.onDevice { return }
        else { log(project, .error, ErrorMessages.crashAfterLaunch(project.name)) }
    }

    /// Crashes on opening seen while something held the app, to be fixed once it's free.
    private var crashesAfterRelease: [String: String] = [:]

    /// Called as the hold ends, before anything waiting starts: with a request already in line the agent hears of
    /// the crash with that, and the chat only says it crashed.
    private func fixHeldCrash(_ project: LampProject) {
        // A change set aside that the turn's agent never heard of starts a fix, unless Stop was pressed. It counts as
        // told only when the fix is sent: kept from it (a request in line, Lamp's own fix already tried), it goes with
        // the next request instead (`turn`), and nothing is put into the app by itself until then (`autoApply`).
        if crashesAfterRelease[project.id] == nil, let aside = setAsideChanges[project.id], !aside.told {
            guard !aside.afterStop else { return }
            setAsideChanges[project.id]?.told = true
            if !fixCrash(project, detail: aside.crash) { setAsideChanges[project.id]?.told = false }
            return
        }
        // A part's crash is fixed through its wish, so while the wish is held (an Undo rebuilding its parts) it waits
        // for the wish's own `finish`.
        if let wish = project.partOf, busy.contains(wish) || turns[wish] != nil, crashesAfterRelease[project.id] != nil { return }
        guard let crash = crashesAfterRelease.removeValue(forKey: project.id) else { return }
        if !fixCrash(project, detail: crash) { log(project, .error, ErrorMessages.crashAfterLaunch(project.isPart ? placeName(project) : project.name)) }
    }

    /// `fixHeldCrash` for the app and, for a wish, each of its other apps, whose crashes waited for it.
    private func fixHeldCrashes(_ project: LampProject) {
        fixHeldCrash(project)
        for part in parts(of: project) where turns[part.id] == nil { fixHeldCrash(part) }
    }

    /// The crash report each app's last automatic fix answered, so the same crash seen twice (on opening, and as
    /// the app goes) starts one fix.
    private var crashesAnswered: [String: Date] = [:]

    /// A crash of an app the person isn't changing starts a fix at once, as if they'd asked for one: Lamp sends the
    /// request itself, and the crash report goes with it (`Runtime.crashNote`). It does so once in a row: when the
    /// latest request in the chat is Lamp's own, a fix already had its chance (and its own launch crashes were
    /// retried within it), so the next crash is the person's to decide on and nothing more is spent until they say
    /// something. True when the crash is taken care of (a fix started, or one is already under way for it).
    @discardableResult
    private func fixCrash(_ project: LampProject, detail: String) -> Bool {
        guard let crashed = current(project) else { return true }
        // A part's crash is fixed by its wish's turn, which knows the part as one of its own.
        let project = Self.requestOwner(of: crashed, among: projects)
        let report = Runtime.newestCrash(of: crashed)?.date
        if let report, crashesAnswered[project.id] == report { return true }
        // While a turn runs or a request waits, the agent hears of the crash with it.
        guard setup.ready, !busy.contains(project.id), turns[project.id] == nil,
              queued[project.id]?.isEmpty ?? true else { return false }
        guard !lastRequestByLamp(project) else { return false }
        if let report { crashesAnswered[project.id] = report }
        log(project, .status, ChatLook.fixingCrash)
        // The report itself goes with the request when macOS wrote one; otherwise what Lamp saw is all there is.
        // The wish's request carries no note of a part's crash, so a part's goes with what Lamp saw, and which part it was.
        let part = crashed.id != project.id
        let request = part ? "\(Parts.name(of: crashed.platform).prefix(1).uppercased() + Parts.name(of: crashed.platform).dropFirst()), in \(crashed.dir.lastPathComponent)/, crashed. Fix the crash." : "Fix the crash."
        queued[project.id, default: []].append(QueuedMessage(text: report == nil || part ? request + "\n\n" + detail : request, byLamp: true))
        startQueued(project)
        return true
    }

    private func lastRequestByLamp(_ project: LampProject) -> Bool {
        (logs[project.id] ?? []).last { $0.kind == .user }?.byLamp == true
    }

    /// An app crashing while it's used, with no turn of Lamp's under way: what the person sees go is fixed the way
    /// a crash on opening is. Only a crash, which leaves macOS's report: a quit leaves none. A crash just after a
    /// change went into the open app is the live change's to answer (`watchAfterReload`).
    private func appEnded(_ app: NSRunningApplication) {
        // By its id first: a wish's Mac app is installed under the wish's name, which its TV app shares.
        guard let project = projects.first(where: { app.bundleIdentifier == $0.bundleID })
                ?? projects.first(where: { $0.hasMac && app.bundleURL?.standardizedFileURL == $0.installedURL.standardizedFileURL }),
              !busy.contains(project.id), reloadWatches[project.id] == nil else { return }
        let since = app.launchDate ?? Date().addingTimeInterval(-5)
        Task { [weak self] in
            // macOS writes the report after the process is gone, sometimes ten seconds or more later (the time
            // it shows its own crash dialog).
            for _ in 0..<60 {
                guard let self, let current = self.current(project) else { return }
                if let crash = Runtime.newestCrash(of: current), crash.date > since {
                    // Its chat went with it: it comes up in Lamp's panel, with what Lamp does about the crash.
                    MagicPanel.shared.showChatAfterQuit(current)
                    // After Lamp's own fix it's said once, and left to the person.
                    if !self.fixCrash(current, detail: crash.summary), self.lastRequestByLamp(current),
                       self.crashesAnswered[current.id] != crash.date {
                        self.crashesAnswered[current.id] = crash.date
                        self.log(current, .error, ErrorMessages.crashed(current.name))
                    }
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    struct ForeignBuild: LocalizedError {
        let id: String?
        var errorDescription: String? { "its build says it's another app (\(id ?? "no id")), so Lamp won't sign it as this one." }
    }

    /// Throws unless the built app and each piece Lamp signs inside it (the chat, a widget, a share extension)
    /// carry the ids Lamp gave them. Once it's `signed`, each signature must be whole and name the same id: a
    /// signature made while a file said something else wouldn't.
    nonisolated static func checkOwnIDs(in app: URL, for project: LampProject, signed: Bool = false) throws {
        let fm = FileManager.default
        let pieces = [(app, project.bundleID),
                      (Sidebar.extensionURL(in: app), Sidebar.bundleID(for: project)),
                      (Template.widgetURL(in: app, of: project), Template.widgetBundleID(for: project)),
                      (Template.shareURL(in: app, of: project), project.bundleID + ".share")]
        for (bundle, expected) in pieces where bundle == app || fm.fileExists(atPath: bundle.path) {
            let id = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"] as? String
            guard id == expected else { throw ForeignBuild(id: id) }
            guard signed else { continue }
            var code: SecStaticCode?
            var info: CFDictionary?
            guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code,
                  SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess,
                  SecCodeCopySigningInformation(code, [], &info) == errSecSuccess else { throw ForeignBuild(id: nil) }
            let signedID = (info as? [String: Any])?[kSecCodeInfoIdentifier as String] as? String
            guard signedID == expected else { throw ForeignBuild(id: signedID) }
        }
    }

    struct LinkedBuild: LocalizedError {
        var errorDescription: String? { "its build reaches outside itself, so Lamp won't sign it." }
    }

    /// A copy of the app's build in `folder`, hidden until it's swapped in, for Lamp alone to finish and sign.
    /// A copy keeps symbolic links as links, so one that leads out of the copy (or a build that is itself a link)
    /// would have Lamp change, read and sign files the agent can still write: such a build isn't staged. The copy
    /// is what's checked, not the build, which can be swapped for a link between a look at it and the copy.
    nonisolated static func stage(_ project: LampProject, in folder: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent(".\(project.exe)-\(UUID().uuidString).app")
        // Reached without following a link: a build/ that is one would bring in a bundle from anywhere.
        try AppFolder.copy(project.builtURL, in: project.dir, to: copy, in: folder)
        do { try checkContained(copy) } catch { try? fm.removeItem(at: copy); throw error }
        return copy
    }

    /// Throws when a link in the bundle leads out of it. Asked of the copy as it's made and again of the finished
    /// one before it's signed, since what deploy copies in from the app's folder (its assets, the icon) keeps
    /// its links too.
    nonisolated static func checkContained(_ app: URL) throws {
        let fm = FileManager.default
        if (try? fm.destinationOfSymbolicLink(atPath: app.path)) != nil { throw LinkedBuild() }
        let inside = app.standardizedFileURL.path + "/"
        for case let file as URL in fm.enumerator(at: app, includingPropertiesForKeys: nil) ?? FileManager.DirectoryEnumerator() {
            guard let target = try? fm.destinationOfSymbolicLink(atPath: file.path) else { continue }
            let resolved = target.hasPrefix("/") ? URL(fileURLWithPath: target) : file.deletingLastPathComponent().appendingPathComponent(target)
            if !resolved.standardizedFileURL.path.hasPrefix(inside) { throw LinkedBuild() }
        }
    }

    /// Signs `app`, Lamp's copy of the Mac half of an app for both, for the team: with the profile and entitlements
    /// Xcode signed Lamp's own project with for the Mac (`TeamSigning`), and the chat inside it first. True when it
    /// came out signed with the team's certificate. The certificate is looked up after Xcode's signing, which makes
    /// one when this Mac has none for the team yet.
    nonisolated static func signForTeam(_ app: URL, for project: LampProject, team: String,
                                        env: [String: String]) async throws -> Bool {
        let fm = FileManager.default
        var output: [String] = []
        let (plan, planDir) = try await TeamSigning.plan(for: project, team: team, place: .mac, destination: "platform=macOS") { output.append($0) }
        guard let identity = await Devices.signingIdentity(for: team) else { return false }
        guard let piece = plan.app else { throw TeamSigning.Problem(message: "Lamp couldn't tell what to sign it with.") }
        // Nothing that runs but the app's own program and the chat Lamp put in it.
        try TeamSigning.checkCode(in: app, allowing: [app, Sidebar.extensionURL(in: app)])
        let embedded = app.appendingPathComponent("Contents/embedded.provisionprofile")
        try? fm.removeItem(at: embedded)
        if let profile = piece.profile { try fm.copyItem(at: planDir.appendingPathComponent(profile), to: embedded) }
        let entitlements = planDir.appendingPathComponent(piece.entitlements)
        let signed = await Shell.run(AppSigning.universalCommand, cwd: FileManager.default.temporaryDirectory,
                                     env: env.merging(["LAMP_APP": app.path, "LAMP_IDENTITY": identity, "LAMP_APP_ENTITLEMENTS": entitlements.path]) { $1 }) {
            output.append($0)
        } == 0 && AppSigning.isCertificateSigned(app)
        if !signed { print("Signing \(project.name) for the team failed:\n" + output.joined(separator: "\n")) }
        return signed
    }

    /// A signed copy of the app's build in Lamp's own folder (`stageSigned`), waiting to take the installed copy's
    /// place (`swapIn`).
    private struct SignedCopy {
        let app: URL
        let signed: Bool
        /// What the installed copy it replaces was signed as, and what this one is: a change clears the app's permissions.
        let replaced: String?
        let requirement: String?
        /// The icon it carries is the one that replaces the blueprint (`iconReachedApp`), as it was when the copy was
        /// made: artwork drawn after that isn't in it.
        var iconReady = false
        /// Deletes a copy that won't go in (the person kept the app open).
        func discard() { try? FileManager.default.removeItem(at: app) }
    }

    /// Copies the freshly built bundle into the apps folder, puts the icon in, signs it and swaps it in place of
    /// the installed copy. The swap is atomic, so it's safe even while the app is running.
    private func deploy(_ project: LampProject) async throws {
        try await swapIn(try await stageSigned(project), for: project)
    }

    /// Everything `deploy` does before the swap: a copy of the build in the apps folder, finished and signed there.
    /// It touches nothing of the installed copy, so it's done while that copy is still open, before it's asked to quit:
    /// only the swap waits for the app to close.
    private func stageSigned(_ project: LampProject) async throws -> SignedCopy {
        let fm = FileManager.default
        // An icon still being drawn (after a change that went into the open app, New Icon, new artwork) is finished
        // before it's copied in.
        await iconPreparations[project.id]?.value
        await iconRenders[project.id]?.value
        let iconReady = (try? String(contentsOf: Icons.waitingURL(project), encoding: .utf8)) == Self.iconReady
        // Everything from here to the swap is done to a copy in the apps folder, which the agent's commands can't
        // write: the build folder is theirs, and a bundle there could be changed between Lamp's look at it and its
        // signature.
        let app = try Self.stage(project, in: Self.installDir)
        AppsLink.ensure()
        var finished = false
        defer { if !finished { try? fm.removeItem(at: app) } }
        // The entitlements it's signed with are written beside it, for the same reason: in the app's folder they
        // could be changed between Lamp writing them and codesign reading them.
        let signing = app.deletingPathExtension().appendingPathExtension("signing")
        try fm.createDirectory(at: signing, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: signing) }
        let resources = app.appendingPathComponent("Contents/Resources")
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        Self.setInstallValues(for: project, in: app.appendingPathComponent("Contents/Info.plist"), root: Self.installDir, wishKey: wishKey(for: project))
        // Every usage description, from the one list: without its reason macOS kills the app the moment it
        // asks for the microphone, photos and the rest. Added here as well as in build.sh so apps made before
        // a reason was added get it too.
        var plist = """
            P="$LAMP_APP/Contents/Info.plist"
            /usr/bin/plutil -replace CFBundleName -string "$LAMP_NAME" "$P" && \\
            /usr/bin/plutil -replace CFBundleDisplayName -string "$LAMP_NAME" "$P"

            """
        for (key, text) in Template.macUsageDescriptions {
            let reason = text.replacingOccurrences(of: "{{NAME}}", with: project.name).replacingOccurrences(of: "'", with: "'\\''")
            plist += "/usr/bin/plutil -replace \(key) -string '\(reason)' \"$P\"\n"
        }
        _ = await Shell.run(plist, cwd: project.dir, env: ["LAMP_APP": app.path, "LAMP_NAME": project.name]) { _ in }
        if fm.fileExists(atPath: Icons.icnsURL(project).path) {
            try? fm.removeItem(at: resources.appendingPathComponent("AppIcon.icns"))
            try fm.copyItem(at: Icons.icnsURL(project), to: resources.appendingPathComponent("AppIcon.icns"))
            // With Xcode 26, the compiled Icon Composer icon lets macOS 26 draw it in Liquid Glass.
            try? fm.removeItem(at: resources.appendingPathComponent("Assets.car"))
            let hasCar = fm.fileExists(atPath: Icons.carURL(project).path)
            if hasCar { try fm.copyItem(at: Icons.carURL(project), to: resources.appendingPathComponent("Assets.car")) }
            let iconName = hasCar
                ? "/usr/bin/plutil -replace CFBundleIconName -string AppIcon \"$LAMP_APP/Contents/Info.plist\""
                : "{ /usr/bin/plutil -remove CFBundleIconName \"$LAMP_APP/Contents/Info.plist\" 2>/dev/null || true; }"
            _ = await Shell.run("""
                /usr/bin/plutil -replace CFBundleIconFile -string AppIcon "$LAMP_APP/Contents/Info.plist" && \(iconName)
                """, cwd: project.dir, env: ["LAMP_APP": app.path]) { _ in }
        }
        // The app's own files (Assets/) ship inside it, where LampAssets finds them; the chat's attachments
        // don't. A binary built by an older Lamp (a new icon installed without a rebuild) still looks for
        // Attachments, so that folder is kept for it until it's rebuilt.
        Sharing.Assets.adopt(in: project)
        let assets = project.dir.appendingPathComponent(Sharing.Assets.folder)
        try? fm.removeItem(at: resources.appendingPathComponent(Sharing.Assets.folder))
        if fm.fileExists(atPath: assets.path) {
            try fm.copyItem(at: assets, to: resources.appendingPathComponent(Sharing.Assets.folder))
        }
        try? fm.removeItem(at: resources.appendingPathComponent(Attachments.folder))
        if BuildStamp.read(app)?.isOutdated ?? true {
            let attachments = project.dir.appendingPathComponent(Attachments.folder)
            if fm.fileExists(atPath: attachments.path) {
                try fm.copyItem(at: attachments, to: resources.appendingPathComponent(Attachments.folder))
            }
        }
        // What the agent declared in capabilities.json, as the simulator's bundle gets its own (finishSimulatorBundle).
        let capabilities = Template.Capabilities.load(project)
        capabilities.apply(to: app, for: project)
        // Told once: from now on the app opens at login and keeps running, which is the person's to undo.
        let told = project.dir.appendingPathComponent(".lamp/background-told")
        if capabilities.background == true, !FileManager.default.fileExists(atPath: told.path) {
            FileManager.default.createFile(atPath: told.path, contents: nil)
            log(project, .status, "\(project.name) works in the background: it opens when you log in and keeps running after you close its windows. To stop that, turn off Open at Login in its settings, or in System Settings → General → Login Items.")
        }
        // Signed from Lamp's own keychain, which the script unlocks, so nobody is asked for keychain access.
        // Files copied into the bundle (attachments, icon artwork, an edited Info.plist) can carry Finder
        // metadata and resource forks. codesign accepts those for an ad hoc signature but refuses them for a
        // certificate one ("resource fork, Finder information, or similar detritus not allowed"), which is
        // how apps silently ended up ad hoc. Strip them first.
        // The chat the app shows inside its window, signed with the app.
        try Sidebar.install(into: app, for: project, entitlementsIn: signing)
        _ = await Shell.run("/usr/bin/xattr -cr \"$LAMP_APP\"", cwd: project.dir, env: ["LAMP_APP": app.path]) { _ in }
        // A widget keeps its own signature inside the app's (AppSigning.command), with entitlements Lamp
        // writes beside the copy rather than takes from the build folder, where anything could have changed them.
        let widget = Template.widgetURL(in: app, of: project)
        let hasWidget = fm.fileExists(atPath: widget.path)
        if hasWidget, project.platform == .mac {
            Self.setInstallValues(for: project, in: widget.appendingPathComponent("Contents/Info.plist"), root: Self.installDir,
                                  values: Template.widgetInstallValues(for: project))
        }
        let entitlements = signing.appendingPathComponent("widget-entitlements.plist")
        if hasWidget { try Template.widgetEntitlementsPlist.write(to: entitlements, atomically: true, encoding: .utf8) }
        // A share extension the same way. It hands what it's given to the app through a folder they share,
        // which macOS allows only to a signature with a team, so it stays only in an app signed for one.
        let share = Template.shareURL(in: app, of: project)
        var hasShare = project.platform == .mac && fm.fileExists(atPath: share.path)
        let shareEntitlements = signing.appendingPathComponent("share-entitlements.plist")
        var signingEnv = ["LAMP_APP": app.path, "LAMP_WIDGET": widget.path, "LAMP_WIDGET_ENTITLEMENTS": entitlements.path,
                          "LAMP_SHARE": share.path, "LAMP_SHARE_ENTITLEMENTS": shareEntitlements.path]
            .merging(Sidebar.signingEnvironment(in: app, entitlementsIn: signing)) { $1 }
        // Only a build that is this app is signed as it: an id rewritten after build.sh, signed with Lamp's
        // certificate, would get that other app's permissions and keychain items. Read from the copy, which only
        // Lamp writes, just before it's signed, as a bundle that leads nowhere else.
        try Self.checkContained(app)
        try Self.checkOwnIDs(in: app, for: project)
        // An app for both is signed for the person's team, never with Lamp's own certificate, which could carry neither
        // its team's ids nor what Apple ties to a team. Its build is unsigned (it ran in the app's sandbox, without the
        // keys); what it's signed with is what Xcode signed Lamp's own project with for the Mac (`TeamSigning`): that
        // profile, put in the copy, and those entitlements.
        // For an app for both, the team's certificate is looked up only after Xcode has signed Lamp's own project, which
        // makes one the first time.
        let identity = project.platform == .universal ? "-" : await AppSigning.identity()
        var signed = false
        if project.platform == .universal, !Devices.team.isEmpty {
            signed = try await Self.signForTeam(app, for: project, team: Devices.team, env: signingEnv)
        } else {
            // A Mac app is signed for the person's Apple team when there is one: macOS runs an app's App Intents
            // (Siri, Shortcuts, Spotlight) only for an app signed with a team. Otherwise Lamp's own certificate.
            if project.platform == .mac, let team = await Devices.signingIdentity(for: Devices.team) {
                // Signed for a team, the app and its extensions can share a folder, where the widget's buttons queue
                // what they ask of the app (`LampWidget.perform`) and the share extension leaves what it was given
                // (`LampShare`); each is told its name in its Info.plist.
                var env = signingEnv.merging(["LAMP_IDENTITY": team]) { $1 }
                if hasWidget || hasShare {
                    let group = Template.macAppGroup(team: Devices.team, for: project)
                    Self.setAppGroup(group, in: [app] + (hasWidget ? [widget] : []) + (hasShare ? [share] : []))
                    let appEntitlements = signing.appendingPathComponent("app-entitlements.plist")
                    try Template.Capabilities().entitlementsPlist(container: nil, platform: .mac, appGroup: group)
                        .write(to: appEntitlements, atomically: true, encoding: .utf8)
                    if hasWidget { try Template.widgetEntitlementsPlist(appGroup: group).write(to: entitlements, atomically: true, encoding: .utf8) }
                    if hasShare { try Template.macShareEntitlementsPlist(appGroup: group).write(to: shareEntitlements, atomically: true, encoding: .utf8) }
                    env["LAMP_APP_ENTITLEMENTS"] = appEntitlements.path
                }
                var output: [String] = []
                signed = await Shell.run(AppSigning.command(adHoc: false, widget: hasWidget, share: hasShare, ownKeychain: false,
                                                            appEntitlements: hasWidget || hasShare),
                                         cwd: project.dir, env: env) { output.append($0) } == 0
                    && AppSigning.isCertificateSigned(app) && (!hasWidget || AppSigning.isCertificateSigned(widget))
                    && (!hasShare || AppSigning.isCertificateSigned(share))
                if !signed { print("Signing \(project.name) for the team failed:\n" + output.joined(separator: "\n")) }
                Self.rememberTeamSigning(failed: !signed, for: project)
            }
            if !signed, project.platform == .mac {
                // Not signed for a team, the app's intents would be listed by macOS and never run: they're taken
                // out. The widget's stay: its buttons run them inside the widget, which needs no team. Nor is
                // there a shared folder: the widget sends its actions to the app over their connection instead.
                try? fm.removeItem(at: app.appendingPathComponent("Contents/Resources/Metadata.appintents"))
                if hasWidget {
                    Self.setAppGroup(nil, in: [app, widget])
                    try Template.widgetEntitlementsPlist.write(to: entitlements, atomically: true, encoding: .utf8)
                }
                // A share extension with no folder to leave things in would take what people share and lose it:
                // it's left out, and `look_at_app` says why (`shareHint`).
                if hasShare {
                    try? fm.removeItem(at: share)
                    hasShare = false
                }
            }
        }
        if !signed, project.platform != .universal, identity != "-" {
            var output: [String] = []
            signingEnv["LAMP_IDENTITY"] = identity
            signingEnv["LAMP_KEYCHAIN"] = AppSigning.keychain
            signed = await Shell.run(AppSigning.command(adHoc: false, widget: hasWidget),
                                     cwd: project.dir, env: signingEnv) { output.append($0) } == 0
            // Trust the result, not the exit status: check the app really carries the certificate.
            if signed && !(AppSigning.isCertificateSigned(app) && (!hasWidget || AppSigning.isCertificateSigned(widget))) {
                signed = false
                output.append("codesign returned 0 but the app is not certificate-signed")
            }
            if !signed { print("Signing \(project.name) with \(identity) failed:\n" + output.joined(separator: "\n")) }
        }
        print("Install \(project.name): identity=\(identity) signed=\(signed)")
        if !signed {
            // Ad hoc keeps the app installable, but macOS won't remember its permissions across rebuilds and
            // won't ask for Location Services at all, so the person is told, once.
            _ = await Shell.run(AppSigning.command(adHoc: true, widget: hasWidget), cwd: project.dir, env: signingEnv) { _ in }
            if AppSigning.needsAdHocNotice(after: logs[project.id] ?? []) {
                log(project, .status, AppSigning.adHocNotice(for: project.name))
            }
        }

        // Read once more from what was signed: the copy, its ids and its signatures. Only Lamp writes the copy, so
        // what's read here is what's swapped in.
        try Self.checkContained(app)
        try Self.checkOwnIDs(in: app, for: project, signed: true)

        // What the copy being replaced was signed as, to notice when this build is signed differently. Only a copy
        // of this app, by its id: one of another id at the same place (an app of the same name since deleted, or
        // made by Lamp with other settings) had no permissions of this app's to lose.
        // Read from the file, not `Bundle`, which keeps what it read of a path for as long as Lamp runs.
        let previousID = NSDictionary(contentsOf: project.installedURL.appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"] as? String
        let replaced = previousID == project.bundleID ? await AppSigning.requirement(of: project.installedURL) : nil
        let requirement = replaced == nil ? nil : await AppSigning.requirement(of: app)
        finished = true
        return SignedCopy(app: app, signed: signed, replaced: replaced, requirement: requirement, iconReady: iconReady)
    }

    /// The rest of `deploy`, once the app is closed: the signed copy takes the installed one's place.
    private func swapIn(_ copy: SignedCopy, for project: LampProject) async throws {
        let fm = FileManager.default, app = copy.app
        var swapped = false
        defer { if !swapped { copy.discard() } }
        // What Lamp signed as the app's sidebar, the one program it will talk to there.
        Sidebar.remember(project, signed: app)

        // The app isn't running by now (a build quits it, an icon waits for it to close), but its widget's
        // process may be: ended here, last thing before the swap, so no program outlives the copy it came from.
        await WidgetProcess.end(for: project)
        if fm.fileExists(atPath: project.installedURL.path) {
            _ = try fm.replaceItemAt(project.installedURL, withItemAt: app)
        } else {
            try fm.createDirectory(at: project.installedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: app, to: project.installedURL)
        }
        swapped = true
        if copy.iconReady { Self.iconReachedApp(project) }
        // What the app now runs when it opens is this build's sources (LiveReload compares a change with them).
        LiveReload.installed(project)
        // The installed app's classes hold every property it was built with, and its spare places are empty.
        LiveSlots.clear(project)
        // What's installed is what the app runs now, whatever was set aside before.
        setAsideChanges[project.id] = nil
        if LiveReload.eligible(project) {
            let built = LiveReload.built(project)
            LiveReload.markRunning(project, from: FileManager.default.fileExists(atPath: built.path) ? built : nil)
            LiveReload.keepInstalled(project)
        } else {
            LiveReload.forget(project)
        }
        // Nudge Finder, the Dock and Launchpad to pick up the new icon. Opening the app doesn't wait for it (macOS
        // registers an app it's asked to open), unless its permissions are to be cleared, which needs it registered.
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: project.installedURL.path)
        let register = Task {
            _ = await Shell.run(
                Self.lsregister + " -f \"$LAMP_APP\"",
                cwd: project.dir, env: ["LAMP_APP": project.installedURL.path]) { _ in }
        }
        // macOS keeps a permission with the signature it was given to. Signed differently, the app has lost
        // what it had, but System Settings still shows the old entries switched on, and they do nothing.
        if let replaced = copy.replaced, let requirement = copy.requirement, replaced != requirement {
            await register.value
        }
        if let replaced = copy.replaced, let requirement = copy.requirement, replaced != requirement,
           await AppSigning.forgetPermissions(of: project.bundleID) {
            print("\(project.name) is signed differently from the copy it replaced, so its macOS permissions were cleared:\n"
                  + "  was: \(replaced)\n  now: \(requirement)")
            // An app signed ad hoc is signed differently every time: that was said when it was signed.
            if copy.signed {
                log(project, .status, "If you gave \(project.name) a permission in System Settings (such as Full Disk Access or Screen Recording), macOS needs it once more: Lamp signs apps with a new certificate. After that it stays on.")
            }
        }
    }

    // MARK: - Icons

    /// Makes sure icon.json exists, then renders it (with cached artwork if there is any).
    private func prepareIcon(_ project: LampProject) async {
        // One prepared while the app went on goes first.
        await iconPreparations[project.id]?.value
        await drawIcon(project)
    }

    /// `prepareIcon` without waiting for it, for a change that went into the open app: whatever puts a copy together
    /// next waits for it (`stageSigned`).
    private func prepareIconMeanwhile(_ project: LampProject) {
        let before = iconPreparations[project.id]
        iconPreparations[project.id] = Task { [weak self] in
            await before?.value
            await self?.drawIcon(project)
        }
    }

    private func drawIcon(_ project: LampProject) async {
        // A part's design is its wish's, which may still be on its way.
        await iconDesigns[wish(of: project).id]?.value
        var spec = Icons.load(project)
        if spec == nil && project.untitled { return }   // keeps its placeholder until the first message
        if project.isDeviceSetup { return }   // a device's setup is shown with the device's own symbol, not an app's icon
        if spec == nil {
            log(project, .status, "Designing an icon…")
            spec = await Icons.design(for: project)
            Icons.save(spec!, for: project)
        }
        // A wish Lamp came with has its icon already, drawn when Lamp was made, until its design changes.
        if Starters.hasShippedIcon(project), icons[project.id] != nil { return }
        await renderIcon(project, spec: spec!)
    }

    /// Every render of an app's icon goes through here, one after another: New Icon, new artwork and an install
    /// can ask at once, and two at a time would write the same files.
    private func renderIcon(_ project: LampProject, spec: IconSpec) async {
        let before = iconRenders[project.id]
        let mine = Task { [weak self] in
            await before?.value
            await self?.renderIconNow(project, spec: spec)
        }
        iconRenders[project.id] = mine
        await mine.value
    }

    private func renderIconNow(_ project: LampProject, spec: IconSpec) async {
        do {
            let art = Icons.artwork(project, spec: spec)
            if art != nil { artApplied[project.id] = spec }
            let waiting = art == nil && awaitsArtwork(project, spec: spec)
            icons[project.id] = try await Icons.write(spec, art: art ?? (waiting ? .waiting : nil), for: project)
            // The app keeps the blueprint until an install takes it what's drawn now (`iconReachedApp`).
            let marker = Icons.waitingURL(project)
            if waiting || FileManager.default.fileExists(atPath: marker.path) {
                try? Data((waiting ? Self.iconWaiting : Self.iconReady).utf8).write(to: marker)
            }
        } catch {
            log(project, .detail, "Icon render failed: \(error.localizedDescription)")
        }
    }

    /// Whether this design's artwork is on its way, drawn by Lamp: the icon is the blueprint until it comes. Not for a
    /// starter (it never gets any), nor while the person draws icons themselves, nor once drawing it failed.
    private func awaitsArtwork(_ project: LampProject, spec: IconSpec) -> Bool {
        !Starters.isStarter(project) && !AppAI.iconsByHand && !spec.subject.trimmed.isEmpty
            && !artFailed.contains(Icons.artKey(project, spec: spec)) && (GlassIcons.canDraw || AppAI.imageRoute != nil)
    }

    /// Artwork that won't come after all (`failed`: drawing it didn't work; otherwise the person now draws icons
    /// themselves): the icon goes from the blueprint to its symbol, in Lamp and on the app. While a turn has the app,
    /// it's put on the app when the turn ends (`finish`).
    private func artworkWontCome(_ project: LampProject, spec: IconSpec, failed: Bool = true) async {
        if failed { artFailed.insert(Icons.artKey(project, spec: spec)) }
        guard exists(project), Icons.load(project) == spec, Icons.artwork(project, spec: spec) == nil else { return }
        guard begin(project) != nil else {
            // Queued before rendering, which waits on Icon Composer: the turn may end meanwhile, and its `finish`
            // must find this.
            iconFallbackWhenFree.insert(project.id)
            await renderIcon(project, spec: spec)
            return
        }
        await renderIcon(project, spec: spec)
        if hasMacBuild(project) { await installIcon(project) }
        await iconToParts(of: project, spec: spec)
        finish(project)
    }

    /// A wish has one icon, and each of its apps carries it: what the app at its root was just given (artwork, a new
    /// design, its symbol in place of artwork that won't come), its other apps are given too, drawn into their own
    /// folders and put on any Mac app among them that's built. An iPhone app takes it when it next opens, as one on
    /// its own does. One busy now draws it at its next install (`prepareIcon`), from the design as it is then.
    private func iconToParts(of project: LampProject, spec: IconSpec) async {
        guard !project.isPart else { return }
        for part in parts(of: project) {
            // A part busy on its own (opened from its menu) takes it when it's given back (`finish`). What it last drew
            // is forgotten, since a picture chosen in its place keeps the same design and would otherwise pass for it.
            guard begin(part) != nil else {
                artApplied[part.id] = nil
                pendingIconArt.insert(part.id)
                continue
            }
            await renderIcon(part, spec: spec)
            if hasMacBuild(part) { await installIcon(part) }
            release(part)
            installHeldIcons(for: [part.id])
        }
    }

    /// Whether the app has a Mac build an icon can be installed into: an iPhone or TV app's build is no Mac app, and
    /// takes its icon when it opens.
    private func hasMacBuild(_ project: LampProject) -> Bool {
        FileManager.default.isExecutableFile(atPath: project.builtURL.appendingPathComponent("Contents/MacOS/\(project.exe)").path)
    }

    /// What `Icons.waitingURL` says: the icon drawn is the blueprint, or the icon that replaces it, drawn but not yet
    /// on the app (an install held while it was open, or one a quit of Lamp cut short).
    private static let iconWaiting = "waiting", iconReady = "ready"

    /// An install put the icon drawn now on the app: once that's the one that replaces the blueprint, nothing is left
    /// to pick up.
    private static func iconReachedApp(_ project: LampProject) {
        let marker = Icons.waitingURL(project)
        if (try? String(contentsOf: marker, encoding: .utf8)) == iconReady { try? FileManager.default.removeItem(at: marker) }
    }

    /// Icons left waiting for artwork when Lamp last quit: drawn now, or put on the app if they came meanwhile, or
    /// given their symbol when nothing can draw them any more.
    private func resumeWaitingIcons() {
        for project in projects where FileManager.default.fileExists(atPath: Icons.waitingURL(project).path) {
            guard let spec = Icons.load(project) else { continue }
            if (try? String(contentsOf: Icons.waitingURL(project), encoding: .utf8)) == Self.iconReady {
                // Drawn already, and only the install is missing: the app takes it now, or when it next closes. An app
                // that isn't installed on this Mac (an iPhone app, a TV app) took it when it last opened, or does next time.
                guard hasMacBuild(project) else {
                    try? FileManager.default.removeItem(at: Icons.waitingURL(project))
                    continue
                }
                Task {
                    guard begin(project) != nil else { return }
                    await installIcon(project)
                    finish(project)
                }
            } else if Icons.artwork(project, spec: spec) != nil {
                Task {
                    guard begin(project) != nil else { return }
                    await applyIconArt(project, spec: spec)
                    finish(project)
                }
            } else if awaitsArtwork(project, spec: spec) {
                upgradeIconArt(project)
            } else {
                Task { await artworkWontCome(project, spec: spec, failed: false) }
            }
        }
    }

    /// The setup offers already in an app's chat.
    func offers(in project: LampProject) -> Set<SetupOffer> {
        Set((logs[project.id] ?? []).compactMap(\.setupOffer))
    }

    /// Offers a way to set up `offer` in the app's chat, once per app: the moment an app first wants
    /// something nothing here can do is when a key or a download is worth explaining, not the welcome screen.
    /// Lamp's own offers (`fromAgent` false) also keep away from anything the person said "Not Now" to in
    /// any app; the agent's, which come with a reason of their own, only from what was turned down in this
    /// one. Returns what happened, in words for the agent.
    @discardableResult
    func offerSetup(_ project: LampProject, _ offer: SetupOffer, because reason: String, fromAgent: Bool = false) -> String {
        let resolution = AppAI.resolve(offer.capability, for: project, in: offer.context)
        guard resolution.tier != .best else {
            return "\(offer.capability.title) is already set up: \(resolution.answer ?? ""). Nothing to offer."
        }
        guard !offer.declined(in: fromAgent ? project : nil) else {
            return "The person said Not Now to setting this up. Don't offer it again; build so the app copes without it."
        }
        // An icon's card is answered apart from the app's pictures (it follows Settings' choices and the
        // choice to draw by hand, not the app's own models), so it can be all set while this isn't.
        let iconAnswered = AppAI.resolve(.pictures, for: project, in: .icon).tier == .best
        switch LogLine.standing(of: offer, in: logs[project.id] ?? [], iconAnswered: iconAnswered) {
        case .offered: return "Lamp already offered this in the chat. Don't offer it again."
        case .replaces(let index):
            // The card there was about the icon and is folded away, answered. This is about pictures the
            // app makes, which aren't: it takes that card's place, and an icon the person draws gets its
            // line instead.
            logs[project.id]?.remove(at: index)
            log(project, .offer, reason, offer: offer)
            upgradeIconArt(project)
        case .new: log(project, .offer, reason, offer: offer)
        }
        return "Lamp showed the person a card in the chat to set up \(offer.capability.title.lowercased()). Carry on; don't mention keys or settings in your reply."
    }

    /// Lamp's own words for an offer it makes when an app hit something nothing here can do.
    private static func offerReason(_ capability: Capability, for project: LampProject) -> String {
        switch capability {
        case .text: "\(project.name) just tried to use AI, but nothing on this Mac can answer yet. Set up one of the ways below and it will work the next time."
        case .decisions: "\(project.name) uses AI to make quick judgments, like yes or no, or which of a few options fits, but nothing on this Mac can make them yet. Set up one of the ways below and they will work the next time."
        case .browser: "\(project.name) also works in Chrome. Connect Lamp to Chrome to use it beside a page."
        case .pictures: "\(project.name) just tried to make a picture, but nothing on this Mac can draw yet. Set up one of the ways below and it will work the next time."
        }
    }

    /// An iPhone app that uses AI, just put on the phone: if nothing goes with it, say so once.
    private func offerAwaySetup(_ project: LampProject) {
        let sources = project.dir.appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        let usesAI = files.contains { url in
            url.pathExtension == "swift" && url.lastPathComponent != "LampSupport.swift"
                && ((try? String(contentsOf: url, encoding: .utf8))?.contains("LampAI.") ?? false)
        }
        guard usesAI else { return }
        offerSetup(project, SetupOffer(capability: .text, away: true),
                   because: "\(project.name)'s AI runs through this Mac, so on your phone it only works nearby. Add an OpenRouter key and the app takes it along, so its AI works anywhere.")
    }

    /// Generates artwork for the icon's object in the background (best of a few candidates) and swaps it in
    /// when ready: layers of glass where the model that draws them can be reached, else a painting with whatever
    /// can make pictures, and always a painting for a game. With nothing, the first app asks for a key instead.
    private func upgradeIconArt(_ project: LampProject) {
        // A part's artwork is its wish's: drawn once, for the wish, and given to each of its apps (`iconToParts`).
        let project = wish(of: project)
        guard !Starters.isStarter(project), let spec = Icons.load(project), !spec.subject.trimmed.isEmpty,
              Icons.artwork(project, spec: spec) == nil else { return }
        // The person chose to draw icons themselves: Lamp draws nothing, key or no key, and asks for no key.
        guard !AppAI.iconsByHand else { return offerDrawing(project, spec: spec) }
        guard artInProgress.insert(project.id).inserted else { return }
        Task {
            defer { artInProgress.remove(project.id) }
            guard await AppAI.imageRoute() != nil else {
                offerSetup(project, SetupOffer(capability: .pictures, icon: true),
                           because: "Nothing on this Mac can draw pictures yet. Set up one of the ways below and Lamp will paint \(project.name) a proper icon, and your apps will be able to make pictures too.")
                return await artworkWontCome(project, spec: spec)
            }
            // The person may choose to draw icons themselves during either wait here: from then on nothing
            // Lamp drew is used, and the drawing is theirs to do; the icon is its symbol until then.
            guard !AppAI.iconsByHand else {
                offerDrawing(project, spec: spec)
                return await artworkWontCome(project, spec: spec, failed: false)
            }
            do {
                let log: @MainActor (String) -> Void = { [weak self] in self?.log(project, .detail, $0) }
                let art: Icons.Artwork
                if !spec.game, GlassIcons.canDraw {
                    let about = AppFile.text(project.dir.appendingPathComponent("APP.md"), in: project) ?? ""
                    art = .glass(try await GlassIcons.generateBest(for: spec, appName: project.name, about: about, log: log))
                } else {
                    art = .picture(try await Icons.generateBestArt(spec, appName: project.name, log: log))
                }
                guard !AppAI.iconsByHand else {
                    offerDrawing(project, spec: spec)
                    return await artworkWontCome(project, spec: spec, failed: false)
                }
                // Deleted while these were being drawn: saving would make its folder again, outside the Trash.
                guard exists(project) else { return }
                // A picture picked in Image Playground while these were being drawn is the person's choice: it stays.
                guard Icons.artwork(project, spec: spec) == nil else { return }
                switch art {
                case .glass(let glass):
                    try Icons.save(glass, for: project, spec: spec)
                case .waiting: return
                case .picture(let image):
                    let url = Icons.artURL(project, spec: spec)
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?
                        .representation(using: .png, properties: [:]) else { return }
                    try png.write(to: url)
                }
                guard Icons.load(project) == spec else { return }   // the icon was redesigned meanwhile
                // During a build the install that ends it picks the artwork up; if that install came first,
                // finish() applies it. Otherwise apply it now.
                // Deploying touches build/ and the installed app, so it owns the app like a turn does. If a
                // turn has it, the install that ends the turn (or finish()) picks the artwork up; the chat
                // shows the artwork now, so "designed an icon" isn't a tick beside the old one.
                guard begin(project) != nil else {
                    pendingIconArt.insert(project.id)
                    // Rendering takes a moment, and the turn may redesign the icon meanwhile (or restore a version
                    // with another): the preview is kept only if the design is still this one.
                    let preview = await Icons.preview(spec, art: art)
                    if exists(project), Icons.load(project) == spec { icons[project.id] = preview }
                    return
                }
                await applyIconArt(project, spec: spec)
                finish(project)
            } catch let failure as AppAI.Failure where failure.needs == .pictures {
                // Codex signed out between the check and the pictures: the key card is still the right answer.
                offerSetup(project, SetupOffer(capability: .pictures, icon: true),
                           because: "Nothing on this Mac can draw pictures yet. Set up one of the ways below and Lamp will paint \(project.name) a proper icon, and your apps will be able to make pictures too.")
                await artworkWontCome(project, spec: spec)
            } catch {
                log(project, .detail, "Couldn't draw the icon's artwork. \(error.localizedDescription)")
                await artworkWontCome(project, spec: spec)
            }
        }
    }

    /// Says in the chat that the app's icon is waiting to be drawn, with the button that opens Image
    /// Playground: once per design, and once the app has been built. While a turn has the app (the agent
    /// builds and opens it to look at it, long before it's done) the offer is held, like artwork that
    /// arrives mid-turn, and made when the turn finishes (`offerHeldDrawing`), so it's the last line of
    /// the turn and not one among its steps. An app whose chat has the card about its icon (from before
    /// the person chose to draw icons) has the button there, for whatever design it has.
    private func offerDrawing(_ project: LampProject, spec: IconSpec) {
        let key = Icons.artKey(project, spec: spec)
        switch LogLine.drawingOffer(key, after: logs[project.id] ?? [],
                                    built: FileManager.default.fileExists(atPath: project.builtURL.path),
                                    inTurn: turns[project.id] != nil) {
        case .none: break
        case .held: heldDrawingOffers.insert(project.id)
        case .now: log(project, .drawIcon, key)
        }
    }

    /// Designs a fresh icon (different from the current one). An app that's open keeps running: it gets the
    /// icon when it closes.
    func newIcon(_ project: LampProject) async {
        guard begin(project) != nil else { return }
        defer { finish(project) }
        log(project, .status, "Designing a new icon…")
        let spec = await Icons.design(for: project, avoiding: Icons.load(project))
        Icons.save(spec, for: project)
        await renderIcon(project, spec: spec)
        var waits = false
        if FileManager.default.fileExists(atPath: project.builtURL.path) {
            waits = await !installIcon(project)
        }
        await iconToParts(of: project, spec: spec)
        let applied = waits ? "New icon made. \(project.name) gets it the next time it closes." : "New icon applied."
        // Drawn by hand, the new design's artwork is the person's to make: the sheet opens for it now.
        guard !AppAI.iconsByHand else {
            log(project, .status, applied)
            return iconFromPlayground(project)
        }
        log(project, .status, AppAI.imageRoute != nil ? applied + " Artwork is on its way." : applied)
        Task { upgradeIconArt(project) }
    }

    /// Opens Image Playground to make this app's icon, with a request for the icon's object already typed in.
    func iconFromPlayground(_ project: LampProject) {
        playgroundIcon = project
        showingPlayground = true
    }

    /// The request Image Playground opens with.
    var playgroundPrompt: String {
        playgroundIcon.flatMap(Icons.load).map(Icons.playgroundPrompt) ?? ""
    }

    /// Makes the picture picked in Image Playground the icon's artwork: cut out and kept where generated
    /// artwork is, so composing, installing and sharing treat it as they treat any other.
    func useIconPicture(_ picture: Data, for project: LampProject) async {
        guard let spec = Icons.load(project) else { return }
        do {
            let png = try await Task.detached { () throws -> Data in
                let art = try Icons.cutOut(picture)
                guard let tiff = art.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                    throw AppAI.Failure(message: "Couldn't save the picture.")
                }
                return png
            }.value
            // Nothing owned the app during the cut-out: it may have been deleted meanwhile, or a turn may have
            // redesigned its icon, and the picture was made for the design it replaced.
            guard exists(project) else { return }
            guard Icons.load(project) == spec else {
                log(project, .status, "\(project.name)'s icon changed while that picture was being prepared, so it wasn't used.")
                return
            }
            let url = Icons.artURL(project, spec: spec)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: url)
            // The person's picture takes the place of a glass design drawn for the same icon.
            try? FileManager.default.removeItem(at: Icons.glassURL(project, spec: spec))
            // The icon on show was made with other artwork, or none, on the wish's other apps too.
            for app in [project] + parts(of: project) { artApplied[app.id] = nil }
            // As with generated artwork: a turn that has the app installs the picture when it ends. The chat
            // shows it at once and says so, or picking it would look like nothing happened.
            guard begin(project) != nil else {
                pendingIconArt.insert(project.id)
                let preview = await Icons.preview(spec, art: NSImage(data: png).map(Icons.Artwork.picture))
                if exists(project), Icons.load(project) == spec {
                    icons[project.id] = preview
                    log(project, .status, "Your picture is \(project.name)'s icon now. It goes on the app when this turn ends.")
                }
                return
            }
            await applyIconArt(project, spec: spec)
            finish(project)
        } catch {
            log(project, .status, "That picture couldn't become \(project.name)'s icon: \(error.localizedDescription)")
        }
    }

    /// Gives apps made before icons existed an icon, once.
    private func backfillIcons() async {
        for project in projects where Icons.load(project) == nil {
            // Owning the app for the whole of it: the icon design is an AI call, and a build starting
            // meanwhile would get a half-finished bundle installed.
            guard begin(project) != nil else { continue }
            await prepareIcon(project)
            if FileManager.default.fileExists(atPath: project.builtURL.path) {
                await installIcon(project)
            }
            finish(project)
            upgradeIconArt(project)
        }
    }

    /// Runs an app that is only its widget, out of sight (it has no window and no Dock icon), so it can say
    /// whether the widget is placed. It quits by itself once it is, or after a while.
    private func watchWidget(of project: LampProject) async {
        guard FileManager.default.fileExists(atPath: project.installedURL.path), !isRunning(project) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true
        config.addsToRecentItems = false
        _ = try? await NSWorkspace.shared.openApplication(at: project.installedURL, configuration: config)
    }

    /// Which widgets are placed, read from what each app last said, for the cards on show. Asked every couple
    /// of seconds: a small file per app with a card.
    private func refreshWidgetCards() {
        let placed = Set(projects.filter { project in
            (logs[project.id] ?? []).contains { $0.kind == .widget } && WidgetCard.isPlaced(project)
        }.map(\.id))
        if placed != placedWidgets { placedWidgets = placed }
    }

    /// Back in Lamp, perhaps from adding a widget or taking one away: an app that is only its widget, and
    /// has stopped waiting to hear, is asked again.
    private func askAboutWidgets() {
        for project in projects where WidgetCard.asksAgain(hasCard: (logs[project.id] ?? []).contains { $0.kind == .widget },
                                                             widgetOnly: Template.isWidgetOnly(project), busy: busy.contains(project.id)) {
            Task { await watchWidget(of: project) }
        }
    }

    /// Keeps `openApps` current as apps launch and quit. Menu bar apps don't always announce themselves,
    /// so it's also checked whenever Lamp comes to the front and after Lamp opens or quits one.
    private func watchOpenApps() {
        refreshOpenApps()
        // Builds that were waiting for their app to close when Lamp was last quit: still waiting, and one
        // whose app has closed since goes in now.
        projects.forEach(LiveReload.recoverUnfinishedBuild)
        for project in projects where Runtime.holdsBuild(project) || LiveReload.awaitsInstall(project) {
            _ = heldInstalls.mayInstall(project.id, running: true)
        }
        installHeldIcons(for: heldInstalls.waiting)
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let installer = app?.bundleIdentifier == SetupCheck.installerID
                MainActor.assumeIsolated {
                    Store.shared.refreshOpenApps()
                    if name == NSWorkspace.didTerminateApplicationNotification, let app { Store.shared.appEnded(app) }
                    if installer { Store.shared.installerChanged(open: name == NSWorkspace.didLaunchApplicationNotification) }
                }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                Store.shared.refreshOpenApps()
                Store.shared.askAboutWidgets()
                Store.shared.cameBackFromInstaller()
            }
        }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { Store.shared.refreshWidgetCards() }
        }
        Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            MainActor.assumeIsolated { Store.shared.reloadIfAway() }
        }
    }

    func refreshOpenApps() {
        let prefix = Edition.appBundlePrefix
        // By the app's whole id first: an app for both carries the team in its id, which isn't its folder's name.
        let byBundle = Dictionary(projects.map { ($0.bundleID, $0.id) }, uniquingKeysWith: { first, _ in first })
        // Then by where it runs from: a copy with another id at an app's place is that app's (`macCopies`).
        let byPlace = Dictionary(projects.map { ($0.installedURL.standardizedFileURL.resolvingSymlinksInPath(), $0.id) },
                                 uniquingKeysWith: { first, _ in first })
        let onMac = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }.compactMap { app -> String? in
            if let id = app.bundleIdentifier, let project = byBundle[id] { return project }
            if let place = app.bundleURL?.standardizedFileURL.resolvingSymlinksInPath(), let project = byPlace[place] { return project }
            return app.bundleIdentifier.flatMap { $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : nil }
        }
        simulatorApps = simulatorApps.filter { Simulator.isRunning(pid: $0.value.pid) }
        deviceApps = deviceApps.filter { $0.value.isRunning }
        // An Android app is open while its process is, which `AndroidRun` watches.
        androidApps = androidApps.filter { $0.value.alive }
        // A TV app is open while its preview is, unless a TV is chosen: then Play is for putting it on the TV, which
        // Lamp can't watch, so it always offers Play.
        let previews = TVPreview.openIDs.filter { id in projects.first { $0.id == id }.map { $0.onTV && $0.device == nil } ?? false }
        // A device app is open while it's the one Lamp last put on its device, so Stop can take the device back.
        let onIOS = Array(simulatorApps.keys) + Array(deviceApps.keys) + Array(androidApps.keys) + previews + Array(deviceRuns.keys)
        // A build or icon held for a Mac copy goes in when that copy closes, even with its iPhone copy still open.
        let closedOnMac = openOnMac.subtracting(onMac)
        if Set(onMac) != openOnMac { openOnMac = Set(onMac) }
        if Set(onIOS) != openOnIOS { openOnIOS = Set(onIOS) }
        let ids = onMac + onIOS
        let closed = openApps.subtracting(ids).union(closedOnMac)
        if Set(ids) != openApps { openApps = Set(ids) }
        if !closed.isEmpty { installHeldIcons(for: closed) }
    }

    /// Quits the app, for the Stop button. It's asked, and its answer is waited for: an app asking about
    /// unsaved work stays open until the person has said what to do with it.
    /// An app for both is quit only where Try On points: its other copy stays open.
    func quitApp(_ project: LampProject) async {
        await quit(project, only: project.platform.choosesPlace ? project.destination : nil)
        refreshOpenApps()
    }

    /// Apps that were asked to quit and aren't responding, with the process that isn't: the chat offers to
    /// force it to quit while this holds. Lamp never does that itself.
    @Published private(set) var notResponding: [String: pid_t] = [:]

    /// The person's click on Force Quit: ends the copy that isn't responding, and whatever was waiting for
    /// it to close (a build, Lamp's Quit, Delete) goes on.
    /// Before Lamp itself ends an app: a launch still being watched takes its going for a death only when it's
    /// surely a crash (`watchLaunch`).
    private func retireLaunches(of project: LampProject) {
        for watch in turns[project.id]?.launches ?? [] where watch.app == project.id { watch.retire() }
    }

    func forceQuit(_ project: LampProject) {
        retireLaunches(of: project)
        guard let pid = notResponding.removeValue(forKey: project.id),
              let app = macCopies(of: project).first(where: { $0.processIdentifier == pid }) else { return }
        app.forceTerminate()
    }

    /// Asks the app to quit (AppQuit says how its answer is read). False when its Mac copy stays open: the
    /// person kept it, at its question about unsaved work, or `owner`'s turn was stopped while it was asking.
    @discardableResult
    /// `only` quits the copy in one place (an app for both can be open on this Mac and in a simulator at once);
    /// without it every copy is quit, as deleting or renaming the app needs.
    private func quit(_ project: LampProject, for owner: Turn? = nil, only place: Destination? = nil) async -> Bool {
        // Lamp closing it isn't the app dying on launch.
        retireLaunches(of: project)
        if project.onDevice {
            // Its preview on this Mac too, with the page's sound and timers.
            TVPreview.close(project)
            refreshOpenApps()
            deviceRunBuilt[project.id] = nil
            if let run = deviceRuns.removeValue(forKey: project.id) {
                run.end()
                // Home takes a device back from the app, where its remote has one.
                if DeviceApps.keys(for: project).contains("home") { try? await DeviceApps.press("home", in: project, on: run.device) }
            }
            return true
        }
        if project.onTV {
            TVPreview.close(project)
            refreshOpenApps()
            return true
        }
        if project.onAndroid {
            if let running = androidApps[project.id] {
                await Adb.stop(Template.androidPackage(for: project), on: running.serial)
                running.end()
                if androidLeases[running.serial] == project.id { androidLeases[running.serial] = nil }
            }
            androidApps[project.id] = nil
            refreshOpenApps()
            return true
        }
        if project.hasIOS, place != .mac {
            if let attached = deviceApps[project.id] {
                if attached.isRunning { attached.terminate() }
                deviceApps[project.id] = nil
            }
            // On the simulator it was launched on, not whichever one would be picked now.
            if let running = simulatorApps[project.id] {
                await Simulator.terminate(project.bundleID, on: running.udid)
                if simulatorLeases[running.udid] == project.id { simulatorLeases[running.udid] = nil }
            }
            simulatorApps[project.id] = nil
            refreshOpenApps()
            if !project.hasMac || place == .ios { return true }
        }
        // Nobody is waiting once the turn is stopped or over. Not `stopped`, which the agent's exit clears.
        // A part's work is its wish's turn (`requestOwner`), never one of its own.
        let ownerID = Self.requestOwner(of: project, among: projects).id
        let stopped = { owner.map { self.turns[ownerID] !== $0 || $0.wasStopped } ?? false }
        var closed = true
        for app in macCopies(of: project) {
            let gone = await AppQuit.close(app, id: project.id, runtime: Runtime.macFolder(project), stopped: stopped, asking: {
                // Its question may be behind Lamp's window: in front, the person sees what is being waited for,
                // and a build says in the chat that it's waiting.
                app.activate()
                if owner != nil { self.log(project, .status, "Waiting for \(project.name) to close…") }
            }, silent: { silent in
                // Stuck, or in the middle of something long: Lamp can't tell which, so ending it is theirs to
                // do, from the chat (`UnresponsiveNotice`). The app isn't brought in front of that.
                if !silent {
                    if self.notResponding[project.id] == app.processIdentifier { self.notResponding[project.id] = nil }
                    return
                }
                self.notResponding[project.id] = app.processIdentifier
                NSApp.requestUserAttention(.informationalRequest)
                if owner != nil { self.log(project, .status, "Waiting for \(project.name) to close…") }
            })
            if !gone { closed = false }
        }
        // Kept open: its launch is watched again for what's left of its first seconds.
        if !closed { for watch in turns[project.id]?.launches ?? [] where watch.app == project.id { watch.resume() } }
        return closed
    }

    // MARK: - AI gateway for generated apps

    private func startGateway() {
        let gateway = Gateway(handler: { request in await Store.shared.handleAI(request) },
                              pages: { request in await Store.shared.phonePage(request) })
        do {
            try gateway.start()
            self.gateway = gateway
            syncLocalNetwork()
        } catch {
            NSLog("Lamp AI gateway failed to start: \(error)")
        }
    }

    /// The gateway answers on the local network only while an app is set to open on the person's own phone or
    /// tablet, Apple's or Android's, or on a TV, or is an app for a device (which always opens on one) that takes Lamp's
    /// building blocks: kept in step with the list of apps (Try On, deletion, rename, reload). A TV app's phone page has a
    /// port of its own (`PhoneSites`), opened and closed here too, with the TV preview.
    func syncLocalNetwork() {
        gateway?.setLocalNetwork(everyApp.contains {
            (($0.hasIOS || $0.platform.reaches(.android) || $0.onTV) && $0.device != nil) || ($0.onDevice && !DeviceSupport.libraries(for: $0).isEmpty)
        })
        PhoneSites.sync(projects)
        WishRooms.sync(wishes.map { ($0, apps(of: $0)) })
    }

    /// Whether a TV app's phone page is handed out now: while the app runs, in the preview, or on a TV, which Lamp
    /// can't watch, for as long as it's the TV the app opens on. Lamp serves it so the agent never has to start a
    /// server of its own, which would outlive the app.
    static func servesPhonePage(_ project: LampProject) -> Bool {
        project.holdsApp && project.hasTV && (project.device != nil || TVPreview.window(project) != nil) && takesPlayers(project)
    }

    /// A TV app's phone page (`TVTemplate.phoneFolder`, as staged): GET /phone/<app>/<file>, from a phone on the
    /// network by this Mac's name or address, or on this Mac by a loopback name, like the rest of the gateway. No token:
    /// a browser opening a QR code's link has none, so the page is only ever the app's own files, which the agent is
    /// told anyone on the network can read while the app runs.
    func phonePage(_ request: Gateway.Request) async -> Gateway.Page {
        let missing = Gateway.Page(status: 404, body: Data("Nothing here. Open the app on the TV first.".utf8))
        let host = request.headers["host"]
        guard request.fromNetwork ? Self.isMacHost(host) : Self.isLocalHost(host) else {
            return Gateway.Page(status: 403, body: Data("Not for this host.".utf8))
        }
        let path = request.path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst(2).map { $0.removingPercentEncoding ?? "" }
        guard let id = parts.first, !id.isEmpty, let project = projects.first(where: { $0.id == id }), Self.servesPhonePage(project) else { return missing }
        // The page's own links are relative, so its address has to end in a slash.
        if parts.count == 1 { return Gateway.Page(status: 301, location: path + "/") }
        var names = Array(parts.dropFirst())
        if names.last == "" { names[names.count - 1] = "index.html" }
        // Lamp's own library for a controller page, served beside the app's files as if it were one of them.
        if names == ["lamp-controller.js"] {
            return Gateway.Page(status: 200, type: Self.pageType("js"), body: Data(TVTemplate.phoneControllerJS.utf8))
        }
        // Where lamp-controller.js opens its socket: the controllers' relay, on this Mac by the name the page was reached
        // at, asked before each try, since the relay may have started again elsewhere.
        if names == ["lamp-relay.json"] {
            guard let port = await ControllerRelay.ready(),
                  let body = try? JSONSerialization.data(withJSONObject: ["port": Int(port), "app": project.id]) else {
                return Gateway.Page(status: 503, body: Data("Lamp couldn't start the link for controllers.".utf8))
            }
            return Gateway.Page(status: 200, type: Self.pageType("json"), body: body)
        }
        // Only the staged copy's own files: no step up, nothing hidden, no empty name, nothing that isn't a plain file.
        guard names.allSatisfy({ !$0.isEmpty && !$0.hasPrefix(".") && !$0.contains("/") && !$0.contains("\0") }) else { return missing }
        guard let file = TVs.phoneFile(names, in: TVs.phoneFolder(for: project)),
              let data = try? Data(contentsOf: file) else { return missing }
        return Gateway.Page(status: 200, type: Self.pageType(file.pathExtension), body: data)
    }

    nonisolated static func pageType(_ ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": "text/html; charset=utf-8"
        case "js", "mjs": "text/javascript; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        case "json", "webmanifest": "application/json"
        case "svg": "image/svg+xml"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "webp": "image/webp"
        case "ico": "image/x-icon"
        case "woff2": "font/woff2"
        case "woff": "font/woff"
        case "mp3": "audio/mpeg"
        case "wav": "audio/wav"
        case "mp4": "video/mp4"
        case "txt": "text/plain; charset=utf-8"
        default: "application/octet-stream"
        }
    }

    func handleAI(_ request: Gateway.Request) async -> (Int, [String: Any]) {
        if BrowserBridge.enabled, request.path.hasPrefix("/browser/") {
            return BrowserBridge.shared.handle(request, projects: projects)
        }
        let route = request.path.split(separator: "?").first.map(String.init) ?? request.path
        let paths = ["/ai", "/ai/keys", "/ai/status", "/ai/image", "/ai/decide", "/ai/computer", "/agent/computer", "/agent/look", "/agent/use", "/agent/approve",
                     "/agent/versions", "/agent/versions/name", "/agent/versions/restore", "/agent/memory", "/agent/skill", "/agent/setup", "/agent/kind", "/agent/connectors", "/agent/integration", "/agent/art", "/agent/talk", "/agent/steer", "/mcp", "/pi/key", "/app/secrets", "/app/share", "/app/claim", "/app/controller", "/app/phone-page", "/app/wish", "/app/wish/open", "/app/wish/poll", "/app/wish/send", "/app/wish/claim"]
        // MCP clients may try to open a listening stream (GET) or end a session (DELETE): neither is offered.
        if route == "/mcp", request.method != "POST" { return (405, ["error": "Method not allowed"]) }
        guard request.method == "POST", paths.contains(route) else {
            return (404, ["error": "Not found"])
        }
        // Only requests addressed to this Mac: a web page that resolved its own name to 127.0.0.1 (DNS
        // rebinding) arrives with that name as the host, and gets nothing. No Host at all gets nothing either.
        let token = request.headers["authorization"]?.replacingOccurrences(of: "Bearer ", with: "") ?? ""
        let agentRoute = route == "/mcp" || route.hasPrefix("/agent/")
        if request.fromNetwork {
            // An app on the person's phone: only the app routes, addressed to this Mac by its network name,
            // with the app's own token like any other. The agent's routes never leave the Mac, and neither
            // does the one that hands pi its key.
            guard !agentRoute, route != "/pi/key", Self.isMacHost(request.headers["host"]) else {
                return (403, ["error": "Not for this host."])
            }
        } else {
            guard Self.isLocalHost(request.headers["host"]) else { return (403, ["error": "Not for this host."]) }
        }
        // An app Lamp has just put on a TV or another device asking for its token, which is never in its package: answered
        // only from the address of the device it was put on, for half an hour after (`DeviceSupport.Claims`).
        if route == "/app/claim" {
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
            guard request.fromNetwork, let id = body["app"] as? String, DeviceSupport.Claims.shared.take(id, from: request.peerAddress),
                  let project = projects.first(where: { $0.id == id }) else {
                return (403, ["error": "Lamp didn't just put this app here."])
            }
            return (200, ["token": Template.token(for: project), "routes": DeviceSupport.installValues(for: project)["routes"] ?? []])
        }
        // A wish's TV app Lamp has just put on a TV asking for its wish's key, sealed to the key pair its page just made
        // (`WishRooms.claim`): answered only from that TV's address, for minutes after Lamp put the app there, and once.
        if route == "/app/wish/claim" {
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
            guard request.fromNetwork, let id = body["app"] as? String,
                  let project = projects.first(where: { $0.id == id }), Template.talksToOtherApps(project),
                  let publicKey = (body["public"] as? String).flatMap({ Data(base64Encoded: $0) }) else {
                return (403, ["error": "Lamp didn't just put this app here."])
            }
            let wish = wish(of: project)
            return WishRooms.claim(for: project, wish: wish, apps: apps(of: wish), publicKey: publicKey, from: request.peerAddress)
        }
        // pi collecting its provider's key (Agent.keyCommand). The ticket is the whole credential, and it's
        // good once.
        if route == "/pi/key" {
            guard let key = KeyTicket.redeem(token) else { return (403, ["error": "This ticket isn't good any more."]) }
            return (200, ["key": key])
        }
        // A coding agent driving another app's task (ComputerUse.Job): its token opens only the task's own
        // tools, over MCP (Claude Code, Codex) or pi's extension's route, never the build tools.
        if let task = computerTasks[token] {
            guard route == "/mcp" || route == "/agent/computer" else { return (403, ["error": "Not for this task."]) }
            return await computerCall(request, task: task, mcp: route == "/mcp")
        }
        if agentRoute {
            // The agent's routes take only the agent's token for the turn in progress.
            guard let id = agentTokens[token], let project = projects.first(where: { $0.id == id }) else {
                return (401, ["error": "Lamp isn't working on this app right now."])
            }
            guard setup.ready else { return (503, ["error": "Lamp isn't set up yet. Open Lamp to finish setup."]) }
            guard turns[project.id]?.agent != nil else { return (409, ["error": "Lamp isn't working on this app right now."]) }
            if project.isDeviceSetup, let refusal = Self.deviceSetupRefusal(route: route, request: request) { return refusal }
            return await agentRequest(request, route: route, for: project)
        }
        // The app may have been created since the last reload. A reload rereads every app, so a stale app
        // polling with an old token can't make Lamp do that on every request.
        if tokens[token] == nil, Date().timeIntervalSince(lastReloadForToken) > 5 {
            lastReloadForToken = Date()
            reload()
        }
        guard let id = tokens[token], let project = projects.first(where: { $0.id == id }) else {
            return (401, ["error": "This app isn't registered with Lamp."])
        }
        // A phone asking what it may keep is answered whatever the state of setup: a key just removed makes
        // setup incomplete, and that's exactly when the phone has to hear that its copy should go.
        if route == "/ai/keys" { return keysForPhone(project) }
        if route == "/ai/status" { return await aiStatus(for: project) }
        if route == "/app/secrets" { return appSecrets(request, for: project) }
        if route == "/app/share" { return await appShare(request, for: project) }
        if route == "/app/controller" { return await controllerSession(request, for: project) }
        if route == "/app/phone-page" { return await phonePageAddress(for: project) }
        if route.hasPrefix("/app/wish") { return await wishRoom(request, route: route, for: project) }
        guard setup.ready else { return (503, ["error": "Lamp isn't set up yet. Open Lamp to finish setup."]) }
        return await appRequest(request, for: project)
    }

    /// Where a TV app's game meets the phones that join it (`Lamp.controllers` in lamp.js), asked by its page in the
    /// preview or on a TV: the relay (`ControllerRelay`), by the address the page reached Lamp at, with a host's
    /// credential. Lamp only introduces them; what they say to each other never comes here. A wish's own apps join the
    /// game the way the wish's apps reach each other (`LampController` over `LampWish`), with nothing from Lamp, so an app
    /// of a wish that asks here was built by an earlier Lamp. None of it is anything of Lamp's.
    private func controllerSession(_ request: Gateway.Request, for project: LampProject) async -> (Int, [String: Any]) {
        // By the name or address the app reached Lamp at, at the relay's port.
        let host = (request.headers["host"] ?? "127.0.0.1").split(separator: ":").first.map(String.init) ?? "127.0.0.1"
        guard project.hasTV else {
            return (409, ["error": "This app was built by an earlier Lamp: open it from Lamp on your Mac to update it, and it joins the TV app's game again."])
        }
        guard Self.takesPlayers(project) else { return (409, ["error": "The app has no phone page yet: put one in Phone/index.html."]) }
        syncLocalNetwork()
        guard Self.servesPhonePage(project) else { return (409, ["error": "The app isn't open in the TV preview or set to open on a TV."]) }
        guard let port = await ControllerRelay.ready() else { return (503, ["error": "Lamp couldn't start the link for controllers."]) }
        let relay: [String: Any] = ["kind": "relay", "socket": "ws://\(host):\(port)/", "app": project.id,
                                    "credential": PhoneControllers.shared.hostCredential(for: project, preview: request.fromPreview)]
        return (200, ["links": [relay], "renew": 15])
    }

    /// The wish's apps seeing each other and talking (`WishRooms`): any app of a wish, by its own token, is told where its
    /// wish's room is at the relay and who is in it (`/app/wish`), or, for one that can't hold a socket, has Lamp hold one
    /// for it that carries its sealed messages unread (`/app/wish/open`, `/app/wish/poll`, `/app/wish/send`:
    /// `WishProxies`). Only the app's own wish is ever answered for, and what lets an app in is never here: it's the
    /// wish's key the app was given when it was put on its device, except for the TV preview's page, which asks through
    /// its bridge on this Mac.
    private func wishRoom(_ request: Gateway.Request, route: String, for project: LampProject) async -> (Int, [String: Any]) {
        let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
        let wish = wish(of: project)
        let apps = apps(of: wish)
        switch route {
        case "/app/wish/open":
            return await WishProxies.open(project, wish: wish, apps: apps)
        case "/app/wish/poll":
            return await WishProxies.poll(project, link: body["link"] as? Int ?? 0)
        case "/app/wish/send":
            return await WishProxies.send(project, body: body)
        default:
            // By the name or address the app reached Lamp at, at the relay's port, as a TV app's page is told its relay.
            let host = (request.headers["host"] ?? "127.0.0.1").split(separator: ":").first.map(String.init) ?? "127.0.0.1"
            return await WishRooms.answer(for: project, wish: wish, apps: apps, host: host, preview: request.fromPreview)
        }
    }

    /// A TV app that phones or the wish's other apps join as players: one with a page for phones, or with an iPhone or
    /// Mac app beside it in its wish (`Parts`): at the wish's root with parts, or itself a part (in TV/), beside the
    /// app at the root.
    /// Read off the wish itself (its parts as found in its folder), never off the list of apps, which is being set
    /// while Lamp reads its apps again: a game must not end because, for a moment, the list was half made.
    nonisolated static func takesPlayers(_ project: LampProject) -> Bool {
        project.hasTV && (TVs.hasPhonePage(project) || !project.partFolders.isEmpty || project.isPart)
    }

    /// Where a TV app's phone page is now (`Lamp.phonePage` in lamp.js, which asks as the page opens and now and then
    /// after): the address its site is listening at, which moves when another program has taken the port it had.
    private func phonePageAddress(for project: LampProject) async -> (Int, [String: Any]) {
        guard project.hasTV else { return (403, ["error": "Only TV apps have phone pages."]) }
        guard TVs.hasPhonePage(project) else { return (409, ["error": "The app has no phone page yet: put one in Phone/index.html."]) }
        syncLocalNetwork()
        guard let port = await PhoneSites.ready(project.id) else { return (503, ["error": "Lamp couldn't open the phone page."]) }
        return (200, ["url": TVs.phonePage(port: port)])
    }

    /// File ▸ Share… in a Mac app (`LampShareApp`): the app as a file to open with Lamp, the same one Lamp's own Share…
    /// makes, with its picture. Lamp writes them and the app shows the system's share picker from its own window,
    /// which Lamp can't open over another app's. Only the app itself is answered, as for its secrets, and it can ask
    /// only for itself: the file is made from the app's folder here, never from anything the app sends.
    private func appShare(_ request: Gateway.Request, for project: LampProject) async -> (Int, [String: Any]) {
        guard !request.fromNetwork, let port = request.peerPort,
              PeerProcess.isApp(at: project.installedURL, connectedFrom: port, to: Gateway.port) else {
            return (403, ["error": "Only the app itself, as Lamp installed it, can do that."])
        }
        do {
            let icon = await Sharing.sharedIcon(of: project)
            // Where Lamp keeps an app's shared file, written over each time: a share never leaves a copy behind.
            let (file, picture) = try await Task.detached(priority: .userInitiated) {
                let file = try Store.sharedFile(of: project, icon: icon)
                return (file, Store.sharePicture(for: file))
            }.value
            var answer = ["file": file.path, "note": "Open this with Lamp https://lamp.dev"]
            if let picture { answer["picture"] = picture.path }
            return (200, answer)
        } catch {
            return (500, ["error": "\(project.name) couldn't be made into a file to share: \(error.localizedDescription)"])
        }
    }

    /// `LampSecrets` in a Mac app: what it keeps secret, kept here (AppSecrets). Only the app itself is answered, the
    /// program Lamp installed, on this Mac: the token is in the app's folder, where the agent can read it.
    private func appSecrets(_ request: Gateway.Request, for project: LampProject) -> (Int, [String: Any]) {
        guard !request.fromNetwork, let port = request.peerPort,
              PeerProcess.isApp(at: project.installedURL, connectedFrom: port, to: Gateway.port) else {
            return (403, ["error": "Only the app itself, as Lamp installed it, can do that."])
        }
        let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
        guard let name = body["name"] as? String, AppSecrets.isName(name) else { return (400, ["error": "That name can't be used."]) }
        switch body["op"] as? String {
        case "read":
            return (200, AppSecrets.read(name, app: project.instance).map { ["value": $0.base64EncodedString()] } ?? [:])
        case "save":
            guard let value = (body["value"] as? String).flatMap({ Data(base64Encoded: $0) }), value.count <= 64 * 1024 else {
                return (400, ["error": "Nothing to keep."])
            }
            return AppSecrets.save(value, as: name, app: project.instance) ? (200, ["ok": true]) : (500, ["error": "Lamp couldn't keep it."])
        case "delete":
            return AppSecrets.delete(name, app: project.instance) ? (200, ["ok": true]) : (500, ["error": "Lamp couldn't forget it."])
        default:
            return (400, ["error": "Unknown request."])
        }
    }

    /// Whether a Host header is this Mac's name on the local network (what apps on phones are given), or one of its
    /// own addresses there, with an optional numeric port. A web app on a TV or a console can't choose its Host, and
    /// those devices don't resolve the Mac's name, so they reach it by an address; an address can't be rebound to
    /// another site the way a name can, so it's no way round the check.
    static func isMacHost(_ header: String?) -> Bool {
        guard let host = header?.trimmed.lowercased(), !host.isEmpty else { return false }
        let name = host.split(separator: ":", maxSplits: 1).first.map(String.init) ?? host
        guard host.count == name.count || host.dropFirst(name.count + 1).allSatisfy(\.isNumber) else { return false }
        return name == Devices.macHost.lowercased() || Devices.localAddresses.contains(name)
    }

    /// Whether a Host header names this Mac and nothing else: exactly a loopback name or address, with an
    /// optional numeric port. "localhost.evil.example" and "127.0.0.1.evil.example" are not.
    static func isLocalHost(_ header: String?) -> Bool {
        guard var host = header?.trimmed.lowercased(), !host.isEmpty else { return false }
        if host.hasPrefix("[") {   // an IPv6 address, [::1] or [::1]:port
            guard let close = host.firstIndex(of: "]") else { return false }
            let port = host[host.index(after: close)...]
            guard port.isEmpty || (port.hasPrefix(":") && port.count > 1 && port.dropFirst().allSatisfy(\.isNumber)) else { return false }
            host = String(host[...close])
        } else if let colon = host.firstIndex(of: ":") {
            let port = host[host.index(after: colon)...]
            guard !port.isEmpty, port.allSatisfy(\.isNumber) else { return false }
            host = String(host[..<colon])
        }
        return ["127.0.0.1", "localhost", "[::1]"].contains(host)
    }

    /// The routes the agent uses mid-turn: build and try the app, approvals, versions, and the MCP tools.
    private func agentRequest(_ request: Gateway.Request, route: String, for project: LampProject) async -> (Int, [String: Any]) {
        // Codex is cut to pass a message on only while Lamp isn't answering it (`steer`).
        let turn = route == "/mcp" || route == "/agent/approve" ? turns[project.id] : nil
        turn?.answering += 1
        defer {
            if let turn {
                turn.answering -= 1
                if turns[project.id] === turn, turn.steering == .codex { steer(project) }
            }
        }
        if route == "/mcp" { return await mcp(request.body, for: project, fileTools: request.path.contains("files=1")) }
        if request.path == "/agent/look" {
            let arguments = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
            return Self.withPictureData(await lookCall(arguments, for: project), in: project)
        }
        if request.path == "/agent/use" {
            let arguments = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
            return Self.withPictureData(await useCall(arguments, for: project), in: project)
        }
        if request.path.hasPrefix("/agent/versions") {
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
            return await versions(String(request.path.dropFirst("/agent/versions".count)), body, of: project)
        }
        if route == "/agent/memory" {
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
            return notes(body["tool"] as? String ?? "", body["arguments"] as? [String: Any] ?? [:], for: project)
        }
        if route == "/agent/skill" {
            return Skills.read((try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:],
                               from: Skills.readable(parts: parts(of: project)))
        }
        if route == "/agent/art" {
            return Self.withPictureData(await makeArt((try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:], for: project), in: project)
        }
        if route == "/agent/talk" {
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
            return talk(body["tool"] as? String ?? "", body["arguments"] as? [String: Any] ?? [:], for: project)
        }
        if route == "/agent/setup" {
            return agentOffer((try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:], for: project)
        }
        if route == "/agent/kind" {
            return await agentKind((try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:], for: project)
        }
        if route == "/agent/steer" {
            guard turns[project.id]?.steering == .pi else { return (200, [:]) }
            return (200, handOver(project).map { ["message": $0] } ?? [:])
        }
        if route == "/agent/integration" {
            return await agentIntegration((try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:], for: project)
        }
        if route == "/agent/connectors" {
            return Connectors.answer((try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:], for: project)
        }
        if route == "/agent/approve" {
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
            // One of the agent's file tools, about to touch something outside the app's folder or in its runtime folder.
            if let tool = body["file_tool"] as? String, let path = body["path"] as? String {
                let (allowed, reason) = await fileAccess(tool: tool, path: path, for: project)
                return (200, reason.map { ["allow": allowed, "reason": $0] } ?? ["allow": allowed])
            }
            // pi's extension sends {"command", "description", "call"}; Claude Code's hook sends {"tool_input": {"command",
            // "description"}, "tool_use_id"}. The call's id ties the command's row to the call its outcome comes back by.
            let input = body["tool_input"] as? [String: Any] ?? [:]
            let call = (body["call"] as? String ?? body["tool_use_id"] as? String)?.nilIfEmpty
            let tool = body["tool_name"] as? String ?? "Bash"
            if request.path.contains("format=claude-file") {
                // One of Claude Code's file tools, before it runs: the same check pi's and Codex's get.
                let names = ["Read": "read", "Edit": "edit", "Write": "write", "Glob": "find", "Grep": "grep"]
                let path = input["file_path"] as? String ?? input["path"] as? String ?? project.dir.path
                var (allowed, reason) = (false, nil as String?)
                if let session = turns[project.id]?.claudeSession,
                   Privacy.isOwnOutput(tool: names[tool] ?? "write", path: path, session: session, project: project) {
                    allowed = true
                } else if tool == "Glob" || tool == "Grep", Privacy.wouldUncover(root: path, project: project) {
                    reason = "That search would pass over Lamp's own files, which aren't yours to open. Search a narrower folder."
                } else {
                    (allowed, reason) = await fileAccess(tool: names[tool] ?? "read", path: path, for: project)
                }
                var output: [String: Any] = ["hookEventName": "PreToolUse", "permissionDecision": allowed ? "allow" : "deny"]
                if let reason { output["permissionDecisionReason"] = reason }
                return (200, ["hookSpecificOutput": output])
            }
            var command = body["command"] as? String ?? input["command"] as? String ?? ""
            let shell = !command.isEmpty
            if command.isEmpty {   // a non-shell tool Claude Code wants permission for (e.g. a write outside the app)
                let target = input["file_path"] as? String ?? input["url"] as? String ?? input["path"] as? String ?? ""
                command = target.isEmpty ? tool : "\(tool): \(target)"
            }
            // Claude Code already ran its own classifier before asking ("claude-permission"), so ask the user.
            let escalated = request.path.contains("format=claude-permission")
            // Whose command: Claude Code's and pi's come back wrapped (Sandbox); Codex runs inside the sandbox
            // whole, so its commands are confined already and go back as they are.
            let engine: Engine = request.path.contains("format=codex") ? .codex : request.path.contains("format=claude") ? .claude : .pi
            // A command Lamp confined already (below, for Claude Code's classifier) comes back wrapped: it's shown
            // and logged as the agent wrote it, and stays as it was confined.
            let wrapped = command
            let known = engine == .claude ? confinedCommands[wrapped] : nil
            if let known { command = known.original }
            let confined = known != nil ? wrapped : shell && engine != .codex ? Sandbox.wrap(command, for: project) : nil
            // It ran: what Claude Code's classifier let through is said in the chat as a command Lamp let run is.
            if request.path.contains("format=claude-refused") {
                if let known { confinedCommands[wrapped] = nil }
                let why = (body["reason"] as? String ?? body["message"] as? String)?.trimmed.nilIfEmpty
                log(project, .status, ChatLook.notRun + command, said: known?.said, call: known?.call ?? call)
                if let why { log(project, .detail, "Claude's check stopped it: \(why)") }
                return (200, [:])
            }
            if request.path.contains("format=claude-ran") {
                if let known {
                    confinedCommands[wrapped] = nil
                    log(project, .status, "Ran: \(command)", said: known.said,
                        failed: body["hook_event_name"] as? String == "PostToolUseFailure", call: known.call ?? call)
                }
                return (200, [:])
            }
            let sandboxed = shell
            // No sandbox, no shell: a command that can't be confined isn't run rather than run loose.
            if shell && engine != .codex && confined == nil {
                log(project, .error, "A shell command was refused: Lamp could not set up the sandbox that keeps it inside the app.")
                let reason = "Lamp could not confine this command; use the file tools instead."
                if escalated {
                    return (200, ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": ["behavior": "deny", "message": reason]]])
                }
                if engine == .claude {
                    return (200, ["hookSpecificOutput": ["hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": reason]])
                }
                return (200, ["allow": false, "reason": reason])
            }
            // Under "Only when risky", Claude Code's own classifier decides (auto mode): Lamp only confines the
            // command, with no decision of its own, and what the classifier asks about comes back as a
            // "claude-permission" request for the card.
            if request.path.contains("format=claude-confine"), let confined {
                if known == nil {
                    let said = (input["description"] as? String ?? body["description"] as? String)?.trimmed.nilIfEmpty
                    if confinedCommands.count > 500 { confinedCommands.removeAll() }   // ones refused never come back
                    confinedCommands[confined] = (command, said, call)
                }
                return (200, ["hookSpecificOutput": ["hookEventName": "PreToolUse", "updatedInput": ["command": confined]]])
            }
            if request.path.contains("format=codex") {
                // Codex's PreToolUse hook can only block: an empty answer lets the command run.
                // Codex says what its commands are for in its reasoning, which comes before them (`AgentEvent.naming`).
                let allowed = await approveCommand(command, for: project, escalated: false, sandboxed: sandboxed,
                                                   said: turns[project.id]?.naming, call: call)
                return (200, allowed ? [:] : ["hookSpecificOutput": ["hookEventName": "PreToolUse",
                                                                     "permissionDecision": "deny",
                                                                     "permissionDecisionReason": "The user denied this command in Lamp."]])
            }
            // Claude Code's hook and pi's extension carry the command's own description, so each command keeps its
            // own words whichever of the approval and the engine's output reaches Lamp first.
            let said = (input["description"] as? String ?? body["description"] as? String)?.trimmed.nilIfEmpty
            let allowed = await approveCommand(command, for: project, escalated: escalated, shell: shell, sandboxed: sandboxed, said: said,
                                               call: call)
            let reason = allowed ? "Approved in Lamp." : "The user denied this command in Lamp."
            // An allowed command goes back confined: the hooks run what Lamp hands them.
            if escalated {
                var decision: [String: Any] = allowed ? ["behavior": "allow"] : ["behavior": "deny", "message": reason]
                if allowed, let confined { decision["updatedInput"] = ["command": confined] }
                return (200, ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]])
            }
            if request.path.contains("format=claude") {
                var output: [String: Any] = ["hookEventName": "PreToolUse", "permissionDecision": allowed ? "allow" : "deny",
                                             "permissionDecisionReason": reason]
                if allowed, let confined { output["updatedInput"] = ["command": confined] }
                return (200, ["hookSpecificOutput": output])
            }
            var answer: [String: Any] = ["allow": allowed, "reason": reason]
            if allowed, let confined { answer["command"] = confined }
            return (200, answer)
        }
        return (404, ["error": "Not found"])
    }

    /// The routes a running app uses: text, pictures, decisions, and using the other apps on the Mac.
    private func appRequest(_ request: Gateway.Request, for project: LampProject) async -> (Int, [String: Any]) {
        // A sign-in Lamp last found signed out may have been signed in since (from Terminal, say): what's
        // older than a few minutes is checked again before choosing a route, so it can answer again.
        await EngineSignIn.refresh()
        if request.path == "/ai/computer" { return await useComputer(for: project, request: request.body) }
        if request.path == "/ai/decide" {
            guard let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any],
                  let state = body["state"], let questions = body["questions"] as? [String: Any], !questions.isEmpty else {
                return (400, ["error": "A decision needs `state` and at least one question."])
            }
            do {
                let models = AppModels.load(project)
                let (answers, cost) = try await AppAI.decide(state: state, questions: questions,
                                                             model: models.decision, appText: models.text)
                record(project, cost: cost)
                return (200, ["answers": answers])
            } catch let failure as AppAI.Failure {
                return failed(failure, for: project)
            } catch {
                return (502, ["error": "Couldn't reach the decision model: \(error.localizedDescription)"])
            }
        }
        guard let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any],
              let prompt = body["prompt"] as? String, !prompt.trimmed.isEmpty else {
            return (400, ["error": "Missing prompt."])
        }
        do {
            let images = (body["images"] as? [[String: String]] ?? []).compactMap { image -> AppAI.Image? in
                guard let type = image["media_type"], let data = image["data"] else { return nil }
                return AppAI.Image(mediaType: type, data: data)
            }
            if request.path == "/ai/image" {
                do {
                    let models = AppModels.load(project)
                    let (png, cost) = try await AppAI.image(prompt: prompt, references: images,
                                                            aspectRatio: body["aspect_ratio"] as? String,
                                                            model: models.image, appText: models.text)
                    record(project, cost: cost)
                    return (200, ["image": png.base64EncodedString(), "media_type": "image/png"])
                }
            }
            let (text, cost) = try await AppAI.complete(prompt: prompt, images: images,
                                                         system: body["system"] as? String ?? "",
                                                         json: body["json"] as? Bool ?? false,
                                                         appModel: body["model"] as? String ?? AppModels.load(project).text)
            record(project, cost: cost)
            return (200, ["text": text])
        } catch let failure as AppAI.Failure {
            if failure.cost > 0 { record(project, cost: failure.cost) }   // billed even though it failed
            return failed(failure, for: project)
        } catch {
            return (502, ["error": "Couldn't reach the AI: \(error.localizedDescription)"])
        }
    }

    /// An app's AI call that failed. When it failed because nothing is set up to answer, the app is told
    /// which capability (`needs`, so LampAI can say so) and the person is offered a way in the app's chat.
    private func failed(_ failure: AppAI.Failure, for project: LampProject) -> (Int, [String: Any]) {
        var reply: [String: Any] = ["error": failure.message]
        if let needs = failure.needs {
            reply["needs"] = needs.rawValue
            offerSetup(project, SetupOffer(capability: needs), because: Self.offerReason(needs, for: project))
        }
        return (502, reply)
    }

    /// `LampAI.isAvailable`: which capabilities can answer this app now, so it can leave out or explain a
    /// feature instead of failing at it.
    private func aiStatus(for project: LampProject) async -> (Int, [String: Any]) {
        await EngineSignIn.refresh()
        var reply: [String: Any] = [:]
        for capability in Capability.allCases {
            reply[capability.rawValue] = setup.ready && AppAI.resolve(capability, for: project).tier != .none
        }
        return (200, reply)
    }

    /// What an app on the person's own phone keeps so its AI works away from the Mac:
    /// the OpenRouter key and the models the app is set to, as
    /// `AppAI.resolve` has them for `.phoneAway`. Only for iPhone apps; a Mac app
    /// or the simulator never needs it, and the key stays in the phone's Keychain, put there by the app itself.
    private func keysForPhone(_ project: LampProject) -> (Int, [String: Any]) {
        guard project.hasIOS else { return (403, ["error": "Not for this app."]) }
        guard AppAI.resolve(.text, for: project, in: .phoneAway).tier != .none, let key = KeyStore.openRouterKey else {
            return (404, ["error": "There's no OpenRouter key to keep."])
        }
        let models = AppModels.load(project)
        let decision = AppAI.awayDecisionModel(for: models.awayDecision)
        var keys: [String: Any] = [
            "openrouter": key,
            "text_model": AppAI.awayModel(for: models.away).openRouter,
        ]
        keys["decision_model"] = decision.model
        keys["decision_provider"] = decision.provider
        // The cloud image model chosen for away from the Mac (the Mac's own model can't travel).
        keys["image_model"] = AppAI.awayImageModel(for: models.awayImage)
        // Sealed with the secret that went to the phone inside its build, never over the network: the token
        // in the request is on the air too, so it can't be what protects the key.
        guard let json = try? JSONSerialization.data(withJSONObject: keys),
              let box = try? AES.GCM.seal(json, using: SymmetricKey(data: SHA256.hash(data: Data(Template.phoneSecret(in: Devices.buildFolder(for: project)).utf8)))),
              let sealed = box.combined else { return (500, ["error": "Couldn't prepare the keys."]) }
        return (200, ["sealed": sealed.base64EncodedString()])
    }

    /// `LampComputer.ask` / `.perform` from an app: a task done with the other apps on the Mac (see ComputerUse).
    private func useComputer(for project: LampProject, request body: Data) async -> (Int, [String: Any]) {
        guard let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let task = (json["task"] as? String)?.trimmed, !task.isEmpty else { return (400, ["error": "Missing task."]) }
        let allowActions = json["act"] as? Bool ?? false
        guard ComputerUse.enabled, await ComputerUse.status() == .ready else {
            // Asked once per app per launch: an app that keeps trying would otherwise raise a dialog per call.
            if computerUseRefused.insert(project.id).inserted {
                NSApp.activate()
                let alert = NSAlert()
                alert.messageText = "\(project.title) wants to use your other apps"
                alert.informativeText = "To let apps read and use apps like Slack, Mail or your browser, turn on “Let apps use your other apps” in Lamp's settings."
                alert.addButton(withTitle: "Open Settings")
                alert.addButton(withTitle: "Not Now")
                if await present(alert) == .alertFirstButtonReturn {
                    UserDefaults.standard.set("apps", forKey: "settingsTab")
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            }
            return (503, ["error": "Using other apps is turned off. Turn on “Let apps use your other apps” in Lamp → Settings → Apps, then try again."])
        }
        if let problem = ComputerUse.check() { return (502, ["error": problem.message]) }
        // The task goes along the route chosen for the app's text; with none chosen, the one that's good at this.
        let chosen = AppAI.computerRoute(for: AppModels.load(project).text)
        var allowAll = false
        // Weak: the job keeps this closure, so a strong reference back would keep every finished job alive.
        weak var job: ComputerUse.Job?
        let work: ComputerUse.Job
        do {
            work = try await ComputerUse.Job(task, appName: project.name, allowActions: allowActions) { [weak self] action in
                // A job stopped while this step was on its way asks nothing more: its questions were closed.
                guard let self, ComputerUse.enabled, let job, !job.isStopped else { return false }
                if allowAll { return true }
                let answer = await self.confirm(action, for: project, owner: ObjectIdentifier(job))
                switch answer {
                case .allow: return true
                case .allowAll: allowAll = true; return true
                case .deny: return false
                case .stop: job.stop(); return false
                }
            }
        } catch {
            return (502, ["error": error.localizedDescription])
        }
        job = work
        defer { work.close() }
        let token = UUID().uuidString + UUID().uuidString
        computerTasks[token] = work
        defer { computerTasks[token] = nil }
        do {
            let (text, cost) = try await ComputerUse.answer(work, route: chosen, token: token)
            record(project, cost: cost)
            print("Computer task for \(project.name) through \(chosen.label): \(work.steps) steps, answered.")
            // Stopped while the last answer was on its way: the person said not to finish, so it isn't one.
            if work.isStopped { return (409, ["error": ComputerUse.stoppedByPerson.message]) }
            return (200, ["text": text])
        } catch {
            // What the steps so far cost was spent whether or not the task got to an answer.
            if let spent = (error as? ComputerUse.Failure)?.cost, spent > 0 { record(project, cost: spent) }
            print("Computer task for \(project.name) through \(chosen.label): \(work.steps) steps, ended: \(error.localizedDescription)")
            // However the agent ended once stopped (killed, or failing on its next step), the app is told why.
            if work.isStopped { return (409, ["error": ComputerUse.stoppedByPerson.message]) }
            return (502, ["error": error.localizedDescription])
        }
    }

    /// Tasks a coding agent is driving right now, by the token that agent was given.
    private var computerTasks: [String: ComputerUse.Job] = [:]

    /// A coding agent's call into a task: MCP for Claude Code and Codex (list the tools, call one), or pi's
    /// extension's plain POST of {name, arguments}, answered with the text and the pictures.
    private func computerCall(_ request: Gateway.Request, task: ComputerUse.Job, mcp: Bool) async -> (Int, [String: Any]) {
        let json = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
        guard mcp else {
            guard let name = json["name"] as? String else { return (400, ["error": "Missing tool name."]) }
            do {
                let (text, pictures) = try await task.call(name, json["arguments"] as? [String: Any] ?? [:])
                return (200, ["text": text, "pictures": pictures.map { ["mimeType": $0.mimeType, "data": $0.data] }])
            } catch {
                return (502, ["error": error.localizedDescription])
            }
        }
        guard let method = json["method"] as? String else {
            return (400, ["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Not a JSON-RPC request."]])
        }
        let id = json["id"] ?? NSNull()
        func reply(_ result: [String: Any]) -> (Int, [String: Any]) { (200, ["jsonrpc": "2.0", "id": id, "result": result]) }
        switch method {
        case "initialize":
            return reply(["protocolVersion": "2025-03-26", "capabilities": ["tools": [:]],
                          "serverInfo": ["name": "lamp", "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"]])
        case "ping":
            return reply([:])
        case "tools/list":
            return reply(["tools": task.mcpTools])
        case "tools/call":
            let params = json["params"] as? [String: Any] ?? [:]
            do {
                let (text, pictures) = try await task.call(params["name"] as? String ?? "", params["arguments"] as? [String: Any] ?? [:])
                var content: [[String: Any]] = [["type": "text", "text": text]]
                content += pictures.map { ["type": "image", "data": $0.data, "mimeType": $0.mimeType] }
                return reply(["content": content])
            } catch {
                return reply(["content": [["type": "text", "text": error.localizedDescription]], "isError": true])
            }
        default:
            if json["id"] == nil { return (202, [:]) }
            return (200, ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found: \(method)"]])
        }
    }

    private typealias ActionAnswer = ApprovalPanel.Answer

    /// Asks the person before an app clicks, types or presses keys in another app, beside where it happens.
    private func confirm(_ action: ComputerUse.Action, for project: LampProject, owner: ObjectIdentifier?) async -> ActionAnswer {
        await ApprovalPanel.ask(.init(
            asker: project.name,
            askerIcon: NSWorkspace.shared.icon(forFile: project.installedURL.path),
            target: action.target,
            targetIcon: action.pid.flatMap { NSRunningApplication(processIdentifier: $0)?.icon },
            details: action.details,
            intent: action.intent,
            point: action.point,
            window: action.window,
            owner: owner))
    }

    /// Shows an alert without stopping everything else: as a sheet on Lamp's window when there is one, so
    /// other apps' turns and requests carry on while it waits for an answer.
    private func present(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey }) else {
            return alert.runModal()
        }
        return await alert.beginSheetModal(for: window)
    }

    /// The agent's version tools: `list_versions`, `name_version` and `restore_version`. `action` is "" to
    /// list, "/name" or "/restore", for pi's endpoint and the MCP tools alike.
    private func versions(_ action: String, _ body: [String: Any], of project: LampProject) async -> (Int, [String: Any]) {
        // Only for the agent Lamp is running right now: the app knows the same token, and must not be
        // able to change its own history.
        guard turns[project.id]?.agent != nil else { return (409, ["error": "Lamp isn't working on this app right now."]) }
        let versions = await Versions.list(project)
        let id = (body["version"] as? String)?.trimmed.nilIfEmpty
        let version = id.flatMap { Versions.find($0, in: versions) }
        if id != nil && version == nil {
            return (404, ["error": "There's no version \(id!). Call list_versions for the ids."])
        }
        switch action {
        case "/name":
            guard let name = (body["name"] as? String)?.trimmed.nilIfEmpty else { return (400, ["error": "A name is needed."]) }
            guard let version else {
                turns[project.id]?.pendingName = name
                return (200, ["text": "Lamp will name the version this request makes “\(name)”."])
            }
            await Versions.name(project, version.id, name)
            versionsRevision += 1
            return (200, ["text": "Named \(version.shortID) “\(name)”."])
        case "/restore":
            guard let version else { return (400, ["error": "Say which version to restore."]) }
            guard await Versions.restoreFiles(project, to: version) else {
                return (500, ["error": "Lamp couldn't restore that version."])
            }
            await followRestored(project)
            log(project, .status, Versions.restoredMessage(to: version))
            return (200, ["text": """
                The app's files are now as they were in “\(version.label)”. Your changes earlier in this request \
                are gone too. Read files again before editing them. Lamp builds and opens the app when you finish.
                """])
        default:
            return (200, ["text": Versions.describe(versions)])
        }
    }

    /// The pictures a tool's reply shows the agent, as the paths it reads: small copies of the screenshots or
    /// the art (`Previews.forAgent`), so a conversation holds many before a request is too big to send; none
    /// when the person keeps pictures from the model. The files given are left as they are.
    static func agentPictures(_ pictures: [URL], in project: LampProject) -> [String] {
        Privacy.sharesPictures ? pictures.compactMap { Previews.forAgent($0, in: project)?.path } : []
    }

    /// Those pictures' bytes, as every engine is given them: read by Lamp as `AppFile` reads, so a picture swapped
    /// for a link after its copy was made brings the agent nothing else. An engine handed only the path would read
    /// it itself, through whatever link was there by then.
    static func pictureData(_ paths: [String], in project: LampProject) -> [[String: String]] {
        paths.compactMap { path in
            AppFile.read(URL(fileURLWithPath: path), in: project).map { ["data": $0.base64EncodedString(), "mimeType": Previews.mimeType(of: path)] }
        }
    }

    /// A tool's answer with its pictures' bytes beside their paths, for pi's extension.
    private static func withPictureData(_ result: (Int, [String: Any]), in project: LampProject) -> (Int, [String: Any]) {
        guard let paths = result.1["screenshots"] as? [String], !paths.isEmpty else { return result }
        var answer = result.1
        answer["pictures"] = pictureData(paths, in: project)
        return (result.0, answer)
    }

    /// What a look says while a change waits for the person to press Reload (`awaitReload`).
    private static let reloadNoteStart = "The app built, but this change can't go into it while it runs"
    /// What a look says the first time a change waits for the person to press Reload (`awaitReload`, `held`): with why
    /// it couldn't go in, and where there's a known shape that would have, what that is, so the next change can take
    /// it. The agent goes on with the rest without claiming what's held is on screen, and is told that a look is how
    /// it asks to see, which stops the turn until the Reload.
    private func reloadNote(for project: LampProject) -> String {
        var why = ""
        if let reason = turns[project.id]?.reloadWhy {
            why = " Why: \(reason)."
            if let advice = LiveReload.advice(for: reason) { why += " Next time, \(advice)" }
        }
        return """
            \(Self.reloadNoteStart): it has to be reopened, and that's the person's to do.\(why) \
            The app and the chat show them a Reload button, and Lamp doesn't reopen it for them. Until they press it \
            what's on screen isn't your change, and nothing you do after it shows either. \(Self.goOnNote)
            """
    }

    /// How the first note about a held change ends: the agent goes on with what's left, says so without claiming the
    /// change is in, and knows that looking again is how it asks to see, which stops the turn (`seeNote`).
    private static let goOnNote = """
        If passes of this request are left, go on with them: they're held with this one and show when the person \
        presses Reload. Never say a held change is in or on screen: a progress line says what you built and that it \
        shows after Reload ("Taproom look built, Reload to see it"). When you need to see the app before going on, \
        look again: Lamp then stops you until the person has pressed Reload, and starts you again after. With \
        nothing left, finish, and tell them in a sentence to press Reload to see it.
        """

    /// What a look or `use_app` says once the agent has been told its change waits and asks to see it anyway
    /// (`held`): the turn stops here, and Lamp holds it to that (`endIfOver`), whichever engine it is. What the agent
    /// asks the person for is what puts the change in: Reload where a Reload is offered (`Runtime.awaitReload`), and
    /// closing the app where the person kept an earlier copy open at its own question and no Reload is (the build
    /// goes in when it closes, `installIcon`), so the agent never asks for a button that isn't there.
    static func seeNote(reloadOffered: Bool) -> String {
        let press = reloadOffered ? "press Reload" : "close the app, so the new version can open"
        let once = reloadOffered ? "Once they've pressed Reload and the app has reopened with your change"
            : "Once they've closed the app and the new version has gone in"
        return """
            Your change still waits for the person to \(press), so the app can't show it to you yet, and nothing \
            you'd do after it would show either. Stop here: say in one sentence that you need to see the change \
            before going on and ask them to \(press), and end your reply with no more tool calls. Lamp ends this \
            turn at your next tool call. \(once), Lamp starts you again in this conversation with a message saying \
            so, and you carry on from there.
            """
    }

    /// How the turn's changes reached the app, as one line in the details ("2 went into the open app, 1 waits for
    /// Reload"): how often a change goes in live is what the live rules are tuned by.
    static func outcomeTally(_ outcomes: [ChangeOutcome], name: String) -> String? {
        guard !outcomes.isEmpty else { return nil }
        func count(_ kind: ChangeOutcome, _ words: String) -> String? {
            let n = outcomes.filter { $0 == kind }.count
            return n == 0 ? nil : "\(n) \(words)"
        }
        let parts = [count(.live, "went into the open app"), count(.held, "waited for Reload"),
                     count(.reopened, "reopened \(name)"), count(.opened, "opened \(name)")].compactMap { $0 }
        return "Changes this request: " + parts.joined(separator: ", ") + "."
    }

    /// How long the person watching waited to see the turn's work, as one line in the details ("First change on
    /// screen after 1 min 12 s; longest wait between changes 2 min 40 s"): what the rule to show work early and
    /// often is tuned by. Nothing for a turn that changed nothing.
    static func paceTally(began: Date, shown: [Date], outcomes: [ChangeOutcome]) -> String? {
        guard !outcomes.isEmpty else { return nil }
        guard let first = shown.first else { return "Nothing reached the screen this request." }
        func spoken(_ interval: TimeInterval) -> String {
            let total = max(0, Int(interval.rounded()))
            return total < 60 ? "\(total) s" : total % 60 == 0 ? "\(total / 60) min" : "\(total / 60) min \(total % 60) s"
        }
        // Between changes only: the wait for the first is its own measure, and its own part of the rule.
        let longest = zip(shown, shown.dropFirst()).map { $1.timeIntervalSince($0) }.max() ?? 0
        let firstPart = "First change on screen after \(spoken(first.timeIntervalSince(began)))"
        return shown.count < 2 ? firstPart + "." : firstPart + "; longest wait between changes \(spoken(longest))."
    }

    /// What a look with `reopen` says when Lamp asked the person instead (`asksBeforeReopening`).
    private static let askedToReopenNote = """
        The person has the app open, so Lamp asked them before reopening it: the app and the chat show a Reload \
        button, and it opens fresh when they press it. Any change you made is built and goes in with it, and nothing \
        more you do shows until then. \(goOnNote)
        """

    /// What a look says when the person kept the earlier build open (`Turn.keptOpen`).
    private static let keptOpenNote = """
        The app built, but the person has the version from before open and chose to keep it open (it may hold \
        work they haven't saved), so Lamp didn't replace it. What's on screen isn't your change, and nothing more \
        you do shows until the new version goes in, which it does when they close the app. If passes of this \
        request are left, go on with them; they go in with it. Never say a held change is in or on screen. When you \
        need to see the app before going on, look again: Lamp then stops you until the new version is in, and \
        starts you again after. With nothing left, finish, and tell them in a sentence that the new version opens \
        once they close the app.
        """

    /// `look_at_app`, for the wish or the part its `part` names.
    private func lookCall(_ arguments: [String: Any], for project: LampProject) async -> (Int, [String: Any]) {
        let (app, refusal) = target(arguments, in: project)
        guard let app else { return (400, ["error": refusal ?? "No such part."]) }
        return await underTurn(of: project, app) {
            arguments["sidebar"] as? Bool == true
                ? await lookAtSidebar(app, page: arguments["page"] as? String, reopen: arguments["reopen"] as? Bool ?? false)
                : await look(at: app, prop: arguments["prop"] as? String, motion: arguments["motion"] as? Bool ?? false,
                             reopen: arguments["reopen"] as? Bool ?? false, onDevice: arguments["on_device"] as? Bool ?? false)
        }
    }

    /// `use_app`, for the wish or the part its `part` names.
    private func useCall(_ arguments: [String: Any], for project: LampProject) async -> (Int, [String: Any]) {
        let (app, refusal) = target(arguments, in: project)
        guard let app else { return (400, ["error": refusal ?? "No such part."]) }
        var actions = arguments
        actions["part"] = nil
        let body = (try? JSONSerialization.data(withJSONObject: actions)) ?? Data("{}".utf8)
        return await underTurn(of: project, app) { await use(app, request: body) }
    }

    /// The app of the wish a tool call is for: the one its `part` names ("iphone", "tv", "mac"), which may be left out
    /// only when the wish has one app. No app of a wish is the one meant by saying none.
    private func target(_ arguments: [String: Any], in project: LampProject) -> (LampProject?, String?) {
        let apps = apps(of: project)
        let have = apps.map { "\"\(Parts.word(for: $0.platform))\" (\(Parts.name(of: $0.platform)))" }.joined(separator: ", ")
        guard let word = (arguments["part"] as? String)?.trimmed, !word.isEmpty else {
            guard apps.count > 1 else { return (apps.first ?? project, nil) }
            return (nil, "This wish has \(apps.count) apps: say which with `part`: \(have).")
        }
        if let found = Parts.pick(word, among: apps) { return (found, nil) }
        return (nil, "This wish has no \(word) app. Its apps: \(have). To add one, use make_app_for.")
    }

    /// A part's look or use runs under its wish's turn, as the wish's own does: the turn is the part's too while it
    /// lasts, so everything that asks whether Lamp is working on the app (and which turn) finds it.
    private func underTurn(of wish: LampProject, _ app: LampProject, _ work: () async -> (Int, [String: Any])) async -> (Int, [String: Any]) {
        guard app.id != wish.id, let turn = turns[wish.id] else { return await work() }
        guard turns[app.id] == nil || turns[app.id] === turn else { return (409, ["error": "Lamp is busy with that part right now."]) }
        // A look inside the turn's end, which holds the part already (`asPartOf`), leaves it held.
        let before = turns[app.id]
        turns[app.id] = turn
        defer { if turns[app.id] === turn { turns[app.id] = before } }
        return await work()
    }

    /// The agent's `look_at_app` tool: builds what it has written so far, opens the app behind the
    /// user's windows, and reports what happened. The pictures are sent as file paths for pi to read. For a Mac
    /// app it can instead show one of the app's 3D props from four sides (`prop`), or watch the window for a
    /// couple of seconds and say what moved and what flickered (`motion`). `reopen` closes the open app the usual
    /// way, asking about unsaved work, and opens a fresh copy: for what only a launch shows (how long it takes to
    /// open, code run once at the start), where otherwise a change goes into the open app. The agent ending the
    /// app's process itself skipped that question, and Lamp rightly asked the person about every such command.
    /// `onDevice`: for a game, where Try On points (its window, the simulator or the Xbox) rather than in the preview (`GameKit`).
    private func look(at project: LampProject, prop: String? = nil, motion: Bool = false, reopen: Bool = false, onDevice: Bool = false) async -> (Int, [String: Any]) {
        withLateCrash(await lookNow(at: project, prop: prop, motion: motion, reopen: reopen, onDevice: onDevice), of: project)
    }

    private func lookNow(at project: LampProject, prop: String?, motion: Bool, reopen: Bool, onDevice: Bool) async -> (Int, [String: Any]) {
        // Only for the agent Lamp is running right now. The app knows the same token and must not
        // be able to rebuild itself.
        guard let turn = turns[project.id], turn.agent != nil else {
            return (409, ["error": "Lamp isn't working on this app right now."])
        }
        guard !turn.look.inProgress else { return (200, ["text": "Lamp is already looking at the app. Wait for that result."]) }
        turn.look.inProgress = true
        progress[project.id]?.looking = true
        // Told at the end how long the look took: the agent is asked to look after each part of a change, and
        // a cost it has seen is one it allows for, where "takes a while" had it putting looks off.
        let began = Date()
        await turn.early?.value
        // A fresh launch asked for while the person has the app open waits for them to say so, like a change that
        // needs one: the look puts in what it can as usual, then asks with Reload.
        let wantsFresh = reopen
        var asking = reopen && !project.onIOS && asksBeforeReopening(project, owner: turn)
        var reopen = reopen && !asking
        turn.look.installed[project.id] = false
        // Each stage says itself from here; once the look is over the model is reading what it found. Only while this
        // look's turn is the one on screen: after Stop, a look still waiting on the app can end after the next turn began.
        func say(_ activity: String) {
            guard turns[project.id] === turn, !turn.stopped else { return }
            self.note(activity, for: project)
        }
        say(TurnProgress.activity(for: ToolCall("look_at_app")))
        defer {
            turn.look.inProgress = false
            if turns[project.id] === turn { progress[project.id]?.looking = false }
            say(Activity.thinking)
        }

        try? await writeOwnFiles(project, all: false)
        // A game is played in the preview on this Mac; only a look asked to be on the Xbox goes there.
        if GameKit.isGame(project), !onDevice { return await lookAtGame(project, turn: turn, motion: motion) }
        // A screen is looked at in the TV preview, wherever it's shown, with no build of the app around it. Pointed at a TV
        // it goes the TV app's way below, which stages the page before it opens the preview.
        if ScreenKit.isScreen(project), !onDevice, !project.onTV {
            return await lookOnTV(project, turn: turn, changed: Runtime.sourcesChanged(project), reopen: reopen)
        }
        let changed = Runtime.sourcesChanged(project)
        if changed, let errors = await build(project, inPlace: !reopen) {
            if errors == gameToolsProblem(project) {
                return (200, ["text": "The game can't be built yet, and Lamp has told the person why: \(errors)\n\nThis isn't a mistake in the code. Finish what was asked without a look, and tell the person in a sentence that you'll build it once the tools are there."])
            }
            if errors == androidToolsProblem(project) {
                return (200, ["text": "The app can't be built yet, and Lamp has told the person why: \(errors)\n\nThis isn't a mistake in the code. Finish what was asked without a look, and tell the person in a sentence that you'll build it once the tools are there."])
            }
            if errors == macMembershipProblem(project) {
                return (200, ["text": "The app can't be built for this Mac, and Lamp has told the person why: \(errors)\n\nThis isn't a mistake in the code. Don't take iCloud out unless the person asked for that; finish what was asked without a look."])
            }
            return (200, ["text": "The app doesn't build yet. Fix these compiler errors:\n\n\(errors)"])
        }
        var note = "The app built and is running."
        var screenshots: [URL] = []
        let looking = "Looking at \(project.name)"
        // What went into the open app as the agent saved, since its last look.
        let saved = turn.autoApplied
        turn.autoApplied = 0
        if project.onAndroid { return await lookOnAndroid(project, turn: turn, changed: changed, reopen: reopen) }
        if project.onTV { return await lookOnTV(project, turn: turn, changed: changed, reopen: reopen) }
        if project.onDevice { return await lookOnDeviceApp(project, turn: turn, changed: changed, reopen: reopen, onDevice: onDevice) }
        if project.onIOS {
            // The simulator photographs the screen; nothing in the app has to cooperate.
            // Open, and the device still this app's: otherwise it's opened again (which takes the device back).
            let running = simulatorApps[project.id].map { Simulator.isRunning(pid: $0.pid) && simulatorLeases[$0.udid] == project.id } ?? false
            if changed || !running || reopen {
                let crash = await install(project, inFront: false, early: true)
                turn.look.installed[project.id] = true
                turn.look.crashes[project.id] = crash
                if let crash { return (200, ["text": "The app \(changed ? "built" : "is built"), but it didn't stay open.\n\n\(crash)"]) }
                if !changed { note = "The app is running your latest code; it was reopened without rebuilding." }
                if reopen { note = "The app was closed and opened again, so it started fresh." }
            } else {
                note = "The app is running your latest code; nothing needed rebuilding."
                // With a phone chosen under Try On, what's open in the simulator is this code, as after a launch: the
                // turn's end puts it on the phone, as it does after a look that opened it. Without one the simulator is
                // left as the agent found it, its state kept.
                if project.device != nil {
                    turn.look.installed[project.id] = true
                    turn.look.crashes[project.id] = nil
                }
            }
            say(looking)
            let picture = Runtime.folder(project).appendingPathComponent("screenshot.png")
            if let udid = simulatorApps[project.id]?.udid, await Simulator.screenshot(on: udid, to: picture) { screenshots = [picture] }
            if turn.look.crashes[project.id] == nil { await present(project, in: turn) }
            // Which simulator: what it can show depends on it (a Dynamic Island is only on some iPhones).
            var on = ""
            if let udid = simulatorApps[project.id]?.udid, let name = await Simulator.name(of: udid) { on = " It's open on the \(name) simulator." }
            if !turn.look.toldPhone {
                turn.look.toldPhone = true
                devices = await Devices.list()
                on += " " + Devices.tryOnNote(chosen: project.device, among: devices)
            }
            var text = note + on + " " + (screenshots.isEmpty ? "No picture of the iPhone could be taken."
                : Privacy.sharesPictures ? "A picture of the iPhone's screen follows. Points for use_app are pixels in it." : Privacy.picturesOff)
            if !Privacy.sharesLog { text += " " + Privacy.logOff }
            // The screen in words, beside its picture. Reading it needs the same permission as use_app, which
            // is what asks for it: until then a look is the picture alone, as it always was.
            if Privacy.sharesPictures, Simulator.Driver.isAllowed, let running = simulatorApps[project.id] {
                switch await Simulator.Driver.screen(of: running.udid, owner: "\(project.id):\(running.pid)") {
                case .success(let screen):
                    // Asked again after the read: it takes a moment, and the setting can be turned off meanwhile.
                    if let words = await Simulator.Driver.screenText(on: screen), Privacy.sharesPictures { text += "\n\n" + words }
                case .failure(let trouble):
                    // The picture came from the simulator itself and is good; only the words and use_app need the window.
                    text += "\n\nThe screen as text is missing, and use_app would be refused for the same reason: " +
                        trouble.message(viewer: Simulator.viewerName(), device: project.family.name)
                }
            }
            if Privacy.sharesLog, let tail = Runtime.logTail(project) { text += "\n\nWhat it printed:\n\(tail)" }
            if prop != nil || motion { text += "\n\nprop and motion are for Mac apps; this look is the usual one." }
            return (200, ["text": text, "screenshots": Self.agentPictures(screenshots, in: project)])
        }
        // The copy on screen is an earlier build the person kept open: not shown as the agent's work, and not
        // asked to quit again at every look.
        if turn.keptOpen, isRunning(project) { return held(turn, in: project, note: Self.keptOpenNote) }
        // Asked again after the build, which can take a minute: the person may have opened the app meanwhile.
        if wantsFresh, !asking, asksBeforeReopening(project, owner: turn) {
            asking = true
            reopen = false
        }
        if asking {
            if !Runtime.waitsForReload(project) {
                _ = await install(project, inFront: false, early: true)
                if turn.keptOpen { return held(turn, in: project, note: Self.keptOpenNote) }
                // Gone since (closed, or crashed with the change): nothing to ask about, and the next look opens it.
                guard isRunning(project) else { return (200, ["text": "The app closed before Lamp could ask to reopen it. Look again to open it."]) }
                if !Runtime.waitsForReload(project) { awaitReload(project, owner: turn) }
            }
            return held(turn, in: project, note: Self.askedToReopenNote)
        }
        if Runtime.waitsForReload(project), isRunning(project), !reopen { return held(turn, in: project, note: reloadNote(for: project)) }
        var since = Date()
        // A copy kept open in an earlier request is older than the build too: it's asked to quit, once.
        if !reopen, !changed, !Runtime.holdsBuild(project), macCopies(of: project).first != nil {
            // Nothing to rebuild and the app is open: ask it for fresh pictures instead of relaunching it.
            let asked = Date()
            since = asked
            say(looking)
            Runtime.requestScreenshots(of: project)
            screenshots = await Runtime.screenshots(of: project, since: asked, waiting: 2)
            note = saved > 0 ? "What you saved went into the open app by itself as you saved it (\(saved) \(saved == 1 ? "time" : "times")): the person is seeing it now, with the window as they left it."
                : "The app is running your latest code; nothing needed rebuilding."
            turn.look.installed[project.id] = !screenshots.isEmpty
            turn.look.crashes[project.id] = nil
        }
        if screenshots.isEmpty {
            let launched = Date()
            // A look with `reopen` asks for the fresh launch itself, so it doesn't wait for Reload.
            let crash = await install(project, inFront: false, fresh: reopen, reload: reopen, early: true)
            if turn.keptOpen { return held(turn, in: project, note: Self.keptOpenNote) }
            if Runtime.waitsForReload(project), isRunning(project) { return held(turn, in: project, note: reloadNote(for: project)) }
            turn.look.installed[project.id] = true
            turn.look.crashes[project.id] = crash
            if let crash {
                return (200, ["text": "The app \(changed ? "built" : "is built"), but it quit right after launching.\n\n\(crash)"])
            }
            if !changed { note = "The app is running your latest code; it was reopened without rebuilding." }
            if reopen { note = "The app was closed and opened again, so it started fresh." }
            // Which way the change reached the app: the person sees a live change at once, as they left the window.
            switch turn.outcomes.last {
            case .live?:
                note = saved > 0 ? "What you saved went into the open app by itself as you saved it (\(saved) \(saved == 1 ? "time" : "times")), without reopening it: the person is seeing it now, with the window as they left it."
                    : "The change went into the open app without reopening it: the person is seeing it now, with the window as they left it."
                if turn.endedReloadWait {
                    note += " The change that was waiting for Reload went in with it, so nothing waits for Reload now; don't tell the person to press it."
                    turn.endedReloadWait = false
                }
            case .opened?: note = "The app wasn't open, so it was opened" + (changed ? " with the change." : ".")
            case .reopened?: note = "The app was closed and opened again with the change" + (turn.reloadWhy.map { ": \($0)." } ?? ".")
            default: break
            }
            say(looking)
            // A change that went into the open app didn't launch it, so nothing takes the pictures a launch does:
            // they're asked for, once the new code has had a moment to draw.
            if turn.updatedInPlace {
                try? await Task.sleep(for: .milliseconds(300))
                Runtime.requestScreenshots(of: project)
            }
            // Since this copy was asked to open, not since the look began: the copy it replaced pictures its window as it quits.
            since = max(launched, turn.launches.last { $0.app == project.id }?.opened ?? launched)
            screenshots = await Runtime.screenshots(of: project, since: since)
        }
        if turn.reloadedByPerson {
            turn.reloadedByPerson = false
            note += " The app was reloaded while you worked, so the change that waited for Reload is on screen now; nothing waits for Reload."
        }
        var lead = ""
        if let prop, !prop.isEmpty, !screenshots.isEmpty {
            // One prop on its own: the app shows it from four sides over its scene, pictures it, and goes back.
            let asked = Date()
            say("Looking at it from all sides")
            Runtime.requestProp(prop, of: project)
            switch await Runtime.propAnswer(of: project) {
            case "shown"?:
                let pictures = await Runtime.screenshots(of: project, since: asked, waiting: 3)
                if !pictures.isEmpty { screenshots = pictures }
                lead = "The prop \"\(prop)\" on its own, from the front, the right, above at three quarters and the back. "
            case let why?:
                lead = why + " "
            case nil:
                lead = "The app didn't show the prop: only a LampSceneView given `props` can. "
            }
        }
        if motion, !screenshots.isEmpty {
            say("Watching it move")
            if Privacy.sharesPictures, let watched = await Runtime.motion(of: project) {
                lead += watched.text + " "
                if !watched.pictures.isEmpty { screenshots = watched.pictures }
            } else if Privacy.sharesPictures {
                lead += "The app didn't answer the request to watch it; it may need rebuilding. "
            }
        }
        var text = lead + note + " " + (screenshots.isEmpty
            ? "It has no window open, so there's no picture. If it lives in the menu bar, use_app's bar_icon opens its panel."
            : Privacy.sharesPictures ? (lead.isEmpty ? "Pictures of its windows follow, frontmost first; x and y for use_app are pixels in the first." : "") : Privacy.picturesOff)
        if !Privacy.sharesLog { text += " " + Privacy.logOff }
        text += " This look took \(Int(Date().timeIntervalSince(began).rounded())) seconds."
        text += Self.handingHint(for: project)
        text += await Self.intentsHint(for: project)
        text += Self.shareHint(for: project)
        // The front window in words, beside its picture, from the app itself (LampScreen in LampSupport.swift).
        if Privacy.sharesPictures, !screenshots.isEmpty, Self.binary(of: project, contains: Self.screenTextMarker),
           let words = await Runtime.screenText(of: project, since: since) { text += "\n\n" + words }
        if Privacy.sharesLog, let tail = Runtime.logTail(project) { text += "\n\nWhat it printed:\n\(tail)" }
        if !screenshots.isEmpty { await present(project, in: turn) }
        return (200, ["text": text, "screenshots": Self.agentPictures(screenshots, in: project)])
    }

    /// A new Mac app is shown to the person as soon as there's something to show: its scaffold (a window with its
    /// name, which says Lamp is making it) is built and opened while the agent starts work, and the chat moves beside
    /// it (`present`), so the passes that follow go in where the person is already looking rather than after the
    /// agent's first look, minutes in. Quietly: a build that fails (the agent may be writing files as it runs) just
    /// leaves it to that first look. An iPhone app waits for that look, which opens the simulator.
    private func showEarly(_ project: LampProject, in turn: Turn) {
        guard project.platform == .mac || (project.platform.addsPlaces && project.destination == .mac), Template.isScaffold(project),
              !isRunning(project) else { return }
        turn.early = Task { [weak self] in
            guard let self, turns[project.id] === turn, !turn.stopped else { return }
            guard await build(project) == nil, turns[project.id] === turn, !turn.stopped, !turn.asked else { return }
            guard await install(project, inFront: false) == nil, !turn.didNotOpen else { return }
            await present(project, in: turn)
        }
    }

    /// A new app is built in passes, and the first look that opens it shows it to the person, so they watch it take
    /// shape instead of waiting for the end: a Mac app comes forward with its chat beside it (`MagicPanel.handOff`, which
    /// otherwise happens once the turn is over), an iPhone app's simulator comes forward. Once a turn, after the agent's
    /// pictures are taken, and only for the first turn of a new app: later turns change an app that's open already.
    private func present(_ project: LampProject, in turn: Turn) async {
        // A part is new with its wish, and shown at its own first look.
        let shown = project.isPart ? turn.look.presentedParts.contains(project.id) : turn.look.presented
        guard progress[wish(of: project).id]?.newApp == true, !shown, turns[project.id] === turn, !turn.stopped,
              !turn.keptOpen else { return }
        if project.isPart { turn.look.presentedParts.insert(project.id) } else { turn.look.presented = true }
        if project.onAndroid {
            if project.device == nil { await Emulator.bringForward() }
        } else if project.onIOS {
            if let udid = simulatorApps[project.id]?.udid { await Simulator.show(udid) }
        } else if !project.isPart {
            // The chat goes beside the wish's own app; a Mac part has no chat of its own to bring.
            Task { await MagicPanel.shared.handOff(project) }
        }
    }

    /// For an app that declares what it opens (`opens` in capabilities.json): the command that hands this
    /// copy a file, said with each look because the path is the installed one, which the agent's confined
    /// shell can open with but can't see, and which moves when the app is renamed. Given the copy in build/
    /// or the bundle id instead, macOS starts that copy beside the one Lamp opened.
    nonisolated static func handingHint(for project: LampProject) -> String {
        guard !project.onIOS, !Template.Capabilities.load(project).kinds.isEmpty else { return "" }
        return "\n\nTo hand it a file or folder as Finder would, run `open -g -a \(Sandbox.quoted(project.installedURL.path)) <path>`, " +
            "then `use_app` with a wait to see the result. Use that path, not the copy in build/ or the bundle id: those start a second copy."
    }

    /// For a Mac app whose code has App Intents and whose installed copy has none: `deploy` takes them out of an
    /// app it couldn't sign for an Apple team, since macOS lists such an app's intents and never runs them. Read
    /// off the installed copy, so a team that's chosen but couldn't sign (its key refused) is told as well.
    nonisolated static func intentsHint(for project: LampProject) async -> String {
        guard project.platform == .mac, usesAppIntents(project), !hasIntentsMetadata(project.installedURL) else { return "" }
        if await Subprocess.run("/usr/bin/xcrun", ["-f", "appintentsmetadataprocessor"], timeout: 20).status != 0 {
            return "\n\nSiri, Shortcuts and Spotlight can't see this app's App Intents: reading them out of the code takes Xcode, which " +
                "isn't installed. Tell the user they come on once Xcode is installed."
        }
        if await Devices.signingIdentity(for: Devices.team) == nil {
            return "\n\nSiri, Shortcuts and Spotlight can't use this app's App Intents yet: macOS runs them only for an app signed for an " +
                "Apple developer team, and Lamp has none to sign with. Tell the user they come on once they choose their team in Lamp's " +
                "Settings → Building (it needs Xcode signed in to their Apple account)."
        }
        return "\n\nSiri, Shortcuts and Spotlight can't use this app's App Intents: Lamp couldn't sign it for the user's Apple team, most " +
            "likely because macOS asked for access to the team's signing key and it wasn't allowed. Tell the user to choose Always Allow " +
            "when macOS asks during the next build."
    }

    /// For a Mac app with a share extension that its installed copy doesn't carry: `deploy` leaves it out of an
    /// app it couldn't sign for an Apple team, since without a team the extension has no folder to leave what
    /// it's given for the app.
    nonisolated static func shareHint(for project: LampProject) -> String {
        guard project.platform == .mac, Template.hasShare(project),
              FileManager.default.fileExists(atPath: project.installedURL.path),
              !FileManager.default.fileExists(atPath: Template.shareURL(in: project.installedURL, of: project).path) else { return "" }
        return "\n\nThe app isn't in other apps' share menus yet: on a Mac, Lamp can only add its share extension to an app it signs for " +
            "an Apple developer team. Tell the user it comes on once they choose their team in Lamp's Settings → Building (it needs " +
            "Xcode signed in to their Apple account)."
    }

    /// Whether a bundle carries App Intents for the system to find.
    nonisolated static func hasIntentsMetadata(_ app: URL) -> Bool {
        FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/Resources/Metadata.appintents").path)
    }

    /// A Mac app installed without its App Intents, which a build could now give them: Xcode's tool is here to
    /// read them, there's a team on this Mac to sign for, and signing for that team hasn't already failed (its
    /// key refused), so an app whose intents can't come back opens as it is instead of being built every time.
    nonisolated static func intentsCanComeBack(_ project: LampProject) async -> Bool {
        guard project.platform == .mac, usesAppIntents(project),
              FileManager.default.fileExists(atPath: project.installedURL.path), !hasIntentsMetadata(project.installedURL),
              (try? String(contentsOf: teamSigningFailure(project), encoding: .utf8)) != Devices.team else { return false }
        guard await Subprocess.run("/usr/bin/xcrun", ["-f", "appintentsmetadataprocessor"], timeout: 20).status == 0 else { return false }
        return await Devices.signingIdentity(for: Devices.team) != nil
    }

    /// The same for a Mac app's share extension, which `deploy` leaves out of an app it can't sign for a team:
    /// a team to sign for now, which hasn't already failed, brings it back with a build.
    nonisolated static func shareCanComeBack(_ project: LampProject) async -> Bool {
        guard project.platform == .mac, Template.hasShare(project),
              FileManager.default.fileExists(atPath: project.installedURL.path),
              !FileManager.default.fileExists(atPath: Template.shareURL(in: project.installedURL, of: project).path),
              (try? String(contentsOf: teamSigningFailure(project), encoding: .utf8)) != Devices.team else { return false }
        return await Devices.signingIdentity(for: Devices.team) != nil
    }

    /// Writes what the app is told about itself and Lamp (`Template.installValues`) into a bundle's Info.plist,
    /// before it's signed: LampSupport reads it there at launch rather than having it compiled in. `root` is the
    /// folder the bundle is in, read and written without following links out of it: the simulator's bundle is in
    /// the app's build folder, which the agent's commands can write.
    ///
    /// `wishKey` is the wish's key for an app with others in its wish (`WishKeys`), only ever for a copy in a folder of
    /// Lamp's own: the installed Mac app's.
    nonisolated static func setInstallValues(for project: LampProject, in plistURL: URL, root: URL,
                                             values: [String: String]? = nil, wishKey: Data? = nil) {
        guard let data = AppFile.read(plistURL, inFolder: root),
              var plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return }
        plist["LampInstall"] = values ?? Template.installValues(for: project)
        plist[Template.wishKeyName] = wishKey?.base64EncodedString()
        if let out = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
            try? AppFolder.write(out, to: plistURL, in: root)
        }
    }

    /// Writes, or takes out, the name of the folder a Mac app shares with its widget, in each bundle's Info.plist,
    /// before they're signed. Both sides read it there to choose how the widget's buttons reach the app.
    nonisolated static func setAppGroup(_ group: String?, in bundles: [URL]) {
        for bundle in bundles {
            let url = bundle.appendingPathComponent("Contents/Info.plist")
            guard let data = try? Data(contentsOf: url),
                  var plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { continue }
            guard (plist["LampAppGroup"] as? String) != group else { continue }
            plist["LampAppGroup"] = group
            if let out = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) { try? out.write(to: url) }
        }
    }

    /// Where `deploy` notes the team it couldn't sign an app for; a build the person or the agent asks for
    /// tries again either way.
    nonisolated static func teamSigningFailure(_ project: LampProject) -> URL {
        project.dir.appendingPathComponent(".lamp/team-signing-failed")
    }

    nonisolated static func rememberTeamSigning(failed: Bool, for project: LampProject) {
        let file = teamSigningFailure(project)
        if failed { try? Devices.team.write(to: file, atomically: true, encoding: .utf8) } else { try? FileManager.default.removeItem(at: file) }
    }

    /// Whether the app's code, or its widget's, uses App Intents, as build.sh decides it.
    nonisolated static func usesAppIntents(_ project: LampProject) -> Bool {
        ["Sources", "Widget"].contains { folder in
            let root = project.dir.appendingPathComponent(folder)
            guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return false }
            return files.contains { item in
                guard let url = item as? URL, url.pathExtension == "swift", url.lastPathComponent != "LampSupport.swift" else { return false }
                return (try? String(contentsOf: url, encoding: .utf8))?.contains("import AppIntents") == true
            }
        }
    }

    private func record(_ project: LampProject, cost: Double) {
        usage[project.id, default: AppUsage()].calls += 1
        usage[project.id, default: AppUsage()].cost += cost
        saveUsage(project)
    }

    private func recordAgent(_ project: LampProject, cost: Double) {
        var current = usage[project.id] ?? AppUsage()
        current.agentRuns = (current.agentRuns ?? 0) + 1
        current.agentCost = (current.agentCost ?? 0) + cost
        usage[project.id] = current
        saveUsage(project)
    }

    /// A picture the builder painted (`make_art`): part of what building the app cost, not a run of its own.
    private func recordArt(_ project: LampProject, cost: Double) {
        guard cost > 0 else { return }
        usage[project.id, default: AppUsage()].agentCost = (usage[project.id]?.agentCost ?? 0) + cost
        saveUsage(project)
    }

    private func saveUsage(_ project: LampProject) {
        if let data = try? JSONEncoder().encode(usage[project.id]) {
            try? data.write(to: project.dir.appendingPathComponent(".lamp/usage.json"))
        }
    }

    private static let lsregister =
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// One app's own choice of models for its AI features, in .lamp/models.json. nil uses Lamp's default
/// from Settings → Apps.
struct AppModels: Codable, Equatable {
    var text: String?       // an AppAI.TextRoute id
    var image: String?      // an id from Icons.artModels
    var decision: String?   // an id from AppAI.decisionModels
    var away: String?       // iPhone apps: an id from AppAI.anthropicModels, for when the phone can't reach the Mac
    var awayImage: String?  // iPhone apps: an id from Icons.artModels, likewise
    var awayDecision: String?  // iPhone apps: an id from AppAI.awayDecisionModels, likewise

    private static func url(_ project: LampProject) -> URL { project.dir.appendingPathComponent(".lamp/models.json") }

    static func load(_ project: LampProject) -> AppModels {
        (try? Data(contentsOf: url(project))).flatMap { try? JSONDecoder().decode(AppModels.self, from: $0) } ?? AppModels()
    }

    func save(_ project: LampProject) {
        let url = Self.url(project)
        defer { NotificationCenter.default.post(name: Self.changed, object: project.id) }
        if self == AppModels() { try? FileManager.default.removeItem(at: url); return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(self).write(to: url)
    }

    /// Posted when an app's own choices are saved, with its id: setup cards and notes look again.
    static let changed = Notification.Name("LampAppModelsChanged")
}
