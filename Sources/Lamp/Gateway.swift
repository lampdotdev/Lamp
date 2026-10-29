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
        var response = Data(("HTTP/1.1 \(page.status) \(reason)\r\nContent-Type: \(page.type)\r\nContent-Length: \(page.body.count)\r\n\(location)"
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
    /// Where an app's text AI goes: a model through OpenRouter, the Claude Code or Codex sign-in, or a model
    /// running on this Mac. Settings and an app's own choice keep the id.
    struct TextRoute: Identifiable, Equatable {
        enum Kind: Equatable {
            case openRouter(model: String)
            case engine(Engine, model: String)   // Claude Code or Codex with one of its models
            case localModel(provider: String, model: String)   // Native Mac AI
        }
        let id: String
        /// The model with what runs it ("Opus via Claude Code"): captions and the per-app panel.
        let label: String
        /// For the menus, where the routes sit under their provider: the provider's name and the model's.
        let group: String
        let name: String
        let kind: Kind
        /// Whether this route can answer right now: the key, the tool or the model it needs is there.
        /// Worked out when the list is made, on the main thread, where the local models live.
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
            // pi builds through OpenRouter or a model on this Mac, each a route of its own.
            case .engine(.pi, _): available = false
            // Installed, and not known to be signed out: a signed-out sign-in can't answer, and the setup offer
            // should be to sign in rather than to say it's set up.
            case .engine(let engine, _): available = EngineInstall.path(for: engine) != nil && EngineSignIn.known[engine] != false
            case .localModel(_, let model): available = LocalModels.shared.installed.contains { $0.id == model }
            }
            return TextRoute(id: id, label: "\(name) via \(via ?? group)", group: group, name: name, kind: kind, available: available)
        }
    }

    /// Sonnet through OpenRouter: what Lamp's own calls use when there's a key.
    static var defaultOpenRouterModel: String { anthropicModels.first { $0.id == "sonnet" }!.openRouter }

    /// The OpenRouter model for Lamp's own text-only calls (an app's name and parts, the next-message
    /// suggestion, a version's title): Sonnet, unless apps' text goes to a model on this Mac. Someone who
    /// chose to stay local gets nil here, so these calls follow that route instead of leaving the Mac.
    @MainActor static func helperModel() async -> String? {
        if case .localModel = model.kind { return nil }
        return defaultOpenRouterModel
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
        Provider.ListedModel(id: "claude-fable-5-1", name: "Claude Fable", blurb: "Smartest, priciest", openRouter: "anthropic/claude-fable-5.1"),
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
        for model in LocalModels.shared.installed where !LocalModels.isDecisionModel(model.id) {
            routes.append(.make(id: "local:\(model.id)", group: "Native Mac AI", name: model.name, via: "Native Mac AI on this Mac",
                                kind: .localModel(provider: Builder.localProvider, model: model.id)))
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
        default: return id
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

    /// The route apps use when nothing was chosen: what builds apps when that's a model on this Mac (someone
    /// who chose to stay local keeps staying local), else OpenRouter's Sonnet with a key, else the builder's
    /// own sign-in, else the first thing that can answer.
    @MainActor static var defaultRoute: TextRoute {
        let routes = allTextRoutes
        func route(_ id: String) -> TextRoute? { routes.first { $0.id == id && $0.available } }
        if Builder.engine == .pi, Builder.piProvider == Builder.localProvider, let local = route("local:\(Builder.piModel)") {
            return local
        }
        if let sonnet = route("sonnet") { return sonnet }
        // The builder's own sign-in: Sonnet through Claude Code (never Haiku unasked), Codex's best model.
        switch Builder.engine {
        case .claude: if let route = route("engine:claude:sonnet") { return route }
        case .codex: if let route = route(canonicalRoute("engine:codex")) { return route }
        case .pi: break
        }
        // Never a model on this Mac by default: it's for those who choose it (here, or pi building with it, above).
        return routes.first { route in
            if case .localModel = route.kind { return false }
            return route.available
        } ?? routes.first { $0.id == "sonnet" }!
    }

    /// The OpenRouter model an app on the person's phone uses away from the Mac, where only OpenRouter can
    /// answer: Settings' choice, else the chosen route's own model when that's through OpenRouter, else Sonnet.
    @MainActor static var awayModel: Provider.ListedModel {
        let saved = UserDefaults.standard.string(forKey: "awayModel") ?? ""
        if let chosen = anthropicModels.first(where: { $0.id == saved }) { return chosen }
        if case .openRouter(let name) = model.kind, let same = anthropicModels.first(where: { $0.openRouter == name }) { return same }
        return anthropicModels.first { $0.id == "sonnet" }!
    }

    /// The same for one app: its own choice (info panel), else Settings'.
    @MainActor static func awayModel(for choice: String?) -> Provider.ListedModel {
        anthropicModels.first { $0.id == choice } ?? awayModel
    }

    /// The image model an app on the phone uses away from the Mac: Settings' choice, else the Mac's own
    /// choice when that's a cloud model, else the first cloud model. The model on this Mac can't travel.
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
    /// it uses away, asked the questions as JSON. The Mac's own model stays here.
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

    /// The text route for one app: its own choice (info panel), or Settings', when it can answer; else the
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
    /// the task where Sonnet didn't), then the OpenRouter model that did. Someone staying on this Mac's own
    /// models stays there, and whatever else answers text is the last resort.
    nonisolated static func computerDefault(among routes: [TextRoute], builder: Engine, textDefault: TextRoute, hasKey: Bool) -> TextRoute {
        if case .localModel = textDefault.kind { return textDefault }
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
        case .localModel(_, let model):
            let base = try await LocalModels.shared.ensureServer(for: model)
            return try await viaOpenAICompatible("\(base)/v1/chat/completions", key: nil,
                                                 prompt: prompt, images: images, system: system, model: model, schema: json ? schema : nil)
        }
    }

    private static func isJSON(_ text: String) -> Bool {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])) != nil
    }

    /// The failure an app gets when nothing can answer its text: Lamp offers a way in the app's chat.
    static let noTextRoute = "Apps' AI features need an OpenRouter key, or a working builder. Set one up in Lamp → Settings (⌘,)."

    /// One-shot answer from an external coding agent, using the user's own sign-in (and so their subscription).
    /// Isolated from their setup like a build turn, with no tools except reading the images it's given.
    /// `sealed` takes Codex's own tools away too (commands, web search, connectors, sub-agents) and refuses any
    /// approval, for a caller whose answer decides what an app does next (`AppAct`): Claude Code's `--restricted`
    /// with no tools already leaves it nothing to run.
    static func viaEngine(_ engine: Engine, prompt: String, images: [Image],
                          system: String, model: String, schema: [String: Any]? = nil,
                          timeLimit: TimeInterval? = nil, sealed: Bool = false) async throws -> (String, Double) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-ai-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var files: [String] = []
        for (index, image) in images.enumerated() {
            guard let data = Data(base64Encoded: image.data) else { continue }
            let name = "image\(index).\(image.mediaType.hasSuffix("png") ? "png" : "jpg")"
            try data.write(to: folder.appendingPathComponent(name))
            files.append(name)
        }
        var env: [String: String] = ["PATH": ToolLocator.userPath, "LAMP_TOOL": EngineInstall.path(for: engine) ?? "",
                                     "LAMP_SYSTEM": system.isEmpty ? "You are a helpful assistant inside an app." : system,
                                     "LAMP_PROMPT": prompt]
        env.merge(EngineInstall.environment(for: engine)) { $1 }
        for (index, file) in files.enumerated() { env["LAMP_FILE_\(index)"] = file }
        // A JSON schema the answer must fit: Claude Code takes it as text, Codex as a file.
        var schemaArg = ""
        if let schema, let data = try? JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys]) {
            env["LAMP_SCHEMA"] = String(decoding: data, as: UTF8.self)
            if engine == .codex { try data.write(to: folder.appendingPathComponent("schema.json")) }
            schemaArg = engine == .codex ? "--output-schema schema.json " : "--json-schema \"$LAMP_SCHEMA\" "
        }
        let command: String
        switch engine {
        case .claude:
            // Claude Code takes images by reading them, so it gets the Read tool and their names.
            if !files.isEmpty { env["LAMP_PROMPT"] = prompt + "\n\n(Images: " + files.joined(separator: ", ") + ". Read them.)" }
            env["LAMP_MODEL"] = model   // Claude Code's own aliases ("sonnet", "opus") or a full model id
            command = """
            "$LAMP_TOOL" -p "$LAMP_PROMPT" --output-format stream-json --verbose --no-session-persistence \\
              --restricted --strict-mcp-config --disable-slash-commands \\
              --tools \(files.isEmpty ? "''" : "Read --allowedTools Read") --model "$LAMP_MODEL" \(schemaArg)--system-prompt "$LAMP_SYSTEM"
            """
        case .codex:
            env["LAMP_CODEX_INSTRUCTIONS"] = "developer_instructions="
                + Agent.tomlString(env["LAMP_SYSTEM"]! + "\n\nAnswer directly. Don't run commands or change files.")
            let imageArgs = files.indices.map { "-i \"$LAMP_FILE_\($0)\"" }.joined(separator: " ")
            // Only one of Codex's own models is passed on; an Anthropic id (an app built before Codex
            // answered for it) means Codex's default.
            var modelArg = ""
            if Builder.codexModels.contains(where: { $0.id == model && !model.isEmpty }) {
                env["LAMP_MODEL"] = model
                modelArg = "-m \"$LAMP_MODEL\" "
            }
            // Every key here is one of Codex's documented settings; --ignore-user-config already leaves out the
            // person's MCP servers.
            let seal = sealed ? #"-c approval_policy="never" -c features.shell_tool=false -c features.unified_exec=false -c web_search="disabled" -c features.apps=false -c features.multi_agent=false "# : ""
            command = """
            "$LAMP_TOOL" exec --json --ignore-user-config --ignore-rules --skip-git-repo-check --ephemeral \\
              -s read-only -c hooks={} -c model_reasoning_effort="low" \(seal)\(modelArg)\(schemaArg)-c "$LAMP_CODEX_INSTRUCTIONS" \(imageArgs) -- "$LAMP_PROMPT"
            """
        case .pi:
            throw Failure(message: noTextRoute, needs: .text)
        }
        var text = ""
        var cost = 0.0
        var failure: String?
        final class Deadline { var passed = false }
        let deadline = Deadline()
        let status = await Shell.run(command, cwd: folder, env: env, started: { process in
            guard let timeLimit else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeLimit))
                guard process.isRunning else { return }
                deadline.passed = true
                // The whole tree, killed if it won't stop: a child left holding the output, or an engine that
                // ignores the signal, would keep the call waiting past its limit all the same.
                Subprocess.terminateTree(process)
            }
        }) { line in
            // With a schema, Claude Code gives the answer in its result, not as a message.
            if schema != nil, engine == .claude, line.contains("\"structured_output\""),
               let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any], obj["type"] as? String == "result",
               let answer = obj["structured_output"], let data = try? JSONSerialization.data(withJSONObject: answer) {
                text = String(decoding: data, as: UTF8.self)
                return
            }
            for event in Agent.parse(line, engine: engine) {
                switch event {
                case .text(let chunk): text = chunk   // the last message is the answer
                case .cost(let amount): cost += amount
                case .failed(let message): failure = message
                default: break
                }
            }
        }
        if deadline.passed { throw Failure(message: "\(engine.title) took too long to answer.") }
        if let failure { throw Failure(message: Provider.friendlyError(failure, from: engine.title)) }
        guard !text.isEmpty else {
            throw Failure(message: status == 0 ? "The AI didn't answer." : "\(engine.title) didn't answer. Check it's signed in.")
        }
        return (text, cost)
    }

    /// Chat completion against an OpenAI-compatible endpoint: Lamp's own model servers on this Mac.
    /// `timeout` is for a caller with a deadline of its own; otherwise a model has time to load first.
    /// `templateArgs` go to the model's chat template (llama.cpp's `chat_template_kwargs`).
    static func viaOpenAICompatible(_ endpoint: String, key: String?, prompt: String, images: [Image],
                                    system: String, model: String, schema: [String: Any]? = nil,
                                    timeout: TimeInterval = 600, templateArgs: [String: Any]? = nil) async throws -> (String, Double) {
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var messages: [[String: Any]] = []
        if !system.trimmed.isEmpty { messages.append(["role": "system", "content": system]) }
        let content: [[String: Any]] = [["type": "text", "text": prompt]] + images.map {
            ["type": "image_url", "image_url": ["url": "data:\($0.mediaType);base64,\($0.data)"]]
        }
        messages.append(["role": "user", "content": content])
        var body: [String: Any] = ["model": model, "messages": messages]
        if let schema { body["response_format"] = ["type": "json_schema", "json_schema": ["name": "answer", "strict": true, "schema": schema]] }
        if let templateArgs { body["chat_template_kwargs"] = templateArgs }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let choices = obj["choices"] as? [[String: Any]],
              let text = (choices.first?["message"] as? [String: Any])?["content"] as? String else {
            let message = (obj["error"] as? [String: Any])?["message"] as? String ?? "The local model didn't answer."
            throw Failure(message: message)
        }
        // Reasoning models may wrap their thinking in <think>…</think>; apps only want the answer.
        let answer = text.replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
        return (answer.trimmed, 0)
    }

    // MARK: Decisions (System One models such as Jev)

    /// Where decisions go: Jev through OpenRouter, a decision model on this Mac, or a small text model
    /// answering as JSON (`decideByText`).
    static let decisionModels: [(id: String, label: String, provider: String, model: String)] = [
        ("openrouter:jev-latest", "Jev via OpenRouter", "openrouter", "jev-latest"),
        ("local:h2o-lightning-4b", "H2O Lightning 4B on this Mac", "local", "h2o-lightning-4b"),
        ("text", "By text, through what answers apps", "text", ""),
    ]

    /// The decision model on this Mac, as installed (its id for the local server), or nil.
    @MainActor static func localDecisionModel() -> String? {
        guard let spec = LocalModels.decisionCatalog.first else { return nil }
        return LocalModels.shared.installedID(for: spec)
    }

    static var decisionModel: (id: String, label: String, provider: String, model: String) {
        let saved = UserDefaults.standard.string(forKey: "decisionModel") ?? ""
        if let chosen = decisionModels.first(where: { $0.id == saved }) { return chosen }
        return decisionModels[0]
    }

    /// Whether a decision model can answer now: its key, or its download for the one on this Mac; by text
    /// whenever the app's text route (`appText`, else Settings') can.
    @MainActor static func canDecide(with choice: (id: String, label: String, provider: String, model: String),
                                      appText: String? = nil) -> Bool {
        switch choice.provider {
        case "text": route(for: appText).available
        case "local": localDecisionModel() != nil
        default: KeyStore.key(for: choice.provider) != nil
        }
    }

    /// What answers for a choice (an app's own, else Settings'): the choice when it can, else the first
    /// decision model that can, else the text model as JSON when something answers, else nil. `decide`,
    /// `resolve(.decisions)` and Settings all go by this, so what they name is what really answers.
    @MainActor static func decisionRoute(for appChoice: String?, appText: String? = nil) -> (id: String, label: String, provider: String, model: String)? {
        let wanted = decisionModels.first { $0.id == appChoice } ?? decisionModel
        if canDecide(with: wanted, appText: appText) { return wanted }
        // Not the model on this Mac unless it's the one chosen: it's for those who choose it.
        return decisionModels.first { $0.provider == "openrouter" && canDecide(with: $0, appText: appText) }
            ?? decisionModels.first { $0.provider == "text" && canDecide(with: $0, appText: appText) }
    }

    /// Sends `state` and typed `questions` (the System One format) to the decision model.
    /// Returns the answers keyed like the questions, and the cost in USD.
    /// `appText` is the app's own text choice: decisions made by text go along it, as the app's text does.
    static func decide(state: Any, questions: [String: Any],
                       model appChoice: String? = nil, appText: String? = nil) async throws -> ([String: Any], Double) {
        guard let choice = await decisionRoute(for: appChoice, appText: appText) else {
            let wanted = decisionModels.first { $0.id == appChoice } ?? decisionModel
            if wanted.provider == "local" {
                throw Failure(message: "The decision model on this Mac isn't downloaded yet. Get it in Lamp → Settings (⌘,) → AI Providers → Native Mac AI.", needs: .decisions)
            }
            throw Failure(message: "Decisions need an OpenRouter key. Add one in Lamp → Settings (⌘,) → AI Providers.", needs: .decisions)
        }
        if choice.provider == "text" { return try await decideByText(state: state, questions: questions, appText: appText) }
        if choice.provider == "local", let id = await localDecisionModel() {
            return try await decideLocally(state: state, questions: questions, model: id)
        }
        guard let key = KeyStore.key(for: choice.provider) else {
            // Gone since the route was chosen: the text model answers the same questions in JSON instead.
            return try await decideByText(state: state, questions: questions, appText: appText)
        }
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/systemone")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Lamp", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["state": state, "model": choice.model,
                                                                       "questions": questions] as [String: Any])
        // Rate limits (429) and overload (529) are expected under load: back off and retry a few times.
        for attempt in 0..<4 {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            if (status == 429 || status == 529) && attempt < 3 {
                try await Task.sleep(for: .milliseconds(500 << attempt))
                continue
            }
            guard status == 200, let answers = obj["answers"] as? [String: Any] else {
                let error = obj["error"] as? [String: Any]
                let detail = error?["message"] as? String ?? obj["detail"].map { "\($0)" } ?? "HTTP \(status)"
                throw Failure(message: status == 422 ? "The decision request was invalid: \(detail)"
                                                     : Provider.friendlyError(status: status, reply: obj, from: Provider.keyProvider(choice.provider)?.name ?? choice.provider))
            }
            let usage = obj["usage"] as? [String: Any] ?? [:]
            // Jev charges per input token ($0.042 per million); OpenRouter may report the exact cost.
            let cost = usage["cost"] as? Double ?? Double(usage["input_tokens"] as? Int ?? 0) * 0.042 / 1_000_000
            return (answers, cost)
        }
        throw Failure(message: "The decision model is busy. Try again in a moment.")
    }

    /// The state as the decision models read it: text as it is, anything else as JSON.
    private static func stateText(_ state: Any) -> String {
        if let text = state as? String { return text }
        return (try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys, .fragmentsAllowed]))
            .map { String(decoding: $0, as: UTF8.self) } ?? "\(state)"
    }

    /// Each question's options, in order: for a choice the criteria's names (with descriptions); for a
    /// score the levels, lowest first; for a noul true then false.
    private static func options(of question: [String: Any]) -> [(name: String, description: String)] {
        switch question["type"] as? String {
        case "noul":
            let criteria = question["criteria"] as? [String: Any] ?? [:]
            return [("true", criteria["true"] as? String ?? "Yes"), ("false", criteria["false"] as? String ?? "No")]
        case "score":
            return (question["criteria"] as? [String] ?? []).map { ($0, "") }
        default:
            if let dict = question["criteria"] as? [String: Any] {
                return dict.keys.sorted().map { ($0, dict[$0] as? String ?? "") }
            }
            return (question["criteria"] as? [String] ?? []).map { ($0, "") }
        }
    }

    /// A Jev-class model on this Mac, through the local server, the way its serving shim does it: one
    /// question per forward pass, the record and the lettered options in a chat prompt ending in "Answer:",
    /// and the probabilities read off the label tokens at that slot (softmax over their log-probabilities
    /// at the model's temperature), with the shim's confidence and the floor it holds yes/no answers to.
    static func decideLocally(state: Any, questions: [String: Any], model: String) async throws -> ([String: Any], Double) {
        let base = try await LocalModels.shared.ensureServer(for: model)
        let labels = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz").map(String.init)
        let record = stateText(state)
        var answers: [String: Any] = [:]
        for (id, value) in questions {
            guard let question = value as? [String: Any] else { continue }
            let options = options(of: question)
            guard !options.isEmpty, options.count <= labels.count else { throw Failure(message: "The question \"\(id)\" has no options, or too many.") }
            let lines = options.enumerated().map { index, option in
                "\(labels[index])) \(option.name)" + (option.description.isEmpty ? "" : ": \(option.description)")
            }
            let user = "record: \(record)\nquestion: \(question["instructions"] as? String ?? "")\noptions:\n" + lines.joined(separator: "\n")
            let prompt = "<|im_start|>system\nYou are a decision engine. You read a record and answer one question about it by choosing exactly one option. Reply with a single letter.<|im_end|>\n"
                + "<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\nAnswer:"
            var request = URLRequest(url: URL(string: "\(base)/v1/completions")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 600
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "prompt": prompt, "max_tokens": 1, "temperature": 0,
                                                                           "logprobs": max(options.count * 2, 20)] as [String: Any])
            let (data, response) = try await URLSession.shared.data(for: request)
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            // The server lists the likeliest tokens at the answer slot: [{token, logprob}] under the first
            // content entry (or, from older servers, a {token: logprob} dictionary).
            guard (response as? HTTPURLResponse)?.statusCode == 200, let choice = (obj["choices"] as? [[String: Any]])?.first,
                  let logprobs = choice["logprobs"] as? [String: Any] else {
                throw Failure(message: "The decision model on this Mac didn't answer: \((obj["error"] as? [String: Any])?["message"] as? String ?? "no probabilities came back").")
            }
            var top: [String: Double] = [:]
            if let content = (logprobs["content"] as? [[String: Any]])?.first, let list = content["top_logprobs"] as? [[String: Any]] {
                for entry in list { if let token = entry["token"] as? String, let p = entry["logprob"] as? Double { top[token] = p } }
            } else if let dict = (logprobs["top_logprobs"] as? [[String: Any]])?.first {
                for (token, p) in dict { if let p = p as? Double { top[token] = p } }
            }
            guard !top.isEmpty else { throw Failure(message: "The decision model on this Mac didn't answer: no probabilities came back.") }
            // The label's log-probability at the answer slot, with or without the space the tokenizer puts first.
            var logs: [Double] = []
            for index in options.indices {
                let label = labels[index]
                let found = top.first { $0.key.trimmingCharacters(in: .whitespaces) == label }?.value
                logs.append(found ?? -30)
            }
            let temperature = 0.8
            let scaled = logs.map { $0 / temperature }
            let peak = scaled.max() ?? 0
            let weights = scaled.map { exp($0 - peak) }
            let total = weights.reduce(0, +)
            let probabilities = weights.map { $0 / total }
            let confidence = options.count < 2 ? 1 : (probabilities.max()! - 1 / Double(options.count)) / (1 - 1 / Double(options.count))
            switch question["type"] as? String {
            case "noul":
                var p = probabilities[0]
                let floor = 0.801   // the shim commits a yes/no it isn't sure of to the floor on its side
                if max(p, 1 - p) < floor { p = p >= 0.5 ? floor : 1 - floor }
                answers[id] = ["noul": p]
            case "score":
                let score = probabilities.enumerated().reduce(0.0) { $0 + Double($1.offset) * $1.element }
                answers[id] = ["score": score, "probabilities": Dictionary(uniqueKeysWithValues: probabilities.enumerated().map { (String($0.offset), $0.element) }),
                               "confidence": confidence]
            default:
                let best = probabilities.enumerated().max { $0.element < $1.element }!.offset
                answers[id] = ["choice": options[best].name, "probabilities": Dictionary(uniqueKeysWithValues: zip(options.map(\.name), probabilities)),
                               "confidence": confidence]
            }
        }
        return (answers, 0)
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

    /// The answers' shape as a JSON schema, which the routes that take one hold the model to: every question's key,
    /// and for a choice only its own options, written exactly. Without it a small model sometimes left the
    /// question's key off its answer.
    static func decisionSchema(_ questions: [String: Any]) -> [String: Any] {
        func object(_ properties: [String: Any]) -> [String: Any] {
            ["type": "object", "properties": properties, "required": properties.keys.sorted(), "additionalProperties": false]
        }
        let number: [String: Any] = ["type": "number"]
        var answers: [String: Any] = [:]
        for (id, value) in questions {
            guard let question = value as? [String: Any], let type = question["type"] as? String else { continue }
            switch type {
            case "noul":
                answers[id] = object(["noul": number])
            case "choice":
                // Each option once: an app may list one twice, and the schema's properties can't hold it twice.
                let options = Set((question["criteria"] as? [String: Any]).map { Array($0.keys) } ?? (question["criteria"] as? [String] ?? [])).sorted()
                answers[id] = object(["choice": ["type": "string", "enum": options] as [String: Any],
                                      "probabilities": object(Dictionary(uniqueKeysWithValues: options.map { ($0, number as Any) })),
                                      "confidence": number])
            case "score":
                let levels = (question["criteria"] as? [Any])?.count ?? 0
                answers[id] = object(["score": number,
                                      "probabilities": object(Dictionary(uniqueKeysWithValues: (0..<levels).map { (String($0), number as Any) })),
                                      "confidence": number])
            default:
                continue
            }
        }
        return object(answers)
    }

    /// Decisions without a decision model: the questions go to a small text model as JSON, and its answers
    /// come back in the same shape Jev's would (`noul`, `choice`/`score` with `probabilities` and
    /// `confidence`), checked against each question so an app can't be handed a made-up option.
    static func decideByText(state: Any, questions: [String: Any], appText: String? = nil) async throws -> ([String: Any], Double) {
        let stateJSON = (try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys, .fragmentsAllowed]))
            .map { String(decoding: $0, as: UTF8.self) } ?? "\(state)"
        let questionsJSON = (try? JSONSerialization.data(withJSONObject: questions, options: [.sortedKeys]))
            .map { String(decoding: $0, as: UTF8.self) } ?? ""
        // Worded for a small model: Luna got "rm -rf ~" backwards with a terser version of this.
        let system = """
        You answer typed questions about some state, like a calibrated classifier. The questions are JSON, keyed \
        by id; reply with one JSON object with the same keys and nothing else.

        For a question of type "noul", the value is {"noul": p}: p is the probability, from 0 to 1, that the \
        answer to its instructions is yes, judged against its criteria ("true" describes a yes, "false" a no). \
        A clear no is 0.0, a clear yes 1.0.

        For a question of type "choice", the criteria are the options (a description of when each applies, or \
        null). The value is {"choice": option, "probabilities": {option: p, ...}, "confidence": c}: one \
        probability per option, summing to 1; choice is the most likely option; confidence (0 to 1) is how \
        concentrated the probabilities are.

        For a question of type "score", the criteria are ordered levels, lowest first, each describing a \
        situation. The value is {"score": s, "probabilities": {"0": p, "1": p, ...}, "confidence": c}: one \
        probability per level index, summing to 1; s is the probability-weighted index; confidence (0 to 1) is \
        how concentrated the probabilities are.
        """
        let prompt = "State:\n\(stateJSON)\n\nQuestions:\n\(questionsJSON)"
        let fast = await fastModel(for: route(for: appText))
        let (text, cost) = try await complete(prompt: prompt, images: [], system: system, json: true, appModel: appText, engineModel: fast,
                                              schema: decisionSchema(questions))
        guard let raw = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw Failure(message: "The model's decision wasn't valid JSON.", cost: cost)
        }
        var answers: [String: Any] = [:]
        for (id, question) in questions {
            guard let q = question as? [String: Any], let type = q["type"] as? String else { continue }
            let given = raw[id] as? [String: Any] ?? [:]
            func clamp(_ value: Any?) -> Double? { (value as? NSNumber).map { min(max($0.doubleValue, 0), 1) } }
            switch type {
            case "noul":
                guard let p = clamp(given["noul"]) else { throw Failure(message: "The model didn't answer \"\(id)\".", cost: cost) }
                answers[id] = ["noul": p]
            case "choice":
                let options = (q["criteria"] as? [String: Any])?.keys.map { $0 } ?? (q["criteria"] as? [String] ?? [])
                var probabilities = (given["probabilities"] as? [String: Any] ?? [:]).reduce(into: [String: Double]()) {
                    if options.contains($1.key), let p = clamp($1.value) { $0[$1.key] = p }
                }
                var choice = given["choice"] as? String
                if choice == nil || !options.contains(choice!) { choice = probabilities.max { $0.value < $1.value }?.key }
                guard let choice else { throw Failure(message: "The model didn't pick an option for \"\(id)\".", cost: cost) }
                if probabilities.isEmpty { probabilities = [choice: 1] }
                let total = probabilities.values.reduce(0, +)
                if total > 0 { probabilities = probabilities.mapValues { $0 / total } }
                answers[id] = ["choice": choice, "probabilities": probabilities,
                               "confidence": clamp(given["confidence"]) ?? probabilities[choice] ?? 1]
            case "score":
                let levels = (q["criteria"] as? [Any])?.count ?? 0
                let top = Double(max(levels - 1, 0))
                // One normalized distribution is the truth; the score is derived from it, so the two can't
                // disagree. The model's own score only stands in when it gave no usable probabilities.
                var probabilities = (given["probabilities"] as? [String: Any] ?? [:]).reduce(into: [String: Double]()) {
                    if let index = Int($1.key), index >= 0, Double(index) <= top, let p = clamp($1.value) { $0[$1.key] = p }
                }
                let total = probabilities.values.reduce(0, +)
                if total > 0 {
                    probabilities = probabilities.mapValues { $0 / total }
                } else if let given = (given["score"] as? NSNumber).map({ min(max($0.doubleValue, 0), top) }) {
                    probabilities = [String(Int(given.rounded())): 1]
                } else {
                    throw Failure(message: "The model didn't rate \"\(id)\".", cost: cost)
                }
                let score = probabilities.reduce(0) { $0 + Double($1.key)! * $1.value }
                answers[id] = ["score": score, "probabilities": probabilities,
                               "confidence": clamp(given["confidence"]) ?? probabilities.values.max() ?? 1]
            default:
                throw Failure(message: "Unknown question type \"\(type)\".", cost: cost)
            }
        }
        return (answers, cost)
    }

    /// Where images come from: OpenRouter's image models with a key; otherwise a picture model on this Mac
    /// (mflux, from Hugging Face), if one was downloaded; otherwise Codex's own image tool, with a ChatGPT
    /// sign-in; otherwise nothing, and Lamp asks the first time an app wants a picture. (Apple's on-device Image Playground has no
    /// programmatic API any more: ImageCreator stopped working in macOS 27.)
    enum ImageRoute { case openRouter, codex, local }

    /// The route for pictures, as far as can be told without asking anything: an explicit choice of the
    /// model on this Mac (when it's there and the request makes a picture from words), else OpenRouter with a
    /// key, else the model on this Mac, else Codex when it's chosen and was last known to be signed in.
    /// `imageRoute(…)` asks Codex first; this is the one rule both follow, and the one `resolve` reports.
    @MainActor static func pictureRoute(choice: String? = nil, appText: String? = nil, editing: Bool = false) -> ImageRoute? {
        let wantsLocal = choice == Icons.localArt || (choice == nil && Icons.artModel == Icons.localArt)
        if wantsLocal, ImageModels.ready, !editing { return .local }
        if Provider.hasKey { return .openRouter }
        if ImageModels.ready, !editing { return .local }
        if codexChosen(appText: appText), EngineInstall.path(for: .codex) != nil, EngineSignIn.known[.codex] != false { return .codex }
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
    /// A model on this Mac makes pictures from words only, so a request that edits existing pictures skips it.
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
        case .local: "\(ImageModels.chosen?.name ?? "a model") on this Mac"
        }
    }

    /// The failure an app gets when nothing can make images: Lamp shows a card asking for a key or a download.
    static let noImageRoute = "Making images needs an OpenRouter key, or a picture model on this Mac. Add one in Lamp → Settings (⌘,)."

    /// Creates or edits an image. `references` are input images to edit or combine. Returns PNG data and
    /// the cost in USD (0 through Codex).
    static func image(prompt: String, references: [Image], aspectRatio: String?,
                      model appChoice: String? = nil, appText: String? = nil) async throws -> (Data, Double) {
        // Someone who picked the Mac's own model over the cloud ones gets it, key or no key (`pictureRoute`).
        let wantsLocal = (appChoice == Icons.localArt || (appChoice == nil && Icons.artModel == Icons.localArt)) && ImageModels.ready
        if wantsLocal, !references.isEmpty {
            throw Failure(message: "\(ImageModels.chosen?.name ?? "The model on this Mac") makes pictures from words and can't edit one. Pick a cloud image model in Lamp → Settings → AI for this.")
        }
        switch await imageRoute(editing: !references.isEmpty, appText: appText, choice: appChoice) {
        case .openRouter: break
        case .codex: return (try await viaCodexImage(prompt: prompt, references: references, aspectRatio: aspectRatio), 0)
        case .local:
            let (width, height) = localSize(aspectRatio)
            return (try await ImageModels.generate(prompt: prompt, width: width, height: height), 0)
        case nil: throw Failure(message: noImageRoute, needs: .pictures)
        }
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/images")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 240
        request.setValue("Bearer \(KeyStore.openRouterKey ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Lamp", forHTTPHeaderField: "X-Title")
        let imageModel = Icons.artModels.contains { $0.id == appChoice } ? appChoice! : Icons.artModel
        var body: [String: Any] = ["model": imageModel, "prompt": prompt, "n": 1, "output_format": "png"]
        if let aspectRatio { body["aspect_ratio"] = aspectRatio }
        if !references.isEmpty {
            body["input_references"] = references.map {
                ["type": "image_url", "image_url": ["url": "data:\($0.mediaType);base64,\($0.data)"]]
            }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw Failure(message: Provider.friendlyError(status: status, reply: obj, from: Provider.openRouter))
        }
        guard let base64 = (obj["data"] as? [[String: Any]])?.first?["b64_json"] as? String,
              let decoded = Data(base64Encoded: base64), NSImage(data: decoded) != nil else {
            throw Failure(message: "The image model didn't return a picture.")
        }
        return (decoded, (obj["usage"] as? [String: Any])?["cost"] as? Double ?? 0)
    }

    /// Pixel sizes for the local models (multiples of 16, about a megapixel).
    private static func localSize(_ aspectRatio: String?) -> (Int, Int) {
        switch aspectRatio {
        case "16:9": (1024, 576)
        case "9:16": (576, 1024)
        case "4:3": (1024, 768)
        case "3:4": (768, 1024)
        case "3:2": (1024, 688)
        case "2:3": (688, 1024)
        default: (1024, 1024)
        }
    }

    /// Codex makes the picture with its built-in image tool and saves it in a scratch folder; reference
    /// images are attached and named in the prompt. Takes about a minute.
    private static func viaCodexImage(prompt: String, references: [Image], aspectRatio: String?) async throws -> Data {
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

    private static func viaOpenRouter(prompt: String, images: [Image], system: String,
                                      model: String, json: Bool = false, schema: [String: Any]? = nil) async throws -> (String, Double) {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(KeyStore.openRouterKey ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Lamp", forHTTPHeaderField: "X-Title")
        var messages: [[String: Any]] = []
        if !system.trimmed.isEmpty { messages.append(["role": "system", "content": system]) }
        let content: [[String: Any]] = [["type": "text", "text": prompt]] + images.map {
            ["type": "image_url", "image_url": ["url": "data:\($0.mediaType);base64,\($0.data)"]]
        }
        messages.append(["role": "user", "content": content])
        var body: [String: Any] = ["model": model, "messages": messages, "usage": ["include": true]]
        if json {
            // Structured output: the model must return a JSON object, and gets room for a long one (a plan
            // with scripts in it can run to thousands of tokens; a cut-off reply is what breaks apps).
            // With a schema, the object must also fit it.
            body["response_format"] = schema.map { ["type": "json_schema", "json_schema": ["name": "answer", "strict": true, "schema": $0]] }
                ?? ["type": "json_object"]
            body["max_tokens"] = 16_000
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Anthropic's safety classifier sometimes refuses an ordinary request (finish_reason "content_filter",
        // empty reply, HTTP 200): about 1 in 20 identical benign requests in others' measurements, and more
        // under bursts. It's random, so asking again gets the answer.
        var cost = 0.0
        for attempt in 0..<3 {
            let (data, response) = try await URLSession.shared.data(for: request)
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let choice = (obj["choices"] as? [[String: Any]])?.first
            cost += (obj["usage"] as? [String: Any])?["cost"] as? Double ?? 0
            guard status == 200, let choice else {
                throw Failure(message: Provider.friendlyError(status: status, reply: obj, from: Provider.openRouter))
            }
            let text = (choice["message"] as? [String: Any])?["content"] as? String ?? ""
            if choice["finish_reason"] as? String == "content_filter" {
                if attempt < 2 { try await Task.sleep(for: .milliseconds(400 << attempt)); continue }
                throw Failure(message: "The AI provider's content filter cut the reply off. Try rewording the request.")
            }
            return (text, cost)
        }
        throw Failure(message: "The AI didn't answer.")
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
