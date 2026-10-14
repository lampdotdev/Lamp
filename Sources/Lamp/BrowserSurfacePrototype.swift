import Foundation
import CryptoKit

/// The extension renders data, never app-supplied HTML or code. The app owns its state and actions.
@MainActor
final class BrowserSurfacePrototype {
    static let shared = BrowserSurfacePrototype()
    struct Surface: Codable {
        struct Section: Codable { var title: String; var text: String }
        struct Field: Codable { var id: String; var label: String; var value: String }
        struct Action: Codable { var id: String; var label: String; var readsPage: Bool; var readsSelection: Bool? }
        var title: String
        var detail: String
        var sections: [Section]
        var fields: [Field]
        var actions: [Action]
        var busy: Bool
        var valid: Bool {
            title.count <= 120 && detail.count <= 1000 && sections.count <= 20 && fields.count <= 12 && actions.count <= 8
            && sections.allSatisfy { $0.title.count <= 120 && $0.text.count <= 16000 }
            && fields.allSatisfy { !$0.id.isEmpty && $0.id.count <= 60 && $0.label.count <= 120 && $0.value.count <= 4000 }
            && actions.allSatisfy { !$0.id.isEmpty && $0.id.count <= 60 && $0.label.count <= 120 && !($0.readsPage && $0.readsSelection == true) }
            && Set(actions.map(\.id)).count == actions.count && Set(fields.map(\.id)).count == fields.count
        }
    }
    private struct Registration {
        var instance: String
        var boot: String
        var name: String
        var surface: Surface
        var revision: String
        var fingerprint: String
        var seen: Date
        var event: [String: Any]?
        var eventDate: Date?
        var accepted: [String] = []
    }
    private var apps: [String: Registration] = [:]

    func exchange(_ body: [String: Any], app: LampProject) -> (Int, [String: Any]) {
        guard app.platform.hasMac, let boot = body["boot"] as? String, UUID(uuidString: boot) != nil,
              let raw = body["surface"], let data = try? JSONSerialization.data(withJSONObject: raw), data.count <= 100_000,
              let surface = try? JSONDecoder().decode(Surface.self, from: data), surface.valid else {
            return (400, ["error": "This companion couldn't be displayed."])
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let canonical = try! encoder.encode(surface)
        let fingerprint = SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
        var entry = apps[app.id]
        if entry?.instance != app.instance || entry?.boot != boot {
            entry = Registration(instance: app.instance, boot: boot, name: app.name, surface: surface, revision: UUID().uuidString, fingerprint: fingerprint, seen: Date())
        }
        if entry!.fingerprint != fingerprint {
            entry!.revision = UUID().uuidString
            entry!.fingerprint = fingerprint
        }
        entry!.surface = surface; entry!.seen = Date(); entry!.name = app.name
        if let ack = body["ack"] as? String, ack == entry!.event?["id"] as? String { entry!.event = nil; entry!.eventDate = nil; entry!.revision = UUID().uuidString }
        if let date = entry!.eventDate, Date().timeIntervalSince(date) > 240 { entry!.event = nil; entry!.eventDate = nil; entry!.revision = UUID().uuidString }
        apps[app.id] = entry
        return (200, entry!.event.map { ["event": $0] } ?? [:])
    }

    func native(_ body: [String: Any], projects: [LampProject]) -> [String: Any] {
        let live = apps.filter { key, entry in
            Date().timeIntervalSince(entry.seen) < 6 && projects.contains { $0.id == key && $0.instance == entry.instance }
        }
        if body["op"] as? String == "surface-list" {
            return ["apps": live.sorted { $0.value.name < $1.value.name }.map { ["id": $0.key, "name": $0.value.name] }]
        }
        guard let id = body["app"] as? String, var entry = live[id] else { return ["error": "Open this app on your Mac to use its companion."] }
        if body["op"] as? String == "surface-view" {
            return ["surface": try! JSONSerialization.jsonObject(with: JSONEncoder().encode(entry.surface)),
                    "revision": entry.revision, "busy": entry.event != nil]
        }
        guard body["op"] as? String == "surface-action", let eventID = body["id"] as? String, UUID(uuidString: eventID) != nil else {
            return ["error": "Unknown companion action."]
        }
        if entry.accepted.contains(eventID) { return ["accepted": true] }
        guard body["revision"] as? String == entry.revision, !entry.surface.busy, entry.event == nil,
              let action = entry.surface.actions.first(where: { $0.id == body["action"] as? String }),
              let fields = body["fields"] as? [String: String], fields.count <= 12,
              fields.allSatisfy({ key, value in entry.surface.fields.contains { $0.id == key } && value.count <= 4000 }) else {
            return ["error": "The app changed. Wait for its companion to update, then try again."]
        }
        var event: [String: Any] = ["id": eventID, "action": action.id, "fields": fields]
        if action.readsPage || action.readsSelection == true {
            guard let page = body["page"] as? [String: String], let url = page["url"],
                  let u = URLComponents(string: url), u.user == nil, u.password == nil,
                  u.scheme == "https" || (u.scheme == "http" && ["localhost", "127.0.0.1"].contains(u.host ?? "")),
                  url.count <= 4000, let text = page["text"], text.utf8.count <= 100_000,
                  let title = page["title"], title.count <= 1000,
                  action.readsSelection != true || (page["scope"] == "selection" && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) else { return ["error": "That page couldn't be read. Try again on a website."] }
            event["page"] = ["url": url, "text": text, "title": title, "scope": action.readsSelection == true ? "selection" : "page"]
        } else if body["page"] != nil { return ["error": "This action doesn't read a page."] }
        entry.event = event; entry.eventDate = Date(); entry.accepted.append(eventID)
        entry.accepted = Array(entry.accepted.suffix(64)); apps[id] = entry
        return ["accepted": true]
    }
}
