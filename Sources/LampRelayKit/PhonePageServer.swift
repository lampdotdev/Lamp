import Foundation
import Network

/// One game's phone page, served by the game itself (`ControllerRuntime`) on a port of its own, as Lamp serves a TV
/// app's page (`PhoneSites`): each game's page is an origin of its own in a phone's browser. Plain GETs of the files of
/// the page Lamp put in the game's bundle (`ControllerSnapshot`), from a phone on the network by one of the device's names
/// or addresses, or on the device by a loopback name; `lamp-relay.json`, where lamp-controller.js opens its socket; and
/// `lamp-phone.json`, the version of the page served now, which an open page reads to find a newer one (`use`).
public final class PhonePageServer: @unchecked Sendable {
    /// The port asked for (0: any the system gives), then the one it listens on once it does.
    public private(set) var port: UInt16?
    /// The page served, and its version: swapped whole (`use`), so every answer is from the one or the other.
    private var served: (root: URL, version: String?)
    private let servedLock = NSLock()
    private let app: String
    private let queue = DispatchQueue(label: "dev.lamp.controllers.page")
    private var listener: NWListener?
    /// Connections open now, by the address they came from: a page is a few small requests, so a host that holds many
    /// open, or one that never finishes its request, is let go before it can use up what the game needs for phones.
    private var open: [ObjectIdentifier: String] = [:]
    public static let connectionLimit = (all: 64, each: 16)
    public static let headDeadline: TimeInterval = 10
    /// The names and addresses the device answers as, lowercased, read when asked: they change with the network.
    private let hosts: @Sendable () -> Set<String>
    private let relayPort: @Sendable () -> UInt16?

    /// Where an open page reads the version served now, and the mark at the top of a page saying the version it is: an
    /// HTML comment, which comes before the doctype without changing how the page is drawn. A host with neither (an LG
    /// TV's, an Xbox's, a game built by an earlier Lamp) leaves lamp-controller.js with nothing to compare, and the page
    /// stays as it opened.
    public static let versionFile = "lamp-phone.json"

    public static func marked(_ html: Data, version: String) -> Data {
        Data("<!--lamp-phone \(version)-->\n".utf8) + html
    }

