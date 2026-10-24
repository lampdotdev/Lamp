import CryptoKit
import Foundation

/// How a wish's apps prove to each other that they're of the same wish, and then talk where nobody else on the network
/// can read or change what they say. Every app of a wish is given the wish's key when Lamp puts it on its device (32
/// random bytes, one per wish, kept in Lamp's own folder: `WishKeys`); it never travels in clear, and neither does
/// anything that would let someone else in. The relay (`Relay` rooms) is the side that listens; LampSupport.swift,
/// LampSupport.kt and lamp.js are the side that connects, each with its own copy of the same steps, so they must stay
/// byte for byte the same as these (`WishChannelTests` holds them to it).
///
/// The handshake, as JSON text on the socket, every value base64:
///
///   connecting side  {"t":"hello","tag":<8 bytes>,"peer":"tv","nonce":<16 random bytes>}
///   listening side   {"t":"challenge","peer":"lamp","nonce":<16 random bytes>,"proof":<32 bytes>}
///   connecting side  {"t":"proof","proof":<32 bytes>}
///
/// The tag (`tag(for:)`) tells the listener which wish this is without the wish being named on the network. Each proof
/// is an HMAC under the wish's key over everything said so far (`transcript`), with a label for which side made it, so
/// neither can be taken for the other, and both nonces are new each time, so a hello or a whole handshake seen on the
/// network and sent again gets nowhere. The connecting side checks the listener's proof before it sends its own.
///
/// Then each side has a key for what it sends (`keys`), made from the wish's key and the transcript, and everything
/// after the handshake is a binary message: AES-256-GCM under that key, with a nonce that counts the messages sent that
/// way from zero (`Sealer`), so a message can't be read, changed, dropped, sent again or put out of order without the
/// other side noticing, which lets the link go. Inside each is the same JSON the room spoke before (`welcome`, `send`,
/// `message`…); the connecting side's first is `{"t":"join","device":"…"}`. Only beats (`{"t":"beat"}`, every few seconds
/// each way) stay text in clear: they carry nothing, and an app whose socket Lamp holds for it has Lamp beat for it.
///
/// What it doesn't do: every app of the wish has the same key, so a device that has one of the wish's apps can join as
/// any of them; and there is no forward secrecy, so someone who recorded the traffic and later got the key could read it.
public enum WishChannel {
    public static let keySize = 32
    public static let tagSize = 8
    public static let nonceSize = 16
    /// What the relay calls itself in a handshake, as the listening side.
    public static let relayName = "lamp"
    /// The most a sealed message may hold: one message between the wish's apps, and its seal.
    public static let sealedLimit = ControllerWire.message + 1024

    /// HMAC-SHA256 under the wish's key of a label, a zero byte and what it's about: every value the channel derives.
    public static func derive(_ label: String, key: SymmetricKey, _ data: Data = Data()) -> Data {
        var message = Data(label.utf8)
        message.append(0)
        message.append(data)
        return Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
    }

    /// Which wish this is, as the listener knows it: the first 8 bytes of a value only the wish's key makes.
    public static func tag(for key: SymmetricKey) -> Data { derive("lamp-wish tag", key: key).prefix(tagSize) }

    /// A peer's name, as it may be in a handshake: Lamp's folder names, lowercased.
    public static func isName(_ name: String) -> Bool {
        (1...32).contains(name.utf8.count) && name.utf8.allSatisfy { ($0 >= 0x61 && $0 <= 0x7a) || ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2d }
    }

    /// Everything the handshake has said, in one order: the tag, each side's name with its length before it, and both nonces.
    public static func transcript(tag: Data, client: String, server: String, clientNonce: Data, serverNonce: Data) -> Data {
        var data = tag
        for name in [client, server] {
            data.append(UInt8(name.utf8.count))
            data.append(Data(name.utf8))
        }
        data.append(clientNonce)
        data.append(serverNonce)
        return data
    }

    public static func serverProof(key: SymmetricKey, transcript: Data) -> Data { derive("lamp-wish server", key: key, transcript) }
    public static func clientProof(key: SymmetricKey, transcript: Data) -> Data { derive("lamp-wish client", key: key, transcript) }

    /// The keys each side seals with: what the connecting side sends, and what the listening side sends.
    public static func keys(key: SymmetricKey, transcript: Data) -> (client: SymmetricKey, server: SymmetricKey) {
        (SymmetricKey(data: derive("lamp-wish c2s", key: key, transcript)), SymmetricKey(data: derive("lamp-wish s2c", key: key, transcript)))
    }

    /// Two values compared in a time that doesn't depend on where they differ.
    public static func same(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    public static func random(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: 0...255, using: &generator) })
    }

    /// One direction of a link: seals what goes, or opens what comes, the nth message with nonce n.
    public struct Sealer: Sendable {
        let key: SymmetricKey
        public private(set) var count: UInt64 = 0
        public init(key: SymmetricKey) { self.key = key }

        static func nonce(_ count: UInt64) -> AES.GCM.Nonce {
            var bytes = Data(repeating: 0, count: 4)
            withUnsafeBytes(of: count.bigEndian) { bytes.append(contentsOf: $0) }
            return try! AES.GCM.Nonce(data: bytes)
        }

        /// The message sealed: what was sent, then its 16-byte tag.
        public mutating func seal(_ plain: Data) -> Data {
            defer { count += 1 }
            let box = try! AES.GCM.seal(plain, using: key, nonce: Self.nonce(count))
            return box.ciphertext + box.tag
        }

        /// What a sealed message said, when it's the next one this way and nothing in it was changed; nil otherwise.
        public mutating func open(_ sealed: Data) -> Data? {
            guard sealed.count >= 16, sealed.count <= sealedLimit + 16,
                  let box = try? AES.GCM.SealedBox(nonce: Self.nonce(count), ciphertext: sealed.dropLast(16), tag: sealed.suffix(16)),
                  let plain = try? AES.GCM.open(box, using: key) else { return nil }
            count += 1
            return plain
        }
    }
}
