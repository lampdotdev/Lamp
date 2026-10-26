import Foundation

/// A free Apple account's team puts at most three apps on a phone. Lamp's apps carry the team at the end of their
/// bundle id (`deviceBundleID(team:)`), and `devicectl` marks what a developer built, so Lamp can count its own there
/// before it builds a fourth, and offer to take one off rather than let Apple refuse the install (`Store.installOnDevice`,
/// `PhoneSlotLine`). Lamp only ever takes off its own apps, and only when the person says so: what an app saved on the
/// phone goes with it. An app of the same team that isn't Lamp's can't be told apart, so Apple's refusal
/// (`PhoneFailure.appLimit`) stays for that.
enum PhoneSlots {
    static let limit = 3

    /// The bundle ids of the apps a developer built on the phone, from `devicectl device info apps --json-output`.
    static func developerApps(in json: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let apps = (root["result"] as? [String: Any])?["apps"] as? [[String: Any]] else { return [] }
        return apps.filter { $0["builtByDeveloper"] as? Bool == true }.compactMap { $0["bundleIdentifier"] as? String }
    }

    /// Lamp's apps signed for `team`: in a Lamp's own namespace (`isLampApp`), ending in ".<team>", lowercased as bundle
    /// ids are. Another developer's app of the same team ends the same way, so the namespace is what makes it Lamp's.
    static func teamApps(_ bundleIDs: [String], team: String) -> [String] {
        bundleIDs.filter { isLampApp($0) && $0.hasSuffix("." + team.lowercased()) }
    }

    /// Whether the bundle id is an app any Lamp on this Mac made (`Edition.appBundlePrefix`): the release's "dev.lamp.app.",
    /// Lamp Dev's "dev.lamp.dev.app.", or an instance's "dev.lamp.dev.<instance>.app.".
    static func isLampApp(_ bundleID: String) -> Bool {
        bundleID.range(of: #"^dev\.lamp\.(dev\.([a-z0-9-]+\.)?)?app\."#, options: .regularExpression) != nil
    }

    /// One of the person's apps Lamp knows on the phone: its bundle id there, and when its copy runs out.
    struct Known: Equatable { let bundleID: String; let expires: Date? }

    /// The app to offer to take off so `mine` can go on, or nil when there's room or nothing Lamp may suggest: one that
    /// has stopped opening first, then the one renewed least lately, then one of this team's apps this Lamp doesn't
    /// know (another Lamp's, or a wish deleted since).
    static func toTakeOff(installed: [String], mine: String, known: [Known], now: Date = Date()) -> String? {
        guard !installed.contains(mine), installed.count >= limit else { return nil }
        let others = known.filter { $0.bundleID != mine && installed.contains($0.bundleID) }
        if let stopped = others.filter({ ($0.expires ?? .distantFuture) < now }).min(by: { $0.expires! < $1.expires! }) { return stopped.bundleID }
        if let oldest = others.min(by: { ($0.expires ?? .distantFuture) < ($1.expires ?? .distantFuture) }) { return oldest.bundleID }
        return installed.first { id in id != mine && !known.contains { $0.bundleID == id } }
    }
}

/// The chat's card asking to take one app off a full phone so this one can go on. Its text is the bundle id to take
/// off, and "done:" before it once it's gone.
enum PhoneSlotLine {
    static let done = "done:"
    static func text(this: String, other: String, phone: String, taken: Bool) -> String {
        taken ? "Took \(other) off \(phone)."
            : "Your free Apple account lets \(phone) hold \(PhoneSlots.limit) apps, and it has \(PhoneSlots.limit). Take \(other) off it to put \(this) there? What it saved on the phone goes with it."
    }
    static let button = "Take It Off"
    static let symbol = "iphone"
}
