import Foundation

/// The scaffold every generated app starts from.
enum Template {
    static func scaffold(name rawName: String, untitled: Bool = false, in root: URL) throws -> ForgeProject {
        let name = rawName.trimmed.filter { !"\"\\<>&/:".contains($0) }
        let exe = identifier(from: name)
        var slug = exe.lowercased()
        var n = 2
        while FileManager.default.fileExists(atPath: root.appendingPathComponent(slug).path) {
            slug = "\(exe.lowercased())-\(n)"
            n += 1
        }
        let project = ForgeProject(id: slug, name: name.isEmpty ? exe : name, exe: exe,
                                   dir: root.appendingPathComponent(slug), untitled: untitled)

        let files: [String: String] = [
            "Package.swift": packageSwift,
            "Sources/App.swift": appSwift,
            "Sources/ContentView.swift": contentViewSwift,
            "build.sh": buildSh,
            "APP.md": appMd,
            ".gitignore": ".build/\nbuild/\n.forge/\n",
        ]
        for (path, template) in files {
            let url = project.dir.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let contents = template
                .replacingOccurrences(of: "{{NAME}}", with: project.name)
                .replacingOccurrences(of: "{{EXE}}", with: project.exe)
                .replacingOccurrences(of: "{{SLUG}}", with: project.id)
                .replacingOccurrences(of: "{{BUNDLE}}", with: project.bundleID)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: project.dir.appendingPathComponent("build.sh").path)

        let forgeDir = project.dir.appendingPathComponent(".forge")
        try FileManager.default.createDirectory(at: forgeDir, withIntermediateDirectories: true)
        try JSONEncoder().encode(ProjectMeta(name: project.name, exe: project.exe, untitled: untitled ? true : nil))
            .write(to: forgeDir.appendingPathComponent("meta.json"))
        try writeSupport(for: project)
        return project
    }

    /// Per-app secret the app sends to Forge's AI gateway. Created on first use.
    static func token(for project: ForgeProject) -> String {
        let url = project.dir.appendingPathComponent(".forge/token")
        if let token = (try? String(contentsOf: url, encoding: .utf8))?.trimmed, !token.isEmpty { return token }
        let token = UUID().uuidString + UUID().uuidString
        try? token.write(to: url, atomically: true, encoding: .utf8)
        return token
    }

