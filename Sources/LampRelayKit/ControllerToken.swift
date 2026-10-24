import CryptoKit
import Foundation

/// A controller's credential as it's written and checked: a short signed token for one kind of holder in one app's
/// session, signed with a key that lives only in memory. Lamp signs them (`ControllerCredential`), and so does the relay
/// (`Relay`), which Lamp gives the same key when it starts it; a wish's iPhone app checks the ones made with the key Lamp
/// gave it for its own listener (`LampController` in LampSupport writes the same form).
///
///   host        the TV app's page, for its socket, for as long as a session may last.
///   join        what a phone's link carries, after the #, which a browser never sends: for fifteen minutes.
///   controller  given to a phone once it has joined: its place, for two minutes, renewed while it stays, so a phone that
///               drops off comes back as the same player.
///   peer        one of a wish's own apps, for its wish's room (`Relay` rooms): named by its part ("tv", "iphone", "mac",
///               "android"), for an hour; the app asks Lamp for a fresh one with its own token when it runs out.
public enum ControllerToken {
    public enum Kind: String, CaseIterable, Sendable {
        case host, join, controller, peer
        public var lifetime: TimeInterval {
            switch self {
            case .host: 12 * 3600
            case .join: 15 * 60
            case .controller: 2 * 60
            case .peer: 3600
            }
        }
    }

    public struct Claim: Equatable, Sendable {
        public let kind: Kind
        public let app: String
        public let player: Int?
        /// A host's: the TV preview on the Mac, which keeps its game from a TV that runs the same app meanwhile.
        public let preview: Bool
        /// A peer's: which of the wish's apps it is, by its part's word.
        public let peer: String?
        public init(kind: Kind, app: String, player: Int?, preview: Bool, peer: String? = nil) {
            self.kind = kind
            self.app = app
            self.player = player
            self.preview = preview
            self.peer = peer
        }
    }

    public static func issue(kind: Kind, app: String, generation: Int, player: Int? = nil, preview: Bool = false, peer: String? = nil,
                             lifetime: TimeInterval? = nil, now: Date = Date(), key: SymmetricKey) -> String {
        var payload: [String: Any] = ["k": kind.rawValue, "a": app, "g": generation,
                                      "e": Int(now.addingTimeInterval(lifetime ?? kind.lifetime).timeIntervalSince1970),
                                      "n": Data((0..<9).map { _ in UInt8.random(in: 0...255) }).urlSafeBase64]
        if let player { payload["p"] = player }
        if preview { payload["v"] = 1 }
        if let peer { payload["r"] = peer }
        let body = ((try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()).urlSafeBase64
        return body + "." + Data(HMAC<SHA256>.authenticationCode(for: Data(body.utf8), using: key)).urlSafeBase64
    }

    /// What a credential says when it was made with this key, for this app in this generation of its session, of one of
    /// these kinds, and it hasn't run out; nil otherwise, whatever is wrong with it.
    public static func check(_ token: String?, kinds: Set<Kind>, app: String, generation: Int, now: Date = Date(),
                             key: SymmetricKey) -> Claim? {
        guard let token, token.utf8.count <= 1024 else { return nil }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, let signature = Data(urlSafeBase64: String(parts[1])),
              HMAC<SHA256>.isValidAuthenticationCode(signature, authenticating: Data(parts[0].utf8), using: key),
              let body = Data(urlSafeBase64: String(parts[0])),
              let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let kind = (payload["k"] as? String).flatMap(Kind.init(rawValue:)), kinds.contains(kind),
              payload["a"] as? String == app, payload["g"] as? Int == generation,
              let expires = payload["e"] as? Int, Double(expires) > now.timeIntervalSince1970 else { return nil }
        return Claim(kind: kind, app: app, player: payload["p"] as? Int, preview: payload["v"] as? Int == 1, peer: payload["r"] as? String)
    }
}

extension Data {
    public var urlSafeBase64: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    public init?(urlSafeBase64 text: String) {
        guard text.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        var plain = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        plain += String(repeating: "=", count: (4 - plain.count % 4) % 4)
        self.init(base64Encoded: plain)
    }
}
