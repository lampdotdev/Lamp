import AppKit
import CoreImage
import CryptoKit
import Foundation
import Network

/// What an integration acts with, and nothing else. Each primitive is held to what it may reach: a request goes only to
/// the address the device was found at, which must be on the local network; a command only to that device, over SSH
/// with its host key pinned; a program on this Mac only from Lamp's list, or downloaded, checked and confined. The
/// guards are here, beside the primitives, so no caller can reach a device another way.

// MARK: - The device's address

enum DeviceAddress {
    /// A private or link-local address: where a device in the person's home is. Never this Mac itself, by loopback or
    /// by any of its own addresses on the network, which would reach Lamp's own gateway (it listens on the network
    /// while a device app needs it) and the apps' ports; and never a name, which could be made to lead anywhere.
    static func isPrivate(_ address: String) -> Bool {
        guard onNetwork(address) else { return false }
        let raw = IPv4Address(address).map { $0.rawValue } ?? IPv6Address(address).map { $0.rawValue }
        return raw.map { !thisMac().contains($0) } ?? false
    }

    /// A private or link-local address, this Mac's own included.
    static func onNetwork(_ address: String) -> Bool {
        if let v4 = IPv4Address(address) {
            let b = [UInt8](v4.rawValue)
            switch (b[0], b[1]) {
            case (10, _): return true
            case (172, 16...31): return true
            case (192, 168): return true
            case (169, 254): return true
            default: return false
            }
        }
        if let v6 = IPv6Address(address) {
            let b = [UInt8](v6.rawValue)
            if b[0] & 0xFE == 0xFC { return true }               // fc00::/7, unique local
            if b[0] == 0xFE && b[1] & 0xC0 == 0x80 { return true } // fe80::/10, link-local
            return false
        }
        return false
    }

    /// This Mac's own addresses on every interface, read each time: they change as it moves between networks.
    static func thisMac() -> Set<Data> {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var own: Set<Data> = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let address = pointer.pointee.ifa_addr else { continue }
            switch Int32(address.pointee.sa_family) {
            case AF_INET:
                own.insert(address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { withUnsafeBytes(of: $0.pointee.sin_addr) { Data($0) } })
            case AF_INET6:
                own.insert(address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { withUnsafeBytes(of: $0.pointee.sin6_addr) { Data($0) } })
            default: continue
            }
        }
        return own
    }

    struct NotOnNetwork: LocalizedError {
        let address: String
        var errorDescription: String? { "Lamp only talks to devices on your own network, and \(address) isn't one." }
    }
}

// MARK: - http

/// A request to a device, as an integration may make it.
enum DeviceHTTP {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct Answer {
        let status: Int
        let body: Data
        /// The cookies the device set (a CSRF token), by name, for `{cookie:<name>}` later in the same sequence.
        var cookies: [String: String] = [:]
        /// The certificate the device showed, over HTTPS (DER).
        var certificate: Data?
        var ok: Bool { (200..<300).contains(status) }
        var text: String { String(decoding: body, as: UTF8.self) }
    }

