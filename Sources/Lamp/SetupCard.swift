import SwiftUI
import Combine
import LampSidebarKit

/// Offers a way to set up a kind of AI where it's first wanted: in the chat of the app that wanted it, put
/// there by Lamp when an app hit something nothing here can do, or by the agent with `offer_setup`. Built
/// like the build card above it in the chat (an icon, a headline and a status line, then rows), and
/// what it offers comes from `AppAI.resolve`, as Settings' does, so the two always agree. Once that capability
/// is set up (here or in Settings) it folds down to its header, saying what answers now. What it says is
/// worked out here (`SetupCards`) and drawn by `SetupCardView`, the same card the chat beside the app shows.
struct SetupCard: View {
    let offer: SetupOffer
    let reason: String
    /// The folder of the app whose chat this is.
    let dir: URL
    @ObservedObject private var cards = SetupCards.shared
    @State private var showGuide = false

    private var project: LampProject? { Store.shared.projects.first { $0.dir == dir } }

    var body: some View {
        let _ = cards.revision
        SetupCardView(cards.content(for: offer, reason: reason, in: project)) { action in
            if action == .row(Upgrade.browserExtension.id) { return showGuide = true }
            cards.act(action, on: offer, in: project)
        }
        .sheet(isPresented: $showGuide) { BrowserSetupGuide() }
        // Asked for from the chat beside the app, which can't show the guide itself.
        .onReceive(cards.$guideFor) { id in
            guard let id, id == project?.id else { return }
            cards.guideFor = nil
            showGuide = true
        }
    }
}

/// What a setup card says and what its buttons do, for Lamp's window and the chat beside an app alike. Keys
/// being checked are kept here, by provider, rather than in a card's view, so a key pasted beside the app
/// shows its check there and in Lamp's window.
@MainActor
final class SetupCards: ObservableObject {
    static let shared = SetupCards()
    /// Goes up whenever something a card shows may have changed: keys, choices, downloads, sign-ins, icons.
    @Published private(set) var revision = 0
    /// The app whose chat should open the Chrome setup guide (asked for beside the app).
    @Published var guideFor: String?
    private var checks: [String: KeyCheck] = [:]
    private var signingIn: Set<Engine> = []
    private var watching: [AnyCancellable] = []

    private init() {
        let center = NotificationCenter.default
        let changes: [AnyPublisher<Void, Never>] = [
            center.publisher(for: KeyStore.changed).map { _ in }.eraseToAnyPublisher(),
            center.publisher(for: AppModels.changed).map { _ in }.eraseToAnyPublisher(),
            center.publisher(for: UserDefaults.didChangeNotification).map { _ in }.eraseToAnyPublisher(),
            LocalModels.shared.objectWillChange.map { _ in }.eraseToAnyPublisher(),
            ImageModels.shared.objectWillChange.map { _ in }.eraseToAnyPublisher(),
            PythonTools.shared.objectWillChange.map { _ in }.eraseToAnyPublisher(),
            BrowserSetup.shared.objectWillChange.map { _ in }.eraseToAnyPublisher(),
            Store.shared.$icons.map { _ in }.eraseToAnyPublisher(),
        ]
        // After the change is made, never during a view's update.
        watching = changes.map { $0.receive(on: DispatchQueue.main).sink { [weak self] in self?.changed() } }
    }

    private func changed() { revision += 1 }