    /// Apps used to build unoptimized (`-c debug`), which made games and simulations run many times slower.
    /// Forge owns build.sh, so before each build it moves older apps to optimized builds, with debug info
    /// (-g) so crash reports keep file names and line numbers.
    static func upgradeBuildScript(for project: ForgeProject) {
        let url = project.dir.appendingPathComponent("build.sh")
        guard let script = try? String(contentsOf: url, encoding: .utf8), script.contains("swift build -c debug") else { return }
        let upgraded = script.replacingOccurrences(of: "swift build -c debug", with: "swift build -c release -Xswiftc -g")
        try? upgraded.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// Forge owns ForgeSupport.swift and rewrites it before every agent turn and build,
    /// so existing apps pick up helper improvements automatically.
    static func writeSupport(for project: ForgeProject) throws {
        let contents = forgeSupportSwift
            .replacingOccurrences(of: "{{SLUG}}", with: project.id)
            .replacingOccurrences(of: "{{TOKEN}}", with: token(for: project))
            .replacingOccurrences(of: "{{PORT}}", with: String(Gateway.port))
        // Left alone when it's already current, so its date only moves when the app needs a rebuild.
        let url = project.dir.appendingPathComponent("Sources/ForgeSupport.swift")
        if (try? String(contentsOf: url, encoding: .utf8)) != contents {
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// "pomodoro timer!" → "PomodoroTimer"
    static func identifier(from name: String) -> String {
        let words = name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        var id = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
        if id.isEmpty { id = "Untitled" }
        if id.first!.isNumber { id = "App" + id }
        return id
    }

    static let packageSwift = """
    // swift-tools-version:5.9
    import PackageDescription

    let package = Package(
        name: "{{EXE}}",
        platforms: [.macOS(.v14)],
        targets: [.executableTarget(name: "{{EXE}}", path: "Sources")]
    )

    """

    static let appSwift = """
    import SwiftUI

    @main
    struct MainApp: SwiftUI.App {
        var body: some SwiftUI.Scene {
            WindowGroup("{{NAME}}") {
                ContentView()
            }
            .commands { ForgeCommands() }
        }
    }

    """

    /// The line every fresh scaffold shows. It's gone as soon as an agent writes the app's real interface.
    static let scaffoldHint = "Press ⇧⌘E to tell Forge what to build."

    /// Whether the app is still the empty scaffold: nothing has been built into it yet.
    static func isScaffold(_ project: ForgeProject) -> Bool {
        let view = try? String(contentsOf: project.dir.appendingPathComponent("Sources/ContentView.swift"), encoding: .utf8)
        return view?.contains(scaffoldHint) ?? false
    }

    static let contentViewSwift = """
    import SwiftUI

    struct ContentView: View {
        var body: some View {
            VStack(spacing: 12) {
                Image(systemName: "hammer")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("{{NAME}}")
                    .font(.title2.bold())
                Text("\(scaffoldHint)")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(minWidth: 420, minHeight: 300)
        }
    }

    """

    static let forgeSupportSwift = #"""
    // Generated by Forge before every build. Don't edit: changes are overwritten.
    import SwiftUI
    import AppKit
    import SQLite3

    /// Adds "Edit with Forge…" (⇧⌘E), which jumps back to this app's chat in Forge.
    struct ForgeCommands: Commands {
        init() {
            ForgeRuntime.start
            ForgeWindows.start
        }

        var body: some Commands {
            CommandGroup(after: .appInfo) {
                Button("Edit with Forge…") {
                    NSWorkspace.shared.open(URL(string: "forge://edit?app={{SLUG}}")!)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }

    /// Lets Forge's Play button bring this app back with a window: macOS's "reopen" request doesn't make a
    /// SwiftUI app open one when another app asks, so Forge sends this message instead.
    enum ForgeWindows {
        static let start: Void = {
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("dev.forge.showWindow"), object: Bundle.main.bundleIdentifier, queue: .main
            ) { _ in
                MainActor.assumeIsolated { show() }
            }
        }()

        @MainActor static func show() {
            NSApp.unhide(nil)
            let windows = NSApp.windows.filter { $0.canBecomeMain }
            if let minimized = windows.first(where: \.isMiniaturized), !windows.contains(where: \.isVisible) {
                minimized.deminiaturize(nil)
            } else if !windows.contains(where: \.isVisible), let item = newWindowItem(in: NSApp.mainMenu),
                      let menu = item.menu {
                // SwiftUI's File ▸ New … Window (⌘N).
                menu.performActionForItem(at: menu.index(of: item))
            }
            NSApp.activate()
            NSApp.windows.first { $0.isVisible && $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        }

        private static func newWindowItem(in menu: NSMenu?) -> NSMenuItem? {
            for item in menu?.items ?? [] {
                if item.keyEquivalent == "n", item.keyEquivalentModifierMask == .command, item.isEnabled { return item }
                if let found = newWindowItem(in: item.submenu) { return found }
            }
            return nil
        }
    }

    /// Saves what this app prints (`print`, `NSLog`, SwiftUI runtime warnings, fatal errors) and a picture of
    /// its windows to its Forge project, where Forge's builder looks to see what happened while the app ran.
    enum ForgeRuntime {
        static let folder = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Forge/Apps/{{SLUG}}/.forge/runtime")

        /// Runs once, at launch. Each launch starts a new log.txt and keeps the one before as previous-log.txt.
        static let start: Void = {
            let fm = FileManager.default
            // Only on a Mac where Forge has this app's project.
            guard fm.fileExists(atPath: folder.deletingLastPathComponent().path) else { return }
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            // Pictures: once the first window has settled, and whenever the user leaves the app
            // (often to ask Forge for a change).
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { MainActor.assumeIsolated { snapshot() } }
            NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                   object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { snapshot() }
            }
            // Forge asks for fresh pictures when its builder wants to look at the app.
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("dev.forge.snapshot.{{SLUG}}"), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { snapshot() }
            }
            let log = folder.appendingPathComponent("log.txt")
            let previous = folder.appendingPathComponent("previous-log.txt")
            try? fm.removeItem(at: previous)
            try? fm.moveItem(at: log, to: previous)
            guard freopen(log.path, "a", stderr) != nil else { return }
            dup2(fileno(stderr), STDOUT_FILENO)
            setvbuf(stdout, nil, _IOLBF, 0)   // so nothing is lost if the app crashes
            setvbuf(stderr, nil, _IONBF, 0)
            fputs("Launched \(Date().formatted(date: .abbreviated, time: .standard))\n", stderr)
            NSSetUncaughtExceptionHandler { exception in
                fputs("Uncaught exception \(exception.name.rawValue): \(exception.reason ?? "")\n"
                      + exception.callStackSymbols.prefix(20).joined(separator: "\n") + "\n", stderr)
            }
            trimmer.resume()
        }()

        /// Saves up to three open windows, frontmost first, as screenshot.png, screenshot-2.png and screenshot-3.png.
        /// The app draws its own windows, so this needs no screen recording permission.
        @MainActor
        static func snapshot() {
            let windows = NSApp.orderedWindows.filter {
                $0.isVisible && !$0.isMiniaturized && $0.frame.width > 40 && $0.frame.height > 40
            }
            guard !windows.isEmpty else { return }   // nothing on screen: keep the last pictures
            for index in 0..<3 {
                let url = folder.appendingPathComponent(index == 0 ? "screenshot.png" : "screenshot-\(index + 1).png")
                if index < windows.count, let png = picture(of: windows[index]) {
                    try? png.write(to: url, options: .atomic)
                } else {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }

        /// The window with its title bar, at most 1600 pixels on the long side.
        @MainActor
        private static func picture(of window: NSWindow) -> Data? {
            guard let view = window.contentView?.superview ?? window.contentView else { return nil }
            let size = view.bounds.size
            let scale = min(window.backingScaleFactor, 1600 / max(size.width, size.height))
            guard let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
            bitmap.size = size
            view.cacheDisplay(in: view.bounds, to: bitmap)
            return bitmap.representation(using: .png, properties: [:])
        }

        /// Keeps a chatty app from filling the disk: past 1 MB, the log starts over.
        private static let trimmer: DispatchSourceTimer = {
            let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            timer.schedule(deadline: .now() + 30, repeating: 30)
            timer.setEventHandler {
                var info = stat()
                guard fstat(fileno(stderr), &info) == 0, info.st_size > 1_000_000 else { return }
                ftruncate(fileno(stderr), 0)
                fputs("(Earlier output was dropped: the log passed 1 MB.)\n", stderr)
            }
            return timer
        }()
    }

    /// Keeps the app's data safe across launches and across changes to the app, in a SQLite database
    /// (~/Library/Application Support/<bundle id>/data.sqlite). Three ways in, simplest first:
    ///
    ///     // 1. One value, saved whole: settings, small state.
    ///     @State private var prefs = ForgeStore.load(Prefs.self, from: "prefs") ?? Prefs()
    ///     .onChange(of: prefs) { ForgeStore.save(prefs, to: "prefs") }
    ///
    ///     // 2. A collection of items, saved one at a time: notes, tasks, files seen. Scales to large lists.
    ///     let notes = ForgeStore.collection("notes", of: Note.self)   // Note: Codable & Identifiable
    ///     notes.put(note); notes.all(); notes.get(id); notes.delete(id)
    ///     notes.all(where: "kind", equals: "receipt", orderBy: "date", descending: true, limit: 50)
    ///
    ///     // 3. Your own tables, for joins, aggregates or full-text search.
    ///     ForgeStore.execute("CREATE TABLE IF NOT EXISTS visits (url TEXT, at REAL)")
    ///     ForgeStore.execute("INSERT INTO visits VALUES (?, ?)", url, Date().timeIntervalSince1970)
    ///     let rows = ForgeStore.query("SELECT url, count(*) AS n FROM visits GROUP BY url")   // [[String: Any]]
    ///
    /// Values and items are stored as JSON, so adding an optional property never breaks old data. Before the
    /// first change of each launch, the database is copied to Backups/ (the newest 20 are kept). Anything this
    /// version of the app can't read is left untouched: the user is told once, and it loads again once fixed.
    /// `folder` suits other files the app keeps, such as images (store their names, not their bytes).
    enum ForgeStore {
        static let folder: URL = {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let url = base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "{{EXE}}")
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }()

        static var backups: URL { folder.appendingPathComponent("Backups") }

        // MARK: One value

        /// The saved value, or nil when there's none yet (or it can't be read; see above).
        static func load<T: Decodable>(_ type: T.Type, from name: String = "data") -> T? {
            importJSONFile(name)
            guard let json = query("SELECT json FROM forge_values WHERE name = ?", name).first?["json"] as? String else {
                return nil
            }
            do {
                return try decoder.decode(T.self, from: Data(json.utf8))
            } catch {
                lock.withLock { _ = unreadable.insert(name) }
                problem("couldn't read the saved \"\(name)\", so it won't be overwritten. Make the types decode the "
                        + "existing data (add new properties as optionals), and it loads again. Error: \(error)")
                return nil
            }
        }

        static func save<T: Encodable>(_ value: T, to name: String = "data") {
            guard let json = encode(value) else { return }
            if lock.withLock({ unreadable.contains(name) }) {
                // Keep what the user does now as well, without touching the data that couldn't be read.
                execute("INSERT OR REPLACE INTO forge_values (name, json, updated) VALUES (?, ?, ?)",
                        name + " (while unreadable)", json, Date().timeIntervalSince1970)
                return
            }
            execute("INSERT OR REPLACE INTO forge_values (name, json, updated) VALUES (?, ?, ?)",
                    name, json, Date().timeIntervalSince1970)
        }

        // MARK: Collections

        static func collection<T: Codable & Identifiable>(_ name: String, of type: T.Type) -> Collection<T> {
            Collection(name: name)
        }

        struct Collection<T: Codable & Identifiable> {
            let name: String

            /// Adds the item, or replaces the one with the same id.
            func put(_ item: T) {
                guard let json = ForgeStore.encode(item) else { return }
                ForgeStore.execute("INSERT OR REPLACE INTO forge_items (collection, id, json, updated) VALUES (?, ?, ?, ?)",
                                   name, "\(item.id)", json, Date().timeIntervalSince1970)
            }

            /// Adds or replaces several items in one transaction (much faster than one at a time).
            func put(_ items: [T]) {
                ForgeStore.transaction { items.forEach(put) }
            }

            func get(_ id: T.ID) -> T? {
                decode(ForgeStore.query("SELECT id, json FROM forge_items WHERE collection = ? AND id = ?", name, "\(id)")).first
            }

            func delete(_ id: T.ID) {
                ForgeStore.execute("DELETE FROM forge_items WHERE collection = ? AND id = ?", name, "\(id)")
            }

            func deleteAll() {
                ForgeStore.execute("DELETE FROM forge_items WHERE collection = ?", name)
            }

            var count: Int {
                ForgeStore.query("SELECT count(*) AS n FROM forge_items WHERE collection = ?", name).first?["n"] as? Int ?? 0
            }

            /// Items, optionally only those whose `field` equals `value`, sorted by a field (default: oldest
            /// change first). Fields are top-level property names; nested ones use a path like "author.name".
            func all(where field: String? = nil, equals value: Any? = nil, orderBy order: String? = nil,
                     descending: Bool = false, limit: Int? = nil) -> [T] {
                var sql = "SELECT id, json FROM forge_items WHERE collection = ?"
                var args: [Any?] = [name]
                if let field {
                    sql += " AND json_extract(json, ?) = ?"
                    args += ["$." + field, value is Bool ? ((value as! Bool) ? 1 : 0) : value]
                }
                if let order {
                    sql += " ORDER BY json_extract(json, ?)"
                    args.append("$." + order)
                } else {
                    sql += " ORDER BY updated"
                }
                if descending { sql += " DESC" }
                if let limit { sql += " LIMIT \(max(0, limit))" }
                return decode(ForgeStore.query(sql, args))
            }

            /// Rows that can't be decoded are skipped and left as they are, never deleted.
            private func decode(_ rows: [[String: Any]]) -> [T] {
                rows.compactMap { row in
                    guard let json = row["json"] as? String else { return nil }
                    do {
                        return try ForgeStore.decoder.decode(T.self, from: Data(json.utf8))
                    } catch {
                        ForgeStore.problem("skipped an item in \"\(name)\" (id \(row["id"] ?? "?")) that couldn't be read; "
                                           + "it's kept as it is. Make the type decode it (add new properties as optionals). "
                                           + "Error: \(error)")
                        return nil
                    }
                }
            }
        }

        // MARK: SQL

        /// Runs a statement with `?` placeholders. Arguments: String, Int, Double, Bool, Date, Data or nil.
        /// Your own tables: create them with IF NOT EXISTS, and change them only by adding columns.
        @discardableResult
        static func execute(_ sql: String, _ args: Any?...) -> Bool { execute(sql, args) }

        @discardableResult
        static func execute(_ sql: String, _ args: [Any?]) -> Bool {
            lock.withLock {
                backUpOnce()
                return run(sql, args) { _ in } != nil
            }
        }

        /// Rows as dictionaries keyed by column name: Int, Double, String, Data or NSNull.
        static func query(_ sql: String, _ args: Any?...) -> [[String: Any]] { query(sql, args) }

        static func query(_ sql: String, _ args: [Any?]) -> [[String: Any]] {
            lock.withLock {
                var rows: [[String: Any]] = []
                _ = run(sql, args) { statement in
                    var row: [String: Any] = [:]
                    for column in 0..<sqlite3_column_count(statement) {
                        let key = String(cString: sqlite3_column_name(statement, column))
                        switch sqlite3_column_type(statement, column) {
                        case SQLITE_INTEGER: row[key] = Int(sqlite3_column_int64(statement, column))
                        case SQLITE_FLOAT: row[key] = sqlite3_column_double(statement, column)
                        case SQLITE_TEXT: row[key] = String(cString: sqlite3_column_text(statement, column))
                        case SQLITE_BLOB:
                            let count = Int(sqlite3_column_bytes(statement, column))
                            row[key] = count == 0 ? Data() : Data(bytes: sqlite3_column_blob(statement, column), count: count)
                        default: row[key] = NSNull()
                        }
                    }
                    rows.append(row)
                }
                return rows
            }
        }

        /// Runs `body` as one transaction: all its changes are saved together, or none are.
        static func transaction(_ body: () -> Void) {
            lock.withLock {
                execute("BEGIN")
                body()
                execute("COMMIT")
            }
        }

        // MARK: Internals

        private static let lock = NSRecursiveLock()
        nonisolated(unsafe) private static var unreadable: Set<String> = []
        nonisolated(unsafe) private static var backedUp = false
        nonisolated(unsafe) private static var warned = false

        static let decoder: JSONDecoder = {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return decoder
        }()

        static func encode<T: Encodable>(_ value: T) -> String? {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            do {
                return String(decoding: try encoder.encode(value), as: UTF8.self)
            } catch {
                print("ForgeStore: couldn't save a \(T.self): \(error)")
                return nil
            }
        }

        nonisolated(unsafe) private static let db: OpaquePointer? = {
            var db: OpaquePointer?
            let path = folder.appendingPathComponent("data.sqlite").path
            guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK
            else {
                print("ForgeStore: couldn't open \(path)")
                return nil
            }
            sqlite3_busy_timeout(db, 5000)
            for sql in ["PRAGMA journal_mode = WAL",
                        "CREATE TABLE IF NOT EXISTS forge_values (name TEXT PRIMARY KEY, json TEXT NOT NULL, updated REAL)",
                        "CREATE TABLE IF NOT EXISTS forge_items (collection TEXT NOT NULL, id TEXT NOT NULL, json TEXT NOT NULL, "
                            + "updated REAL, PRIMARY KEY (collection, id))"] {
                sqlite3_exec(db, sql, nil, nil, nil)
            }
            return db
        }()

        /// Prepares, binds and steps one statement, calling `row` for each result row. nil on failure.
        private static func run(_ sql: String, _ args: [Any?], row: (OpaquePointer) -> Void) -> Void? {
            guard let db else { return nil }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                print("ForgeStore: SQL error in \(sql): \(String(cString: sqlite3_errmsg(db)))")
                return nil
            }
            defer { sqlite3_finalize(statement) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            for (index, arg) in args.enumerated() {
                let i = Int32(index + 1)
                switch arg {
                case nil, is NSNull: sqlite3_bind_null(statement, i)
                case let v as Bool: sqlite3_bind_int64(statement, i, v ? 1 : 0)
                case let v as Int: sqlite3_bind_int64(statement, i, Int64(v))
                case let v as Int64: sqlite3_bind_int64(statement, i, v)
                case let v as Double: sqlite3_bind_double(statement, i, v)
                case let v as Float: sqlite3_bind_double(statement, i, Double(v))
                case let v as Date: sqlite3_bind_double(statement, i, v.timeIntervalSince1970)
                case let v as Data: _ = v.withUnsafeBytes { sqlite3_bind_blob(statement, i, $0.baseAddress, Int32(v.count), transient) }
                case let v as String: sqlite3_bind_text(statement, i, v, -1, transient)
                case let v?: sqlite3_bind_text(statement, i, "\(v)", -1, transient)
                }
            }
            while true {
                switch sqlite3_step(statement) {
                case SQLITE_ROW: row(statement)
                case SQLITE_DONE: return ()
                default:
                    print("ForgeStore: SQL error in \(sql): \(String(cString: sqlite3_errmsg(db)))")
                    return nil
                }
            }
        }

        /// Before the first change of each launch: a copy of the database in Backups/, keeping the newest 20.
        private static func backUpOnce() {
            guard !backedUp, let db else { return }
            backedUp = true
            let fm = FileManager.default
            var any = false
            _ = run("SELECT 1 FROM forge_values UNION ALL SELECT 1 FROM forge_items LIMIT 1", []) { _ in any = true }
            guard any else { return }
            try? fm.createDirectory(at: backups, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let target = backups.appendingPathComponent("data-\(stamp).sqlite").path
            sqlite3_exec(db, "VACUUM INTO '\(target.replacingOccurrences(of: "'", with: "''"))'", nil, nil, nil)
            let old = ((try? fm.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.hasPrefix("data-20") && $0.pathExtension == "sqlite" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            for file in old.dropFirst(20) { try? fm.removeItem(at: file) }
        }

        /// Brings in a value saved as <name>.json by earlier versions of ForgeStore, once.
        private static func importJSONFile(_ name: String) {
            let file = folder.appendingPathComponent(name + ".json")
            guard let data = try? Data(contentsOf: file), let json = String(data: data, encoding: .utf8) else { return }
            execute("INSERT OR IGNORE INTO forge_values (name, json, updated) VALUES (?, ?, ?)",
                    name, json, Date().timeIntervalSince1970)
            try? FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
            try? FileManager.default.moveItem(at: file, to: backups.appendingPathComponent("\(name)-imported.json"))
        }

        static func problem(_ message: String) {
            print("ForgeStore: " + message)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard !warned else { return }
                    warned = true
                    let alert = NSAlert()
                    alert.messageText = "Some saved data couldn't be opened"
                    alert.informativeText = "This version of the app can't read some data saved by an earlier one. Your data "
                        + "is safe and won't be overwritten. Choose Edit with Forge (⇧⌘E) and ask Forge to fix it."
                    alert.runModal()
                }
            }
        }
    }

    /// Files attached in Forge's chat, bundled inside this app (Contents/Resources/Attachments).
    ///
    ///     let logo = ForgeAssets.image("logo.png")
    ///     let csv = ForgeAssets.text("prices.csv")
    enum ForgeAssets {
        static var folder: URL? { Bundle.main.resourceURL?.appendingPathComponent("Attachments") }

        static func url(_ name: String) -> URL? {
            guard let url = folder?.appendingPathComponent(name),
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url
        }

        static func image(_ name: String) -> NSImage? { url(name).flatMap(NSImage.init(contentsOf:)) }

        static func text(_ name: String) -> String? { url(name).flatMap { try? String(contentsOf: $0, encoding: .utf8) } }

        /// Every attached file's name.
        static var names: [String] {
            guard let folder else { return [] }
            return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
        }
    }

    /// AI for this app, using the same AI account as Forge. No API keys needed.
    ///
    ///     let summary = try await ForgeAI.ask("Summarise these notes:\n\(notes)")
    ///
    ///     struct Items: Decodable { let items: [String] }
    ///     let result = try await ForgeAI.ask("Extract action items from:\n\(notes)\n" +
    ///         #"Reply as JSON: {"items": ["..."]}"#, as: Items.self)
    ///
    /// Pass images (photos, screenshots, camera frames) to have the AI look at them:
    ///
    ///     let verdict = try await ForgeAI.ask("What's in this photo?", images: [photo])
    ///
    /// To read text, barcodes or faces, or to tag images, use Vision instead: it's on-device, instant and free.
    ///
    /// Create or edit pictures with an image model:
    ///
    ///     let poster = try await ForgeAI.makeImage("a retro travel poster of Lisbon", aspectRatio: "3:4")
    ///     let edited = try await ForgeAI.editImage(photo, "turn this into a watercolour painting")
    ///     let combined = try await ForgeAI.editImages([person, beach], "put the person from the first photo on this beach")
    ///
    /// Make quick decisions with a decision model (Jev): probabilities and confidence, not text.
    /// Use these to classify, route, filter, prioritise, match or moderate anything by its meaning.
    /// They're smart, answer in well under a second and cost about $0.04 per million input tokens, so judging
    /// every item (hundreds of files, messages or rows) is fine and costs a fraction of a cent. Prefer them to
    /// keyword lists or hand-written rules that guess at meaning; keep exact facts (sizes, dates) in code and
    /// pass them in as part of the state.
    ///
    ///     let urgent = try await ForgeAI.isTrue("Does this message need a reply today?", about: email)   // 0…1
    ///     let team = try await ForgeAI.choose("Which team should handle this?", from: ["billing", "bugs", "sales"], about: ticket)
    ///     if team.confidence ?? 0 > 0.7 { route(to: team.choice!) } else { askUser() }
    ///     let mood = try await ForgeAI.rate("How frustrated is the customer?", levels: ["Calm", "Annoyed", "Furious"], about: ticket)
    ///
    /// `about:` takes text, a dictionary/array, or any Encodable value. Ask several questions about the same
    /// thing in one request with `ForgeAI.decide(about:_:)`; they run in parallel. To judge many items, run one
    /// call per item concurrently:
    ///
    ///     let verdicts = try await withThrowingTaskGroup(of: (URL, Double).self) { group in
    ///         for file in files {
    ///             group.addTask {
    ///                 let info: [String: Any] = ["name": file.lastPathComponent, "size_mb": sizeMB(file), "days_old": age(file)]
    ///                 return (file, try await ForgeAI.isTrue("Is this file safe to throw away?", about: info))
    ///             }
    ///         }
    ///         return try await group.reduce(into: [:]) { $0[$1.0] = $1.1 }
    ///     }
    ///
    /// Text calls take a few seconds; decisions well under a second; image calls 10–60 seconds. Show a ProgressView, and show
    /// `error.localizedDescription` on failure. Aspect ratios look like "1:1", "16:9", "3:4".
    enum ForgeAI {
        struct Failure: LocalizedError {
            let message: String
            var errorDescription: String? { message }
        }

        static func ask(_ prompt: String, images: [NSImage] = [], system: String? = nil) async throws -> String {
            try await call(prompt: prompt, images: images, system: system, json: false)
        }

        /// Asks for JSON and decodes it. Describe the exact JSON shape in the prompt.
        static func ask<T: Decodable>(_ prompt: String, images: [NSImage] = [], system: String? = nil,
                                      as type: T.Type) async throws -> T {
            let text = try await call(prompt: prompt, images: images, system: system, json: true)
            do {
                return try JSONDecoder().decode(T.self, from: Data(text.utf8))
            } catch {
                throw Failure(message: "The AI's answer wasn't in the expected format. Try again.")
            }
        }

        /// Creates a new picture from a description.
        static func makeImage(_ description: String, aspectRatio: String = "1:1") async throws -> NSImage {
            try await image(prompt: description, images: [], aspectRatio: aspectRatio)
        }

        /// Changes a picture following an instruction, e.g. "remove the background" or "make it night time".
        /// Leave `aspectRatio` nil to keep the original shape where the model allows.
        static func editImage(_ image: NSImage, _ instruction: String, aspectRatio: String? = nil) async throws -> NSImage {
            try await self.image(prompt: instruction, images: [image], aspectRatio: aspectRatio)
        }

        /// Combines or edits several pictures following an instruction that can refer to them in order.
        static func editImages(_ images: [NSImage], _ instruction: String, aspectRatio: String? = nil) async throws -> NSImage {
            try await image(prompt: instruction, images: images, aspectRatio: aspectRatio)
        }

        // MARK: Decisions

        /// The probability (0…1) that the answer to a yes/no question is yes.
        static func isTrue(_ question: String, about state: Any, yes: String? = nil, no: String? = nil) async throws -> Double {
            let answer = try await decide(about: state, ["q": .yesNo(question, yes: yes, no: no)])["q"]
            guard let probability = answer?.probability else { throw Failure(message: "The decision model didn't answer.") }
            return probability
        }

        /// Picks one option. Check `confidence` before acting on a close call; `probabilities` has every option.
        static func choose(_ question: String, from options: [String], about state: Any) async throws -> ForgeDecision {
            guard let answer = try await decide(about: state, ["q": .choice(question, options: options)])["q"] else {
                throw Failure(message: "The decision model didn't answer.")
            }
            return answer
        }

        /// Places something on a scale of described levels. `score` runs from 0 to levels.count - 1 and can
        /// land between levels.
        static func rate(_ question: String, levels: [String], about state: Any) async throws -> ForgeDecision {
            guard let answer = try await decide(about: state, ["q": .score(question, levels: levels)])["q"] else {
                throw Failure(message: "The decision model didn't answer.")
            }
            return answer
        }

        /// Asks several questions about the same thing in one request. Answers come back under the same keys.
        static func decide(about state: Any, _ questions: [String: ForgeQuestion]) async throws -> [String: ForgeDecision] {
            let reply = try await post("/ai/decide", [
                "state": try jsonState(state),
                "questions": questions.mapValues(\.json),
            ])
            let answers = reply["answers"] as? [String: [String: Any]] ?? [:]
            return answers.mapValues(ForgeDecision.init)
        }

        private static func jsonState(_ state: Any) throws -> Any {
            if let text = state as? String { return text }
            if JSONSerialization.isValidJSONObject(state) { return state }
            if let value = state as? any Encodable {
                return try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: .fragmentsAllowed)
            }
            throw Failure(message: "Pass text, a dictionary or array, or an Encodable value to a decision.")
        }

        private static func image(prompt: String, images: [NSImage], aspectRatio: String?) async throws -> NSImage {
            var body: [String: Any] = ["prompt": prompt, "images": images.compactMap(encode)]
            if let aspectRatio { body["aspect_ratio"] = aspectRatio }
            let reply = try await post("/ai/image", body)
            guard let base64 = reply["image"] as? String, let data = Data(base64Encoded: base64),
                  let picture = NSImage(data: data) else {
                throw Failure(message: "The image model didn't return a picture.")
            }
            return picture
        }

        private static func call(prompt: String, images: [NSImage], system: String?, json: Bool) async throws -> String {
            let reply = try await post("/ai", [
                "prompt": prompt, "system": system ?? "", "json": json, "images": images.compactMap(encode),
            ])
            guard let text = reply["text"] as? String else { throw Failure(message: "The AI request failed.") }
            return text
        }

        private static func post(_ path: String, _ body: [String: Any]) async throws -> [String: Any] {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:{{PORT}}" + path)!)
            request.httpMethod = "POST"
            request.timeoutInterval = 240
            request.setValue("Bearer {{TOKEN}}", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            for attempt in 0..<2 {
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
                    if (response as? HTTPURLResponse)?.statusCode == 200 { return reply }
                    let message = reply["error"] as? String ?? "The AI request failed."
                    fputs("ForgeAI \(path) failed: \(message)\n", stderr)
                    throw Failure(message: message)
                } catch let error as URLError where error.code == .cannotConnectToHost && attempt == 0 {
                    // Forge isn't running: start it in the background, then retry once.
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = false
                    if let forge = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "dev.forge.host") {
                        _ = try? await NSWorkspace.shared.openApplication(at: forge, configuration: config)
                    }
                    try await Task.sleep(for: .seconds(3))
                }
            }
            fputs("ForgeAI \(path) failed: couldn't reach Forge\n", stderr)
            throw Failure(message: "Couldn't reach Forge. Open Forge and try again.")
        }

        /// Downscales to at most 1568px on the long side (the most the model uses) and JPEG-encodes.
        private static func encode(_ image: NSImage) -> [String: String]? {
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            let scale = min(1, 1568 / Double(max(cg.width, cg.height)))
            let width = max(1, Int(Double(cg.width) * scale)), height = max(1, Int(Double(cg.height) * scale))
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            context.interpolationQuality = .high
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let scaled = context.makeImage(),
                  let jpeg = NSBitmapImageRep(cgImage: scaled).representation(using: .jpeg, properties: [.compressionFactor: 0.8])
            else { return nil }
            return ["media_type": "image/jpeg", "data": jpeg.base64EncodedString()]
        }
    }

    /// A question for `ForgeAI.decide`. Put the full meaning in the question; give options/levels clear descriptions.
    struct ForgeQuestion {
        let json: [String: Any]

        /// Yes/no. Optionally describe what counts as yes and no.
        static func yesNo(_ question: String, yes: String? = nil, no: String? = nil) -> ForgeQuestion {
            var json: [String: Any] = ["type": "noul", "instructions": question]
            if yes != nil || no != nil { json["criteria"] = ["true": yes ?? "Yes", "false": no ?? "No"] }
            return ForgeQuestion(json: json)
        }

        /// Pick one of these options. Include a "none of these" option when nothing may fit.
        static func choice(_ question: String, options: [String]) -> ForgeQuestion {
            ForgeQuestion(json: ["type": "choice", "instructions": question,
                                 "criteria": Dictionary(uniqueKeysWithValues: options.map { ($0, NSNull()) })])
        }

        /// Pick one option, each with a description of when it applies.
        static func choice(_ question: String, options: [String: String]) -> ForgeQuestion {
            ForgeQuestion(json: ["type": "choice", "instructions": question, "criteria": options])
        }

        /// Rate on ordered levels (2–10), lowest first. Describe each level as a concrete situation.
        static func score(_ question: String, levels: [String]) -> ForgeQuestion {
            ForgeQuestion(json: ["type": "score", "instructions": question, "criteria": levels])
        }
    }

    /// The answer to one decision question.
    struct ForgeDecision {
        /// Yes/no questions: the probability (0…1) that the answer is yes.
        let probability: Double?
        /// Choice questions: the most likely option.
        let choice: String?
        /// Score questions: 0…levels-1, weighted by probability, so it can land between levels.
        let score: Double?
        /// Every option (choice) or level index as text (score), with its probability.
        let probabilities: [String: Double]
        /// Choice and score: how concentrated the probabilities are (0…1). Low means a close call.
        let confidence: Double?

        init(_ json: [String: Any]) {
            probability = json["noul"] as? Double
            choice = json["choice"] as? String
            score = json["score"] as? Double
            probabilities = json["probabilities"] as? [String: Double] ?? [:]
            confidence = json["confidence"] as? Double
        }
    }

    """#

    static let buildSh = """
    #!/bin/zsh
    # Builds build/{{EXE}}.app. Run after every change.
    set -euo pipefail
    cd "$(dirname "$0")"
    swift build -c release -Xswiftc -g 2>&1
    BIN="$(swift build -c release -Xswiftc -g --show-bin-path)/{{EXE}}"
    APP="build/{{EXE}}.app"
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS"
    cp "$BIN" "$APP/Contents/MacOS/{{EXE}}"
    cat > "$APP/Contents/Info.plist" <<PLIST
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>CFBundleExecutable</key><string>{{EXE}}</string>
      <key>CFBundleIdentifier</key><string>{{BUNDLE}}</string>
      <key>CFBundleName</key><string>{{NAME}}</string>
      <key>CFBundleDisplayName</key><string>{{NAME}}</string>
      <key>CFBundlePackageType</key><string>APPL</string>
      <key>CFBundleShortVersionString</key><string>0.1</string>
      <key>LSMinimumSystemVersion</key><string>14.0</string>
      <key>NSPrincipalClass</key><string>NSApplication</string>
      <key>NSHighResolutionCapable</key><true/>
    </dict></plist>
    PLIST
    codesign --force -s - "$APP" >/dev/null 2>&1
    echo "Built $APP"

    """

    static let appMd = """
    # {{NAME}}

    A macOS SwiftUI app built and live-edited with Forge.

    ## What it does
    Nothing yet: fresh scaffold.

    ## Structure
    - `Sources/App.swift`: entry point and window.
    - `Sources/ContentView.swift`: main UI.
    - `Sources/ForgeSupport.swift`: generated by Forge ("Edit with Forge" command and `ForgeAI`). Don't edit.
    - `build.sh`: builds `build/{{EXE}}.app`.

    """
}
