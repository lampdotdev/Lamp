import Foundation
import Network

/// The way out to the internet for the sidebar preview's page reader (`PageReader`), and its only one: the reader's
/// web view is given this as its proxy (WebKit's `proxyConfigurations`), so every connection the page makes, the
/// page itself, its redirects and everything it loads, comes here first. A name says nothing about where it leads
/// (any domain can point at this Mac or the local network), so each one is looked up here, refused when any of its
/// addresses is this Mac, the local network or another range that isn't the internet, and connected to the very
/// address that was checked, so a second lookup can't send it elsewhere. It listens on this Mac only, for as long
/// as one page is read.
final class PublicOnlyProxy: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "PublicOnlyProxy")
    private var open: [ObjectIdentifier: NWConnection] = [:]
    private var refusedHosts: [String] = []

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    /// The hosts turned away so far, for saying why a page couldn't be read.
    var refused: [String] { queue.sync { refusedHosts } }

    /// Starts listening; the port, or nil when it couldn't (the reader then reads nothing).
    func start() async -> NWEndpoint.Port? {
        await withCheckedContinuation { done in
            // The listener reports on `queue` only, so its states arrive one at a time.
            final class Once: @unchecked Sendable { var done = false }
            let once = Once()
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready: if !once.done { once.done = true; done.resume(returning: listener.port) }
                case .failed, .cancelled: if !once.done { once.done = true; done.resume(returning: nil) }
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue: queue)
        }
    }

    func stop() {
        queue.async { [self] in
            listener.cancel()
            open.values.forEach { $0.cancel() }
            open = [:]
        }
    }

    // MARK: One tunnel

    private func keep(_ connection: NWConnection) {
        open[ObjectIdentifier(connection)] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .failed, .cancelled: self.open[ObjectIdentifier(connection)] = nil
            default: break
            }
        }
    }

    private func accept(_ client: NWConnection) {
        keep(client)
        client.start(queue: queue)
        readRequest(client, Data())
    }

    /// The request is `CONNECT host:port HTTP/1.1` and its headers; anything else is refused.
    private func readRequest(_ client: NWConnection, _ sofar: Data) {
        client.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, complete, error in
            guard let self else { return }
            var buffer = sofar
            if let data { buffer.append(data) }
            guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                if complete || error != nil || buffer.count > 16_384 { client.cancel() } else { self.readRequest(client, buffer) }
                return
            }
            let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
            let rest = buffer[end.upperBound...]
            let words = head.split(separator: "\r\n").first?.split(separator: " ") ?? []
            guard words.count == 3, words[0] == "CONNECT", let (host, port) = Self.target(String(words[1])) else {
                return self.answer(client, "405 Method Not Allowed")
            }
            // The lookup can take a while: off this queue, then back to it.
            DispatchQueue.global().async {
                let addresses = Self.resolve(host)
                self.queue.async {
                    guard let first = addresses.first, addresses.allSatisfy(Self.isPublic) else {
                        self.refusedHosts.append(host)
                        return self.answer(client, "403 Forbidden")
                    }
                    self.tunnel(client, to: first, port: port, carrying: Data(rest))
                }
            }
        }
    }

    private func answer(_ client: NWConnection, _ status: String) {
        client.send(content: Data("HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8),
                    completion: .contentProcessed { _ in client.cancel() })
    }

    private func tunnel(_ client: NWConnection, to address: [UInt8], port: NWEndpoint.Port, carrying early: Data) {
        let host: NWEndpoint.Host = address.count == 4 ? .ipv4(IPv4Address(Data(address))!) : .ipv6(IPv6Address(Data(address))!)
        let upstream = NWConnection(host: host, port: port, using: .tcp)
        keep(upstream)
        var settled = false
        upstream.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready where !settled:
                settled = true
                client.send(content: Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8), completion: .contentProcessed { _ in
                    if !early.isEmpty { upstream.send(content: early, completion: .idempotent) }
                    self.pump(client, upstream)
                    self.pump(upstream, client)
                })
            case .waiting, .failed:
                if !settled { settled = true; self.answer(client, "502 Bad Gateway"); upstream.cancel() }
            case .cancelled:
                self.open[ObjectIdentifier(upstream)] = nil
                client.cancel()
            default: break
            }
        }
        upstream.start(queue: queue)
    }

    private func pump(_ from: NWConnection, _ to: NWConnection) {
        from.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            if let data, !data.isEmpty {
                to.send(content: data, completion: .contentProcessed { sent in
                    if sent == nil, !complete, error == nil { self?.pump(from, to) } else { from.cancel(); to.cancel() }
                })
            } else if complete || error != nil {
                from.cancel(); to.cancel()
            } else {
                self?.pump(from, to)
            }
        }
    }

    // MARK: Checks

    /// `host:port` or `[v6]:port` from a CONNECT line.
    static func target(_ authority: String) -> (String, NWEndpoint.Port)? {
        guard let colon = authority.lastIndex(of: ":"), let number = UInt16(authority[authority.index(after: colon)...]),
              number > 0, let port = NWEndpoint.Port(rawValue: number) else { return nil }
        var host = String(authority[..<colon])
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        return host.isEmpty || host.count > 253 ? nil : (host, port)
    }

    /// Every address the system's resolver gives for a name (or the literal address), as raw bytes.
    static func resolve(_ host: String) -> [[UInt8]] {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: IPPROTO_TCP,
                             ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &list) == 0, let list else { return [] }
        defer { freeaddrinfo(list) }
        var found: [[UInt8]] = []
        for entry in sequence(first: list, next: { $0.pointee.ai_next }) {
            guard let address = entry.pointee.ai_addr else { continue }
            if entry.pointee.ai_family == AF_INET {
                var v4 = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                found.append(withUnsafeBytes(of: &v4) { Array($0) })
            } else if entry.pointee.ai_family == AF_INET6 {
                var v6 = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
                found.append(withUnsafeBytes(of: &v6) { Array($0) })
            }
        }
        return found
    }

    /// Whether an address (4 or 16 bytes) is on the internet: not unspecified, this Mac, link-local, private,
    /// shared (CGN), multicast, reserved or for documentation, including an IPv4 one carried inside IPv6.
    static func isPublic(_ a: [UInt8]) -> Bool {
        if a.count == 4 {
            switch (a[0], a[1], a[2]) {
            case (0, _, _), (10, _, _), (127, _, _), (169, 254, _), (192, 168, _), (192, 0, 0), (192, 0, 2), (192, 88, 99),
                 (198, 51, 100), (203, 0, 113): return false
            case (100, let b, _) where (64...127).contains(b): return false
            case (172, let b, _) where (16...31).contains(b): return false
            case (198, let b, _) where b == 18 || b == 19: return false
            case (let x, _, _) where x >= 224: return false
            default: return true
            }
        }
        guard a.count == 16 else { return false }
        if a[0..<10].allSatisfy({ $0 == 0 }) && a[10] == 0xff && a[11] == 0xff { return isPublic(Array(a[12...])) }  // ::ffff:v4
        if a[0..<12].allSatisfy({ $0 == 0 }) { return false }                                                     // ::, ::1, ::v4
        if a[0..<12] == [0, 0x64, 0xff, 0x9b, 0, 0, 0, 0, 0, 0, 0, 0] { return isPublic(Array(a[12...])) }      // NAT64
        if a[0] == 0x20 && a[1] == 0x02 { return isPublic(Array(a[2..<6])) }                                     // 6to4
        if a[0] == 0x20 && a[1] == 0x01 && (a[2] == 0x0d && a[3] == 0xb8 || a[2] == 0 && a[3] == 0) { return false } // docs, Teredo
        if a[0] == 0 && a[1] == 0x64 && a[2] == 0xff && a[3] == 0x9b { return false }                            // local NAT64
        if a[0] == 0x01 && a[1] == 0 && a[2...7].allSatisfy({ $0 == 0 }) { return false }                         // discard
        if a[0] & 0xfe == 0xfc { return false }                                                                  // unique local
        if a[0] == 0xfe && a[1] & 0x80 == 0x80 { return false }                                                  // link- and site-local
        if a[0] == 0xff { return false }                                                                         // multicast
        return true
    }
}
