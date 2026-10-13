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
    private struct Grant: Codable {
        let id: String
        let app: String
        let instance: String
        let name: String
        let origin: String
        let profile: String
        let openClosed: Bool
    }
    private struct Pending {
        let id: String
        let app: String
        let instance: String
        let name: String
        let origin: String
        let url: String
        let expires: Date
        let mode: String
        let grantID: String?
        var claim: [String: String]?
        var result: [String: Any]?
    }
    private var pending: [String: Pending] = [:]
    private var grants: [Grant] = []
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
        if let bytes = try? Data(contentsOf: Self.folder.appendingPathComponent("grants.json")) {
            grants = try JSONDecoder().decode([Grant].self, from: bytes)
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

    private func saveGrants() throws {
        try JSONEncoder().encode(grants).write(to: Self.folder.appendingPathComponent("grants.json"), options: .atomic)
    }
    private func summary(_ g: Grant) -> [String: Any] {
        ["id": g.id, "app": g.app, "name": g.name, "origin": g.origin, "openClosed": g.openClosed]
    }
    private func revoke(_ ids: Set<String>) throws {
        // Denial is effective even when its disk write fails. Never release a captured result after revocation.
        grants.removeAll { ids.contains($0.id) }
        for key in Array(pending.keys) where pending[key]?.grantID.map({ ids.contains($0) }) == true {
            pending[key]?.result = ["error": "Access was revoked. Approve this app again before reading."]
            pending[key]?.claim = nil
        }
        try saveGrants()
    }
    func handle(_ request: Gateway.Request, projects: [LampProject]) -> (Int, [String: Any]) {
        guard request.method == "POST", !request.fromNetwork, Store.isLocalHost(request.headers["host"]),
              request.headers["origin"] == nil, request.body.count < 300_000,
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
        case "/prototype/browser/status":
            return (200, ["grants": grants.filter { $0.app == app.id && $0.instance == app.instance }.map(summary)])
        case "/prototype/browser/revoke":
            guard let id = body["id"] as? String, grants.contains(where: { $0.id == id && $0.app == app.id && $0.instance == app.instance }) else { return (403, ["error": "Not this app's grant."]) }
            do { try revoke([id]); return (200, ["revoked": true]) } catch { return (500, ["error": "Access ended for this session, but the change could not be saved. Remove site access in Chrome too."]) }
        case "/prototype/browser/request":
            guard let url = body["url"] as? String, let site = origin(url), url.count < 4000,
                  let mode = body["mode"] as? String, ["approve", "read"].contains(mode) else { return (400, ["error": "Choose a website and an action."]) }
            let candidates = grants.filter { $0.app == app.id && $0.instance == app.instance && $0.origin == site }
            if mode == "read", candidates.count != 1 { return (403, ["error": "No standing access for this app and site. Ask for access first."]) }
            let item = Pending(id: UUID().uuidString, app: app.id, instance: app.instance, name: app.name, origin: site,
                               url: url, expires: now.addingTimeInterval(mode == "approve" ? 120 : 25), mode: mode,
                               grantID: mode == "read" ? candidates.first?.id : nil)
            pending[app.id] = item
            return (200, ["id": item.id])
        case "/prototype/browser/result":
            guard let item = pending[app.id], item.instance == app.instance, item.id == body["id"] as? String else { return (410, ["error": "The request ended. Check Chrome and try again."]) }
            if let result = item.result { pending[app.id] = nil; return (200, ["result": result]) }
            return (200, ["waiting": true])
        default: return (404, ["error": "Not found."])
        }
    }

    private func native(_ body: [String: Any]) -> [String: Any] {
        let fail: (String) -> [String: Any] = { ["error": $0] }
        guard let session = body["session"] as? String, let profile = body["profile"] as? String,
              UUID(uuidString: profile) != nil else { return fail("Missing browser identity.") }
        let op = body["op"] as? String ?? ""
        if op == "list" || op == "poll" {
            var jobs: [[String: Any]] = []
            if op == "poll" {
                for key in Array(pending.keys) {
                    guard var item = pending[key], item.mode == "read", item.result == nil,
                          let grant = grants.first(where: { $0.id == item.grantID && $0.profile == profile && $0.app == item.app && $0.instance == item.instance && $0.origin == item.origin }) else { continue }
                    if item.claim != nil { continue }
                    let challenge = UUID().uuidString
                    item.claim = ["session": session, "profile": profile, "challenge": challenge]
                    pending[key] = item
                    jobs.append(["id": item.id, "app": item.app, "url": item.url, "origin": item.origin, "grant": grant.id,
                                 "openClosed": grant.openClosed, "challenge": challenge])
                }
            }
            return ["requests": pending.values.filter { $0.mode == "approve" && $0.result == nil }.sorted { $0.name < $1.name }.map {
                ["id": $0.id, "name": $0.name, "origin": $0.origin, "url": $0.url]
            }, "grants": grants.filter { $0.profile == profile }.map(summary), "jobs": jobs]
        }
        if op == "revoke" {
            guard let id = body["grant"] as? String, grants.contains(where: { $0.id == id && $0.profile == profile }) else { return fail("Unknown grant.") }
            do { try revoke([id]); return ["revoked": true] } catch { return fail("Access ended for this session, but the change could not be saved. Remove site access in Chrome too.") }
        }
        if op == "permissionRemoved" {
            guard let ids = body["grants"] as? [String] else { return fail("Missing grants.") }
            do {
                let scoped = Set(grants.filter { ids.contains($0.id) && $0.profile == profile }.map(\.id))
                try revoke(scoped)
                return ["revoked": true]
            } catch { return fail("Access ended for this session, but the change could not be saved. Remove site access in Chrome too.") }
        }
        guard let id = body["id"] as? String, let key = pending.first(where: { $0.value.id == id })?.key,
              var item = pending[key], item.result == nil else { return fail("The request ended. Ask from the app again.") }
        if op == "grant" {
            guard item.mode == "approve", let url = body["url"] as? String, origin(url) == item.origin,
                  body["origin"] as? String == item.origin else { return fail("This app asked for another website.") }
            let grant = Grant(id: UUID().uuidString, app: item.app, instance: item.instance, name: item.name,
                              origin: item.origin, profile: profile, openClosed: body["openClosed"] as? Bool ?? false)
            let old = grants
            grants.removeAll { $0.app == item.app && $0.instance == item.instance && $0.origin == item.origin }
            grants.append(grant)
            do { try saveGrants() } catch { grants = old; return fail("Couldn't save approval.") }
            item.result = ["approved": true]
            pending[key] = item
            return ["approved": true]
        }
        guard item.mode == "read", let grant = grants.first(where: { $0.id == item.grantID && $0.app == item.app && $0.instance == item.instance && $0.origin == item.origin && $0.profile == profile }),
              let claim = item.claim, claim["session"] == session, claim["profile"] == profile,
              claim["challenge"] == body["challenge"] as? String, body["grant"] as? String == grant.id else { return fail("Access ended or this belongs to another app or browser.") }
        if op == "failure" {
            item.result = ["error": String((body["error"] as? String ?? "The page couldn't be read.").prefix(500))]
        } else if op == "deliver" {
            guard let page = body["page"] as? [String: Any], let url = page["url"] as? String,
                  url == item.url, origin(url) == item.origin,
                  let title = page["title"] as? String, title.count <= 1000,
                  let text = page["text"] as? String, text.utf8.count <= 100_000 else { return fail("The page changed or was too large. Start again.") }
            item.result = ["url": url, "title": title, "text": text, "capturedAt": ISO8601DateFormatter().string(from: Date()), "app": item.name]
        } else { return fail("Unknown action.") }
        pending[key] = item
        return ["delivered": true]
    }
}
