import SwiftUI
import LampSidebarKit
import CryptoKit
import AppKit

/// What an app is for: a Mac app that installs beside the user's others, an iPhone app that runs in the
/// iOS Simulator on this Mac or on the person's own phone, or one app for both, as Xcode's multiplatform
/// apps are: one code, built for whichever is chosen under Try On (`LampProject.destination`).
enum Platform: String, Codable {
    case mac, iphone, universal   // "iphone" is the iOS kind: iPhone and iPad apps alike (see DeviceFamily)

    var hasMac: Bool { self != .iphone }
    var hasIOS: Bool { self != .mac }
}

/// Where an app is built for and opened: this Mac, or iOS (a simulator, or the person's phone, by
/// `LampProject.family` and `device`). A Mac app or an iPhone app has one; an app for both has the one
/// Try On last chose.
enum Destination: String, Codable {
    case mac, ios
}

/// Which simulator an iOS app opens on. The app itself is built for both.
enum DeviceFamily: String, Codable {
    case iphone, ipad
    var name: String { self == .ipad ? "iPad" : "iPhone" }
}

/// What a new app is made as, chosen before its first message: in the welcome and in a new app's intro.
/// iPhone and iPad are one kind of app, as Apple has it; which simulator it opens in is Try On's choice.
/// The names are what the intro's sentence says ("Describe the iPhone & iPad app you wish you had").
extension Platform {
    /// What an app made for these devices is: the names `make_app_for` and the naming call use ("mac",
    /// "iphone" for iPhone and iPad, "watch"). A watch app is part of an iPhone app (`Template.hasWatch`), so
    /// "watch" brings the iPhone with it. Nil for an empty list or a device Lamp doesn't make apps for.
    init?(devices: Set<String>) {
        guard !devices.isEmpty, devices.isSubset(of: ["mac", "iphone", "watch"]) else { return nil }
        let phone = devices.contains("iphone") || devices.contains("watch")
        self = devices.contains("mac") ? (phone ? .universal : .mac) : .iphone
    }
}

enum AppKind: String, CaseIterable {
    case mac = "Mac", phone = "iPhone & iPad", universal = "Mac, iPhone & iPad"

    init(_ project: LampProject) {
        self = switch project.platform {
        case .mac: .mac
        case .universal: .universal
        case .iphone: .phone
        }
    }
    var platform: Platform { self == .mac ? .mac : self == .universal ? .universal : .iphone }
    /// For the prompts that describe the app to a model: "a Mac app", "an iPhone and iPad app".
    var phrase: String {
        switch self {
        case .mac: "a Mac app"
        case .phone: "an iPhone and iPad app"
        case .universal: "an app for the Mac and the iPhone, one code for both"
        }
    }
    /// The device's picture where the kind is chosen.
    var symbol: String {
        switch self {
        case .mac: "laptopcomputer"
        case .phone: "iphone"
        case .universal: "laptopcomputer.and.iphone"
        }
    }
}

struct LampProject: Identifiable, Hashable {
    let id: String      // folder name; also used in lamp:// links
    let name: String    // display name
    let exe: String     // Swift target / executable name
    let dir: URL
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
    var platform: Platform = .mac
    var family: DeviceFamily = .iphone
    /// The person's own iPhone or iPad that Play puts the app on (Devices), instead of the simulator.
    var device: String?
    /// For an app made for both: where Try On last put it. Meaningless for the other kinds, which have one place.
    var chosen: Destination = .mac
    /// iOS apps: the simulator chosen by name under Try On (its udid), or nil for Lamp's own pick of the family.
    var simulator: String?
    /// Where the app is built for and opened now.
    var destination: Destination {
        switch platform {
        case .mac: .mac
        case .iphone: .ios
        case .universal: chosen
        }
    }
    /// On iOS now: the simulator, or the person's phone. The rest of Lamp's phone work follows this, and an
    /// app for both goes through it only while that's where it opens.
    var onIOS: Bool { destination == .ios }
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
    var builtURL: URL { dir.appendingPathComponent(platform == .universal && onIOS ? "build/iOS/\(exe).app" : "build/\(exe).app") }
    /// Every successful build is copied here so it shows up in Spotlight and Launchpad.
    var installedURL: URL { Store.installDir.appendingPathComponent("\(name).app") }
    /// What the app is called on screen. An unnamed one has only a stand-in name on disk ("Untitled", which
    /// its folder and everything that asks `untitled` go by), so the screen says what it is instead: a wish,
    /// theirs from the site or one still to be told. Nothing is an app until Lamp has made something; the
    /// name Lamp or the person gives it takes over everywhere at once.
    var title: String { !untitled ? name : fromWish ? "Your wish" : finding ? "Finding a wish" : "New wish" }
    /// False for a draft (Template.draft): a new app whose scaffold isn't written yet.
    var scaffolded: Bool { FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) }
}

struct ProjectMeta: Codable {
    var name: String
    var exe: String
    var untitled: Bool?
    var platform: Platform?   // nil in apps made before iPhone apps existed: a Mac app
    var family: DeviceFamily?  // iOS apps: which simulator they open on; nil means iPhone
    var device: String?        // iOS apps: the person's own phone (its udid) that Play puts the app on, if any
    var target: Destination?   // apps for both: where Try On last put it; nil means the Mac
    var simulator: String?     // iOS apps: the simulator chosen by name under Try On, if any
    var instance: String?      // LampProject.instance
    var wish: Bool?            // LampProject.fromWish
    var finding: Bool?         // LampProject.finding
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
    enum Kind: String, Codable { case user, agent, status, error, detail, tool, summary, needsKey, offer, noted, drawIcon, widget, ask, result, iphoneSetup }
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
    var result: Talk.Result? = nil    // what a request made, as the agent put it
    var noted: NoteReceipt? = nil     // what a save of Lamp's notes changed, with Undo
    var pointed: PointedAt? = nil     // for a request: what was pointed at in the app, one of its attachments

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

    /// "Worked for 4m 21s · $0.48"
    static func workSummary(seconds: Double, cost: Double) -> String {
        let total = Int(seconds.rounded())
        let time = total < 60 ? "\(total)s" : "\(total / 60)m \(total % 60)s"
        return String(format: "Worked for %@ · $%.2f", time, cost)
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
}

extension QueuedMessage {
    /// A request waiting for setup, as it's kept across a relaunch. The card it answers is kept with it:
    /// without it the answer would come back as a message of its own under a card that already shows it,
    /// and taking it back would no longer open the card again.
    var saved: [String: Any] {
        var saved: [String: Any] = ["text": text, "attachments": attachments.map(\.path)]
        if let card { saved["card"] = card.uuidString }
        return saved
    }

    /// `ask` is what the card was called in a request kept by an earlier Lamp: read, so that an answer
    /// still waiting from then can be taken back and its card opens again.
    init(saved: [String: Any], attachments: [URL]) {
        self.init(text: saved["text"] as? String ?? "", attachments: attachments,
                  card: ((saved["card"] ?? saved["ask"]) as? String).flatMap(UUID.init(uuidString:)))
    }
}

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var projects: [LampProject] = [] { didSet { syncLocalNetwork() } }   // the network listener follows which apps open on a phone
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
    /// The turn in progress for each app. A new app's first turn stays here after it finishes, so its
    /// build card can show the result until the next message.
    @Published var progress: [String: TurnProgress] = [:]
    /// Apps that are open right now, however they were started, so Lamp can offer to quit them.
    @Published var openApps: Set<String> = []
    /// The apps open on this Mac, and those open in a simulator or on a phone: an app for both can be in
    /// both at once, and its Play and Stop are for the place Try On points at (`isOpen`).
    @Published private(set) var openOnMac: Set<String> = []
    @Published private(set) var openOnIOS: Set<String> = []

