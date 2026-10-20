import Foundation
import SQLite3

/// A copy of a Mac app's LampStore database taken just before a change goes into the app, by reopening it or in
/// place. The app backs itself up only at the first write of each launch, and a change that goes in live doesn't
/// relaunch it: without this, data the new code spoils has no copy from before it. Each copy is named after the
/// version whose code wrote that data, so a version can later be matched to its data.
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
        let version = await Versions.head(project)
        let data = folder(of: project)
        await Task.detached(priority: .utility) { snapshot(data, version: version) }.value
    }

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
        let newest = changeCopies(in: backups).first.flatMap(modified)
        let written = [database, data.appendingPathComponent("data.sqlite-wal")].compactMap(modified).max()
        if let newest, let written, newest >= written { return nil }
        guard (try? fm.createDirectory(at: backups, withIntermediateDirectories: true)) != nil, !isLink(backups) else { return nil }

        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        let target = backups.appendingPathComponent("\(prefix)\(stamp)-\(version.map { String($0.prefix(8)) } ?? "unsaved").sqlite")
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        sqlite3_busy_timeout(db, 5000)
        let sql = "VACUUM INTO '\(target.path.replacingOccurrences(of: "'", with: "''"))'"
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            print("Couldn't copy \(data.lastPathComponent)'s data before a change: \(String(cString: sqlite3_errmsg(db)))")
            try? fm.removeItem(at: target)
            return nil
        }
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
            // The day is the start of the name: change-YYYY-MM-DD…
            let day = String(copy.lastPathComponent.dropFirst(prefix.count).prefix(10))
            guard let taken = modified(copy), taken >= earliest, daysSeen.insert(day).inserted else { continue }
            keep.insert(copy)
        }
        for copy in copies where !keep.contains(copy) { try? FileManager.default.removeItem(at: copy) }
    }

    private static func isLink(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    private static func modified(_ url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }
}
