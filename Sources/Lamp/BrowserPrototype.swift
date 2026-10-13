import Foundation
import CryptoKit

/// Throwaway, opt-in development experiment. No browser routes exist in a release build.
/// Like existing app tokens, this is not isolation from hostile processes under the same macOS user.
@MainActor
final class BrowserPrototype {
    static var enabled: Bool { Edition.isDev && ProcessInfo.processInfo.environment["LAMP_BROWSER_PROTOTYPE"] == "1" }
    static let shared = BrowserPrototype()
    static let folder = Edition.supportFolder.appendingPathComponent("BrowserPrototype")
    private var secret = ""
    private struct Pending {
        let id: String
        let app: String
        let name: String
        let origin: String
        let expires: Date
        var claim: [String: String]?
        var result: [String: Any]?
    }
    private var pending: [String: Pending] = [:]
    private var nonces: [String: Date] = [:]

    func prepareFixtures(root: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: Self.folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let secretURL = Self.folder.appendingPathComponent("secret")
        if let saved = try? String(contentsOf: secretURL) { secret = saved }
        else {
            secret = UUID().uuidString + UUID().uuidString
            try Data(secret.utf8).write(to: secretURL, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secretURL.path)
        }
        guard let source = ProcessInfo.processInfo.environment["LAMP_BROWSER_FIXTURES"] else { return }
        let fixture = URL(fileURLWithPath: source)
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/BrowserNativeHost")
        let helper = Self.folder.appendingPathComponent("BrowserNativeHost")
        if fm.fileExists(atPath: helper.path) { try fm.removeItem(at: helper) }
        try fm.copyItem(at: bundled, to: helper)
        let config: [String: Any] = ["port": Edition.gatewayPort, "secretPath": secretURL.path]
        try JSONSerialization.data(withJSONObject: config).write(to: helper.deletingLastPathComponent().appendingPathComponent("config.json"))
        let manifest: [String: Any] = ["name": "dev.lamp.prototype", "description": "Lamp browser prototype", "path": helper.path,
                                       "type": "stdio", "allowed_origins": ["chrome-extension://" + (try String(contentsOf: fixture.appendingPathComponent("extension-id.txt"))).trimmed + "/"]]
        let hosts = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts")
        try fm.createDirectory(at: hosts, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: manifest).write(to: hosts.appendingPathComponent("dev.lamp.prototype.json"))
        for name in ["Page Shelf", "Other Shelf"] {
            let slug = Template.identifier(from: name).lowercased()
            if fm.fileExists(atPath: root.appendingPathComponent(slug).path) { continue }
            let project = try Template.scaffold(name: name, in: root)
            var content = try String(contentsOf: fixture.appendingPathComponent("ContentView.swift"))
            content = content.replacingOccurrences(of: "@@TOKEN@@", with: Template.token(for: project))
                .replacingOccurrences(of: "@@PORT@@", with: String(Edition.gatewayPort))
                .replacingOccurrences(of: "@@NAME@@", with: name)
            try content.write(to: project.dir.appendingPathComponent("Sources/ContentView.swift"), atomically: true, encoding: .utf8)
        }
    }