    /// Makes the request with Lamp's values filled in, through lamp's command line, whose request to a device this is
    /// (`cli/devices.mjs`'s `send`, asked of the run that stays: `LampCLI.ask`). It goes only to the device's own
    /// address, which must be on the person's network and never this Mac, by a path that stays a path; no redirect is
    /// followed, a sign-in goes only in answer to the device's own request for it, with the scheme the integration
    /// declared, and the answer is cut off at 16 MB (a device's answers are small, and a picture is a few megabytes).
    /// Over HTTPS, `pins` holds the device to the certificate it showed
    /// the first time; without them (while a device is only being found and read) nothing secret is sent. A look for
    /// devices waits `timeout` for each answer, much less than an install does: a device that answered the scan but
    /// not its port would otherwise hold up the whole look.
    static func send(_ request: Request, to address: String, values: [String: String], files: [String: URL] = [:],
                     pins: DeviceTLS.Pins? = nil, timeout: TimeInterval = 30) async throws -> Answer {
        var given: [String: Any] = ["request": try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)), "address": address,
                                    "values": values, "files": files.mapValues(\.path), "timeout": timeout]
        if let pins { given["pins"] = pins.file.path }
        let done: [String: Any]
        do {
            done = try await LampCLI.ask("send", given)
        } catch let failure as LampCLI.Failure {
            // Said as Lamp's app has always said each, for those who act on which it was.
            switch failure.kind {
            case "changed": throw DeviceTLS.Refusal.changed
            case "unsaved": throw DeviceTLS.Refusal.unsaved
            case "off-network": throw DeviceAddress.NotOnNetwork(address: address)
            case "away":
                let dropped = ["ECONNRESET", "EPIPE", "ECONNABORTED"].contains(failure.code ?? "")
                throw URLError(failure.timedOut ? .timedOut : dropped ? .networkConnectionLost : .cannotConnectToHost)
            default: throw Failure(message: failure.message)
            }
        }
        guard let status = done["status"] as? Int, let body = (done["body"] as? String).flatMap({ Data(base64Encoded: $0) }) else {
            throw Failure(message: "Lamp couldn't read the device's answer.")
        }
        return Answer(status: status, body: body, cookies: done["cookies"] as? [String: String] ?? [:],
                      certificate: (done["certificate"] as? String).flatMap { Data(base64Encoded: $0) })
    }

    // MARK: Reading a value out of an answer

    /// A value by a dotted JSON path ("device.modelName", "items.0.id"), as text.
    static func json(_ path: String, in data: Data) -> String? {
        guard var value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        for part in path.split(separator: ".").map(String.init) {
            if let object = value as? [String: Any], let next = object[part] { value = next }
            else if let array = value as? [Any], let index = Int(part), array.indices.contains(index) { value = array[index] }
            else { return nil }
        }
        return text(of: value)
    }

    /// Every value at a JSON path whose `*` stands for each element of a list ("InstalledPackages.*.PackageFullName");
    /// without one, the one value `json` reads.
    static func jsonValues(_ path: String, in data: Data) -> [String] {
        guard path.split(separator: ".").contains("*") else { return json(path, in: data).map { [$0] } ?? [] }
        guard let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return [] }
        var values: [Any] = [root]
        for part in path.split(separator: ".").map(String.init) {
            values = values.flatMap { value -> [Any] in
                if part == "*" { return value as? [Any] ?? [] }
                if let object = value as? [String: Any], let next = object[part] { return [next] }
                if let array = value as? [Any], let index = Int(part), array.indices.contains(index) { return [array[index]] }
                return []
            }
        }
        return values.compactMap(text(of:))
    }

    private static func text(of value: Any) -> String? {
        switch value {
        case let text as String: return text
        case let number as NSNumber:
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false") : number.stringValue
        case is NSNull: return nil
        default:
            return (try? JSONSerialization.data(withJSONObject: value)).map { String(decoding: $0, as: UTF8.self) }
        }
    }

    /// The text of the first element at an XML path ("model-name", or "device-info/model-name" for one inside another).
    static func xml(_ path: String, in data: Data) -> String? {
        let finder = XMLFinder(path: path.split(separator: "/").map(String.init))
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = finder
        parser.parse()
        return finder.found?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private final class XMLFinder: NSObject, XMLParserDelegate {
        let path: [String]
        var stack: [String] = []
        var text = ""
        var found: String?
        init(path: [String]) { self.path = path }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            stack.append(name)
            if matches { text = "" }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { if matches { text += string } }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if matches, found == nil { found = text; parser.abortParsing() }
            stack.removeLast()
        }
        private var matches: Bool { found == nil && stack.count >= path.count && Array(stack.suffix(path.count)) == path }
    }

    /// The value a read asks for out of an answer.
    static func value(json: String?, xml: String?, in answer: Answer) -> String? {
        if let json { return DeviceHTTP.json(json, in: answer.body) }
        if let xml { return DeviceHTTP.xml(xml, in: answer.body) }
        return nil
    }
}

// MARK: - probe

