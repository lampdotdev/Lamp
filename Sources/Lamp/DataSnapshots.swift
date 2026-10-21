import Foundation
import SQLite3

/// A copy of a Mac app's LampStore database taken just before a change goes into the app, by reopening it or in
/// place. The app backs itself up only at the first write of each launch, and a change that goes in live doesn't
/// relaunch it: without this, data the new code spoils has no copy from before it. Each copy is named after the
/// version the outgoing app ran, the code that wrote that data, so a version can later be matched to its data.
///
/// They sit in the app's own Backups folder beside its launch backups, under a prefix of their own that the app's
/// pruning (`data-20…`) leaves alone, and are pruned here: the newest `kept`, and the newest of each of the last
/// `days` days besides, so a busy afternoon doesn't push last week's out.
enum DataSnapshots {
    static let prefix = "change-"
    static let kept = 20
    static let days = 14

    static func folder(of project: LampProject) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Edition.appBundlePrefix + project.id)
    }

    /// Takes the copy when the app has data and it changed since the last one. Off the main thread, and it never
    /// stops the change: a copy that can't be made is only logged.
    static func take(_ project: LampProject) async {
        guard !project.onIOS else { return }
        let version = running(project)
        let data = folder(of: project)
        await Task.detached(priority: .utility) { snapshot(data, version: version) }.value
    }

    // MARK: What the app runs

    private static func runningKey(_ project: LampProject) -> String { "dataSnapshots.running.\(project.id)" }

    /// The version the open (or last opened) Mac app runs, as `wentIn` last recorded it.
    static func running(_ project: LampProject) -> String? {
        UserDefaults.standard.string(forKey: runningKey(project))
    }

    /// Records the code that just went into the app. Repository HEAD is that code only once it's saved: a turn's
    /// looks install code it hasn't saved yet, which is marked so its data isn't taken for the saved version's.
    static func wentIn(_ project: LampProject) async {
        guard !project.onIOS, let head = await Versions.head(project) else { return }
        let label = String(head.prefix(8)) + (await Versions.hasUnsavedChanges(project) ? "+unsaved" : "")
        UserDefaults.standard.set(label, forKey: runningKey(project))
    }

    // MARK: The copy

    /// The work of `take`, for a data folder; returns the copy made, if one was.
    @discardableResult
    static func snapshot(_ data: URL, version: String?, now: Date = Date()) -> URL? {
        let fm = FileManager.default
        let database = data.appendingPathComponent("data.sqlite")
        let backups = data.appendingPathComponent("Backups")
        // The app's own code can put anything in its data folder, and Lamp writes and deletes here unconfined:
        // nothing on the way may be a link to somewhere else.
        guard !isLink(data), !isLink(database), fm.fileExists(atPath: database.path),
              !fm.fileExists(atPath: backups.path) || !isLink(backups) else { return nil }
        // What the copy covers is the data as last written before it began: a write that lands while it's made may
        // be missing from it, so the copy is dated then (below), and such a write makes the next one.
        // An empty write-ahead log holds nothing written: opening the database to read, this copy included, can leave one.
        let log = data.appendingPathComponent("data.sqlite-wal")
        let written = [database, size(of: log) == 0 ? nil : log].compactMap { $0.flatMap(modified) }.max() ?? now
        // A date set from a `Date` can come back a fraction of a microsecond early, which isn't a write.
        if let newest = changeCopies(in: backups).first.flatMap(modified), newest.addingTimeInterval(0.000_01) >= written { return nil }
        guard (try? fm.createDirectory(at: backups, withIntermediateDirectories: true)) != nil, !isLink(backups) else { return nil }

        let stamp = name(of: now)
        let label = (version ?? "unknown").filter { $0.isLetter || $0.isNumber || $0 == "+" }
        // A name of its own, so a copy made in the same instant never meets an earlier one.
        var target = backups.appendingPathComponent("\(prefix)\(stamp)-\(label).sqlite")
        var attempt = 1
        while fm.fileExists(atPath: target.path) || isLink(target) {
            attempt += 1
            target = backups.appendingPathComponent("\(prefix)\(stamp)-\(label)-\(attempt).sqlite")
        }
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        sqlite3_busy_timeout(db, 5000)
        let sql = "VACUUM INTO '\(target.path.replacingOccurrences(of: "'", with: "''"))'"
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            print("Couldn't copy \(data.lastPathComponent)'s data before a change: \(String(cString: sqlite3_errmsg(db)))")
            // Only what this attempt began: the name was free when it started.
            try? fm.removeItem(at: target)
            return nil
        }
        try? fm.setAttributes([.modificationDate: written], ofItemAtPath: target.path)
        prune(backups, now: now)
        return target
    }

    /// Newest first: the names start with the time they were taken.
    static func changeCopies(in backups: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "sqlite" && !isLink($0) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func prune(_ backups: URL, now: Date = Date()) {
        let copies = changeCopies(in: backups)
        var keep = Set(copies.prefix(kept))
        var daysSeen = Set<String>()
        let earliest = now.addingTimeInterval(-Double(days) * 86_400)
        for copy in copies {
            // When it was taken is in its name (its date on disk is when the data it holds was written).
            let stamp = String(copy.lastPathComponent.dropFirst(prefix.count).prefix(name(of: now).count))
            guard let taken = date(of: stamp), taken >= earliest, daysSeen.insert(String(stamp.prefix(10))).inserted else { continue }
            keep.insert(copy)
        }
        for copy in copies where !keep.contains(copy) { try? FileManager.default.removeItem(at: copy) }
    }

    // MARK: -

    /// 2026-10-19T22-50-14.985Z: sorts as it reads, and a file name can hold it.
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func name(of date: Date) -> String { formatter.string(from: date).replacingOccurrences(of: ":", with: "-") }

    private static func date(of name: String) -> Date? {
        guard name.count > 19 else { return nil }
        var text = name
        for offset in [13, 16] {
            let index = text.index(text.startIndex, offsetBy: offset)
            text.replaceSubrange(index...index, with: ":")
        }
        return formatter.date(from: text)
    }

    private static func isLink(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    private static func size(of url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
    }

    private static func modified(_ url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }
}
