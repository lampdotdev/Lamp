import Foundation
import CryptoKit

/// Putting a change into a Mac app while it's open, without a restart.
/// While the experiment is on, a Mac app is built live (build.sh with LAMP_LIVE: debug, -interposable, from the
/// copy of its sources in `.lamp/live` with each view's body wrapped). After a change, the files it touched are
/// compiled into a library, and the running app loads it (`LampLive` in LampSupport.swift), keeping its state.
/// What can't go in that way (a stored property or an enum case added, removed or changed, but for a property added
/// to a class, which `LiveSlots` fits into a spare place; a file removed, the
/// App itself, Lamp's own file, the app's assets or settings) is installed as before, by reopening the app.
enum LiveReload {
    /// Whether the app is built live: a Mac app, or the Mac half of an app for both while Try On points at this Mac.
    @MainActor static func eligible(_ project: LampProject) -> Bool {
        project.platform.hasMac && !project.onIOS
    }

    static func folder(_ project: LampProject) -> URL { project.dir.appendingPathComponent(".lamp/live") }
    /// The sources the build last used, wrapped (build.sh writes them).
    static func sources(_ project: LampProject) -> URL { folder(project).appendingPathComponent("Sources") }
    /// The sources the open app is running: what was installed, and every change put into it since.
    static func running(_ project: LampProject) -> URL { folder(project).appendingPathComponent("running") }

    /// The sources the last whole build compiled (build.sh keeps them): the live copy may have changed since, when
    /// a change went in or was tried after it (`LiveSlots` rewrites the copy).
    static func built(_ project: LampProject) -> URL { folder(project).appendingPathComponent("built") }

    /// What the open app runs is now `from` (the live copy, after a change went in, or what the build compiled,
    /// after an install), with the other things the build puts in the app as they are.
    static func markRunning(_ project: LampProject, from: URL? = nil) {
        let fm = FileManager.default
        try? fm.removeItem(at: running(project))
        try? fm.copyItem(at: from ?? sources(project), to: running(project))
        try? inputs(project).write(to: runningInputs(project), atomically: true, encoding: .utf8)
        try? fm.removeItem(at: runningLayout(project))
    }

    private static func runningInputs(_ project: LampProject) -> URL { folder(project).appendingPathComponent("running-inputs.txt") }

    /// What else goes into the installed app besides the code, which a library can't bring: what it declares
    /// (capabilities.json), the package, the icon, and what's built beside the app (a widget or share extension,
    /// which run in processes of their own). A change to any of them is installed by reopening the app.
    /// Not its own files (Assets): a live build reads them from the app's folder (`LampAssets`), new ones included.
    static func inputs(_ project: LampProject) -> String {
        let fm = FileManager.default
        let files = ["Package.swift", Template.Capabilities.file, "icon.json"]
            + [Template.widgetFolder, Template.shareFolder].flatMap { folder in
                ((try? fm.subpathsOfDirectory(atPath: project.dir.appendingPathComponent(folder).path)) ?? []).sorted().map { "\(folder)/\($0)" }
            }
        return files.map { name in
            let data = fm.contents(atPath: project.dir.appendingPathComponent(name).path) ?? Data()
            return name + " " + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }.joined(separator: "\n")
    }

    static func forget(_ project: LampProject) {
        try? FileManager.default.removeItem(at: running(project))
        LiveSlots.clear(project)
    }

    /// The open app has a change the copy in the apps folder doesn't: the build goes in when the app closes.
    /// Not `Runtime.holdBuild`, which says the reverse (the open copy is the older one) and keeps the agent off it.
    /// Kept on disk, so the install still happens after Lamp itself has been quit and opened again.
    private static func pendingURL(_ project: LampProject) -> URL { folder(project).appendingPathComponent("install-pending") }
    static func awaitInstall(_ project: LampProject) {
        try? FileManager.default.createDirectory(at: folder(project), withIntermediateDirectories: true)
        try? Data().write(to: pendingURL(project))
    }
    static func installed(_ project: LampProject) { try? FileManager.default.removeItem(at: pendingURL(project)) }