enum DeviceProbe {
    /// Whether the device accepts a TCP connection on a port, within a few seconds. Connects and closes; sends nothing.
    static func tcp(_ address: String, port: Int, timeout: TimeInterval = 3) async -> Bool {
        guard DeviceAddress.isPrivate(address), let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return false }
        let connection = NWConnection(host: NWEndpoint.Host(address), port: nwPort, using: .tcp)
        return await withCheckedContinuation { continuation in
            let once = Once()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: if once.take() { connection.cancel(); continuation.resume(returning: true) }
                case .failed, .cancelled, .waiting: if once.take() { connection.cancel(); continuation.resume(returning: false) }
                default: break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if once.take() { connection.cancel(); continuation.resume(returning: false) }
            }
        }
    }

    final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func take() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
    }

    /// One SSDP answer: where from, and what it said about itself.
    struct SSDPAnswer: Hashable {
        let address: String
        let server: String
        let location: String?
        let searchTarget: String
        let usn: String
    }

    /// An SSDP search of the local network for a search target ("ssdp:all" for everything), for a couple of seconds.
    static func ssdp(_ target: String, seconds: Double = 2) async -> [SSDPAnswer] {
        await search(target, seconds: seconds).answers
    }

    /// The same search, and whether macOS refused it: Lamp isn't allowed on the local network (Privacy & Security →
    /// Local Network), or hasn't been answered yet. A refused search only hears nothing, so a look that heard nothing
    /// asks Network.framework why (`localNetworkDenied`).
    static func search(_ target: String, seconds: Double) async -> (answers: [SSDPAnswer], refused: Bool) {
        async let denied = localNetworkDenied()
        let answers = await Task.detached { search(target, seconds: seconds) }.value
        return (answers, await denied && answers.isEmpty)
    }

    /// Whether macOS refuses Lamp the local network now. A send it refuses still succeeds where Lamp makes it, so a
    /// connection to the SSDP group is asked why its path can't be used, and closed at once.
    static func localNetworkDenied() async -> Bool {
        let connection = NWConnection(host: "239.255.255.250", port: 1900, using: .udp)
        return await withCheckedContinuation { continuation in
            let once = Once()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready, .waiting, .failed:
                    guard once.take() else { return }
                    let denied = connection.currentPath?.unsatisfiedReason == .localNetworkDenied
                    connection.cancel()
                    continuation.resume(returning: denied)
                default: break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { if once.take() { connection.cancel(); continuation.resume(returning: false) } }
        }
    }

    private static func search(_ target: String, seconds: Double) -> [SSDPAnswer] {
        guard !target.contains(where: { $0.isNewline }) else { return [] }
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }
        var wait = timeval(tv_sec: 0, tv_usec: 250_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
        var ttl: UInt8 = 2
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(1))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(1900).bigEndian
        address.sin_addr.s_addr = inet_addr("239.255.255.250")
        let message = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 1\r\nST: \(target)\r\n\r\n"
        for _ in 0..<2 {
            _ = message.withCString { text in
                withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(fd, text, strlen(text), 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
                }
            }
        }
        var answers: [SSDPAnswer] = []
        let end = Date().addingTimeInterval(seconds)
        var buffer = [UInt8](repeating: 0, count: 4096)
        // Asked again partway through: a device that was asleep or busy misses the first search more often than not.
        var askedAgain = false
        while Date() < end {
            if !askedAgain, Date() > end.addingTimeInterval(-seconds / 2) {
                askedAgain = true
                _ = message.withCString { text in
                    withUnsafePointer(to: &address) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(fd, text, strlen(text), 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
                    }
                }
            }
            var from = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let got = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buffer, buffer.count, 0, $0, &length) }
            }
            guard got > 0 else { continue }
            let answer = answer(String(decoding: buffer[0..<got], as: UTF8.self), from: String(cString: inet_ntoa(from.sin_addr)))
            if !answers.contains(answer) { answers.append(answer) }
        }
        return answers
    }

    /// One SSDP answer's headers, as the device at `address` sent them.
    static func answer(_ text: String, from address: String) -> SSDPAnswer {
        var headers: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return SSDPAnswer(address: address, server: headers["server"] ?? "", location: headers["location"],
                          searchTarget: headers["st"] ?? "", usn: headers["usn"] ?? "")
    }

    /// The devices offering a Bonjour service on the local network, by name and address, browsed for a few seconds.
    static func bonjour(_ type: String, seconds: Double = 3) async -> [(name: String, address: String)] {
        guard type.range(of: #"^_[a-z0-9-]{1,40}\._(tcp|udp)$"#, options: .regularExpression) != nil else { return [] }
        let browser = NWBrowser(for: .bonjour(type: type, domain: "local."), using: .tcp)
        let results = Collected<NWBrowser.Result>()
        browser.browseResultsChangedHandler = { all, _ in results.set(Array(all)) }
        browser.start(queue: .global())
        try? await Task.sleep(for: .seconds(seconds))
        browser.cancel()
        var found: [(String, String)] = []
        for result in results.items {
            guard case .service(let name, _, _, _) = result.endpoint else { continue }
            if let address = await resolve(result.endpoint) { found.append((name, address)) }
        }
        return found
    }

    /// A Bonjour service's address, from a connection made to it and closed at once.
    private static func resolve(_ endpoint: NWEndpoint) async -> String? {
        let connection = NWConnection(to: endpoint, using: .tcp)
        return await withCheckedContinuation { continuation in
            let once = Once()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    var address: String?
                    if case .hostPort(let host, _) = connection.currentPath?.remoteEndpoint {
                        switch host {
                        case .ipv4(let v4): address = "\(v4)"
                        case .ipv6(let v6): address = "\(v6)".components(separatedBy: "%").first
                        default: break
                        }
                    }
                    if once.take() { connection.cancel(); continuation.resume(returning: address) }
                case .failed, .cancelled: if once.take() { continuation.resume(returning: nil) }
                default: break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { if once.take() { connection.cancel(); continuation.resume(returning: nil) } }
        }
    }

    final class Collected<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [T] = []
        func set(_ items: [T]) { lock.lock(); stored = items; lock.unlock() }
        var items: [T] { lock.lock(); defer { lock.unlock() }; return stored }
    }
}

