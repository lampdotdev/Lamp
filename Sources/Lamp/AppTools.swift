import AppKit
import Foundation

/// Other AI agents using an app's own tools (`LampTools` in LampSupport.swift): the person's assistant reads
/// the grocery list or logs a workout through the app itself. The app declares its tools and waits at the
/// gateway for calls (`/ai/tools/next`, with its own token); an agent the person has given the app's address
/// speaks MCP to `/apps/<key>/mcp`, and each call is handed to the waiting app and its answer handed back.
/// Off for every app until the person turns it on in the app's menu, which makes the key; turning it off
/// forgets the key, so an address given out stops working. Every call leaves a line in the app's chat.
@MainActor final class AppTools: ObservableObject {
    static let shared = AppTools(file: Edition.supportFolder.appendingPathComponent("app-tools.json"))

    struct Tool: Codable, Equatable {
        struct Parameter: Codable, Equatable {
            let name: String
            let description: String
            let type: String
            let optional: Bool
        }
        let name: String
        let description: String
        let parameters: [Parameter]

        /// As an MCP tool definition.
        var definition: [String: Any] {
            var properties: [String: Any] = [:]
            for parameter in parameters { properties[parameter.name] = ["type": parameter.type, "description": parameter.description] }
            return ["name": name, "description": description,
                    "inputSchema": ["type": "object", "properties": properties,
                                    "required": parameters.filter { !$0.optional }.map(\.name)]]
        }
    }

    struct Call {
        let id: String
        let name: String
        let arguments: [String: Any]
        var json: [String: Any] { ["id": id, "name": name, "arguments": arguments] }
    }

    struct Answer {
        let text: String
        let isError: Bool
    }

    /// Per app (`LampProject.instance`, which survives renames): the secret in its address while agents may
    /// use it, and the tools it said it has the last time it ran. Kept in Lamp's own folder, where the
    /// builder agent can't turn it on for the person.
    @Published private(set) var keys: [String: String] = [:]
    @Published private(set) var declared: [String: [Tool]] = [:]

    /// Calls waiting for their app, the app's waits for a call, and calls waiting for their answer.
    private var queued: [String: [Call]] = [:]
    /// Calls handed to one of the app's waits that the copy of the app it came from (each launch is its own,
    /// and an app for both may be open on the Mac and on iOS at once) hasn't yet said it got. The gateway
    /// can't tell when a wait's connection is gone (the app quit, or a phone lost its way), so a copy's next
    /// wait says what its last one brought, and anything else handed to that copy goes again. A copy that
    /// stops waiting altogether is gone, and what it never acknowledged goes to whichever copy asks next.
    private struct Delivery { let call: Call; let copy: String }
    private var handedOut: [String: [Delivery]] = [:]
    /// When each copy last began a wait. A running copy begins one at least every half minute.
    private var lastWait: [String: [String: Date]] = [:]
    private var listeners: [String: [UUID: (copy: String, continuation: CheckedContinuation<[Call], Never>)]] = [:]
    private var answers: [String: (app: String, continuation: CheckedContinuation<Answer?, Never>)] = [:]
    /// When each app last ended a wait: between two waits it is still listening.
    private var heard: [String: Date] = [:]
    /// The names agents gave for themselves when they connected. Calls carry no name, so the chat's line names
    /// the agent only while one has connected to the app.
    private var clients: [String: Set<String>] = [:]

    private let file: URL
    private struct Saved: Codable { var keys: [String: String]; var declared: [String: [Tool]] }