    /// A whole build running after a change went in early (`Store.reloadBeforeBuilding`), kept on disk: if Lamp
    /// quits before it's done, nothing says the open app's change was ever built, so at the next launch what Lamp
    /// knows of the open app is dropped and the next change takes the usual build.
    private static func buildingURL(_ project: LampProject) -> URL { folder(project).appendingPathComponent("building") }
    static func startedBuilding(_ project: LampProject) {
        try? FileManager.default.createDirectory(at: folder(project), withIntermediateDirectories: true)
        try? Data().write(to: buildingURL(project))
    }
    static func finishedBuilding(_ project: LampProject) { try? FileManager.default.removeItem(at: buildingURL(project)) }
    /// At launch: a build that was still going when Lamp quit.
    static func recoverUnfinishedBuild(_ project: LampProject) {
        guard FileManager.default.fileExists(atPath: buildingURL(project).path) else { return }
        finishedBuilding(project)
        forget(project)
        Runtime.forgetBuilt(project)
    }
    static func awaitsInstall(_ project: LampProject) -> Bool { FileManager.default.fileExists(atPath: pendingURL(project).path) }

    /// What to do with a change: put the files it touched (relative to Sources) into the open app, reopen the
    /// app (with why, for the chat's details, so the rules can be tuned by what actually happens), or nothing.
    enum Verdict: Equatable {
        case reload([String])
        case reopen(String)
        case unchanged
    }

    @MainActor static func verdict(_ project: LampProject) async -> Verdict {
        let built = swiftFiles(in: sources(project)), open = swiftFiles(in: running(project))
        guard !open.isEmpty else { return .reopen("Lamp doesn't know what the open copy was built from") }
        // A new file only brings new types and functions, which the library holds; one taken away may have held
        // something the open app still uses.
        if let gone = Set(open.keys).subtracting(built.keys).sorted().first { return .reopen("\(gone) was removed") }
        if (try? String(contentsOf: runningInputs(project), encoding: .utf8)) != inputs(project) {
            return .reopen("the package, the app's settings, its icon, or its widget or Share item changed")
        }
        var changed: [String] = []
        for (path, url) in built.sorted(by: { $0.key < $1.key }) {
            guard let new = try? String(contentsOf: url, encoding: .utf8) else { return .reopen("\(path) couldn't be read") }
            guard let old = open[path].flatMap({ try? String(contentsOf: $0, encoding: .utf8) }) else {
                // Added: its types are new to the app, so their layout is whatever it says, but not the App.
                if declaresApp(new) { return .reopen("\(path) is the app's entry point") }
                changed.append(path)
                continue
            }
            guard new != old else { continue }
            if ["LampSupport.swift", Template.sceneSupportFile].contains((path as NSString).lastPathComponent) {
                return .reopen("Lamp's own building blocks changed")
            }
            if declaresApp(new) { return .reopen("\(path) is the app's entry point") }
            changed.append(path)
        }
        return changed.isEmpty ? .unchanged : .reload(changed)
    }

    /// Whether the whole new code type-checks and leaves every type the open app has holding what it did:
    /// nil when so, with the new code's layout to keep once it's gone in; else why not. The whole module, not
    /// just the changed files: a changed function can change what a property in another file is inferred to
    /// hold, and an unchanged caller can stop compiling, which compiling the changed files alone wouldn't show
    /// (then the usual build runs and the agent sees its errors). The open app's layout is kept from the last
    /// time, so only the new code is type-checked, alongside the changed files' compile.
    @MainActor static func layoutProblem(_ project: LampProject) async -> (problem: String?, layout: [String]?) {
        let (before, after) = await layouts(project)
        return layoutProblem(before: before, after: after)
    }

    static func layoutProblem(before: [String]?, after: [String]?) -> (problem: String?, layout: [String]?) {
        guard let now = after else { return ("the new code doesn't type-check as a whole", nil) }
        guard let before else { return ("the compiler couldn't say what the open app's types hold", nil) }
        // Type by type, each "Owner<tab>member": a type the open app has must hold just what it did, in order;
        // a new type (a new view with its own state) is the library's to lay out. A type taken away may still
        // have objects in the open app.
        func byType(_ entries: [String]) -> [String: [String]] {
            Dictionary(grouping: entries, by: { String($0.prefix { $0 != "\t" }) })
        }
        let old = byType(before), new = byType(now)
        for (type, members) in old.sorted(by: { $0.key < $1.key }) {
            guard let current = new[type] else { return ("\(type) was taken away", nil) }
            if current != members {
                let what = (current.first { !members.contains($0) } ?? members.first { !current.contains($0) }.map { "no longer " + $0 } ?? "the order of its fields")
                    .replacingOccurrences(of: "\t", with: ".")
                return ("\(type) changed what it holds (\(what))", nil)
            }
        }
        return (nil, now)
    }

