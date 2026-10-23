import Foundation
import Network

/// One WebSocket the relay has taken (the Network framework speaks the protocol), on the relay's queue. Text goes out at
/// once; a file's pieces wait their turn, one handed to the network at a time, so a button pressed meanwhile never waits
/// behind more than one piece.
final class RelayPeer {
    let connection: NWConnection
    private(set) var open = true
    private(set) var heard = Date()
    /// Text messages not yet handed to the network: how far behind the other end is.
    private(set) var pendingText = 0
    private var pendingTextBytes = 0
    /// Past its handshake: until then a close frame can't go, and only cancelling lets the socket go.
    private var ready = false
    private var queue: DispatchQueue?
    private var pieces: [Data] = []
    private var pieceBytes = 0
    private var sendingPiece = false
    var onText: (String) -> Void = { _ in }
    var onBinary: (Data) -> Void = { _ in }
    var onClose: () -> Void = {}

    /// The most a peer may have waiting to go: every file it can be sent at once, each a window ahead.
    static let pieceLimit = ControllerWire.players * ControllerWire.transfers * (ControllerWire.window + ControllerWire.chunk + ControllerWire.header)
    /// Text a peer that has stopped reading may fall behind by before it's let go, so it can't make the relay hold
    /// everything said to it meanwhile.
    static let textLimit = (messages: 256, bytes: 2 * 1024 * 1024)

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start(on queue: DispatchQueue) {
        self.queue = queue
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.ready = true
            case .failed, .cancelled: self?.closed()
            default: break
            }
        }
        connection.start(queue: queue)
        receive()
    }

    func send(_ text: String) {
        guard open else { return }
        let data = Data(text.utf8)
        guard pendingText < Self.textLimit.messages, pendingTextBytes + data.count <= Self.textLimit.bytes else { return close(code: 4002) }
        pendingText += 1
        pendingTextBytes += data.count
        let context = NWConnection.ContentContext(identifier: "text", metadata: [NWProtocolWebSocket.Metadata(opcode: .text)])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { [weak self] _ in
            self?.pendingText -= 1
            self?.pendingTextBytes -= data.count
        })
    }

    /// Queues a piece of a file; false when the peer already has more waiting than it could ever be owed.
    @discardableResult
    func send(piece: Data) -> Bool {
        guard open else { return false }
        guard pieceBytes + piece.count <= Self.pieceLimit else { return false }
        pieces.append(piece)
        pieceBytes += piece.count
        pump()
        return true
    }

    private func pump() {
        guard open, !sendingPiece, !pieces.isEmpty else { return }
        let piece = pieces.removeFirst()
        pieceBytes -= piece.count
        sendingPiece = true
        let context = NWConnection.ContentContext(identifier: "piece", metadata: [NWProtocolWebSocket.Metadata(opcode: .binary)])
        connection.send(content: piece, contentContext: context, isComplete: true, completion: .contentProcessed { [weak self] _ in
            self?.sendingPiece = false
            self?.pump()
        })
    }

    /// Says why, when the socket can still hear it, and lets it go either way: a close frame can't go before the
    /// handshake, nor to a peer that has stopped reading, and waiting for it to would hold the socket for good.
    func close(code: UInt16 = 1000) {
        guard open else { return }
        let connection = connection
        if ready {
            let metadata = NWProtocolWebSocket.Metadata(opcode: .close)
            metadata.closeCode = code >= 4000 ? .privateCode(code) : (NWProtocolWebSocket.CloseCode.Defined(rawValue: code).map { .protocolCode($0) } ?? .protocolCode(.normalClosure))
            let context = NWConnection.ContentContext(identifier: "close", metadata: [metadata])
            connection.send(content: nil, contentContext: context, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
            queue?.asyncAfter(deadline: .now() + 2) { connection.cancel() }
        } else {
            connection.cancel()
        }
        closed()
    }

    private func closed() {
        guard open else { return }
        open = false
        pieces = []
        pieceBytes = 0
        onClose()
    }

    private func receive() {
        connection.receiveMessage { [weak self] content, context, _, error in
            guard let self, self.open else { return }
            if error != nil {
                self.connection.cancel()
                return self.closed()
            }
            let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
            self.heard = Date()
            switch metadata?.opcode {
            case .text?:
                let data = content ?? Data()
                guard data.count <= ControllerWire.message else { return self.close(code: 1009) }
                self.onText(String(decoding: data, as: UTF8.self))
            case .binary?:
                self.onBinary(content ?? Data())
            case .close?:
                self.connection.cancel()
                return self.closed()
            default:
                break
            }
            if self.open { self.receive() }
        }
    }
}
