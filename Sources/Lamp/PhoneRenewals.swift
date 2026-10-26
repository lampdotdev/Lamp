import Foundation
import ServiceManagement

/// Putting the person's iPhone apps back on their phones before Apple lets them stop opening. A profile made for a free
/// Apple account's team lasts seven days (a paid team's, a year); after that the app won't open until it's signed again
/// and installed over itself, which keeps its data. So Lamp keeps what it last put on each phone, signed, with when its
/// profile runs out (`Record`), and once a day signs the same copy again with a new profile and installs it, never
/// opening it (`Store.renewPhoneApps`), so a phone away for a weekend still comes back to an app that opens. The copy is what the person has, never the code as it is now:
/// a turn halfway through must not reach the phone. Kept in the app's signing folder, which the agent can't write.
enum PhoneRenewals {
    /// What's on one phone for one app, and how its last renewal went.
    struct Record: Codable, Equatable {
        var udid: String
        var bundleID: String
        var team: String
        var expires: Date
        /// The last renewal that didn't work: when, and Apple's or the phone's reason, for the next try's timing.
        var failedAt: Date?
        var failure: String?
        /// The expiry the person was told the app had passed, so they're told once.
        var told: Date?
    }

    /// How long before its profile runs out an app is put back: six days, so a free account's seven-day profile is renewed
    /// every day and a phone can be away for most of a week; a paid team's, which lasts a year, near its end. A renewal
    /// keeps the app's id, so it spends none of a free account's ten new ids a week.
    static let window: TimeInterval = 6 * 24 * 3600

    /// When to try again after a renewal that didn't work: soon for a phone that's away or locked, which comes back by
    /// itself; a day for a problem with the account or Apple, which the person fixes.
    static func retryAfter(_ failure: String?) -> TimeInterval {
        switch failure.flatMap(PhoneFailure.Cause.init(rawValue:)) {
        case .locked, .unreachable, .developerMode, .install, nil: return 3600
        default: return 24 * 3600
        }
    }

    /// Whether `record` is to be renewed at `now`.
    static func isDue(_ record: Record, now: Date) -> Bool {
        guard record.expires.timeIntervalSince(now) < window else { return false }
        if let failedAt = record.failedAt, now.timeIntervalSince(failedAt) < retryAfter(record.failure) { return false }
        return true
    }

    /// Whether the person is to be told the app on their phone stopped opening: it ran out and hasn't been told yet.
    static func shouldTell(_ record: Record, now: Date) -> Bool { record.expires < now && record.told != record.expires }

    // MARK: Running unattended

    /// The person chose to keep their phone apps opening: Lamp opens when they log in and keeps running with its window
    /// closed while some app of theirs is on a phone, so renewals happen without them. Off until they choose it.
    static let staysOpenKey = "keepPhoneAppsOpening"
    static var staysOpen: Bool { UserDefaults.standard.bool(forKey: staysOpenKey) }

    /// Turns it on or off: Lamp registered with macOS to open at login, or not. Returns what went wrong, in words, or nil.
    /// macOS may want the person's approval in System Settings → Login Items, which is opened for them then.
    @discardableResult static func setStaysOpen(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch where on {
            return "macOS didn't let Lamp open when you log in: \(error.localizedDescription)"
        } catch {}
        if on, SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        UserDefaults.standard.set(on, forKey: staysOpenKey)
        return nil
    }

    /// Whether any of these apps is on a phone, kept for renewal.
    static func anyOnPhones(_ projects: [LampProject]) -> Bool { projects.contains { record(for: $0) != nil } }

    /// Whether `project`'s copy on the phone `udid` has stopped opening.
    static func stoppedOpening(_ project: LampProject, on udid: String) -> Bool { record(for: project)?.udid == udid && hasExpired(project) }

    /// Whether `project`'s copy on its phone has stopped opening.
    static func hasExpired(_ project: LampProject, now: Date = Date()) -> Bool { (record(for: project)?.expires).map { $0 < now } ?? false }

    /// A free account's profile, which runs out in days, not a paid one's, which lasts a year.
    static func isShortLived(_ record: Record, now: Date = Date()) -> Bool { record.expires.timeIntervalSince(now) < 30 * 24 * 3600 }

    // MARK: Kept on disk

    static func folder(for project: LampProject) -> URL { Devices.signingFolder(for: project).appendingPathComponent("OnPhone") }
    static func recordURL(for project: LampProject) -> URL { folder(for: project).appendingPathComponent("record.json") }
    static func keptApp(for project: LampProject) -> URL { folder(for: project).appendingPathComponent("App.app") }
    /// The project Lamp signed the kept copy from (`TeamSigning.snapshot`).
    static func keptSigning(for project: LampProject) -> URL { folder(for: project).appendingPathComponent("Signing") }

    static func record(for project: LampProject) -> Record? {
        (try? Data(contentsOf: recordURL(for: project))).flatMap { try? JSONDecoder().decode(Record.self, from: $0) }
    }

    static func save(_ record: Record, for project: LampProject) {
        try? FileManager.default.createDirectory(at: folder(for: project), withIntermediateDirectories: true)
        try? JSONEncoder().encode(record).write(to: recordURL(for: project), options: .atomic)
    }

    /// Keeps `app`, just installed on `udid`, as what's on that phone: moved in place of the copy kept before.
    static func keep(_ app: URL, for project: LampProject, udid: String, team: String) async {
        let fm = FileManager.default
        guard let expires = await TeamSigning.expiry(of: app.appendingPathComponent("embedded.mobileprovision")) else { return }
        try? fm.createDirectory(at: folder(for: project), withIntermediateDirectories: true)
        try? fm.removeItem(at: keptApp(for: project))
        guard (try? TeamSigning.snapshot(for: project, place: .iphone, to: keptSigning(for: project))) != nil,
              (try? fm.moveItem(at: app, to: keptApp(for: project))) != nil else { return }
        save(Record(udid: udid, bundleID: project.deviceBundleID(team: team), team: team, expires: expires), for: project)
    }

    /// Forgets what's on the phone, when the app is deleted or put somewhere else.
    static func forget(_ project: LampProject) {
        try? FileManager.default.removeItem(at: folder(for: project))
    }
}

/// The chat's card offering to keep an app opening on the person's phone: a plain action card, its button gone once
/// the person has chosen it (here or in Settings).
enum KeepOpeningLine {
    static func text(_ name: String, on: Bool) -> String {
        on ? "Lamp opens when you log in and puts \(name) back on your phone before it stops opening."
            : "Apple lets apps signed with a free account open for seven days. Lamp can put \(name) back on your phone before then if it opens when you log in and keeps running with its window closed."
    }
    static let button = "Keep It Opening"
    /// The line's text once the person chose it from the card: the card says so even if Settings is changed later.
    static let chosen = "chosen"
    static let symbol = "clock.arrow.circlepath"
}