    init(file: URL) {
        self.file = file
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            keys = saved.keys
            declared = saved.declared
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Saved(keys: keys, declared: declared)) else { return }
        try? data.write(to: file, options: .atomic)
    }

    static func app(_ project: LampProject) -> String { project.instance.isEmpty ? project.id : project.instance }

    func tools(of project: LampProject) -> [Tool] { declared[Self.app(project)] ?? [] }
    func isOn(_ project: LampProject) -> Bool { keys[Self.app(project)] != nil }

    /// The address to paste into an agent, while agents may use the app.
    func address(of project: LampProject) -> String? {
        keys[Self.app(project)].map { "http://127.0.0.1:\(Gateway.port)/apps/\($0)/mcp" }
    }

    func setOn(_ on: Bool, for project: LampProject) {
        let app = Self.app(project)
        if on {
            guard keys[app] == nil else { return }
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return }
            keys[app] = bytes.map { String(format: "%02x", $0) }.joined()
        } else {
            keys[app] = nil
        }
        save()
    }

    func forget(_ project: LampProject) {
        let app = Self.app(project)
        keys[app] = nil
        declared[app] = nil
        save()
    }

    /// The app whose address carries this key.
    func app(forKey key: String) -> String? {
        guard !key.isEmpty else { return nil }
        return keys.first { $0.value == key }?.key
    }

    // MARK: The app's side

    /// The app waiting for calls: what it offers now, then the calls already waiting or the next one to come
    /// within half a minute (none, after that, and the app asks again).
    func next(for project: LampProject, offering body: [String: Any]) async -> [Call] {
        let app = Self.app(project)
        if let list = body["tools"] as? [[String: Any]] {
            let tools = Self.checked(list)
            if tools != declared[app] {
                declared[app] = tools
                save()
            }
        }
        let copy = body["copy"] as? String ?? ""
        let now = Date()
        heard[app] = now
        defer { heard[app] = Date() }
        lastWait[app, default: [:]][copy] = now
        lastWait[app] = lastWait[app]?.filter { now.timeIntervalSince($0.value) < 300 }
        let received = Set(body["received"] as? [String] ?? [])
        var lost: [Call] = []
        handedOut[app] = (handedOut[app] ?? []).filter { delivery in
            guard answers[delivery.call.id] != nil else { return false }   // answered, or given up on
            if delivery.copy == copy {
                if !received.contains(delivery.call.id) { lost.append(delivery.call) }
                return false
            }
            guard now.timeIntervalSince(lastWait[app]?[delivery.copy] ?? .distantPast) > 35 else { return true }
            lost.append(delivery.call)
            return false
        }
        if !lost.isEmpty { queued[app, default: []].insert(contentsOf: lost, at: 0) }
        if let waiting = queued.removeValue(forKey: app), !waiting.isEmpty {
            handedOut[app, default: []] += waiting.map { Delivery(call: $0, copy: copy) }
            return waiting
        }
        let wait = UUID()
        return await withCheckedContinuation { continuation in
            listeners[app, default: [:]][wait] = (copy, continuation)
            Task {
                try? await Task.sleep(for: .seconds(25))
                self.listeners[app]?.removeValue(forKey: wait)?.continuation.resume(returning: [])
            }
        }
    }

    /// The app's answer to a call it was handed.
    func answer(_ body: [String: Any], from project: LampProject) {
        guard let id = body["id"] as? String, let waiting = answers[id], waiting.app == Self.app(project) else { return }
        answers[id] = nil
        let text = String((body["text"] as? String ?? "").prefix(200_000))
        waiting.continuation.resume(returning: Answer(text: text, isError: body["isError"] as? Bool ?? false))
    }

    /// Whether the app is waiting for calls, or was a moment ago and is about to again.
    func isListening(_ project: LampProject) -> Bool {
        let app = Self.app(project)
        return !(listeners[app]?.isEmpty ?? true) || Date().timeIntervalSince(heard[app] ?? .distantPast) < 3
    }

    /// Lets go of an app's waits, when it's known to be closed: they're from a copy that's gone.
    func dropListeners(of project: LampProject) {
        let app = Self.app(project)
        for listener in (listeners.removeValue(forKey: app) ?? [:]).values { listener.continuation.resume(returning: []) }
        heard[app] = nil
    }

    /// Hands a call to the app and waits for its answer: nil when none came in time.
    func call(_ name: String, _ arguments: [String: Any], on project: LampProject, within seconds: Double) async -> Answer? {
        let app = Self.app(project)
        let call = Call(id: UUID().uuidString, name: name, arguments: arguments)
        return await withCheckedContinuation { continuation in
            answers[call.id] = (app, continuation)
            if let listener = listeners[app]?.first {
                listeners[app]?[listener.key] = nil
                handedOut[app, default: []].append(Delivery(call: call, copy: listener.value.copy))
                listener.value.continuation.resume(returning: [call])
            } else {
                queued[app, default: []].append(call)
            }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                self.queued[app]?.removeAll { $0.id == call.id }
                self.handedOut[app]?.removeAll { $0.call.id == call.id }
                self.answers.removeValue(forKey: call.id)?.continuation.resume(returning: nil)
            }
        }
    }

    /// Only well-formed tools, as many as an agent can sensibly be shown: the list comes from the app.
    static func checked(_ list: [[String: Any]]) -> [Tool] {
        func plain(_ name: String) -> Bool {
            !name.isEmpty && name.count <= 64 && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
        }
        var seen = Set<String>()
        return list.prefix(64).compactMap { item -> Tool? in
            guard let name = item["name"] as? String, plain(name), seen.insert(name).inserted else { return nil }
            let parameters = (item["parameters"] as? [[String: Any]] ?? []).prefix(32).compactMap { parameter -> Tool.Parameter? in
                guard let name = parameter["name"] as? String, plain(name),
                      let type = parameter["type"] as? String, ["string", "number", "boolean"].contains(type) else { return nil }
                return Tool.Parameter(name: name, description: String((parameter["description"] as? String ?? "").prefix(500)),
                                      type: type, optional: parameter["optional"] as? Bool ?? false)
            }
            return Tool(name: name, description: String((item["description"] as? String ?? "").prefix(1000)), parameters: Array(parameters))
        }
    }

    // MARK: The agent's side

    /// One MCP request from an outside agent, for the app its address names. Like Lamp's own endpoint: JSON-RPC
    /// answered on the spot, with no sessions or streams.
    /// `log` puts a line in the app's chat; `ready` gets the app listening, or says why it can't.
    func mcp(_ body: Data, for project: LampProject, log: (String) -> Void,
             ready: () async -> String?) async -> (Int, [String: Any]) {
        guard let message = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let method = message["method"] as? String else {
            return (400, ["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Not a JSON-RPC request."]])
        }
        let id = message["id"] ?? NSNull()
        let params = message["params"] as? [String: Any] ?? [:]
        func reply(_ result: [String: Any]) -> (Int, [String: Any]) { (200, ["jsonrpc": "2.0", "id": id, "result": result]) }
        func failed(_ text: String) -> (Int, [String: Any]) { reply(["content": [["type": "text", "text": text]], "isError": true]) }
        switch method {
        case "initialize":
            if let name = (params["clientInfo"] as? [String: Any])?["name"] as? String, !name.isEmpty {
                clients[Self.app(project), default: []].insert(String(name.prefix(40)))
            }
            let asked = params["protocolVersion"] as? String ?? ""
            let version = ["2024-11-05", "2025-03-26", "2025-06-18"].contains(asked) ? asked : "2025-03-26"
            return reply(["protocolVersion": version, "capabilities": ["tools": [:]],
                          "serverInfo": ["name": project.name, "version": "1"],
                          "instructions": "Tools of \(project.name), an app on the user's Mac. Calls reach the app while Lamp is open."])
        case "ping":
            return reply([:])
        case "tools/list":
            return reply(["tools": tools(of: project).map(\.definition)])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            guard tools(of: project).contains(where: { $0.name == name }) else {
                return (200, ["jsonrpc": "2.0", "id": id, "error": ["code": -32602, "message": "\(project.name) has no tool named \(name)."]])
            }
            let known = clients[Self.app(project)] ?? []
            log(Self.line(client: known.count == 1 ? known.first : nil, tool: name, arguments: arguments))
            if let trouble = await ready() { return failed(trouble) }
            guard let answer = await call(name, arguments, on: project, within: 120) else {
                return failed("\(project.name) didn't answer in time.")
            }
            var result: [String: Any] = ["content": [["type": "text", "text": answer.text]]]
            if answer.isError { result["isError"] = true }
            return reply(result)
        default:
            if message["id"] == nil { return (202, [:]) }
            return (200, ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found: \(method)"]])
        }
    }

    /// The chat's line for a call: who, which tool, and what it was given, short.
    static func line(client: String?, tool: String, arguments: [String: Any]) -> String {
        let given = arguments.keys.sorted().compactMap { key -> String? in
            guard let value = arguments[key] else { return nil }
            // JSON's true and false arrive as numbers: shown as the words.
            let flag = (value as? NSNumber).flatMap { CFGetTypeID($0) == CFBooleanGetTypeID() ? ($0.boolValue ? "true" : "false") : nil }
            let text = (value as? String) ?? flag ?? "\(value)"
            return "\(key) “\(text.count > 40 ? String(text.prefix(40)) + "…" : text)”"
        }
        var line = "\(client ?? "An AI agent") used \(tool)"
        if !given.isEmpty { line += ": " + given.joined(separator: ", ") }
        // Cut without an ellipsis at the end: a status line ending in one reads as work under way (Store.log).
        return String(line.prefix(200))
    }
}

