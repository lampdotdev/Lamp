import CryptoKit
import Foundation

/// Phones as controllers for a game on this Mac with Lamp closed: a small service of its own (`LampControllerService`,
/// in Lamp's Helpers), which macOS starts and keeps running while the person is logged in, once they've turned it on in
/// Lamp (`SMAppService.agent`). It serves each game's phone page, runs the relay its phones and the game meet at, and
/// signs who may join; Lamp only gives it each game's page and who the game is, and the game asks it for its session
/// itself, over XPC. Shared here by the service, by Lamp, and by the tests; the game's side is in LampPage.swift, which
/// can't import this, and speaks the same JSON.
///
/// One method carries every call, a JSON object with an `op`, answered with a JSON object, so a newer Lamp, service or
/// game can add calls and fields without the other side's interface changing.
@objc(LampControllerServiceProtocol)
public protocol ControllerServiceCalls {
    func call(_ request: Data, withReply reply: @escaping (Data) -> Void)
}

public enum ControllerService {
    /// What this service speaks. A game or Lamp that speaks less is answered as far as it understands.
    public static let protocolVersion = 1
    /// How often a game asks again for its session, and how long a session lasts once it stops asking.
    public static let renew = 10
    public static let lease: TimeInterval = 30

    /// Which Lamp a service belongs to, by its bundle id, with everything named after it: each Lamp (the release, the
    /// nightly, Lamp Dev and each of its instances) has a service of its own, with its own label, XPC names, folder and
    /// ports, so one never answers another's games. Kept in step with `Edition`, which reads the same bundle id.
    public struct Names: Equatable, Sendable {
        public let bundleID: String
        public init(bundleID: String) { self.bundleID = bundleID }

        public var isDev: Bool { bundleID == "dev.lamp.host.dev" || bundleID.hasPrefix("dev.lamp.host.dev.") }
        public var isNightly: Bool { bundleID == "dev.lamp.host.nightly" }
        public var instance: String { isDev && bundleID.hasPrefix("dev.lamp.host.dev.") ? String(bundleID.dropFirst("dev.lamp.host.dev.".count)) : "" }
        /// The Lamp's name, as its folder under Application Support is named.
        public var lampName: String { isDev ? "Lamp Dev" + (instance.isEmpty ? "" : " " + instance) : isNightly ? "Lamp Nightly" : "Lamp" }

        /// launchd's label for the service, and the name of its plist in Lamp's Contents/Library/LaunchAgents.
        public var label: String { bundleID + ".controllers" }
        public var plistName: String { label + ".plist" }
        /// Where Lamp asks it to take a game's page or let one go: only Lamp itself is let in.
        public var manageService: String { label + ".manage" }
        /// Where a game asks for its session.
        public var gameService: String { label + ".games" }

        /// The service's own folder, beside the Lamp's: the games' pages it serves and what it knows of each.
        public func folder(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
            home.appendingPathComponent("Library/Application Support/\(lampName)/Controllers")
        }

        /// Its ports: the relay at the first, each game's page at one of the rest. A range of each Lamp's own, clear of
        /// Lamp's own phone pages (`Edition.phonePagePorts`) and every other port Lamp uses, so the service and an open
        /// Lamp never take each other's.
        public var ports: ClosedRange<UInt16> {
            if isNightly { return 47960...47975 }
            guard isDev else { return 47940...47955 }
            guard !instance.isEmpty else { return 47980...47995 }
            var hash: UInt32 = 2166136261
            for byte in instance.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
            let start = 55000 + UInt16(hash % 240) * 16
            return start...(start + 15)
        }
        public var relayPort: UInt16 { ports.lowerBound }
        public var pagePorts: ClosedRange<UInt16> { (ports.lowerBound + 1)...ports.upperBound }
    }

    // MARK: Messages

    public static func encode(_ value: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    public static func decode(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    /// What a game's key is kept as: never the key itself, so the service's folder holds nothing a game could show it.
    public static func verifier(of key: String) -> String {
        Data(SHA256.hash(data: Data(key.utf8))).base64EncodedString()
    }

    /// Whether `key` is the one `verifier` was made from, compared in time that doesn't depend on where they differ.
    public static func matches(_ key: String, verifier: String) -> Bool {
        let given = Data(SHA256.hash(data: Data(key.utf8)))
        guard let kept = Data(base64Encoded: verifier), kept.count == given.count else { return false }
        return zip(given, kept).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    /// A new key for a game: what it shows the service to open its own session, and nothing else.
    public static func newKey() -> String {
        Data((0..<32).map { _ in UInt8.random(in: 0...255) }).urlSafeBase64
    }

    /// An installation's id or a version as the service takes it: a name it can make a folder of.
    public static func isName(_ text: String?) -> Bool {
        guard let text, !text.isEmpty, text.utf8.count <= 128, !text.hasPrefix(".") else { return false }
        return text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
    }
}