    /// Whether the app is open where it would open now: for an app for both, where Try On points.
    func isOpen(_ project: LampProject) -> Bool {
        guard project.platform == .universal else { return openApps.contains(project.id) }
        return (project.onIOS ? openOnIOS : openOnMac).contains(project.id)
    }
    /// The apps whose widget the person has put on the desktop (`WidgetCard`), for their chats' cards.
    @Published var placedWidgets: Set<String> = []
    /// Which Lamp built each installed app (see BuildStamp). Missing for apps that aren't built yet.
    @Published var stamps: [String: BuildStamp] = [:]
    @Published var chatFocusRequest = 0
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
        let answer: CheckedContinuation<Bool, Never>
        var explanation: CommandExplanation?
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
    @MainActor final class Turn {
        var agent: Process?                 // the engine, while it runs
        var build: Process?                 // the app's build.sh, while it runs
        var stopped = false                 // the user pressed Stop (or deleted the app, or quit Lamp)
        /// Stop was pressed at some point in this turn. `stopped` is cleared once the agent has stopped, so the
        /// turn can go on; this stays, for what the turn's end reports (`Analytics`).
        var wasStopped = false
        /// The Mac app built but the last install couldn't put it in place or open it: logged, not a crash, so
        /// the turn still counts as a change. Kept so a new app's first run isn't counted when it never opened.
        var didNotOpen = false
        /// The person kept the app open when this turn's build asked it to quit: it isn't asked a second time
        /// in the turn, and the agent isn't shown the copy on screen as its work.
        var keptOpen = false
        /// The chat has said this turn closed the open app and opened it again (`ChatLook.reloaded`).
        var saidReloaded = false
        /// Nil for a simulator/Mac turn; false until the chosen phone acknowledges opening the app.
        var phoneReady: Bool?
        var allowAll = false                // "Allow all for this turn"
        var approving = false               // between the queue check and the approval card
        var look = Look()                   // what the agent's look_at_app has done
        var pendingName: String?            // a name the agent gave the version this request makes
        var pendingResult: Talk.Result?     // the agent's card for what this request made, shown once it's open
        /// The agent put its questions to the person this turn: the turn is over, whatever the agent does next.
        var asked = false
        /// Lamp ended the agent because it went on working past its own questions. Not a stop and not a failure.
        var endedOnQuestions = false
        var artCost = 0.0                   // what make_art's pictures cost, for the turn's summary
        var request: String?                // the user's words, for the command classifiers
        var claudeSession: String?          // Claude Code's conversation, as its own output says (Privacy.isOwnOutput)
        var writing: (line: UUID, unshown: String)?   // the message the agent is writing right now
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
            return pids
        }
    }
    private var turns: [String: Turn] = [:]

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
            let offer = busy.contains(project.id) ? nil : await UndoOffer.version(for: project, chat: logs[project.id] ?? [])
            guard undoOfferReads[project.id] == read else { return }
            let shown = busy.contains(project.id) ? nil : offer
            if undoOffers[project.id] != shown { undoOffers[project.id] = shown }
        }
    }

    /// Gives the app back, without starting anything queued (see `finish`).
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
        /// The app was built and opened by the last look, and this is how that launch went.
        var installed = false
        var crash: String?
    }
    private var artInProgress: Set<String> = []
    private var pendingIconArt: Set<String> = []     // artwork finished during a turn, to apply after it
    private var heldInstalls = HeldInstalls()        // new icons waiting for their app to close
    private var heldDrawingOffers: Set<String> = []  // "Draw Icon…" wanted during a turn, to offer after it
    private var artApplied: [String: IconSpec] = [:] // the spec whose artwork the rendered icon includes
    private var iconDesigns: [String: Task<Void, Never>] = [:]   // icons designed from the first message
    private var tokens: [String: String] = [:]   // app token → project id, for the app's own routes (/ai…)
    /// The agent's token for the turn in progress → project id. Minted per turn and gone with it, so the agent's
    /// routes (/agent/…, /mcp) can't be reached with the app's token, which the app itself holds, nor after the
    /// turn ends. A leaked app token then buys AI calls as that app, and nothing more.
    private var agentTokens: [String: String] = [:]
    private var gateway: Gateway?

    nonisolated static let installDir = Edition.appsFolder

    let root = Edition.supportFolder.appendingPathComponent("Apps")

    private init() {
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
        restoreWaiting()
        for project in projects { discardIfUnused(project.id) }
        Onboarding.settle(hasApps: !projects.isEmpty)
        // Lamp opens on the desk (`WishDesk`), not on a wish's chat.
        selection = nil
        startGateway()
        watchOpenApps()
        // Asking for phones runs devicectl, so only for someone with iPhone apps; Try On asks again when it's opened.
        if projects.contains(where: { $0.platform.hasIOS }) { refreshDevices(); refreshSimulators() }
        if !Provider.models.contains(where: { $0.id == UserDefaults.standard.string(forKey: "model") }) {
            UserDefaults.standard.set(Provider.model, forKey: "model")   // from the Claude Code era ("sonnet")
        }
        // The login shell's PATH, which every tool Lamp runs is given, and the person's own Claude Code and
        // Codex (running each copy found with --version to pick the newest) are looked for off the main thread
        // when Lamp keeps its engines current, before it decides whether it needs its own copy of one.
        EngineDownloads.shared.startKeepingCurrent()
        Task {
            LocalModels.shared.refresh()
            await LocalModels.shared.detectExternal()
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

    func reload() {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        projects = dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(".lamp/meta.json")),
                  let meta = try? JSONDecoder().decode(ProjectMeta.self, from: data) else { return nil }
            return LampProject(id: dir.lastPathComponent, name: meta.name, exe: meta.exe, dir: dir,
                                instance: meta.instance ?? dir.lastPathComponent,
                                untitled: meta.untitled ?? false, fromWish: meta.wish ?? false, finding: meta.finding ?? false,
                                platform: meta.platform ?? .mac, family: meta.family ?? .iphone,
                                device: meta.device, chosen: meta.target ?? .mac, simulator: meta.simulator)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        for project in projects {
            tokens[Template.token(for: project)] = project.id
            if icons[project.id] == nil, let image = NSImage(contentsOf: Icons.previewURL(project)) {
                icons[project.id] = image
            }
        }
        for project in projects { stamps[project.id] = BuildStamp.read(project.installedURL) }
        for project in projects where logs[project.id] == nil {
            let lamp = project.dir.appendingPathComponent(".lamp")
            if let data = try? Data(contentsOf: lamp.appendingPathComponent("chat.json")),
               let saved = try? JSONDecoder().decode([LogLine].self, from: data) {
                logs[project.id] = saved.map(\.upgraded)
            }
            if let data = try? Data(contentsOf: lamp.appendingPathComponent("usage.json")),
               let saved = try? JSONDecoder().decode(AppUsage.self, from: data) {
                usage[project.id] = saved
            }
        }
    }

    func log(_ project: LampProject, _ kind: LogLine.Kind, _ text: String, attachments: [String]? = nil, retryPhone: String? = nil,
             offer: SetupOffer? = nil, noted: NoteReceipt? = nil) {
        logs[project.id, default: []].append(LogLine(kind: kind, text: text, attachments: attachments, retryPhone: retryPhone,
                                                    offer: offer, noted: noted))
        if kind == .status, text.hasSuffix("…") { note(text, for: project) }   // "Building…"
        saveChat(project)
    }

    private func saveChat(_ project: LampProject) {
        guard exists(project) else { return }
        if let data = try? JSONEncoder().encode(logs[project.id]) {
            try? data.write(to: project.dir.appendingPathComponent(".lamp/chat.json"))
        }
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
            let line = LogLine(kind: .agent, text: String(piece.drop(while: \.isWhitespace)))
            logs[project.id, default: []].append(line)
            turn.writing = (line.id, "")
            note("Replying", for: project)
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

    /// Puts what has arrived of the message being written into its chat line.
    private func showWritten(for project: LampProject) {
        guard let turn = turns[project.id], let (line, unshown) = turn.writing, !unshown.isEmpty,
              let index = logs[project.id]?.lastIndex(where: { $0.id == line }) else { return }
        logs[project.id]?[index].text += unshown
        turn.writing?.unshown = ""
    }

    /// Updates what the app's turn is doing right now, for the build card and the activity line.
    /// `file` is the file being written or edited, when that's the step.
    private func note(_ activity: String, file: String? = nil, for project: LampProject) {
        guard let current = progress[project.id], current.activity != activity || current.currentFile != file else { return }
        progress[project.id]?.activity = activity
        progress[project.id]?.currentFile = file
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

    /// Brings Lamp to the front on an app's chat, in its own window, ready to type.
    func showChat(_ id: String) {
        reload()
        selection = id
        chatFocusRequest += 1
        NSApp.activate()
        LampWindows.showChat(id)
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

    /// A wish made on the desk goes straight to its chat, sent as if typed there: the chat sends it as it
    /// appears (`sendWhenShown`), so it goes through the same setup checks and lands in the same place.
    @Published var sendWhenShown: String?

    func wish(_ text: String, attachments: [URL] = [], spoken: Bool = false) {
        guard !text.trimmed.isEmpty || !attachments.isEmpty else { return }
        create(from: spoken ? .spoken : .typed)
        guard let project = selected else { return }
        updateDraft(Draft(text: text.trimmed, attachments: attachments), for: project)
        sendWhenShown = project.id
    }

    /// "Help me find one": a new wish whose first request asks the agent to find it with the person, in the
    /// chat, through its cards (`Agent.findRules`).
    func findWish() {
        create(from: .finding)
        guard let project = selected else { return }
        updateDraft(Draft(text: Agent.findingRequest), for: project)
        sendWhenShown = project.id
    }

    /// The desk's window in front.
    func showDesk() {
        NSApp.activate()
        LampWindows.showDesk()
    }

    /// What's typed in the desk's wish bar and not sent: kept here, so going to a wish's chat and back keeps it.
    @Published var deskDraft = ""

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
        log(project, .error, "Couldn't set up the app: \(problem) Try again in a moment.")
        return nil
    }

    /// What a new app is made as, worked out from its first request (`AppName.suggest`) before anything is built:
    /// nobody is asked to choose. A kind the person didn't say is only taken when this Mac can build it now
    /// (Xcode for an iPhone app; a team too for an app for both), else it's a Mac app, which needs neither, and
    /// the chat says so with the setup a button away (`IPhoneSetupLine`). One they said is taken either way, and
    /// the build says what's missing. A line in the chat says what it'll be unless it's a Mac app, and the person
    /// changes it by asking (`convert`, the agent's `make_app_for`).
    func chooseKind(_ project: LampProject, _ kind: Platform, said: Bool, watch: Bool = false) async -> LampProject {
        guard !project.scaffolded, kind != project.platform else { return project }
        if kind.hasIOS, !said {
            let both = kind == .universal
            let ready = await Task.detached { PhoneTools.checked(family: .iphone, phone: nil, requiresTeam: both, requiresPaidTeam: false).ready }.value
            guard ready else {
                log(project, .iphoneSetup, kind.rawValue)
                return project
            }
        }
        setKind(project, kind)
        guard let chosen = current(project) else { return project }
        if kind != .mac {
            let devices = kind == .iphone ? "iPhone and iPad" : "the Mac, iPhone and iPad"
            log(chosen, .status, watch ? "Making this for \(devices), and Apple Watch." : "Making this for \(devices).")
        }
        return chosen
    }

    /// A draft's kind: a draft only says what it will be, so this is a change to that, made while its first
    /// request is under way (`chooseKind`), before anything is written for it.
    private func setKind(_ project: LampProject, _ platform: Platform) {
        guard !project.scaffolded, let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        var changed = projects[index]
        changed.platform = platform
        // Choosing what to make doesn't need installed tools. Send checks the selected simulator
        // before building and explains the next setup action without blocking this draft's picker.
        if !platform.hasIOS { changed.device = nil }
        // An app for both starts on the Mac, where its first build is seen; Try On moves it.
        changed.chosen = .mac
        guard changed != projects[index], (try? Template.saveMeta(changed)) != nil else { return }
        projects[index] = changed
    }

    @discardableResult
    private func initRepo(_ project: LampProject, message: String) async -> Bool {
        await Versions.git("git init -q && git add -A && \(Self.commit) -qm \"$LAMP_MESSAGE\"", cwd: project.dir,
                        env: ["LAMP_MESSAGE": message]) { _ in } == 0
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
        let moving = project.platform == .universal && project.chosen != .ios
        let newSimulator = simulator ?? project.simulator
        let otherSimulator = newSimulator != project.simulator
        guard project.platform.hasIOS, project.device != udid || project.family != family || moving || otherSimulator,
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
        let said = name.map { "\(changed.name) will open on \($0) from now on. Press Play to put it there." }
            ?? "\(changed.name) will open on the \(simulatorName(changed)) simulator from now on."
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

    /// Back to a simulator from a phone, as one change: the family is set on the project as it is after
    /// the phone is forgotten, not on the copy the menu held.
    func setSimulator(_ project: LampProject, _ family: DeviceFamily) {
        setDevice(project, nil, family: family, simulator: .some(nil))
    }

    /// One simulator by name, from Try On's list.
    func setSimulator(_ project: LampProject, _ choice: Simulator.Choice) {
        setDevice(project, nil, family: choice.family, simulator: .some(choice.udid))
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

    /// The person's paired iPhones and iPads, for Try On. Looked up when the list is wanted (opening the
    /// menu) and at startup; a phone that's gone stays chosen, and Play says so.
    @Published var devices: [Devices.Device] = []

    /// What Try On shows beside Play: the simulator's kind, or the chosen phone's name, or this Mac.
    func tryOnName(_ project: LampProject) -> String {
        guard project.onIOS else { return "My Mac" }
        guard let udid = project.device else { return simulatorName(project) }
        return devices.first(where: { $0.udid == udid })?.name ?? "Your phone"
    }

    /// An app for both, back on this Mac: Try On's "My Mac". Its next open is a Mac build; the iOS copy stays
    /// open, and Stop quits it once Try On points there again.
    func setMac(_ project: LampProject) {
        guard project.platform == .universal, project.chosen != .mac, begin(project) != nil else { return }
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
    func pairDevice(_ device: Devices.Device, for project: LampProject) {
        guard !pairing.contains(device.udid) else { return }
        pairing.insert(device.udid)
        log(project, .status, "Look at \(device.name): tap Trust when it asks, and enter its passcode.")
        Task {
            defer { pairing.remove(device.udid) }
            // The chat may have moved meanwhile: a first message renames a new app under a new id.
            @MainActor func tell(_ kind: LogLine.Kind, _ text: String) { if let now = current(project) { log(now, kind, text) } }
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

    func refreshDevices() {
        Task {
            let found = await Devices.list()
            if found != devices { devices = found }
        }
    }

    /// An untitled app you left without ever using is deleted, so trying New leaves nothing behind.
    /// Words in its message box count as using it: they're kept, like a draft in any other app.
    private func discardIfUnused(_ id: String) {
        guard let project = projects.first(where: { $0.id == id }), project.untitled, nothingAsked(of: id),
              draft(for: project).text.trimmed.isEmpty,
              !FileManager.default.fileExists(atPath: project.builtURL.path) else { return }
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
        guard !project.finding, begin(project) != nil else { return }
        finish(await performRename(project, to: name))
    }

    /// Renames while the app is marked busy, so nothing else starts on it meanwhile.
    private func performRename(_ project: LampProject, to rawName: String) async -> LampProject {
        let name = rawName.trimmed.filter { !"\"\\<>&/:".contains($0) }
        guard !name.isEmpty, name != project.name || project.untitled,
              let current = projects.first(where: { $0.id == project.id }) else { return project }
        let unique = uniqueName(name, ignoring: current.id)
        if !current.scaffolded {
            return renameDraft(current, to: unique)
        }
        if await isPristine(current) {
            return await rescaffold(current, as: unique)
        }

        let fm = FileManager.default
        let renamed = LampProject(id: current.id, name: unique, exe: current.exe, dir: current.dir, instance: current.instance,
                                  platform: current.platform, family: current.family, device: current.device, chosen: current.chosen, simulator: current.simulator)
        try? Template.saveMeta(renamed)
        if fm.fileExists(atPath: current.installedURL.path) {
            try? fm.moveItem(at: current.installedURL, to: renamed.installedURL)
            _ = await Shell.run(Self.lsregister + " -f \"$LAMP_APP\"", cwd: current.dir,
                                env: ["LAMP_APP": renamed.installedURL.path]) { _ in }
        }
        Self.retitle(current.dir, from: current.name, to: unique)
        _ = await Versions.git("git add -A && \(Self.commit) -qm \"$LAMP_MESSAGE\"", cwd: current.dir,
                            env: ["LAMP_MESSAGE": "Rename to \(unique)"]) { _ in }
        reload()
        log(renamed, .status, "Renamed to \(unique)")
        return renamed
    }

    /// The old name in window titles and APP.md. Anything subtler is left for the agent.
    private static func retitle(_ dir: URL, from old: String, to new: String) {
        let fm = FileManager.default
        let sources = dir.appendingPathComponent("Sources")
        let files = (fm.enumerator(at: sources, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "LampSupport.swift" }
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let updated = text.replacingOccurrences(of: "\"\(old)\"", with: "\"\(new)\"")
            if updated != text { try? updated.write(to: file, atomically: true, encoding: .utf8) }
        }
        let appMd = dir.appendingPathComponent("APP.md")
        if let text = try? String(contentsOf: appMd, encoding: .utf8), text.hasPrefix("# \(old)\n") {
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
        let copy = LampProject(id: slug, name: name, exe: exe, dir: root.appendingPathComponent(slug),
                               instance: UUID().uuidString, platform: project.platform, family: project.family,
                               device: project.device, chosen: project.chosen, simulator: project.simulator)
        do {
            try fm.createDirectory(at: copy.dir.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
            // Everything at the top but what a build makes again (Lamp's own files are rewritten before it).
            for item in try fm.contentsOfDirectory(atPath: project.dir.path) where ![".lamp", "build", ".build"].contains(item) {
                try fm.copyItem(at: project.dir.appendingPathComponent(item), to: copy.dir.appendingPathComponent(item))
            }
            for path in Self.duplicatedState where fm.fileExists(atPath: project.dir.appendingPathComponent(path).path) {
                try fm.copyItem(at: project.dir.appendingPathComponent(path), to: copy.dir.appendingPathComponent(path))
            }
            try Template.saveMeta(copy)
            Self.retitle(copy.dir, from: project.name, to: name)
            if let spec = Icons.load(project) {
                var recolored = spec
                recolored.background = otherBackground(than: spec).name
                // The same artwork, filed under the new background so the copy's icon finds it.
                if fm.fileExists(atPath: Icons.artURL(copy, spec: spec).path) {
                    try? fm.copyItem(at: Icons.artURL(copy, spec: spec), to: Icons.artURL(copy, spec: recolored))
                }
                Icons.save(recolored, for: copy)
            }
            // Lamp's own files as the copy's build writes them, so its first version is what it builds and
            // it starts with nothing unsaved.
            try Template.writeOwnedFiles(for: copy)
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
        _ = await Versions.git("git add -A && \(Self.commit) -qm \"$LAMP_MESSAGE\"", cwd: copy.dir,
                               env: ["LAMP_MESSAGE": "Copy of \(project.name)"]) { _ in }
        if let spec = Icons.load(copy) { await renderIcon(copy, spec: spec) }
        finish(copy)
        showChat(copy.id)
        log(copy, .status, "A copy of \(project.name). Building it now…")
        await run(copy)
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
        try? fm.removeItem(at: old.dir)

        if let device = old.device {   // the phone chosen before the first message stays chosen
            var kept = project
            kept.device = device
            try? Template.saveMeta(kept)
        }
        follow(old, to: project)
        return project
    }

    /// A draft has no files yet to name after the app, so renaming it is moving its folder to match.
    private func renameDraft(_ old: LampProject, to name: String) -> LampProject {
        let exe = Template.identifier(from: name)
        let slug = exe.lowercased() == old.id ? old.id : Template.freeSlug(for: exe, in: root)
        let project = LampProject(id: slug, name: name, exe: exe, dir: root.appendingPathComponent(slug), instance: old.instance,
                                  platform: old.platform, family: old.family, device: old.device, chosen: old.chosen, simulator: old.simulator)
        do {
            if slug != old.id { try FileManager.default.moveItem(at: old.dir, to: project.dir) }
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
        let taken = Set(projects.filter { $0.id != id }.map { $0.name.lowercased() })
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

    /// Puts the app's .lampapp file on the clipboard, ready to paste into Slack, Messages, Mail or Finder.
    func canShare(_ project: LampProject) -> Bool { project.scaffolded }

    func copyAppFile(_ project: LampProject) {
        guard canShare(project) else { return }
        do {
            let file = try Self.sharedFile(of: project)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([file as NSURL])
            log(project, .status, "Copied \(file.lastPathComponent). Paste it into Slack, Messages, Mail or a Finder window.")
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// The app's .lampapp, written where it outlives the paste or the drop that hands it on: another app may
    /// read it after Lamp has moved on.
    nonisolated static func sharedFile(of project: LampProject, at file: URL? = nil) throws -> URL {
        let exported = try Sharing.export(project)
        let file = file ?? sharedFolder.appendingPathComponent(exported.lastPathComponent)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: exported, to: file)
        return file
    }

    nonisolated static var sharedFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Forge/Shared", isDirectory: true)
    }

    func chooseExport(_ project: LampProject) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.lampApp]
        panel.nameFieldStringValue = "\(project.name).lampapp"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            let file = try Sharing.export(project)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: file, to: destination)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    struct PendingImport: Identifiable {
        let id = UUID()
        let package: Sharing.Package
        var review: ImportReview?
        /// Opened during setup and kept until now: the review says so, since it arrives unasked.
        var waited = false
        /// The app already here that this file is another version of, if any: the choice is then Update or Keep Both.
        var existing: LampProject?
    }

    /// The app on this Mac that a shared file is a version of: the one it was shared from, or the copy made
    /// by opening an earlier file from it.
    func existingCopy(of package: Sharing.Package) -> LampProject? {
        guard let identity = package.identity else { return nil }
        // Only an app of the same kind: a file that's an iPhone app doesn't replace the Mac app it began as.
        return projects.first { $0.platform == package.platform && $0.scaffolded && Sharing.identity(of: $0, create: false) == identity }
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

    /// Unpacks a shared app and shows its review. `waited`: it was kept from before setup was done.
    private func review(_ file: URL, waited: Bool = false) {
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
            let pending = PendingImport(package: package, waited: waited, existing: existingCopy(of: package))
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
        if let file { review(file, waited: true) }
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
            /// False when the icon's pictures couldn't be returned; the ones there are then left alone.
            func putBack() async -> Bool {
                _ = await Versions.git("git restore --staged --worktree -- . && git clean -fdq -e .lamp -- . ':!\(Attachments.folder)'", cwd: project.dir) { _ in }
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
            } catch {
                let iconBack = await putBack()
                print("Update \(project.name) from a shared file failed: \(error)")
                log(project, .error, Self.updateFailed + (iconBack ? "" : Self.updateChangedIcon))
                return
            }
            if await Versions.hasUnsavedChanges(project) {
                guard await Versions.save(project, message: "Updated from a shared file") else {
                    let iconBack = await putBack()
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
        }
    }

    /// An update that didn't happen, in the chat: the app is untouched or was put back, whatever the cause.
    private static let updateFailed = "Lamp couldn't update this app. It's just as it was."
    private static let updateChangedIcon = " Only its icon may have changed."

    private func finishImport(_ package: Sharing.Package) {
        defer { try? FileManager.default.removeItem(at: package.folder) }
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
            NSAlert(error: error).runModal()
            return
        }

        reload()
        showChat(project.id)
        log(project, .status, "Imported from a shared file. Building it now…")
        Task {
            _ = await Versions.git("git init -q && git add -A && \(Self.commit) -qm 'Imported from a shared file'",
                                cwd: project.dir) { _ in }
            await run(project)
        }
    }

    /// Sends a message, or queues it while the app is busy. Everything queued goes out together
    /// as the next turn, so several quick follow-ups cost one agent run and one rebuild.
    func send(_ prompt: String, attachments: [URL] = [], pointed: PointedAt? = nil, answering card: UUID? = nil, to project: LampProject) {
        // Waiting for setup can outlast this run, and the files may be temporary (a pasted screenshot):
        // keep copies, so the request still has them after a relaunch. What was pointed at goes as a plain
        // picture then, since waiting requests are kept as words and files.
        var attachments = attachments, pointed = pointed
        if !setup.ready, let picture = pointed?.url {
            attachments.append(picture)
            pointed = nil
        }
        let files = setup.ready ? attachments : keepForLater(attachments)
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
        let waiting = setup.ready ? [:] : queued.filter { !$0.value.isEmpty }.mapValues { messages in
            messages.map(\.saved)
        }
        if waiting.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.waitingKey)
        } else {
            UserDefaults.standard.set(waiting, forKey: Self.waitingKey)
        }
    }

    /// Brings back requests that were waiting for setup when Lamp last quit. Kept files no waiting request
    /// needs any more (its build has started, or it was taken back) are cleared out.
    private func restoreWaiting() {
        var kept = Set<String>()
        if let waiting = UserDefaults.standard.dictionary(forKey: Self.waitingKey) as? [String: [[String: Any]]] {
            for (id, messages) in waiting where projects.contains(where: { $0.id == id }) {
                queued[id] = messages.map { message in
                    let files = (message["attachments"] as? [String] ?? []).filter { FileManager.default.fileExists(atPath: $0) }
                    kept.formUnion(files.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path })
                    return QueuedMessage(saved: message, attachments: files.map(URL.init(fileURLWithPath:)))
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

    /// The first message bootstraps the app: it names an untitled app, then designs the icon
    /// while the agent builds the first version. Returns the app as it is now.
    private func bootstrap(_ project: LampProject, brief: String) async -> LampProject {
        var project = project
        // A draft named before its first request (in its intro) is still asked about, for what it runs on.
        if project.untitled || !project.scaffolded {
            let suggestion = await AppName.suggest(for: brief)
            progress[project.id]?.sketch = suggestion?.sketch ?? []
            progress[project.id]?.naming = false
            if let suggestion, let kind = suggestion.kind {
                project = await chooseKind(project, kind, said: suggestion.kindSaid, watch: suggestion.watch)
            }
            if project.untitled, let name = suggestion?.name { project = await performRename(project, to: name) }
        }
        if Icons.load(project) == nil {
            let designing = project
            iconDesigns[project.id] = Task {
                let spec = await Icons.design(for: designing, brief: brief)
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

    private func startQueued(_ project: LampProject) {
        guard setup.ready, let messages = queued[project.id], !messages.isEmpty,
              let owner = begin(project) else { return }
        queued[project.id] = nil
        // A wish being found isn't named by its opening request or by answers to the agent's cards: the wish
        // the agent writes into the box (or one of the person's own) names it when it's sent.
        let spoken = (logs[project.id] ?? []).contains { $0.kind == .user }
        let names = project.finding ? spoken && project.untitled && !messages.contains { $0.card != nil } : !spoken
        let first = names
        let stillFinding = project.finding && !names
        // Still a new app until a request has made its first version: after the agent only asked questions,
        // the answers start the build and get the build card. An imported app has already been built. Not
        // while a wish is being found: there's nothing to build yet.
        let newApp = Template.isScaffold(project) && !hasVersions(project) && (!project.finding || names)
        progress[project.id] = TurnProgress(newApp: newApp)
        // Only the first message names the app (bootstrap). A later one, after the agent only asked questions,
        // finds it untitled if that naming failed, and mustn't show a naming that isn't happening.
        progress[project.id]?.naming = first && project.untitled
        let kind = Analytics.kind(AppKind(project))
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
                // A new app's card stays, showing the result; a later turn's activity line goes away. So does a
                // new app's card when the agent only asked questions: nothing was built, and the answers bring it back.
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
                    // The agent asked through its card: the app's card stays where it is while the person
                    // answers, so the build that follows starts on it and nothing in the chat moves.
                    progress[project.id]?.wait()
                } else {
                    progress[project.id] = nil
                }
                if selection != project.id || !NSApp.isActive { unread.insert(project.id) }
                // Messages queued meanwhile start the next turn straight away; tell the user once it's all done.
                if !owner.stopped, !result.watched, (queued[project.id] ?? []).isEmpty { notify(project, after: result.end) }
                finish(project)
            }
            // Named now, so the scaffold is written under its name. If it can't be, the turn ends here, failed.
            // Not while a wish is still being found: the agent only asks, and the wish it finds may be for the
            // iPhone, which a scaffold already written as a Mac app would rule out.
            if !stillFinding {
                guard let ready = await materialize(project) else { return }
                project = ready
            }
            // Where the app is as the turn starts, so the request can be changed and sent again from here.
            if let head = await Versions.head(project) { mark(asked, sentFrom: head, in: project) }
            result = await turn(messages, attachments: saved, asked: asked, on: project)
            worked = result.end != .failed
        }
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
        endApprovals(for: project)   // a card nobody can answer any more, from a request that raced the agent's end
        // Artwork that arrived during the turn, for an icon that was installed without it: applied now, still
        // owning the app, so nothing else builds or installs meanwhile. With more work queued, the next
        // install picks the artwork up itself.
        if pendingIconArt.contains(project.id), (queued[project.id] ?? []).isEmpty,
           let spec = Icons.load(project), artApplied[project.id] != spec {
            pendingIconArt.remove(project.id)
            Task {
                await applyIconArt(project, spec: spec)
                release(project)
                offerHeldDrawing(project)
                startQueued(project)
                installHeldIcons(for: [project.id])
            }
            return
        }
        release(project)
        offerHeldDrawing(project)
        startQueued(project)
        refreshUndoOffer(project)
        // An icon that was waiting for the app to close, when the app closed while this had it: the moment
        // it closed came and went with the app taken, so it's looked at again now the app is free.
        installHeldIcons(for: [project.id])
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
        let executable = project.builtURL.appendingPathComponent("Contents/MacOS/\(project.exe)")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { return }
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
        return NSWorkspace.shared.runningApplications.filter { app in
            !app.isTerminated && (app.bundleIdentifier == project.bundleID
                || app.bundleURL?.standardizedFileURL.resolvingSymlinksInPath() == place)
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
        guard heldInstalls.mayInstall(project.id, running: isRunning(project)) else { return false }
        do {
            try await deploy(project)
            // A build that waited for the app to close goes in the same way, and is the app's stamp from now on.
            if Runtime.holdsBuild(project) {
                Runtime.releaseBuild(project)
                stamps[project.id] = BuildStamp.read(project.installedURL)
            }
        } catch {}
        if watching { await watchWidget(of: project) }
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
            return !project.onIOS && !isRunning(project) && FileManager.default.fileExists(atPath: project.builtURL.path)
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

    /// One turn of the loop: agent edits → build (agent fixes failures) → commit → relaunch.
    /// `asked` are the chat lines of the requests, which are linked to the version the turn makes.
    private func turn(_ messages: [QueuedMessage], attachments saved: [String], asked: [UUID],
                      on started: LampProject) async -> TurnResult {
        // The agent may change what the app is made for (`make_app_for`) while it works: after each of its runs,
        // the rest of the turn goes on with the app as Lamp now has it, so its build is for the new kind.
        var project = started
        guard let owner = turns[project.id] else { return TurnResult(end: .failed, watched: true) }
        var prompt = messages.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n")
        // Attachments with no words: usually a screenshot or mockup meaning "like this", or a file to use.
        if prompt.isEmpty {
            prompt = """
            The user sent only the attached file\(saved.count == 1 ? "" : "s"), with no message. Work out what \
            they most likely want from it: a screenshot or mockup usually means "make the app look or work like \
            this" (or, if it shows this app, "fix what's wrong here"); a document or data file usually means \
            "use this in the app". If it's clear, do it. If it could mean several different things, ask one \
            short question instead of guessing.
            """
        }

        let files = Attachments.inline(saved, in: project).map { "\(Attachments.folder)/\($0)" }
        // After a request is sent again the build on disk is still of the code that was just taken back, so
        // its picture and its crashes say nothing about the files the agent has now.
        let sentAgain = messages.contains { $0.replaces != nil || !$0.tookBack.isEmpty }
        let pointed = asked.compactMap { id in logs[project.id]?.first { $0.id == id }?.pointed }
        let notes = Attachments.note(for: saved) + PointedAt.note(for: pointed) + Versions.note(for: project)
            + (sentAgain ? "" : Runtime.crashNote(for: project) + Runtime.screenshotNote(for: project))
        turns[project.id]?.request = prompt
        let ran = await runAgent(prompt + notes, files: files, on: project)
        project = current(project) ?? project
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
        // Still finding the wish: there's no app yet to build or save, whatever the agent did.
        if project.finding {
            return TurnResult(end: .replied, watched: isWatching(project.id))
        }
        // A new app the agent didn't touch: it only replied (say, with questions about a vague request).
        // There's nothing worth building or opening yet; the answers start the first build.
        if !hasVersions(project), await !agentChangedFiles(project) {
            return TurnResult(end: .replied, watched: isWatching(project.id))
        }
        // Only build when something changed: not after a question, and not again when the agent's last
        // look already built and opened exactly this code.
        try? Template.writeSupport(for: project)
        let changed = Runtime.sourcesChanged(project)
        if changed {
            guard await buildFixingErrors(project) else {
                return TurnResult(end: owner.asked ? .replied : .failed, watched: isWatching(project.id))
            }
            project = current(project) ?? project   // a fix may have changed what it's made for
        }
        // Opening the app brings it in front of Lamp, so whether the user was watching is decided first.
        let watched = isWatching(project.id)
        // Nothing is committed when the agent changed no files.
        let label = messages.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n\n").nilIfEmpty
            ?? Self.label(attachments: saved)
        let saving = await Versions.commitAll("-qm \"$LAMP_PROMPT\"", in: project.dir, env: ["LAMP_PROMPT": label])
        var committed = saving == .saved
        // Said once the turn's last save is known: a fix for a crash on launch saves again, and may get through.
        var unsaved = saving == .failed
        let edited = changed || committed
        var crash: String?
        if changed {
            crash = await install(project)
        } else if let look = turns[project.id]?.look, look.installed {
            crash = look.crash
            if crash == nil {
                if let app = macCopies(of: project).first {
                    // The look opened it behind the user's windows. Now it's theirs: it shows itself, as when it's
                    // opened again. An app that lives in the menu bar opens its panel (see LampWindows).
                    DistributedNotificationCenter.default().postNotificationName(
                        Notification.Name(Edition.notificationPrefix + "showWindow"), object: project.bundleID, userInfo: nil, deliverImmediately: true)
                    app.activate()
                    log(project, .status, "\(project.name) is ready")
                } else {
                    crash = await install(project)
                }
            }
        }
        // Like build errors, a crash on launch goes back to the agent. The fix joins this turn's commit,
        // so Undo still reverts the whole change.
        for _ in 0..<2 where crash != nil {
            log(project, .status, "Fixing the crash…")
            guard await runAgent("The app builds, but it quit right after launching. Find the cause and fix it.\n\n\(crash!)",
                                 on: project) else { return TurnResult(end: .failed, watched: watched) }
            project = current(project) ?? project
            // It asked instead of fixing: the turn waits for the answer here, as it does after any question.
            if owner.asked { return TurnResult(end: .replied, watched: watched) }
            guard await buildFixingErrors(project) else {
                return TurnResult(end: owner.asked ? .replied : .failed, watched: watched)
            }
            project = current(project) ?? project
            let commit = committed ? "-q --amend --no-edit" : "-qm 'Fix a crash on launch'"
            switch await Versions.commitAll(commit, in: project.dir) {
            case .saved: (committed, unsaved) = (true, false)
            case .failed: unsaved = true
            case .nothingToSave: break
            }
            crash = await install(project)
        }
        // The change is in the app either way. Without a version of its own it can't be gone back to by
        // itself, and the person should know that rather than find it out from Undo.
        if unsaved { log(project, .error, ErrorMessages.versionNotSaved) }
        if crash != nil {
            log(project, .error, ErrorMessages.quitsAfterLaunch(project.name))
        }
        // After the crash fixes, which amend the commit, so the name and the links stay on the version that's kept.
        if committed || turns[project.id]?.pendingName != nil, let head = await Versions.head(project) {
            if let name = turns[project.id]?.pendingName {
                turns[project.id]?.pendingName = nil
                await Versions.name(project, head, name)
            }
            if committed {
                link(asked, to: head, in: project)
                // Not of a copy the person kept open: it's the version before this one.
                if crash == nil, !owner.keptOpen { keepPicture(of: project, version: head) }
                titleVersions(project, limit: 1)
            }
            versionsRevision += 1
        }
        let failed = crash != nil || owner.stopped || owner.phoneReady == false
        // Not over an app that couldn't be put in place or opened either: that isn't a failed turn, but the
        // card would say it's ready next to the line saying it didn't open.
        if !failed, edited, !owner.didNotOpen, var result = owner.pendingResult {
            result.version = await Versions.head(project)
            // The card is the word that it's ready: the line saying so just above it would say it twice.
            if let last = logs[project.id]?.last, last.kind == .status, last.text == "\(project.name) is ready" {
                logs[project.id]?.removeLast()
            }
            logs[project.id, default: []].append(LogLine(kind: .result, text: result.text, result: result))
            saveChat(project)
        }
        return TurnResult(end: failed ? .failed : edited ? .changed : .replied, watched: watched)
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
        var project = current(started) ?? started
        var errors = await build(project)
        // The person's Apple account, not the code: build has said so, and the agent has nothing to fix.
        func isTheAccount() -> Bool { errors != nil && errors == macMembershipProblem(project) }
        for _ in 0..<3 where errors != nil && !isTheAccount() {
            // A build the user stopped (or whose app they deleted) isn't a problem for the agent to fix.
            guard turns[project.id]?.stopped != true, exists(project) else { return false }
            log(project, .status, "Fixing a problem…")
            guard await runAgent("The app failed to build. Fix these compiler errors:\n\n\(errors!)",
                                 on: project) else { return false }
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
    private func runAgent(_ prompt: String, files: [String] = [], on project: LampProject) async -> Bool {
        try? Template.writeSupport(for: project)
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
        // One turn can run the agent several times (fixing build errors, a crash on launch): each run's summary
        // shows only the pictures painted during it.
        let artBefore = turn.artCost
        turn.stopped = false
        let sessionFile = Self.sessionFile(for: project, engine: engine)
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
        // A conversation the copy of the engine Lamp runs can't resume (one kept by the other copy, Lamp's or
        // the person's, not found to bring over) is forgotten, and the request starts a new one rather than failing.
        var session = engine == .pi ? Self.piSession(for: project) : Self.savedSession(sessionFile)
        if engine != .pi, let saved = session, !EngineInstall.carryOver(session: saved, for: engine) {
            try? FileManager.default.removeItem(at: sessionFile)
            session = nil
        }
        let run = Agent.run(prompt: prompt, files: files, project: project, offered: offers(in: project),
                            session: session, token: turn.agentToken)
        let status = await Shell.run(run.command, cwd: project.dir, env: run.env,
                                     started: { turn.agent = $0 }) { [weak self] line in
            guard let self else { return }
            for event in Agent.parseLine(line) {
                if case .raw = event {} else if case .failed = event {} else { answered = true }
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
                    let written = turn.writing?.line
                    turn.writing = nil
                    if let line = written, let index = logs[project.id]?.lastIndex(where: { $0.id == line }) {
                        logs[project.id]?[index].text = text
                        saveChat(project)
                    } else {
                        log(project, .agent, text)
                    }
                case .step(let tool):
                    if !tool.isEmpty { endOnQuestions(turn, before: tool) }
                    streamingTool = tool
                    streamingArguments = ""
                    note(TurnProgress.activity(tool: tool, partialArguments: ""), for: project)
                case .stepArgs(let piece):
                    // The file name is among the first arguments; the rest is the file itself.
                    guard streamingArguments.count < 600 else { break }
                    streamingArguments += piece
                    let call = TurnProgress.call(tool: streamingTool, partialArguments: streamingArguments)
                    note(TurnProgress.activity(for: call), file: TurnProgress.file(changedBy: call), for: project)
                case .plan(let parts):
                    progress[project.id]?.plan = parts
                    progress[project.id]?.tickWrittenParts()
                case .compacted:
                    Memory.compacted(project)
                    AIStatus.compacted(project)
                    Skills.compacted(project)
                case .tool(let text, let fullCall):
                    log(project, .tool, text)
                    let call = ToolCall(text)
                    endOnQuestions(turn, before: call.name)
                    note(TurnProgress.activity(for: call), file: TurnProgress.file(changedBy: call), for: project)
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
                case .cost(let amount): cost += amount
                case .failed(let text):
                    if engine == .pi, Agent.isRequestTooLarge(text), failure.map(Agent.isRequestTooLarge) != true {
                        log(project, .status, Agent.droppingPictures)
                    }
                    failure = text
                case .raw(let text): log(project, .detail, text)
                case .session(let id):
                    if engine == .claude { turn.claudeSession = id }
                    if engine != .pi {
                        try? id.write(to: sessionFile, atomically: true, encoding: .utf8)
                        Memory.delivered(to: project, session: id)
                        AIStatus.delivered(to: project, session: id)
                        Skills.delivered(to: project, session: id)
                    }
                }
            }
        }
        turn.agent = nil
        if answered { Memory.delivered(to: project); AIStatus.delivered(to: project); Skills.delivered(to: project) }
        endApprovals(for: project)
        // A message cut short (the run was stopped, or failed) keeps what was written of it.
        showWritten(for: project)
        turn.writing = nil
        // Pictures are already in the app's building cost (recordArt); the summary shows them with the rest.
        log(project, .summary, LogLine.workSummary(seconds: Date().timeIntervalSince(started), cost: cost + turn.artCost - artBefore))
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
            log(project, .status, "Claude Code's auto mode isn't available, so Lamp will ask before every command.")
            return await runAgent(prompt, files: files, on: project)
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

    /// Asking ends the turn. The tool says so, and an agent that goes on to another step anyway (it has been
    /// seen to ask and then build the app without waiting) is ended here, the way a runaway one is: what it
    /// would build is a guess at the answer, under a card the person hasn't answered yet.
    private func endOnQuestions(_ turn: Turn, before tool: String) {
        guard turn.asked, !turn.endedOnQuestions, ToolCall(tool).action != .ask, let process = turn.agent else { return }
        turn.endedOnQuestions = true
        Subprocess.terminateTree(process)
    }

    /// Ends the engine's conversation for an app: the next request starts a new one, and is told what every
    /// new conversation is told.
    private static func forgetConversation(of project: LampProject, engine: Engine) {
        let file = engine == .pi ? project.dir.appendingPathComponent(".lamp/pi-session") : sessionFile(for: project, engine: engine)
        try? FileManager.default.removeItem(at: file)
        Memory.compacted(project)
        AIStatus.compacted(project)
        Skills.compacted(project)
    }

    /// One pi conversation per app, so the agent remembers earlier requests, including ones that were undone.
    private static func piSession(for project: LampProject) -> String {
        let url = project.dir.appendingPathComponent(".lamp/pi-session")
        if let id = (try? String(contentsOf: url, encoding: .utf8))?.trimmed, !id.isEmpty { return id }
        let id = "lamp-" + UUID().uuidString.lowercased()
        try? id.write(to: url, atomically: true, encoding: .utf8)
        return id
    }

    /// External engines report their own conversation ids; Lamp keeps one per engine per app.
    private static func sessionFile(for project: LampProject, engine: Engine) -> URL {
        project.dir.appendingPathComponent(".lamp/session-\(engine.rawValue)")
    }

    private static func savedSession(_ url: URL) -> String? {
        (try? String(contentsOf: url, encoding: .utf8))?.trimmed.nilIfEmpty
    }

    /// Deletes an app: quits it, stops its agent, and moves its source and built app to the Trash.
    func delete(_ project: LampProject) async {
        stop(project)
        iconDesigns.removeValue(forKey: project.id)?.cancel()
        guard await quit(project) else {
            log(project, .status, ErrorMessages.notDeleted(project.name))
            return
        }
        stop(project)   // anything begun while the app was asking about unsaved work
        // Its widget's process too: in the Trash it would go on running, and answer for an app made later
        // under the same name.
        await WidgetProcess.end(for: project)
        let fm = FileManager.default
        if fm.fileExists(atPath: project.installedURL.path) {
            try? fm.trashItem(at: project.installedURL, resultingItemURL: nil)
        }
        do {
            try fm.trashItem(at: project.dir, resultingItemURL: nil)
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        Self.trashData(of: project)
        // Its sign-ins too: an app made later under the same name is another app, and starts disconnected.
        AppSecrets.forget(app: project.instance)
        projects.removeAll { $0.id == project.id }
        logs[project.id] = nil
        usage[project.id] = nil
        queued[project.id] = nil
        icons[project.id] = nil
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

    /// The latest request per app, so the decision model can judge commands against what the user asked for.

    /// Applies Settings → Building → "Ask before running commands" to one command.
    /// `sandboxed`: the command will run confined to the app (Sandbox), so where it looks isn't in question.
    private func approveCommand(_ command: String, for project: LampProject, escalated: Bool, shell: Bool = true, sandboxed: Bool) async -> Bool {
        switch CommandApproval.current {
        case .never:
            log(project, .status, "Ran: \(command)")
            return true
        case .risky where !escalated:
            let judgment = await commandJudgment(command, for: project)
            // A command the sandbox confines can only change the app's own folder (Sandbox), so only one the
            // checks find risky asks: one they're merely unsure of, or that doesn't seem to match the request
            // (looking for the app's process while fixing it), runs. Asking about those was most of the cards,
            // nearly all of them allowed. A check that couldn't be made at all still asks: the sandbox leaves the
            // network open, so it isn't the only guard.
            if judgment.verdict == .run || (sandboxed && judgment.verdict == .unsure && judgment.judged) {
                log(project, .status, "Ran: \(command)")
                return true
            }
            // A risky verdict always has its reason; if one were ever missing, the card still comes up as flagged.
            let flagged = judgment.verdict == .risky ? judgment.reason ?? .reachesBeyond : nil
            return await requestApproval(for: project, command: command, shell: shell, sandboxed: sandboxed, flagged: flagged)
        default:
            return await requestApproval(for: project, command: command, shell: shell, sandboxed: sandboxed)
        }
    }

    /// Whether a command is plainly fine, for every engine: the decision model's answers (CommandRisk),
    /// against the user's request. No decision model available → not plainly fine.
    private func commandJudgment(_ command: String, for project: LampProject) async -> CommandRisk.Judgment {
        await CommandRisk.judge(command: command, request: turns[project.id]?.request ?? "", folder: project.dir.path) { state, questions in
            try await AppAI.decide(state: state, questions: questions).0
        }
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
                                 building: "\(AppKind(project).phrase) called \"\(project.name)\"") { prompt, system in
            try await AppAI.complete(prompt: prompt, images: [], system: system, json: true).0
        }
    }

    /// Waits for the user to allow or deny a shell command. One request per app at a time; others queue.
    /// There's no timeout: commands wait until the user answers, stops the turn, or the turn ends.
    /// `flagged`: the check that found the command risky; the card gives that check's reason rather than
    /// call it low risk. The in-app model's rating is words for the card and never runs a command.
    func requestApproval(for project: LampProject, command: String, title: String? = nil,
                         explanation given: CommandExplanation? = nil, shell: Bool = true, sandboxed: Bool = false,
                         flagged: CommandRisk.Reason? = nil) async -> Bool {
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
        NSApp.requestUserAttention(.informationalRequest)
        note(title == nil ? "Waiting for your OK to run a command" : "Waiting for your OK", for: project)
        return await withCheckedContinuation { continuation in
            var pending = PendingApproval(command: command, answer: continuation, explanation: given?.raised(for: flagged))
            if let title { pending.title = title }
            approvals[project.id] = pending
            // Explain it while the card is up; until this arrives the card says it's working it out.
            if given == nil { Task {
                let explanation = await explain(command, for: project, sandboxed: sandboxed)?.raised(for: flagged) ?? .unexplained(flagged: flagged)
                if approvals[project.id]?.id == pending.id { approvals[project.id]?.explanation = explanation }
            } }
        }
    }

    func answerApproval(for project: LampProject, allow: Bool, allowAll: Bool = false) {
        guard let pending = approvals.removeValue(forKey: project.id) else { return }
        if allowAll { turns[project.id]?.allowAll = true }
        log(project, .detail, (allow ? "Allowed: " : "Denied: ") + pending.command)
        note(allow && pending.title == PendingApproval.commandTitle ? "Running a command" : "Thinking", for: project)
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
        turn.cancel()
    }

    /// Opens the installed app, or brings it to the front if it's running. Only builds when there's
    /// nothing installed yet (or the installed copy was deleted).
    func open(_ project: LampProject) async {
        if project.onIOS {
            // Running already: bring the simulator forward. Otherwise build (if needed) and launch.
            let toSimulator = project.device == nil
            if toSimulator, let running = simulatorApps[project.id], Simulator.isRunning(pid: running.pid), simulatorLeases[running.udid] == project.id { await Simulator.show(running.udid); return }
            // An app for both reuses a build only when it was made for this place from this code (the
            // place is part of the fingerprint), else it's built again.
            if FileManager.default.fileExists(atPath: project.builtURL.path), stamps[project.id]?.isOutdated != true,
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
        if stamps[project.id]?.isOutdated == true, !busy.contains(project.id),
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
        guard turns[project.id]?.agent != nil else { return (409, ["error": "Lamp isn't working on this app right now."]) }
        guard let request = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let actions = request["actions"] as? [[String: Any]], !actions.isEmpty,
              let json = (try? JSONSerialization.data(withJSONObject: actions)).map({ String(decoding: $0, as: UTF8.self) }) else {
            return (400, ["error": "use_app needs a list of actions."])
        }
        if request["sidebar"] as? Bool == true {
            guard BrowserBridge.enabled, project.platform.hasMac, !project.onIOS else { return (200, ["text": Self.noSidebar]) }
            guard !macCopies(of: project).isEmpty else {
                return (200, ["text": "The app isn't open. Call look_at_app with sidebar first: it builds the app and opens it."])
            }
            return await BrowserPreview.use(project, actions: actions, page: request["page"] as? String, selection: request["selection"] as? String)
        }
        if project.onIOS { return await useOnSimulator(project, actions: actions, json: json) }
        // Not in the copy the person kept open: what it holds is theirs, and it isn't the agent's change.
        if Runtime.holdsBuild(project), isRunning(project) { return (409, ["error": Self.keptOpenNote]) }
        guard let app = macCopies(of: project).first else {
            return (200, ["text": "The app isn't open. Call look_at_app first: it builds the app and opens it."])
        }
        guard Self.binary(of: project, contains: "lampUseAppSignature") else {
            return (200, ["text": "The open app was built before use_app could do this. Call look_at_app to rebuild it, then try again."])
        }
        let readsScreen = Self.binary(of: project, contains: Self.screenTextMarker)
        if !readsScreen, actions.contains(where: { ($0["target"] as? String)?.isEmpty == false }) {
            return (200, ["text": "The open app was built before use_app could act on things by name. Call look_at_app to rebuild it, then try again."])
        }
        let id = UUID().uuidString
        let printed = Runtime.logSize(project)
        let asked = Date()
        // Signed with the app's token rather than carrying it: distributed notifications reach every process.
        let key = SymmetricKey(data: Data(Template.token(for: project).utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data("\(id)\n\(json)".utf8), using: key)
            .map { String(format: "%02x", $0) }.joined()
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(Edition.notificationPrefix + "useApp.\(project.id)"), object: nil,
            userInfo: ["actions": json, "id": id, "lampUseAppSignature": signature], deliverImmediately: true)
        // Waits, and keys held down (a Mac app's `key` with `amount`), each up to 10 seconds, as the app takes them.
        let waits = actions.reduce(0.0) { total, action in
            switch action["action"] as? String {
            case "wait": total + min(action["amount"] as? Double ?? 1, 10)
            case "key": total + min(max(action["amount"] as? Double ?? 0, 0), 10)
            default: total
            }
        }
        let wait = Double(actions.count) * 0.4 + waits + 5
        guard let report = await Runtime.useReport(of: project, id: id, waiting: wait, while: { !app.isTerminated }) else {
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
        text += Privacy.sharesPictures
            ? "\n\nPictures of its windows follow, frontmost first. The screen as text is the first picture's, and x and y for the next use_app are pixels in it."
            : "\n\n" + Privacy.picturesOff
        if !Privacy.sharesLog { text += " " + Privacy.logOff }
        if Privacy.sharesLog, let lines = Runtime.log(of: project, from: printed) { text += "\n\nWhat it printed meanwhile:\n\(lines)" }
        return (200, ["text": text, "screenshots": Self.agentPictures(Runtime.pictures(of: project), in: project)])
    }

    /// `look_at_app` with `sidebar`: the app is built and opened as for any look, then its sidebar in Chrome is
    /// drawn by Lamp (BrowserPreview) in place of its windows, beside the page the agent names.
    private func lookAtSidebar(_ project: LampProject, page: String?) async -> (Int, [String: Any]) {
        guard BrowserBridge.enabled, project.platform.hasMac, !project.onIOS else { return (200, ["text": Self.noSidebar]) }
        let window = await look(at: project)
        guard window.0 == 200, !macCopies(of: project).isEmpty else { return window }
        return await BrowserPreview.look(project, page: page)
    }
    private static let noSidebar = "Only a Mac app has a sidebar in Chrome, and only while Apps in Chrome is on in Lamp's Settings → Experimental."

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
        let report = await Simulator.Driver.perform(decoded, on: screen, picture: picture) { [weak self] in
            guard let self, exists(project), turns[project.id] === owner, !owner.stopped else { return false }
            // Still this app's screen: it's running, the device is still leased to this project (a launch by
            // another project takes the lease before anything else), and no other app of Lamp's is running there.
            guard simulatorLeases[running.udid] == project.id, simulatorApps[project.id]?.pid == running.pid, Simulator.isRunning(pid: running.pid) else { return false }
            return !simulatorApps.contains { $0.key != project.id && $0.value.udid == running.udid && Simulator.isRunning(pid: $0.value.pid) }
        }
        if let data = try? JSONSerialization.data(withJSONObject: ["id": UUID().uuidString, "report": report]) {
            try? data.write(to: Runtime.folder(project).appendingPathComponent("use.json"))
        }
        guard Simulator.isRunning(pid: running.pid) else {
            var text = "What happened:\n\(report)\n\nThe app quit or crashed while doing that."
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
                (status, answer) = arguments["sidebar"] as? Bool == true
                    ? await lookAtSidebar(project, page: arguments["page"] as? String)
                    : await look(at: project, prop: arguments["prop"] as? String, motion: arguments["motion"] as? Bool ?? false)
            case "use_app":
                let actions = (try? JSONSerialization.data(withJSONObject: arguments)) ?? Data("{}".utf8)
                (status, answer) = await use(project, request: actions)
            case "plan":
                // pi's plan reaches the build card through its event stream (Agent.parseLine); here it's set directly.
                let parts = (arguments["parts"] as? [[String: Any]] ?? []).enumerated().compactMap { index, part in
                    (part["title"] as? String).map {
                        PlanPart(id: index, title: $0, done: part["done"] as? Bool ?? false,
                                 files: (part["files"] as? [String] ?? []).map { ($0 as NSString).lastPathComponent })
                    }
                }
                progress[project.id]?.plan = parts
                progress[project.id]?.tickWrittenParts()
                (status, answer) = (200, ["text": "The user can see the plan."])
            case "delete_file":
                (status, answer) = Self.deleteFile(arguments["path"] as? String ?? "", in: project)
            case "list_versions": (status, answer) = await versions("", [:], of: project)
            case "name_version": (status, answer) = await versions("/name", arguments, of: project)
            case "restore_version": (status, answer) = await versions("/restore", arguments, of: project)
            case "read_notes", "save_notes": (status, answer) = notes(name, arguments, for: project)
            case "read_skill": (status, answer) = Skills.read(arguments)
            case "make_art": (status, answer) = await makeArt(arguments, for: project)
            case "offer_setup": (status, answer) = agentOffer(arguments, for: project)
            case "make_app_for": (status, answer) = await agentKind(arguments, for: project)
            case "connectors": (status, answer) = Connectors.answer(arguments, for: project)
            case "ask", "show_result", "write_wish": (status, answer) = talk(name, arguments, for: project)
            default:
                return (200, ["jsonrpc": "2.0", "id": id, "error": ["code": -32602, "message": "Unknown tool \(name)."]])
            }
            if status != 200 {
                return reply(["content": [["type": "text", "text": answer["error"] as? String ?? "Lamp couldn't do that."]], "isError": true])
            }
            var content: [[String: Any]] = [["type": "text", "text": answer["text"] as? String ?? ""]]
            for path in answer["screenshots"] as? [String] ?? [] {
                if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                    content.append(["type": "image", "data": data.base64EncodedString(), "mimeType": Previews.mimeType(of: path)])
                }
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
        let root = project.dir.resolvingSymlinksInPath().standardizedFileURL
        let target = URL(fileURLWithPath: path, relativeTo: project.dir).standardizedFileURL
        let relative = target.path.hasPrefix(root.path + "/") || target.path.hasPrefix(project.dir.path + "/")
            ? String(target.path.dropFirst((target.path.hasPrefix(root.path + "/") ? root.path : project.dir.path).count + 1)) : ""
        guard !relative.isEmpty else { return (400, ["error": "Only files inside the app's folder can be deleted."]) }
        // Compared without regard to case: the Mac's usual file system treats "package.swift" as the same file.
        let protected = [".lamp", ".git", ".build", "build", ".gitignore", "Package.swift", "build.sh", "Sources/LampSupport.swift", Template.sceneSupportPath,
                         Template.widgetFolder + "/" + Template.widgetSupportFile, Template.shareFolder + "/" + Template.shareSupportFile] + Template.watchSupportPaths
        let lowered = relative.lowercased()
        if protected.contains(where: { lowered == $0.lowercased() || lowered.hasPrefix($0.lowercased() + "/") }) {
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

    /// `ask` and `show_result`, for every engine: pi's extension posts them to `/agent/talk`, Claude Code and
    /// Codex call them over MCP.
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
                logs[project.id, default: []].append(LogLine(kind: .ask, text: ask.text, ask: ask))
                // A new app's card gives up its checklist in the same moment the questions arrive, not when
                // the turn ends a little later: once there's something to click, nothing above it moves.
                if progress[project.id]?.newApp == true { progress[project.id]?.asking = true }
                turn.asked = true
                saveChat(project)
                return (200, ["text": Talk.asked])
            }
        case "show_result":
            switch Talk.result(from: arguments) {
            case .failure(let trouble): return (400, ["error": trouble.text])
            case .success(let result):
                // Kept until the app is built and open: a card saying it's ready over a build that failed
                // would be the one thing on screen that isn't true.
                turn.pendingResult = result
                return (200, ["text": Talk.resultKept])
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
        guard var ask = line.ask, let index = logs[project.id]?.firstIndex(where: { $0.id == line.id }) else { return }
        ask.answers = answers
        logs[project.id]?[index].ask = ask
        saveChat(project)
        send(Talk.message(for: ask, answers: answers), answering: line.id, to: project)
    }

    /// After a restore, the app in Lamp's list is what the restored version was made for, as `Versions.restoreFiles`
    /// wrote it to meta.json: an Undo of `make_app_for` puts the kind back with the code.
    /// The app as it is after the restore, for whatever builds it next.
    @discardableResult
    private func followRestoredKind(_ project: LampProject) -> LampProject {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return project }
        if let kind = Template.platform(fromPackageIn: project.dir), projects[index].platform != kind {
            projects[index].platform = kind
            if !kind.hasIOS { projects[index].device = nil }
            refreshOpenApps()
        }
        return projects[index]
    }

    /// `make_app_for`: the person asked for the app on other devices, and the agent asks Lamp to make it so.
    private func agentKind(_ arguments: [String: Any], for project: LampProject) async -> (Int, [String: Any]) {
        let devices = Set(arguments["devices"] as? [String] ?? [])
        guard let kind = Platform(devices: devices) else {
            return (400, ["error": "`devices` must list one or more of mac, iphone and watch."])
        }
        // Asked before the change: once an app isn't for the iPhone, its Watch/ no longer counts as a watch app.
        let hadWatch = current(project).map(Template.hasWatch) ?? false
        let (status, answer) = await convert(project, to: kind)
        guard status == 200, let text = answer["text"] as? String, !text.hasPrefix("Not yet"), !text.hasPrefix("Nothing changed"),
              let now = current(project) else { return (status, answer) }
        // The watch app is code in Watch/, the agent's to write or take away: Lamp says which, with the rule.
        let watch = devices.contains("watch")
        if watch, !Template.hasWatch(now) {
            return (200, ["text": text + "\n\nThen add its Apple Watch app in Watch/:\n" + Agent.Rules.iPhoneWatch])
        }
        if !watch, hadWatch || Template.hasWatch(now) {
            return (200, ["text": text + "\n\nThen take its Apple Watch app away: delete the files in Watch/ with delete_file."])
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
    func convert(_ project: LampProject, to kind: Platform) async -> (Int, [String: Any]) {
        guard let current = current(project), let index = projects.firstIndex(where: { $0.id == project.id }) else {
            return (404, ["error": "Lamp can't find the app."])
        }
        let words = kind == .mac ? "the Mac" : kind == .iphone ? "iPhone and iPad" : "the Mac, iPhone and iPad"
        guard kind != current.platform else { return (200, ["text": "It's already made for \(words)."]) }
        if kind.hasIOS {
            let both = kind == .universal
            let report = await Task.detached { PhoneTools.checked(family: .iphone, phone: nil, requiresTeam: both, requiresPaidTeam: false) }.value
            if let issue = report.issue {
                PhoneSetup.shared.show()
                return (200, ["text": "Not yet: this Mac can't build it for \(words). \(issue.title): \(issue.message) Lamp opened its setup steps. " +
                              "Tell the person in a sentence, and that you'll make the change when they ask again once it's done. Change nothing else for it."])
            }
        }
        // Every copy closes first, the turn's own answer included: one kept open (the person kept unsaved work)
        // would go on as an app Lamp no longer knows by its id.
        guard await quit(current, for: turns[project.id]) else {
            return (200, ["text": "Nothing changed: the person kept \(current.name) open on this Mac, where it asked about unsaved work. " +
                          "Tell them it has to close first, and that you'll make the change when they ask again."])
        }
        var changed = current
        changed.platform = kind
        // Where it opens next: where it's newly made for, so the person sees the change.
        changed.chosen = current.platform == .mac ? .ios : .mac
        if !kind.hasIOS { changed.device = nil }
        do { try Template.saveMeta(changed) } catch { return (500, ["error": "Lamp couldn't save the change: \(error.localizedDescription)"]) }
        projects[index] = changed
        if changed.scaffolded {
            do { try Template.writeOwnedFiles(for: changed) } catch {
                return (500, ["error": "Lamp couldn't write the build files for it: \(error.localizedDescription)"])
            }
        }
        // The Mac copy's data, from an app for both built before its data had a fixed place (`LampStore.folder`):
        // moved there now, while Lamp still knows the id it was kept under.
        if current.platform.hasMac {
            let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            let fixed = support.appendingPathComponent(Edition.appBundlePrefix + current.id)
            let signed = support.appendingPathComponent(current.bundleID)
            if signed != fixed, FileManager.default.fileExists(atPath: signed.path), !FileManager.default.fileExists(atPath: fixed.path) {
                try? FileManager.default.moveItem(at: signed, to: fixed)
            }
        }
        if current.platform.hasMac, kind.hasMac, current.bundleID != changed.bundleID {
            _ = await Shell.run("defaults export \"$LAMP_OLD\" - | defaults import \"$LAMP_NEW\" -", cwd: changed.dir,
                                env: ["LAMP_OLD": current.bundleID, "LAMP_NEW": changed.bundleID]) { _ in }
        }
        syncLocalNetwork()
        log(changed, .status, "\(changed.name) is made for \(words) now.")
        let rules: String = switch kind {
        case .universal: Agent.Rules.universal + Agent.Rules.universalFrameworks + Agent.Rules.universalTry
        case .iphone: Agent.Rules.iPhoneFrameworks + Agent.Rules.iPhoneTry
        case .mac: Agent.Rules.macFrameworks
        }
        return (200, ["text": "Done: \(changed.name) is made for \(words) from now on, and that replaces what your instructions said " +
                      "about what it runs on. Adapt its code now, in this request, and build it before you finish. " +
                      (kind == .universal ? "Put what only one platform has under `#if os(macOS)` or `#if os(iOS)`. " : "") +
                      "What applies now:\n" + rules.replacingOccurrences(of: "{{DEVICE}}", with: changed.family.name)])
    }

    /// `offer_setup`: the agent asks Lamp to offer the person a way to set up a capability, with its reason.
    private func agentOffer(_ arguments: [String: Any], for project: LampProject) -> (Int, [String: Any]) {
        guard let capability = (arguments["capability"] as? String).flatMap(Capability.init(rawValue:)) else {
            return (400, ["error": "`capability` must be text, decisions, pictures or browser."])
        }
        if capability == .browser && (!BrowserBridge.enabled || !project.platform.hasMac) {
            return (400, ["error": "A sidebar in Chrome is only for a Mac app, while Apps in Chrome is on in Lamp's Settings → Experimental."])
        }
        let away = arguments["away"] as? Bool == true
        guard !away || (project.platform.hasIOS && capability != .browser) else {
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
            guard let url = artDestination(name, in: project) else {
                return (400, ["error": "Assets/\(name) can't be written: Assets or the file leads outside the app's folder."])
            }
            try png.write(to: url, options: .atomic)
            let size = NSBitmapImageRep(data: png).map { " (\($0.pixelsWide)×\($0.pixelsHigh) pixels)" } ?? ""
            let around = scene ? "" : ", transparent around the object"
            return (200, ["text": "Saved Assets/\(name)\(size)\(around). Show it with LampAssets.image(\"\(name)\"). It follows.",
                          "screenshots": [Previews.forAgent(url, in: project).path]])
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
        let root = project.dir.resolvingSymlinksInPath().standardizedFileURL
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

    /// The tools every engine gets, from Resources/lamp-tools.json: the one place their names, descriptions and
    /// schemas live. pi's extension (lamp-tools.ts) reads the same file, so the two can't drift apart.
    static let mcpTools: [[String: Any]] = {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("lamp-tools.json"),
              let data = try? Data(contentsOf: url),
              let tools = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            assertionFailure("lamp-tools.json is missing from the app")
            return []
        }
        // `label` is pi's: MCP clients see name, description and inputSchema.
        return tools.map { tool in tool.filter { $0.key != "label" } }
    }()

    /// Whether the installed app's binary contains a string, which says which Lamp features it was built with.
    private static func binary(of project: LampProject, contains marker: String) -> Bool {
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

    func run(_ project: LampProject) async {
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

    /// Goes back to the version before the current one. Like any restore, this is itself a new version.
    /// `change` is the version Undo Last Change in the chat was offered under: when the app has moved on from it
    /// since, nothing is undone, rather than a change the person wasn't looking at.
    func undo(_ project: LampProject, change: String? = nil) async {
        guard begin(project) != nil else { return }
        defer { finish(project) }
        let versions = await Versions.list(project)
        let unsaved = await Versions.hasUnsavedChanges(project)
        if let change, unsaved || versions.first?.id != change || Versions.undoTarget(in: versions)?.undoing.id != change {
            log(project, .status, "The app has changed since, so nothing was undone")
            return
        }
        // A turn that was stopped, or never got the app building, leaves its changes unsaved: Undo discards those first.
        if let current = versions.first, unsaved {
            _ = await Versions.restoreFiles(project, to: current)
            let restored = followRestoredKind(project)
            log(restored, .status, "Discarded the unfinished change")
            if await build(restored) == nil { await installReportingCrash(restored) }
            return
        }
        guard let (undoing, target) = Versions.undoTarget(in: versions),
              await Versions.restore(project, to: target, message: "Undid “\(undoing.label)”",
                                     trailer: "Lamp-Undid: \(undoing.id)") else {
            log(project, .status, "Nothing to undo")
            return
        }
        let restored = followRestoredKind(project)
        Versions.remember(restored, restoredTo: target.label, from: target.date)
        log(restored, .status, "Undid “\(undoing.label)”")
        await rebuild(restored, restoredFrom: target)
    }

    /// Brings back an earlier version's files as a new version, so the restore can be undone too.
    func restore(_ project: LampProject, to version: AppVersion) async {
        guard begin(project) != nil else { return }
        defer { finish(project) }
        guard await Versions.restore(project, to: version, message: Versions.restoredMessage(to: version)) else {
            log(project, .status, "The app is already like “\(version.label)”")
            return
        }
        let restored = followRestoredKind(project)
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
        let versions = await Versions.list(project)
        // Requests from before Lamp noted where they were sent from: the version one made follows that point.
        let start = line.before ?? line.version.flatMap { id in versions.first { $0.id == id }?.parent }
        guard let target = start.flatMap({ id in versions.first { $0.id == id } }),
              await Versions.restoreFiles(project, to: target),
              let chat = logs[project.id], let index = chat.firstIndex(where: { $0.id == line.id }) else {
            log(project, .error, ErrorMessages.restoreFailed)
            return false
        }
        followRestoredKind(project)
        if await Versions.save(project, message: Versions.restoredMessage(to: target)), let head = await Versions.head(project) {
            Versions.copyPicture(in: project, from: target.id, to: head)
            versionsRevision += 1
        }
        // Requests that went out together made one change, so the ones just before this one go out with it again.
        var first = index
        while first > chat.startIndex, chat[first - 1].kind == .user { first -= 1 }
        // They keep what they had taken back themselves: it's the chat's only record of it.
        var again = chat[first..<index].map {
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
        progress[project.id] = nil   // a new app's build card belongs to the request that's gone
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
    private func build(_ project: LampProject) async -> String? {
        guard exists(project) else { return "The app was deleted." }
        log(project, .status, "Building…")
        // Lamp's own files first, and no build without them: the build runs build.sh and Package.swift.
        do {
            try Template.writeOwnedFiles(for: project)
        } catch {
            let problem = "Lamp couldn't write the app's build files: \(error.localizedDescription)"
            log(project, .error, problem)
            return problem
        }
        // Taken before the build, so an edit made while it runs still counts as a change afterwards.
        let fingerprint = Runtime.fingerprint(project)
        var output: [String] = []
        // An app for both is built for where Try On points; its Mac build is Xcode's, signed for the team.
        let universal = project.platform == .universal
        if universal, !project.onIOS, Devices.team.isEmpty {
            let problem = "The Mac build of an app for both is signed for your Apple team, and none is chosen yet. Choose it in Settings → Building, then try again."
            log(project, .error, problem)
            return problem
        }
        // Xcode would get as far as signing and fail there: said first, in the person's words, and once for
        // a request, however many times the request tries to build.
        if let problem = macMembershipProblem(project) {
            let said = (logs[project.id] ?? []).reversed().prefix { $0.kind != .user }.contains { $0.kind == .error && $0.text == problem }
            if !said { log(project, .error, problem) }
            return problem
        }
        let command = universal ? "./build.sh \(project.onIOS ? "ios" : "mac")" : "./build.sh"
        var env: [String: String] = universal ? ["LAMP_TEAM": Devices.team] : [:]
        // The open app takes the change first, when it can (LiveReload): a few seconds, where the whole build
        // takes several more. That build goes on afterwards, for the app to be installed from when it closes.
        if await reloadBeforeBuilding(project, command: command, env: env, fingerprint: fingerprint) { return nil }
        await liveBuilds[project.id]?.value
        liveBuildFailed.remove(project.id)
        if LiveReload.eligible(project) { env["LAMP_LIVE"] = "1" }   // a change can go into the open app (LiveReload)
        let status = await Shell.run(Shell.compatibleSDK + command, cwd: project.dir, env: env,
                                     started: { [weak self] in self?.turns[project.id]?.build = $0 }) { output.append($0) }
        turns[project.id]?.build = nil
        guard exists(project) else { return "The app was deleted." }
        guard status != 0 else {
            Runtime.markBuilt(project, from: fingerprint)
            BuildStamp.write(to: project.builtURL)   // deploy signs the app afterwards
            return nil
        }
        let tail = output.suffix(40).joined(separator: "\n")
        log(project, .detail, "Build failed:\n" + tail)
        return tail
    }

    /// A new app's card that has already said how its turn ended follows what happens to the app afterwards
    /// (Play, a rebuild, opening the copy that's installed), as it does for a phone: it never goes on saying
    /// the app didn't open beside one that has, or the reverse.
    private func noteOpened(_ opened: Bool, for project: LampProject) {
        if progress[project.id]?.finished != nil { progress[project.id]?.unopened = !opened }
    }

    /// The whole builds running after a change went into the open app, by app: a build waits for the one before.
    private var liveBuilds: [String: Task<Void, Never>] = [:]
    /// Apps whose whole build after an early change failed: build/ holds the version before it, which isn't
    /// installed in its place. Cleared by the next build.
    private var liveBuildFailed: Set<String> = []
    /// Apps whose change went in before their build: the install that follows the build has nothing to do.
    private var reloadedBeforeBuild: Set<String> = []

    /// The quick path: refresh the live copy only (build.sh with LAMP_LIVE_COPY), and when the change can go in,
    /// compile just its files and put them into the open app; then build the whole app in the background, for
    /// its install when it closes. False, having changed nothing in the open app, when any of it can't be done:
    /// the build goes on the usual way, and its install decides.
    private func reloadBeforeBuilding(_ project: LampProject, command: String, env: [String: String], fingerprint: String) async -> Bool {
        reloadedBeforeBuild.remove(project.id)
        guard LiveReload.eligible(project), !macCopies(of: project).isEmpty, Self.binary(of: project, contains: "reloaded.txt") else { return false }
        await liveBuilds[project.id]?.value
        liveBuildFailed.remove(project.id)
        var copy = env
        copy["LAMP_LIVE"] = "1"
        copy["LAMP_LIVE_COPY"] = "1"
        guard await Shell.run(Shell.compatibleSDK + command, cwd: project.dir, env: copy) { _ in } == 0,
              await reloadInPlace(project, inFront: false) else { return false }
        reloadedBeforeBuild.insert(project.id)
        // Nothing to install until the whole build is done: the copy in build/ is the one before this change. Only
        // then do these sources count as built, so a Lamp quit meanwhile builds them again (`recoverUnfinishedBuild`).
        LiveReload.installed(project)
        heldInstalls.installed(project.id)
        LiveReload.startedBuilding(project)
        var full = env
        full["LAMP_LIVE"] = "1"
        liveBuilds[project.id] = Task { [weak self] in
            var output: [String] = []
            let status = await Shell.run(Shell.compatibleSDK + command, cwd: project.dir, env: full) { output.append($0) }
            guard let self else { return }
            self.liveBuilds[project.id] = nil
            LiveReload.finishedBuilding(project)
            guard let current = self.current(project) else { return }
            if status == 0 {
                Runtime.markBuilt(current, from: fingerprint)
                BuildStamp.write(to: current.builtURL)
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
    /// way (`LiveReload.reloadable`). True when it went in: the app is updated where it is, and the build is held,
    /// to be installed when the app closes. False sends the change the usual way, by reopening the app.
    private func reloadInPlace(_ project: LampProject, inFront: Bool) async -> Bool {
        // The change went in before the build (`reloadBeforeBuilding`): only the word that it did is left to say.
        // Closed since, the app is installed the usual way, from the whole build once it's done.
        if reloadedBeforeBuild.remove(project.id) != nil {
            if let app = macCopies(of: project).first {
                if inFront {
                    app.activate()
                    log(project, .status, "\(project.name) is updated")
                }
                return true
            }
            await liveBuilds[project.id]?.value
            return false
        }
        guard LiveReload.eligible(project), let app = macCopies(of: project).first,
              Self.binary(of: project, contains: "reloaded.txt") else { return false }
        let changed: [String]
        switch await LiveReload.verdict(project) {
        case .reload(let files): changed = files
        // The open app already runs these sources (a change that went in before its build): nothing to do.
        case .unchanged: return true
        case .reopen(let why):
            log(project, .detail, "Reopening \(project.name) for this change: \(why).")
            return false
        }
        note("Updating \(project.name) in place…", for: project)
        // The changed files' compile and the whole code's check go side by side; the check decides.
        async let compiled = LiveReload.compile(project, changed: changed)
        let check = await LiveReload.layoutProblem(project)
        let (library, problem) = await compiled
        if let why = check.problem {
            log(project, .detail, "Reopening \(project.name) for this change: \(why).")
            return false
        }
        guard let library, let layout = check.layout else {
            print("Live reload of \(project.name) didn't compile:\n\(problem ?? "")")
            return false
        }
        guard await LiveReload.send(library, to: project, token: Template.token(for: project)) else { return false }
        LiveReload.markRunning(project)
        LiveReload.keepLayout(layout, for: project)
        watchAfterReload(project, app: app)
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

    /// The safety net under a live change: if the app crashes within a few seconds of one going in, what it was
    /// told to run didn't suit it after all. It's opened again from the full build, which goes in as it closes
    /// (the install waiting for that), and the chat's details say so. Only a crash, which leaves macOS's report:
    /// an app quit on purpose (its Quit, Lamp's Stop) stays closed.
    private func watchAfterReload(_ project: LampProject, app: NSRunningApplication) {
        let since = Date()
        Task { [weak self] in
            for _ in 0..<16 {
                try? await Task.sleep(for: .milliseconds(500))
                guard app.isTerminated else { continue }
                // macOS writes the report a moment after the process is gone.
                var crashed = false
                for _ in 0..<10 where !crashed {
                    crashed = Runtime.crashed(project, since: since)
                    if !crashed { try? await Task.sleep(for: .milliseconds(300)) }
                }
                guard crashed, let self, let current = self.current(project) else { return }
                self.log(current, .detail, "\(current.name) stopped right after a change went in without reopening it. Opening it again with the full build.")
                LiveReload.forget(current)
                // The full build goes in as the app closes (`installHeldIcons`); then it's opened.
                for _ in 0..<60 where LiveReload.awaitsInstall(current) { try? await Task.sleep(for: .milliseconds(500)) }
                await self.open(current)
                return
            }
        }
    }

    /// Installs and opens the app. Returns what's known about the failure if it died straight away.
    /// `inFront` is false for the agent's looks, which shouldn't pull the app in front of the user mid-turn.
    private func install(_ project: LampProject, inFront: Bool = true) async -> String? {
        guard exists(project) else { return nil }
        // The turn this install belongs to, taken before the icon wait: a Stop during it can end the turn
        // and start the next one's, which must not inherit this launch.
        let owner = turns[project.id]
        await prepareIcon(project)
        if project.onIOS {
            guard let owner, turns[project.id] === owner, !owner.stopped else { return "The app was stopped before it opened." }
            // The person's own phone gets the app when they press Play or a change is finished; the agent's
            // looks (not in front) stay on the simulator, which is the only screen Lamp can see.
            let problem = if inFront, let udid = project.device {
                await installOnDevice(project, owner: owner, udid: udid)
            } else {
                await installOnSimulator(project, owner: owner, inFront: inFront)
            }
            // As for a Mac app below: the artwork asked for while the icon was designed, before there was
            // an app, is asked for again now there is one (an icon drawn by hand is only offered then).
            upgradeIconArt(project)
            // As on the Mac: the widget is built, and adding it to the home screen is the person's to do.
            // Only for a widget to add: Live Activities alone show by themselves and aren't among the widgets.
            if problem == nil, Template.hasHomeScreenWidget(project), WidgetCard.isNeeded(after: logs[project.id] ?? []) { log(project, .widget, "") }
            return problem
        }
        // A change that can go into the open app goes in there, keeping what's on screen; the build waits to be
        // installed until the app closes (LiveReload).
        if await reloadInPlace(project, inFront: inFront) { return nil }
        // A whole build after an early change may still be writing build/: what's installed is what it makes,
        // and nothing when it failed (build/ is the version before the change).
        await liveBuilds[project.id]?.value
        if liveBuildFailed.contains(project.id) {
            let problem = "\(project.name) couldn't be built as a whole after its last change, so it wasn't installed. It's built again with the next request."
            log(project, .error, problem)
            return problem
        }
        // A request's change that closes the open app and opens it again says so in the chat, once in the turn:
        // otherwise the window just goes away and comes back. Not for Open App or Undo, which ask for that.
        let reloading = owner?.request != nil && owner?.saidReloaded == false && isRunning(project)
        // Asked once in a turn: a second build in it leaves the app the person kept open alone.
        let asked = owner?.keptOpen == true && isRunning(project)
        guard !asked, await quit(project, for: owner, only: .mac) else {
            // The person kept the app open, with whatever it holds. It isn't replaced under them (HeldInstalls
            // says what that breaks, too): the build waits, and goes in when the app closes.
            Runtime.holdBuild(project)
            _ = heldInstalls.mayInstall(project.id, running: true)
            if !asked { log(project, .status, ErrorMessages.stayedOpen(project.name)) }
            owner?.keptOpen = true
            owner?.didNotOpen = true
            noteOpened(false, for: project)
            refreshOpenApps()
            return nil
        }
        guard exists(project) else { return nil }   // deleted while its old copy was quitting
        owner?.didNotOpen = false
        do {
            WidgetCard.forget(project)
            try await deploy(project)
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
            let app = try await NSWorkspace.shared.openApplication(at: project.installedURL, configuration: config)
            if await Runtime.diedOnLaunch(app) {
                log(project, .status, "\(project.name) quit right after opening. Looking at why…")
                crash = await Runtime.launchReport(project)
                log(project, .detail, crash!)
            } else {
                noteOpened(true, for: project)
                if reloading, let owner {
                    owner.saidReloaded = true
                    log(project, .status, ChatLook.reloaded)
                }
                if inFront { log(project, .status, "\(project.name) is ready") }
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
    private func installOnSimulator(_ project: LampProject, owner: Turn, inFront: Bool) async -> String? {
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
            return await launchOnSimulator(project, owner: owner, udid: udid, inFront: inFront)
        }
        simulatorWork[udid] = Task { _ = await mine.value }
        return await mine.value
    }

    /// The launch in progress on each simulator, for the next one to wait for.
    private var simulatorWork: [String: Task<Void, Never>] = [:]

    private func launchOnSimulator(_ project: LampProject, owner: Turn, udid: String, inFront: Bool) async -> String? {
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
            await Simulator.terminate(project.bundleID, on: udid)
            try await Simulator.install(project.builtURL, on: udid)
            guard stillOwns() else { return giveBack("The app was deleted or stopped before it opened.") }
            // One Lamp app per simulator: another project's app on this device is closed first, so what the
            // simulator shows is always the app being worked on (and that app's use_app batch, if any, stops).
            for (other, launched) in simulatorApps where other != project.id && launched.udid == udid {
                if let theirs = projects.first(where: { $0.id == other }) { await Simulator.terminate(theirs.bundleID, on: udid) }
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
            try? await Task.sleep(for: .seconds(3))
            if !Simulator.isRunning(pid: pid) {
                simulatorApps[project.id] = nil
                log(project, .status, "\(project.name) quit right after opening. Looking at why…")
                var crash = "The app quit right after launching."
                if Privacy.sharesLog, let tail = Runtime.logTail(project) { crash += "\n\nLast lines it printed:\n" + tail }
                log(project, .detail, crash)
                refreshOpenApps()
                return crash
            }
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
            try Template.writeDeviceProject(for: project, team: team)
        } catch {
            failed("Lamp couldn't get the app ready for \(name). Click Retry. If it fails again, ask Lamp to fix it and include the error from Agent Details.", output: error.localizedDescription)
            return nil
        }
        log(project, .status, "Building for \(name)…")
        var output: [String] = []
        let app: URL
        do {
            app = try await Devices.build(project, team: team, udid: udid, started: { owner.build = $0 }) { output.append($0) }
            owner.build = nil
        } catch {
            owner.build = nil
            let failure = PhoneFailure(stage: .build, output: output.joined(separator: "\n"))
            failed(failure.message, output: failure.output.isEmpty ? error.localizedDescription : failure.output)
            return nil
        }
        guard stillOwns() else { return nil }
        log(project, .status, "Putting \(project.name) on \(name)…")
        do {
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

    /// Finishes the bundle build.sh made, the way `deploy` finishes a Mac app's: the reasons iOS shows when
    /// the app first asks for the microphone, photos or calendar (without which it's killed on the spot), the
    /// icon, and the files attached in Lamp's chat, which LampAssets finds next to the executable. Then the
    /// bundle is signed again, ad hoc, which is all the simulator asks for.
    private func finishSimulatorBundle(_ project: LampProject) async {
        let fm = FileManager.default
        let app = project.builtURL
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
        for (key, names) in capabilities.lists.sorted(by: { $0.key < $1.key }) {
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
        _ = await Shell.run(script, cwd: project.dir,
                            env: ["LAMP_APP": app.path, "LAMP_NAME": project.name, "LAMP_ICON": Icons.squareURL(project).path]) { _ in }
        Sharing.Assets.adopt(in: project)
        let assets = project.dir.appendingPathComponent(Sharing.Assets.folder)
        try? fm.removeItem(at: app.appendingPathComponent(Attachments.folder))
        try? fm.removeItem(at: app.appendingPathComponent(Sharing.Assets.folder))
        if fm.fileExists(atPath: assets.path) {
            try? fm.copyItem(at: assets, to: app.appendingPathComponent(Sharing.Assets.folder))
        }
        // The watch app's icon: watchOS takes one only from a compiled asset catalog, so Xcode's own compiler makes
        // it from the same square as the iPhone's, and Info.plist names it.
        if fm.fileExists(atPath: app.appendingPathComponent("Watch").path), fm.fileExists(atPath: Icons.squareURL(project).path) {
            let work = project.dir.appendingPathComponent(".lamp/watch-icon")
            try? Template.writeWatchIconCatalog(at: work.appendingPathComponent("Icon.xcassets"), icon: Icons.squareURL(project))
            _ = await Shell.run("""
                for watch in "$LAMP_APP"/Watch/*.app(N); do
                  xcrun actool "$LAMP_WORK/Icon.xcassets" --compile "$watch" --platform watchsimulator --minimum-deployment-target 10.0 \\
                    --app-icon AppIcon --output-partial-info-plist "$LAMP_WORK/partial.plist" >/dev/null 2>&1 && \\
                  plutil -replace CFBundleIcons -json '{"CFBundlePrimaryIcon":{"CFBundleIconName":"AppIcon"}}' "$watch/Info.plist"
                done
                """, cwd: project.dir, env: ["LAMP_APP": app.path, "LAMP_WORK": work.path]) { _ in }
        }
        // A widget extension inside is signed first, as Xcode does: the app's signature then seals it. The watch
        // app the same way, its complications before it.
        _ = await Shell.run("""
            xattr -cr "$LAMP_APP"
            for widget in "$LAMP_APP"/PlugIns/*.appex(N); do codesign --force -s - "$widget"; done
            for watch in "$LAMP_APP"/Watch/*.app(N); do
              for extension in "$watch"/PlugIns/*.appex(N); do codesign --force -s - "$extension"; done
              codesign --force -s - "$watch"
            done
            codesign --force -s - "$LAMP_APP"
            """, cwd: project.dir, env: ["LAMP_APP": app.path]) { _ in }
    }

    /// iPhone apps running in the simulator: which simulator each was launched on, and its process id.
    private var simulatorApps: [String: (udid: String, pid: Int32)] = [:]
    /// Which project each simulator belongs to right now: taken before a launch's first wait, so two launches
    /// on one device can't both go ahead, and checked before every action the driver takes.
    private var simulatorLeases: [String: String] = [:]

    /// For Open App and Undo, where no agent is running to fix a crash.
    private func installReportingCrash(_ project: LampProject) async {
        if await install(project) != nil {
            log(project, .error, ErrorMessages.crashAfterLaunch(project.name))
        }
    }

    /// Puts the icon into the freshly built bundle, re-signs it, and swaps it into the apps folder.
    /// The swap is atomic, so it's safe even while the app is running.
    private func deploy(_ project: LampProject) async throws {
        let fm = FileManager.default
        let resources = project.builtURL.appendingPathComponent("Contents/Resources")
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        // Every usage description, from the one list: without its reason macOS kills the app the moment it
        // asks for the microphone, photos and the rest. Added here as well as in build.sh so apps made before
        // a reason was added get it too.
        var plist = """
            P="$LAMP_APP/Contents/Info.plist"
            plutil -replace CFBundleName -string "$LAMP_NAME" "$P" && \\
            plutil -replace CFBundleDisplayName -string "$LAMP_NAME" "$P"

            """
        for (key, text) in Template.macUsageDescriptions {
            let reason = text.replacingOccurrences(of: "{{NAME}}", with: project.name).replacingOccurrences(of: "'", with: "'\\''")
            plist += "plutil -replace \(key) -string '\(reason)' \"$P\"\n"
        }
        _ = await Shell.run(plist, cwd: project.dir, env: ["LAMP_APP": project.builtURL.path, "LAMP_NAME": project.name]) { _ in }
        if fm.fileExists(atPath: Icons.icnsURL(project).path) {
            try? fm.removeItem(at: resources.appendingPathComponent("AppIcon.icns"))
            try fm.copyItem(at: Icons.icnsURL(project), to: resources.appendingPathComponent("AppIcon.icns"))
            // With Xcode 26, the compiled Icon Composer icon lets macOS 26 draw it in Liquid Glass.
            try? fm.removeItem(at: resources.appendingPathComponent("Assets.car"))
            let hasCar = fm.fileExists(atPath: Icons.carURL(project).path)
            if hasCar { try fm.copyItem(at: Icons.carURL(project), to: resources.appendingPathComponent("Assets.car")) }
            let iconName = hasCar
                ? "plutil -replace CFBundleIconName -string AppIcon \"$LAMP_APP/Contents/Info.plist\""
                : "{ plutil -remove CFBundleIconName \"$LAMP_APP/Contents/Info.plist\" 2>/dev/null || true; }"
            _ = await Shell.run("""
                plutil -replace CFBundleIconFile -string AppIcon "$LAMP_APP/Contents/Info.plist" && \(iconName)
                """, cwd: project.dir, env: ["LAMP_APP": project.builtURL.path]) { _ in }
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
        if BuildStamp.read(project.builtURL)?.isOutdated ?? true {
            let attachments = project.dir.appendingPathComponent(Attachments.folder)
            if fm.fileExists(atPath: attachments.path) {
                try fm.copyItem(at: attachments, to: resources.appendingPathComponent(Attachments.folder))
            }
        }
        // What the agent declared in capabilities.json, as the simulator's bundle gets its own (finishSimulatorBundle).
        let capabilities = Template.Capabilities.load(project)
        capabilities.apply(to: project.builtURL, for: project)
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
        try Sidebar.install(into: project.builtURL, for: project)
        _ = await Shell.run("xattr -cr \"$LAMP_APP\"", cwd: project.dir, env: ["LAMP_APP": project.builtURL.path]) { _ in }
        // A widget keeps its own signature inside the app's (AppSigning.command), with entitlements Lamp
        // writes here rather than takes from the build folder, where anything could have changed them.
        let widget = Template.widgetURL(in: project.builtURL, of: project)
        let hasWidget = fm.fileExists(atPath: widget.path)
        let entitlements = project.dir.appendingPathComponent(".lamp/widget-entitlements.plist")
        if hasWidget { try Template.widgetEntitlementsPlist.write(to: entitlements, atomically: true, encoding: .utf8) }
        // A share extension the same way. It hands what it's given to the app through a folder they share,
        // which macOS allows only to a signature with a team, so it stays only in an app signed for one.
        let share = Template.shareURL(in: project.builtURL, of: project)
        var hasShare = project.platform == .mac && fm.fileExists(atPath: share.path)
        let shareEntitlements = project.dir.appendingPathComponent(".lamp/share-entitlements.plist")
        var signingEnv = ["LAMP_APP": project.builtURL.path, "LAMP_WIDGET": widget.path, "LAMP_WIDGET_ENTITLEMENTS": entitlements.path,
                          "LAMP_SHARE": share.path, "LAMP_SHARE_ENTITLEMENTS": shareEntitlements.path]
            .merging(Sidebar.signingEnvironment(for: project)) { $1 }
        // An app for both was signed by Xcode for the person's team; what was put in since is sealed with the
        // same certificate and the same entitlements, never Lamp's own, which could carry neither.
        let identity = project.platform == .universal ? (await Devices.signingIdentity(for: Devices.team) ?? "-") : await AppSigning.identity()
        var signed = false
        if project.platform == .universal, identity != "-" {
            var output: [String] = []
            signed = await Shell.run(Sidebar.signingStep("codesign --force -s \"$LAMP_IDENTITY\"")
                                     + " && codesign --force --preserve-metadata=entitlements -s \"$LAMP_IDENTITY\" \"$LAMP_APP\" 2>&1",
                                     cwd: project.dir, env: signingEnv.merging(["LAMP_IDENTITY": identity]) { $1 }) { output.append($0) } == 0
                && AppSigning.isCertificateSigned(project.builtURL)
            if !signed { print("Signing \(project.name) for the team failed:\n" + output.joined(separator: "\n")) }
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
                    Self.setAppGroup(group, in: [project.builtURL] + (hasWidget ? [widget] : []) + (hasShare ? [share] : []))
                    let appEntitlements = project.dir.appendingPathComponent(".lamp/app-entitlements.plist")
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
                    && AppSigning.isCertificateSigned(project.builtURL) && (!hasWidget || AppSigning.isCertificateSigned(widget))
                    && (!hasShare || AppSigning.isCertificateSigned(share))
                if !signed { print("Signing \(project.name) for the team failed:\n" + output.joined(separator: "\n")) }
                Self.rememberTeamSigning(failed: !signed, for: project)
            }
            if !signed, project.platform == .mac {
                // Not signed for a team, the app's intents would be listed by macOS and never run: they're taken
                // out. The widget's stay: its buttons run them inside the widget, which needs no team. Nor is
                // there a shared folder: the widget sends its actions to the app over their connection instead.
                try? fm.removeItem(at: project.builtURL.appendingPathComponent("Contents/Resources/Metadata.appintents"))
                if hasWidget {
                    Self.setAppGroup(nil, in: [project.builtURL, widget])
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
            if signed && !(AppSigning.isCertificateSigned(project.builtURL) && (!hasWidget || AppSigning.isCertificateSigned(widget))) {
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

        // What Lamp signed as the app's sidebar, the one program it will talk to there.
        Sidebar.remember(project)

        // What the copy being replaced was signed as, to notice when this build is signed differently. Only a copy
        // of this app, by its id: one of another id at the same place (an app of the same name since deleted, or
        // made by Lamp with other settings) had no permissions of this app's to lose.
        // Read from the file, not `Bundle`, which keeps what it read of a path for as long as Lamp runs.
        let previousID = NSDictionary(contentsOf: project.installedURL.appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"] as? String
        let replaced = previousID == project.bundleID ? await AppSigning.requirement(of: project.installedURL) : nil

        try fm.createDirectory(at: Self.installDir, withIntermediateDirectories: true)
        AppsLink.ensure()
        let staging = Self.installDir.appendingPathComponent(".\(project.exe)-\(UUID().uuidString).app")
        try fm.copyItem(at: project.builtURL, to: staging)
        // The app isn't running by now (a build quits it, an icon waits for it to close), but its widget's
        // process may be: ended here, last thing before the swap, so no program outlives the copy it came from.
        await WidgetProcess.end(for: project)
        if fm.fileExists(atPath: project.installedURL.path) {
            _ = try fm.replaceItemAt(project.installedURL, withItemAt: staging)
        } else {
            try fm.moveItem(at: staging, to: project.installedURL)
        }
        // What the app now runs when it opens is this build's sources (LiveReload compares a change with them).
        LiveReload.installed(project)
        if LiveReload.eligible(project) { LiveReload.markRunning(project) } else { LiveReload.forget(project) }
        // Nudge Finder, the Dock and Launchpad to pick up the new icon.
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: project.installedURL.path)
        _ = await Shell.run(
            Self.lsregister + " -f \"$LAMP_APP\"",
            cwd: project.dir, env: ["LAMP_APP": project.installedURL.path]) { _ in }
        // macOS keeps a permission with the signature it was given to. Signed differently, the app has lost
        // what it had, but System Settings still shows the old entries switched on, and they do nothing.
        if let replaced, let requirement = await AppSigning.requirement(of: project.installedURL), replaced != requirement,
           await AppSigning.forgetPermissions(of: project.bundleID) {
            print("\(project.name) is signed differently from the copy it replaced, so its macOS permissions were cleared:\n"
                  + "  was: \(replaced)\n  now: \(requirement)")
            // An app signed ad hoc is signed differently every time: that was said when it was signed.
            if signed {
                log(project, .status, "If you gave \(project.name) a permission in System Settings (such as Full Disk Access or Screen Recording), macOS needs it once more: Lamp signs apps with a new certificate. After that it stays on.")
            }
        }
    }

    // MARK: - Icons

    /// Makes sure icon.json exists, then renders it (with cached artwork if there is any).
    private func prepareIcon(_ project: LampProject) async {
        await iconDesigns[project.id]?.value
        var spec = Icons.load(project)
        if spec == nil && project.untitled { return }   // keeps its placeholder until the first message
        if spec == nil {
            log(project, .status, "Designing an icon…")
            spec = await Icons.design(for: project)
            Icons.save(spec!, for: project)
        }
        await renderIcon(project, spec: spec!)
    }

    private func renderIcon(_ project: LampProject, spec: IconSpec) async {
        do {
            let art = Icons.cachedArt(project, spec: spec)
            if art != nil { artApplied[project.id] = spec }
            icons[project.id] = try await Icons.write(spec, art: art, for: project)
        } catch {
            log(project, .detail, "Icon render failed: \(error.localizedDescription)")
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
    /// when ready, with whatever can make pictures. With nothing, the first app asks for a key instead.
    private func upgradeIconArt(_ project: LampProject) {
        guard let spec = Icons.load(project), !spec.subject.trimmed.isEmpty,
              Icons.cachedArt(project, spec: spec) == nil else { return }
        // The person chose to draw icons themselves: Lamp draws nothing, key or no key, and asks for no key.
        guard !AppAI.iconsByHand else { return offerDrawing(project, spec: spec) }
        guard artInProgress.insert(project.id).inserted else { return }
        Task {
            defer { artInProgress.remove(project.id) }
            guard await AppAI.imageRoute() != nil else {
                offerSetup(project, SetupOffer(capability: .pictures, icon: true),
                           because: "Nothing on this Mac can draw pictures yet. Set up one of the ways below and Lamp will paint \(project.name) a proper icon, and your apps will be able to make pictures too.")
                return
            }
            // The person may choose to draw icons themselves during either wait here: from then on nothing
            // Lamp drew is used, and the drawing is theirs to do.
            guard !AppAI.iconsByHand else { return offerDrawing(project, spec: spec) }
            do {
                let art = try await Icons.generateBestArt(spec, appName: project.name) { [weak self] in
                    self?.log(project, .detail, $0)
                }
                guard !AppAI.iconsByHand else { return offerDrawing(project, spec: spec) }
                // A picture picked in Image Playground while these were being drawn is the person's choice: it stays.
                guard Icons.cachedArt(project, spec: spec) == nil else { return }
                let url = Icons.artURL(project, spec: spec)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard let tiff = art.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?
                    .representation(using: .png, properties: [:]) else { return }
                try png.write(to: url)
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
            } catch {
                log(project, .detail, "Couldn't draw the icon's artwork. \(error.localizedDescription)")
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
            artApplied[project.id] = nil   // the icon on show was made with other artwork, or none
            // As with generated artwork: a turn that has the app installs the picture when it ends. The chat
            // shows it at once and says so, or picking it would look like nothing happened.
            guard begin(project) != nil else {
                pendingIconArt.insert(project.id)
                let preview = await Icons.preview(spec, art: NSImage(data: png))
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
    }

    private func refreshOpenApps() {
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
        let onIOS = Array(simulatorApps.keys) + Array(deviceApps.keys)
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
        await quit(project, only: project.platform == .universal ? project.destination : nil)
        refreshOpenApps()
    }

    /// Apps that were asked to quit and aren't responding, with the process that isn't: the chat offers to
    /// force it to quit while this holds. Lamp never does that itself.
    @Published private(set) var notResponding: [String: pid_t] = [:]

    /// The person's click on Force Quit: ends the copy that isn't responding, and whatever was waiting for
    /// it to close (a build, Lamp's Quit, Delete) goes on.
    func forceQuit(_ project: LampProject) {
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
        if project.platform.hasIOS, place != .mac {
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
            if !project.platform.hasMac || place == .ios { return true }
        }
        // Nobody is waiting once the turn is stopped or over. Not `stopped`, which the agent's exit clears.
        let stopped = { owner.map { self.turns[project.id] !== $0 || $0.wasStopped } ?? false }
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
        return closed
    }

    // MARK: - AI gateway for generated apps

    private func startGateway() {
        let gateway = Gateway { request in await Store.shared.handleAI(request) }
        do {
            try gateway.start()
            gateway.setLocalNetwork(projects.contains { $0.platform.hasIOS && $0.device != nil })
            self.gateway = gateway
        } catch {
            NSLog("Lamp AI gateway failed to start: \(error)")
        }
    }

    /// The gateway answers on the local network only while an app is set to open on the person's own phone:
    /// kept in step with the list of apps (Try On, deletion, rename, reload).
    func syncLocalNetwork() {
        gateway?.setLocalNetwork(projects.contains { $0.platform.hasIOS && $0.device != nil })
    }

    func handleAI(_ request: Gateway.Request) async -> (Int, [String: Any]) {
        if BrowserBridge.enabled, request.path.hasPrefix("/browser/") {
            return BrowserBridge.shared.handle(request, projects: projects)
        }
        let route = request.path.split(separator: "?").first.map(String.init) ?? request.path
        let paths = ["/ai", "/ai/keys", "/ai/status", "/ai/image", "/ai/decide", "/ai/computer", "/agent/computer", "/agent/look", "/agent/use", "/agent/approve",
                     "/agent/versions", "/agent/versions/name", "/agent/versions/restore", "/agent/memory", "/agent/skill", "/agent/setup", "/agent/kind", "/agent/connectors", "/agent/art", "/agent/talk", "/mcp", "/pi/key", "/app/secrets"]
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
        guard setup.ready else { return (503, ["error": "Lamp isn't set up yet. Open Lamp to finish setup."]) }
        return await appRequest(request, for: project)
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

    /// Whether a Host header is this Mac's name on the local network (what apps on phones are given), with
    /// an optional numeric port.
    static func isMacHost(_ header: String?) -> Bool {
        guard let host = header?.trimmed.lowercased(), !host.isEmpty else { return false }
        let name = host.split(separator: ":", maxSplits: 1).first.map(String.init) ?? host
        guard host.count == name.count || host.dropFirst(name.count + 1).allSatisfy(\.isNumber) else { return false }
        return name == Devices.macHost.lowercased()
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
        if route == "/mcp" { return await mcp(request.body, for: project, fileTools: request.path.contains("files=1")) }
        if request.path == "/agent/look" {
            let arguments = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
            return arguments["sidebar"] as? Bool == true
                ? await lookAtSidebar(project, page: arguments["page"] as? String)
                : await look(at: project, prop: arguments["prop"] as? String, motion: arguments["motion"] as? Bool ?? false)
        }
        if request.path == "/agent/use" { return await use(project, request: request.body) }
        if request.path.hasPrefix("/agent/versions") {
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
            return await versions(String(request.path.dropFirst("/agent/versions".count)), body, of: project)
        }
        if route == "/agent/memory" {
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
            return notes(body["tool"] as? String ?? "", body["arguments"] as? [String: Any] ?? [:], for: project)
        }
        if route == "/agent/skill" {
            return Skills.read((try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:])
        }
        if route == "/agent/art" {
            return await makeArt((try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:], for: project)
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
            // pi's extension sends {"command"}; Claude Code's hook sends {"tool_input": {"command"}}.
            let input = body["tool_input"] as? [String: Any] ?? [:]
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
            let confined = shell && engine != .codex ? Sandbox.wrap(command, for: project) : nil
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
            if request.path.contains("format=codex") {
                // Codex's PreToolUse hook can only block: an empty answer lets the command run.
                let allowed = await approveCommand(command, for: project, escalated: false, sandboxed: sandboxed)
                return (200, allowed ? [:] : ["hookSpecificOutput": ["hookEventName": "PreToolUse",
                                                                     "permissionDecision": "deny",
                                                                     "permissionDecisionReason": "The user denied this command in Lamp."]])
            }
            let allowed = await approveCommand(command, for: project, escalated: escalated, shell: shell, sandboxed: sandboxed)
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
    /// the OpenRouter key, the TypeSafe key when decisions go there, and the models the app is set to, as
    /// `AppAI.resolve` has them for `.phoneAway`. Only for iPhone apps; a Mac app
    /// or the simulator never needs it, and the key stays in the phone's Keychain, put there by the app itself.
    private func keysForPhone(_ project: LampProject) -> (Int, [String: Any]) {
        guard project.platform.hasIOS else { return (403, ["error": "Not for this app."]) }
        guard AppAI.resolve(.text, for: project, in: .phoneAway).tier != .none, let key = KeyStore.openRouterKey else {
            return (404, ["error": "There's no OpenRouter key to keep."])
        }
        let models = AppModels.load(project)
        var decision = AppAI.awayDecisionModel(for: models.awayDecision)
        var keys: [String: Any] = [
            "openrouter": key,
            "text_model": AppAI.awayModel(for: models.away).openRouter,
        ]
        if decision.provider == "typesafe" {
            if let typesafe = KeyStore.key(for: "typesafe") { keys["typesafe"] = typesafe }
            else { decision = AppAI.awayDecisionModels.first { $0.provider == "text" }! }   // what `resolve` says stands in
        }
        keys["decision_model"] = decision.model
        keys["decision_provider"] = decision.provider
        // The cloud image model chosen for away from the Mac (the Mac's own model can't travel).
        keys["image_model"] = AppAI.awayImageModel(for: models.awayImage)
        // Sealed with the secret that went to the phone inside its build, never over the network: the token
        // in the request is on the air too, so it can't be what protects the key.
        guard let json = try? JSONSerialization.data(withJSONObject: keys),
              let box = try? AES.GCM.seal(json, using: SymmetricKey(data: SHA256.hash(data: Data(Template.phoneSecret(for: project).utf8)))),
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
            followRestoredKind(project)
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
        Privacy.sharesPictures ? pictures.map { Previews.forAgent($0, in: project).path } : []
    }

    /// What a look says when the person kept the earlier build open (`Turn.keptOpen`).
    private static let keptOpenNote = """
        The app built, but the person has the version from before open and chose to keep it open (it may hold \
        work they haven't saved), so Lamp didn't replace it. What's on screen isn't your change, so don't look \
        or use the app again in this request. Finish, and tell them in a sentence that the new version opens \
        once they close the app.
        """

    /// The agent's `look_at_app` tool: builds what it has written so far, opens the app behind the
    /// user's windows, and reports what happened. The pictures are sent as file paths for pi to read. For a Mac
    /// app it can instead show one of the app's 3D props from four sides (`prop`), or watch the window for a
    /// couple of seconds and say what moved and what flickered (`motion`).
    private func look(at project: LampProject, prop: String? = nil, motion: Bool = false) async -> (Int, [String: Any]) {
        // Only for the agent Lamp is running right now. The app knows the same token and must not
        // be able to rebuild itself.
        guard let turn = turns[project.id], turn.agent != nil else {
            return (409, ["error": "Lamp isn't working on this app right now."])
        }
        guard !turn.look.inProgress else { return (200, ["text": "Lamp is already looking at the app. Wait for that result."]) }
        turn.look.inProgress = true
        turn.look.installed = false
        defer { turn.look.inProgress = false }

        try? Template.writeSupport(for: project)
        let changed = Runtime.sourcesChanged(project)
        if changed, let errors = await build(project) {
            if errors == macMembershipProblem(project) {
                return (200, ["text": "The app can't be built for this Mac, and Lamp has told the person why: \(errors)\n\nThis isn't a mistake in the code. Don't take iCloud out unless the person asked for that; finish what was asked without a look."])
            }
            return (200, ["text": "The app doesn't build yet. Fix these compiler errors:\n\n\(errors)"])
        }
        var note = "The app built and is running."
        var screenshots: [URL] = []
        if project.onIOS {
            // The simulator photographs the screen; nothing in the app has to cooperate.
            // Open, and the device still this app's: otherwise it's opened again (which takes the device back).
            let running = simulatorApps[project.id].map { Simulator.isRunning(pid: $0.pid) && simulatorLeases[$0.udid] == project.id } ?? false
            if changed || !running {
                let crash = await install(project, inFront: false)
                turn.look.installed = true
                turn.look.crash = crash
                if let crash { return (200, ["text": "The app \(changed ? "built" : "is built"), but it didn't stay open.\n\n\(crash)"]) }
                if !changed { note = "The app is running your latest code; it was reopened without rebuilding." }
            } else {
                note = "The app is running your latest code; nothing needed rebuilding."
            }
            try? await Task.sleep(for: .seconds(1))
            let picture = Runtime.folder(project).appendingPathComponent("screenshot.png")
            if let udid = simulatorApps[project.id]?.udid, await Simulator.screenshot(on: udid, to: picture) { screenshots = [picture] }
            // Which simulator: what it can show depends on it (a Dynamic Island is only on some iPhones).
            var on = ""
            if let udid = simulatorApps[project.id]?.udid, let name = await Simulator.name(of: udid) { on = " It's open on the \(name) simulator." }
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
        if turn.keptOpen, isRunning(project) { return (200, ["text": Self.keptOpenNote]) }
        var since = Date()
        // A copy kept open in an earlier request is older than the build too: it's asked to quit, once.
        if !changed, !Runtime.holdsBuild(project), macCopies(of: project).first != nil {
            // Nothing to rebuild and the app is open: ask it for fresh pictures instead of relaunching it.
            let asked = Date()
            since = asked
            Runtime.requestScreenshots(of: project)
            screenshots = await Runtime.screenshots(of: project, since: asked, waiting: 2)
            note = "The app is running your latest code; nothing needed rebuilding."
            turn.look.installed = !screenshots.isEmpty
            turn.look.crash = nil
        }
        if screenshots.isEmpty {
            let launched = Date()
            since = launched
            let crash = await install(project, inFront: false)
            if turn.keptOpen { return (200, ["text": Self.keptOpenNote]) }
            turn.look.installed = true
            turn.look.crash = crash
            if let crash {
                return (200, ["text": "The app \(changed ? "built" : "is built"), but it quit right after launching.\n\n\(crash)"])
            }
            if !changed { note = "The app is running your latest code; it was reopened without rebuilding." }
            screenshots = await Runtime.screenshots(of: project, since: launched)
        }
        var lead = ""
        if let prop, !prop.isEmpty, !screenshots.isEmpty {
            // One prop on its own: the app shows it from four sides over its scene, pictures it, and goes back.
            let asked = Date()
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
        text += Self.handingHint(for: project)
        text += await Self.intentsHint(for: project)
        text += Self.shareHint(for: project)
        // The front window in words, beside its picture, from the app itself (LampScreen in LampSupport.swift).
        if Privacy.sharesPictures, !screenshots.isEmpty, Self.binary(of: project, contains: Self.screenTextMarker),
           let words = await Runtime.screenText(of: project, since: since) { text += "\n\n" + words }
        if Privacy.sharesLog, let tail = Runtime.logTail(project) { text += "\n\nWhat it printed:\n\(tail)" }
        return (200, ["text": text, "screenshots": Self.agentPictures(screenshots, in: project)])
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
    private static let commit = Versions.commit
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
