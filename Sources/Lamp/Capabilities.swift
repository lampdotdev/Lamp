import SwiftUI

/// What apps ask AI for. Each one can be answered by several providers, some better than others, and this
/// is the one place that says which answers now, how well, and what would make it better: the gateway, the
/// chat's setup card, Settings, the agent's status line and the keys a phone takes away all read it.
enum Capability: String, CaseIterable, Codable, Identifiable {
    case text, decisions, pictures

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "Text"
        case .decisions: "Decisions"
        case .pictures: "Pictures"
        }
    }

    var symbol: String {
        switch self {
        case .text: "text.bubble"
        case .decisions: "checklist"
        case .pictures: "photo.on.rectangle.angled"
        }
    }
}

/// Where the app is when it asks: on this Mac (or near it), or an app on the person's phone away from it,
/// where only what the phone can carry (an OpenRouter key and model choices) can answer. `icon` is Lamp
/// itself asking, for the artwork of an app's icon: pictures, with one more way to get them, since for an
/// icon the person can be the one who draws.
enum AIContext: Equatable { case mac, phoneAway, icon }

/// Something the person can do to make a capability better, shown the same way in the chat and in Settings.
enum Upgrade: Hashable, Identifiable {
    /// A key for a provider that takes one ("openrouter", "typesafe", "openai").
    case key(String)
    /// The picture model on this Mac (the first of `ImageModels.catalog`), with mflux if it's missing.
    case pictureModel
    /// The decision model on this Mac (`LocalModels.decisionCatalog`).
    case decisionModel
    case signIn(Engine)
    /// Drawing each app's icon by hand in Image Playground (`Icons.byHand`): for icon artwork only, and
    /// only on a Mac that has it.
    case drawIcons

    var id: String {
        switch self {
        case .key(let provider): "key:\(provider)"
        case .pictureModel: "pictureModel"
        case .decisionModel: "decisionModel"
        case .signIn(let engine): "signIn:\(engine.rawValue)"
        case .drawIcons: "drawIcons"
        }
    }
}

/// How a capability is answered for one app, right now.
struct Resolution: Equatable {
    enum Tier: Int, Comparable {
        /// Nothing can answer: the app gets an error.
        case none
        /// Something answers, but not what was chosen, or slower and less exact than it could be.
        case works
        /// What the person chose, or the best there is.
        case best

        static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }
    }

    let capability: Capability
    let tier: Tier
    /// What answers, as the person would say it ("Sonnet via OpenRouter"); nil when nothing can.
    let answer: String?
    /// The Providers row doing the work, for its badges: "openrouter", `Builder.localProvider`, "engine:codex"…
    /// For icon artwork the person draws themselves it's `Icons.byHand`, which is no row there.
    let provider: String?
    /// Why it isn't the best it could be, in a sentence the person can read as it is, without repeating
    /// `answer`; nil when it is.
    let note: String?

    /// The note with what answers meanwhile, for where `answer` isn't shown beside it.
    var explanation: String? {
        guard let note else { return nil }
        guard tier == .works, let answer else { return note }
        return "For now, \(answer) answers. \(note)"
    }
    /// What would make it better, best first. Empty when nothing would.
    let upgrades: [Upgrade]
}

extension AppAI {
    /// How `capability` is answered for `project` (nil: Settings' choices) in `context`. The routes themselves
    /// are made where they're dispatched (`route(for:)`, `pictureRoute`, `decisionModels`); this says what they
    /// amount to, so nothing else has to work that out again.
    @MainActor static func resolve(_ capability: Capability, for project: LampProject? = nil, in context: AIContext = .mac) -> Resolution {
        let models = project.map(AppModels.load) ?? AppModels()
        switch (capability, context) {
        // Only pictures are asked for an icon; the others are answered as for the app on this Mac.
        case (.text, .mac), (.text, .icon): return resolveText(choice: models.text)
        case (.decisions, .mac), (.decisions, .icon): return resolveDecisions(choice: models.decision, text: models.text)
        case (.pictures, .mac): return resolvePictures(choice: models.image, text: models.text)
        case (.pictures, .icon): return resolveIconArt()
        case (_, .phoneAway): return resolveAway(capability, models: models)
        }
    }

    /// Whether the person draws each app's icon themselves: what answers icon artwork is them.
    @MainActor static var iconsByHand: Bool { resolve(.pictures, in: .icon).provider == Icons.byHand }

    /// A few words on a capability, for the agent: "Sonnet via OpenRouter", "nothing can answer yet".
    @MainActor static func summary(_ resolution: Resolution) -> String {
        switch resolution.tier {
        case .none: "nothing can answer yet"
        case .best: resolution.answer ?? ""
        case .works: "\(resolution.answer ?? "") (\(resolution.note ?? "it could be better"))"
        }
    }

