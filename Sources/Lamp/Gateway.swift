import Foundation
import AppKit
import Network

/// A tiny HTTP server on 127.0.0.1 that lets generated apps use Lamp's AI
/// without ever seeing the key. Apps call it through `LampAI` (see Template.lampSupportSwift).
final class Gateway: @unchecked Sendable {
    static let port: UInt16 = Edition.gatewayPort

    struct Request {
        let method: String
        let path: String
        let headers: [String: String]   // lowercased names
        let body: Data
        /// Came in over the local network (an app on the person's phone) rather than from this Mac.
        var fromNetwork = false
        /// The port the request came from (host order), which tells Lamp which program on this Mac sent it.
        var peerPort: UInt16?
        /// The address it came from: for a request from the network, the device that sent it.
        var peerAddress: String?
        /// Asked by the app's page in the TV preview, through its bridge (`TVPreview`), never over a connection.
        var fromPreview = false
    }

    /// A file the gateway hands out as it is, not JSON: a TV app's phone page (`Store.phonePage`).
    struct Page {
        var status: Int
        var type = "text/plain; charset=utf-8"
        var body = Data()
        var location: String?
        /// What a phone's browser holds a phone page to (`PhonePagePolicy`).
        var policy: String?
    }

    private var listener: NWListener?
    private var networkListener: NWListener?
    private let queue = DispatchQueue(label: "dev.lamp.gateway")
    private let handler: @Sendable (Request) async -> (Int, [String: Any])
    private let pages: @Sendable (Request) async -> Page
    /// The port it answers on: Lamp's gateway's, or one app's phone page's (`PhoneSites`).
    let port: UInt16
    /// A site answers only pages, on every interface, each request marked by where it came from.
    private let isSite: Bool

    /// One app's phone page on a port of its own (`PhoneSites`): every request is a page, whatever its path. A phone's
    /// socket goes to the controllers' relay instead (`ControllerRelay`), never to Lamp.
    init(site port: UInt16, pages: @escaping @Sendable (Request) async -> Page) {
        self.port = port
        self.isSite = true
        self.handler = { _ in (404, ["error": "Not found"]) }
        self.pages = pages
    }

    init(handler: @escaping @Sendable (Request) async -> (Int, [String: Any]), pages: @escaping @Sendable (Request) async -> Page) {
        self.port = Self.port
        self.isSite = false
        self.handler = handler
        self.pages = pages
    }

