import Foundation
import LampOutsideKit

/// Lamp's MCP server for the person's own coding agent (Claude Code, Codex), reached through the helper that agent starts
/// over stdio (`lamp-mcp`, in Lamp's Helpers). It listens on a Unix socket in a folder of this Lamp's own
/// (`OutsideKit.socketFolder`, by `Edition`), private to the person: the folder is 0700 and Lamp's own, and each
/// connection's peer must be the person's own user (`getpeereid`). No port and no token: being the person, on this Mac,
/// running a helper that reaches this folder, is what lets a program in. What it may do is `OutsideWork`'s tools.
///
/// Two copies of the same Lamp never share it: a socket another copy still answers on is left to it, and this copy goes
/// without (said in the log). One nothing answers on is from a copy that ended, and is replaced.
final class OutsideServer: @unchecked Sendable {
    static let shared = OutsideServer()

    private var listener: Int32 = -1
    private let lock = NSLock()
    private var nextConnection = 0
    /// The calls running for each connection, by their JSON-RPC id, so a cancel or the connection's end can reach them.
    private var running: [Int: [String: Task<Void, Never>]] = [:]
    private var alive: Set<Int> = []

    /// Why it isn't listening, when it isn't.
    private(set) var problem: String?

    func start() {
        let folder = OutsideKit.socketFolder(bundleID: Edition.bundleID)
        let path = OutsideKit.socketPath(bundleID: Edition.bundleID)
        do {
            try Self.prepare(folder: folder)
            guard path.utf8.count <= OutsideKit.maxSocketPath else {
                throw Problem("the socket's path is \(path.utf8.count) bytes, over the \(OutsideKit.maxSocketPath) macOS allows")
            }
            try Self.clearStale(path)
            listener = try Self.listen(at: path)
        } catch {
            problem = "\(error)"
            NSLog("Lamp's MCP socket isn't open: \(error)")
            return
        }
        Thread.detachNewThread { [self] in acceptLoop() }
    }

    struct Problem: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    /// The socket's folder, made the person's alone. One that is a link, someone else's, or open to others is refused:
    /// Lamp made it 0700 and nothing of Lamp's changes that, so it's been changed by something else.
    static func prepare(folder: URL) throws {
        var info = stat()
        if lstat(folder.path, &info) != 0 {
            try FileManager.default.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard mkdir(folder.path, 0o700) == 0 || errno == EEXIST else { throw Problem("couldn't make \(folder.path): \(String(cString: strerror(errno)))") }
            guard lstat(folder.path, &info) == 0 else { throw Problem("couldn't read \(folder.path)") }
        }
        guard info.st_mode & S_IFMT == S_IFDIR else { throw Problem("\(folder.path) isn't a folder") }
        guard info.st_uid == geteuid() else { throw Problem("\(folder.path) belongs to someone else") }
        guard info.st_mode & 0o077 == 0 else { throw Problem("\(folder.path) is open to others (mode \(String(info.st_mode & 0o777, radix: 8)))") }
    }