    // MARK: Each capability

    @MainActor private static func resolveText(choice: String?) -> Resolution {
        let route = route(for: choice)
        guard route.available else {
            return Resolution(capability: .text, tier: .none, answer: nil, provider: nil,
                              note: "Nothing on this Mac can answer apps yet.", upgrades: textUpgrades)
        }
        // What was asked for: the app's own choice, else Settings'. A choice that can't answer right now (its
        // key or model went) is why the route is a stand-in.
        let wanted = (choice ?? UserDefaults.standard.string(forKey: "appModel")).map(canonicalRoute)
        if let wanted, wanted != route.id, let missing = allTextRoutes.first(where: { $0.id == wanted }) {
            var upgrades: [Upgrade] = []
            var why = "."
            switch missing.kind {
            case .openRouter:
                upgrades.append(.key("openrouter"))
                why = " without an OpenRouter key."
            case .engine(let engine, _) where engine != .pi && EngineInstall.path(for: engine) != nil:
                upgrades.append(.signIn(engine))
                why = " until you sign in to \(engine.title) again."
            default: break
            }
            return Resolution(capability: .text, tier: .works, answer: route.label, provider: provider(of: route),
                              note: "\(missing.name) can't answer right now\(why)",
                              upgrades: upgrades)
        }
        // A sign-in that answers because nothing was chosen works, but a key is quicker for small calls and
        // goes with an app to a phone. Chosen on purpose, it's what the person wants.
        if wanted == nil, case .engine = route.kind, !Provider.hasKey {
            return Resolution(capability: .text, tier: .works, answer: route.label, provider: provider(of: route),
                              note: "An OpenRouter key answers small requests faster, and goes with apps to your phone.",
                              upgrades: [.key("openrouter")])
        }
        return Resolution(capability: .text, tier: .best, answer: route.label, provider: provider(of: route), note: nil, upgrades: [])
    }

    /// What would let apps' text answer when nothing can: a key, then signing in to Claude Code or Codex where
    /// it's installed (what builds apps first). An installed one that's signed in would already be answering.
    @MainActor private static var textUpgrades: [Upgrade] {
        let engines = ([Builder.engine] + [.claude, .codex]).filter { $0 != .pi }
        var upgrades: [Upgrade] = [.key("openrouter")]
        for engine in engines where EngineInstall.path(for: engine) != nil && !upgrades.contains(.signIn(engine)) {
            upgrades.append(.signIn(engine))
        }
        return upgrades
    }

    @MainActor private static func resolveDecisions(choice: String?, text: String?) -> Resolution {
        let chosen = decisionModels.first { $0.id == choice } ?? decisionModel
        // Decisions by text go along the app's own text route (`AppAI.decide(appText:)`), so they're named by it.
        let textRoute = resolveText(choice: text)
        let byText = "\(fastModelName(for: route(for: text))), answering as text"
        // Why the chosen one can't answer, and what would let it.
        let why: String
        let wants: [Upgrade]
        switch chosen.provider {
        case "text": (why, wants) = ("Nothing can answer apps yet", [])
        case "local": (why, wants) = ("\(LocalModels.decisionCatalog.first?.name ?? "The decision model") isn't on this Mac yet", [.decisionModel])
        default: (why, wants) = ("\(chosen.label) needs \(keyPhrase(chosen.provider))", [.key(chosen.provider)])
        }
        // What `decide` will use: the choice, else another decision model that can, else text.
        guard let used = decisionRoute(for: choice, appText: text) else {
            return Resolution(capability: .decisions, tier: .none, answer: nil, provider: nil,
                              note: "\(why).", upgrades: wants + textRoute.upgrades.filter { !wants.contains($0) })
        }
        let answer = used.provider == "text" ? byText : used.label
        let provider = used.provider == "text" ? textRoute.provider : used.provider == "local" ? Builder.localProvider : used.provider
        if used.id == chosen.id {
            return Resolution(capability: .decisions, tier: .best, answer: answer, provider: provider, note: nil, upgrades: [])
        }
        return Resolution(capability: .decisions, tier: .works, answer: answer, provider: provider,
                          note: used.provider == "text" ? "\(why). Until then they're made by text: slower and less exact." : "\(why).",
                          upgrades: wants)
    }

