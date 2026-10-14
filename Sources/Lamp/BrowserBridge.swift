import Foundation
import CryptoKit

/// Where Chrome and the apps meet Lamp for the sidebar: Lamp Dev only, behind Settings → Experimental.
/// The extension reaches Lamp through Chrome's native messaging: Chrome starts the small helper Lamp installs
/// (`BrowserNativeHost`), which signs each message with a secret only it and Lamp can read and passes it to the
/// gateway; Lamp signs its answer back. Apps reach Lamp with their own token. Like the apps' tokens, this keeps
/// websites and other users out, not a hostile program running as the same person.
@MainActor
final class BrowserBridge {
    nonisolated static let switchKey = "experimentBrowserCompanion"
    nonisolated static var enabled: Bool {
        Edition.isDev && (UserDefaults.standard.object(forKey: switchKey) != nil
            ? UserDefaults.standard.bool(forKey: switchKey)
            : ProcessInfo.processInfo.environment["LAMP_BROWSER_PROTOTYPE"] == "1")
    }
    static let shared = BrowserBridge()
    static let folder = Edition.supportFolder.appendingPathComponent("BrowserPrototype")
    static var secretURL: URL { folder.appendingPathComponent("secret") }
    private var secret = ""
    private var nonces: [String: Date] = [:]

    func prepare() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: Self.folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if secret.isEmpty, let saved = try? String(contentsOf: Self.secretURL), !saved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            secret = saved
        }
        if secret.isEmpty { secret = UUID().uuidString + UUID().uuidString }
        // Written back whenever it's missing or differs, so Repair restores it for the helper.
        if (try? String(contentsOf: Self.secretURL)) != secret {
            try Data(secret.utf8).write(to: Self.secretURL, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.secretURL.path)
        }
    }

    private func mac(_ text: String) -> String {
        Data(HMAC<SHA256>.authenticationCode(for: Data(text.utf8), using: SymmetricKey(data: Data(secret.utf8)))).base64EncodedString()
    }
    private func signed(_ response: [String: Any], nonce: String) -> (Int, [String: Any]) {
        let payload = (try! JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])).base64EncodedString()
        return (200, ["payload": payload, "signature": mac(nonce + "." + payload)])
    }

    func handle(_ request: Gateway.Request, projects: [LampProject]) -> (Int, [String: Any]) {
        guard request.method == "POST", !request.fromNetwork, Store.isLocalHost(request.headers["host"]),
              request.headers["origin"] == nil, request.body.count < 300_000,
              let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] else { return (403, ["error": "Not available here."]) }
        let now = Date()
        nonces = nonces.filter { $0.value > now }
        if request.path == "/browser/native" {
            if secret.isEmpty { try? prepare() }
            guard !secret.isEmpty, let nonce = body["nonce"] as? String, nonce.count < 100, nonces[nonce] == nil,
                  let signature = request.headers["x-lamp-signature"], let data = Data(base64Encoded: signature),
                  HMAC<SHA256>.isValidAuthenticationCode(data, authenticating: request.body, using: SymmetricKey(data: Data(secret.utf8))) else {
                return (401, ["error": "Unrecognized bridge."])
            }
            nonces[nonce] = now.addingTimeInterval(180)
            return signed(native(body, projects: projects), nonce: nonce)
        }
        let token = request.headers["authorization"]?.replacingOccurrences(of: "Bearer ", with: "") ?? ""
        guard let app = projects.first(where: { Template.token(for: $0) == token }) else { return (401, ["error": "Unknown app."]) }
        switch request.path {
        case "/browser/surface":
            let result = BrowserCompanions.shared.exchange(body, app: app)
            if result.0 == 200 && AppAI.resolve(.browser, for: app).tier == .none {
                Store.shared.offerSetup(app, SetupOffer(capability: .browser), because: "\(app.name) also works in Chrome. Connect Lamp to Chrome to use it beside a page.")
            }
            return result
        case "/browser/setup":
            Store.shared.offerSetup(app, SetupOffer(capability: .browser), because: "\(app.name) also works in Chrome. Connect Lamp to Chrome to use it beside a page.", fromAgent: true)
            Store.shared.showChat(app.id)
            return (200, ["opened": true])
        default:
            return (404, ["error": "Not found."])
        }
    }

    private func native(_ body: [String: Any], projects: [LampProject]) -> [String: Any] {
        guard body["session"] is String, let profile = body["profile"] as? String,
              UUID(uuidString: profile) != nil else { return ["error": "Missing browser identity."] }
        let op = body["op"] as? String ?? ""
        if op == "companion-hello" {
            BrowserSetup.shared.receiveHello(version: body["version"] as? Int ?? 0)
            return ["connected": BrowserSetup.shared.connected, "fits": BrowserCompanions.shared.fitsKey(projects)]
        }
        guard op.hasPrefix("surface-") else { return ["error": "Unknown action."] }
        return BrowserCompanions.shared.native(body, tab: BrowserCompanions.tabKey(profile: profile, tab: body["tab"]), projects: projects)
    }
}