    public static func versionAnswer(_ version: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["version": version])) ?? Data()
    }

    public init(port: UInt16 = 0, root: URL, version: String? = nil, app: String, hosts: @escaping @Sendable () -> Set<String>, relayPort: @escaping @Sendable () -> UInt16?) {
        self.port = port
        self.served = (root, version)
        self.app = app
        self.hosts = hosts
        self.relayPort = relayPort
    }

    /// Serves this page from now on: phones open on the last one find `version` and open again from it.
    public func use(page root: URL, version: String?) {
        servedLock.withLock { served = (root, version) }
    }

    /// Starts listening on every interface at its port; `ready` hears true once it does (and `port` says where), false
    /// when another program has the port. `onFailure`: it stopped listening afterwards.
    public func start(ready: @escaping @Sendable (Bool) -> Void, onFailure: @escaping @Sendable () -> Void = {}) {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = false
        let asked = port ?? 0
        guard let listener = try? NWListener(using: params, on: asked == 0 ? .any : (NWEndpoint.Port(rawValue: asked) ?? .any)) else { return ready(false) }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return connection.cancel() }
            var from = "?"
            if case .hostPort(let host, _) = connection.endpoint { from = "\(host)" }
            let id = ObjectIdentifier(connection)
            guard self.open.count < Self.connectionLimit.all, self.open.values.filter({ $0 == from }).count < Self.connectionLimit.each else {
                return connection.cancel()
            }
            self.open[id] = from
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .failed, .cancelled: self?.open[id] = nil
                default: break
                }
            }
            connection.start(queue: self.queue)
            self.queue.asyncAfter(deadline: .now() + Self.headDeadline) { [weak self, weak connection] in
                guard let connection, let from = self?.open[id], from != "answered" else { return }
                connection.cancel()
            }
            self.receive(connection, buffer: Data())
        }
        var answered = false
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self else { return }
            switch state {
            case .ready:
                if !answered { answered = true; self.port = listener?.port?.rawValue; ready(true) }
            case .failed, .cancelled:
                if !answered { answered = true; ready(false) } else { onFailure() }
                listener?.stateUpdateHandler = nil
                listener?.newConnectionHandler = nil
                listener?.cancel()
            default:
                break
            }
        }
        queue.sync { self.listener = listener }
        listener.start(queue: queue)
    }

    public func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
        }
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 14) { [weak self] data, _, done, error in
            guard let self else { return connection.cancel() }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
                let page = self.answer(head)
                // Answered: the deadline is for the request, not for a phone on a slow network taking the page.
                self.open[ObjectIdentifier(connection)] = "answered"
                Self.respond(connection, page)
            } else if done || error != nil || buffer.count > 16 << 10 {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    public struct Page: Equatable {
        public var status: Int
        public var type = "text/plain; charset=utf-8"
        public var body = Data()
        public var location: String?
        public var head = false
        /// What the phone's browser holds the page to (`PhonePagePolicy`), sent with every answer.
        public var policy: String?
    }

    /// The answer to a request's head (its request line and headers).
    public func answer(_ head: String) -> Page {
        var lines = head.components(separatedBy: "\r\n")
        let start = lines.removeFirst().split(separator: " ")
        guard start.count >= 2 else { return Page(status: 400, body: Data("Bad request".utf8)) }
        let method = String(start[0])
        guard method == "GET" || method == "HEAD" else { return Page(status: 405, body: Data("Not allowed".utf8)) }
        var host: String?
        for line in lines {
            guard let colon = line.firstIndex(of: ":"), line[..<colon].lowercased() == "host" else { continue }
            host = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        var page = answer(path: String(start[1]), host: host)
        page.head = method == "HEAD"
        return page
    }

    /// A page by its path, asked for by `host`: only this device by one of its names, so a page elsewhere that made its own
    /// name lead here (DNS rebinding) reads nothing.
    public func answer(path full: String, host: String?) -> Page {
        guard Self.names(host, among: hosts()) else { return Page(status: 403, body: Data("Not for this host.".utf8)) }
        let (root, version) = servedLock.withLock { served }
        let reach = PhonePagePolicy.reach(fileAt: root.appendingPathComponent(PhonePagePolicy.reachFile))
        var page = file(path: full, in: root, version: version, held: reach != .unrestricted)
        page.policy = PhonePagePolicy.header(host: host, relayPort: relayPort(), reach: reach)
        return page
    }

    /// `held`: the page has rules, which lamp-relay.json says (`policy`), so lamp-controller.js only ever takes a refused
    /// socket for a moved relay on a page Lamp gave rules to.
    private func file(path full: String, in root: URL, version: String?, held: Bool) -> Page {
        let missing = Page(status: 404, body: Data("Nothing here. Open the game first.".utf8))
        let path = full.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        guard path.hasPrefix("/") else { return missing }
        var names = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false).map { $0.removingPercentEncoding ?? "\0" }
        if names.last == "" { names[names.count - 1] = "index.html" }
        if names == ["lamp-relay.json"] {
            let port = relayPort()
            var said: [String: Any] = ["port": Int(port ?? 0), "app": app]
            if held { said["policy"] = true }
            guard port != nil, let body = try? JSONSerialization.data(withJSONObject: said) else {
                return Page(status: 503, body: Data("The link for controllers isn't open.".utf8))
            }
            return Page(status: 200, type: Self.type(for: "json"), body: body)
        }
        if names == [Self.versionFile] {
            guard let version else { return missing }
            return Page(status: 200, type: Self.type(for: "json"), body: Self.versionAnswer(version))
        }
        let relative = names.joined(separator: "/")
        guard names.allSatisfy({ !$0.contains("/") }), ControllerSnapshot.isServed(relative) else { return missing }
        var steps = [root]
        for name in names { steps.append(steps[steps.count - 1].appendingPathComponent(name)) }
        guard steps.allSatisfy({ (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == false }) else { return missing }
        let file = steps[steps.count - 1]
        let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values?.isRegularFile == true, (values?.fileSize ?? 0) <= ControllerSnapshot.fileLimit,
              let data = try? Data(contentsOf: file) else { return missing }
        let html = ["html", "htm"].contains(file.pathExtension.lowercased())
        return Page(status: 200, type: Self.type(for: file.pathExtension), body: html && version != nil ? Self.marked(data, version: version!) : data)
    }

    /// Whether a Host header names one of `hosts`, with at most a numeric port after it.
    public static func names(_ header: String?, among hosts: Set<String>) -> Bool {
        guard var host = header?.trimmingCharacters(in: .whitespaces).lowercased(), !host.isEmpty else { return false }
        if host.hasPrefix("[") {
            guard let close = host.firstIndex(of: "]") else { return false }
            let port = host[host.index(after: close)...]
            guard port.isEmpty || (port.hasPrefix(":") && port.count > 1 && port.dropFirst().allSatisfy(\.isNumber)) else { return false }
            host = String(host[host.index(after: host.startIndex)..<close])
        } else if let colon = host.firstIndex(of: ":") {
            let port = host[host.index(after: colon)...]
            guard !port.isEmpty, port.allSatisfy(\.isNumber) else { return false }
            host = String(host[..<colon])
        }
        return hosts.contains(host)
    }

    private static func respond(_ connection: NWConnection, _ page: Page) {
        let reason = HTTPURLResponse.localizedString(forStatusCode: page.status).capitalized
        let location = page.location.map { "Location: \($0)\r\n" } ?? ""
        let policy = page.policy.map { "Content-Security-Policy: \($0)\r\n" } ?? ""
        var response = Data(("HTTP/1.1 \(page.status) \(reason)\r\nContent-Type: \(page.type)\r\nContent-Length: \(page.body.count)\r\n\(location)\(policy)"
            + "Cache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n\r\n").utf8)
        if !page.head { response.append(page.body) }
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    /// The type a page's file is served as, by its extension: Lamp's own serving reads the same list (`Store.pageType`).
    public static func type(for ext: String) -> String {
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

    /// The device's addresses on its Wi‑Fi and wired networks (`ControllerAddresses.lan`).
    public static func localAddresses() -> [String] { ControllerAddresses.lan() }
}