    @MainActor private static func resolvePictures(choice: String?, text: String?) -> Resolution {
        let route = pictureRoute(choice: choice, appText: text)
        let upgrades: [Upgrade] = [.key("openrouter"), .pictureModel]
        guard let route else {
            return Resolution(capability: .pictures, tier: .none, answer: nil, provider: nil,
                              note: "Nothing on this Mac can make pictures yet.", upgrades: upgrades)
        }
        let answer = imageRouteName(route)
        let provider: String = switch route {
        case .openRouter: "openrouter"
        case .local: Builder.localProvider
        case .codex: "engine:codex"
        }
        // A cloud model chosen with no key behind it isn't what makes the pictures: something else stands in.
        let wanted = choice ?? UserDefaults.standard.string(forKey: "imageModel")
        if route != .openRouter, let wanted, let cloud = Icons.artModels.first(where: { $0.id == wanted }) {
            return Resolution(capability: .pictures, tier: .works, answer: answer, provider: provider,
                              note: "\(cloud.label) needs an OpenRouter key.",
                              upgrades: [.key("openrouter")])
        }
        return Resolution(capability: .pictures, tier: .best, answer: answer, provider: provider, note: nil, upgrades: [])
    }

    /// The artwork of an app's icon. It's Lamp's own request, so no app's choices apply: whatever makes
    /// pictures by Settings' choices draws it, unless the person chose to draw icons themselves in Image
    /// Playground, which then is what answers, key or no key. Where nothing can draw, that choice is one
    /// more way to get icons (on a Mac that has Image Playground: `UpgradeView.isOffered`).
    @MainActor private static func resolveIconArt() -> Resolution {
        if Icons.drawnByHand(choice: Icons.iconChoice, available: Icons.playgroundAvailable) {
            return Resolution(capability: .pictures, tier: .best, answer: Icons.byHandLabel, provider: Icons.byHand,
                              note: nil, upgrades: [])
        }
        let pictures = resolvePictures(choice: nil, text: nil)
        guard pictures.tier == .none else { return pictures }
        return Resolution(capability: .pictures, tier: .none, answer: nil, provider: nil, note: pictures.note,
                          upgrades: pictures.upgrades + [.drawIcons])
    }

    /// Away from the Mac a phone answers with what it carries: the OpenRouter key, and a TypeSafe key for
    /// decisions when they go there.
    @MainActor private static func resolveAway(_ capability: Capability, models: AppModels) -> Resolution {
        guard Provider.hasKey else {
            return Resolution(capability: capability, tier: .none, answer: nil, provider: nil,
                              note: "Apps on your phone can use AI only near this Mac.", upgrades: [.key("openrouter")])
        }
        switch capability {
        case .text:
            return Resolution(capability: .text, tier: .best, answer: "\(awayModel(for: models.away).label) via OpenRouter",
                              provider: "openrouter", note: nil, upgrades: [])
        case .pictures:
            let model = awayImageModel(for: models.awayImage)
            return Resolution(capability: .pictures, tier: .best, answer: Icons.artModels.first { $0.id == model }?.label ?? model,
                              provider: "openrouter", note: nil, upgrades: [])
        case .decisions:
            let decision = awayDecisionModel(for: models.awayDecision)
            if decision.provider != "text", decision.provider != "openrouter", KeyStore.key(for: decision.provider) == nil {
                return Resolution(capability: .decisions, tier: .works, answer: "By text, through OpenRouter", provider: "openrouter",
                                  note: "\(decision.label) needs \(keyPhrase(decision.provider)).",
                                  upgrades: [.key(decision.provider)])
            }
            return Resolution(capability: .decisions, tier: .best, answer: decision.label,
                              provider: decision.provider == "text" ? "openrouter" : decision.provider, note: nil, upgrades: [])
        }
    }

    /// "an OpenRouter key", "a TypeSafe key".
    @MainActor static func keyPhrase(_ provider: String) -> String {
        let name = Provider.keyProvider(provider)?.name ?? provider
        return "\("AEIOU".contains(name.prefix(1)) ? "an" : "a") \(name) key"
    }

    /// The Providers row behind a text route.
    @MainActor static func provider(of route: TextRoute) -> String {
        switch route.kind {
        case .openRouter: "openrouter"
        case .engine(.pi, _): Builder.piProvider
        case .engine(let engine, _): "engine:\(engine.rawValue)"
        case .localModel(let provider, _): provider
        }
    }
}

// MARK: - The setup offer in the chat

/// A setup offer in an app's chat: which capability, and whether it's about the app on a phone away from
/// the Mac. Kept on the chat line (`LogLine.offer`).
struct SetupOffer: Codable, Equatable, Hashable {
    let capability: Capability
    var away: Bool? = nil
    /// The card is about the app's own icon (Lamp wanted artwork for it), not something the app tried.
    /// Cards from before this was noted don't say.
    var icon: Bool? = nil

