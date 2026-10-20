import SQLite3
import XCTest
@testable import Lamp

/// Before a change goes into a Mac app, Lamp copies its database: once per change in what it holds, never through
/// a link the app's code left in its data folder, and pruned to the newest and one a day.
final class DataSnapshotsTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("DataSnapshots-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func write(_ sql: String, in folder: URL) {
        var db: OpaquePointer?
        sqlite3_open(folder.appendingPathComponent("data.sqlite").path, &db)
        sqlite3_exec(db, sql, nil, nil, nil)
        sqlite3_close(db)
    }

    func testCopiesOncePerChangeAndNeverThroughALink() throws {
        let data = root.appendingPathComponent("app")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        XCTAssertNil(DataSnapshots.snapshot(data, version: "abc"), "no database, no copy")

        write("PRAGMA journal_mode = WAL; CREATE TABLE t (x); INSERT INTO t VALUES (1);", in: data)
        let now = Date()
        let copy = try XCTUnwrap(DataSnapshots.snapshot(data, version: "01234567", now: now))
        XCTAssertTrue(copy.lastPathComponent.hasPrefix("change-") && copy.lastPathComponent.hasSuffix("-01234567.sqlite"))
        var db: OpaquePointer?
        sqlite3_open(copy.path, &db)
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT x FROM t", -1, &statement, nil)
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(statement, 0), 1)
        sqlite3_finalize(statement)
        sqlite3_close(db)
        // Dated when the data it holds was last written, not when the copy finished: a write during the copy is newer.
        let date = { (url: URL) in try! FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as! Date }
        let source = [data.appendingPathComponent("data.sqlite"), data.appendingPathComponent("data.sqlite-wal")]
            .filter { FileManager.default.fileExists(atPath: $0.path) }.map(date).max()!
        XCTAssertEqual(date(copy).timeIntervalSince1970, source.timeIntervalSince1970, accuracy: 0.001)

        XCTAssertNil(DataSnapshots.snapshot(data, version: "01234567", now: now), "unchanged since the last copy")
        // Changed, and copied again in the same instant under the same version: a second file, the first kept.
        Thread.sleep(forTimeInterval: 0.05)
        write("INSERT INTO t VALUES (2);", in: data)
        let second = try XCTUnwrap(DataSnapshots.snapshot(data, version: "01234567", now: now))
        XCTAssertNotEqual(second, copy)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))

        // Backups made a link elsewhere: nothing is written there.
        let elsewhere = root.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let other = root.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        write("CREATE TABLE t (x);", in: other)
        try FileManager.default.createSymbolicLink(at: other.appendingPathComponent("Backups"), withDestinationURL: elsewhere)
        XCTAssertNil(DataSnapshots.snapshot(other, version: nil))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: elsewhere.path), [])
    }

    func testPruneKeepsTheNewestAndOneADay() throws {
        let backups = root.appendingPathComponent("Backups")
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        let now = Date()
        // 30 copies an hour apart today and yesterday, and one from each of the 20 days before.
        var dates = (0..<30).map { now.addingTimeInterval(-Double($0) * 1800) }
        dates += (2..<22).map { now.addingTimeInterval(-Double($0) * 86_400) }
        for date in dates {
            let url = backups.appendingPathComponent("change-\(DataSnapshots.name(of: date))-abc.sqlite")
            FileManager.default.createFile(atPath: url.path, contents: Data())
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
        let launch = backups.appendingPathComponent("data-2026-01-01T00-00-00Z.sqlite")
        FileManager.default.createFile(atPath: launch.path, contents: Data())

        DataSnapshots.prune(backups, now: now)
        let left = DataSnapshots.changeCopies(in: backups)
        // The newest 20, and the newest of each of days 2 to 14 (one more when the half-hourly ones cross midnight).
        XCTAssertTrue((33...34).contains(left.count), "\(left.count)")
        XCTAssertFalse(left.contains { now.timeIntervalSince(try! FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as! Date) > 14.5 * 86_400 },
                       "older than two weeks goes")
        XCTAssertTrue(FileManager.default.fileExists(atPath: launch.path), "the app's own launch backups are its to prune")
    }
}