    /// A socket left at the path by a copy of this Lamp that has ended is removed; one a running copy answers on, or
    /// anything that isn't a socket, is left where it is and this copy goes without.
    static func clearStale(_ path: String) throws {
        var info = stat()
        guard lstat(path, &info) == 0 else { return }
        guard info.st_mode & S_IFMT == S_IFSOCK else { throw Problem("\(path) is there and isn't a socket") }
        let probe = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(probe) }
        var address = Self.address(path)
        let answered = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(probe, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        } == 0
        if answered { throw Problem("another copy of \(Edition.name) is answering on its socket") }
        guard unlink(path) == 0 else { throw Problem("couldn't remove the old socket: \(String(cString: strerror(errno)))") }
    }

    static func address(_ path: String) -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: Array(path.utf8.prefix(OutsideKit.maxSocketPath)) + [0])
        }
        return address
    }

    private static func listen(at path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Problem("no socket: \(String(cString: strerror(errno)))") }
        var address = address(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0 else { close(fd); throw Problem("couldn't bind \(path): \(String(cString: strerror(errno)))") }
        chmod(path, 0o600)
        guard Darwin.listen(fd, 8) == 0 else { close(fd); throw Problem("couldn't listen: \(String(cString: strerror(errno)))") }
        return fd
    }

    private func acceptLoop() {
        while true {
            let fd = accept(listener, nil, nil)
            if fd < 0 { if errno == EINTR { continue }; return }
            var uid: uid_t = 0, gid: gid_t = 0
            // Only the person's own programs: another user on this Mac can't reach the folder, and this says so again.
            guard getpeereid(fd, &uid, &gid) == 0, uid == geteuid() else { close(fd); continue }
            var one: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            lock.lock()
            nextConnection += 1
            let id = nextConnection
            alive.insert(id)
            lock.unlock()
            Thread.detachNewThread { [self] in serve(fd, connection: id) }
        }
    }

    private func serve(_ fd: Int32, connection: Int) {
        let writer = Writer(fd: fd)
        var greeted = false
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 1 << 16)
        reading: while true {
            let count = read(fd, &chunk, chunk.count)
            if count <= 0 { break }
            buffer.append(contentsOf: chunk[0..<count])
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[buffer.startIndex..<newline])
                buffer = Data(buffer[buffer.index(after: newline)...])
                guard !line.isEmpty else { continue }
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    writer.send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Not JSON."]])
                    continue
                }
                if !greeted {
                    guard let hello = object[OutsideKit.helloKey] as? [String: Any] else { break reading }
                    let theirs = hello["protocol"] as? Int ?? 0
                    if theirs < OutsideKit.oldestProtocol || theirs > OutsideKit.protocolVersion {
                        let fix = theirs < OutsideKit.oldestProtocol ? "This lamp-mcp is older than \(Edition.name): restart the agent's session so it starts the helper inside the Lamp that's installed."
                            : "This lamp-mcp is newer than the \(Edition.name) running: quit \(Edition.name) and open the copy the helper came with."
                        writer.send([OutsideKit.helloKey: ["error": fix]])
                        break reading
                    }
                    greeted = true
                    writer.send([OutsideKit.helloKey: ["protocol": OutsideKit.protocolVersion, "oldest": OutsideKit.oldestProtocol,
                                                       "edition": Edition.name, "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""]])
                    continue
                }
                handle(object, connection: connection, writer: writer)
            }
        }
        close(fd)
        // The connection's calls that haven't begun are dropped; one already running finishes, its answer kept for a retry.
        lock.lock()
        alive.remove(connection)
        running[connection] = nil
        lock.unlock()
        Task { @MainActor in Store.shared.outsideConnectionEnded(connection) }
    }

    func isAlive(_ connection: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return alive.contains(connection)
    }

    final class Writer: @unchecked Sendable {
        let fd: Int32
        private let lock = NSLock()
        init(fd: Int32) { self.fd = fd }
        func send(_ object: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
            lock.lock()
            defer { lock.unlock() }
            let line = data + Data("\n".utf8)
            line.withUnsafeBytes { raw in
                var offset = 0
                while offset < raw.count {
                    let wrote = write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                    if wrote <= 0 { return }
                    offset += wrote
                }
            }
        }
    }

    private func key(_ id: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: ["k": id])).map { String(decoding: $0, as: UTF8.self) } ?? "\(id)"
    }

    /// One JSON-RPC message from the agent. Lamp keeps no MCP session state beyond the connection, so a helper that
    /// reconnected after Lamp started again goes on without a second `initialize`.
    private func handle(_ message: [String: Any], connection: Int, writer: Writer) {
        let method = message["method"] as? String ?? ""
        let id = message["id"]
        func reply(_ result: [String: Any]) { if let id { writer.send(["jsonrpc": "2.0", "id": id, "result": result]) } }
        func fail(_ code: Int, _ text: String) { if let id { writer.send(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": text]]) } }
        let params = message["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            reply(["protocolVersion": OutsideKit.mcpVersions.contains(asked) ? asked : OutsideKit.mcpVersions[0],
                   "capabilities": ["tools": [:]],
                   "serverInfo": ["name": "lamp", "title": Edition.name, "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""],
                   "instructions": OutsideWork.instructions])
        case "notifications/initialized", "notifications/roots/list_changed":
            return
        case "ping":
            reply([:])
        case "tools/list":
            reply(["tools": OutsideWork.tools])
        case "tools/call":
            guard let id else { return }
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let callKey = key(id)
            let payload = OutsideWork.Payload(arguments)
            let task = Task { @MainActor in
                let answer = await Store.shared.outsideCall(name, payload, connection: connection)
                writer.send(["jsonrpc": "2.0", "id": id, "result": answer.mcp])
                self.lock.withLock { self.running[connection]?[callKey] = nil }
            }
            lock.lock()
            running[connection, default: [:]][callKey] = task
            lock.unlock()
        case "notifications/cancelled":
            guard let request = params["requestId"] else { return }
            lock.lock()
            let task = running[connection]?[key(request)]
            lock.unlock()
            task?.cancel()
        default:
            if id != nil { fail(-32601, "Lamp has no \(method).") }
        }
    }
}