    private func check(_ provider: String) -> KeyCheck {
        if let check = checks[provider] { return check }
        let check = KeyCheck()
        watching.append(check.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.changed() })
        checks[provider] = check
        return check
    }

    func content(for offer: SetupOffer, reason: String, in project: LampProject?) -> SetupContent {
        let resolution = AppAI.resolve(offer.capability, for: project, in: offer.context)
        // An icon's card is also answered by the person choosing to draw icons themselves.
        let byHand = resolution.provider == Icons.byHand
        let done = resolution.tier == .best
        let declined = !done && (project.map(offer.declined(in:)) ?? false)
        let status: String
        if done {
            status = byHand ? "All set. You draw each app's icon with Image Playground." : Self.doneText(offer, resolution.answer ?? "")
        } else if declined {
            status = offer.capability == .browser ? "No problem. You can connect Chrome any time in Lamp’s Settings, under Experimental."
                : "No problem. You can set this up any time in Lamp's Settings, under AI Providers."
        } else {
            status = reason
        }
        // Answered by drawing icons by hand, the card is where this app's is drawn, while it's plain.
        let plainIcon = byHand && project.flatMap { project in Icons.load(project).map { Icons.cachedArt(project, spec: $0) == nil } } == true
        return SetupContent(
            symbol: offer.context == .phoneAway ? "iphone.radiowaves.left.and.right" : offer.capability.symbol,
            title: Self.title(offer), status: status, done: done, declined: declined, drawIcon: plainIcon,
            rows: rows(resolution.upgrades, compact: false),
            // Something answers already, just not as well: say what, so nothing looks broken meanwhile.
            note: resolution.tier == .works ? resolution.answer.map { "For now it works through \($0); the options above work better." } : nil)
    }

    func act(_ action: SetupAction, on offer: SetupOffer, in project: LampProject?) {
        switch action {
        case .notNow:
            if let project { offer.decline(in: project) }
        case .drawIcon:
            if let project { Store.shared.iconFromPlayground(project) }
        case .row(let id):
            perform(id)
        case .key(let id, let typed):
            guard id.hasPrefix("key:"), let provider = Provider.keyProvider(String(id.dropFirst(4))) else { return }
            let check = check(provider.id)
            guard let typed else { return check.edited() }
            check.save(typed, for: provider, strict: true) {
                Task { await Store.shared.recheckSetup() }
            }
        }
        changed()
    }

    /// A row's button, but for a key's (typed in place in the chat, in its sheet in Settings) and Chrome's (a
    /// guide shown where the row is).
    func perform(_ id: String) {
        if id == Upgrade.pictureModel.id, let spec = ImageModels.catalog.first {
            Task {
                if !ImageModels.hasMflux { await PythonTools.shared.install(.mflux) }
                if ImageModels.hasMflux { ImageModels.shared.download(spec) }
            }
        } else if id == Upgrade.decisionModel.id, let spec = LocalModels.decisionCatalog.first {
            LocalModels.shared.download(spec)
        } else if id.hasPrefix("signIn:"), let engine = Engine(rawValue: String(id.dropFirst(7))), !signingIn.contains(engine) {
            signingIn.insert(engine)
            Task {
                _ = await EngineSignIn.signIn(engine)
                await Store.shared.recheckSetup()
                signingIn.remove(engine)
                changed()
            }
        } else if id == Upgrade.drawIcons.id {
            Icons.iconChoice = Icons.byHand
        }
        changed()
    }

    private static func title(_ offer: SetupOffer) -> String {
        if offer.context == .phoneAway { return "Use AI on your phone, away from this Mac" }
        // Raised for the app's icon, its options include drawing icons by hand, which isn't AI.
        if offer.context == .icon { return "Give your apps proper icons" }
        return switch offer.capability {
        case .text: "Use AI in your apps"
        case .decisions: "Let your apps make quick judgments"
        case .pictures: "Make pictures with AI"
        case .browser: "Use your app in Chrome"
        }
    }

    private static func doneText(_ offer: SetupOffer, _ answer: String) -> String {
        if offer.context == .phoneAway { return "All set. Away from this Mac, your phone's apps now use your OpenRouter key." }
        return switch offer.capability {
        case .text: "All set. Your apps' AI now runs on \(answer)."
        case .decisions: "All set. Your apps' judgments are now made by \(answer)."
        case .pictures: "All set. Pictures are now made by \(answer)."
        case .browser: "All set. Lamp is connected to Chrome."
        }
    }

    /// Some can't be done on this Mac: a picture model that needs more memory than it has.
    static func isOffered(_ upgrade: Upgrade) -> Bool {
        switch upgrade {
        case .pictureModel:
            guard let spec = ImageModels.catalog.first else { return false }
            return Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824 >= Double(spec.minRAMGB)
        case .decisionModel: return LocalModels.decisionCatalog.first != nil
        case .key(let provider): return Provider.keyProvider(provider) != nil
        case .signIn: return true
        case .drawIcons: return Icons.playgroundAvailable
        case .browserExtension: return BrowserBridge.enabled
        }
    }

    /// What would make a capability better, best first, a row each. The same rows in the chat's card and in
    /// Settings (`compact`), which says each in a line where the card explains, since the card is often the
    /// first the person hears of it.
    func rows(_ upgrades: [Upgrade], compact: Bool) -> [UpgradeRow] {
        upgrades.filter(Self.isOffered).compactMap { row($0, compact: compact) }
    }

    private func row(_ upgrade: Upgrade, compact: Bool) -> UpgradeRow? {
        switch upgrade {
        case .key(let id):
            guard let provider = Provider.keyProvider(id) else { return nil }
            let detail = switch (provider.id, compact) {
            case ("openrouter", true): "One key for the best text, pictures and decisions. Pay as you go."
            case ("openrouter", false):
                "OpenRouter is one account for many AI models. Create a key on its website and paste it here; you pay only for what your apps use, usually cents."
            case ("typesafe", true): "Jev, made for fast, reliable judgments."
            case ("typesafe", false): "TypeSafe makes Jev, a model built for quick, reliable judgments. Create a key on its website and paste it here."
            case ("openai", _): "OpenAI's Decisions API, with a key from your OpenAI account."
            default: "Use your \(provider.name) account."
            }
            let check = check(provider.id)
            return UpgradeRow(id: upgrade.id, symbol: "key.horizontal", title: "Add \(AppAI.keyPhrase(provider.id))", detail: detail,
                              button: "Add Key…",
                              key: KeyField(site: provider.name, link: provider.keyURL, checking: check.checking, problem: check.problem))
        case .pictureModel:
            guard let spec = ImageModels.catalog.first else { return nil }
            let tools = PythonTools.shared
            return UpgradeRow(
                id: upgrade.id, symbol: "desktopcomputer", title: compact ? "Make them on this Mac" : "Download a picture model to this Mac",
                detail: compact ? String(format: "Free and private, with %@. A %.1f GB download.", spec.name, spec.sizeGB)
                    : String(format: "Pictures are made right here, free and private, with nothing sent online. %@ is a %.1f GB download and needs a Mac with %d GB of memory or more.",
                             spec.name, spec.sizeGB, spec.minRAMGB),
                button: "Download", progress: LocalModels.shared.progress["image:" + spec.id],
                working: tools.installing.contains(.mflux), problem: tools.errors[.mflux])
        case .decisionModel:
            guard let spec = LocalModels.decisionCatalog.first else { return nil }
            return UpgradeRow(
                id: upgrade.id, symbol: "desktopcomputer", title: compact ? "Make them on this Mac" : "Download a judgment model to this Mac",
                detail: compact ? String(format: "Free and private, with %@. A %.1f GB download.", spec.name, spec.sizeGB)
                    : String(format: "Judgments are made right here, free and private, with nothing sent online. %@ is a %.1f GB download.",
                             spec.name, spec.sizeGB),
                button: "Download", progress: LocalModels.shared.progress[spec.id])
        case .signIn(let engine):
            return UpgradeRow(id: upgrade.id, symbol: "person.crop.circle", title: "Sign in to \(engine.title)",
                              detail: compact ? "Use the plan you already pay for." : "Your apps can use AI through the \(engine.title) plan you already have.",
                              button: "Sign In…", working: signingIn.contains(engine))
        case .drawIcons:
            // Drawing icons by hand, one of the ways to get icon artwork where nothing can draw it, which
            // `AppAI.resolve` lists for `.icon` alone. It's a choice for every app's icon, made once.
            return UpgradeRow(id: upgrade.id, symbol: "paintbrush.pointed", title: "Draw icons yourself",
                              detail: "Free, with Image Playground. You draw each app's icon.", button: "Use for All Apps")
        case .browserExtension:
            let browser = BrowserSetup.shared
            return UpgradeRow(id: upgrade.id, symbol: "sidebar.right", title: browser.connected ? "Connected to Chrome" : "Connect Lamp to Chrome",
                              detail: browser.connected ? "Click Lamp in Chrome’s toolbar beside a page."
                                  : (browser.bridgeInstalled ? "Add the Lamp extension in Chrome." : "Add Lamp to Chrome to use apps beside pages."),
                              button: browser.connected ? "Open…" : "Set Up…")
        }
    }
}