    private func mac(_ text: String) -> String {
        Data(HMAC<SHA256>.authenticationCode(for: Data(text.utf8), using: SymmetricKey(data: Data(secret.utf8)))).base64EncodedString()
    }
    private func signed(_ response: [String: Any], nonce: String) -> (Int, [String: Any]) {
        let payload = (try! JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])).base64EncodedString()
        return (200, ["payload": payload, "signature": mac(nonce + "." + payload)])
    }
    private func origin(_ url: String) -> String? {
        guard let u = URLComponents(string: url), let scheme = u.scheme, let host = u.host,
              u.user == nil, u.password == nil, scheme == "https" || (scheme == "http" && ["127.0.0.1", "localhost"].contains(host)) else { return nil }
        return scheme + "://" + host + (u.port.map { ":\($0)" } ?? "")
    }

    func handle(_ request: Gateway.Request, projects: [LampProject]) -> (Int, [String: Any]) {
        guard request.method == "POST", !request.fromNetwork, Store.isLocalHost(request.headers["host"]),
              request.headers["origin"] == nil,
              request.body.count < 300_000,
              let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] else { return (403, ["error": "Not available here."]) }
        let now = Date()
        pending = pending.filter { $0.value.expires > now }
        nonces = nonces.filter { $0.value > now }
        if request.path == "/prototype/browser/native" {
            guard !secret.isEmpty, let nonce = body["nonce"] as? String, nonce.count < 100, nonces[nonce] == nil,
                  let signature = request.headers["x-lamp-signature"], let data = Data(base64Encoded: signature),
                  HMAC<SHA256>.isValidAuthenticationCode(data, authenticating: request.body, using: SymmetricKey(data: Data(secret.utf8))) else {
                return (401, ["error": "Unrecognized bridge."])
            }
            nonces[nonce] = now.addingTimeInterval(180)
            return signed(native(body), nonce: nonce)
        }
        let token = request.headers["authorization"]?.replacingOccurrences(of: "Bearer ", with: "") ?? ""
        guard let app = projects.first(where: { Template.token(for: $0) == token }) else { return (401, ["error": "Unknown app."]) }
        switch request.path {
        case "/prototype/browser/request":
            guard let site = body["origin"] as? String, origin(site) == site else { return (400, ["error": "Choose an exact website origin."]) }
            let item = Pending(id: UUID().uuidString, app: app.id, name: app.name, origin: site, expires: now.addingTimeInterval(120))
            pending[app.id] = item
            return (200, ["id": item.id])
        case "/prototype/browser/result":
            guard let item = pending[app.id], item.id == body["id"] as? String else { return (410, ["error": "The request ended. Try again."]) }
            if let result = item.result { pending[app.id] = nil; return (200, ["result": result]) }
            return (200, ["waiting": true])
        default: return (404, ["error": "Not found."])
        }
    }

    private func native(_ body: [String: Any]) -> [String: Any] {
        let fail: (String) -> [String: Any] = { ["error": $0] }
        guard let session = body["session"] as? String else { return fail("Missing browser session.") }
        if body["op"] as? String == "list" {
            return ["requests": pending.values.filter { $0.result == nil }.sorted { $0.name < $1.name }.map {
                ["id": $0.id, "name": $0.name, "origin": $0.origin]
            }]
        }
        guard let id = body["id"] as? String, let key = pending.first(where: { $0.value.id == id })?.key,
              var item = pending[key], item.result == nil else { return fail("The request ended. Ask from the app again.") }
        if body["op"] as? String == "prepare" {
            guard let url = body["url"] as? String, origin(url) == item.origin,
                  let document = body["document"] as? String, let tab = body["tab"] as? String else { return fail("This app asked for another website.") }
            let challenge = UUID().uuidString
            item.claim = ["session": session, "document": document, "tab": tab, "challenge": challenge, "url": url]
            pending[key] = item
            return ["challenge": challenge, "name": item.name, "origin": item.origin]
        }
        guard let claim = item.claim, claim["session"] == session, claim["challenge"] == body["challenge"] as? String else { return fail("Open the extension again to approve this page.") }
        if body["op"] as? String == "cancel" {
            item.result = ["error": "Sharing canceled."]
            item.claim = nil
            pending[key] = item
            return ["canceled": true]
        }
        guard body["op"] as? String == "deliver", claim["document"] == body["document"] as? String,
              claim["tab"] == body["tab"] as? String, let page = body["page"] as? [String: Any],
              let url = page["url"] as? String, url == claim["url"], origin(url) == item.origin,
              let title = page["title"] as? String, title.count <= 1000,
              let text = page["text"] as? String, text.utf8.count <= 100_000 else { return fail("The page changed or was too large. Start again.") }
        item.result = ["url": url, "title": title, "text": text, "capturedAt": ISO8601DateFormatter().string(from: Date()), "app": item.name]
        item.claim = nil
        pending[key] = item
        return ["delivered": true, "name": item.name]
    }
}