    var context: AIContext { away == true ? .phoneAway : icon == true ? .icon : .mac }

    /// One card per capability per app, on this Mac or away, whatever raised it: an app whose icon card is
    /// in the chat isn't given another when it tries to make a picture, so `icon` is no part of which offer
    /// this is.
    static func == (a: SetupOffer, b: SetupOffer) -> Bool { a.capability == b.capability && (a.away == true) == (b.away == true) }
    func hash(into hasher: inout Hasher) {
        hasher.combine(capability)
        hasher.combine(away == true)
    }

    /// "Not Now" is remembered for the app it was said in, and for every app: Lamp doesn't raise the same
    /// offer by itself elsewhere. The agent may still raise it in another app, with a reason of its own.
    private static let declinedKey = "declinedSetupOffers"
    private var key: String { capability.rawValue + (away == true ? "@away" : "") }

    func declined(in project: LampProject?) -> Bool {
        let declined = Set(UserDefaults.standard.stringArray(forKey: Self.declinedKey) ?? [])
        return project.map { declined.contains("\($0.id) \(key)") } ?? declined.contains(key)
    }

    func decline(in project: LampProject) {
        var declined = Set(UserDefaults.standard.stringArray(forKey: Self.declinedKey) ?? [])
        declined.insert(key)
        declined.insert("\(project.id) \(key)")
        UserDefaults.standard.set(Array(declined).sorted(), forKey: Self.declinedKey)
    }
}

// MARK: - What the agent is told

/// The line on what AI an app has, at the end of a request, so the agent builds for what's there (and
/// offers what isn't with `offer_setup`). Like Memory's summaries it rides with the request rather than the
/// system prompt, which Claude Code and Codex keep from a conversation's start; and like them it's sent once
/// per conversation and again only when it changes, so most requests carry nothing.
enum AIStatus {
    @MainActor static func line(for project: LampProject, offered: Set<SetupOffer>) -> String {
        var lines = Capability.allCases.map { capability in
            let resolution = AppAI.resolve(capability, for: project)
            var line = "- \(capability.title): \(AppAI.summary(resolution))"
            if resolution.tier != .best, offered.contains(SetupOffer(capability: capability)) { line += "; Lamp has offered the person a way to set it up" }
            return line
        }
        if project.platform == .iphone {
            let away = AppAI.resolve(.text, for: project, in: .phoneAway)
            lines.append("- On the person's phone away from this Mac: \(away.tier == .none ? "no AI" : "text, pictures and decisions through OpenRouter")")
        }
        return lines.joined(separator: "\n")
    }

    @MainActor static func brief(for project: LampProject, engine: Engine, session: String?, offered: Set<SetupOffer>) -> String {
        let now = line(for: project, offered: offered)
        let known = session.flatMap { session in
            shown(in: project)[engine.rawValue].flatMap { $0.session == session || $0.session.isEmpty ? $0 : nil }
        }
        // Codex doesn't say when it compacts, so its conversations are told again every so many requests.
        let stale = engine == .codex && (known?.requests ?? 0) >= 8
        let fresh = known == nil || known?.forgot == true || stale
        pending[project.id] = Shown(engine: engine.rawValue, session: session ?? "", line: now,
                                    requests: fresh ? 1 : (known?.requests ?? 0) + 1)
        if fresh {
            return "\n\n---\nAI this app can use right now (from Lamp, not part of the request above):\n\(now)"
        }
        guard known?.line != now else { return "" }
        return "\n\n---\nThe AI this app can use has changed (from Lamp, not part of the request above):\n\(now)"
    }

    /// The agent answered, so the request and the line in it arrived.
    @MainActor static func delivered(to project: LampProject, session: String? = nil) {
        guard var run = pending[project.id] else { return }
        if let session { run.session = session; pending[project.id] = run }
        var all = shown(in: project)
        all[run.engine] = run
        try? JSONEncoder().encode(all).write(to: file(project), options: .atomic)
    }

    /// The engine summed up its conversation: the line may be gone from it, so the next request says it again.
    @MainActor static func compacted(_ project: LampProject) { pending[project.id]?.forgot = true }

    private struct Shown: Codable {
        var engine: String
        var session: String
        var line: String
        var requests: Int
        var forgot: Bool?
    }

    @MainActor private static var pending: [String: Shown] = [:]

    private static func file(_ project: LampProject) -> URL { project.dir.appendingPathComponent(".lamp/ai-shown.json") }

    private static func shown(in project: LampProject) -> [String: Shown] {
        (try? Data(contentsOf: file(project))).flatMap { try? JSONDecoder().decode([String: Shown].self, from: $0) } ?? [:]
    }
}