/// The line in the chat that offers to draw an app's icon, for someone who chose to draw icons themselves:
/// what's so, and the button that opens Image Playground. It's shown only while it has something to offer
/// (`Icons.awaitsDrawing`).
struct DrawIconLine: View {
    let project: LampProject

    static func text(_ project: LampProject) -> String { "\(project.name) has a plain icon for now." }

    var body: some View {
        CardLook.ActionLine(symbol: "paintbrush.pointed", text: Self.text(project), button: "Draw Icon…") {
            Store.shared.iconFromPlayground(project)
        }
    }
}

/// A first request that read as an iPhone app, made for the Mac because this Mac can't build one yet. The
/// button opens the iPhone setup; once it's done, the app is asked to be made for the iPhone as well (or
/// instead), as the person would ask, so the change goes through the agent like any other.
struct IPhoneSetupLine: View {
    let project: LampProject
    let wanted: Platform
    @ObservedObject private var asked = Asked.shared
    @ObservedObject private var store = Store.shared

    /// Apps whose setup is under way: one click per app, so a second can't queue the same conversion again.
    /// Once setup is done the request is the app's turn, queued or running, which keeps the button off until
    /// it ends; an app still only for the Mac then (the turn failed, was stopped or undone) can try again.
    @MainActor final class Asked: ObservableObject {
        static let shared = Asked()
        @Published var ids: Set<String> = []
    }

