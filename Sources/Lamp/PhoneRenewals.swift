import Foundation

/// Putting the person's iPhone apps back on their phones before Apple lets them stop opening. A profile made for a free
/// Apple account's team lasts seven days (a paid team's, a year); after that the app won't open until it's signed again
/// and installed over itself, which keeps its data. So Lamp keeps what it last put on each phone, signed, with when its
/// profile runs out (`Record`), and within a couple of days of that signs the same copy again with a new profile and
/// installs it, never opening it (`Store.renewPhoneApps`). The copy is what the person has, never the code as it is now:
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

    /// How long before its profile runs out an app is put back: time for a phone that's away for a day or so.
    static let window: TimeInterval = 2 * 24 * 3600

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

    // MARK: Kept on disk

    static func folder(for project: LampProject) -> URL { Devices.signingFolder(for: project).appendingPathComponent("OnPhone") }
    static func recordURL(for project: LampProject) -> URL { folder(for: project).appendingPathComponent("record.json") }
    static func keptApp(for project: LampProject) -> URL { folder(for: project).appendingPathComponent("App.app") }

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
        guard (try? fm.moveItem(at: app, to: keptApp(for: project))) != nil else { return }
        save(Record(udid: udid, bundleID: project.deviceBundleID(team: team), team: team, expires: expires), for: project)
    }

    /// Forgets what's on the phone, when the app is deleted or put somewhere else.
    static func forget(_ project: LampProject) {
        try? FileManager.default.removeItem(at: folder(for: project))
    }
}
