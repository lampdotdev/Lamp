import CryptoKit
import LampRelayKit
import XCTest

/// A phone sending the TV app something bigger than a message, such as a game for the TV to play: through the relay, in
/// pieces, every byte arriving as it was sent, more than a window's worth so the sender has to wait for the TV's
/// acknowledgements on the way.
final class RelayTransferTests: XCTestCase {
    private let key = SymmetricKey(size: .bits256)

    func testAPhoneSendsTheTVAFileBiggerThanAMessage() async throws {
        let relay = Relay(key: key)
        defer { relay.stop() }
        let started: UInt16? = await withCheckedContinuation { done in relay.start { done.resume(returning: $0) } }
        let port = try XCTUnwrap(started)
        relay.configure(app: "game", Relay.Session(generation: 0, pagePort: nil, page: nil, hosts: []))
        let address = try XCTUnwrap(URL(string: "ws://127.0.0.1:\(port)/"))

        let host = URLSession.shared.webSocketTask(with: address)
        host.maximumMessageSize = 1 << 20
        host.resume()
        try await host.send(.string(Self.json(["t": "hello", "app": "game",
                                               "credential": ControllerToken.issue(kind: .host, app: "game", generation: 0, key: key)])))
        let welcome = try await Self.text(host)
        XCTAssertEqual(welcome["role"] as? String, "host")

        let phone = URLSession.shared.webSocketTask(with: address)
        phone.maximumMessageSize = 1 << 20
        phone.resume()
        try await phone.send(.string(Self.json(["t": "hello", "app": "game",
                                                "credential": ControllerToken.issue(kind: .join, app: "game", generation: 0, key: key)])))
        let welcomed = try await Self.text(phone)
        XCTAssertEqual(welcomed["role"] as? String, "controller")
        let joined = try await Self.text(host)
        XCTAssertEqual(joined["t"] as? String, "joined")
        let place = try XCTUnwrap(joined["player"] as? Int)

        let file = Data((0..<1_500_000).map { _ in UInt8.random(in: 0...255) })
        try await phone.send(.string(Self.json(["t": "file", "id": 1, "name": "game.nes", "type": "application/octet-stream", "size": file.count])))
        let announced = try await Self.text(host)
        XCTAssertEqual(announced["t"] as? String, "file")
        XCTAssertEqual(announced["size"] as? Int, file.count)
        XCTAssertEqual(announced["player"] as? Int, place)

        // The TV takes each piece and acknowledges it; the phone sends no more than a window past what's acknowledged.
        let tv = Task { () -> Data in
            var received = Data()
            while received.count < file.count {
                guard case .data(let piece) = try await host.receive() else { continue }
                XCTAssertEqual(ControllerWire.chunkHeader(piece)?.player, UInt8(place))
                received.append(piece.dropFirst(ControllerWire.header))
                try await host.send(.string(Self.json(["t": "file-ack", "player": place, "id": 1, "got": received.count])))
            }
            return received
        }
        var sent = 0, acknowledged = 0
        while sent < file.count {
            if sent - acknowledged >= ControllerWire.window {
                let ack = try await Self.text(phone)
                if ack["t"] as? String == "file-ack" { acknowledged = ack["got"] as? Int ?? acknowledged }
                continue
            }
            let count = min(ControllerWire.chunk, file.count - sent)
            var piece = Data([1, 0, 0, 0, 0, 0, 0, 1])
            piece.append(file[sent..<(sent + count)])
            try await phone.send(.data(piece))
            sent += count
        }
        let received = try await tv.value
        XCTAssertEqual(received, file, "every byte arrived as it was sent")
        host.cancel(with: .goingAway, reason: nil)
        phone.cancel(with: .goingAway, reason: nil)
    }

    /// The next text message on a socket, past beats.
    private static func text(_ socket: URLSessionWebSocketTask) async throws -> [String: Any] {
        while true {
            if case .string(let text) = try await socket.receive(),
               let message = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any], message["t"] as? String != "beat" {
                return message
            }
        }
    }

    private static func json(_ value: [String: Any]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: value)) ?? Data(), as: UTF8.self)
    }
}
