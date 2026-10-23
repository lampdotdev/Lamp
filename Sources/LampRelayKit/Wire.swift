import Foundation

/// What a TV app and its controllers say to each other, the same on every link: through the relay (`Relay`), and on a
/// link straight to a wish's iPhone app (`LampController` in LampSupport). lamp.js and lamp-controller.js keep the same
/// numbers (`TVTemplate.filesJS`), and LampSupport its own copy.
///
/// Text messages are small JSON: a button, a stick, a message, and a file's start, acknowledgements and end. A file's
/// bytes go as binary messages of at most `chunk` bytes, each behind an 8-byte header: 1, the player it's for or from
/// (the relay's place for a phone; 0 on a direct link), two zero bytes, and the transfer's id (big-endian). The sender
/// sends at most `window` bytes past what the receiver has acknowledged (`file-ack`), so nothing between them ever holds
/// more than that for one file, and a button pressed meanwhile waits behind one piece at most: the relay and the
/// libraries send a piece only once the one before it has gone, and a text message never waits for a piece.
public enum ControllerWire {
    public static let message = 16 * 1024          // bytes, any text message
    public static let chunk = 64 * 1024            // bytes of a file in one binary message
    public static let header = 8
    public static let window = 512 * 1024          // bytes of a file sent ahead of what's acknowledged
    public static let file = 64 * 1024 * 1024      // the largest file
    public static let transfers = 2                // files at once each way, for each phone
    public static let players = 8
    public static let perSecond = 120.0            // messages a phone may send each second, a little over a screen's rate
    public static let backlog = 32                 // messages waiting to go to a TV past which movement is dropped
    public static let silence: TimeInterval = 15
    public static let beat: TimeInterval = 5

    /// The transfer a binary message belongs to, and who it's for or from, when it's well formed.
    public static func chunkHeader(_ data: Data) -> (player: UInt8, id: UInt32)? {
        guard data.count >= header else { return nil }
        let bytes = [UInt8](data.prefix(header))
        guard bytes[0] == 1 else { return nil }
        return (bytes[1], bytes[4...7].reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
    }

    /// The same piece, said to be for or from another player.
    public static func readdressed(_ data: Data, to player: UInt8) -> Data {
        var copy = data
        copy[copy.startIndex + 1] = player
        return copy
    }

    /// Whether a transfer's id is one a library would make: 1 and up, within 31 bits, as JavaScript counts them.
    public static func isID(_ value: Any?) -> UInt32? {
        guard let n = value as? Int, n > 0, n < 1 << 31 else { return nil }
        return UInt32(n)
    }
}