    static func text(_ project: LampProject) -> String { "\(project.name) is a Mac app for now. This Mac needs a few things from Apple to make iPhone apps." }
    static let button = "See What's Needed…"

    @MainActor static func canSetUp(_ project: LampProject) -> Bool {
        let store = Store.shared
        return !Asked.shared.ids.contains(project.id) && !store.busy.contains(project.id) && (store.queued[project.id] ?? []).isEmpty
    }

    var body: some View {
        let _ = (asked.ids, store.busy)
        CardLook.ActionLine(symbol: "iphone", text: Self.text(project), button: Self.button, enabled: Self.canSetUp(project)) {
            Self.setUp(project, wanted: wanted)
        }
    }

    @MainActor static func setUp(_ project: LampProject, wanted: Platform) {
        guard canSetUp(project) else { return }
        let id = project.id, both = wanted == .universal
        Asked.shared.ids.insert(id)
        // Resolved again each time: an app that's gone, or no longer only a Mac app, has nothing to set up for,
        // and the setup lets go of the request rather than hold up the ones behind it.
        PhoneSetup.shared.perform(resolve: {
            guard let current = Store.shared.current(project), current.platform == .mac else { return nil }
            return PhoneSetup.Context(family: .iphone, requiresTeam: both)
        }, cancelled: { Asked.shared.ids.remove(id) }) {
            Asked.shared.ids.remove(id)
            guard let current = Store.shared.current(project), current.platform == .mac else { return }
            Store.shared.send(both ? "Make it work on my iPhone too." : "Make it an iPhone app instead.", to: current)
        }
    }
}

/// What Settings says under a capability's picker when it isn't answered the best way it could be: why,
/// and the same upgrades the chat's card offers, each in a line.
struct CapabilityNote: View {
    let capability: Capability
    var project: LampProject? = nil
    var context: AIContext = .mac
    @ObservedObject private var cards = SetupCards.shared
    @State private var showGuide = false
    @Environment(\.openSettings) private var openSettings
    @AppStorage("settingsTab") private var settingsTab = "building"
    @AppStorage("settingsSheet") private var settingsSheet = ""

    var body: some View {
        let _ = cards.revision
        let resolution = AppAI.resolve(capability, for: project, in: context)
        if resolution.tier != .best {
            VStack(alignment: .leading, spacing: 6) {
                // Gray: in Settings the Not Ready badge beside the choice is the only orange.
                if let note = resolution.explanation {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                UpgradeRows(cards.rows(resolution.upgrades, compact: true), compact: true) { action in
                    guard case .row(let id) = action else { return }
                    perform(id)
                }
            }
            .sheet(isPresented: $showGuide) { BrowserSetupGuide() }
        }
    }

    /// In Settings a key is added in its provider's sheet, where it can be saved unchecked, and several
    /// capabilities wanting the same key share that one sheet.
    private func perform(_ id: String) {
        if id.hasPrefix("key:") {
            settingsSheet = String(id.dropFirst(4))
            settingsTab = "providers"
            openSettings()
        } else if id == Upgrade.browserExtension.id {
            showGuide = true
        } else {
            cards.perform(id)
        }
    }
}

/// The Chrome row on its own, under Settings' checkbox for it.
struct BrowserConnectionUpgrade: View {
    var compact = false
    @ObservedObject private var cards = SetupCards.shared
    @State private var showGuide = false

    var body: some View {
        let _ = cards.revision
        UpgradeRows(cards.rows([.browserExtension], compact: compact), compact: compact) { _ in showGuide = true }
            .sheet(isPresented: $showGuide) { BrowserSetupGuide() }
    }
}
