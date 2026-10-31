import CryptoKit
import LampRelayKit
import Network
import XCTest
@testable import Lamp

/// A file's pieces as a TV page's browser and an Android app send them: each message one unfragmented WebSocket frame
/// (a browser's `send` and LampSupport.kt's `Ws.write` never split one), not split as the Network framework splits
/// what a Swift app sends. A file of several full pieces gets through the relay whole, and the sender keeps its link.
final class WishFramingTests: XCTestCase {
    /// One app of the wish on a plain TCP socket, speaking just enough WebSocket: every message is a single masked frame.
    final class RawPeer {
        let connection: NWConnection
        var sealer: WishChannel.Sealer?
        var opener: WishChannel.Sealer?
        private var buffer = Data()
        private let queue = DispatchQueue(label: "raw-peer")

        init(port: UInt16) { connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp) }

        func write(_ data: Data) async throws {
            try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
                connection.send(content: data, completion: .contentProcessed { error in error.map { done.resume(throwing: $0) } ?? done.resume() })
            }
        }

        private func more() async throws {
            let data: Data = try await withCheckedThrowingContinuation { done in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { data, _, complete, error in
                    if let error { return done.resume(throwing: error) }
                    if let data, !data.isEmpty { return done.resume(returning: data) }
                    done.resume(throwing: complete ? URLError(.networkConnectionLost) : URLError(.unknown))
                }
            }
            buffer.append(data)
        }

        func open() async throws {
            connection.start(queue: queue)
            try await write(Data("GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n".utf8))
            while buffer.range(of: Data("\r\n\r\n".utf8)) == nil { try await more() }
            buffer.removeSubrange(..<buffer.range(of: Data("\r\n\r\n".utf8))!.upperBound)
        }

        /// One whole message in one frame, never split.
        func frame(_ payload: Data, text: Bool) async throws {
            var frame = Data([text ? 0x81 : 0x82])
            let mask: [UInt8] = [0x37, 0xfa, 0x21, 0x3d]
            if payload.count < 126 { frame.append(0x80 | UInt8(payload.count)) }
            else if payload.count < 65536 { frame.append(contentsOf: [0x80 | 126, UInt8(payload.count >> 8), UInt8(payload.count & 0xff)]) }
            else { frame.append(0x80 | 127); for i in (0..<8).reversed() { frame.append(UInt8((payload.count >> (8 * i)) & 0xff)) } }
            frame.append(contentsOf: mask)
            frame.append(Data(payload.enumerated().map { $0.element ^ mask[$0.offset % 4] }))
            // In segments of a network's size, a moment apart, as a frame arrives from a device on Wi-Fi rather than
            // in one piece over the loopback.
            var at = frame.startIndex
            while at < frame.endIndex {
                let end = min(at + 1448, frame.endIndex)
                try await write(frame.subdata(in: at..<end))
                at = end
                if at < frame.endIndex, (at - frame.startIndex) % (1448 * 16) == 0 { try await Task.sleep(for: .milliseconds(2)) }
            }
        }

        /// The next data frame: whether it's text, and its bytes.
        func next() async throws -> (text: Bool, data: Data) {
            while true {
                while buffer.count < 2 { try await more() }
                let b = [UInt8](buffer.prefix(14))
                var length = Int(b[1] & 0x7f), at = 2
                if length == 126 { while buffer.count < 4 { try await more() }; length = Int([UInt8](buffer.prefix(4))[2]) << 8 | Int([UInt8](buffer.prefix(4))[3]); at = 4 }
                else if length == 127 { while buffer.count < 10 { try await more() }; length = [UInt8](buffer.prefix(10))[2..<10].reduce(0) { $0 << 8 | Int($1) }; at = 10 }
                while buffer.count < at + length { try await more() }
                let opcode = b[0] & 0x0f, payload = buffer.subdata(in: (buffer.startIndex + at)..<(buffer.startIndex + at + length))
                buffer.removeSubrange(buffer.startIndex..<(buffer.startIndex + at + length))
                if opcode == 8 { throw URLError(.networkConnectionLost) }
                if opcode == 1 || opcode == 2 { return (opcode == 1, payload) }
            }
        }

        /// The next sealed message, past beats.
        func nextSealed() async throws -> Data {
            while true {
                let (text, data) = try await next()
                if !text { return try XCTUnwrap(opener!.open(data)) }
            }
        }

        func send(_ value: [String: Any]) async throws { try await frame(sealer!.seal(try JSONSerialization.data(withJSONObject: value)), text: false) }
        func sendPlain(_ data: Data) async throws { try await frame(sealer!.seal(data), text: false) }

        static func join(port: UInt16, as peer: String, key: Data) async throws -> RawPeer {
            let joined = RawPeer(port: port)
            try await joined.open()
            let key = SymmetricKey(data: key)
            let tag = WishChannel.tag(for: key), nonce = WishChannel.random(16)
            try await joined.frame(Data(WishRoomTests.json(["t": "hello", "tag": tag.base64EncodedString(), "peer": peer, "nonce": nonce.base64EncodedString()]).utf8), text: true)
            let (_, said) = try await joined.next()
            let challenge = try XCTUnwrap(WishRoomTests.parse(String(decoding: said, as: UTF8.self)))
            let theirs = try XCTUnwrap((challenge["nonce"] as? String).flatMap { Data(base64Encoded: $0) })
            let transcript = WishChannel.transcript(tag: tag, client: peer, server: challenge["peer"] as? String ?? "", clientNonce: nonce, serverNonce: theirs)
            try await joined.frame(Data(WishRoomTests.json(["t": "proof", "proof": WishChannel.clientProof(key: key, transcript: transcript).base64EncodedString()]).utf8), text: true)
            let keys = WishChannel.keys(key: key, transcript: transcript)
            joined.sealer = WishChannel.Sealer(key: keys.client)
            joined.opener = WishChannel.Sealer(key: keys.server)
            try await joined.send(["t": "join", "device": "TV", "wire": 3])
            return joined
        }
    }

    /// A TV page sending a file of three full pieces and a tail, each piece one frame: the other app gets all of it, and
    /// the page's link stays up.
    func testAFileOfSeveralPiecesSentAsSingleFramesGoesThroughTheRelay() async throws {
        let relay = Relay(key: SymmetricKey(size: .bits256))
        let started: UInt16? = await withCheckedContinuation { done in relay.start { done.resume(returning: $0) } }
        defer { relay.stop() }
        let port = try XCTUnwrap(started)
        let key = WishChannel.random(32)
        relay.configureRoom("wish:framing", key: key, apps: ["tv": ("tv", "the TV app"), "android": ("android", "the Android app")])
        let tv = try await RawPeer.join(port: port, as: "tv", key: key)
        _ = try await tv.nextSealed()   // welcome
        let android = try await WishPeer.join(try XCTUnwrap(URL(string: "ws://127.0.0.1:\(port)/")), as: "android", device: "Android", key: key, wire: 3)
        _ = try await android.next()    // welcome
        _ = try await tv.nextSealed()   // joined

        let chunk = WishChannel.pieceSize
        let size = chunk * 3 + 1000
        try await tv.send(["t": "file", "to": "android", "id": 5, "name": "save.dat", "type": "", "size": size])
        let started2 = try await android.next()
        XCTAssertEqual(started2["t"] as? String, "file")
        var got = 0, offset = 0
        while offset < size {
            let n = min(chunk, size - offset)
            try await tv.sendPlain(WishChannel.piece(peer: "android", id: 5, bytes: Data(repeating: UInt8(offset / chunk), count: n)))
            offset += n
            let piece = try await android.nextPlain()
            let header = try XCTUnwrap(WishChannel.pieceHeader(piece))
            got += piece.count - header.offset
            try await android.send(["t": "file-ack", "to": "tv", "id": 5, "got": got])
            let ack = try WishRoomTests.parse(String(decoding: await tv.nextSealed(), as: UTF8.self))
            XCTAssertEqual(ack?["got"] as? Int, got, "acknowledged as it came")
        }
        XCTAssertEqual(got, size, "the whole file arrived")
        try await tv.send(["t": "send", "data": "still here"])
        let after = try await android.next()
        XCTAssertEqual(after["data"] as? String, "still here", "the page's link stayed up")
    }

    /// The TV preview's own WebKit sending full-size pieces, and a little more, each as the one frame a browser sends,
    /// to a socket set up as the relay's: every one arrives whole.
    @MainActor func testABrowsersSingleFramePiecesFitTheRelaysSocket() async throws {
        let options = NWProtocolWebSocket.Options()
        options.autoReplyPing = true
        options.maximumMessageSize = Relay.messageLimit
        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        let listener = try NWListener(using: parameters, on: .any)
        defer { listener.cancel() }
        var sizes: [Int] = [], failed = false
        func receive(_ connection: NWConnection) {
            connection.receiveMessage { data, _, _, error in
                MainActor.assumeIsolated {
                    guard error == nil else { failed = true; return }
                    if let data { sizes.append(data.count) }
                    receive(connection)
                }
            }
        }
        listener.newConnectionHandler = { connection in MainActor.assumeIsolated { connection.start(queue: .main); receive(connection) } }
        listener.start(queue: .main)
        for _ in 0..<50 where (listener.port?.rawValue ?? 0) == 0 { try await Task.sleep(for: .milliseconds(50)) }
        let port = try XCTUnwrap(listener.port?.rawValue)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wish-framing-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("app"), staged = root.appendingPathComponent("web")
        for folder in [dir, staged] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        // A whole sealed piece behind the longest peer name, and a little past it.
        let largest = WishChannel.piece(peer: String(repeating: "a", count: 32), id: 1, bytes: Data(count: WishChannel.pieceSize)).count + 16
        let wanted = [1000, largest - 100, largest, largest + 500]
        try """
            <html><body><script>
            var s = new WebSocket('ws://127.0.0.1:\(port)/');
            s.binaryType = 'arraybuffer';
            s.onopen = function () { \(wanted).forEach(function (n) { s.send(new Uint8Array(n).buffer); }); };
            </script></body></html>
            """.write(to: staged.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        var project = LampProject(id: "wish-framing", name: "Frames", exe: "Frames", dir: dir, platform: .tv)
        project.instance = UUID().uuidString
        let store = try XCTUnwrap(TVPreview.store(for: project.instance))
        defer { Task { _ = await PreviewStores.remove(store, tries: 20) } }
        let shown = await TVPreview.show(project, staged: staged, inFront: false)
        XCTAssertNil(shown)
        defer { TVPreview.close(project) }
        for _ in 0..<100 where sizes.count < wanted.count && !failed { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertFalse(failed, "the socket was cut")
        XCTAssertEqual(sizes, wanted)
    }
}
