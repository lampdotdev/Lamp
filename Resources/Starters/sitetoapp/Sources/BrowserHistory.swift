import Foundation
import SQLite3

/// The sites someone visits most, read from their browsers' history on this Mac: Chrome, Arc, Brave, Edge, Vivaldi
/// and, when the app may read it, Safari. It's read on this Mac and never sent anywhere.
enum BrowserHistory {
    struct Visit {
        let host: String
        var visits: Int
    }

    /// Hosts visited in the last 60 days, most visited first.
    static func topHosts(limit: Int = 40) -> [Visit] {
        var counts: [String: Int] = [:]
        for (host, n) in chromiumVisits() + safariVisits() {
            counts[host, default: 0] += n
        }
        return counts
            .filter { isCandidate($0.key) && $0.value >= 4 }
            .map { Visit(host: $0.key, visits: $0.value) }
            .sorted { $0.visits > $1.visits }
            .prefix(limit)
            .map { $0 }
    }

    private static func isCandidate(_ host: String) -> Bool {
        guard host.contains("."), !host.hasPrefix("localhost"), host.rangeOfCharacter(from: .letters) != nil else { return false }
        let skip: Set<String> = ["www.google.com", "google.com", "www.bing.com", "bing.com", "duckduckgo.com",
                                 "search.yahoo.com", "accounts.google.com", "myaccount.google.com", "consent.google.com",
                                 "login.microsoftonline.com", "login.live.com", "appleid.apple.com", "t.co", "lnkd.in",
                                 "bit.ly", "translate.google.com", "www.gstatic.com", "id.atlassian.com"]
        return !skip.contains(host)
    }

    // MARK: Chromium browsers

    private static let chromiumFolders = [
        "Google/Chrome", "Arc/User Data", "BraveSoftware/Brave-Browser", "Microsoft Edge", "Vivaldi", "Chromium",
    ]

    private static func chromiumVisits() -> [(String, Int)] {
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        // Chrome counts time in microseconds since 1601.
        let since = Int64((Date().addingTimeInterval(-60 * 86400).timeIntervalSince1970 + 11_644_473_600) * 1_000_000)
        var results: [(String, Int)] = []
        for folder in chromiumFolders {
            let base = support.appendingPathComponent(folder)
            let profiles = ((try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? [])
                .filter { $0 == "Default" || $0.hasPrefix("Profile ") }
            for profile in profiles {
                let file = base.appendingPathComponent(profile).appendingPathComponent("History")
                results += read(file, "SELECT url, visit_count FROM urls WHERE last_visit_time > \(since)")
            }
        }
        return results
    }

    // MARK: Safari

    private static func safariVisits() -> [(String, Int)] {
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari/History.db")
        // Safari counts time in seconds since 2001.
        let since = Date().addingTimeInterval(-60 * 86400).timeIntervalSinceReferenceDate
        return read(file, """
            SELECT i.url, COUNT(v.id) FROM history_visits v JOIN history_items i ON i.id = v.history_item
            WHERE v.visit_time > \(since) GROUP BY i.id
            """)
    }

    // MARK: Reading a history file

    /// A copy is read, since the browser keeps its own file locked while it's open.
    private static func read(_ file: URL, _ sql: String) -> [(String, Int)] {
        let files = FileManager.default
        guard files.isReadableFile(atPath: file.path) else { return [] }
        let copy = files.temporaryDirectory.appendingPathComponent("history-\(UUID().uuidString).db")
        guard (try? files.copyItem(at: file, to: copy)) != nil else { return [] }
        for suffix in ["-wal", "-shm"] where files.fileExists(atPath: file.path + suffix) {
            try? files.copyItem(atPath: file.path + suffix, toPath: copy.path + suffix)
        }
        defer {
            for suffix in ["", "-wal", "-shm"] { try? files.removeItem(atPath: copy.path + suffix) }
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var results: [(String, Int)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, 0),
                  let host = URL(string: String(cString: text))?.host()?.lowercased(),
                  URL(string: String(cString: text))?.scheme?.hasPrefix("http") == true else { continue }
            results.append((host, Int(sqlite3_column_int(statement, 1))))
        }
        return results
    }
}

extension Library {
    /// Fills `recent` with the sites someone visits most, worked out on this Mac alone: nothing is sent anywhere.
    func loadRecent() async {
        let visits = await Task.detached(priority: .utility) { BrowserHistory.topHosts() }.value
        let hosts = Set(sites.map(\.host))
        recent = visits
            .filter { !hosts.contains($0.host) && !SiteSuggestion.hasDesktopApp($0.host) }
            .prefix(8)
            .map { visit in
                let url = "https://\(visit.host)"
                return SiteSuggestion(name: AddSiteView.suggestedName(for: URL(string: url)), url: url, fromHistory: true)
            }
    }
}