extension Store {
    /// The app's menu turning outside agents' use on or off. Turning it on copies the address, with one line
    /// in the chat saying where it goes.
    func setAgentTools(_ on: Bool, for project: LampProject) {
        AppTools.shared.setOn(on, for: project)
        if on {
            copyAgentAddress(project)
            log(project, .status, "Other AI agents can use \(project.name) now. Its address is copied: add it to your agent as an MCP server. Anything with the address can use the app.")
        } else {
            log(project, .status, "Other AI agents can't use \(project.name) any more.")
        }
    }

    func copyAgentAddress(_ project: LampProject) {
        guard let address = AppTools.shared.address(of: project) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(address, forType: .string)
    }

    /// Gets the app listening for a call: a Mac app that's closed is opened behind the person's windows; an
    /// app on iOS can't be started from here. Nil when it's listening, else what to tell the agent.
    func readyForTools(_ project: LampProject) async -> String? {
        let tools = AppTools.shared
        if project.onIOS {
            return tools.isListening(project) ? nil : "\(project.name) answers only while it's open on the iPhone or iPad. Ask the user to open it."
        }
        let running = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == project.bundleID && !$0.isTerminated }
        if !running {
            tools.dropListeners(of: project)
            guard FileManager.default.fileExists(atPath: project.installedURL.path) else {
                return "\(project.name) isn't built yet."
            }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            do {
                _ = try await NSWorkspace.shared.openApplication(at: project.installedURL, configuration: config)
            } catch {
                return "\(project.name) couldn't be opened: \(error.localizedDescription)"
            }
        }
        for _ in 0..<60 where !tools.isListening(project) { try? await Task.sleep(for: .milliseconds(250)) }
        return tools.isListening(project) ? nil : "\(project.name) is open but isn't taking calls. It may need to be built again in Lamp."
    }

    /// `/apps/<key>/mcp`: only from this Mac, addressed to it by a loopback name, and never from a web page
    /// (a browser says where a request comes from; an agent doesn't). The key is the whole credential.
    func outsideAgentRequest(_ request: Gateway.Request, route: String) async -> (Int, [String: Any]) {
        guard !request.fromNetwork, Self.isLocalHost(request.headers["host"]), request.headers["origin"] == nil else {
            return (403, ["error": "Not for this host."])
        }
        let parts = route.split(separator: "/")
        guard parts.count == 3, parts[2] == "mcp", let app = AppTools.shared.app(forKey: String(parts[1])),
              let project = projects.first(where: { AppTools.app($0) == app }) else {
            return (401, ["error": "This address doesn't open any app. Turn on Let Other AI Agents Use It in Lamp for a new one."])
        }
        // No listening stream (GET) and no sessions to end (DELETE).
        guard request.method == "POST" else { return (405, ["error": "Method not allowed"]) }
        return await AppTools.shared.mcp(request.body, for: project,
                                         log: { self.log(project, .status, $0) }, ready: { await self.readyForTools(project) })
    }
}
