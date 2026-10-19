import Foundation
import CryptoKit

/// Putting a change into a Mac app while it's open, without a restart.
/// While the experiment is on, a Mac app is built live (build.sh with LAMP_LIVE: debug, -interposable, from the
/// copy of its sources in `.lamp/live` with each view's body wrapped). After a change, the files it touched are
/// compiled into a library, and the running app loads it (`LampLive` in LampSupport.swift), keeping its state.
/// What can't go in that way (a stored property or an enum case removed or changed, or added where `LiveSlots`
/// has no spare for it; the App itself, Lamp's own file, the package or the app's settings) is installed as
/// before, by reopening the app.
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
    /// All of it is in the agent's folder, where a build may have left a link, so it's copied and written there
    /// without following one (`AppFolder`).
    static func markRunning(_ project: LampProject, from: URL? = nil) {
        try? AppFolder.copy(from ?? sources(project), to: running(project), in: project.dir)
        try? AppFolder.write(inputs(project), to: runningInputs(project), in: project.dir)
        AppFolder.remove(runningLayout(project), in: project.dir)
        // Installed, the app runs one generation of code again: nothing older is left running in it.
        if from != nil { AppFolder.remove(oldCodeURL(project), in: project.dir) }
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
        AppFolder.remove(running(project), in: project.dir)
        AppFolder.remove(oldCodeURL(project), in: project.dir)
        LiveSlots.clear(project)
    }

    /// Where the open app's code may still be running old versions of itself, from every change that went in since
    /// it opened (`oldCodeUses`), kept beside the sources it runs: the sources of one change are replaced by the
    /// next's, but a timer or a task started by an earlier change's code goes on running it.
    private static func oldCodeURL(_ project: LampProject) -> URL { folder(project).appendingPathComponent("old-code.txt") }
    static func recordOldCode(_ uses: [String], for project: LampProject) {
        let known = oldCodeRecorded(project)
        let all = known + uses.filter { !known.contains($0) }
        // Written even when there's nothing: the record's being there says the installed generation's is in it.
        if all.count != known.count || !hasOldCodeRecord(project) {
            try? AppFolder.write(all.joined(separator: "\n"), to: oldCodeURL(project), in: project.dir)
        }
    }
    static func oldCodeRecorded(_ project: LampProject) -> [String] {
        AppFile.text(oldCodeURL(project), in: project)?.components(separatedBy: "\n").filter { !$0.isEmpty } ?? []
    }
    /// Whether anything has been recorded since the app was installed: before the first change, the installed
    /// generation's uses are read off the sources it runs, before those are replaced.
    static func hasOldCodeRecord(_ project: LampProject) -> Bool { FileManager.default.fileExists(atPath: oldCodeURL(project).path) }
    /// The uses in the sources the open app runs, for the record; nil when the compiler can't say.
    @MainActor static func oldCodeUsesOfRunning(_ project: LampProject) async -> [String]? {
        await dump(of: running(project), in: project, module: project.exe, macOS: Template.macMinimum(project)).map(oldCodeUses(inDump:))
    }

    /// The open app has a change the copy in the apps folder doesn't: the build goes in when the app closes.
    /// Not `Runtime.holdBuild`, which says the reverse (the open copy is the older one) and keeps the agent off it.
    /// Kept on disk, so the install still happens after Lamp itself has been quit and opened again.
    private static func pendingURL(_ project: LampProject) -> URL { folder(project).appendingPathComponent("install-pending") }
    static func awaitInstall(_ project: LampProject) { try? AppFolder.write(Data(), to: pendingURL(project), in: project.dir) }
    static func installed(_ project: LampProject) { AppFolder.remove(pendingURL(project), in: project.dir) }

    /// A whole build running after a change went in early (`Store.reloadBeforeBuilding`), kept on disk: if Lamp
    /// quits before it's done, nothing says the open app's change was ever built, so at the next launch what Lamp
    /// knows of the open app is dropped and the next change takes the usual build.
    private static func buildingURL(_ project: LampProject) -> URL { folder(project).appendingPathComponent("building") }
    static func startedBuilding(_ project: LampProject) { try? AppFolder.write(Data(), to: buildingURL(project), in: project.dir) }
    static func finishedBuilding(_ project: LampProject) { AppFolder.remove(buildingURL(project), in: project.dir) }
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
        // A new file only brings new types and functions, which the library holds. One taken away leaves its code
        // in the open app, which the new code no longer calls; what it declared that something still holds shows
        // as that holder changing (`layoutProblem`). But not the App, which runs once at launch, nor Lamp's own.
        let gone = Set(open.keys).subtracting(built.keys).sorted()
        for path in gone where ["LampSupport.swift", Template.sceneSupportFile].contains((path as NSString).lastPathComponent) {
            return .reopen("Lamp's own building blocks changed")
        }
        if (try? String(contentsOf: runningInputs(project), encoding: .utf8)) != inputs(project) {
            return .reopen("the package, the app's settings, its icon, or its widget or Share item changed")
        }
        var changed: [String] = []
        for (path, url) in built.sorted(by: { $0.key < $1.key }) {
            guard let new = try? String(contentsOf: url, encoding: .utf8) else { return .reopen("\(path) couldn't be read") }
            guard let old = open[path].flatMap({ try? String(contentsOf: $0, encoding: .utf8) }) else {
                // Added: its types are new to the app, so their layout is whatever it says.
                changed.append(path)
                continue
            }
            guard new != old else { continue }
            if ["LampSupport.swift", Template.sceneSupportFile].contains((path as NSString).lastPathComponent) {
                return .reopen("Lamp's own building blocks changed")
            }
            // What's read only at launch (the App, its scenes, its menu commands, an application delegate) is held to
            // what the open app had by the layout check (`SwiftSource.launchEntries`), wherever it's written.
            changed.append(path)
        }
        // A file taken away while another arrives is most often one renamed: what was private to it (a type, a
        // static, a global) is named after its file, so the new code would make all of it again, starting over.
        if let went = gone.first, let came = built.keys.filter({ open[$0] == nil }).sorted().first {
            return .reopen("\(went) was renamed or replaced by \(came), whose private state would start over")
        }
        // A file taken away can change what an unchanged caller means: a method it declared may have stood in for
        // a protocol's default or another overload, which the caller now gets. So every file of the app's is
        // compiled again, the App's too (what else is in its file may call it, and the App itself, which ran once
        // at launch, is never run again), and every call goes to code compiled without it. Not Lamp's own files.
        if !gone.isEmpty {
            changed = built.keys.sorted().filter { !["LampSupport.swift", Template.sceneSupportFile].contains(($0 as NSString).lastPathComponent) }
        }
        return changed.isEmpty && gone.isEmpty ? .unchanged : .reload(changed)
    }

    /// Whether the whole new code type-checks and leaves every type the open app has holding what it did:
    /// nil when so, with the new code's layout to keep once it's gone in; else why not. The whole module, not
    /// just the changed files: a changed function can change what a property in another file is inferred to
    /// hold, and an unchanged caller can stop compiling, which compiling the changed files alone wouldn't show
    /// (then the usual build runs and the agent sees its errors). The open app's layout is kept from the last
    /// time, so only the new code is type-checked, alongside the changed files' compile.
    @MainActor static func layoutProblem(_ project: LampProject) async -> (problem: String?, layout: [String]?) {
        let (before, after, _, _) = await layouts(project)
        return layoutProblem(before: before, after: after)
    }

    /// The layout's lines that aren't a type's members, by the control character their group begins with: what's
    /// read at launch (`SwiftSource.launchEntries`), constants' values (`constantEntries`), typealiases (`aliasGroup`)
    /// and what's declared (`declarationGroup`). Each is compared its own way, never as a type's fields.
    static func isGroup(_ type: String) -> Bool { (type.first?.asciiValue ?? 32) < 32 }
    static let aliasGroup = "\u{3}alias", declarationGroup = "\u{5}declared"

    /// Whether the new code declares other functions, initializers, subscripts, computed properties or
    /// conformances than the open app's: an unchanged caller may then mean another one (a new overload, a method
    /// where a protocol's default stood in, an extension's method over a system one), so every file is compiled again.
    static func declarationsChanged(before: [String], after: [String]) -> Bool {
        Set(before.filter { $0.hasPrefix(declarationGroup + "\t") }) != Set(after.filter { $0.hasPrefix(declarationGroup + "\t") })
    }

    static func layoutProblem(before: [String]?, after: [String]?) -> (problem: String?, layout: [String]?) {
        guard let now = after else { return ("the new code doesn't type-check as a whole", nil) }
        guard let before else { return ("the compiler couldn't say what the open app's types hold", nil) }
        // A typealias is printed as itself wherever it's used, so a type keeping `var amount: Money` reads the same
        // when Money changes from Int to Double, while its size changes under the open app's values: an alias the
        // open app has must still name what it did. One added or taken away changes nothing of what exists.
        func aliases(_ entries: [String]) -> [String: String] {
            Dictionary(entries.filter { $0.hasPrefix(aliasGroup + "\t") }.compactMap { entry -> (String, String)? in
                guard let equals = entry.range(of: " = ") else { return nil }
                return (String(entry[entry.index(after: entry.firstIndex(of: "\t")!)..<equals.lowerBound]), String(entry[equals.upperBound...]))
            }, uniquingKeysWith: { first, _ in first })
        }
        for (name, was) in aliases(before).sorted(by: { $0.key < $1.key }) {
            if let is_ = aliases(now)[name], is_ != was { return ("the typealias \(name) changed from \(was) to \(is_)", nil) }
        }
        // Type by type, each "Owner<tab>member": a type the open app has must hold just what it did, in order;
        // a new type (a new view with its own state) is the library's to lay out. A type taken away keeps its
        // objects and their code in the open app, and the new code doesn't touch them: whatever held one either
        // changed what it holds (and is caught here) or was taken away too.
        func byType(_ entries: [String]) -> [String: [String]] {
            Dictionary(grouping: entries, by: { String($0.prefix { $0 != "\t" }) })
        }
        let old = byType(before), new = byType(now)
        for (type, members) in old.sorted(by: { $0.key < $1.key }) where !isGroup(type) || type == "\u{1}launch" {
            guard let current = new[type] else { continue }
            if type == "\u{1}launch", current != members {
                let what = (current.first { !members.contains($0) } ?? members.first { !current.contains($0) } ?? "")
                    .split(separator: "\t").last.map { String($0.prefix { $0 != ":" }) } ?? ""
                return ("what the app reads only at launch changed (\(what))", nil)
            }
            if current != members, !LiveSlots.casesAdded(type, members, current) {
                let what = (current.first { !members.contains($0) } ?? members.first { !current.contains($0) }.map { "no longer " + $0 } ?? "the order of its fields")
                    .replacingOccurrences(of: "\t", with: ".")
                return ("\(type) changed what it holds (\(what))", nil)
            }
        }
        // A type taken away is still in the open app, with its objects and statics, until it reopens: its layout
        // is kept, so one brought back under the same name is held to what it was. So is an alias taken away, each
        // on its own, since a type kept that way still reads by it.
        let remaining = aliases(now)
        let kept = now + before.filter { let group = String($0.prefix { $0 != "\t" }); return group != aliasGroup && new[group] == nil }
            + before.filter { $0.hasPrefix(aliasGroup + "\t") && aliases([$0]).keys.allSatisfy { remaining[$0] == nil } }
        return (nil, kept)
    }

    /// The enums that only gained cases at the end (`LiveSlots.casesAdded`), which the layout check let through.
    static func grownEnums(before: [String], after: [String]) -> [String] {
        func byType(_ entries: [String]) -> [String: [String]] {
            Dictionary(grouping: entries, by: { String($0.prefix { $0 != "\t" }) })
        }
        let old = byType(before), new = byType(after)
        return old.keys.sorted().filter { type in
            guard !isGroup(type), let current = new[type], current != old[type] else { return false }
            return LiveSlots.casesAdded(type, old[type]!, current)
        }
    }

    /// Why a grown enum can't go in, if it can't: something the app keeps holds it other than as itself or in a
    /// plain collection of it (an optional, another enum's case, a wrapper), where Swift gives its unused numbers
    /// meanings that a new case takes over. Looked for in every stored field, static and global of the new code,
    /// and in what the spares keep, whose types the compiler no longer sees.
    @MainActor static func enumsHeld(_ project: LampProject, grown: [String]) async -> String? {
        guard let dump = await dump(of: sources(project), in: project, module: project.exe, macOS: Template.macMinimum(project)) else {
            return "the compiler couldn't say what holds the enums that grew"
        }
        let held = members(inDump: dump, held: true).compactMap { entry -> (String, String)? in
            guard !isGroup(String(entry.prefix { $0 != "\t" })), let colon = entry.range(of: ": ") else { return nil }
            return (String(entry.prefix { $0 != "\t" }), String(entry[colon.upperBound...]))
        } + LiveSlots.mapping(project).flatMap { type, properties in properties.map { (type, $0.value.type) } }
        // A value of the enum could hide in what holds anything at all, where its type can't be seen.
        let untyped = try! NSRegularExpression(pattern: #"(?<![\w.])(Any|AnyObject|AnyHashable|any [\w.]+)(?![\w])"#)
        for (owner, kind) in held where untyped.firstMatch(in: kind, range: NSRange(kind.startIndex..., in: kind)) != nil {
            return "\(owner.isEmpty ? "a global" : owner) keeps values of any type (\(kind)), which may hold \(grown.joined(separator: ", "))"
        }
        for type in grown {
            let name = NSRegularExpression.escapedPattern(for: type)
            let mention = try! NSRegularExpression(pattern: #"(?<![\w.])"# + name + #"(?![\w])"#)
            let plainly = try! NSRegularExpression(pattern: #"^(\[(\w[\w.]*: )?"# + name + #"\]|Set<"# + name + #">|"# + name + #"|\("# + name + #"\.Type\) -> "# + name + #")$"#)
            for (owner, kind) in held {
                let range = NSRange(kind.startIndex..., in: kind)
                if mention.firstMatch(in: kind, range: range) != nil, plainly.firstMatch(in: kind, range: range) == nil {
                    return "\(owner.isEmpty ? "a global" : owner) holds \(type) as \(kind), which a new case would change"
                }
            }
        }
        return nil
    }

    /// Why a grown enum can't go in for the code the open app is still running, if it can't. Every file is compiled
    /// again for one, but code already running keeps the version it started with: a closure given to a timer, a
    /// task or an observer, a `.task` of a view's, a function waiting on an `await`. A `switch` over the enum
    /// there was compiled for the cases it had, and a new case lands in another's arm or past the end; printing
    /// it reads the old description of the enum. So the sources the open app runs, and those of every change that
    /// went in before (`recordOldCode`, since what an earlier change's code started may still be running), are read
    /// for a `switch` over the enum, or an interpolation of it, in an escaping closure made outside a view's body
    /// (what a body makes is made again at the next draw), in an async closure anywhere, or in an async function.
    @MainActor static func enumsMetByOldCode(_ project: LampProject, grown: [String]) async -> String? {
        guard let dump = await dump(of: running(project), in: project, module: project.exe, macOS: Template.macMinimum(project)) else {
            return "the compiler couldn't say where the open app uses the enums that grew"
        }
        return oldCode(meeting: grown, uses: oldCodeRecorded(project) + oldCodeUses(inDump: dump))
    }

    /// Why a grown enum can't go in, among what old code may still be doing: the first use of one of the enums.
    static func oldCode(meeting enums: [String], uses: [String]) -> String? {
        let names = Set(enums), optional = Set(enums.map { $0 + "?" })
        for use in uses {
            let parts = use.split(separator: "\t", maxSplits: 2).map(String.init)
            guard parts.count == 3, names.contains(parts[0]) || optional.contains(parts[0]) else { continue }
            return "\(parts[1]) \(parts[2]) \(parts[0]) in code that may still be running (a timer, a task, an observer), which doesn't know the new cases"
        }
        return nil
    }

    static func oldCode(meeting enums: [String], inDump dump: String) -> String? { oldCode(meeting: enums, uses: oldCodeUses(inDump: dump)) }

    /// Every `switch` over an enum, and every interpolation of one, in code that may go on running after a change
    /// (an escaping closure made outside a view's body, an async closure, an async function), as
    /// "Type<tab>where<tab>switches over" or "…<tab>prints", for every enum: which ones will grow isn't known yet.
    static func oldCodeUses(inDump dump: String) -> [String] {
        enum Kind { case body, escaping, async, function(String?, async: Bool), other }
        // A view's body, or the live copy's name for it (`Template.liveCopySteps` moves the body into `__lampBody`).
        let bodyDecl = try! NSRegularExpression(pattern: #"^(\s*)\(var_decl\b[^"]*"(?:body|__lampBody)" "#)
        let closure = try! NSRegularExpression(pattern: #"^(\s*)\((?:closure_expr|autoclosure_expr)\b(.*)$"#)
        let function = try! NSRegularExpression(pattern: #"^(\s*)\((?:func_decl|accessor_decl|constructor_decl)\b[^"]*(?:"([^"]+)")? interface_type="([^"]*)""#)
        let scope = try! NSRegularExpression(pattern: #"^(\s*)\((?:var_decl|subscript_decl|struct_decl|class_decl|enum_decl|actor_decl|extension_decl|protocol)\b"#)
        let switchStmt = try! NSRegularExpression(pattern: #"^(\s*)\(switch_stmt\b"#)
        let casePattern = try! NSRegularExpression(pattern: #"^(\s*)\(pattern_enum_element\b.*? type="([^"]*)""#)
        let interpolation = try! NSRegularExpression(pattern: #"^(\s*)\(declref_expr\b.*? type="[^"]*\(([^"()]*)\) -> \(\)".*? decl="Swift\.\(file\)\.DefaultStringInterpolation\.appendInterpolation"#)
        var scopes: [(indent: Int, kind: Kind)] = [], uses: [String] = [], seen = Set<String>()
        var switching: Int?
        func note(_ type: String, _ how: String) {
            let use = type + "\t" + place() + "\t" + how
            if seen.insert(use).inserted { uses.append(use) }
        }
        func risky() -> Bool {
            var inBody = false
            for (_, kind) in scopes {
                switch kind {
                case .body: inBody = true
                case .async, .function(_, async: true): return true
                case .escaping where !inBody: return true
                default: break
                }
            }
            return false
        }
        func place() -> String {
            for (_, kind) in scopes.reversed() { if case .function(let name?, _) = kind { return name } }
            return "the app"
        }
        for raw in dump.split(separator: "\n") {
            let line = String(raw), range = NSRange(line.startIndex..., in: line)
            let indent = line.prefix { $0 == " " }.count
            guard line.dropFirst(indent).first == "(" else { continue }
            while let last = scopes.last, last.indent >= indent { scopes.removeLast() }
            if let at = switching, at >= indent { switching = nil }
            if bodyDecl.firstMatch(in: line, range: range) != nil {
                scopes.append((indent, .body))
            } else if let m = closure.firstMatch(in: line, range: range) {
                let rest = String(line[Range(m.range(at: 2), in: line)!])
                scopes.append((indent, rest.contains(" async") ? .async : rest.contains(" escaping") ? .escaping : .other))
            } else if let m = function.firstMatch(in: line, range: range) {
                let type = String(line[Range(m.range(at: 3), in: line)!])
                let name = m.range(at: 2).location == NSNotFound ? nil : String(line[Range(m.range(at: 2), in: line)!])
                scopes.append((indent, .function(name, async: type.contains(" async"))))
            } else if scope.firstMatch(in: line, range: range) != nil {
                scopes.append((indent, .other))
            } else if switchStmt.firstMatch(in: line, range: range) != nil {
                if risky() { switching = indent }
            } else if let at = switching, indent > at, let m = casePattern.firstMatch(in: line, range: range) {
                note(String(line[Range(m.range(at: 2), in: line)!]), "switches over")
            } else if let m = interpolation.firstMatch(in: line, range: range), risky() {
                note(String(line[Range(m.range(at: 2), in: line)!]), "prints")
            }
        }
        return uses
    }

    /// What the open app's types hold (kept from the last time, or worked out from the sources it runs) and what
    /// the new code's hold; nil for either the compiler can't say.
    /// With the new code's, where each of its properties is declared, for `LiveSlots` to rewrite.
    @MainActor static func layouts(_ project: LampProject) async
        -> (before: [String]?, after: [String]?, declarations: SwiftSource.Declarations, oldCode: [String]) {
        async let after = analysis(of: sources(project), in: project, module: project.exe, macOS: Template.macMinimum(project))
        // Written back after a reload, so never read through a link: it would bring what it leads to into the folder.
        var before = AppFile.text(runningLayout(project), in: project).map { $0.components(separatedBy: "\n").filter { !$0.isEmpty } }
        if before == nil {
            before = await analysis(of: running(project), in: project, module: project.exe, macOS: Template.macMinimum(project))?.layout
            if let before { try? AppFolder.write(before.joined(separator: "\n"), to: runningLayout(project), in: project.dir) }
        }
        let new = await after
        return (before, new?.layout, new?.declarations ?? SwiftSource.Declarations(), new?.oldCode ?? [])
    }

    /// What the open app's types hold, kept beside the sources it runs: written when a change goes in (the new
    /// code's), gone when the app is installed (worked out again at the next change).
    private static func runningLayout(_ project: LampProject) -> URL { folder(project).appendingPathComponent("running-layout.txt") }

    static func keepLayout(_ layout: [String], for project: LampProject) {
        try? AppFolder.write(layout.joined(separator: "\n"), to: runningLayout(project), in: project.dir)
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
    static func layout(of folder: URL, in project: LampProject, files: [String]?, module: String, macOS: String, ios: Bool = false,
                       rawValues: Bool = false) async -> [String]? {
        if files?.isEmpty == true { return [] }
        // All of the app's own files, by name: the compiler prints (and checks the bodies of) only the files it's
        // given as primaries, or just the first with none. Lamp's building blocks are read for context only: the
        // app's code can't change what they hold or make them stop compiling, and they're most of the time.
        let primaries = files ?? swiftFiles(in: folder).keys.filter { ($0 as NSString).lastPathComponent != "LampSupport.swift" }.sorted()
        guard !primaries.isEmpty else { return [] }
        var output: [String] = []
        let status = await Sandbox.run(frontend("-dump-ast", in: folder, primaries: primaries, module: module, macOS: macOS, ios: ios) + " 2>/dev/null",
                                       for: project, cwd: folder) { output.append($0) }
        guard status == 0 else { return nil }
        return members(inDump: output.joined(separator: "\n"), rawValues: rawValues)
    }

    /// The compiler's printout of a live copy's whole code but Lamp's own, or nil when it doesn't type-check (or
    /// there's none): empty for a copy with no files of the app's.
    static func dump(of folder: URL, in project: LampProject, module: String, macOS: String) async -> String? {
        let primaries = swiftFiles(in: folder).keys.filter { ($0 as NSString).lastPathComponent != "LampSupport.swift" }.sorted()
        guard !primaries.isEmpty else { return "" }
        var output: [String] = []
        let status = await Sandbox.run(frontend("-dump-ast", in: folder, primaries: primaries, module: module, macOS: macOS) + " 2>/dev/null",
                                       for: project, cwd: folder) { output.append($0) }
        return status == 0 ? output.joined(separator: "\n") : nil
    }

    /// A live copy's layout as `layout` gives it, with what's read only at launch (`SwiftSource.launchEntries`)
    /// and where each property is declared, all from the one printout.
    /// And where its code may go on running after the next change (`oldCodeUses`), to record once it's in.
    static func analysis(of folder: URL, in project: LampProject, module: String, macOS: String)
        async -> (layout: [String], declarations: SwiftSource.Declarations, oldCode: [String])? {
        guard let dump = await dump(of: folder, in: project, module: module, macOS: macOS) else { return nil }
        let declarations = SwiftSource.declarations(inDump: dump)
        return (members(inDump: dump) + SwiftSource.launchEntries(inDump: dump, folder: folder) + SwiftSource.constantEntries(declarations),
                declarations, oldCodeUses(inDump: dump))
    }

    /// The stored members of every type in a `-dump-ast` printout: each line's indent says what it's inside, so
    /// a function's locals (inside a func or closure) never count, nor a static or a computed property.
    /// `held` adds what the app keeps beyond its types' own fields: static properties, and globals (under "").
    static func members(inDump dump: String, rawValues: Bool = false, held: Bool = false) -> [String] {
        let typeDecl = try! NSRegularExpression(pattern: #"^(\s*)\((struct|class|enum|actor)_decl\b[^"]*"([^"]+)""#)
        // A protocol's requirements lay out its witness tables, which a change keeps using the app's: listed as what
        // the protocol holds, so one that gained or lost a requirement reopens the app like a type that changed.
        let protocolDecl = try! NSRegularExpression(pattern: #"^(\s*)\(protocol(_decl)?\b[^"]*"([^"]+)""#)
        let requirement = try! NSRegularExpression(pattern: #"^(\s*)\((func_decl|var_decl|subscript_decl|constructor_decl|associated_type_decl)\b[^"]*"([^"]+)" interface_type="([^"]*)""#)
        // A property's or subscript's accessors are requirements of their own (`{ get }` against `{ get set }`),
        // printed under it: each is listed with the requirement, by what it is.
        let accessor = try! NSRegularExpression(pattern: #"^(\s*)\(accessor_decl\b.*? interface_type="([^"]*)".*? (get|set|_modify|_read|unsafeAddress|unsafeMutableAddress|init|read|modify) for="#)
        let scopeDecl = try! NSRegularExpression(pattern: #"^(\s*)\((func_decl|accessor_decl|constructor_decl|destructor_decl|closure_expr|subscript_decl|top_level_code_decl)\b"#)
        // A declaration's position (decl_context=…, range=[…]) comes before its name; neither holds a quote.
        let varDecl = try! NSRegularExpression(pattern: #"^(\s*)\(var_decl\b[^"]*"([^"]+)" interface_type="([^"]*)"(.*)$"#)
        let caseDecl = try! NSRegularExpression(pattern: #"^(\s*)\(enum_element_decl\b[^"]*"([^"]+)" interface_type="([^"]*)""#)
        // A typealias, with what it names; an extension, which puts its members under its type; what a type or an
        // extension conforms to; and a function, initializer or subscript, by its name and type (`declarationGroup`).
        let aliasDecl = try! NSRegularExpression(pattern: #"^(\s*)\(typealias\b[^"]*? range=\[([^:\]]*):[^\]]*\][^"]*"([^"]+)" interface_type="[^"]*" access=(\w+).*? type="([^"]*)""#)
        let extensionDecl = try! NSRegularExpression(pattern: #"^(\s*)\(extension_decl\b[^"]*"([^"]+)""#)
        let inherits = try! NSRegularExpression(pattern: #" inherits="([^"]*)""#)
        let memberDecl = try! NSRegularExpression(pattern: #"^(\s*)\((func_decl|constructor_decl|subscript_decl)\b[^"]*"([^"]+)" interface_type="([^"]*)""#)
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
            // Something declared at the top or in a type, never a function's local, under `declarationGroup`.
            func declared(_ what: String) {
                // What the compiler declares by itself (a memberwise initializer, a conformance's synthesized
                // methods) follows from what's written, which is listed already.
                guard !line.contains(" implicit") else { return }
                let place: String
                if let owner, !owner.hasPrefix("\u{4}") { place = owner + "." } else if scopes.isEmpty { place = "" } else { return }
                let entry = declarationGroup + "\t" + place + what
                if seen.insert(entry).inserted { out.append(entry) }
            }
            func conformances(_ type: String) {
                if let m = inherits.firstMatch(in: line, range: range) { declared(type + " inherits " + String(line[Range(m.range(at: 1), in: line)!])) }
            }
            if let m = protocolDecl.firstMatch(in: line, range: range) {
                let type = "protocol " + String(line[Range(m.range(at: 3), in: line)!])
                scopes.append((indent, type))
                if seen.insert(type + "\t").inserted { out.append(type + "\t") }
            } else if let owner, owner.hasPrefix("protocol "), let m = requirement.firstMatch(in: line, range: range) {
                let entry = owner + "\t" + String(line[Range(m.range(at: 3), in: line)!]) + ": " + String(line[Range(m.range(at: 4), in: line)!])
                if seen.insert(entry).inserted { out.append(entry) }
                scopes.append((indent, "\u{4}" + entry))
            } else if let owner, owner.hasPrefix("\u{4}"), let m = accessor.firstMatch(in: line, range: range) {
                let entry = String(owner.dropFirst()) + " " + String(line[Range(m.range(at: 3), in: line)!]) + ": " + String(line[Range(m.range(at: 2), in: line)!])
                if seen.insert(entry).inserted { out.append(entry) }
                scopes.append((indent, nil))
            } else if let m = typeDecl.firstMatch(in: line, range: range) {
                let name = String(line[Range(m.range(at: 3), in: line)!])
                let outer = scopes.compactMap(\.type).last
                let type = outer.map { $0 + "." + name } ?? name
                conformances(type)
                scopes.append((indent, type))
                // Every type is listed, members or not: an empty one the open app has is still its, and a first
                // field added to it changes what it holds.
                if seen.insert(type + "\t").inserted { out.append(type + "\t") }
            } else if let m = extensionDecl.firstMatch(in: line, range: range) {
                let type = String(line[Range(m.range(at: 2), in: line)!])
                conformances(type)
                scopes.append((indent, type))
            } else if let m = aliasDecl.firstMatch(in: line, range: range) {
                var name = String(line[Range(m.range(at: 3), in: line)!])
                let type = String(line[Range(m.range(at: 5), in: line)!]), access = String(line[Range(m.range(at: 4), in: line)!])
                // One private to its file is known by its file too: another file may have one of the same name.
                if ["private", "fileprivate"].contains(access) {
                    name = ((String(line[Range(m.range(at: 2), in: line)!]) as NSString).lastPathComponent) + ":" + name
                }
                if let owner, !owner.hasPrefix("\u{4}") {
                    if seen.insert(aliasGroup + "\t" + owner + "." + name + " = " + type).inserted { out.append(aliasGroup + "\t" + owner + "." + name + " = " + type) }
                } else if scopes.isEmpty, seen.insert(aliasGroup + "\t" + name + " = " + type).inserted {
                    out.append(aliasGroup + "\t" + name + " = " + type)
                }
            } else if let m = varDecl.firstMatch(in: line, range: range) {
                let rest = String(line[Range(m.range(at: 4), in: line)!])
                let global = held && scopes.isEmpty
                let name = String(line[Range(m.range(at: 2), in: line)!]), type = String(line[Range(m.range(at: 3), in: line)!])
                if let owner = owner ?? (global ? "" : nil), rest.contains("readImpl=stored"), held || !rest.contains(" static") {
                    let entry = owner + "\t" + name + ": " + type
                    if seen.insert(entry).inserted { out.append(entry) }
                } else if !rest.contains("readImpl=stored") {
                    declared(name + ": " + type)
                }
            } else if let m = memberDecl.firstMatch(in: line, range: range) {
                declared(String(line[Range(m.range(at: 3), in: line)!]) + ": " + String(line[Range(m.range(at: 4), in: line)!]))
                scopes.append((indent, nil))
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
    /// Compiles the whole module from the live copy, the way the live build does (SwiftPM's for a Mac app,
    /// Xcode's for the Mac half of an app for both: both unoptimized, testable, for the app's macOS, named after the app),
    /// and links the changed files' objects into a library for the open app. Nil, with the compiler's words, when it doesn't compile.
    /// Every file of the app's in the live copy, but Lamp's own.
    static func appFiles(_ project: LampProject) -> [String] {
        swiftFiles(in: sources(project)).keys.filter { !["LampSupport.swift", Template.sceneSupportFile].contains(($0 as NSString).lastPathComponent) }.sorted()
    }

    /// `keep` names the types whose metadata the library brings as its own rather than taking the app's
    /// (`LiveObject`): the enums that gained cases, by their mangled names.
    static func compile(_ project: LampProject, changed: [String], keep: [String] = []) async -> (url: URL?, problem: String?) {
        guard !changed.isEmpty else { return (nil, nil) }
        let live = folder(project)
        let work = live.appendingPathComponent("hot")
        try? FileManager.default.removeItem(at: work)
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let library = live.appendingPathComponent("hot-\(UUID().uuidString.prefix(8)).dylib")
        // One object for each changed file, in the order they're named; only they are compiled.
        let objects = changed.indices.map { work.appendingPathComponent("\($0).o").path }
        let macOS = Template.macMinimum(project)
        var output: [String] = []
        let compiled = await Sandbox.run("set -e\n" + frontend("-c", in: sources(project), primaries: changed, module: project.exe, macOS: macOS)
            + " " + objects.map { "-o " + quoted($0) }.joined(separator: " ") + " 2>&1", for: project) { output.append($0) }
        guard compiled == 0 else { return (nil, output.suffix(30).joined(separator: "\n")) }
        // The types the objects define over again are made the app's before they're linked.
        var matched = Set<String>()
        for object in objects {
            if let problem = LiveObject.rewrite(object, kept: keep, matched: &matched) { return (nil, "the change couldn't be made the app's: \(problem)") }
        }
        guard matched.count == Set(keep).count else { return (nil, "an enum that gained cases wasn't found in the change") }
        // A type's name is referred to weakly, so a type the app doesn't have (a new one) loads all the same, and
        // the library's own copy stands in for it (`LampLive`); mismatched references are made weak too.
        let script = "set -e\n" + Shell.compatibleSDK + #"SDK="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}""# + "\n" + """
            xcrun swiftc -emit-library \(objects.map(quoted).joined(separator: " ")) -o \(quoted(library.path)) \\
              -target arm64-apple-macosx\(macOS) -sdk "$SDK" -Xlinker -undefined -Xlinker dynamic_lookup -Xlinker -interposable \\
              -Xlinker -weak_reference_mismatches -Xlinker weak 2>&1
            codesign --force -s - \(quoted(library.path)) 2>&1
            """
        let status = await Sandbox.run(script, for: project) { output.append($0) }
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

/// A stored property added while the app is open, put in without reopening it. A live build gives every class of the
/// app's `count` spare places (`__lampSpare_<Class>_0`…), every other struct one that holds any number of properties
/// by name (`__lampSpare_<Struct>`), and every view a `@State` box (`__lampState_<View>`), all written by the
/// copy step (`Template.sparesPerl`), so the open app's objects and values already have room. When the only thing
/// keeping a change out is new stored properties in such types, each one's declaration in the live copy becomes a
/// computed property kept in a spare: the type then holds what it did, and the change goes in like any other. Being
/// stored, a spare is observed like the rest (`@Observable`'s tracking, `@Published` in an `ObservableObject`, a
/// view's state), so what reads the new property is redrawn when it changes. Which property is where is kept until
/// the app is next installed, and put back into every live copy made meanwhile (`apply`), so later changes see the
/// same layout. Cases added at the end of an enum without payloads need nothing: its values keep their size.
enum LiveSlots {
    static let count = 4

    /// What keeps a property: a class's own place, a struct's shared one, or a view's state box.
    enum Holder: String, Codable { case object, value, view }

    struct Slot: Codable, Equatable {
        var index: Int
        /// The property's type as the compiler worked it out, for a declaration that doesn't spell it.
        var type: String
        /// Nil in what was saved before structs and views had spares: a class's.
        var holder: Holder?
        /// A struct's property: the cases of its enum type when it was taken in, by which its starting value is
        /// judged again each time it's put back.
        var cases: [String]?
        /// A struct's property: the starting value it was taken in with. Its spare compares a value that never set
        /// it by that, so a different one later can't share the spare: the property stays stored, and reopens the app.
        var initial: String?
    }

    private static func url(_ project: LampProject) -> URL { LiveReload.folder(project).appendingPathComponent("slots.json") }

    /// Type ("Outer.Inner") → property → its place.
    static func mapping(_ project: LampProject) -> [String: [String: Slot]] {
        (try? JSONDecoder().decode([String: [String: Slot]].self, from: Data(contentsOf: url(project)))) ?? [:]
    }

    private static func save(_ mapping: [String: [String: Slot]], for project: LampProject) {
        try? JSONEncoder().encode(mapping).write(to: url(project), options: .atomic)
    }

    /// Whether a live build's errors are about the spares rather than the app's own code.
    static func brokeBuild(_ output: String) -> Bool {
        ["__lampSpare_", "__lampState_", "LampSpare", "LampStateBox"].contains { output.contains($0) }
    }

    /// Live copies of the app have no spares from now on (build.sh skips them while the file is there). True the
    /// first time, so the build is tried once more.
    static func giveUp(_ project: LampProject) -> Bool {
        let marker = LiveReload.folder(project).appendingPathComponent("no-spares")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return false }
        return FileManager.default.createFile(atPath: marker.path, contents: Data())
    }

    /// The app was installed: its objects are the new build's, with every property stored, and its places empty.
    static func clear(_ project: LampProject) {
        try? FileManager.default.removeItem(at: url(project))
        try? FileManager.default.removeItem(at: constantsURL(project))
    }

    /// Whether an enum only gained cases, at the end, with none of its cases carrying anything: a value of it is
    /// then its case's number, which the cases it had keep, in the same size (up to 256 cases; one case takes no
    /// room, so it needs two to begin with). The code that reads the new cases is the change's. But the numbers
    /// after the last case mean something too: Swift uses the first one free for `nil` in an optional of it, and
    /// the next for another enum's cases that carry it, so a new case would read an existing `nil` as itself.
    /// That's checked before the change goes in (`LiveReload.enumsHeld`).
    static func casesAdded(_ type: String, _ old: [String], _ new: [String]) -> Bool {
        func plain(_ entry: String) -> Bool {
            guard let field = entry.split(separator: "\t", maxSplits: 1).last, field.hasPrefix("case ") else { return false }
            return field.components(separatedBy: "->").count == 2
        }
        // Each type's list starts with the type itself ("Mood<tab>"), which holds nothing.
        let old = old.filter { !$0.hasSuffix("\t") }, new = new.filter { !$0.hasSuffix("\t") }
        return old.count >= 2 && new.count > old.count && new.count <= 256
            && old.allSatisfy(plain) && new.allSatisfy(plain) && Array(new.prefix(old.count)) == old
    }

    /// What fitting a change into the spares did: the properties newly taken in ("Game.onFoot"), the new code's
    /// layout as the open app now sees it (the moved properties no longer stored), and the files of the live copy
    /// that were rewritten (relative to it), which are compiled with the change.
    struct Plan {
        var added: [String]
        var layout: [String]
        var files: [String]
        /// The constants given their new values for the first time ("Car.topSpeed").
        var constants: [String] = []
    }

    private static func constantsURL(_ project: LampProject) -> URL { LiveReload.folder(project).appendingPathComponent("constants.json") }

    /// Whether a constant's new value was given at an earlier change: the live copy is then rewritten before anything
    /// is compiled.
    static func hasConstants(_ project: LampProject) -> Bool {
        ((try? JSONDecoder().decode([String].self, from: Data(contentsOf: constantsURL(project)))) ?? []).isEmpty == false
    }

    /// The constants (static or global `let`s, "Type<tab>name") whose value changed since the app opened: those that
    /// differ now, and those that did at an earlier change, which the fresh live copy has as they're written again.
    static func changedConstants(_ project: LampProject, before: [String], after: [String]) -> [String] {
        func values(_ entries: [String]) -> [String: String] {
            Dictionary(entries.filter { $0.hasPrefix("\u{2}constant\t") }.compactMap { entry -> (String, String)? in
                let field = entry.dropFirst("\u{2}constant\t".count)
                guard let colon = field.range(of: ": ", options: .backwards) else { return nil }
                return (String(field[..<colon.lowerBound]), String(field[colon.upperBound...]))
            }, uniquingKeysWith: { first, _ in first })
        }
        let old = values(before), new = values(after)
        let earlier = (try? JSONDecoder().decode([String].self, from: Data(contentsOf: constantsURL(project)))) ?? []
        return Set(new.keys.filter { key in old[key].map { $0 != new[key] } ?? false } + earlier.filter { new[$0] != nil }).sorted()
    }

    /// When every way the new code's types differ from the open app's is a stored property added to a type with a
    /// spare for it, rewrites each one's declaration in the live copy into a computed property kept in its spare,
    /// and answers what it did; else changes nothing and answers nil. The live copy is fresh from the app's sources
    /// each time, so the properties already in spares (`mapping`) come back as additions too, and are put back in
    /// the same places. Where each is declared comes from the compiler (`declarations`), so however it's written
    /// (with attributes, across lines, in a list with others, in a type written on one line), it's found exactly.
    static func fit(_ project: LampProject, before: [String], after: [String], declarations: SwiftSource.Declarations,
                    constants: [String] = []) -> Plan? {
        func byType(_ entries: [String]) -> [String: [String]] {
            Dictionary(grouping: entries, by: { String($0.prefix { $0 != "\t" }) })
        }
        let old = byType(before), new = byType(after)
        var map = mapping(project)
        var cases: [String: Set<String>] = [:]
        for entry in after {
            let parts = entry.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, parts[1].hasPrefix("case "), let colon = parts[1].range(of: ": ") else { continue }
            cases[String(parts[0]), default: []].insert(String(parts[1][parts[1].index(parts[1].startIndex, offsetBy: 5)..<colon.lowerBound]))
        }
        var planned: [(type: String, name: String, slot: Slot, published: Bool, isNew: Bool)] = []
        var moved = Set<String>()
        for (type, members) in old.sorted(by: { $0.key < $1.key }) where !LiveReload.isGroup(type) {
            guard let current = new[type] else { continue }
            guard current != members, !casesAdded(type, members, current) else { continue }
            // Only additions, with what was there still there, in order.
            let extras = current.filter { !members.contains($0) }
            guard current.filter({ members.contains($0) }) == members, !extras.isEmpty else { return nil }
            // The spares as the type keeps them: a class's plain, behind @Observable's `_`, or in @Published's
            // wrapper; a struct's plain; a view's in its State.
            let first = place(0, in: type)
            let observed = members.contains(type + "\t_\(first): LampSpare?")
            let published = members.contains(type + "\t_\(first): Published<LampSpare?>")
            let holder: Holder
            if observed || published || members.contains(type + "\t\(first): LampSpare?") {
                holder = .object
            } else if members.contains(type + "\t\(place(in: type, holder: .value)): LampSpare") {
                holder = .value
            } else if members.contains(type + "\t_\(place(in: type, holder: .view)): State<LampStateBox>")
                        || members.contains(type + "\t__\(place(in: type, holder: .view)): LazyState<LampStateBox>") {
                holder = .view
            } else {
                return nil
            }
            var taken = Set((map[type] ?? [:]).values.map(\.index))
            for extra in extras {
                let field = extra.dropFirst(type.count + 1)
                guard !field.hasPrefix("case "), let colon = field.range(of: ": ") else { return nil }
                var name = String(field[..<colon.lowerBound]), kind = String(field[colon.upperBound...])
                // A wrapper's storage: `_name: Wrapper<T>`, or `__name: LazyState<T>` where @State is a macro.
                func unwrap(_ wrapper: String, underscores: Int = 1) -> Bool {
                    guard name.hasPrefix(String(repeating: "_", count: underscores)), kind.hasPrefix(wrapper + "<"), kind.hasSuffix(">") else { return false }
                    name.removeFirst(underscores)
                    kind = String(kind.dropFirst(wrapper.count + 1).dropLast())
                    return true
                }
                switch holder {
                case .object:
                    // @Observable keeps a property in `_name`, @Published in `_name: Published<T>`.
                    if !unwrap("Published"), observed, name.hasPrefix("_") { name.removeFirst() }
                case .value:
                    // A wrapper's storage (`_name`) isn't a plain property.
                    guard !name.hasPrefix("_") else { return nil }
                case .view:
                    guard unwrap("State") || unwrap("LazyState", underscores: 2) else { return nil }
                }
                moved.insert(extra)
                if let kept = map[type]?[name] {
                    // Already in a spare: the same place, as long as it's still the same property.
                    guard kept.type == kind, (kept.holder ?? .object) == holder else { return nil }
                    planned.append((type, name, kept, published, false))
                    continue
                }
                var index = 0
                if holder == .object {
                    guard let free = (0..<count).first(where: { !taken.contains($0) }) else { return nil }
                    taken.insert(free)
                    index = free
                }
                let known = holder == .value ? cases[enumName(kind)].map { $0.sorted() } : nil
                planned.append((type, name, Slot(index: index, type: kind, holder: holder, cases: known), published, true))
            }
        }
        // Every type the open app doesn't have is the library's to lay out; one it has that changed must be fitted.
        guard !planned.isEmpty || !constants.isEmpty else { return nil }

        // Each declaration rewritten in its file, the last first so the earlier places stay where they are.
        var byFile: [String: [(binding: Int, items: [(type: String, name: String, slot: Slot, published: Bool, isNew: Bool)], constant: String?)]] = [:]
        for item in planned {
            guard let variable = declarations.variables[item.type + "\t" + item.name] else { return nil }
            let file = variable.position.file
            var list = byFile[file] ?? []
            if let at = list.firstIndex(where: { $0.binding == variable.binding }) { list[at].items.append(item) } else { list.append((variable.binding, [item], nil)) }
            byFile[file] = list
        }
        // A constant whose value is made from a changed one is made again too (`half = size / 2`), and so on.
        let constants = withDependents(constants, in: declarations)
        let byType = Dictionary(grouping: after, by: { String($0.prefix { $0 != "\t" }) })
        for key in constants {
            guard let variable = declarations.constants[key] else { return nil }
            byFile[variable.position.file, default: []].append((variable.binding, [], key))
        }
        let initializers = memberwiseInitializers(for: planned.filter { $0.slot.holder == .value }.map { ($0.type, $0.name) },
                                                  declarations: declarations)
        var written: [(path: String, text: String)] = []
        for (file, edits) in byFile {
            guard let original = SwiftSource.Text(path: file) else { return nil }
            var bytes = original.bytes
            var views: [String] = []
            let ordered = edits.sorted { declarations.bindings[$0.binding].start.line > declarations.bindings[$1.binding].start.line
                || (declarations.bindings[$0.binding].start.line == declarations.bindings[$1.binding].start.line
                    && declarations.bindings[$0.binding].start.column > declarations.bindings[$1.binding].start.column) }
            for edit in ordered {
                let made = edit.constant.map { rewriteConstant($0, in: original, declarations: declarations, rewritten: Set(constants), layout: byType) }
                    ?? rewrite(declarations.bindings[edit.binding], items: edit.items, in: original, declarations: declarations, cases: cases)
                guard let (range, text) = made else { return nil }
                bytes.replaceSubrange(range, with: Array(text.utf8))
                for item in edit.items where item.slot.holder == .view { views.append(item.name) }
            }
            var text = String(decoding: bytes, as: UTF8.self)
            // A view's `$name` was its state's binding: now the box's.
            for name in views { text = SwiftText.replacing(identifier: "$" + name, with: "__lampBinding_" + name, in: text) }
            text += initializers[file] ?? ""
            written.append((file, text))
        }
        for item in planned {
            var slot = item.slot
            if slot.holder == .value, slot.initial == nil {
                // The starting value as the computed property uses it: an optional with none written starts as nil.
                slot.initial = declarations.variables[item.type + "\t" + item.name].flatMap { variable in
                    initialText(of: variable, in: declarations)
                        ?? (variable.type.hasSuffix("?") || variable.type.hasPrefix("Optional<") ? "nil" : nil)
                }
            }
            map[item.type, default: [:]][item.name] = slot
        }
        let base = LiveReload.sources(project).standardizedFileURL.path + "/"
        for file in written { try? file.text.write(toFile: file.path, atomically: true, encoding: .utf8) }
        let earlier = (try? JSONDecoder().decode([String].self, from: Data(contentsOf: constantsURL(project)))) ?? []
        save(map, for: project)
        try? JSONEncoder().encode(constants).write(to: constantsURL(project), options: .atomic)
        return Plan(added: planned.filter(\.isNew).map { $0.type + "." + $0.name },
                    layout: after.filter { !moved.contains($0) },
                    files: written.map { URL(fileURLWithPath: $0.path).standardizedFileURL.path }.map { $0.hasPrefix(base) ? String($0.dropFirst(base.count)) : $0 },
                    constants: constants.filter { !earlier.contains($0) }.map(displayName))
    }

    /// A struct's new properties, moved into its spare, are no longer stored, so the initializer Swift made for it
    /// (`CityPart(edges:…, fuel:…)`) no longer takes them, and the new code that passes them doesn't compile. So it's
    /// made again beside the struct, in extensions in its file, calling the one Swift now makes and setting the moved
    /// properties after. A call may pass any of the moved ones, so there's one for each: the n-th takes the n-th moved
    /// property without a default, the later ones with theirs, and none of the earlier ones (left at their starting
    /// values). A call is then matched by the first moved property it passes and by nothing else, and one that passes
    /// none only by Swift's own. The call inside passes the spare's argument, which only Swift's takes; without a spare
    /// there's nothing to tell them apart by, and none is added. By file, the text to add to its end.
    static func memberwiseInitializers(for moved: [(type: String, name: String)],
                                       declarations: SwiftSource.Declarations) -> [String: String] {
        var out: [String: String] = [:]
        for (type, items) in Dictionary(grouping: moved, by: \.type).sorted(by: { $0.key < $1.key }) {
            let names = Set(items.map(\.name))
            guard let file = items.compactMap({ declarations.variables[type + "\t" + $0.name]?.position.file }).first else { continue }
            func initial(_ label: String) -> String? {
                declarations.variables[type + "\t" + label].flatMap { initialText(of: $0, in: declarations) }
            }
            for made in declarations.memberwise[type] ?? [] {
                // Swift's own, told apart from these by the spare's argument, which only it takes.
                let kept = made.labels.filter { !names.contains($0) }.compactMap { label -> String? in
                    guard label.hasPrefix("__lamp") else { return "\(label): \(label)" }
                    return initial(label).map { "\(label): \($0)" }
                }
                guard kept.contains(where: { $0.hasPrefix("__lamp") }) else { continue }
                let order = made.labels.filter(names.contains)
                // One the app declares itself with the same labels and types is the app's: a second would be a
                // redeclaration. One with other types is another overload, and this one is still needed beside it.
                let declared = declarations.initializers[type] ?? []
                for (n, first) in order.enumerated() {
                    let later = Set(order[(n + 1)...])
                    let taken = zip(made.labels, made.types).filter { label, _ in
                        !label.hasPrefix("__lamp") && (!names.contains(label) || label == first || later.contains(label))
                    }
                    guard !declared.contains(where: { $0.labels == taken.map(\.0) && $0.types == taken.map(\.1) }) else { continue }
                    let params = zip(made.labels, made.types).filter { label, _ in
                        !label.hasPrefix("__lamp") && (!names.contains(label) || label == first || later.contains(label))
                    }.map { label, kind in
                        var param = "\(label): \(kind)"
                        if label != first {
                            if let value = initial(label) { param += " = " + value } else if kind.hasSuffix("?") { param += " = nil" }
                        }
                        return param
                    }
                    let set = ([first] + order[(n + 1)...]).map { "        self.\($0) = \($0)\n" }.joined()
                    out[file, default: ""] += "\n\nextension \(type) {\n    init(\(params.joined(separator: ", "))) {\n"
                        + "        self.init(\(kept.joined(separator: ", ")))\n" + set + "    }\n}\n"
                }
            }
        }
        return out
    }

    /// A constant whose value changed, rewritten to give the new one: `static let size: Float = 200` becomes a
    /// computed `static var` that makes the value once (`LampConstants`) and keeps it. The open app made the old
    /// value once and keeps it in storage the new code no longer reads. Its name in `LampConstants` carries its
    /// text and the texts of the rewritten constants it's made from, so a change to any of them makes it again. Not
    /// for one that can hold an object, however wrapped (`[Model]`, `Session<Int>`, a struct holding one, a
    /// `LampAPI`): new objects there would split the app's state in two, so that reopens (`holdsObject`).
    private static func rewriteConstant(_ key: String, in text: SwiftSource.Text, declarations: SwiftSource.Declarations,
                                        rewritten: Set<String>, layout: [String: [String]]) -> (Range<Int>, String)? {
        guard let variable = declarations.constants[key] else { return nil }
        let binding = declarations.bindings[variable.binding]
        guard binding.entries.count == 1, let from = text.offset(binding.start), let end = text.tokenEnd(binding.last),
              let at = text.offset(variable.position), let initial = initialText(of: variable, in: declarations) else { return nil }
        // The declaration may start at `static` (or `class`): the `let` is the last word before the name.
        let lead = text.slice(from, at)
        guard let keyword = lead.range(of: #"\blet\b"#, options: [.regularExpression, .backwards]) else { return nil }
        let start = from + lead[..<keyword.lowerBound].utf8.count
        var seen = Set<String>()
        guard !holdsObject(variable.type, classes: declarations.classes, layout: layout, seen: &seen) else { return nil }
        // Its own text, and those of the rewritten constants it's made from, however far back.
        // Walked and hashed in name order, each with its name, so the same inputs always give the same name.
        var sources: [String: String] = [key: initial], queue = [initial]
        while let next = queue.popLast() {
            for other in rewritten.sorted() where sources[other] == nil && SwiftText.mentions(constantName(other), in: next) {
                guard let made = declarations.constants[other].flatMap({ initialText(of: $0, in: declarations) }) else { continue }
                sources[other] = made
                queue.append(made)
            }
        }
        // Named by its key, the file of a private one included: two files' `private let spacing` are two values.
        let name = key.replacingOccurrences(of: "\t", with: ".") + "#" + SwiftSource.digest(sources.keys.sorted().map { $0 + "=" + sources[$0]! }.joined(separator: "\n"))
        let quoted = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return (start..<end, "var \(variable.name): \(variable.type) { LampConstants.value(\"\(quoted)\") { () -> \(variable.type) in \(initial) } }")
    }

    /// The changed constants and every constant whose starting value names one of them, however far back.
    private static func withDependents(_ changed: [String], in declarations: SwiftSource.Declarations) -> [String] {
        var set = Set(changed), grew = true
        while grew {
            grew = false
            for (key, variable) in declarations.constants where !set.contains(key) {
                guard let made = initialText(of: variable, in: declarations) else { continue }
                if set.contains(where: { SwiftText.mentions(constantName($0), in: made) }) { set.insert(key); grew = true }
            }
        }
        return set.sorted()
    }

    /// A constant's own name, from its key ("Type<tab>name", "@File.swift" after a private one's).
    private static func constantName(_ key: String) -> String {
        String(key.split(separator: "\t", omittingEmptySubsequences: false).last?.prefix { $0 != "@" } ?? "")
    }

    /// A constant's name as people read it: "Car.topSpeed", or "topSpeed" for a global.
    private static func displayName(_ key: String) -> String {
        let owner = key.split(separator: "\t", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        return (owner.isEmpty ? "" : owner + ".") + constantName(key)
    }

    /// Whether a value of this type can hold an object: one of the app's own classes named in it, a type of the app's
    /// named in it that holds one, as far down as it goes, or any type that isn't a plain value Swift or SwiftUI has
    /// (an object of Lamp's building blocks, `LampAPI`, or of the system's). Made again, such an object would be a
    /// second one beside the one the open app already holds, and what's done to one wouldn't reach the other.
    static func holdsObject(_ type: String, classes: Set<String>, layout: [String: [String]], seen: inout Set<String>) -> Bool {
        let names = try! NSRegularExpression(pattern: #"[A-Za-z_]\w*(\.[A-Za-z_]\w*)*"#)
        for match in names.matches(in: type, range: NSRange(type.startIndex..., in: type)) {
            let range = Range(match.range, in: type)!
            // A tuple's or a case's label (`(width: Int, height: Int)`) names an element, not a type: it comes just
            // after `(` or `,` and before a colon. A dictionary's key comes after `[`, so it's still read.
            let before = type[..<range.lowerBound].last(where: { !$0.isWhitespace })
            let after = type[range.upperBound...].first(where: { !$0.isWhitespace })
            if after == ":", before == "(" || before == "," { continue }
            var name = String(type[range])
            // A metatype is a value, whatever it names.
            for suffix in [".Type", ".Protocol"] where name.hasSuffix(suffix) { name.removeLast(suffix.count) }
            let last = String(name.split(separator: ".").last ?? "")
            if classes.contains(name) || classes.contains(last) { return true }
            if let members = layout[name] ?? layout[last] {
                guard seen.insert(name).inserted else { continue }
                for member in members {
                    guard let colon = member.range(of: ": ") else { continue }
                    // Lamp's own spare places hold only properties moved into them, which the layout lists as the
                    // type's own fields with their own types.
                    if member[..<colon.lowerBound].split(separator: "\t").last?.hasPrefix("__lamp") == true { continue }
                    if holdsObject(String(member[colon.upperBound...]), classes: classes, layout: layout, seen: &seen) { return true }
                }
                continue
            }
            if !plainValues.contains(last) && !seen.contains(name) { return true }
        }
        return false
    }

    /// Value types a constant is made of that hold no object of their own.
    private static let plainValues: Set<String> = [
        "Swift", "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "Double", "Float",
        "Float16", "CGFloat", "Bool", "String", "Substring", "Character", "StaticString", "Array", "Dictionary", "Set",
        "Optional", "Range", "ClosedRange", "Void", "Never", "TimeInterval", "Date", "URL", "UUID", "Decimal", "Data",
        "Duration", "SIMD2", "SIMD3", "SIMD4", "SIMD8", "SIMD16", "simd_float2", "simd_float3", "simd_float4",
        "simd_float4x4", "simd_quatf", "CGPoint", "CGSize", "CGRect", "CGVector", "CGAffineTransform", "Color", "Font",
        "Angle", "UnitPoint", "EdgeInsets", "Edge", "Alignment", "HorizontalAlignment", "VerticalAlignment", "Animation",
        "Gradient", "LinearGradient", "RadialGradient", "AngularGradient", "Image", "Text", "LocalizedStringKey",
        "KeyboardShortcut", "KeyEquivalent", "EventModifiers", "ContentMode",
    ]

    /// The text of a property's starting value, when it has one.
    private static func initialText(of variable: SwiftSource.Variable, in declarations: SwiftSource.Declarations) -> String? {
        let binding = declarations.bindings[variable.binding]
        guard let entry = binding.entries.first(where: { $0.name == variable.name }), let initial = entry.initial,
              let text = SwiftSource.Text(path: initial.start.file), let start = text.offset(initial.start), let end = text.tokenEnd(initial.last) else { return nil }
        return text.slice(start, end)
    }

    /// One declaration (`var a = 1, b: Int = 2`, with what's written before it) rewritten: the names moving into
    /// spares each become a computed property of their own, on lines after what stays stored. Answers the bytes it
    /// replaces and their replacement, or nil when one can't move (no type or starting value, or a starting value a
    /// struct can't keep, or a @Published one in a class whose places aren't published, or `let` in a view).
    private static func rewrite(_ binding: SwiftSource.Binding, items: [(type: String, name: String, slot: Slot, published: Bool, isNew: Bool)],
                                in text: SwiftSource.Text, declarations: SwiftSource.Declarations,
                                cases: [String: Set<String>]) -> (Range<Int>, String)? {
        guard let start = text.offset(binding.start), let end = text.tokenEnd(binding.last), let type = items.first?.type else { return nil }
        let variables = binding.entries.map { declarations.variables[type + "\t" + $0.name] }
        guard variables.allSatisfy({ $0 != nil }) else { return nil }
        let all = variables.compactMap { $0 }
        // What's written before the keyword: attributes (the compiler knows where each is) and access words.
        let attributes = all[0].attributes
        let first = attributes.compactMap { text.offset($0.start) }.min().map { min($0, start) } ?? start
        let keyword = text.slice(start, start + 3)
        let prefix = text.slice(first, start)
        // The same with a wrapper's attribute taken out, for a computed property, which can't carry one.
        var plain = Array(text.bytes[first..<start])
        for attribute in attributes.sorted(by: { ($0.start.line, $0.start.column) > ($1.start.line, $1.start.column) })
        where ["Published", "State", "ObservationIgnored"].contains(attribute.name) {
            guard let from = text.offset(attribute.start), let to = text.tokenEnd(attribute.last), from >= first, to <= start else { return nil }
            plain.removeSubrange((from - first)..<(to - first))
        }
        let plainPrefix = String(decoding: plain, as: UTF8.self).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        // Each name's own text, from its name to the comma before the next (or the declaration's end).
        guard let starts = Optional(all.compactMap { text.offset($0.position) }), starts.count == all.count else { return nil }
        var pieces: [String] = []
        for (index, from) in starts.enumerated() {
            var to = index + 1 < starts.count ? starts[index + 1] : end
            if index + 1 < starts.count {
                to -= 1
                while to > from, text.bytes[to] != UInt8(ascii: ",") { to -= 1 }
            }
            pieces.append(text.slice(from, to).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        // The line's indent, for the lines added after it.
        var lineStart = first
        while lineStart > 0, text.bytes[lineStart - 1] != UInt8(ascii: "\n") { lineStart -= 1 }
        let indent = String(text.slice(lineStart, first).prefix { $0 == " " || $0 == "\t" })
        var stays: [String] = [], lines: [String] = []
        for (index, variable) in all.enumerated() {
            guard let item = items.first(where: { $0.name == variable.name }) else {
                // Stays stored. A name that took its type from a later one in the list gets it written out.
                let piece = pieces[index]
                stays.append(piece.contains(":") || piece.contains("=") ? piece : piece + ": " + variable.type)
                continue
            }
            guard !variable.special, let made = computed(variable, item: item, keyword: keyword, declarations: declarations, cases: cases) else { return nil }
            if item.published == false, item.slot.holder ?? .object == .object, attributes.contains(where: { $0.name == "Published" }) { return nil }
            lines += made.map { (plainPrefix.isEmpty ? "" : plainPrefix + " ") + $0 }
        }
        let kept = stays.isEmpty ? [] : [prefix + keyword + " " + stays.joined(separator: ", ")]
        return (first..<end, (kept + lines).joined(separator: "\n" + indent))
    }

    /// A moved property as the computed one that keeps it in its spare, from `var` on (and for a view's state, the
    /// binding its `$name` becomes).
    private static func computed(_ variable: SwiftSource.Variable, item: (type: String, name: String, slot: Slot, published: Bool, isNew: Bool),
                                 keyword: String, declarations: SwiftSource.Declarations, cases: [String: Set<String>]) -> [String]? {
        let name = variable.name, declared = variable.type, type = item.type
        let isLet = keyword == "let"
        let optional = declared.hasSuffix("?") || declared.hasPrefix("Optional<")
        guard let initial = initialText(of: variable, in: declarations) ?? (optional ? "nil" : nil) else { return nil }
        switch item.slot.holder ?? .object {
        case .object:
            let place = place(item.slot.index, in: type)
            let first = !isLiteral(initial) ? "let v: \(declared) = \(initial); \(place) = LampSpare(v); return v" : "return \(initial)"
            let getter = "get { if let v = \(place)?.value as? \(declared) { return v }; \(first) }"
            let setter = isLet ? "" : " set { \(place) = LampSpare(newValue) }"
            return ["var \(name): \(declared) { \(getter)\(setter) }"]
        case .value:
            guard isSteady(initial, type: declared, cases: item.isNew ? cases : [enumName(item.slot.type): Set(item.slot.cases ?? [])]) else { return nil }
            if let taken = item.slot.initial, taken != initial { return nil }
            let place = place(in: type, holder: .value)
            let getter = "get { if let v = \(place).field(\"\(name)\") as? \(declared) { return v }; return \(initial) }"
            // Set back to its starting value, it's as if never set, so two values alike compare alike.
            let setter = isLet ? "" : " set { \(place) = LampSpare.setting(\"\(name)\", to: newValue, initial: { () -> \(declared) in \(initial) }(), in: \(place)) }"
            return ["var \(name): \(declared) { \(getter)\(setter) }"]
        case .view:
            guard !isLet else { return nil }
            let box = place(in: type, holder: .view)
            let read = "\(box).get(\"\(name)\") { () -> \(declared) in \(initial) }"
            return ["var \(name): \(declared) { get { \(read) } nonmutating set { \(box).set(\"\(name)\", newValue) } }",
                    "var __lampBinding_\(name): Binding<\(declared)> { Binding(get: { \(read) }, set: { \(box).set(\"\(name)\", $0) }) }"]
        }
    }

    /// A class's spare place: named after the class, since a subclass has its own beside those it inherits.
    static func place(_ index: Int, in type: String) -> String {
        "__lampSpare_\(simpleName(type))_\(index)"
    }

    /// A struct's one spare, or a view's state box.
    static func place(in type: String, holder: Holder) -> String {
        holder == .view ? "__lampState_\(simpleName(type))" : "__lampSpare_\(simpleName(type))"
    }

    /// The enum a property's type names, an optional's included.
    private static func enumName(_ type: String) -> String { type.hasSuffix("?") ? String(type.dropLast()) : type }

    private static func simpleName(_ type: String) -> String { type.split(separator: ".").last.map(String.init) ?? type }

    /// A starting value that's the same every time it's worked out: answered as it is until something is set.
    /// Anything else (`.now`, a call, another property) is worked out once and kept, as a stored property would be.
    private static func isLiteral(_ value: String) -> Bool {
        value.range(of: #"^(-?[0-9][0-9_.eE+-]*|true|false|nil|\[\]|\[:\]|"[^"\\]*")$"#, options: .regularExpression) != nil
    }

    /// A struct can't keep a value the first time it's read (its getter can't change it), so its new property's
    /// starting value must come out the same every time: a literal, an empty collection (`[Item]()`), or one of
    /// the app's own enum's cases (`.sedan`, by the enum's cases in `cases`). Nothing judged by its spelling alone:
    /// `Session()` may make something new each time, and `.shared` or `.now` may be worked out on each read.
    private static func isSteady(_ value: String, type: String, cases: [String: Set<String>]) -> Bool {
        if isLiteral(value) || value.range(of: #"^\[[\w.<>, :?]+\]\(\)$"#, options: .regularExpression) != nil { return true }
        let enumName = enumName(type)
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].isEmpty || parts[0] == Substring(enumName) else { return false }
        return cases[enumName]?.contains(String(parts[1])) == true
    }

}

/// Reading Swift source only as far as Lamp's live rewrites need: where a string or a comment ends, and which brace
/// closes which, so text inside them is never taken for code.
enum SwiftText {
    /// The index just past the string literal or comment that starts at `index`, or nil when none does. Strings
    /// may be raw (`#"…"#`, any number of `#`) and multiline (`"""…"""`); escapes count only in non-raw ones.
    static func skip(_ chars: [Character], at index: Int) -> Int? {
        guard index < chars.count else { return nil }
        if chars[index] == "/", index + 1 < chars.count {
            if chars[index + 1] == "/" {
                var end = index
                while end < chars.count, chars[end] != "\n" { end += 1 }
                return end
            }
            if chars[index + 1] == "*" {
                var end = index + 2, depth = 1
                while end < chars.count, depth > 0 {
                    if chars[end] == "/", end + 1 < chars.count, chars[end + 1] == "*" { depth += 1; end += 2; continue }
                    if chars[end] == "*", end + 1 < chars.count, chars[end + 1] == "/" { depth -= 1; end += 2; continue }
                    end += 1
                }
                return end
            }
        }
        var hashes = 0, at = index
        while at < chars.count, chars[at] == "#" { hashes += 1; at += 1 }
        guard at < chars.count, chars[at] == "\"" else { return nil }
        let multiline = at + 2 < chars.count && chars[at + 1] == "\"" && chars[at + 2] == "\""
        let quotes = multiline ? 3 : 1
        var end = at + quotes
        while end < chars.count {
            // An escape: `\` and, in a raw string, its hashes. `\(…)` is an interpolation, code with strings of its
            // own, read to its closing parenthesis.
            if chars[end] == "\\", end + hashes < chars.count, chars[(end + 1)..<(end + 1 + hashes)].allSatisfy({ $0 == "#" }) {
                let after = end + 1 + hashes
                if after < chars.count, chars[after] == "(" { end = interpolationEnd(chars, from: after + 1); continue }
                if hashes == 0 { end += 2; continue }
            }
            if !multiline, chars[end] == "\n" { return end }
            if chars[end] == "\"", end + quotes - 1 < chars.count, chars[end..<(end + quotes)].allSatisfy({ $0 == "\"" }) {
                let after = end + quotes
                if after + hashes <= chars.count, chars[after..<(after + hashes)].allSatisfy({ $0 == "#" }) { return after + hashes }
            }
            end += 1
        }
        return end
    }

    /// Just past the `)` that closes an interpolation whose code starts at `index`.
    private static func interpolationEnd(_ chars: [Character], from index: Int) -> Int {
        var depth = 1, at = index
        while at < chars.count {
            if let skipped = skip(chars, at: at) { at = skipped; continue }
            if chars[at] == "(" { depth += 1 } else if chars[at] == ")" { depth -= 1; if depth == 0 { return at + 1 } }
            at += 1
        }
        return at
    }

    /// Whether `identifier` is used in `text`'s code (not in a string's text or a comment, nor as part of a longer
    /// name), the code of a string's interpolations included.
    static func mentions(_ identifier: String, in text: String) -> Bool {
        let code = codeOnly(Array(text))
        return !identifier.isEmpty && replacing(identifier: identifier, with: "\u{0}", in: code) != code
    }

    /// `chars` with comments and strings' text taken out, and the code of strings' interpolations kept.
    static func codeOnly(_ chars: [Character]) -> String {
        var out = "", at = 0
        while at < chars.count {
            guard let end = skip(chars, at: at) else { out.append(chars[at]); at += 1; continue }
            out += " "
            if chars[at] != "/" {
                // A string: what's inside each `\(…)` (`\#(…)` in a raw one) is code.
                var hashes = 0
                while at + hashes < end, chars[at + hashes] == "#" { hashes += 1 }
                var inside = at + hashes
                while inside < end {
                    if chars[inside] == "\\", inside + 1 + hashes < end,
                       chars[(inside + 1)..<(inside + 1 + hashes)].allSatisfy({ $0 == "#" }), chars[inside + 1 + hashes] == "(" {
                        let open = inside + 2 + hashes, close = interpolationEnd(chars, from: open)
                        out += codeOnly(Array(chars[open..<max(open, close - 1)])) + " "
                        inside = close
                        continue
                    }
                    inside += hashes == 0 && chars[inside] == "\\" ? 2 : 1
                }
            }
            at = end
        }
        return out
    }

    /// `text` with each use of `identifier` in its code (not in a string or comment, nor part of a longer name)
    /// replaced.
    static func replacing(identifier: String, with replacement: String, in text: String) -> String {
        let chars = Array(text), target = Array(identifier)
        func isName(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" || c == "$" }
        var out = "", at = 0
        while at < chars.count {
            if let skipped = skip(chars, at: at) { out += String(chars[at..<skipped]); at = skipped; continue }
            if chars[at] == target.first, at + target.count <= chars.count, Array(chars[at..<(at + target.count)]) == target,
               at == 0 || !isName(chars[at - 1]), at + target.count == chars.count || !isName(chars[at + target.count]) {
                out += replacement
                at += target.count
                continue
            }
            out.append(chars[at])
            at += 1
        }
        return out
    }
}