// MARK: - stream

/// A device's log, read line by line from a TCP port into the app's log. Read only: nothing is ever sent.
final class DeviceStream: @unchecked Sendable {
    private let connection: NWConnection
    private var pending = Data()

    init?(address: String, port: Int, onLine: @escaping @Sendable (String) -> Void) {
        guard DeviceAddress.isPrivate(address), let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return nil }
        connection = NWConnection(host: NWEndpoint.Host(address), port: nwPort, using: .tcp)
        connection.start(queue: DispatchQueue(label: "lamp.device-stream"))
        read(onLine)
    }

    private func read(_ onLine: @escaping @Sendable (String) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            guard let self else { return }
            if let data { self.pending.append(data) }
            while let newline = self.pending.firstIndex(of: 10) {
                let line = String(decoding: self.pending[..<newline], as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
                self.pending.removeSubrange(...newline)
                onLine(line)
            }
            // A device that never sends a newline doesn't grow this without end.
            if self.pending.count > 64 << 10 { onLine(String(decoding: self.pending, as: UTF8.self)); self.pending.removeAll() }
            if done || error != nil { self.connection.cancel(); return }
            self.read(onLine)
        }
    }

    func stop() { connection.cancel() }
}

// MARK: - field

/// What the person typed for a device (a passphrase, a PIN, a developer password), kept for that device only and sent
/// only to it. Kept the way apps' secrets are (`AppSecrets`): the Keychain when Lamp is signed for a team, else a file
/// only this user can read, under a place of its own.
enum DeviceFields {
    static var place: AppSecrets.Place {
        KeyStore.usesKeychain ? .keychain(service: Edition.bundleID + ".device-fields")
            : .file(Edition.supportFolder.appendingPathComponent("device-fields.json"))
    }