    /// A site's one listener, on every interface: a request from this Mac's own loopback is told from one from the network.
    /// True once it's listening; false when it couldn't take its port, which `NWListener` says only after it starts.
    /// The port is never shared: another program listening there keeps it, and the site goes elsewhere.
    func startSite(onFailure: @escaping @Sendable () -> Void = {}) async -> Bool {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = false
        guard let listener = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!) else { return false }
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: self?.queue ?? .main)
            var loopback = false
            if case .hostPort(let host, _) = connection.endpoint {
                switch host {
                case .ipv4(let address): loopback = address.isLoopback
                case .ipv6(let address): loopback = address.isLoopback || address.asIPv4?.isLoopback == true
                default: break
                }
            }
            self?.receive(connection, buffer: Data(), fromNetwork: !loopback)
        }
        self.listener = listener
        return await withCheckedContinuation { continuation in
            var answered = false
            // The listener keeps this handler, so it holds the listener weakly, and lets go of both handlers (and the
            // callback with them) once the listener is done: a failed try or a closed site leaves nothing behind.
            listener.stateUpdateHandler = { [weak listener] state in
                switch state {
                case .ready:
                    if !answered { answered = true; continuation.resume(returning: true) }
                case .failed, .cancelled:
                    if !answered { answered = true; continuation.resume(returning: false) } else { onFailure() }
                    listener?.stateUpdateHandler = nil
                    listener?.newConnectionHandler = nil
                    listener?.cancel()
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        queue.async { [self] in
            listener?.cancel()
            networkListener?.cancel()
            listener = nil
            networkListener = nil
        }
    }

    func start() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: self?.queue ?? .main)
            self?.receive(connection, buffer: Data(), fromNetwork: false)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    /// Also answers on the local network, for apps on the person's own iPhone or iPad (chosen under Try
    /// On). Requests that come in this way are marked, and the handler lets them use only the
    /// app routes; the agent's stay on this Mac.
    func setLocalNetwork(_ on: Bool) {
        queue.async { [self] in
            if !on {
                networkListener?.cancel()
                networkListener = nil
                return
            }
            guard networkListener == nil else { return }
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            guard let listener = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.port)!) else { return }
            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: self?.queue ?? .main)
                self?.receive(connection, buffer: Data(), fromNetwork: true)
            }
            listener.start(queue: queue)
            networkListener = listener
        }
    }

    private func receive(_ connection: NWConnection, buffer: Data, fromNetwork: Bool) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, done, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if var request = Self.parse(buffer) {
                if request.method == "BAD" { self.respond(connection, status: 400, json: ["error": "Bad request"]); return }
                request.fromNetwork = fromNetwork
                if case .hostPort(let host, let port) = connection.endpoint {
                    request.peerPort = port.rawValue
                    switch host {
                    case .ipv4(let address): request.peerAddress = "\(address)"
                    case .ipv6(let address): request.peerAddress = address.asIPv4.map { "\($0)" } ?? "\(address)"
                    default: break
                    }
                }
                // A web app on a TV or a console asks before it sends a request with a token, as browsers do across
                // origins. Only over the network: nothing on this Mac is answered across origins.
                if fromNetwork, request.method == "OPTIONS" {
                    self.respond(connection, status: 204, json: [:], crossOrigin: true)
                    return
                }
                // A phone opening a TV app's page: plain files, read by a browser that came by following a link.
                if request.method == "GET" || request.method == "HEAD", self.isSite {
                    Task {
                        let page = await self.pages(request)
                        self.respond(connection, page: page, head: request.method == "HEAD")
                    }
                    return
                }
                Task {
                    let (status, json) = await self.handler(request)
                    self.respond(connection, status: status, json: json, crossOrigin: fromNetwork)
                }
            } else if done || error != nil || buffer.count > 40_000_000 {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer, fromNetwork: fromNetwork)
            }
        }
    }

    /// `crossOrigin` lets a web app on a device read the answer: the app's token is what's checked, never where its page
    /// came from, which is the device's own package.
    private func respond(_ connection: NWConnection, status: Int, json: [String: Any], crossOrigin: Bool = false) {
        // 202 is how the MCP endpoint acknowledges a notification, and 204 a preflight: no body.
        let body = status == 202 || status == 204 ? Data() : (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
        let reason = HTTPURLResponse.localizedString(forStatusCode: status).capitalized
        let cors = crossOrigin ? "Access-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: POST\r\nAccess-Control-Allow-Headers: Authorization, Content-Type\r\nAccess-Control-Max-Age: 600\r\n" : ""
        var response = Data("HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n\(cors)Connection: close\r\n\r\n".utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    /// A page as it is. Never cached, since the app's files change with every build, and never read as another type
    /// than the one given.
    private func respond(_ connection: NWConnection, page: Page, head: Bool) {
        let reason = HTTPURLResponse.localizedString(forStatusCode: page.status).capitalized
        let location = page.location.map { "Location: \($0)\r\n" } ?? ""
        let policy = page.policy.map { "Content-Security-Policy: \($0)\r\n" } ?? ""
        var response = Data(("HTTP/1.1 \(page.status) \(reason)\r\nContent-Type: \(page.type)\r\nContent-Length: \(page.body.count)\r\n\(location)\(policy)"
            + "Cache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n\r\n").utf8)
        if !head { response.append(page.body) }
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    /// Returns a request once the headers and the full body have arrived.
    private static func parse(_ data: Data) -> Request? {
        guard let split = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[..<split.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let start = lines.removeFirst().split(separator: " ")
        guard start.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        // A negative or absurd length is a malformed request, not one to wait for (prefix(-1) would trap).
        guard let length = Int(headers["content-length"] ?? "0"), (0...40_000_000).contains(length) else {
            return Request(method: "BAD", path: String(start[1]), headers: headers, body: Data())
        }
        let body = data[split.upperBound...]
        guard body.count >= length else { return nil }
        return Request(method: String(start[0]), path: String(start[1]), headers: headers, body: Data(body.prefix(length)))
    }
}

/// Runs an in-app AI request with whatever Lamp is connected to.
enum AppAI {
    /// Where an app's text AI goes: a model through OpenRouter, or the Claude Code or Codex sign-in. Settings and
    /// an app's own choice keep the id.
    struct TextRoute: Identifiable, Equatable {
        enum Kind: Equatable {
            case openRouter(model: String)
            case engine(Engine, model: String)   // Claude Code or Codex with one of its models
        }
        let id: String
        /// The model with what runs it ("Opus via Claude Code"): captions and the per-app panel.
        let label: String
        /// For the menus, where the routes sit under their provider: the provider's name and the model's.
        let group: String
        let name: String
        let kind: Kind
        /// Whether this route can answer right now: the key or the tool it needs is there.
        /// Worked out when the list is made, on the main thread.
        let available: Bool

        /// The OpenRouter model that stands in for this route where only OpenRouter can answer (an app on a
        /// phone away from the Mac): the route's own model, else the usual default.
        var openRouter: String {
            if case .openRouter(let model) = kind { return model }
            return AppAI.anthropicModels.first { $0.id == "sonnet" }!.openRouter
        }

        @MainActor static func make(id: String, group: String, name: String, via: String? = nil, kind: Kind) -> TextRoute {
            let available: Bool
            switch kind {
            case .openRouter: available = Provider.hasKey
            // pi builds through OpenRouter, a route of its own.
            case .engine(.pi, _): available = false
            // Installed, and not known to be signed out: a signed-out sign-in can't answer, and the setup offer
            // should be to sign in rather than to say it's set up.
            case .engine(let engine, _): available = EngineInstall.path(for: engine) != nil && EngineSignIn.known[engine] != false
            }
            return TextRoute(id: id, label: "\(name) via \(via ?? group)", group: group, name: name, kind: kind, available: available)
        }
    }

    /// Sonnet through OpenRouter: what Lamp's own calls use when there's a key.
    static var defaultOpenRouterModel: String { anthropicModels.first { $0.id == "sonnet" }!.openRouter }

    /// The link's id of the page shared on lamp.dev this request is for (`SharedPagesAI`), nil for an app of the
    /// person's own. A shared page is someone else's code: it never gets a route that runs an engine's own tools, which
    /// for now is picture-making through Codex (`viaCodexImage`). Its answers from Claude Code and Codex are sealed as
    /// every app's are (`viaEngine`).
    @TaskLocal static var sharedPage: String?

    /// The OpenRouter model for Lamp's own text-only calls (an app's name and parts, the next-message
    /// suggestion, a version's title): Sonnet.
    @MainActor static func helperModel() async -> String? {
        defaultOpenRouterModel
    }

    /// Whether a helper's answer is one of its own prompt's examples handed back, which small models do when
    /// they can't work one out: a tip calculator's version titled "Added account shortcuts". That counts as
    /// no answer, unless the person's own words say the same (asked for a stopwatch, "Stopwatch" is its name).
    nonisolated static func parrots(_ answer: String, examples: [String], asked: String = "") -> Bool {
        func plain(_ text: String) -> String {
            text.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
        }
        let answer = plain(answer)
        guard examples.contains(where: { plain($0) == answer }) else { return false }
        return !" \(plain(asked)) ".contains(" \(answer) ")
    }

    /// The models OpenRouter offers for apps; Sonnet is the default among them (Haiku is cheaper but
    /// noticeably worse, so it's only used when someone picks it).
    static let anthropicModels: [Provider.ListedModel] = [
        Provider.ListedModel(id: "claude-fable-5-2", name: "Claude Fable", blurb: "Smartest, priciest", openRouter: "anthropic/claude-fable-5.2"),
        Provider.ListedModel(id: "opus", name: "Claude Opus", blurb: "Best at coding", openRouter: "anthropic/claude-opus-5.5"),
        Provider.ListedModel(id: "sonnet", name: "Claude Sonnet", blurb: "Faster & cheaper", openRouter: "anthropic/claude-sonnet-5.5"),
        Provider.ListedModel(id: "haiku", name: "Claude Haiku", blurb: "Fastest, cheapest", openRouter: "anthropic/claude-haiku-5.5"),
    ]

    /// Every route there is, whether or not it can answer right now; the pickers show the ones that can,
    /// plus whatever is chosen.
    @MainActor static var allTextRoutes: [TextRoute] {
        var routes = anthropicModels.map { TextRoute.make(id: $0.id, group: "OpenRouter", name: $0.label, kind: .openRouter(model: $0.openRouter)) }
        // The sign-ins, one route per model they offer (Claude Code's short names; the models Codex lists).
        for model in Builder.claudeModels where !model.id.isEmpty {
            routes.append(.make(id: "engine:claude:\(model.id)", group: Engine.claude.title, name: model.label, kind: .engine(.claude, model: model.id)))
        }
        // Codex lists its models once it has run; until then its default, with no model named, is the route.
        let codexModels = Builder.codexModels.filter { !$0.id.isEmpty }
        if codexModels.isEmpty {
            routes.append(.make(id: "engine:codex", group: Engine.codex.title, name: "ChatGPT's default model", kind: .engine(.codex, model: "")))
        }
        for model in codexModels {
            routes.append(.make(id: "engine:codex:\(model.id)", group: Engine.codex.title, name: model.label, kind: .engine(.codex, model: model.id)))
        }
        return routes
    }

    /// The routes a picker shows, under their providers in the order the routes come.
    @MainActor static func textRouteGroups(including chosen: String?) -> [(title: String, routes: [TextRoute])] {
        var groups: [(title: String, routes: [TextRoute])] = []
        for route in textRoutes(including: chosen) {
            if let index = groups.firstIndex(where: { $0.title == route.group }) { groups[index].routes.append(route) }
            else { groups.append((route.group, [route])) }
        }
        return groups

    }

    /// What the pickers offer: the routes that can answer now, and the chosen one even if it can't (so a
    /// choice isn't silently lost when a key or model goes), in that order.
    /// A route id as saved by an earlier Lamp, when the sign-ins were one route each with no model, read as
    /// today's: Sonnet through Claude Code, Codex's first model.
    @MainActor static func canonicalRoute(_ id: String) -> String {
        switch id {
        case "engine:claude": return "engine:claude:sonnet"
        case "engine:codex": return Builder.codexModels.first { !$0.id.isEmpty }.map { "engine:codex:\($0.id)" } ?? id
        // A model named by its earlier id, in an app's own choice or its code, is today's.
        default: return Builder.currentModel(id)
        }
    }

    @MainActor static func textRoutes(including chosen: String?) -> [TextRoute] {
        let routes = allTextRoutes.filter(\.available)
        let chosen = chosen.map(canonicalRoute)
        if let chosen, !routes.contains(where: { $0.id == chosen }), let kept = allTextRoutes.first(where: { $0.id == chosen }) {
            return routes + [kept]
        }
        return routes
    }

    /// The route apps use when nothing was chosen: OpenRouter's Sonnet with a key, else the builder's own
    /// sign-in, else the first thing that can answer.
    @MainActor static var defaultRoute: TextRoute {
        let routes = allTextRoutes
        func route(_ id: String) -> TextRoute? { routes.first { $0.id == id && $0.available } }
        if let sonnet = route("sonnet") { return sonnet }
        // The builder's own sign-in: Sonnet through Claude Code (never Haiku unasked), Codex's best model.
        switch Builder.engine {
        case .claude: if let route = route("engine:claude:sonnet") { return route }
        case .codex: if let route = route(canonicalRoute("engine:codex")) { return route }
        case .pi: break
        }
        return routes.first(where: \.available) ?? routes.first { $0.id == "sonnet" }!
    }

    /// The OpenRouter model an app on the person's phone uses away from the Mac, where only OpenRouter can
    /// answer: Settings' choice, else the chosen route's own model when that's through OpenRouter, else Sonnet.
    @MainActor static var awayModel: Provider.ListedModel {
        let saved = Builder.currentModel(UserDefaults.standard.string(forKey: "awayModel") ?? "")
        if let chosen = anthropicModels.first(where: { $0.id == saved }) { return chosen }
        if case .openRouter(let name) = model.kind, let same = anthropicModels.first(where: { $0.openRouter == name }) { return same }
        return anthropicModels.first { $0.id == "sonnet" }!
    }

    /// The same for one app: its own choice (one an earlier Lamp let it make), else Settings'.
    @MainActor static func awayModel(for choice: String?) -> Provider.ListedModel {
        anthropicModels.first { $0.id == choice.map(Builder.currentModel) } ?? awayModel
    }

    /// The image model an app on the phone uses away from the Mac: Settings' choice, else the Mac's own
    /// choice, else the first cloud model.
    @MainActor static var awayImageModel: String {
        let saved = UserDefaults.standard.string(forKey: "awayImageModel") ?? ""
        if Icons.artModels.contains(where: { $0.id == saved }) { return saved }
        let macs = Icons.artModel
        return Icons.artModels.contains(where: { $0.id == macs }) ? macs : Icons.artModels[0].id
    }

    @MainActor static func awayImageModel(for choice: String?) -> String {
        Icons.artModels.contains { $0.id == choice } ? choice! : awayImageModel
    }

    /// What a phone can decide with on its own, through the OpenRouter key it carries: Jev, or the text model
    /// it uses away, asked the questions as JSON.
    static var awayDecisionModels: [(id: String, label: String, provider: String, model: String)] {
        [("openrouter:jev-latest", "Jev", "openrouter", "jev-latest"), ("text", "By text, through the text model above", "text", "")]
    }

    /// The decision model an app on the phone uses away from the Mac: Settings' choice, else by text when
    /// that's the Mac's choice too, else Jev.
    @MainActor static var awayDecisionModel: (id: String, label: String, provider: String, model: String) {
        let saved = UserDefaults.standard.string(forKey: "awayDecisionModel") ?? ""
        return awayDecisionModels.first { $0.id == saved } ?? awayDecisionModels.first { $0.id == decisionModel.id } ?? awayDecisionModels[0]
    }

    @MainActor static func awayDecisionModel(for choice: String?) -> (id: String, label: String, provider: String, model: String) {
        awayDecisionModels.first { $0.id == choice } ?? awayDecisionModel
    }

    /// The route Settings chose for apps, when it can still answer; else the default.
    @MainActor static var model: TextRoute { route(for: UserDefaults.standard.string(forKey: "appModel")) }

    /// The text route for one app: its own choice (one an earlier Lamp let it make), or Settings', when it can answer; else the
    /// default.
    @MainActor static func route(for choice: String?) -> TextRoute {
        chosenRoute(for: choice) ?? defaultRoute
    }

    /// What was chosen for an app's text, by the app or in Settings, when it can answer; nil when nobody chose.
    @MainActor private static func chosenRoute(for choice: String?) -> TextRoute? {
        let choice = choice.map(canonicalRoute)
        if let choice, let route = allTextRoutes.first(where: { $0.id == choice }), route.available { return route }
        if let saved = UserDefaults.standard.string(forKey: "appModel").map(canonicalRoute), saved != choice,
           let route = allTextRoutes.first(where: { $0.id == saved }), route.available { return route }
        return nil
    }

    /// The route for a task done with the person's other apps (`ComputerUse`): what was chosen for the app's
    /// text, when something was; else `computerDefault`, which isn't the text default.
    @MainActor static func computerRoute(for choice: String?) -> TextRoute {
        chosenRoute(for: choice)
            ?? computerDefault(among: allTextRoutes, builder: Builder.engine, textDefault: defaultRoute, hasKey: Provider.hasKey)
    }

    /// The OpenRouter model for those tasks when a key is all there is. Chosen by running one task in TextEdit
    /// (a new document, a sentence, its font and color) through Lamp's own loop: this one did it in 38
    /// seconds for 5 cents, Opus in 93 seconds for 96 cents, Gemini Flash in 156 seconds for 22 cents, and
    /// Sonnet, the text default, not at all. It isn't one of the models offered for apps' text.
    static let computerOpenRouterModel = (id: "openai/gpt-6.1-sol", name: "GPT-6.1 Sol")

    /// The route for a task in other apps when nobody chose one. Such a task is many steps of reading a
    /// window and acting on it, and the text default did it badly: Sonnet through OpenRouter took minutes,
    /// finished wrong and cost dollars a run, where the sign-ins did it right in about a minute. So a
    /// sign-in comes first (the one that builds apps, then the other; Opus through Claude Code, which did
    /// the task where Sonnet didn't), then the OpenRouter model that did, and whatever else answers text is the
    /// last resort.
    nonisolated static func computerDefault(among routes: [TextRoute], builder: Engine, textDefault: TextRoute, hasKey: Bool) -> TextRoute {
        for engine in builder == .claude ? [Engine.claude, .codex] : [.codex, .claude] {
            let own = routes.first { route in
                guard route.available, case .engine(engine, let model) = route.kind else { return false }
                return engine == .codex || model == "opus"   // Codex's are listed best first
            }
            if let own { return own }
        }
        guard hasKey else { return textDefault }
        let model = computerOpenRouterModel
        return TextRoute(id: "computer:openrouter", label: "\(model.name) via OpenRouter", group: "OpenRouter", name: model.name,
                         kind: .openRouter(model: model.id), available: true)
    }

    struct Failure: LocalizedError {
        let message: String
        /// What was billed before the failure (both JSON attempts, say), so the app's usage still counts it.
        var cost: Double = 0
        /// Set when the failure is that nothing is set up to answer: the gateway tells the app, and Lamp
        /// offers the person a way to set it up in the app's chat.
        var needs: Capability? = nil
        /// Whoever shows this as any other error shows the message, not "The operation couldn't be completed".
        var errorDescription: String? { message }
    }

    /// Whether apps' text AI can answer: some route can, the same test the pickers and `resolve` use.
    @MainActor static var canAnswer: Bool { allTextRoutes.contains(where: \.available) }

    /// Returns the model's text and what the call cost in USD.
    /// An image from the app: `media_type` (e.g. image/jpeg) and base64 `data`.
    struct Image {
        let mediaType: String
        let data: String
    }

    /// `model` overrides the in-app model (an OpenRouter model ID), e.g. for Lamp's own import review.
    /// `appModel` is an app's own text model (an id from `models`), when it has one.
    /// `schema` is a JSON Schema the reply must fit. OpenRouter holds the model to it; the other routes
    /// can't, so a caller that depends on the shape still checks the reply.
    /// `via` is a route the caller has already settled on, for one that must know what answered: the call
    /// goes that way or fails, and nothing is looked up again.
    /// `timeLimit` ends a call through Claude Code or Codex that hasn't answered by then, for a caller that would
    /// rather have no answer than wait on a stuck one: their runs have no limit of their own, where the routes over
    /// the network give up by themselves.
    static func complete(prompt: String, images: [Image], system: String, json: Bool,
                         model: String? = nil, appModel: String? = nil, engineModel: String? = nil,
                         schema: [String: Any]? = nil, via: TextRoute? = nil, timeLimit: TimeInterval? = nil) async throws -> (String, Double) {
        let chosen: TextRoute
        if let via { chosen = via } else { chosen = await route(for: appModel) }
        var system = system
        if json { system += "\n\nRespond with only valid JSON. No prose, no code fences." }
        var (text, cost) = try await dispatch(prompt: prompt, images: images, system: system, json: json, model: model, chosen: chosen, engineModel: engineModel, schema: schema, timeLimit: timeLimit)
        guard json else { return (text, cost) }
        // A JSON reply that doesn't parse (cut off, or wrapped in prose) is useless to the app: ask once more,
        // through the same provider, saying so, before giving up. Both attempts are billed, so the cost goes
        // with the failure too.
        var reply = stripFences(text)
        if !isJSON(reply) {
            let again = "\(prompt)\n\nYour previous reply was not valid JSON (it may have been cut off). Reply with the complete JSON only."
            do {
                let (retry, more) = try await dispatch(prompt: again, images: images, system: system, json: true, model: model, chosen: chosen, engineModel: engineModel, schema: schema, timeLimit: timeLimit)
                cost += more
                reply = stripFences(retry)
            } catch let failure as Failure {
                throw Failure(message: failure.message, cost: cost)
            } catch {
                throw Failure(message: error.localizedDescription, cost: cost)
            }
            if !isJSON(reply) {
                throw Failure(message: "The AI's reply wasn't valid JSON, even on a second try. Ask for less at once.", cost: cost)
            }
        }
        return (reply, cost)
    }

    /// One request along the route: `model` names an OpenRouter model to use instead of the route's own, for
    /// Lamp's own calls (the icon judge, suggestions) when there's a key; `engineModel` likewise names the
    /// model for Claude Code or Codex (the fast one for decisions by text).
    private static func dispatch(prompt: String, images: [Image], system: String, json: Bool, model: String?,
                                 chosen: TextRoute, engineModel: String? = nil, schema: [String: Any]? = nil,
                                 timeLimit: TimeInterval? = nil) async throws -> (String, Double) {
        if let model, Provider.hasKey {
            return try await viaOpenRouter(prompt: prompt, images: images, system: system, model: model, json: json, schema: schema)
        }
        switch chosen.kind {
        case .openRouter(let model):
            guard Provider.hasKey else { throw Failure(message: noTextRoute, needs: .text) }
            return try await viaOpenRouter(prompt: prompt, images: images, system: system, model: model, json: json, schema: schema)
        case .engine(.pi, _):
            throw Failure(message: noTextRoute, needs: .text)
        case .engine(let engine, let model):
            return try await viaEngine(engine, prompt: prompt, images: images, system: system, model: engineModel ?? model,
                                       schema: json ? schema : nil, timeLimit: timeLimit)
        }
    }

    private static func isJSON(_ text: String) -> Bool {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])) != nil
    }

    /// The failure an app gets when nothing can answer its text: Lamp offers a way in the app's chat.
    static let noTextRoute = "Apps' AI features need an OpenRouter key, or a working builder. Set one up in Lamp → Settings (⌘,)."

    /// One answer from Claude Code or Codex, with the person's own sign-in (and so their subscription), run by lamp's
    /// command line (`engineAnswer`, cli/ai.mjs), the one place that runs them for an app's AI: sealed every time, with
    /// none of the person's setup and none of the engine's tools, so nothing on the Mac is read or run whatever the
    /// prompt asks. Pictures go with the request itself, never through a tool that reads files. Which copy of the engine
    /// runs, and what it needs set, are decided here (`EngineInstall`). A cancelled caller stops the run with it.
    static func viaEngine(_ engine: Engine, prompt: String, images: [Image],
                          system: String, model: String, schema: [String: Any]? = nil,
                          timeLimit: TimeInterval? = nil) async throws -> (String, Double) {
        guard engine != .pi else { throw Failure(message: noTextRoute, needs: .text) }
        var env = ["PATH": ToolLocator.userPath]
        env.merge(EngineInstall.environment(for: engine)) { $1 }
        var given: [String: Any] = ["engine": engine == .codex ? "codex" : "claude", "tool": EngineInstall.path(for: engine) ?? "",
                                    "env": env, "system": system, "prompt": prompt,
                                    "images": images.map { ["media_type": $0.mediaType, "data": $0.data] }]
        // Claude Code takes its own aliases ("sonnet", "opus") or a full id. Only one of Codex's own models is passed on;
        // an Anthropic id (an app built before Codex answered for it) means Codex's default.
        if engine == .claude || Builder.codexModels.contains(where: { $0.id == model && !model.isEmpty }) { given["model"] = model }
        if let schema { given["schema"] = schema }
        if let timeLimit { given["seconds"] = timeLimit }
        let done = try await LampCLI.ask("engineAnswer", given)
        try Task.checkCancellation()
        if let text = done["text"] as? String { return (text, 0) }   // the person's sign-in: nothing billed through Lamp
        let trouble = done["trouble"] as? [String: Any] ?? [:]
        let message = trouble["message"] as? String ?? "The AI didn't answer."
        switch trouble["kind"] as? String {
        case "failed": throw Failure(message: Provider.friendlyError(message, from: engine.title))
        case "stopped": throw CancellationError()
        default: throw Failure(message: message)
        }
    }

    /// One answer for Lamp's own reading of text someone else wrote (`SuggestionSummaries`), only along a way that can't
    /// act. Never `complete`, which can hand the call to an engine unsealed. Nil when none of these can answer:
    /// - OpenRouter with the person's key: text in, text out.
    /// - Claude Code and Codex only through the run proven for answers beside a turn (`SideAnswer.Run`): a version that run
    ///   was tested on, launched with no tools (Claude Code started afresh, `claudeFreshArguments`; Codex with its model's
    ///   catalog entry edited), its own report of what it was given checked before a word is taken (Claude Code's must
    ///   list no tools and no MCP servers), and a tool tried stopping that version for good, with every run of it going.
    ///   `viaEngine`'s sealed launches have the flags without that check, so neither is used here.
    /// What comes back says which engine and version answered, so the caller can ask again before keeping it.
    struct ToolFreeAnswer {
        var text: String
        var cost: Double
        var engine: Engine? = nil
        var version = ""

        /// Still showable: an engine's answer whose version hasn't been stopped since by any run of it.
        var stillGood: Bool { engine.map { !SideAnswer.isStopped($0, version: version) } ?? true }
    }

    @MainActor static func toolFreeAvailable() async -> Bool {
        if Provider.hasKey, await helperModel() != nil { return true }
        guard model.available else { return false }
        switch model.kind {
        case .openRouter, .engine(.pi, _): return false
        case .engine(let engine, _): return answerRoute(engine, model: "") != nil
        }
    }

    @MainActor static func toolFree(prompt: String, system: String, schema: [String: Any], for project: LampProject) async throws -> ToolFreeAnswer? {
        if Provider.hasKey, let helper = await helperModel() {
            let (text, cost) = try await viaOpenRouter(prompt: prompt, images: [], system: system, model: helper, json: true, schema: schema)
            return ToolFreeAnswer(text: text, cost: cost)
        }
        let chosen = model
        guard chosen.available else { return nil }
        switch chosen.kind {
        case .openRouter, .engine(.pi, _): return nil
        case .engine(let engine, let name):
            guard var route = answerRoute(engine, model: fastModel(for: chosen) ?? name) else { return nil }
            // Claude Code takes the system prompt as its own; Codex's proven launch has none, so what it's told goes first
            // in what it's asked.
            route.system = system
            let run = SideAnswer.Run(message: UUID(), engine: engine)
            let outcome = await run.answer(engine == .codex ? system + "\n\n" + prompt : prompt, route: route, transcript: nil, in: project)
            guard SideAnswer.mayShow(outcome, engine: engine), let reply = outcome.reply else { return nil }
            return ToolFreeAnswer(text: reply, cost: 0, engine: engine, version: outcome.version)
        }
    }

    /// Claude Code or Codex as `SideAnswer` runs it; nil when it isn't here. Codex always on the model it was proven with.
    @MainActor static func answerRoute(_ engine: Engine, model: String) -> SideAnswer.Route? {
        guard engine != .pi, let executable = EngineInstall.path(for: engine) else { return nil }
        return SideAnswer.Route(engine: engine, executable: executable, configFolder: EngineInstall.configFolder(engine).path,
                                model: engine == .codex ? SideAnswer.testedCodexModel : model, system: "", path: ToolLocator.userPath,
                                environment: EngineInstall.environment(for: engine))
    }

    // MARK: Decisions (System One models such as Jev)

    /// Where decisions go: Jev through OpenRouter, or a small text model answering as JSON (`decideByText`).
    static let decisionModels: [(id: String, label: String, provider: String, model: String)] = [
        ("openrouter:jev-latest", "Jev via OpenRouter", "openrouter", "jev-latest"),
        ("text", "By text, through what answers apps", "text", ""),
    ]

    static var decisionModel: (id: String, label: String, provider: String, model: String) {
        let saved = UserDefaults.standard.string(forKey: "decisionModel") ?? ""
        if let chosen = decisionModels.first(where: { $0.id == saved }) { return chosen }
        return decisionModels[0]
    }

    /// Whether a decision model can answer now: its key; by text whenever the app's text route (`appText`,
    /// else Settings') can.
    @MainActor static func canDecide(with choice: (id: String, label: String, provider: String, model: String),
                                      appText: String? = nil) -> Bool {
        switch choice.provider {
        case "text": route(for: appText).available
        default: KeyStore.key(for: choice.provider) != nil
        }
    }

    /// What answers for a choice (an app's own, else Settings'): the choice when it can, else the first
    /// decision model that can, else the text model as JSON when something answers, else nil. `decide`,
    /// `resolve(.decisions)` and Settings all go by this, so what they name is what really answers.
    @MainActor static func decisionRoute(for appChoice: String?, appText: String? = nil) -> (id: String, label: String, provider: String, model: String)? {
        let wanted = decisionModels.first { $0.id == appChoice } ?? decisionModel
        if canDecide(with: wanted, appText: appText) { return wanted }
        return decisionModels.first { $0.provider == "openrouter" && canDecide(with: $0, appText: appText) }
            ?? decisionModels.first { $0.provider == "text" && canDecide(with: $0, appText: appText) }
    }

    /// Sends `state` and typed `questions` (the System One format) to the decision model.
    /// Returns the answers keyed like the questions, and the cost in USD.
    /// `appText` is the app's own text choice: decisions made by text go along it, as the app's text does.
    static func decide(state: Any, questions: [String: Any],
                       model appChoice: String? = nil, appText: String? = nil) async throws -> ([String: Any], Double) {
        guard let choice = await decisionRoute(for: appChoice, appText: appText) else {
            throw Failure(message: "Decisions need an OpenRouter key. Add one in Lamp → Settings (⌘,) → AI Providers.", needs: .decisions)
        }
        if choice.provider == "text" { return try await decideByText(state: state, questions: questions, appText: appText) }
        guard let key = KeyStore.key(for: choice.provider) else {
            // Gone since the route was chosen: the text model answers the same questions in JSON instead.
            return try await decideByText(state: state, questions: questions, appText: appText)
        }
        // Sent by lamp's command line (`openRouterDecide`, cli/openrouter.mjs), which backs off and asks again when the
        // model is busy.
        let done = try await LampCLI.ask("openRouterDecide", ["key": key, "model": choice.model, "state": state, "questions": questions])
        if let answers = done["answers"] as? [String: Any] { return (answers, done["cost"] as? Double ?? 0) }
        throw openRouterFailure(done["trouble"] as? [String: Any] ?? [:], from: Provider.keyProvider(choice.provider)?.name ?? choice.provider)
    }

    /// The small model for quick judgments on the route that will run them: Haiku 5.5 when Claude Code
    /// answers, Luna 6 when Codex does; any other route uses its own model.
    static func fastModel(for route: TextRoute) -> String? {
        switch route.kind {
        case .engine(.claude, _): Builder.claudeFastModel
        case .engine(.codex, _): Builder.codexFastModel
        default: nil
        }
    }

    /// What the fallback for decisions is called in Settings: the fast model on the apps' text route.
    @MainActor static var fastModelName: String { fastModelName(for: model) }

    /// The same for one route: an app's own text choice.
    @MainActor static func fastModelName(for model: TextRoute) -> String {
        switch model.kind {
        case .engine(.claude, _): "Haiku 5.5 through Claude"
        case .engine(.codex, _): (Builder.codexModels.first { $0.id == Builder.codexFastModel }?.label).map { "\($0) through ChatGPT" } ?? "ChatGPT"
        default: model.label.replacingOccurrences(of: "Your ", with: "your ")
        }
    }

    /// Decisions without a decision model: the questions go to a small text model as JSON, and its answers
    /// come back in the same shape Jev's would (`noul`, `choice`/`score` with `probabilities` and
    /// `confidence`), checked against each question so an app can't be handed a made-up option.
    static func decideByText(state: Any, questions: [String: Any], appText: String? = nil) async throws -> ([String: Any], Double) {
        // What the model is told and how its answer is read is lamp's command line's (cli/app-ai.mjs), which lamp's own
        // answers use too: worded for a small model, and held to the answers' shape where the route takes a schema.
        let asked = try await LampCLI.ask("decideAsk", ["state": state, "questions": questions])
        let fast = await fastModel(for: route(for: appText))
        let (text, cost) = try await complete(prompt: asked["prompt"] as? String ?? "", images: [], system: asked["system"] as? String ?? "",
                                              json: true, appModel: appText, engineModel: fast, schema: asked["schema"] as? [String: Any])
        let read = try await LampCLI.ask("decideRead", ["text": text, "questions": questions])
        guard let answers = read["answers"] as? [String: Any] else {
            throw Failure(message: read["problem"] as? String ?? "The model's decision wasn't valid JSON.", cost: cost)
        }
        return (answers, cost)
    }

    /// Where images come from: OpenRouter's image models with a key; otherwise Codex's own image tool, with a
    /// ChatGPT sign-in; otherwise nothing, and Lamp asks the first time an app wants a picture. (Apple's on-device Image Playground has no
    /// programmatic API any more: ImageCreator stopped working in macOS 27.)
    enum ImageRoute { case openRouter, codex }

    /// The route for pictures, as far as can be told without asking anything: OpenRouter with a key, else Codex
    /// when it's chosen and was last known to be signed in.
    /// `imageRoute(…)` asks Codex first; this is the one rule both follow, and the one `resolve` reports.
    @MainActor static func pictureRoute(choice: String? = nil, appText: String? = nil, editing: Bool = false) -> ImageRoute? {
        if Provider.hasKey { return .openRouter }
        // Never for a page shared on lamp.dev: Codex makes a picture with its own tools (`viaCodexImage`).
        if sharedPage == nil, codexChosen(appText: appText), EngineInstall.path(for: .codex) != nil, EngineSignIn.known[.codex] != false { return .codex }
        return nil
    }

    /// The route for Settings' choices, for its text.
    @MainActor static var imageRoute: ImageRoute? { pictureRoute() }

    /// Codex draws pictures only when the person chose it for something: to build apps, to answer inside
    /// them, or as this one app's own text choice. A Codex sign-in that merely happens to be on the Mac isn't
    /// spent on pictures.
    private static func codexChosen(appText: String? = nil) -> Bool {
        Builder.engine == .codex || (UserDefaults.standard.string(forKey: "appModel") ?? "").hasPrefix("engine:codex")
            || (appText ?? "").hasPrefix("engine:codex")
    }

    /// The route to act on. Codex counts only when it's chosen (above) and signed in (a copy can be
    /// there before anyone has signed in to it: Lamp's, or the one inside the ChatGPT app); that's checked at most every few minutes.
    static func imageRoute(editing: Bool = false, appText: String? = nil, choice: String? = nil) async -> ImageRoute? {
        if codexChosen(appText: appText), EngineInstall.path(for: .codex) != nil {
            let last = await MainActor.run { EngineSignIn.checked[.codex] }
            if Date().timeIntervalSince(last ?? .distantPast) > 300 { _ = await EngineSignIn.isSignedIn(.codex) }
        }
        return await pictureRoute(choice: choice, appText: appText, editing: editing)
    }


    /// What's making images, for Settings.
    @MainActor static var imageRouteName: String? { imageRoute.map(imageRouteName) }

    @MainActor static func imageRouteName(_ route: ImageRoute) -> String {
        switch route {
        case .openRouter: "OpenRouter"
        case .codex: "ChatGPT, with your sign-in"
        }
    }

    /// The failure an app gets when nothing can make images: Lamp shows a card asking for a key or a download.
    static let noImageRoute = "Making images needs an OpenRouter key. Add one in Lamp → Settings (⌘,)."

    /// Creates or edits an image. `references` are input images to edit or combine. Returns PNG data and
    /// the cost in USD (0 through Codex).
    static func image(prompt: String, references: [Image], aspectRatio: String?,
                      model appChoice: String? = nil, appText: String? = nil) async throws -> (Data, Double) {
        switch await imageRoute(editing: !references.isEmpty, appText: appText, choice: appChoice) {
        case .openRouter: break
        case .codex: return (try await viaCodexImage(prompt: prompt, references: references, aspectRatio: aspectRatio), 0)
        case nil: throw Failure(message: noImageRoute, needs: .pictures)
        }
        // Sent by lamp's command line (`openRouterImage`, cli/openrouter.mjs); what comes back is checked here as a picture.
        let imageModel = Icons.artModels.contains { $0.id == appChoice } ? appChoice! : Icons.artModel
        var given: [String: Any] = ["key": KeyStore.openRouterKey ?? "", "model": imageModel, "prompt": prompt,
                                    "references": references.map { ["media_type": $0.mediaType, "data": $0.data] }]
        if let aspectRatio { given["aspectRatio"] = aspectRatio }
        let done = try await LampCLI.ask("openRouterImage", given)
        guard let base64 = done["image"] as? String else { throw openRouterFailure(done["trouble"] as? [String: Any] ?? [:]) }
        guard let decoded = Data(base64Encoded: base64), NSImage(data: decoded) != nil else {
            throw Failure(message: "The image model didn't return a picture.")
        }
        return (decoded, done["cost"] as? Double ?? 0)
    }

    /// Codex makes the picture with its built-in image tool and saves it in a scratch folder; reference
    /// images are attached and named in the prompt. Takes about a minute.
    private static func viaCodexImage(prompt: String, references: [Image], aspectRatio: String?) async throws -> Data {
        // Codex makes a picture by running its own tools in a folder, which a shared page's request never gets.
        guard sharedPage == nil else {
            throw Failure(message: "Pictures for a page shared on lamp.dev can't be made with ChatGPT. Choose another picture AI in \(Edition.name).")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-image-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var files: [String] = []
        for (index, image) in references.enumerated() {
            guard let data = Data(base64Encoded: image.data) else { continue }
            let name = "reference\(index + 1).\(image.mediaType.hasSuffix("png") ? "png" : "jpg")"
            try data.write(to: folder.appendingPathComponent(name))
            files.append(name)
        }
        var request = "Create an image and save it as image.png in the current folder, then reply with just: done.\n\n"
        request += "The image: \(prompt)"
        if let aspectRatio { request += "\n\nAspect ratio \(aspectRatio)." }
        if !files.isEmpty {
            request += "\n\nUse the attached \(files.count == 1 ? "image" : "images") (\(files.joined(separator: ", "))) as "
                + (files.count == 1 ? "the reference: edit or build on it as the description says." : "references.")
        }
        var env: [String: String] = ["PATH": ToolLocator.userPath, "LAMP_TOOL": EngineInstall.path(for: .codex) ?? "codex",
                                     "LAMP_PROMPT": request]
        env.merge(EngineInstall.environment(for: .codex)) { $1 }
        for (index, file) in files.enumerated() { env["LAMP_FILE_\(index)"] = file }
        let imageArgs = files.indices.map { "-i \"$LAMP_FILE_\($0)\"" }.joined(separator: " ")
        let command = """
        "$LAMP_TOOL" exec --json --ignore-user-config --ignore-rules --skip-git-repo-check --ephemeral \\
          -c sandbox_mode="workspace-write" -c hooks={} -C "$PWD" \(imageArgs) -- "$LAMP_PROMPT"
        """
        var failure: String?
        _ = await Shell.run(command, cwd: folder, env: env) { line in
            for case .failed(let message) in Agent.parse(line, engine: .codex) { failure = message }
        }
        if let failure { throw Failure(message: Provider.friendlyError(failure, from: Engine.codex.title)) }
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("image.png")), NSImage(data: data) != nil else {
            throw Failure(message: "ChatGPT didn't make the picture. Check it's signed in (Lamp → Settings → Building).")
        }
        return data
    }

    /// A text answer from OpenRouter with the person's key, sent by lamp's command line (`openRouterText`,
    /// cli/openrouter.mjs), which `lamp dev` and `lamp ai` send with too: with `json`, a JSON object with room for a long
    /// one, fitting `schema` when there is one, and asked again when a provider's content filter cuts the reply off.
    private static func viaOpenRouter(prompt: String, images: [Image], system: String,
                                      model: String, json: Bool = false, schema: [String: Any]? = nil) async throws -> (String, Double) {
        var given: [String: Any] = ["key": KeyStore.openRouterKey ?? "", "prompt": prompt, "system": system, "model": model, "json": json,
                                    "images": images.map { ["media_type": $0.mediaType, "data": $0.data] }]
        if let schema { given["schema"] = schema }
        let done = try await LampCLI.ask("openRouterText", given)
        if let text = done["text"] as? String { return (text, done["cost"] as? Double ?? 0) }
        throw openRouterFailure(done["trouble"] as? [String: Any] ?? [:])
    }

    /// What kept OpenRouter from answering, as the app is told it, with what it cost all the same.
    static func openRouterFailure(_ trouble: [String: Any], from name: String = Provider.openRouter) -> Failure {
        let cost = trouble["cost"] as? Double ?? 0
        if trouble["kind"] as? String == "refused", let status = trouble["status"] as? Int, status > 0 {
            return Failure(message: Provider.friendlyError(status: status, reply: trouble["reply"] as? [String: Any] ?? [:], from: name), cost: cost)
        }
        return Failure(message: trouble["message"] as? String ?? "The AI didn't answer.", cost: cost)
    }

    static func stripFences(_ text: String) -> String {
        var t = text.trimmed
        if t.hasPrefix("```") {
            t = String(t.drop(while: { $0 != "\n" }).dropFirst())
            if let end = t.range(of: "```", options: .backwards) { t = String(t[..<end.lowerBound]) }
        }
        return t.trimmed
    }
}