    /// What the open app's types hold (kept from the last time, or worked out from the sources it runs) and what
    /// the new code's hold; nil for either the compiler can't say.
    @MainActor static func layouts(_ project: LampProject) async -> (before: [String]?, after: [String]?) {
        async let after = layout(of: sources(project), files: nil, module: project.exe, macOS: Template.macMinimum(project))
        var before = (try? String(contentsOf: runningLayout(project), encoding: .utf8)).map { $0.components(separatedBy: "\n").filter { !$0.isEmpty } }
        if before == nil {
            before = await layout(of: running(project), files: nil, module: project.exe, macOS: Template.macMinimum(project))
            if let before { try? before.joined(separator: "\n").write(to: runningLayout(project), atomically: true, encoding: .utf8) }
        }
        return (before, await after)
    }

    /// What the open app's types hold, kept beside the sources it runs: written when a change goes in (the new
    /// code's), gone when the app is installed (worked out again at the next change).
    private static func runningLayout(_ project: LampProject) -> URL { folder(project).appendingPathComponent("running-layout.txt") }

    static func keepLayout(_ layout: [String], for project: LampProject) {
        try? layout.joined(separator: "\n").write(to: runningLayout(project), atomically: true, encoding: .utf8)
    }

    /// A path for a shell command line, quoted.
    private static func quoted(_ path: String) -> String { "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// The compiler's command line for the live copy: the files named as primaries (what's compiled, or printed)
    /// and every other one there for context, the way the live build compiles a file (unoptimized, testable,
    /// the macOS the app is built for, named after the app, with SwiftUI's macros). `ios` reads code written for the
    /// iPhone instead, for the simulator, as it's built.
    private static func frontend(_ action: String, in folder: URL, primaries: [String], module: String, macOS: String,
                                 ios: Bool = false) -> String {
        let all = swiftFiles(in: folder)
        // The widget's code the app shares (Widget/Shared, linked into Sources and not followed there) is read for
        // context: a change to it reopens the app (`inputs`), but the app's code may use what it declares.
        let shared = swiftFiles(in: folder.deletingLastPathComponent()
            .appendingPathComponent(Template.widgetFolder).appendingPathComponent(Template.sharedWidgetFolder)).values.map(\.path)
        let others = (all.filter { !primaries.contains($0.key) }.values.map(\.path) + shared).sorted()
        let firsts = primaries.compactMap { all[$0]?.path }.map { "-primary-file " + quoted($0) }.joined(separator: " ")
        // On a Mac with only the Command Line Tools, the SDK the app's own build uses (`Shell.compatibleSDK`): the
        // newest one's `@State` is a macro whose plugin comes only with Xcode, and nothing would type-check.
        let sdk = ios ? #"SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)""#
            : Shell.compatibleSDK + #"SDK="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}""#
        return """
            \(sdk)
            PLUGINS="$(dirname "$(dirname "$(xcrun -f swiftc)")")/lib/swift/host/plugins"
            xcrun swiftc -frontend \(action) \(firsts) \(others.map(quoted).joined(separator: " ")) -module-name \(quoted(module)) \\
              -parse-as-library -Onone -enable-testing -D DEBUG -D LAMP_LIVE -target \(ios ? "arm64-apple-ios17.0-simulator" : "arm64-apple-macosx" + macOS) -sdk "$SDK" \\
              -plugin-path "$PLUGINS" -plugin-path "$SDK/../../usr/lib/swift/host/plugins"
            """
    }

    private static func swiftFiles(in folder: URL) -> [String: URL] {
        let base = folder.standardizedFileURL.path + "/"
        let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        return Dictionary(items.filter { $0.pathExtension == "swift" }.map { (String($0.standardizedFileURL.path.dropFirst(base.count)), $0) },
                          uniquingKeysWith: { first, _ in first })
    }

    /// What the open app's objects are laid out by, as the compiler sees it: for each struct, class, enum and
    /// actor in `files`, its stored properties with their types (inferred ones included) and its cases with what
    /// they carry, in order, from the type-checked syntax tree (`-dump-ast`). Comparing the open app's with the new
    /// code's says whether a library can go in: no reading of the text, which formatting, comments, strings and
    /// inferred types all fool. Nil when the compiler can't say (the code doesn't type-check). `rawValues` adds
    /// each case's raw value (`= "plant_name"`), which is what a coding key or a saved enum writes.
    static func layout(of folder: URL, files: [String]?, module: String, macOS: String, ios: Bool = false,
                       rawValues: Bool = false) async -> [String]? {
        if files?.isEmpty == true { return [] }
        // All of the app's own files, by name: the compiler prints (and checks the bodies of) only the files it's
        // given as primaries, or just the first with none. Lamp's building blocks are read for context only: the
        // app's code can't change what they hold or make them stop compiling, and they're most of the time.
        let primaries = files ?? swiftFiles(in: folder).keys.filter { ($0 as NSString).lastPathComponent != "LampSupport.swift" }.sorted()
        guard !primaries.isEmpty else { return [] }
        var output: [String] = []
        let status = await Shell.run(frontend("-dump-ast", in: folder, primaries: primaries, module: module, macOS: macOS, ios: ios) + " 2>/dev/null",
                                     cwd: folder) { output.append($0) }
        guard status == 0 else { return nil }
        return members(inDump: output.joined(separator: "\n"), rawValues: rawValues)
    }

    /// The stored members of every type in a `-dump-ast` printout: each line's indent says what it's inside, so
    /// a function's locals (inside a func or closure) never count, nor a static or a computed property.
    static func members(inDump dump: String, rawValues: Bool = false) -> [String] {
        let typeDecl = try! NSRegularExpression(pattern: #"^(\s*)\((struct|class|enum|actor)_decl\b[^"]*"([^"]+)""#)
        let scopeDecl = try! NSRegularExpression(pattern: #"^(\s*)\((func_decl|accessor_decl|constructor_decl|destructor_decl|closure_expr|subscript_decl|top_level_code_decl)\b"#)
        // A declaration's position (decl_context=…, range=[…]) comes before its name; neither holds a quote.
        let varDecl = try! NSRegularExpression(pattern: #"^(\s*)\(var_decl\b[^"]*"([^"]+)" interface_type="([^"]*)"(.*)$"#)
        let caseDecl = try! NSRegularExpression(pattern: #"^(\s*)\(enum_element_decl\b[^"]*"([^"]+)" interface_type="([^"]*)""#)
        // A case's raw value is the node right under it: a string's in quotes, a number's bare.
        let rawValue = try! NSRegularExpression(pattern: #"^\s*\(raw_value_expr=\w+\b.*? value=("(?:[^"\\]|\\.)*"|[^ )]+)"#)
        var scopes: [(indent: Int, type: String?)] = [], out: [String] = [], seen = Set<String>()
        var lastCase: Int?
        for raw in dump.split(separator: "\n") {
            let line = String(raw), range = NSRange(line.startIndex..., in: line)
            let indent = line.prefix { $0 == " " }.count
            // Only a line that opens a node says where it sits; the closing brackets of a deep node sometimes
            // come on a line of their own at the left edge, which would otherwise end every scope.
            guard line.dropFirst(indent).first == "(" else { continue }
            if rawValues, let index = lastCase, let m = rawValue.firstMatch(in: line, range: range) {
                out[index] += " = " + String(line[Range(m.range(at: 1), in: line)!])
                lastCase = nil
                continue
            }
            lastCase = nil
            while let last = scopes.last, last.indent >= indent { scopes.removeLast() }
            // What a member line belongs to is the nearest scope around it: a type's member when that's the type,
            // nothing when it's a function, an accessor or a closure (a local).
            let owner = scopes.last?.type
            if let m = typeDecl.firstMatch(in: line, range: range) {
                let name = String(line[Range(m.range(at: 3), in: line)!])
                let outer = scopes.compactMap(\.type).last
                let type = outer.map { $0 + "." + name } ?? name
                scopes.append((indent, type))
                // Every type is listed, members or not: an empty one the open app has is still its, and a first
                // field added to it changes what it holds.
                if seen.insert(type + "\t").inserted { out.append(type + "\t") }
            } else if let m = varDecl.firstMatch(in: line, range: range) {
                let rest = String(line[Range(m.range(at: 4), in: line)!])
                if let owner, rest.contains("readImpl=stored"), !rest.contains(" static") {
                    let entry = owner + "\t" + String(line[Range(m.range(at: 2), in: line)!]) + ": " + String(line[Range(m.range(at: 3), in: line)!])
                    if seen.insert(entry).inserted { out.append(entry) }
                }
            } else if let m = caseDecl.firstMatch(in: line, range: range), let owner {
                let entry = owner + "\tcase " + String(line[Range(m.range(at: 2), in: line)!]) + ": " + String(line[Range(m.range(at: 3), in: line)!])
                if seen.insert(entry).inserted {
                    out.append(entry)
                    lastCase = out.count - 1
                }
            } else if scopeDecl.firstMatch(in: line, range: range) != nil {
                scopes.append((indent, nil))
            }
        }
        return out
    }

    /// The App runs once, at launch: a change to it can't show in an app that's already open.
    private static func declaresApp(_ source: String) -> Bool {
        source.range(of: #"@main\b"#, options: .regularExpression) != nil || source.range(of: #":\s*(SwiftUI\.)?App\s*\{"#, options: .regularExpression) != nil
    }

    /// Compiles the whole module from the live copy, the way the live build does (SwiftPM's for a Mac app,
    /// Xcode's for the Mac half of an app for both: both unoptimized, testable, for the app's macOS, named after the app),
    /// and links the changed files' objects into a library for the open app. Nil, with the compiler's words, when it doesn't compile.
    static func compile(_ project: LampProject, changed: [String]) async -> (url: URL?, problem: String?) {
        let live = folder(project)
        let work = live.appendingPathComponent("hot")
        try? FileManager.default.removeItem(at: work)
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let library = live.appendingPathComponent("hot-\(UUID().uuidString.prefix(8)).dylib")
        // One object for each changed file, in the order they're named; only they are compiled.
        let objects = changed.indices.map { work.appendingPathComponent("\($0).o").path }
        let macOS = Template.macMinimum(project)
        let script = "set -e\n" + frontend("-c", in: sources(project), primaries: changed, module: project.exe, macOS: macOS)
            + " " + objects.map { "-o " + quoted($0) }.joined(separator: " ") + " 2>&1\n" + """
            xcrun swiftc -emit-library \(objects.map(quoted).joined(separator: " ")) -o \(quoted(library.path)) \\
              -target arm64-apple-macosx\(macOS) -sdk "$SDK" -Xlinker -undefined -Xlinker dynamic_lookup -Xlinker -interposable 2>&1
            codesign --force -s - \(quoted(library.path)) 2>&1
            """
        var output: [String] = []
        let status = await Shell.run(script, cwd: project.dir) { output.append($0) }
        guard status == 0 else { return (nil, output.suffix(30).joined(separator: "\n")) }
        return (library, nil)
    }

    /// Asks the open app to load the library, signed with its token (only Lamp has it), and waits a moment for
    /// its answer, which it leaves in its runtime folder.
    static func send(_ library: URL, to project: LampProject, token: String) async -> Bool {
        let answer = Runtime.macFolder(project).appendingPathComponent("reloaded.txt")
        try? FileManager.default.removeItem(at: answer)
        let key = SymmetricKey(data: Data(token.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data("reload\n\(library.path)".utf8), using: key)
            .map { String(format: "%02x", $0) }.joined()
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(Edition.notificationPrefix + "reload"), object: project.bundleID,
            userInfo: ["path": library.path, "signature": signature], deliverImmediately: true)
        for _ in 0..<50 {
            try? await Task.sleep(for: .milliseconds(100))
            if let text = try? String(contentsOf: answer, encoding: .utf8) { return text.hasPrefix("ok") }
        }
        return false
    }
}

/// A stored property added to a class while the app is open, put in without reopening it. A live build gives every
/// class of the app's `count` spare places (`__lampSpare0`…, of `LampSpare?`, written by build.sh's copy step), so
/// the open app's objects already have room. When the only thing keeping a change out is new stored properties in
/// such classes, each one's declaration in the live copy becomes a computed property kept in a free spare place:
/// the class then holds what it did, and the change goes in like any other. Being stored, a spare place is observed
/// like the rest (`@Observable`'s tracking, `@Published` in an `ObservableObject`), so a view that reads the new
/// property is redrawn when it changes. Which property is in which place is kept until the app is next installed,
/// and put back into every live copy made meanwhile (`apply`), so later changes see the same layout.
enum LiveSlots {
    static let count = 4

    struct Slot: Codable, Equatable {
        var index: Int
        /// The property's type as the compiler worked it out, for a declaration that doesn't spell it.
        var type: String
    }

    private static func url(_ project: LampProject) -> URL { LiveReload.folder(project).appendingPathComponent("slots.json") }

    /// Type ("Outer.Inner") → property → its place.
    static func mapping(_ project: LampProject) -> [String: [String: Slot]] {
        (try? JSONDecoder().decode([String: [String: Slot]].self, from: Data(contentsOf: url(project)))) ?? [:]
    }

    private static func save(_ mapping: [String: [String: Slot]], for project: LampProject) {
        try? JSONEncoder().encode(mapping).write(to: url(project), options: .atomic)
    }

    /// The app was installed: its objects are the new build's, with every property stored, and its places empty.
    static func clear(_ project: LampProject) { try? FileManager.default.removeItem(at: url(project)) }

    /// Puts the properties already in places back into a fresh live copy, before it's compared with the open app.
    static func apply(_ project: LampProject) {
        for (type, properties) in mapping(project) {
            for (name, slot) in properties { _ = rewrite(name, as: slot, in: type, project: project) }
        }
    }

    /// When every way the new code's types differ from the open app's is a stored property added to a class that
    /// has places to spare, moves each into a place and answers what it moved ("Game.onFoot"); else nothing
    /// changes and it answers nil.
    static func fit(_ project: LampProject, before: [String], after: [String]) -> [String]? {
        func byType(_ entries: [String]) -> [String: [String]] {
            Dictionary(grouping: entries, by: { String($0.prefix { $0 != "\t" }) })
        }
        let old = byType(before), new = byType(after)
        var map = mapping(project)
        var planned: [(type: String, name: String, slot: Slot)] = []
        for (type, members) in old.sorted(by: { $0.key < $1.key }) {
            guard let current = new[type] else { return nil }
            guard current != members else { continue }
            // Only additions, with what was there still there, in order.
            let extras = current.filter { !members.contains($0) }
            guard current.filter({ members.contains($0) }) == members, !extras.isEmpty else { return nil }
            // The places as the class keeps them: plain, behind @Observable's `_`, or in @Published's wrapper.
            let observed = members.contains(type + "\t___lampSpare0: LampSpare?")
            guard observed || members.contains(type + "\t__lampSpare0: LampSpare?")
                    || members.contains(type + "\t___lampSpare0: Published<LampSpare?>") else { return nil }
            var taken = Set((map[type] ?? [:]).values.map(\.index))
            for extra in extras {
                let field = extra.dropFirst(type.count + 1)
                guard !field.hasPrefix("case "), let colon = field.range(of: ": ") else { return nil }
                var name = String(field[..<colon.lowerBound]), kind = String(field[colon.upperBound...])
                // @Observable keeps a property in `_name`, @Published in `_name: Published<T>`.
                if observed, name.hasPrefix("_") { name.removeFirst() }
                if kind.hasPrefix("Published<"), kind.hasSuffix(">"), name.hasPrefix("_") {
                    name.removeFirst()
                    kind = String(kind.dropFirst("Published<".count).dropLast())
                }
                guard map[type]?[name] == nil, let free = (0..<count).first(where: { !taken.contains($0) }) else { return nil }
                taken.insert(free)
                planned.append((type, name, Slot(index: free, type: kind)))
            }
        }
        // Every type the open app doesn't have is the library's to lay out; one it has that changed must be fitted.
        guard !planned.isEmpty else { return nil }
        var originals: [URL: Data] = [:]
        for item in planned {
            guard rewrite(item.name, as: item.slot, in: item.type, project: project, keeping: &originals) != nil else {
                // Put back what was already rewritten: the change goes in by reopening, from the copy as it was.
                for (url, data) in originals { try? data.write(to: url) }
                return nil
            }
            map[item.type, default: [:]][item.name] = item.slot
        }
        save(map, for: project)
        return planned.map { $0.type + "." + $0.name }
    }

    @discardableResult
    private static func rewrite(_ name: String, as slot: Slot, in type: String, project: LampProject) -> URL? {
        var unused: [URL: Data] = [:]
        return rewrite(name, as: slot, in: type, project: project, keeping: &unused)
    }

    /// Turns `var name = value` in the class `type` of the live copy into a computed property kept in the place.
    /// Only a one-line declaration with nothing but access words, `@Published` or `@ObservationIgnored` before it,
    /// and a type or a starting value (an optional may have neither): anything else (a `didSet`, `lazy`, `weak`,
    /// another wrapper) isn't moved, and the change goes in by reopening. Answers the file changed.
    private static func rewrite(_ name: String, as slot: Slot, in type: String, project: LampProject,
                                keeping originals: inout [URL: Data]) -> URL? {
        let simple = String(type.split(separator: ".").last ?? Substring(type))
        let files = (FileManager.default.enumerator(at: LiveReload.sources(project), includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL } ?? []).filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path }
        let header = try! NSRegularExpression(
            pattern: #"^([ \t]*)(?:@[\w.]+(?:\([^)\n]*\))?\s+)*(?:(?:public|private|fileprivate|internal|open|final|nonisolated)\s+)*class\s+"#
                + NSRegularExpression.escapedPattern(for: simple) + #"\b[^{\n]*\{"#, options: .anchorsMatchLines)
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let declaration = try! NSRegularExpression(
            pattern: #"^([ \t]*)((?:@(?:Published|ObservationIgnored)[ \t]+)*)((?:(?:public|private|fileprivate|internal|nonisolated)(?:\(set\))?[ \t]+)*)(var|let)[ \t]+"#
                + escaped + #"[ \t]*(?::[ \t]*([^={}\n]+?))?[ \t]*(?:=[ \t]*([^{}\n]+?))?[ \t]*(?://[^\n]*)?$"#, options: .anchorsMatchLines)
        for file in files where !["LampSupport.swift", Template.sceneSupportFile].contains(file.lastPathComponent) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let ns = text as NSString
            for found in header.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                // The class's body: from its header to the first line that closes at the header's indent or less.
                let indent = ns.substring(with: found.range(at: 1)).count
                let start = found.range.location + found.range.length
                var end = ns.length
                let closing = try! NSRegularExpression(pattern: #"^[ \t]{0,\#(indent)}\}"#, options: .anchorsMatchLines)
                if let close = closing.firstMatch(in: text, range: NSRange(location: start, length: ns.length - start)) { end = close.range.location }
                let body = NSRange(location: start, length: end - start)
                guard let m = declaration.firstMatch(in: text, range: body) else { continue }
                func group(_ i: Int) -> String? {
                    m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)).trimmingCharacters(in: .whitespaces)
                }
                let lead = ns.substring(with: m.range(at: 1)), access = group(3) ?? "", isLet = group(4) == "let"
                let declared = group(5) ?? slot.type
                guard !declared.isEmpty else { return nil }
                let optional = declared.hasSuffix("?") || declared.hasPrefix("Optional<")
                guard let start = group(6) ?? (optional ? "nil" : nil) else { return nil }
                let place = "__lampSpare\(slot.index)"
                // A starting value that's worked out (a call, an object) is kept the first time it's read, so every
                // read after sees the same one; a plain value is just answered until something is set.
                let made = start.contains("(") || start.contains("{")
                let first = made ? "let v: \(declared) = \(start); \(place) = LampSpare(v); return v" : "return \(start)"
                let getter = "get { if let v = \(place)?.value as? \(declared) { return v }; \(first) }"
                let setter = isLet ? "" : " set { \(place) = LampSpare(newValue) }"
                let line = "\(lead)\(access.isEmpty ? "" : access + " ")var \(name): \(declared) { \(getter)\(setter) }"
                if originals[file] == nil { originals[file] = Data(text.utf8) }
                try? ns.replacingCharacters(in: m.range, with: line).write(to: file, atomically: true, encoding: .utf8)
                return file
            }
        }
        return nil
    }
}