    /// The device's name for its secrets: its id may hold characters a secret's name can't.
    static func owner(_ deviceID: String) -> String {
        "d" + SHA256.hash(data: Data(deviceID.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    static func read(_ key: String, device: String) -> String? {
        AppSecrets.read(key, app: owner(device), in: place).map { String(decoding: $0, as: UTF8.self) }
    }

    @discardableResult
    static func save(_ value: String, as key: String, device: String) -> Bool {
        AppSecrets.save(Data(value.utf8), as: key, app: owner(device), in: place)
    }

    /// Everything typed for a device, for Forget.
    static func forget(device: String) { AppSecrets.forget(app: owner(device), in: place) }
}

// MARK: - show, qr

enum DeviceQR {
    static func image(_ text: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

// MARK: - vendorSignIn

/// The vendor's sign-in page in the browser, answered on this Mac's own loopback address for as long as one sign-in
/// takes. The card shows the page's domain before it opens; what comes back is kept as the device's `signIn` field.
enum VendorSignIn {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// The domain the card names before the page opens.
    static func domain(of page: String) -> String? { URL(string: page)?.host }

    /// Opens the page with `{callback}` filled and waits for the vendor to send the person back, up to ten minutes.
    /// The answer is the query (or form body) the vendor sent back.
    static func run(page: String, values: [String: String]) async throws -> String {
        let listener = try Loopback()
        let callback = "http://127.0.0.1:\(listener.port)/callback"
        var filled = values
        filled["callback"] = callback
        let address = try Placeholders.fill(page, filled, in: .form)
        guard IntegrationCheck.isWebPage(address), let url = URL(string: address) else { throw Failure(message: "The sign-in page isn't an https page.") }
        await MainActor.run { _ = NSWorkspace.shared.open(url) }
        return try await listener.wait(timeout: 600)
    }

    /// One listener on 127.0.0.1 at a port the system picks, answering only `/callback`.
    final class Loopback: @unchecked Sendable {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "lamp.vendor-signin")
        private var continuation: CheckedContinuation<String, Error>?
        private var finished = false
        let port: UInt16

        init() throws {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
            listener = try NWListener(using: parameters)
            let ready = DispatchSemaphore(value: 0)
            listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
            listener.newConnectionHandler = { _ in }
            listener.start(queue: queue)
            _ = ready.wait(timeout: .now() + 3)
            guard let port = listener.port?.rawValue else { listener.cancel(); throw Failure(message: "Lamp couldn't listen for the sign-in on this Mac.") }
            self.port = port
        }

        func wait(timeout: TimeInterval) async throws -> String {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    self.continuation = continuation
                    self.listener.newConnectionHandler = { [weak self] in self?.handle($0) }
                    self.queue.asyncAfter(deadline: .now() + timeout) { self.finish(.failure(Failure(message: "The sign-in wasn't finished in time. Try again."))) }
                }
            }
        }

        private func finish(_ result: Result<String, Error>) {
            guard !finished else { return }
            finished = true
            listener.cancel()
            continuation?.resume(with: result)
            continuation = nil
        }

        private func handle(_ connection: NWConnection) {
            connection.start(queue: queue)
            var received = Data()
            func more() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
                    guard let self else { return }
                    if let data { received.append(data) }
                    let text = String(decoding: received, as: UTF8.self)
                    if let end = text.range(of: "\r\n\r\n") {
                        let head = String(text[..<end.lowerBound])
                        let length = head.split(separator: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }
                            .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
                        let body = String(text[end.upperBound...])
                        if body.utf8.count >= length {
                            let page = "<html><body style=\"font: 15px -apple-system; padding: 40px\">You're signed in. You can close this page and go back to Lamp.</body></html>"
                            let reply = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(page.utf8.count)\r\nConnection: close\r\n\r\n\(page)"
                            connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in connection.cancel() })
                            let line = head.split(separator: "\r\n").first.map(String.init) ?? ""
                            let target = line.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                            if target.hasPrefix("/callback") {
                                let query = target.split(separator: "?", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
                                self.finish(.success(body.isEmpty ? query : body))
                            }
                            return
                        }
                    }
                    if done || error != nil || received.count > 1 << 20 { connection.cancel(); return }
                    more()
                }
            }
            more()
        }
    }
}
