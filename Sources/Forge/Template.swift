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
    import Carbon.HIToolbox
    import CoreServices
    import PDFKit
    import ServiceManagement
    import UniformTypeIdentifiers
    import UserNotifications
    @preconcurrency import Vision

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

    /// Brings the app back with a window when there isn't one: clicking it in the Dock, opening it again from
    /// Finder or Launchpad, and Forge's Play button. SwiftUI doesn't open a new window for macOS's "reopen"
    /// request on its own, so this answers that request itself; Forge also sends its own message.
    enum ForgeWindows {
        static let start: Void = {
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("dev.forge.showWindow"), object: Bundle.main.bundleIdentifier, queue: .main
            ) { _ in
                MainActor.assumeIsolated { show() }
            }
            // AppKit installs its own handler while launching, so take over once launching is done.
            MainActor.assumeIsolated { ReopenHandler.shared.install() }
            NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification,
                                                   object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { ReopenHandler.shared.install() }
            }
        }()

        @MainActor private final class ReopenHandler: NSObject {
            static let shared = ReopenHandler()

            func install() {
                NSAppleEventManager.shared().setEventHandler(
                    self, andSelector: #selector(reopen(_:reply:)),
                    forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEReopenApplication))
            }

            @objc func reopen(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
                ForgeWindows.show()
            }
        }

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
            // ...and clicks, types and presses keys in it when the builder wants to try something (ForgeDriver).
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("dev.forge.use.{{SLUG}}"), object: nil, queue: .main) { note in
                let actions = note.userInfo?["actions"] as? String, token = note.userInfo?["token"] as? String
                MainActor.assumeIsolated { ForgeDriver.perform(actions, token: token) }
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
            let windows = windowsOnScreen
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

        /// Open windows, frontmost first.
        @MainActor
        static var windowsOnScreen: [NSWindow] {
            NSApp.orderedWindows.filter { $0.isVisible && !$0.isMiniaturized && $0.frame.width > 40 && $0.frame.height > 40 }
        }

        /// Picture pixels per window point: at most 1400 pixels on the long side, a size models see unscaled.
        @MainActor
        static func scale(of window: NSWindow) -> CGFloat {
            let size = (window.contentView?.superview ?? window.contentView)?.bounds.size ?? window.frame.size
            return min(window.backingScaleFactor, 1400 / max(size.width, size.height))
        }

        /// The window with its title bar, at most 1400 pixels on the long side.
        @MainActor
        private static func picture(of window: NSWindow) -> Data? {
            guard let view = window.contentView?.superview ?? window.contentView else { return nil }
            let size = view.bounds.size
            let scale = scale(of: window)
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

    /// Lets Forge's builder use the app the way a person would: it clicks, types and presses keys in the front
    /// window, from inside the app, so no Accessibility permission is needed. Points are pixels in the latest
    /// picture of that window (ForgeRuntime.snapshot), so the builder aims at what it saw. What happened goes to
    /// .forge/runtime/use.txt, then a fresh picture is taken.
    @MainActor
    enum ForgeDriver {
        struct Action: Decodable {
            let action: String          // click, double_click, type, key, scroll, wait
            var x: Double?
            var y: Double?
            var text: String?
            var key: String?            // "return", "escape", "cmd+a", "down"…
            var amount: Double?         // scroll: points, positive is down; wait: seconds
        }

        static func perform(_ json: String?, token: String?) {
            guard token == "{{TOKEN}}", let data = json?.data(using: .utf8),
                  let actions = try? JSONDecoder().decode([Action].self, from: data) else { return }
            var report: [String] = []
            func step(_ index: Int) {
                guard index < actions.count else {
                    // Let the app react, then show the result.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        try? report.joined(separator: "\n").write(to: ForgeRuntime.folder.appendingPathComponent("use.txt"),
                                                                    atomically: true, encoding: .utf8)
                        ForgeRuntime.snapshot()
                    }
                    return
                }
                let action = actions[index]
                report.append(run(action))
                let pause = action.action == "wait" ? min(action.amount ?? 1, 10) : 0.35
                DispatchQueue.main.asyncAfter(deadline: .now() + pause) { step(index + 1) }
            }
            step(0)
        }

        private static func run(_ action: Action) -> String {
            guard let window = ForgeRuntime.windowsOnScreen.first, let frame = window.contentView?.superview else {
                return "\(action.action): the app has no window open"
            }
            switch action.action {
            case "click", "double_click":
                guard let x = action.x, let y = action.y else { return "\(action.action): needs x and y" }
                // Pictures run top-down in pixels; windows run bottom-up in points.
                let scale = ForgeRuntime.scale(of: window)
                let point = NSPoint(x: x / scale, y: frame.bounds.height - y / scale)
                return "\(action.action) at \(Int(x)), \(Int(y)): " + click(at: point, in: window, count: action.action == "click" ? 1 : 2)
            case "type":
                let text = action.text ?? ""
                for character in text { send(String(character), code: 0, flags: [], to: window) }
                return "typed \"\(text)\""
            case "key":
                let name = action.key ?? ""
                guard let (characters, code, flags) = key(name) else { return "key \(name): not a key I know" }
                send(characters, code: code, flags: flags, to: window)
                return "pressed \(name)"
            case "scroll":
                let scale = ForgeRuntime.scale(of: window)
                let point = NSPoint(x: (action.x ?? 0) / scale, y: frame.bounds.height - (action.y ?? 0) / scale)
                guard let view = frame.hitTest(point), let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                                                         wheel1: Int32(-(action.amount ?? 200)), wheel2: 0, wheel3: 0),
                      let event = NSEvent(cgEvent: cg) else { return "scroll: nothing to scroll there" }
                (view.enclosingScrollView ?? view).scrollWheel(with: event)
                return "scrolled \(Int(action.amount ?? 200)) points"
            case "wait":
                return "waited \(action.amount ?? 1) s"
            default:
                return "\(action.action): not an action I know"
            }
        }

        private static func click(at point: NSPoint, in window: NSWindow, count: Int) -> String {
            guard let frame = window.contentView?.superview, let view = frame.hitTest(point) else { return "nothing there" }
            let swiftUI = String(describing: type(of: view)).contains("HostingView")
            for n in 1...count {
                func event(_ type: NSEvent.EventType) -> NSEvent? {
                    NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: n,
                                       pressure: type == .leftMouseDown ? 1 : 0)
                }
                guard let down = event(.leftMouseDown), let up = event(.leftMouseUp) else { return "couldn't click" }
                // Straight to the view: through the window, a click on an inactive window would only activate it.
                if swiftUI {
                    // SwiftUI's own views (plain buttons, toggles, tap gestures) take the mouse-up directly.
                    view.mouseDown(with: down)
                    view.mouseUp(with: up)
                } else {
                    // AppKit controls (buttons, fields, tables and their headers) track the mouse and read the
                    // mouse-up from the event queue.
                    NSApp.postEvent(up, atStart: false)
                    view.mouseDown(with: down)
                }
            }
            return describe(view, at: point)
        }

        /// A short name for what was clicked, when AppKit can say.
        private static func describe(_ view: NSView, at point: NSPoint) -> String {
            switch view {
            case let button as NSButton: return button.title.isEmpty ? "a button" : "the \"\(button.title)\" button"
            case is NSTextField, is NSTextView: return "a text field"
            case is NSTableHeaderView: return "a column header"
            case let table as NSTableView:
                let row = table.row(at: table.convert(point, from: nil))
                return row >= 0 ? "row \(row + 1) of a list" : "a list"
            default: return "the app's content"
            }
        }

        private static func send(_ characters: String, code: UInt16, flags: NSEvent.ModifierFlags, to window: NSWindow) {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
                                                   timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                   context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                                   isARepeat: false, keyCode: code) else { continue }
                window.sendEvent(event)
            }
        }

        /// "cmd+shift+z" → characters, key code and modifier flags.
        private static func key(_ name: String) -> (String, UInt16, NSEvent.ModifierFlags)? {
            var parts = name.lowercased().split(separator: "+").map(String.init)
            guard let last = parts.popLast() else { return nil }
            var flags: NSEvent.ModifierFlags = []
            for part in parts {
                switch part {
                case "cmd", "command": flags.insert(.command)
                case "shift": flags.insert(.shift)
                case "option", "alt": flags.insert(.option)
                case "ctrl", "control": flags.insert(.control)
                default: return nil
                }
            }
            func scalar(_ value: Int) -> String { String(UnicodeScalar(UInt32(value))!) }
            let keys: [String: (String, UInt16)] = [
                "return": ("\r", 36), "enter": ("\r", 36), "tab": ("\t", 48), "space": (" ", 49), "delete": (scalar(127), 51),
                "escape": (scalar(27), 53), "left": (scalar(NSLeftArrowFunctionKey), 123), "right": (scalar(NSRightArrowFunctionKey), 124),
                "down": (scalar(NSDownArrowFunctionKey), 125), "up": (scalar(NSUpArrowFunctionKey), 126),
            ]
            if let (characters, code) = keys[last] { return (characters, code, flags) }
            return last.count == 1 ? (last, 0, flags) : nil
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

    // MARK: - Mac building blocks

    /// Tells you when files in a folder (and its subfolders) are added, changed, renamed or removed.
    /// Keep the watcher alive (e.g. in a @State or a model object); it stops when released.
    ///
    ///     @State private var watcher: ForgeFolderWatcher?
    ///     watcher = ForgeFolderWatcher(ForgeFolders.downloads) { changed in reload(changed) }
    final class ForgeFolderWatcher {
        private var stream: FSEventStreamRef?
        private let handler: ([URL]) -> Void

        /// `handler` runs on the main thread with the changed files, batched over `latency` seconds.
        init(_ folder: URL, latency: TimeInterval = 0.5, handler: @escaping ([URL]) -> Void) {
            self.handler = handler
            var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                               retain: nil, release: nil, copyDescription: nil)
            let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<ForgeFolderWatcher>.fromOpaque(info).takeUnretainedValue()
                let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
                let urls = Array(Set(list.prefix(count))).sorted().map { URL(fileURLWithPath: $0) }
                watcher.handler(urls)
            }
            let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
                               | kFSEventStreamCreateFlagNoDefer)
            stream = FSEventStreamCreate(nil, callback, &context, [folder.path] as CFArray,
                                         FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags)
            if let stream {
                FSEventStreamSetDispatchQueue(stream, .main)
                FSEventStreamStart(stream)
            }
        }

        deinit {
            guard let stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    /// The user's usual folders.
    enum ForgeFolders {
        static var home: URL { URL(fileURLWithPath: NSHomeDirectory()) }
        static var downloads: URL { FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0] }
        static var desktop: URL { FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0] }
        static var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

        /// Where screenshots are saved (the Desktop unless the user changed it in the Screenshot app).
        static var screenshots: URL {
            if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
                return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            }
            return desktop
        }

        /// Files directly in a folder, newest first, skipping hidden ones.
        static func files(in folder: URL) -> [URL] {
            let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
            let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                       options: [.skipsHiddenFiles])) ?? []
            func date(_ url: URL) -> Date { (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast }
            return items.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
                .sorted { date($0) > date($1) }
        }
    }

    /// A keyboard shortcut that works from any app, with no permission needed. Keep the returned value alive.
    ///
    ///     @State private var hotKey = ForgeHotKey("cmd+shift+space") { ForgeWindows.show() }
    ///
    /// Keys: a–z, 0–9, space, return, tab, escape, delete, up, down, left, right, f1–f12, and - = [ ] ; ' , . / `
    /// Modifiers: cmd, shift, option (or alt), control (or ctrl). Returns nil if the key isn't recognised
    /// or another app already uses the shortcut.
    final class ForgeHotKey {
        private var ref: EventHotKeyRef?
        private let id: UInt32
        private let action: () -> Void

        nonisolated(unsafe) private static var actions: [UInt32: () -> Void] = [:]
        nonisolated(unsafe) private static var nextID: UInt32 = 1
        nonisolated(unsafe) private static var handlerInstalled = false

        init?(_ shortcut: String, action: @escaping () -> Void) {
            var modifiers: UInt32 = 0
            var key: UInt32?
            for part in shortcut.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                switch part {
                case "cmd", "command", "⌘": modifiers |= UInt32(cmdKey)
                case "shift", "⇧": modifiers |= UInt32(shiftKey)
                case "option", "opt", "alt", "⌥": modifiers |= UInt32(optionKey)
                case "control", "ctrl", "⌃": modifiers |= UInt32(controlKey)
                default: key = Self.keyCodes[part]
                }
            }
            guard let key else { print("ForgeHotKey: unknown key in \"\(shortcut)\""); return nil }
            self.action = action
            self.id = Self.nextID
            Self.nextID += 1
            Self.installHandler()
            let hotKeyID = EventHotKeyID(signature: OSType(0x46524745), id: id)   // "FRGE"
            guard RegisterEventHotKey(key, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr else {
                print("ForgeHotKey: \"\(shortcut)\" is already in use")
                return nil
            }
            Self.actions[id] = action
        }

        deinit {
            if let ref { UnregisterEventHotKey(ref) }
            Self.actions[id] = nil
        }

        private static func installHandler() {
            guard !handlerInstalled else { return }
            handlerInstalled = true
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                let id = hotKeyID.id
                DispatchQueue.main.async { ForgeHotKey.actions[id]?() }
                return noErr
            }, 1, &spec, nil, nil)
        }

        private static let keyCodes: [String: UInt32] = {
            var codes: [String: UInt32] = [
                "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
                "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
                "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34,
                "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46,
                ".": 47, "`": 50, "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53, "esc": 53,
                "left": 123, "right": 124, "down": 125, "up": 126,
            ]
            let fKeys: [UInt32] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
            for (index, code) in fKeys.enumerated() { codes["f\(index + 1)"] = code }
            return codes
        }()
    }

    /// Opening the app when the user logs in. Show it as a toggle in Settings, not something turned on silently.
    ///
    ///     Toggle("Open at Login", isOn: Binding(get: { ForgeLoginItem.isEnabled }, set: { ForgeLoginItem.isEnabled = $0 }))
    enum ForgeLoginItem {
        static var isEnabled: Bool {
            get { SMAppService.mainApp.status == .enabled }
            set {
                do {
                    if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    print("ForgeLoginItem: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Text from files and pictures, read on this Mac (no AI call, free and private): PDFs (with recognition for
    /// scanned pages), images and screenshots (Apple's Live Text), and plain-text, RTF, Word and HTML documents.
    ///
    ///     let text = await ForgeText.read(url)               // any supported file; "" if there's no text
    ///     let lines = await ForgeText.recognize(in: image)   // NSImage → lines of text, top to bottom
    enum ForgeText {
        static func read(_ url: URL) async -> String {
            let type = UTType(filenameExtension: url.pathExtension) ?? .data
            if type.conforms(to: .pdf) { return await readPDF(url) }
            if type.conforms(to: .image), let image = NSImage(contentsOf: url) {
                return await recognize(in: image).joined(separator: "\n")
            }
            if type.conforms(to: .plainText) || type.conforms(to: .sourceCode) || type.conforms(to: .json) {
                return (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) ?? ""
            }
            // RTF, Word (.doc, .docx), HTML, OpenDocument: AppKit's document readers.
            if let text = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) { return text.string }
            return ""
        }

        /// Each page's text; pages with no text layer (scans) are recognised from their image.
        static func readPDF(_ url: URL) async -> String {
            guard let document = PDFDocument(url: url) else { return "" }
            var pages: [String] = []
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if text.count > 20 {
                    pages.append(text)
                } else {
                    let bounds = page.bounds(for: .mediaBox)
                    let scale = 2000 / max(bounds.width, bounds.height, 1)
                    let image = page.thumbnail(of: NSSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
                    pages.append(await recognize(in: image).joined(separator: "\n"))
                }
            }
            return pages.joined(separator: "\n\n")
        }

        /// Lines of text in a picture, top to bottom.
        static func recognize(in image: NSImage) async -> [String] {
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
            return await withCheckedContinuation { continuation in
                let request = VNRecognizeTextRequest { request, _ in
                    let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                        .compactMap { $0.topCandidates(1).first?.string }
                    continuation.resume(returning: lines)
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = true
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try VNImageRequestHandler(cgImage: cgImage).perform([request])
                    } catch {
                        continuation.resume(returning: [])
                    }
                }
            }
        }
    }

    /// Accepts files dragged onto a view: Finder files and folders, images from other apps (saved to temporary
    /// files), and URLs. Highlights while something is over it.
    ///
    ///     List(items) { ... }
    ///         .forgeDropFiles { urls in add(urls) }
    ///     ForgeDropZone("Drop screenshots here") { urls in add(urls) }   // an empty-state drop target
    extension View {
        func forgeDropFiles(_ handler: @escaping ([URL]) -> Void) -> some View {
            modifier(ForgeDropModifier(handler: handler))
        }
    }

    struct ForgeDropModifier: ViewModifier {
        let handler: ([URL]) -> Void
        @State private var targeted = false

        func body(content: Content) -> some View {
            content
                .overlay {
                    if targeted {
                        RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 3)
                            .background(Color.accentColor.opacity(0.08)).allowsHitTesting(false)
                    }
                }
                .onDrop(of: [.fileURL, .image, .url], isTargeted: $targeted) { providers in
                    ForgeDrop.load(providers) { urls in if !urls.isEmpty { handler(urls) } }
                    return true
                }
        }
    }

    struct ForgeDropZone: View {
        let title: String
        let handler: ([URL]) -> Void

        init(_ title: String = "Drop files here", handler: @escaping ([URL]) -> Void) {
            self.title = title
            self.handler = handler
        }

        var body: some View {
            VStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down").font(.system(size: 34)).foregroundStyle(.secondary)
                Text(title).font(.title3).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(30)
            .background(RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundStyle(.tertiary))
            .padding()
            .forgeDropFiles(handler)
        }
    }

    enum ForgeDrop {
        /// Resolves dropped items to file URLs (images without a file become temporary PNGs), in drop order.
        static func load(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
            var results = [URL?](repeating: nil, count: providers.count)
            let group = DispatchGroup()
            for (index, provider) in providers.enumerated() {
                group.enter()
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in results[index] = url; group.leave() }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                        if let data, let image = NSImage(data: data), let tiff = image.tiffRepresentation,
                           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Dropped \(UUID().uuidString.prefix(8)).png")
                            if (try? png.write(to: url)) != nil { results[index] = url }
                        }
                        group.leave()
                    }
                } else if provider.canLoadObject(ofClass: URL.self) {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in results[index] = url; group.leave() }
                } else {
                    group.leave()
                }
            }
            group.notify(queue: .main) { completion(results.compactMap { $0 }) }
        }
    }

    /// Tells you when something new is copied, from any app. Keep the watcher alive.
    ///
    ///     @State private var clipboard = ForgeClipboardWatcher { item in if let text = item.text { history.insert(text, at: 0) } }
    final class ForgeClipboardWatcher {
        struct Item {
            let text: String?
            let image: NSImage?
            let fileURLs: [URL]
        }

        private var timer: Timer?
        private var lastChange = NSPasteboard.general.changeCount

        /// `handler` runs on the main thread. Copies made by this app itself are included.
        init(handler: @escaping (Item) -> Void) {
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                let board = NSPasteboard.general
                guard let self, board.changeCount != self.lastChange else { return }
                self.lastChange = board.changeCount
                let files = (board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
                handler(Item(text: board.string(forType: .string),
                             image: files.isEmpty ? NSImage(pasteboard: board) : nil,
                             fileURLs: files))
            }
        }

        deinit { timer?.invalidate() }

        /// Puts text on the clipboard.
        static func copy(_ text: String) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    /// Mac notifications. Asks permission the first time.
    ///
    ///     ForgeNotifications.send("Export finished", body: "Saved 12 files to Documents")
    enum ForgeNotifications {
        /// Shows notifications even while this app is in front (macOS hides them otherwise).
        private final class Presenter: NSObject, UNUserNotificationCenterDelegate {
            func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                        withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
                completion([.banner, .sound, .list])
            }
        }
        private static let presenter = Presenter()

        static func send(_ title: String, body: String = "", sound: Bool = true) {
            let center = UNUserNotificationCenter.current()
            if center.delegate == nil { center.delegate = presenter }
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                guard granted else {
                    print("ForgeNotifications: not allowed\(error.map { " (\($0.localizedDescription))" } ?? "")")
                    return
                }
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                if sound { content.sound = .default }
                center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            }
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
