import Foundation

/// Samsung's bridge to a TV in developer mode, spoken directly: sdb is adb's protocol under another name, on the
/// TV's port 26101, so Lamp needs none of Tizen Studio to reach one. A connection opens with CNXN; each command is a
/// stream (OPEN … OKAY, WRTE answered by OKAY, CLSE), and files go up through the `sync:` service. A retail TV in
/// developer mode answers CNXN directly, with no key exchange. Blocking, one connection per use, off the main thread.
final class SdbConnection {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private enum Command: UInt32 {
        case cnxn = 0x4E58_4E43, auth = 0x4854_5541, open = 0x4E45_504F, okay = 0x5941_4B4F, wrte = 0x4554_5257, clse = 0x4553_4C43
    }
    private struct Frame {
        let command: UInt32
        let arg0: UInt32
        let arg1: UInt32
        let payload: Data
    }

    private let fd: Int32
    private var maxData = 4096
    private var nextLocal: UInt32 = 1
    /// What the TV called itself in its CNXN ("device::QN50LS03BAFXZA::0").
    private(set) var banner = ""

    init(host: String, port: UInt16 = 26101, timeout: TimeInterval = 10) throws {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_STREAM, ai_protocol: IPPROTO_TCP,
                             ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &info) == 0, let address = info else {
            throw Failure(message: "Couldn't find the TV at \(host).")
        }
        defer { freeaddrinfo(info) }
        fd = socket(address.pointee.ai_family, address.pointee.ai_socktype, address.pointee.ai_protocol)
        guard fd >= 0 else { throw Failure(message: "Couldn't open a connection to the TV.") }
        var wait = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        guard connect(fd, address.pointee.ai_addr, address.pointee.ai_addrlen) == 0 else {
            Darwin.close(fd)
            throw Failure(message: "The TV at \(host) didn't answer. It must be on, in developer mode, and on the same network as this Mac.")
        }
        try send(.cnxn, 0x0100_0000, UInt32(maxData), Data("host::lamp".utf8))
        let reply = try read()
        guard reply.command == Command.cnxn.rawValue else {
            close()
            throw Failure(message: reply.command == Command.auth.rawValue
                ? "The TV asked for a key Lamp doesn't hold. Turn developer mode off and on again on the TV, with this Mac's address."
                : "The TV answered in a way Lamp doesn't understand.")
        }
        // Each side keeps to the smaller of what both announced: the TV refuses a piece bigger than Lamp said it would send.
        if reply.arg1 > 0 { maxData = min(maxData, Int(reply.arg1)) }
        banner = String(decoding: reply.payload.prefix { $0 != 0 }, as: UTF8.self)
    }

    deinit { close() }
    private var closed = false
    func close() {
        guard !closed else { return }
        closed = true
        Darwin.close(fd)
    }

    // MARK: Frames

    private func send(_ command: Command, _ arg0: UInt32, _ arg1: UInt32, _ payload: Data = Data()) throws {
        var header = Data(capacity: 24)
        func put(_ value: UInt32) { var little = value.littleEndian; header.append(Data(bytes: &little, count: 4)) }
        put(command.rawValue); put(arg0); put(arg1); put(UInt32(payload.count))
        put(payload.reduce(UInt32(0)) { $0 &+ UInt32($1) }); put(command.rawValue ^ 0xFFFF_FFFF)
        try writeAll(header + payload)
    }

    private func writeAll(_ data: Data) throws {
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                guard written > 0 else { throw Failure(message: "The connection to the TV was cut off.") }
                offset += written
            }
        }
    }

    private func readExactly(_ count: Int) throws -> Data {
        var data = Data(count: count)
        var offset = 0
        try data.withUnsafeMutableBytes { buffer in
            while offset < count {
                let got = Darwin.read(fd, buffer.baseAddress! + offset, count - offset)
                guard got > 0 else { throw Failure(message: got == 0 ? "The TV closed the connection." : "The TV stopped answering.") }
                offset += got
            }
        }
        return data
    }

    private func read() throws -> Frame {
        let header = try readExactly(24)
        func value(_ at: Int) -> UInt32 { header.subdata(in: at..<at + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian }
        let length = Int(value(12))
        guard length <= 1 << 20 else { throw Failure(message: "The TV sent more than Lamp expected.") }
        return Frame(command: value(0), arg0: value(4), arg1: value(8), payload: length > 0 ? try readExactly(length) : Data())
    }

    // MARK: Streams

    /// One stream: opened, `body` writes on it if it needs to, and everything the TV writes back is gathered until
    /// it closes the stream. `onData` hears each piece as it comes.
    private func stream(_ service: String, onData: ((Data) -> Void)? = nil,
                        body: ((_ write: (Data) throws -> Void, _ readMore: () throws -> Data) throws -> Void)? = nil) throws -> Data {
        let local = nextLocal
        nextLocal += 1
        try send(.open, local, 0, Data(service.utf8) + Data([0]))
        var remote: UInt32 = 0
        var received = Data()
        var pending = Data()
        var ended = false
        // Reads one frame for this stream and handles it; true when it was an OKAY to a write of ours.
        func pump() throws -> Bool {
            let frame = try read()
            guard frame.arg1 == local else { return false }
            switch frame.command {
            case Command.okay.rawValue:
                if remote == 0 { remote = frame.arg0; return false }
                return true
            case Command.wrte.rawValue:
                received.append(frame.payload)
                pending.append(frame.payload)
                onData?(frame.payload)
                try send(.okay, local, frame.arg0)
            case Command.clse.rawValue:
                if remote == 0 { throw Failure(message: "The TV refused \(service.split(separator: ":").first ?? "")") }
                ended = true
            default: break
            }
            return false
        }
        while remote == 0 { _ = try pump() }
        if let body {
            try body({ data in
                var offset = 0
                while offset < data.count {
                    let piece = data.subdata(in: offset..<min(offset + maxData, data.count))
                    try send(.wrte, local, remote, piece)
                    while !(try pump()) { if ended { throw Failure(message: "The TV closed the stream while Lamp was sending.") } }
                    offset += piece.count
                }
            }, {
                while pending.isEmpty, !ended { _ = try pump() }
                defer { pending = Data() }
                return pending
            })
        }
        while !ended { _ = try pump() }
        try? send(.clse, local, remote)
        return received
    }

    /// A command the TV's sdbd knows (`0 getduid`, `0 vd_appinstall …`), with what it printed. `onLine` hears each
    /// line as it comes, for an install's progress.
    @discardableResult
    func shell(_ command: String, onLine: ((String) -> Void)? = nil) throws -> String {
        var partial = ""
        let out = try stream("shell:" + command, onData: { data in
            guard let onLine else { return }
            partial += String(decoding: data, as: UTF8.self)
            while let newline = partial.firstIndex(of: "\n") {
                let line = String(partial[..<newline]).trimmingCharacters(in: .whitespacesAndNewlines)
                partial = String(partial[partial.index(after: newline)...])
                if !line.isEmpty { onLine(line) }
            }
        })
        return String(decoding: out, as: UTF8.self)
    }

    /// What the TV says about itself: its Tizen version, where packages are staged, and the rest.
    func capability() throws -> [String: String] {
        let out = try stream("capability:")
        // Two bytes of length come first.
        let text = String(decoding: out.dropFirst(2), as: UTF8.self)
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 { result[parts[0]] = parts[1] }
        }
        return result
    }

    /// Puts `data` on the TV at `path` through the sync service.
    func push(_ data: Data, to path: String) throws {
        func packet(_ id: String, _ payload: Data) -> Data {
            var length = UInt32(payload.count).littleEndian
            return Data(id.utf8) + Data(bytes: &length, count: 4) + payload
        }
        _ = try stream("sync:") { write, readMore in
            try write(packet("SEND", Data(path.utf8)))
            var offset = 0
            while offset < data.count {
                let end = min(offset + 64 * 1024, data.count)
                try write(packet("DATA", data.subdata(in: offset..<end)))
                offset = end
            }
            var mtime = UInt32(Date().timeIntervalSince1970).littleEndian
            try write(packet("DONE", Data(bytes: &mtime, count: 4)))
            var reply = Data()
            while reply.count < 8 { reply.append(try readMore()) }
            let id = String(decoding: reply.prefix(4), as: UTF8.self)
            guard id == "OKAY" else {
                throw Failure(message: "The TV didn't take the package: \(String(decoding: reply.dropFirst(8), as: UTF8.self))")
            }
            try? write(packet("QUIT", Data()))
        }
    }
}
