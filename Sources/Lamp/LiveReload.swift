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
    /// The libraries of earlier changes: each is mapped into the app once loaded, so the files may go, and
    /// otherwise a long session leaves one for every change tried. All of them once the app is installed.
    static func forgetLibraries(_ project: LampProject, but keeping: URL? = nil) {
        for path in (try? FileManager.default.contentsOfDirectory(atPath: folder(project).path)) ?? []
        where path.hasPrefix("hot-") && path.hasSuffix(".dylib") && path != keeping?.lastPathComponent {
            AppFolder.remove(folder(project).appendingPathComponent(path), in: project.dir)
        }
    }

    static func markRunning(_ project: LampProject, from: URL? = nil) {
        if from != nil { forgetLibraries(project) }
        try? AppFolder.copy(from ?? sources(project), to: running(project), in: project.dir)
        try? AppFolder.write(inputs(project), to: runningInputs(project), in: project.dir)
        // What it now runs was most often read already, as the live copy a change was tried with (`Analyses`): its
        // layout is kept, so the next change doesn't have the compiler print it again.
        if let known = analyses.entry(Analyses.digest(of: running(project), module: project.exe, macOS: Template.macMinimum(project))) {
            keepLayout(known.layout, for: project)
        } else {
            AppFolder.remove(runningLayout(project), in: project.dir)
        }
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
                ((try? fm.subpathsOfDirectory(atPath: project.dir.appendingPathComponent(folder).path)) ?? []).sorted()
                    .filter { !$0.hasPrefix(".") && !$0.contains("/.") }.map { "\(folder)/\($0)" }
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
        let macOS = Template.macMinimum(project)
        if let known = analyses.entry(Analyses.digest(of: running(project), module: project.exe, macOS: macOS)) { return known.oldCode }
        return await dump(of: running(project), in: project, module: project.exe, macOS: macOS).map(oldCodeUses(inDump:))
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
        for path in gone where ownFiles.contains((path as NSString).lastPathComponent) {
            return .reopen("Lamp's own building blocks changed")
        }
        if AppFile.text(runningInputs(project), in: project) != inputs(project) {
            return .reopen("the package, the app's settings, its icon, or its widget or Share item changed")
        }
        var changed: [String] = []
        for (path, url) in built.sorted(by: { $0.key < $1.key }) {
            guard let new = AppFile.text(url, in: project) else { return .reopen("\(path) couldn't be read") }
            guard let old = open[path].flatMap({ AppFile.text($0, in: project) }) else {
                // Added: its types are new to the app, so their layout is whatever it says.
                changed.append(path)
                continue
            }
            guard new != old else { continue }
            if ownFiles.contains((path as NSString).lastPathComponent) {
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
            changed = built.keys.sorted().filter { !ownFiles.contains(($0 as NSString).lastPathComponent) }
        }
        return changed.isEmpty && gone.isEmpty ? .unchanged : .reload(changed)
    }

    /// Whether the whole new code type-checks and leaves every type the open app has holding what it did:
    /// nil when so, with the new code's layout to keep once it's gone in; else why not. The whole module, not
    /// just the changed files: a changed function can change what a property in another file is inferred to
    /// hold, and an unchanged caller can stop compiling, which compiling the changed files alone wouldn't show
    /// (then the usual build runs and the agent sees its errors). The open app's layout is kept from the last
    /// time, so only the new code is type-checked, alongside the changed files' compile.
    /// The layout's lines that aren't a type's members, by the control character their group begins with: what's
    /// read at launch (`SwiftSource.launchEntries`), constants' values (`constantEntries`), typealiases (`aliasGroup`)
    /// and what's declared (`declarationGroup`). Each is compared its own way, never as a type's fields.
    static func isGroup(_ type: String) -> Bool { (type.first?.asciiValue ?? 32) < 32 }

    /// A private type is keyed with its file (`Row@A.swift`, each part of a nested one), since two files may each
    /// declare one of the name and the two are two types at run time; this is the key as Swift names the type.
    static func bare(_ key: String) -> String { key.replacingOccurrences(of: #"@[^\t]*?\.swift"#, with: "", options: .regularExpression) }
    /// Layout entries with every type named bare, the groups' (an alias's owner, a shape's type, a conformance's)
    /// included, for what compares them with types as the code names them (a field's type, a use in old code);
    /// two private twins' fields merge, which errs toward reopening.
    static func bared(_ entries: [String]) -> [String] { entries.map(bare) }

    /// The kinds of entry in a layout besides a type's own fields and cases, each under a control character so none
    /// reads as a type's name: what's read at launch (`SwiftSource.launchEntries`); a constant's value
    /// (`constantEntries`); a typealias and what it names; what's declared (functions, initializers, computed
    /// properties, conformances, a member's `@objc`); what a `some`-returning member builds; where a private type is
    /// declared (its mangled name carries its file, so one moved is another type at run time); and a class's
    /// initializers and finality (each initializer has a method descriptor, a final class's too, so one added or
    /// changed reshapes the method table); and a type's shape (`shapeGroup`): whether it's a struct, class, enum or
    /// actor, `@objc` and `indirect` on an enum, a class's superclass, and a protocol's requirement signature (what
    /// it inherits, `AnyObject`, its associated types' constraints), each of which lays out values, objects, method
    /// tables or witness tables differently while the type holds the same fields. An entry is the group's mark, a
    /// tab, and its parts tab-separated.
    enum Group: String {
        case launch = "\u{1}launch", constant = "\u{2}constant", alias = "\u{3}alias", declared = "\u{5}declared"
        case opaque = "\u{6}opaque", place = "\u{7}place", inits = "\u{8}inits", shape = "\u{e}shape"
        func entry(_ parts: String...) -> String { ([rawValue] + parts).joined(separator: "\t") }
        /// The entry's parts when it's of this group, else nil.
        func parts(of entry: String) -> [String]? {
            guard entry.hasPrefix(rawValue + "\t") else { return nil }
            return entry.dropFirst(rawValue.count + 1).split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        }
        /// The entries of this group, each as its parts.
        func parts(in entries: [String]) -> [[String]] { entries.compactMap(parts(of:)) }
        /// What an entry of this group is about, by which one kept from the open app's layout is told to be gone from
        /// the new one: an alias's name, a constant's, an opaque member's, a private type's with its file, a class's
        /// for its initializers, a type's for its shape. Nil for what's read at launch and what's declared, which
        /// are compared whole.
        func subject(of entry: String) -> String? {
            guard let parts = parts(of: entry), let first = parts.first else { return nil }
            switch self {
            case .alias: return first.components(separatedBy: " = ").first
            case .constant: return String(parts.joined(separator: "\t").prefix { $0 != ":" })
            case .inits: return first.hasSuffix(".final") ? String(first.dropLast(6)) : first.range(of: ".init").map { String(first[..<$0.lowerBound]) }
            case .place: return parts.joined(separator: "\t")
            case .opaque, .shape: return first
            case .launch, .declared: return nil
            }
        }
    }
    /// Lamp's own files in an app's sources, never the app's to change nor read for its layout.
    static let ownFiles: Set<String> = ["LampSupport.swift", Template.sceneSupportFile]

    /// A layout's entries by the type (or group) each belongs to, in order.
    static func byType(_ entries: [String]) -> [String: [String]] {
        Dictionary(grouping: entries, by: { String($0.prefix { $0 != "\t" }) })
    }

    static let aliasGroup = Group.alias.rawValue, declarationGroup = Group.declared.rawValue, opaqueGroup = Group.opaque.rawValue
    static let placeGroup = Group.place.rawValue, initsGroup = Group.inits.rawValue, shapeGroup = Group.shape.rawValue

    /// The SwiftData model classes in a layout, each with the file that declares it (`SwiftSource.launchEntries`):
    /// a change that compiles that file, whatever it changed, makes the model's key paths over again.
    static func modelFiles(inLayout layout: [String]) -> [(name: String, file: String)] {
        Group.launch.parts(in: layout).compactMap { parts in
            guard let what = parts.first, what.hasPrefix("model "), let at = what.firstIndex(of: "@"), let colon = what.range(of: ": ") else { return nil }
            return (String(what[what.index(what.startIndex, offsetBy: 6)..<at]), String(what[what.index(after: at)..<colon.lowerBound]))
        }
    }

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
            Dictionary(Group.alias.parts(in: entries).compactMap { parts -> (String, String)? in
                guard let alias = parts.first, let equals = alias.range(of: " = ") else { return nil }
                return (String(alias[..<equals.lowerBound]), String(alias[equals.upperBound...]))
            }, uniquingKeysWith: { first, _ in first })
        }
        for (name, was) in aliases(before).sorted(by: { $0.key < $1.key }) {
            if let is_ = aliases(now)[name], is_ != was { return ("the typealias \(name) changed from \(was) to \(is_)", nil) }
        }
        // A type's shape: a struct become a class (or back) lays its values out as objects, an enum made `@objc` or
        // `indirect` changes how its values are kept, a class under another superclass puts its fields and methods
        // elsewhere, and a protocol whose requirement signature changed (`: AnyObject`, an associated type's
        // constraint) lays its witness tables out differently. All while the type holds the same fields, so said
        // here, and before a class's finality, which a new superclass changes too. Compared only where both layouts
        // say: one kept by an earlier Lamp says nothing of shapes.
        for (name, was) in shapes(before).sorted(by: { $0.key < $1.key }) {
            guard let is_ = shapes(now)[name], is_ != was else { continue }
            if name.hasPrefix("protocol ") { return ("the protocol \(name.dropFirst(9))'s requirements changed in kind (\(was) to \(is_)), and the open app's witness tables were laid out for what they were", nil) }
            return ("\(name) is \(described(is_)) now, where the open app's is \(described(was))", nil)
        }
        // A private type's name carries its file: moved to another, it's a new type to the runtime, so a value the
        // open app made is no longer one (`as? Helper` fails) though its layout is the same.
        // Two files may each have a private type of one name: each name maps to every file declaring it, and a
        // move is a file that no longer declares it beside one that newly does.
        func places(_ entries: [String]) -> [String: Set<String>] {
            Dictionary(Group.place.parts(in: entries).compactMap { $0.count == 2 ? ($0[0], Set([$0[1]])) : nil }, uniquingKeysWith: { $0.union($1) })
        }
        for (name, was) in places(before).sorted(by: { $0.key < $1.key }) {
            guard let is_ = places(now)[name], let from = was.subtracting(is_).sorted().first, let to = is_.subtracting(was).sorted().first else { continue }
            return ("\(name) is private and moved from \(from) to \(to), which makes it another type for the values the open app holds", nil)
        }
        func shapes(_ entries: [String]) -> [String: String] {
            Dictionary(Group.shape.parts(in: entries).compactMap { $0.count == 2 ? ($0[0], $0[1]) : nil }, uniquingKeysWith: { first, _ in first })
        }
        // "a struct", "an @objc enum", "a class under NSObject", in the words of the shape entry.
        func described(_ shape: String) -> String {
            var words = shape.split(separator: " ").map(String.init)
            var under: String?
            if let colon = words.firstIndex(of: ":") { under = words[(colon + 1)...].joined(separator: " "); words.removeSubrange(colon...) }
            let kind = words.removeFirst()
            let article = (words.first ?? kind).first.map { "aeio".contains($0) ? "an " : "a " } ?? "a "
            return article + (words + [kind]).joined(separator: " ") + (under.map { " under " + $0 } ?? "")
        }
        // A class the open app has whose initializers changed: each is in its method table, so the runtime would
        // refuse the change once compiled and sent; said here, before either.
        func inits(_ entries: [String]) -> [String: Set<String>] {
            Dictionary(Group.inits.parts(in: entries).compactMap { parts -> (String, Set<String>)? in
                guard let rest = parts.first else { return nil }
                if rest.hasSuffix(".final") { return (String(rest.dropLast(6)), [rest]) }
                guard let dot = rest.range(of: ".init") else { return nil }
                return (String(rest[..<dot.lowerBound]), [rest])
            }, uniquingKeysWith: { $0.union($1) })
        }
        for (owner, was) in inits(before).sorted(by: { $0.key < $1.key }) {
            guard let is_ = inits(now)[owner], is_ != was, now.contains(owner + "\t") else { continue }
            if was.contains(owner + ".final") != is_.contains(owner + ".final") {
                return ("\(owner) is \(is_.contains(owner + ".final") ? "final now" : "no longer final (something subclasses it)"), and its methods would go through a table the open app's class doesn't have", nil)
            }
            return ("an initializer of \(owner) was added, taken away or changed, and a class's initializers are in its method table", nil)
        }
        // What a `some`-returning member builds is its type, which the open app's witness tables and callers were
        // laid out for; one that builds another type under the same name, or from other calls where the type can't
        // be printed, returns what they can't take. A value beginning "~" is a digest of the body, not a type.
        func opaque(_ entries: [String]) -> [String: String] {
            Dictionary(Group.opaque.parts(in: entries).compactMap { $0.count == 2 ? ($0[0], $0[1]) : nil }, uniquingKeysWith: { first, _ in first })
        }
        for (name, was) in opaque(before).sorted(by: { $0.key < $1.key }) {
            guard let is_ = opaque(now)[name], is_ != was else { continue }
            if !was.hasPrefix("~"), !is_.hasPrefix("~") { return ("\(name) returns a \(is_) now, where the open app's returned a \(was)", nil) }
            return ("\(name) returns another kind of value now (some …), which what the open app made can't take", nil)
        }
        // Type by type, each "Owner<tab>member": a type the open app has must hold just what it did, in order;
        // a new type (a new view with its own state) is the library's to lay out. A type taken away keeps its
        // objects and their code in the open app, and the new code doesn't touch them: whatever held one either
        // changed what it holds (and is caught here) or was taken away too.
        let old = byType(before), new = byType(now)
        for (type, members) in old.sorted(by: { $0.key < $1.key }) where !isGroup(type) || type == Group.launch.rawValue {
            guard let current = new[type] else { continue }
            if type == Group.launch.rawValue, current != members {
                let what = (current.first { !members.contains($0) } ?? members.first { !current.contains($0) } ?? "")
                    .split(separator: "\t").last.map { String($0.prefix { $0 != ":" }) } ?? ""
                if what.hasPrefix("model ") { return ("the file of the SwiftData model \(what.dropFirst(6).prefix { $0 != "@" }) changed, and its data is found by key paths the open app made", nil) }
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
        // Each group's entries by what they're about (`Group.subject`): one kept when the new code has no entry of
        // that group about that subject (a group of its own: an alias named Mood says nothing of the shape Mood had);
        // what's read at launch and what's declared are the new code's whole.
        func keyed(_ entry: String) -> String? {
            Group(rawValue: String(entry.prefix { $0 != "\t" })).flatMap { group in group.subject(of: entry).map { group.rawValue + "\t" + $0 } }
        }
        let subjects = Set(now.compactMap(keyed))
        let kept = now + before.filter { entry in
            let group = String(entry.prefix { $0 != "\t" })
            guard let key = keyed(entry) else { return new[group] == nil }
            return !subjects.contains(key)
        }
        return (nil, kept)
    }

    /// The enums that only gained cases at the end (`LiveSlots.casesAdded`), which the layout check let through.
    static func grownEnums(before: [String], after: [String]) -> [String] {
        let old = byType(before), new = byType(after)
        return old.keys.sorted().filter { type in
            guard !isGroup(type), let current = new[type], current != old[type] else { return false }
            return LiveSlots.casesAdded(type, old[type]!, current)
        }
    }

    /// Why a grown enum can't go in, if it can't: something the app keeps holds it other than as itself or in a
    /// plain collection of it (an optional, another enum's case, a wrapper), where Swift gives its unused numbers
    /// meanings that a new case takes over. Looked for in every stored field, static and global of the new code,
    /// and in what the spares keep, whose types the compiler no longer sees. A value type of the app's that carries
    /// the enum by value (a struct with a field of it, an enum with a payload of it, through any depth of such
    /// types) lends its own optional and payload cases the enum's unused numbers too, so what holds such a carrier
    /// is held to the same plain forms; a struct with a spare of Lamp's isn't one, since the spare's `Any?` gives
    /// Swift more unused numbers than the enum does.
    @MainActor static func enumsHeld(_ project: LampProject, grown: [String]) async -> String? {
        guard let made = await analysis(of: sources(project), in: project, module: project.exe, macOS: Template.macMinimum(project)) else {
            return "the compiler couldn't say what holds the enums that grew"
        }
        return enumsHeld(grown: grown, held: made.held, spares: LiveSlots.mapping(project))
    }

    /// The same, from an analysis's held members (the layout with statics and globals) and what the spares keep.
    static func enumsHeld(grown: [String], held layout: [String], spares: [String: [String: LiveSlots.Slot]]) -> String? {
        // Types by the layout's keys (a private one with its file), the enums by their bare names, as fields name them.
        let entries = layout, grown = grown.map(bare)
        let held = entries.compactMap { entry -> (String, String)? in
            guard !isGroup(String(entry.prefix { $0 != "\t" })), let colon = entry.range(of: ": ") else { return nil }
            return (String(entry.prefix { $0 != "\t" }), String(entry[colon.upperBound...]))
        }
        // What the spares keep (properties added while the app was open), by type, name and kind: a spare holds its
        // value as any value, under the metadata the app's code had when it was set.
        let inSpares = spares.flatMap { type, properties in properties.map { (type, $0.key, $0.value.type) } }.sorted { ($0.0, $0.1) < ($1.0, $1.1) }
        // A value of the enum could hide in what holds anything at all, where its type can't be seen: a value of
        // any type, or of any type conforming to a protocol the enum conforms to.
        let conformed = conformances(inLayout: entries)
        for type in grown {
            for (owner, kind) in held + inSpares.map { ($0.0, $0.2) } {
                if let box = existential(in: kind, holding: type, conformances: conformed) {
                    return "\(owner.isEmpty ? "a global" : owner) keeps values of any type (\(box)), which may hold \(type)"
                }
            }
        }
        // The classes, by their keys as the layout has them, so a nested class of one name doesn't stand for a
        // struct of the same name at the top, nor one file's private class for another's struct; and each generic
        // type's parameters (`generic<Element>` in its shape), which are no alias of anything however they're named.
        var classes = Set<String>(), generics: [String: Set<String>] = [:]
        for parts in Group.shape.parts(in: entries) where parts.count == 2 {
            if parts[1].hasPrefix("class") || parts[1].hasPrefix("actor") { classes.insert(parts[0]) }
            if let open = parts[1].range(of: "generic<"), let close = parts[1][open.upperBound...].firstIndex(of: ">") {
                generics[parts[0]] = Set(parts[1][open.upperBound..<close].split(separator: ",").map { String($0.split(separator: ":").first ?? "").trimmingCharacters(in: .whitespaces) })
            }
        }
        let spared = Set(entries.compactMap { entry -> String? in
            let parts = entry.split(separator: "\t", maxSplits: 1)
            return parts.count == 2 && (parts[1].hasPrefix("__lampSpare_") || parts[1].hasPrefix("__lampState_")) ? String(parts[0]) : nil
        })
        let word = try! NSRegularExpression(pattern: #"[A-Za-z_]\w*(\.[A-Za-z_]\w*)*"#)
        func last(_ name: String) -> String { String(name.split(separator: ".").last ?? "") }
        // A kind as a field prints it may name a typealias (`Choice`, for `Picky?`): each is written out as what it
        // names, wrappers and all, until none is left, so what holds the enum is judged by the type itself. A name
        // that is a type's of the app's is that type, not a nested alias of the same short name elsewhere.
        func expanded(_ kind: String, in owner: String) -> String {
            var kind = kind
            // A type's own generic parameters, and those of every type it's declared inside, which it uses too.
            let parts = owner.split(separator: ".")
            let own = Set((0..<parts.count).flatMap { generics[parts[...$0].joined(separator: ".")] ?? [] })
            for _ in 0..<8 {
                var changed = false
                for m in word.matches(in: kind, range: NSRange(kind.startIndex..., in: kind)).reversed() {
                    let range = Range(m.range, in: kind)!, name = String(kind[range])
                    guard !own.contains(name), !conformed.types.contains(name), let target = conformed.aliases[name], target != name else { continue }
                    kind.replaceSubrange(range, with: target)
                    changed = true
                }
                if !changed { break }
            }
            return kind
        }
        // The layout's own keys only: the bare copies merge twins, which are judged each on its own.
        let own = Set(entries.compactMap { entry -> String? in
            guard !isGroup(entry), let tab = entry.firstIndex(of: "\t") else { return nil }
            return String(entry[..<tab])
        })
        let fields = Dictionary(conformed.fields.filter { own.contains($0.key) }.map { type, kinds in (type, kinds.map { expanded($0, in: type) }) }, uniquingKeysWith: +)
        let holders = held.map { ($0.0, expanded($0.1, in: $0.0)) }
        // What's found is named bare, as a field's type names it; what carries it is judged by its own key.
        func carriers(of enumName: String) -> [String] {
            var found = Set([enumName]), grew = true
            while grew {
                grew = false
                for (type, kinds) in fields where !found.contains(bare(type)) && !classes.contains(type) && !spared.contains(type) {
                    for kind in kinds {
                        let names = word.matches(in: kind, range: NSRange(kind.startIndex..., in: kind)).map { String(kind[Range($0.range, in: kind)!]) }
                        if names.contains(where: { found.contains($0) || found.contains(last($0)) }) { found.insert(bare(type)); grew = true; break }
                    }
                }
            }
            return found.sorted()
        }
        for type in grown {
            for carrier in carriers(of: type) {
                let name = NSRegularExpression.escapedPattern(for: carrier)
                let mention = try! NSRegularExpression(pattern: #"(?<![\w.])"# + name + #"(?![\w])"#)
                // A plain form keeps the enum's unused numbers unused: the enum itself, an array, set or dictionary of
                // it through any depth, a dictionary of it with a key or value that doesn't name it at all, and the
                // enum's own case constructors (`(Mood.Type) -> Mood`).
                func plain(_ kind: String) -> Bool {
                    let kind = kind.trimmingCharacters(in: .whitespaces)
                    if kind == carrier { return true }
                    if mention.firstMatch(in: kind, range: NSRange(kind.startIndex..., in: kind)) == nil { return true }
                    for (open, close) in [("[", "]"), ("Set<", ">"), ("Array<", ">")] where kind.hasPrefix(open) && kind.hasSuffix(close) {
                        let inside = String(kind.dropFirst(open.count).dropLast(close.count))
                        // A dictionary: its key and value, split at the colon outside any brackets.
                        var depth = 0
                        for (n, ch) in inside.enumerated() {
                            if "[<(".contains(ch) { depth += 1 } else if "]>)".contains(ch) { depth -= 1 }
                            if ch == ":", depth == 0, open == "[" {
                                let at = inside.index(inside.startIndex, offsetBy: n)
                                return plain(String(inside[..<at])) && plain(String(inside[inside.index(after: at)...]))
                            }
                        }
                        return plain(inside)
                    }
                    return kind.range(of: #"^(?:<[^>]*> )?\("# + name + #"(?:<[^>]*>)?\.Type\) -> "# + name + #"(?:<[^>]*>)?$"#, options: .regularExpression) != nil
                }
                for (owner, kind) in holders {
                    let range = NSRange(kind.startIndex..., in: kind)
                    if mention.firstMatch(in: kind, range: range) != nil, !plain(kind) {
                        let what = carrier == type ? type : "\(carrier), which carries \(type),"
                        return "\(owner.isEmpty ? "a global" : owner) holds \(what) as \(kind), which a new case would change"
                    }
                }
                // A spare keeps its value as any value, under the metadata the app's code had: after the growth the
                // enum's is the change's own, so the value no longer reads as one and the property starts over.
                for (owner, property, kind) in inSpares where { let k = expanded(kind, in: owner); return mention.firstMatch(in: k, range: NSRange(k.startIndex..., in: k)) != nil }() {
                    return "\(owner) keeps \(property), added while the app was open, in a place that holds it as any value, which the grown \(type) no longer reads from"
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
    /// for a `switch` over the enum, or an interpolation of it, in an escaping closure that outlives a draw: one
    /// made outside a view's body, or one a body hands to anything but SwiftUI (a Timer, a dispatch queue, a Task,
    /// the app's own code keep theirs; what SwiftUI is handed, a Button's action, is made again at the next draw),
    /// in an async closure anywhere, or in an async function.
    @MainActor static func enumsMetByOldCode(_ project: LampProject, grown: [String]) async -> String? {
        guard let made = await analysis(of: running(project), in: project, module: project.exe, macOS: Template.macMinimum(project)) else {
            return "the compiler couldn't say where the open app uses the enums that grew"
        }
        // What holds the enum by value is changed with it: an old frame holding such a value reads it by the old layout.
        let related = grown + holders(of: grown, inLayout: made.held)
        return oldCode(meeting: related, uses: oldCodeRecorded(project) + made.oldCode)
    }

    /// Why a grown enum can't go in, among what old code may still be doing: the first use of one of the enums.
    static func oldCode(meeting enums: [String], uses: [String]) -> String? {
        func last(_ name: String) -> String { String(name.split(separator: ".").last ?? "") }
        let names = Set(enums.map(bare) + enums.map { last(bare($0)) }), optional = Set(names.map { $0 + "?" })
        // A switch or a print is said as such; a value merely in hand is said when nothing more telling is.
        for use in uses.filter({ !$0.hasSuffix("\tuses") }) + uses.filter({ $0.hasSuffix("\tuses") }) {
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
        enum Kind { case body, escaping, async, function(String?, async: Bool), named(String), other }
        // A view's body, or the live copy's name for it (`Template.liveCopySteps` moves the body into `__lampBody`).
        let bodyDecl = try! NSRegularExpression(pattern: #"^(\s*)\(var_decl\b[^"]*"(?:body|__lampBody)" "#)
        // A closure, written out or as a value a property or a binding starts with (`original_init=closure_expr`).
        let closure = try! NSRegularExpression(pattern: #"^(\s*)\((?:\w+=)?(?:closure_expr|autoclosure_expr)\b(.*)$"#)
        // What holds a closure other than a call: a property being set, a binding or property it's the value of.
        let holder = try! NSRegularExpression(pattern: #"^(\s*)\((?:assign_expr|pattern_binding_decl)\b"#)
        let function = try! NSRegularExpression(pattern: #"^(\s*)\((?:func_decl|accessor_decl|constructor_decl)\b[^"]*(?:"([^"]+)")? interface_type="([^"]*)""#)
        let scope = try! NSRegularExpression(pattern: #"^(\s*)\((?:var_decl|subscript_decl|struct_decl|class_decl|enum_decl|actor_decl|extension_decl|protocol)\b(?:[^"]*"([^"]+)")?"#)
        // What a call calls: the module before "(file)" in the declaration it names, kept with the call itself,
        // since the arguments (a closure among them) are the call's children, beside the function, not under it.
        let call = try! NSRegularExpression(pattern: #"^(\s*)\((?:\w+=)?call_expr\b"#)
        let callee = try! NSRegularExpression(pattern: #"^(\s*)\(declref_expr\b.*? decl="([\w.]+?)\.\(file\)"#)
        let switchStmt = try! NSRegularExpression(pattern: #"^(\s*)\(switch_stmt\b"#)
        let typeOf = try! NSRegularExpression(pattern: #" type="([^"]*)""#)
        let word = try! NSRegularExpression(pattern: #"[A-Za-z_]\w*(\.[A-Za-z_]\w*)*"#)
        let casePattern = try! NSRegularExpression(pattern: #"^(\s*)\(pattern_enum_element\b.*? type="([^"]*)""#)
        let interpolation = try! NSRegularExpression(pattern: #"^(\s*)\(declref_expr\b.*? type="[^"]*\(([^"()]*)\) -> \(\)".*? decl="Swift\.\(file\)\.DefaultStringInterpolation\.appendInterpolation"#)
        var scopes: [(indent: Int, kind: Kind)] = [], uses: [String] = [], seen = Set<String>()
        var switching: Int?, typeNames: [String: [String]] = [:]
        // The calls around the line being read, by the module each one's function is from.
        var calls: [Int] = [], callees: [(indent: Int, module: String)] = [], holders: [Int] = []
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
            for (_, kind) in scopes.reversed() {
                if case .function(let name?, _) = kind { return name }
                if case .named(let name) = kind { return name }
            }
            return "the app"
        }
        for raw in SwiftSource.lines(dump) {
            guard let node = SwiftSource.node(raw) else { continue }
            let indent = node.indent, opens = node.opens
            // Made only for a line a pattern is tried on.
            lazy var line = String(raw)
            lazy var range = NSRange(line.startIndex..., in: line)
            while let last = scopes.last, last.indent >= indent { scopes.removeLast() }
            while let last = callees.last, last.indent >= indent { callees.removeLast() }
            while let last = calls.last, last >= indent { calls.removeLast() }
            while let last = holders.last, last >= indent { holders.removeLast() }
            if let at = switching, at >= indent { switching = nil }
            if node.names("call_expr"), call.firstMatch(in: line, range: range) != nil { calls.append(indent) }
            if opens("assign_expr", "pattern_binding_decl"), holder.firstMatch(in: line, range: range) != nil { holders.append(indent) }
            // The call's function is the first thing named under it; what its arguments name is theirs.
            if let at = calls.last, callees.last?.indent != at, opens("declref_expr"), let m = callee.firstMatch(in: line, range: range) {
                callees.append((at, String(line[Range(m.range(at: 2), in: line)!])))
            }
            if opens("var_decl"), bodyDecl.firstMatch(in: line, range: range) != nil {
                scopes.append((indent, .body))
            } else if node.names("closure_expr"), let m = closure.firstMatch(in: line, range: range) {
                let rest = String(line[Range(m.range(at: 2), in: line)!])
                // An escaping closure handed to anything but SwiftUI is kept by it, however deep in a body it's made;
                // so is one set into a property or given as a value, whatever call it's made inside. A key path
                // passed as a function (`.map(\.name)`) is an escaping closure the compiler makes for that call, and
                // lives with it.
                let stored = (holders.last ?? -1) > (calls.last ?? -1)
                let kept = stored || !["SwiftUI", "SwiftUICore"].contains(callees.last?.module ?? "SwiftUI")
                let keyPath = line.contains("(autoclosure_expr implicit") && rest.contains("captures=($kp$")
                scopes.append((indent, rest.contains(" async") ? .async : rest.contains(" escaping") && !keyPath ? (kept ? .async : .escaping) : .other))
            } else if opens("func_decl", "accessor_decl", "constructor_decl"), let m = function.firstMatch(in: line, range: range) {
                let type = String(line[Range(m.range(at: 3), in: line)!])
                let name = m.range(at: 2).location == NSNotFound ? nil : String(line[Range(m.range(at: 2), in: line)!])
                // A member that returns a view is drawn by a body, and what it hands SwiftUI is made again with it;
                // one that is async may be suspended across the change, so it stays a function.
                let async = type.contains(" async")
                scopes.append((indent, type.hasSuffix("some View") && !async ? .body : .function(name, async: async)))
            } else if opens("var_decl", "subscript_decl", "struct_decl", "class_decl", "enum_decl", "actor_decl", "extension_decl", "protocol"),
                      let m = scope.firstMatch(in: line, range: range) {
                // A type or property, named so a use can say where it is; a type's name is what a body's uses show.
                scopes.append((indent, m.range(at: 2).location == NSNotFound ? .other : .named(String(line[Range(m.range(at: 2), in: line)!]))))
            } else if opens("switch_stmt"), switchStmt.firstMatch(in: line, range: range) != nil {
                if risky() { switching = indent }
            } else if let at = switching, indent > at, opens("pattern_enum_element"), let m = casePattern.firstMatch(in: line, range: range) {
                note(String(line[Range(m.range(at: 2), in: line)!]), "switches over")
            } else if opens("declref_expr"), SwiftSource.has(line, "appendInterpolation"), risky(), let m = interpolation.firstMatch(in: line, range: range) {
                note(String(line[Range(m.range(at: 2), in: line)!]), "prints")
            }
            // Any value of the enum's type, or of a type holding it, that running code has in hand: compared, hashed,
            // cast, read as an optional, each by the layout the code was compiled with, which a new case changes.
            if risky(), SwiftSource.has(line, " type=\""), let m = typeOf.firstMatch(in: line, range: range) {
                let kind = String(line[Range(m.range(at: 1), in: line)!])
                // The same few types come up on most lines: each is read for its names once.
                if typeNames[kind] == nil {
                    typeNames[kind] = word.matches(in: kind, range: NSRange(kind.startIndex..., in: kind))
                        .map { String(kind[Range($0.range, in: kind)!]) }.filter { $0.first?.isUppercase == true }
                }
                for name in typeNames[kind]! { note(name, "uses") }
            }
        }
        return uses
    }

    /// The value types that hold any of `types` by value, through any depth of the app's own types, from a layout's
    /// fields: what a grown enum's new case changes beyond the enum itself. A class holds the enum in a field of its
    /// own, which keeps its layout (old code reading the field is caught as a use of the enum itself), and a view's
    /// value lives in SwiftUI's own graph: neither is a carrier.
    static func holders(of types: [String], inLayout entries: [String]) -> [String] {
        let conformed = conformances(inLayout: entries), types = types.map(bare)
        // Judged by its own key, so a private class in one file doesn't speak for a struct of its name in another.
        func carrier(_ owner: String) -> Bool {
            let kinds = conformed.kinds[owner] ?? []
            if !kinds.isEmpty, kinds.isSubset(of: ["class", "actor"]) { return false }
            return conformed.of[owner]?.contains("View") != true
        }
        // The layout's own keys only: the bare copies merge twins, which are judged each on its own.
        let own = Set(entries.compactMap { entry -> String? in
            guard !isGroup(entry), let tab = entry.firstIndex(of: "\t") else { return nil }
            return String(entry[..<tab])
        })
        let word = try! NSRegularExpression(pattern: #"[A-Za-z_]\w*(\.[A-Za-z_]\w*)*"#)
        func last(_ name: String) -> String { String(name.split(separator: ".").last ?? "") }
        // A field's type may be a typealias of one: followed to what it names.
        func resolved(_ name: String) -> String {
            var name = name, steps = 0
            while !conformed.types.contains(name), let target = conformed.aliases[name], target != name, steps < 8 { name = target; steps += 1 }
            return name
        }
        var found = Set(types), grew = true
        while grew {
            grew = false
            // What's found is named bare, as a field's type names it.
            for (owner, kinds) in conformed.fields where own.contains(owner) && !found.contains(bare(owner)) && carrier(owner) {
                for kind in kinds {
                    let names = word.matches(in: kind, range: NSRange(kind.startIndex..., in: kind)).flatMap { m -> [String] in
                        let name = String(kind[Range(m.range, in: kind)!]), target = resolved(name)
                        return [name] + word.matches(in: target, range: NSRange(target.startIndex..., in: target)).map { String(target[Range($0.range, in: target)!]) }
                    }
                    if names.contains(where: { found.contains($0) || found.contains(last($0)) }) { found.insert(bare(owner)); grew = true; break }
                }
            }
        }
        return found.subtracting(types).sorted()
    }

    /// What each type and protocol conforms to or inherits, from the layout's declarations ("Mood inherits P, Q",
    /// an extension's included, a nested type's under its qualified name), with the protocols the app declares
    /// itself and the types it declares, so an extension of a system type (`extension Optional: P`) is told apart.
    struct Conformances {
        var of: [String: Set<String>] = [:]
        var protocols = Set<String>(), types = Set<String>()
        /// Each type's stored fields' types, an enum's cases' payloads included, to tell a type that may wrap
        /// anything (a generic parameter, `Any`, a system type) from one made of plain values and the app's own types.
        var fields: [String: [String]] = [:]
        /// Each typealias and what it names, by its name and its qualified name.
        var aliases: [String: String] = [:]
        /// What each type is (struct, class, enum, actor), from the layout's shapes; unknown in one an earlier Lamp
        /// kept, and more than one under a bare name two files' private types share.
        var kinds: [String: Set<String>] = [:]
    }
    /// Keyed as the layout keys types (a private one with its file), and again by the bare name the code uses, where
    /// two files' private types of one name merge: a lookup by a field's type or a use in old code finds them both.
    static func conformances(inLayout entries: [String]) -> Conformances {
        var out = Conformances()
        func keys(_ type: String) -> Set<String> { [type, bare(type)] }
        for entry in entries {
            if let parts = Group.shape.parts(of: entry), parts.count == 2, let kind = parts[1].split(separator: " ").first.map(String.init) {
                for key in keys(parts[0]) { out.kinds[key, default: []].insert(kind) }
                continue
            }
            if entry.hasPrefix("protocol "), entry.hasSuffix("\t") { out.protocols.insert(String(entry.dropFirst("protocol ".count).dropLast())); continue }
            if let alias = Group.alias.parts(of: entry)?.first, let equals = alias.range(of: " = ") {
                let name = String(alias[..<equals.lowerBound]), names = String(alias[equals.upperBound...])
                for key in keys(name) {
                    out.aliases[key] = names
                    out.aliases[String(key.split(separator: ".").last ?? "").split(separator: ":").last.map(String.init) ?? key] = names
                }
                continue
            }
            if entry.hasSuffix("\t"), !isGroup(entry) { out.types.formUnion(keys(String(entry.dropLast()))); continue }
            if !isGroup(entry), !entry.hasPrefix("protocol "), let tab = entry.firstIndex(of: "\t"), let colon = entry.range(of: ": ") {
                for key in keys(String(entry[..<tab])) { out.fields[key, default: []].append(String(entry[colon.upperBound...])) }
                continue
            }
            guard let declared = Group.declared.parts(of: entry)?.first, let at = declared.range(of: " inherits ") else { continue }
            for key in keys(String(declared[..<at.lowerBound])) {
                for name in declared[at.upperBound...].split(separator: ",") { out.of[key, default: []].insert(name.trimmingCharacters(in: .whitespaces)) }
            }
        }
        return out
    }

    /// The existential in a stored type that a value of the enum could be kept in, if there is one. `Any` takes
    /// any value, `AnyObject` too (a value is boxed into an object for it), and so does `any P` for a protocol the
    /// app doesn't declare: the standard wrappers conform to many of those on their own (`Optional` is
    /// CustomDebugStringConvertible whatever it wraps, an array a Collection), so `any Collection` may hold
    /// `[Mood?]`. For a protocol of the app's own, the enum must conform to it, directly, in an extension or
    /// through a protocol that inherits it, or a type that could wrap the enum must: an extension of a type the app
    /// doesn't declare (`Optional`, `Array`), or a type of the app's with a field of a type that isn't the app's or
    /// a plain value (a generic parameter, `Any`, a system type), followed through the app's types. A model keeping
    /// `any Shape` isn't a reason to reopen for a Mood that is no Shape.
    static func existential(in kind: String, holding type: String, conformances: Conformances) -> String? {
        // What the enum conforms to, followed through the protocols those inherit, and the same for the app's
        // extensions of types it doesn't declare, which may wrap the enum.
        func reach(_ from: [String]) -> Set<String> {
            var seen = Set<String>(), queue = from
            while let next = queue.popLast() {
                guard seen.insert(next).inserted else { continue }
                queue += conformances.of[next] ?? []
            }
            return seen
        }
        let own = reach(Array(conformances.of[type] ?? []))
        // Whether a type of the app's could hold anything: a field whose type names something that isn't one of the
        // app's types or a plain value, looked through the app's types it's made of.
        let names = try! NSRegularExpression(pattern: #"[A-Za-z_]\w*(\.[A-Za-z_]\w*)*"#)
        func mayWrap(_ type: String, _ seen: inout Set<String>) -> Bool {
            guard seen.insert(type).inserted else { return false }
            return (conformances.fields[type] ?? []).contains { mayWrap(kind: $0, &seen) }
        }
        func mayWrap(kind: String, _ seen: inout Set<String>) -> Bool {
            for match in names.matches(in: kind, range: NSRange(kind.startIndex..., in: kind)) {
                var name = String(kind[Range(match.range, in: kind)!])
                // A case's type names its enum's metatype; the type itself is what's looked at.
                for suffix in [".Type", ".Protocol"] where name.hasSuffix(suffix) { name.removeLast(suffix.count) }
                let last = String(name.split(separator: ".").last ?? "")
                if ["any", "some", "inout"].contains(name) || LiveSlots.plainValues.contains(last) { continue }
                if let named = conformances.aliases[name] ?? conformances.aliases[last] {
                    if seen.insert("=" + name).inserted, mayWrap(kind: named, &seen) { return true } else { continue }
                }
                if conformances.types.contains(name) { if mayWrap(name, &seen) { return true } else { continue } }
                if conformances.types.contains(last) { if mayWrap(last, &seen) { return true } else { continue } }
                return true
            }
            return false
        }
        let wrappers = reach(conformances.of.keys.filter { key in
            guard !conformances.protocols.contains(key), conformances.of[key] != nil else { return false }
            var seen = Set<String>()
            return !conformances.types.contains(key) || mayWrap(key, &seen)
        })
        // Any, AnyObject (a value is boxed for it), AnyHashable, an existential; and the containers that keep their
        // elements as any value without saying so: a navigation path, Foundation's collections.
        let boxes = try! NSRegularExpression(pattern: #"(?<![\w.])(Any|AnyObject|AnyHashable|NavigationPath|NS(?:Mutable)?(?:Array|Dictionary|Set|OrderedSet)|NSCache|NSMapTable|NSHashTable|NSPointerArray|any (?:[\w.]+(?: & [\w.]+)*))(?![\w])"#)
        for match in boxes.matches(in: kind, range: NSRange(kind.startIndex..., in: kind)) {
            let box = String(kind[Range(match.range(at: 1), in: kind)!])
            if !box.hasPrefix("any ") { return box }
            let protocols = box.dropFirst(4).split(separator: "&").map { $0.trimmingCharacters(in: .whitespaces) }
            let holds = protocols.allSatisfy { name in
                let simple = String(name.split(separator: ".").last ?? Substring(name))
                guard conformances.protocols.contains(simple) else { return true }
                return own.contains(simple) || own.contains(name) || wrappers.contains(simple)
            }
            if holds { return box }
        }
        return nil
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
            // Most often what a change before read as the live copy (`Analyses`).
            let macOS = Template.macMinimum(project)
            before = analyses.entry(Analyses.digest(of: running(project), module: project.exe, macOS: macOS))?.layout
            if before == nil { before = await analysis(of: running(project), in: project, module: project.exe, macOS: macOS)?.layout }
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

    fileprivate static func swiftFiles(in folder: URL) -> [String: URL] {
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
        let primaries = files ?? swiftFiles(in: folder).keys.filter { !ownFiles.contains(($0 as NSString).lastPathComponent) }.sorted()
        guard !primaries.isEmpty else { return [] }
        let (status, output) = await Sandbox.output(frontend("-dump-ast", in: folder, primaries: primaries, module: module, macOS: macOS, ios: ios),
                                                    for: project, cwd: folder)
        guard status == 0 else { return nil }
        return members(inDump: String(decoding: output, as: UTF8.self), rawValues: rawValues)
    }

    /// The compiler's printout of a live copy's whole code but Lamp's own, or nil when it doesn't type-check (or
    /// there's none): empty for a copy with no files of the app's.
    static func dump(of folder: URL, in project: LampProject, module: String, macOS: String) async -> String? {
        let primaries = swiftFiles(in: folder).keys.filter { !ownFiles.contains(($0 as NSString).lastPathComponent) }.sorted()
        guard !primaries.isEmpty else { return "" }
        // Tens of megabytes for a big app: kept whole as it comes, off the main actor, never handed over line by line.
        let (status, output) = await Sandbox.output(frontend("-dump-ast", in: folder, primaries: primaries, module: module, macOS: macOS),
                                                    for: project, cwd: folder)
        return status == 0 ? String(decoding: output, as: UTF8.self) : nil
    }

    /// A live copy's layout as `layout` gives it, with what's read only at launch (`SwiftSource.launchEntries`)
    /// and where each property is declared, all from the one printout.
    /// And where its code may go on running after the next change (`oldCodeUses`), to record once it's in.
    /// Kept by what it was made from (`Analyses`), so the same code is never printed and read twice.
    static func analysis(of folder: URL, in project: LampProject, module: String, macOS: String)
        async -> (layout: [String], held: [String], declarations: SwiftSource.Declarations, oldCode: [String])? {
        let digest = Analyses.digest(of: folder, module: module, macOS: macOS)
        if let known = analyses.entry(digest, in: folder.standardizedFileURL.path) {
            return (known.layout, known.held, known.declarations, known.oldCode)
        }
        guard let dump = await dump(of: folder, in: project, module: module, macOS: macOS) else { return nil }
        let declarations = SwiftSource.declarations(inDump: dump)
        let made = (layout: members(inDump: dump) + SwiftSource.launchEntries(inDump: dump, folder: folder) + SwiftSource.constantEntries(declarations),
                    held: members(inDump: dump, held: true), declarations: declarations, oldCode: oldCodeUses(inDump: dump))
        // Kept only when the code didn't change while it was read.
        if Analyses.digest(of: folder, module: module, macOS: macOS) == digest {
            analyses.keep(digest, .init(folder: folder.standardizedFileURL.path, layout: made.layout, held: made.held, declarations: made.declarations, oldCode: made.oldCode))
        }
        return made
    }

    /// The analyses made lately, in memory, by a digest of the code they were made from. Two reads of the same code
    /// are common: a change that can't go in is tried before its build and again at the install after it, on the
    /// same live copy; and once the app reopens, the sources it runs are the live copy that change read. A big app's
    /// printout takes the compiler several seconds. The layout and what old code does name no folder, so they stand for
    /// any copy of the same code; where each property is declared names the files, so it stands only for its own folder.
    final class Analyses: @unchecked Sendable {
        struct Entry {
            var folder: String
            var layout: [String]
            /// The layout with what the app keeps beyond its types' fields (statics, globals): what a grown enum is checked against.
            var held: [String]
            var declarations: SwiftSource.Declarations
            var oldCode: [String]
        }
        private let lock = NSLock()
        private var entries: [(digest: String, entry: Entry)] = []

        /// The latest made from this code, in `folder` when given: only there do its declarations' places hold.
        func entry(_ digest: String, in folder: String? = nil) -> Entry? {
            lock.withLock { entries.last { $0.digest == digest && (folder == nil || $0.entry.folder == folder) }?.entry }
        }

        func keep(_ digest: String, _ entry: Entry) {
            lock.withLock {
                entries.removeAll { $0.digest == digest && $0.entry.folder == entry.folder }
                entries.append((digest, entry))
                // A few apps' worth: each is the size of a layout, much smaller than a printout.
                if entries.count > 6 { entries.removeFirst(entries.count - 6) }
            }
        }

        /// What the compiler reads for a copy's printout: its Swift files (each by its place in the copy and what it
        /// holds), the widget's shared code read beside it (`frontend`), the module's name and the macOS it's for.
        static func digest(of folder: URL, module: String, macOS: String) -> String {
            let shared = folder.deletingLastPathComponent().appendingPathComponent(Template.widgetFolder).appendingPathComponent(Template.sharedWidgetFolder)
            return LiveReload.digest(of: [folder, shared], extra: [module, macOS, ProcessInfo.processInfo.environment["DEVELOPER_DIR"] ?? ""],
                                     only: { $0.pathExtension == "swift" })
        }
    }
    private static let analyses = Analyses()

    /// A digest of what these files and folders hold, each file by its path under the one given and its bytes, with
    /// `extra` beside them. Read as Lamp, but only hashed: nothing read is passed on.
    static func digest(of places: [URL], extra: [String] = [], only include: (URL) -> Bool = { _ in true }) -> String {
        var hash = SHA256()
        func add(_ text: String) { hash.update(data: Data((text + "\u{0}").utf8)) }
        extra.forEach(add)
        let fm = FileManager.default
        // Each place by where it is in the list, not by its name: the live copy, `built` and `running` hold the same
        // code under different names, and stand for one another.
        for (index, place) in places.enumerated() {
            add("@\(index)")
            var isFolder: ObjCBool = false
            guard fm.fileExists(atPath: place.path, isDirectory: &isFolder) else { add("-"); continue }
            guard isFolder.boolValue else { hash.update(data: fm.contents(atPath: place.path) ?? Data()); continue }
            let base = place.standardizedFileURL.path + "/"
            let files = (fm.enumerator(at: place, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? [])
                .filter(include)
                .map { (String($0.standardizedFileURL.path.dropFirst(base.count)), $0) }
                .sorted { $0.0 < $1.0 }
            for (name, url) in files {
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
                add(name)
                hash.update(data: fm.contents(atPath: url.path) ?? Data())
            }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The stored members of every type in a `-dump-ast` printout: each line's indent says what it's inside, so
    /// a function's locals (inside a func or closure) never count, nor a static or a computed property.
    /// `held` adds what the app keeps beyond its types' own fields: static properties, and globals (under "").
    static func members(inDump dump: String, rawValues: Bool = false, held: Bool = false) -> [String] {
        // Its access comes after its name (and a generic one's parameters, in quotes); its place before, read apart.
        let typeDecl = try! NSRegularExpression(pattern: #"^(\s*)\((struct|class|enum|actor)_decl\b[^"]*"([^"]+)".*? access=(\w+)"#)
        let declFile = try! NSRegularExpression(pattern: #" range=\[([^:\]]*):"#)
        // A generic type's parameters, quoted after its name (`"Stack" "<Element>"`).
        let genericDecl = try! NSRegularExpression(pattern: #"^\s*\(\w+_decl\b[^"]*"[^"]+" "<([^"]*)>""#)
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
        // An associated type the compiler inferred (Identifiable's ID, a Sequence's Iterator, a modifier's Body) is
        // a typealias it declares itself; one naming an opaque type (`some View`) is held by its member instead.
        let inferredAlias = try! NSRegularExpression(pattern: #"^(\s*)\(typealias\b[^"]*? implicit "([^"]+)" interface_type="[^"]*" access=\w+ type="([^"]*)""#)
        // A member returning `some …`: the type it builds, which the compiler prints where the body's value becomes
        // the opaque one; when that is itself opaque (a modifier's `some View`), what the body builds from instead.
        let opaqueMember = try! NSRegularExpression(pattern: #"^(\s*)\((func_decl|var_decl)\b(?! implicit)[^"]*"([^"]+)" interface_type="([^"]*some [^"]*)" access=(\w+)"#)
        let attribute = try! NSRegularExpression(pattern: #" (?:decl|type)="([^"]*)""#)
        let toOpaque = try! NSRegularExpression(pattern: #"^\s*\(underlying_to_opaque_expr\b"#)
        // A declaration inside the member (a local function, a type), whose own conversions aren't the member's.
        let inner = try! NSRegularExpression(pattern: #"^\s*\((?:func_decl|var_decl|subscript_decl|struct_decl|class_decl|enum_decl|actor_decl)\b"#)
        let typeOf = try! NSRegularExpression(pattern: #" type="([^"]*)""#)
        // The place is a path (which may hold spaces, as the apps folder does), a line and a column.
        let place = try! NSRegularExpression(pattern: #"@[^"]*?\.swift:\d+:\d+"#)
        // A literal's value, or an argument left to its default, changes no type: left out of the digest.
        let valueOnly = try! NSRegularExpression(pattern: #"^\s*\((?:\w+_literal_expr|default_argument_expr)\b"#)
        let extensionDecl = try! NSRegularExpression(pattern: #"^(\s*)\(extension_decl\b[^"]*"([^"]+)""#)
        let inherits = try! NSRegularExpression(pattern: #" inherits="([^"]*)""#)
        // A type's shape (`shapeGroup`): `indirect` is the node right under an enum, as `@objc` is, which the line
        // says too; a stored reference's `weak` or `unowned` is the node right under its property, and changes what
        // the field holds (a side table's reference, an unretained one), so it's part of the field's entry.
        let indirectAttr = try! NSRegularExpression(pattern: #"^(\s*)\(indirect_attr\b"#)
        let ownershipAttr = try! NSRegularExpression(pattern: #"^(\s*)\(reference_ownership_attr\b(?: range=\[[^\]]*\])? (\S+?)\)"#)
        let signature = try! NSRegularExpression(pattern: #" requirement_signature="([^"]*)""#)
        // A class's superclass is the first name it inherits, when that's a class: one of the app's own, or a name
        // that isn't one of the app's protocols nor shaped like a protocol's (a system protocol's name ends in
        // `able`, `ible`, `Delegate`, `DataSource` or `Protocol`, a system class's never). A subclass of a system
        // class the rule reads as a protocol would reopen for a change to the protocol list instead; neither mistake
        // lets a changed superclass through unnoticed.
        let appClasses = Set(dump.split(separator: "\n").compactMap { line -> String? in
            guard let m = line.range(of: #"^\s*\(class_decl\b[^"]*"([^"]+)""#, options: .regularExpression) else { return nil }
            return String(line[m]).split(separator: "\"").dropFirst().first.map(String.init)
        })
        let appProtocols = Set(dump.split(separator: "\n").compactMap { line -> String? in
            guard let m = line.range(of: #"^\s*\(protocol(?:_decl)?\b[^"]*"([^"]+)""#, options: .regularExpression) else { return nil }
            return String(line[m]).split(separator: "\"").dropFirst().first.map(String.init)
        })
        func superclass(of inherited: String) -> String? {
            guard let first = inherited.split(separator: ",").first?.trimmingCharacters(in: .whitespaces), !first.isEmpty else { return nil }
            let bare = String(first.prefix { $0 != "<" }), simple = String(bare.split(separator: ".").last ?? "")
            if appClasses.contains(simple) { return first }
            if appProtocols.contains(simple) { return nil }
            return ["able", "ible", "Delegate", "DataSource", "Protocol"].contains(where: simple.hasSuffix) ? nil : first
        }
        let memberDecl = try! NSRegularExpression(pattern: #"^(\s*)\((func_decl|constructor_decl|subscript_decl)\b[^"]*"([^"]+)" interface_type="([^"]*)""#)
        // What a member answers to from Objective-C, the node right under it: `@objc`, with the selector when one is
        // given or implied (an override of a system class's method). Declared, since the open app's class goes on
        // answering to a selector taken away or renamed unless every file is compiled.
        let objcAttr = try! NSRegularExpression(pattern: #"^(\s*)\(objc_attr\b(?:.*? name="([^"]+)")?"#)
        // A case's raw value is the node right under it: a string's in quotes, a number's bare.
        let rawValue = try! NSRegularExpression(pattern: #"^\s*\(raw_value_expr=\w+\b.*? value=("(?:[^"\\]|\\.)*"|[^ )]+)"#)
        var scopes: [(indent: Int, type: String?)] = [], out: [String] = [], seen = Set<String>()
        var lastCase: Int?, classTypes = Set<String>()
        // The indents of extension scopes: an initializer declared in one is a convenience initializer, in no table.
        // And of generic types' scopes: a type declared inside one is laid out for each type it's used at too.
        var extensions = Set<Int>(), genericScopes = Set<Int>()
        // The member just read, whose `@objc` would be the next node under it: its indent and its entry so far.
        var objcPending: (indent: Int, entry: String)?
        // The enum just read, whose `indirect` would be the next node under it, and the stored property just read,
        // whose `weak` or `unowned` would be: each by its indent and its entry's place in `out`.
        var shapePending: (indent: Int, index: Int)?, ownershipPending: (indent: Int, index: Int)?
        // The `some`-returning member being read, what its body names so far, the type it builds once found, the
        // indent of a conversion to the opaque type whose child names that type, and of a declaration inside it.
        var opaque: (indent: Int, key: String, names: [String], builds: String?, converting: Int?, inner: Int?)?
        func closeOpaque() {
            guard let open = opaque else { return }
            // A literal may change (`1` to `1.5`) without a call or type changing, and a call may change
            // (`.bold()`) without the type: the type decides, when the compiler can print it.
            let entry = opaqueGroup + "\t" + open.key + "\t" + (open.builds ?? "~" + SwiftSource.digest(open.names.joined(separator: "\n")))
            if seen.insert(entry).inserted { out.append(entry) }
            opaque = nil
        }
        for raw in SwiftSource.lines(dump) {
            // Only a line that opens a node says where it sits; the closing brackets of a deep node sometimes
            // come on a line of their own at the left edge, which would otherwise end every scope.
            guard let node = SwiftSource.node(raw) else { continue }
            let indent = node.indent, opens = node.opens
            // Made only for a line a pattern is tried on.
            lazy var line = String(raw)
            lazy var range = NSRange(line.startIndex..., in: line)
            if let open = opaque {
                if indent > open.indent {
                    if let within = open.inner, indent <= within { opaque?.inner = nil }
                    if opaque?.inner != nil {
                        // Inside a local declaration: its names count, its conversions don't.
                    } else if let at = open.converting, indent > at {
                        opaque?.converting = nil
                        if open.builds == nil, SwiftSource.has(line, " type=\""), let m = typeOf.firstMatch(in: line, range: range) {
                            let type = String(line[Range(m.range(at: 1), in: line)!])
                            if !type.contains("some ") { opaque?.builds = place.stringByReplacingMatches(in: type, range: NSRange(type.startIndex..., in: type), withTemplate: "") }
                        }
                    } else if opens("underlying_to_opaque_expr"), toOpaque.firstMatch(in: line, range: range) != nil {
                        opaque?.converting = indent
                    } else if opens("func_decl", "var_decl", "subscript_decl", "struct_decl", "class_decl", "enum_decl", "actor_decl"),
                              inner.firstMatch(in: line, range: range) != nil {
                        opaque?.inner = indent
                    }
                    if !(node.names("_literal_expr") || opens("default_argument_expr")) || valueOnly.firstMatch(in: line, range: range) == nil,
                       SwiftSource.has(line, "decl=\"") || SwiftSource.has(line, "type=\"") {
                        for m in attribute.matches(in: line, range: range) {
                            // A declaration of the app's is named with where it is, which differs between the copy
                            // the app runs and the new one, and moves with any edit above it.
                            let value = String(line[Range(m.range(at: 1), in: line)!])
                            opaque?.names.append(!value.contains("@") ? value : place.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value), withTemplate: ""))
                        }
                    }
                    continue
                }
                closeOpaque()
            }
            if let pending = objcPending {
                if indent == pending.indent + 2, opens("objc_attr"), let m = objcAttr.firstMatch(in: line, range: range) {
                    let selector = m.range(at: 2).location == NSNotFound ? "" : "(" + String(line[Range(m.range(at: 2), in: line)!]) + ")"
                    let entry = pending.entry + " @objc" + selector
                    if seen.insert(entry).inserted { out.append(entry) }
                    objcPending = nil
                    continue
                }
                if indent <= pending.indent { objcPending = nil }
            }
            if let pending = shapePending {
                if indent == pending.indent + 2, opens("indirect_attr"), indirectAttr.firstMatch(in: line, range: range) != nil { out[pending.index] += " indirect"; shapePending = nil; continue }
                if indent <= pending.indent { shapePending = nil }
            }
            if let pending = ownershipPending {
                if indent == pending.indent + 2, opens("reference_ownership_attr"), let m = ownershipAttr.firstMatch(in: line, range: range) {
                    let ownership = String(line[Range(m.range(at: 2), in: line)!])
                    if let tab = out[pending.index].firstIndex(of: "\t") { out[pending.index].insert(contentsOf: ownership + " ", at: out[pending.index].index(after: tab)) }
                    ownershipPending = nil
                    continue
                }
                if indent <= pending.indent { ownershipPending = nil }
            }
            if rawValues, let index = lastCase, opens("raw_value_expr"), let m = rawValue.firstMatch(in: line, range: range) {
                out[index] += " = " + String(line[Range(m.range(at: 1), in: line)!])
                lastCase = nil
                continue
            }
            lastCase = nil
            while let last = scopes.last, last.indent >= indent { extensions.remove(last.indent); genericScopes.remove(last.indent); scopes.removeLast() }
            // What a member line belongs to is the nearest scope around it: a type's member when that's the type,
            // nothing when it's a function, an accessor or a closure (a local).
            let owner = scopes.last?.type
            // Something declared at the top or in a type, never a function's local, under `declarationGroup`.
            func declared(_ what: String, listed: Bool = true) {
                // What the compiler declares by itself (a memberwise initializer, a conformance's synthesized
                // methods) follows from what's written, which is listed already.
                guard !line.contains(" implicit") else { return }
                let place: String
                if let owner, !owner.hasPrefix("\u{4}") { place = owner + "." } else if scopes.isEmpty { place = "" } else { return }
                let entry = declarationGroup + "\t" + place + what
                if listed, seen.insert(entry).inserted { out.append(entry) }
                objcPending = (indent, entry)
            }
            func conformances(_ type: String) {
                if let m = inherits.firstMatch(in: line, range: range) { declared(type + " inherits " + String(line[Range(m.range(at: 1), in: line)!])) }
            }
            if opens("protocol"), let m = protocolDecl.firstMatch(in: line, range: range) {
                let type = "protocol " + String(line[Range(m.range(at: 3), in: line)!])
                conformances(String(line[Range(m.range(at: 3), in: line)!]))
                scopes.append((indent, type))
                if seen.insert(type + "\t").inserted { out.append(type + "\t") }
                if let m = signature.firstMatch(in: line, range: range) {
                    let entry = shapeGroup + "\t" + type + "\t" + String(line[Range(m.range(at: 1), in: line)!])
                    if seen.insert(entry).inserted { out.append(entry) }
                }
            } else if let owner, owner.hasPrefix("protocol "), opens("func_decl", "var_decl", "subscript_decl", "constructor_decl", "associated_type_decl"),
                      let m = requirement.firstMatch(in: line, range: range) {
                let entry = owner + "\t" + String(line[Range(m.range(at: 3), in: line)!]) + ": " + String(line[Range(m.range(at: 4), in: line)!])
                if seen.insert(entry).inserted { out.append(entry) }
                scopes.append((indent, "\u{4}" + entry))
            } else if let owner, owner.hasPrefix("\u{4}"), opens("accessor_decl"), let m = accessor.firstMatch(in: line, range: range) {
                let entry = String(owner.dropFirst()) + " " + String(line[Range(m.range(at: 3), in: line)!]) + ": " + String(line[Range(m.range(at: 2), in: line)!])
                if seen.insert(entry).inserted { out.append(entry) }
                scopes.append((indent, nil))
            } else if opens("struct_decl", "class_decl", "enum_decl", "actor_decl"), let m = typeDecl.firstMatch(in: line, range: range) {
                var name = String(line[Range(m.range(at: 3), in: line)!])
                let outer = scopes.compactMap(\.type).last
                let access = String(line[Range(m.range(at: 4), in: line)!])
                let file = declFile.firstMatch(in: line, range: range).map { (String(line[Range($0.range(at: 1), in: line)!]) as NSString).lastPathComponent }
                // A private type is keyed with its file: another file may declare one of the same name, and the two
                // are two types, each with its own fields (`bare` gives the name back).
                if ["private", "fileprivate"].contains(access), let file { name += "@" + file }
                let type = outer.map { $0 + "." + name } ?? name
                // By its bare name: `declared` puts the owner before it, which makes the qualified name once.
                conformances(name)
                // Generic itself, or declared inside a generic type: laid out afresh for each type it's used at.
                let parameters = genericDecl.firstMatch(in: line, range: range).map { String(line[Range($0.range(at: 1), in: line)!]) }
                let generic = parameters != nil || scopes.contains { genericScopes.contains($0.indent) }
                scopes.append((indent, type))
                if generic { genericScopes.insert(indent) }
                if line[Range(m.range(at: 2), in: line)!] == "class" {
                    classTypes.insert(type)
                    // Whether it's final: a final class keeps no method table, so one that stops being final (a
                    // subclass added) or starts needs the app reopened, with its initializers.
                    if line.range(of: #" final\b"#, options: .regularExpression) != nil, seen.insert(initsGroup + "\t" + type + ".final").inserted {
                        out.append(initsGroup + "\t" + type + ".final")
                    }
                }
                // Every type is listed, members or not: an empty one the open app has is still its, and a first
                // field added to it changes what it holds.
                if seen.insert(type + "\t").inserted { out.append(type + "\t") }
                let kind = String(line[Range(m.range(at: 2), in: line)!])
                // A generic type's parameters are named too (`generic<T>`): a field's type naming one is no alias.
                var shape = kind + (line.contains(" @objc ") ? " @objc" : "") + (generic ? " generic" + (parameters.map { "<" + $0 + ">" } ?? "") : "")
                if kind == "class", let i = inherits.firstMatch(in: line, range: range), let above = superclass(of: String(line[Range(i.range(at: 1), in: line)!])) {
                    shape += " : " + above
                }
                let entry = shapeGroup + "\t" + type + "\t" + shape
                if seen.insert(entry).inserted {
                    out.append(entry)
                    if kind == "enum" { shapePending = (indent, out.count - 1) }
                }
                // A private type is known by its file too (`placeGroup`, by its bare name): moved, it's another type.
                if ["private", "fileprivate"].contains(access), let file {
                    let entry = placeGroup + "\t" + bare(type) + "\t" + file
                    if seen.insert(entry).inserted { out.append(entry) }
                }
            } else if opens("extension_decl"), let m = extensionDecl.firstMatch(in: line, range: range) {
                let type = String(line[Range(m.range(at: 2), in: line)!])
                conformances(type)
                scopes.append((indent, type))
                extensions.insert(indent)
            } else if opens("typealias"), let m = inferredAlias.firstMatch(in: line, range: range), let owner, !owner.hasPrefix("\u{4}") {
                let name = String(line[Range(m.range(at: 2), in: line)!]), type = String(line[Range(m.range(at: 3), in: line)!])
                if !type.contains("some "), seen.insert(aliasGroup + "\t" + owner + "." + name + " = " + type).inserted {
                    out.append(aliasGroup + "\t" + owner + "." + name + " = " + type)
                }
            } else if opens("func_decl", "var_decl"), let m = opaqueMember.firstMatch(in: line, range: range), !["private", "fileprivate"].contains(String(line[Range(m.range(at: 5), in: line)!])),
                      case let name = String(line[Range(m.range(at: 3), in: line)!]), name != "__lampBody", !name.hasPrefix("$") {
                // A view's body is wrapped by the live copy (`__lampBody`, read only by `body` beside it), so its type
                // may change; a private member's callers are all in its file, compiled with it. Keyed with its
                // signature, since overloads share a name; and declared like any member, so one added recompiles
                // every caller.
                let signature = name + ": " + String(line[Range(m.range(at: 4), in: line)!])
                declared(signature)
                if let owner, !owner.hasPrefix("\u{4}") { opaque = (indent, owner + "." + signature, [], nil, nil, nil) }
                else if scopes.isEmpty { opaque = (indent, signature, [], nil, nil, nil) }
                scopes.append((indent, nil))
            } else if opens("typealias"), let m = aliasDecl.firstMatch(in: line, range: range) {
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
            } else if opens("var_decl"), let m = varDecl.firstMatch(in: line, range: range) {
                let rest = String(line[Range(m.range(at: 4), in: line)!])
                let global = held && scopes.isEmpty
                let name = String(line[Range(m.range(at: 2), in: line)!]), type = String(line[Range(m.range(at: 3), in: line)!])
                if let owner = owner ?? (global ? "" : nil), rest.contains("readImpl=stored"), held || !rest.contains(" static") {
                    let entry = owner + "\t" + name + ": " + type
                    if seen.insert(entry).inserted { out.append(entry); ownershipPending = (indent, out.count - 1) }
                } else if !rest.contains("readImpl=stored") {
                    declared(name + ": " + type)
                }
                // A stored property's `@objc` (a static's too) is its accessors' from Objective-C: declared, not listed.
                // Its observers (`didSet`) make every write a call to its setter, which a caller compiled without
                // them doesn't make: declared and listed, so adding or removing them compiles every file.
                let observed = rest.contains("with_observers")
                if rest.contains("readImpl=stored") { declared(name + ": " + type + (observed ? " observed" : ""), listed: observed) }
            } else if opens("func_decl", "constructor_decl", "subscript_decl"), let m = memberDecl.firstMatch(in: line, range: range) {
                let signature = String(line[Range(m.range(at: 3), in: line)!]) + ": " + String(line[Range(m.range(at: 4), in: line)!])
                declared(signature)
                // A class's initializers, the compiler's own included: each has a method descriptor.
                if line[Range(m.range(at: 2), in: line)!] == "constructor_decl", let owner, classTypes.contains(owner),
                   let scope = scopes.last, !extensions.contains(scope.indent) {
                    let entry = initsGroup + "\t" + owner + "." + signature
                    if seen.insert(entry).inserted { out.append(entry) }
                }
                scopes.append((indent, nil))
            } else if opens("enum_element_decl"), let m = caseDecl.firstMatch(in: line, range: range), let owner {
                let entry = owner + "\tcase " + String(line[Range(m.range(at: 2), in: line)!]) + ": " + String(line[Range(m.range(at: 3), in: line)!])
                if seen.insert(entry).inserted {
                    out.append(entry)
                    lastCase = out.count - 1
                }
            } else if opens("func_decl", "accessor_decl", "constructor_decl", "destructor_decl", "closure_expr", "subscript_decl", "top_level_code_decl"),
                      scopeDecl.firstMatch(in: line, range: range) != nil {
                scopes.append((indent, nil))
            }
        }
        closeOpaque()
        return out
    }

    /// The App runs once, at launch: a change to it can't show in an app that's already open.
    /// Compiles the whole module from the live copy, the way the live build does (SwiftPM's for a Mac app,
    /// Xcode's for the Mac half of an app for both: both unoptimized, testable, for the app's macOS, named after the app),
    /// and links the changed files' objects into a library for the open app. Nil, with the compiler's words, when it doesn't compile.
    /// Every file of the app's in the live copy, but Lamp's own.
    static func appFiles(_ project: LampProject) -> [String] {
        swiftFiles(in: sources(project)).keys.filter { !ownFiles.contains(($0 as NSString).lastPathComponent) }.sorted()
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

    /// What putting a change into the open app came to: it went in, with what was done beyond the code (a property
    /// added, a constant given its new value, each a line for the chat); or the app has to reopen, with why.
    enum Outcome {
        case went(said: [String])
        case reopen(why: String)
    }

    /// Puts a change into the open app: the one pipeline, from the layout check to the record of what the app now
    /// runs, given the files the verdict found changed. The changed files' compile and the whole code's check go
    /// side by side, and the check decides; with properties already in spares, the live copy is rewritten before
    /// anything is compiled (`LiveSlots.fit`). What's declared changed, an enum that grew and a constant given a new
    /// value each compile every file. The app loads the library (`send`) and, once it has, the sources it runs, its
    /// layout and what its code may leave running are recorded for the next change.
    @MainActor static func put(_ project: LampProject, changed files: [String], token: String) async -> Outcome {
        // A change that couldn't go in is tried again at the install after its build, on the same live copy and the
        // same open app: the answer is the same, so it's given again without the compiler's seconds of work.
        let key = refusalKey(project, changed: files)
        if let known = refused[project.id], known.key == key { return .reopen(why: known.why) }
        var settled = true
        let outcome = await attempt(project, changed: files, token: token, settled: &settled)
        if case .reopen(let why) = outcome, settled { refused[project.id] = (key, why) } else { refused[project.id] = nil }
        return outcome
    }

    /// Why each app's last change couldn't go in, with what it was judged on (`refusalKey`).
    @MainActor private static var refused: [String: (key: String, why: String)] = [:]

    /// Everything `put` judges a change by: the live copy and the sources the open app runs, what else goes into the
    /// app (`inputs`, the widget's shared code among it), which properties are in spares and which constants are remade,
    /// and what old code may still be running. Not the open app's own answer to a change, which `attempt` leaves unsettled.
    private static func refusalKey(_ project: LampProject, changed: [String]) -> String {
        let live = folder(project)
        return digest(of: [sources(project), running(project), live.appendingPathComponent("slots.json"),
                           live.appendingPathComponent("constants.json"), oldCodeURL(project), runningInputs(project)],
                      extra: [inputs(project), Template.macMinimum(project)] + changed)
    }

    /// `put`'s work. `settled` is set false when the change was refused by the open app itself rather than by
    /// what it was judged on, which a later try might not repeat.
    @MainActor private static func attempt(_ project: LampProject, changed files: [String], token: String, settled: inout Bool) async -> Outcome {
        var changed = files, said: [String] = []
        let spared = !LiveSlots.mapping(project).isEmpty || LiveSlots.hasConstants(project)
        async let early: (url: URL?, problem: String?) = spared ? (nil, nil) : await compile(project, changed: changed)
        let (before, after, declarations, oldCode) = await layouts(project)
        var check = layoutProblem(before: before, after: after)
        // A constant made from an enum that grew (`Mood.allCases`) keeps the value the open app made: remade too.
        let grownEarly = before.flatMap { before in after.map { grownEnums(before: before, after: $0) } } ?? []
        var constants = before.flatMap { before in after.map { LiveSlots.changedConstants(project, before: before, after: $0) } } ?? []
        constants = Array(Set(constants + LiveSlots.constants(naming: grownEarly, in: declarations))).sorted()
        var plan: LiveSlots.Plan?
        var (library, problem) = await early
        // Stored properties added to existing types go into their spares, constants whose value changed give the new
        // one, and the change is compiled with them.
        var fitting: LiveSlots.Fit?
        if check.problem != nil || !constants.isEmpty, let before, let after {
            fitting = LiveSlots.fitting(project, before: before, after: after, declarations: declarations, constants: constants)
        }
        if case .plan(let fitted) = fitting, let before {
            plan = fitted
            changed = Array(Set(changed).union(fitted.files)).sorted()
            // A constant newly read through its new code is read so everywhere: the open app's own reads go to storage
            // that keeps the first value. Afterwards every caller reads through it, so later changes need no more.
            if !fitted.constants.isEmpty { changed = appFiles(project) }
            check = layoutProblem(before: before, after: fitted.layout)
            (library, problem) = await compile(project, changed: changed)
            if check.problem == nil, !fitted.added.isEmpty { said.append("Added \(fitted.added.joined(separator: ", "))") }
            if check.problem == nil, !fitted.constants.isEmpty {
                said.append("Gave \(fitted.constants.joined(separator: ", ")) \(fitted.constants.count == 1 ? "its" : "their") new value")
            }
        } else if !constants.isEmpty, check.problem == nil {
            return .reopen(why: "a constant's new value can't be given in place")
        } else if spared, check.problem == nil {
            (library, problem) = await compile(project, changed: changed)
        }
        // The layout's reason, and when the spares had one of their own for not taking the change, that too.
        if let why = check.problem {
            if case .refused(let refused?) = fitting { return .reopen(why: why + "; " + refused) }
            return .reopen(why: why)
        }
        // What's declared changed (a function added, an overload, a conformance): an unchanged caller may now mean
        // another one, so every file is compiled again and every call goes to code compiled with the new declarations.
        if let before, let after, declarationsChanged(before: before, after: after), changed != appFiles(project) {
            changed = appFiles(project)
            (library, problem) = await compile(project, changed: changed)
        }
        // An enum that only gained cases goes in when nothing holds it where a new case would change what's there.
        // Then every file of the app's is compiled again, so no code of the open app's meets a case it never knew
        // (a switch, or printing it), and the enum's own metadata is the change's, which knows the new cases.
        if let before, let layout = check.layout, case let grown = grownEnums(before: before, after: layout), !grown.isEmpty {
            // A generic enum's values are laid out by the runtime for each type it's used at, from the cases it had
            // when the open app first asked: there's no one metadata to point at the change's.
            if let generic = grown.first(where: { name in Group.shape.parts(in: layout).contains { $0.first == name && $0.last?.contains(" generic") == true } }) {
                return .reopen(why: "\(generic) is generic, and the open app laid its values out for each type it's used at from the cases it had")
            }
            var why = await enumsHeld(project, grown: grown)
            if why == nil { why = await enumsMetByOldCode(project, grown: grown) }
            if let why { return .reopen(why: why) }
            changed = appFiles(project)
            let kinds = Dictionary(Group.shape.parts(in: layout).compactMap { parts -> (String, String)? in
                guard parts.count == 2, let kind = parts[1].split(separator: " ").first else { return nil }
                return (bare(parts[0]), kind == "struct" ? "V" : kind == "enum" ? "O" : "C")
            }, uniquingKeysWith: { first, _ in first })
            (library, problem) = await compile(project, changed: changed, keep: grown.map { LiveObject.mangledType(bare($0), module: project.exe, kind: "O", kinds: kinds) })
        }
        guard let layout = check.layout, library != nil || changed.isEmpty else {
            return .reopen(why: "the change didn't compile on its own.\n\(problem ?? "")")
        }
        // A SwiftData model's file compiled into the change for any reason (every file is, when what's declared
        // changed) makes the model's key paths over again, which the open app's container doesn't know.
        if let model = modelFiles(inLayout: layout).first(where: { changed.contains($0.file) }) {
            return .reopen(why: "the file of the SwiftData model \(model.name) is compiled again, and its data is found by key paths the open app made")
        }
        // A property taken out of the code leaves its spare place holding its value: the app sets its name aside,
        // and the place is retired here, so a name brought back later gets a fresh place.
        let retiring = after.map { LiveSlots.retiring(project, keeping: $0) } ?? []
        // Files only taken away leave nothing to load: the open app already has what's left.
        if let library, let why = await send(library, to: project, token: token, whole: changed == appFiles(project), retired: retiring) {
            settled = false
            return .reopen(why: why)
        }
        // Only now, with the change in, are the spares' places and the constants remade written down.
        if let plan { LiveSlots.commit(plan, for: project) }
        // What a generation's code may leave running (a timer, a task) outlives the next change's replacing its
        // sources: the installed generation's uses are recorded before the first change replaces them, each
        // change's as it goes in.
        if !hasOldCodeRecord(project), let installed = await oldCodeUsesOfRunning(project) { recordOldCode(installed, for: project) }
        if let after { LiveSlots.retire(project, keeping: after) }
        markRunning(project)
        keepLayout(layout, for: project)
        recordOldCode(oldCode, for: project)
        forgetLibraries(project, but: library)
        return .went(said: said)
    }

    /// A reason in the person's words: the copy step's own names (a spare place, a view's state box, the wrapped
    /// body, the entry) said as what they are.
    /// For a reason a change couldn't go into the open app: the shape that would have, where there is a known one,
    /// said to the agent with its look so the next change can take it. Nil for a reason with no such shape.
    static func advice(for why: String) -> String? {
        let w = why.lowercased()
        // The App's body is what's read only at launch, whichever check saw it change (its scenes are an opaque type).
        if w.contains("reads only at launch") || w.contains("app's scenes") || w.contains("menu commands") || w.contains("some scene")
            || w.range(of: #"\bapp\.body\b"#, options: .regularExpression) != nil {
            return "leave the App, its scenes and menu commands as they are once the app is open, and put new views and logic in other files."
        }
        if w.contains("renamed or replaced") { return "add a file rather than renaming one." }
        if w.contains("package") || w.contains("its icon") || w.contains("widget or share") {
            return "make such changes in a request of their own, or first, before the ones that can go in live."
        }
        if w.contains("initializer") || w.contains("method table") || w.contains("subclass") || w.contains("final") {
            return "add a method to a class nothing subclasses, or put the new behaviour in a free function or a struct."
        }
        if w.contains("swiftdata") || w.contains("@model") { return "keep SwiftData model files as they are, and change what reads them." }
        if w.contains("typealias") || w.contains("returns a") || w.contains("returns another") || w.contains("protocol") {
            return "keep a type's existing names and return types, and add new ones beside them."
        }
        if w.contains("holds") || w.contains(" is ") || w.contains("stored") || w.contains("property") || w.contains("case") {
            return "add state as a new property with a starting value, or in a new view, rather than changing, moving or removing an existing one, and add enum cases only at the end."
        }
        return nil
    }

    static func readable(_ why: String) -> String {
        var text = why
        for (pattern, words) in [(#"(?:[\w.]+\.)?_*lampState_(\w+)(?:: [^),]*)?"#, "Lamp's state box for $1"),
                                 (#"(?:[\w.]+\.)?_*lampSpare_(\w+?)(?:_\d+)?(?!\w)(?:: [^),]*)?"#, "Lamp's spare place in $1"),
                                 (#"__lampBinding_(\w+)"#, "\\$$1"), (#"__lampBody"#, "its body"), (#"__LampEntry"#, "Lamp's entry"),
                                 (#"(\w+)@([\w.-]+\.swift)"#, "$1 in $2"), (#"\$__lazy_storage_\$_(\w+)"#, "$1 (lazy)")] {
            text = text.replacingOccurrences(of: pattern, with: words, options: .regularExpression)
        }
        return text
    }

    /// Asks the open app to load the library, signed with its token (only Lamp has it), and waits a moment for
    /// its answer, which it leaves in its runtime folder.
    /// Nil when the app took the change; else why not, in the app's words (`LampLive`), or that it didn't answer.
    /// `whole` says every file was compiled into the library, so the app may take what it doesn't define of a
    /// class's Objective-C methods as taken away.
    static func send(_ library: URL, to project: LampProject, token: String, whole: Bool, retired: [String] = []) async -> String? {
        let answer = Runtime.macFolder(project).appendingPathComponent("reloaded.txt")
        try? FileManager.default.removeItem(at: answer)
        let key = SymmetricKey(data: Data(token.utf8))
        // The app may begin loading until the deadline, and Lamp waits a while past it for the answer, so a change
        // that got in is never taken for one that didn't, nor the other way round.
        let until = String(Int(Date().timeIntervalSince1970) + 5)
        let signature = HMAC<SHA256>.authenticationCode(for: Data(("reload\n\(library.path)" + (whole ? "\nwhole" : "") + (retired.isEmpty ? "" : "\nretired " + retired.joined(separator: ","))
            + "\nuntil " + until).utf8), using: key).map { String(format: "%02x", $0) }.joined()
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(Edition.notificationPrefix + "reload"), object: project.bundleID,
            userInfo: ["path": library.path, "signature": signature, "whole": whole ? "1" : "0", "retired": retired.joined(separator: ","), "until": until], deliverImmediately: true)
        for _ in 0..<120 {
            try? await Task.sleep(for: .milliseconds(100))
            if let text = try? String(contentsOf: answer, encoding: .utf8) {
                if text.hasPrefix("ok") { return nil }
                let why = text.hasPrefix("failed: ") ? String(text.dropFirst(8)) : "the app couldn't take it"
                return why.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return "the app didn't answer"
    }
}

/// A stored property added while the app is open, put in without reopening it. A live build gives every class of the
/// app's `count` spare places (`__lampSpare_<Class>_0`…), every other struct one that holds any number of properties
/// by name (`__lampSpare_<Struct>`), and every view a `@State` box (`__lampState_<View>`), all written by the
/// copy step (`Template.livePerl`), so the open app's objects and values already have room. When the only thing
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
        /// Set once the property was taken out of the code again (`retire`): its place still holds the value it had,
        /// so one brought back under the same name gets a place of its own, never this one.
        var retired: Bool?
        /// Which time round this name has a place: a struct's or view's keeps its values by name, so a name brought
        /// back is kept under the name with this number, apart from what the old one left.
        var generation: Int?
    }
    /// A class's place that was retired, kept under this prefix with the property's name so its index stays taken.
    private static let retiredKey = "\u{1}retired "

    private static func url(_ project: LampProject) -> URL { LiveReload.folder(project).appendingPathComponent("slots.json") }

    /// Type ("Outer.Inner") → property → its place, without the retired places' records.
    static func mapping(_ project: LampProject) -> [String: [String: Slot]] {
        whole(project).mapValues { $0.filter { !$0.key.hasPrefix(retiredKey) } }
    }
    private static func whole(_ project: LampProject) -> [String: [String: Slot]] {
        (try? JSONDecoder().decode([String: [String: Slot]].self, from: Data(contentsOf: url(project)))) ?? [:]
    }

    /// Marks the places of properties the new code no longer declares (`layout`, the new code's whole layout):
    /// each still holds the value the property had, so a property brought back under the name later gets a fresh
    /// place rather than that value. Called once a change is in.
    static func retire(_ project: LampProject, keeping layout: [String]) {
        var map = whole(project)
        let gone = gone(in: map, keeping: layout)
        guard !gone.isEmpty else { return }
        for (type, name, _) in gone { map[type]?[name]?.retired = true }
        save(map, for: project)
    }
    /// The places about to be retired by `retire`, each as the key its struct's or view's spare keeps the value
    /// under (`spareKey`), for the app to set aside before the change goes in.
    static func retiring(_ project: LampProject, keeping layout: [String]) -> [String] {
        gone(in: whole(project), keeping: layout).map { spareKey(type: $0.type, name: $0.name, generation: $0.slot.generation) }.sorted()
    }
    /// The properties in spares that the new code no longer declares, by type and name.
    private static func gone(in mapping: [String: [String: Slot]], keeping layout: [String]) -> [(type: String, name: String, slot: Slot)] {
        var out: [(type: String, name: String, slot: Slot)] = []
        for (type, properties) in mapping {
            for (name, slot) in properties where !name.hasPrefix(retiredKey) && slot.retired != true {
                // As a field, or as a wrapper's storage (`_name`, `__name`).
                let still = ["", "_", "__"].contains { prefix in layout.contains { $0.hasPrefix(type + "\t" + prefix + name + ": ") } }
                if !still { out.append((type, name, slot)) }
            }
        }
        return out
    }
    /// The key a struct's or view's spare keeps a property's value under: its type and name, so two types' `score`
    /// are two values and retiring one leaves the other, numbered when the name has been brought back.
    static func spareKey(type: String, name: String, generation: Int?) -> String {
        type + "." + name + (generation.map { "#\($0)" } ?? "")
    }

    /// Writes down what `fit` planned, once the change is in: the spares' places and the constants remade so far.
    static func commit(_ plan: Plan, for project: LampProject) {
        save(plan.slots, for: project)
        try? JSONEncoder().encode(plan.allConstants).write(to: constantsURL(project), options: .atomic)
    }

    /// The constants (as `changedConstants` names them) whose starting value names one of `types`: made from an
    /// enum that grew, they keep the value the open app made.
    static func constants(naming types: [String], in declarations: SwiftSource.Declarations) -> [String] {
        guard !types.isEmpty else { return [] }
        let names = types.map { String(LiveReload.bare($0).split(separator: ".").last ?? "") }
        return declarations.constants.keys.sorted().filter { key in
            guard let variable = declarations.constants[key], let text = initialText(of: variable, in: declarations) else { return false }
            return names.contains { SwiftText.mentions($0, in: text) }
        }
    }

    private static func save(_ mapping: [String: [String: Slot]], for project: LampProject) {
        try? JSONEncoder().encode(mapping).write(to: url(project), options: .atomic)
    }

    /// Whether a live build's errors are about the spares rather than the app's own code.
    static func brokeBuild(_ output: String) -> Bool {
        // A memberwise initializer passed as a value (`.map(Item.init(name:))`) with a spare in its signature leaves
        // the compiler unable to say what went wrong; that message is the spares' too.
        ["__lampSpare_", "__lampState_", "LampSpare", "LampStateBox", "failed to produce diagnostic", memberwiseFile].contains { output.contains($0) }
    }

    /// Whether a live build's errors come from a class the copy step made final (`Template.livePerl`) that
    /// something subclasses or overrides after all: the compiler names the class, and one the app's own code writes
    /// `final` is the agent's error, not the step's.
    static func brokeFinal(_ output: String, project: LampProject) -> Bool {
        if output.contains("members of 'final' classes") { return true }
        let named = try! NSRegularExpression(pattern: #"(?:from a final class|inherit from final class|of a final class|'final' (?:class|instance|property|subscript|method)[^']*?)[^'\n]*'(\w+)'"#)
        let range = NSRange(output.startIndex..., in: output)
        let classes = Set(named.matches(in: output, range: range).map { String(output[Range($0.range(at: 1), in: output)!]) })
        guard !classes.isEmpty else { return ["overrides a 'final'", "override a 'final'", "cannot be overridden"].contains { output.contains($0) } }
        let written = project.dir.appendingPathComponent("Sources")
        let files = (FileManager.default.enumerator(at: written, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []).filter { $0.pathExtension == "swift" }
        // The sources as code only (`SwiftText`): a mention in a comment or a string's text isn't the app writing it.
        let text = SwiftText.codeOnly(Array(files.compactMap { AppFile.text($0, in: project) }.joined(separator: "\n")))
        return classes.contains { text.range(of: #"\bfinal\b(?:\s+\w+(?:\([^)]*\))?)*?\s+class\s+"# + NSRegularExpression.escapedPattern(for: $0) + #"\b"#, options: .regularExpression) == nil }
    }

    /// Live copies of the app have no classes made final from now on (`no-final`). True the first time.
    static func giveUpFinal(_ project: LampProject) -> Bool {
        let marker = LiveReload.folder(project).appendingPathComponent("no-final")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return false }
        return FileManager.default.createFile(atPath: marker.path, contents: nil)
    }

    /// Live copies of the app have no spares from now on (build.sh skips them while the file is there). True the
    /// first time, so the build is tried once more.
    static func giveUp(_ project: LampProject) -> Bool {
        let marker = LiveReload.folder(project).appendingPathComponent("no-spares")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return false }
        return FileManager.default.createFile(atPath: marker.path, contents: Data())
    }

    /// A give-up (`no-spares`, `no-final`) isn't for ever: the code that broke the build may be gone. Each whole live
    /// build counts in the marker, and the tenth takes it away, so the step is tried again now and then at the cost
    /// of one failed build when it still breaks.
    static func expireGiveUps(_ project: LampProject) {
        for name in ["no-spares", "no-final"] {
            let marker = LiveReload.folder(project).appendingPathComponent(name)
            guard let text = try? String(contentsOf: marker, encoding: .utf8) else { continue }
            let count = (Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) + 1
            if count >= 10 { try? FileManager.default.removeItem(at: marker) } else { try? "\(count)".write(to: marker, atomically: true, encoding: .utf8) }
        }
    }

    /// The file the spares need beside them: every struct the copy step gave a spare has its memberwise initializer
    /// written again, in an extension, without the spare's parameter. A reference to the initializer as a value
    /// (`.map(Item.init)`) and one a protocol requires (`init(rawValue:)`) match by their whole signature, which the
    /// spare's defaulted parameter changed; a call matches the one with fewer defaults, Swift's own or this.
    /// Written from the compiler's own list of what each struct's initializer takes, read off the app's plain sources
    /// (the live copy may not compile, which is why this is called). True when the file changed, so the build is worth
    /// trying again.
    static let memberwiseFile = "LampMemberwise.swift"
    @MainActor static func addMemberwise(_ project: LampProject) async -> Bool {
        let live = LiveReload.sources(project)
        let spared = Set(LiveReload.swiftFiles(in: live).keys.flatMap { path -> [String] in
            guard let text = try? String(contentsOf: live.appendingPathComponent(path), encoding: .utf8) else { return [] }
            return text.matches(of: #/var __lampSpare_(\w+) = LampSpare\(nil\)/#).map { String($0.1) }
        })
        let url = live.appendingPathComponent(memberwiseFile)
        let before = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var text = ""
        if !spared.isEmpty, let dump = await LiveReload.dump(of: project.dir.appendingPathComponent("Sources"), in: project, module: project.exe, macOS: Template.macMinimum(project)) {
            let declarations = SwiftSource.declarations(inDump: dump)
            // A private struct's initializer is reached only from its file, where an extension of Lamp's can't be.
            for (type, made) in declarations.memberwise.sorted(by: { $0.key < $1.key }) where spared.contains(simpleName(type)) && !declarations.privateTypes.contains(type) {
                for initializer in made where !(declarations.initializers[type] ?? []).contains(where: { $0.labels == initializer.labels && $0.types == initializer.types }) {
                    let params = zip(initializer.labels, initializer.types).map { "\($0): \($1)" }.joined(separator: ", ")
                    let args = initializer.labels.map { "\($0): \($0)" } + ["__lampSpare_\(simpleName(type)): LampSpare(nil)"]
                    text += "extension \(type) { init(\(params)) { self.init(\(args.joined(separator: ", "))) } }\n"
                }
            }
        }
        guard text != before else { return false }
        if text.isEmpty { try? FileManager.default.removeItem(at: url) } else { try? text.write(to: url, atomically: true, encoding: .utf8) }
        return true
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
        /// What to write down once the change is in (`commit`): the spares' places, and every constant remade so far.
        var slots: [String: [String: Slot]] = [:]
        var allConstants: [String] = []
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
            Dictionary(LiveReload.Group.constant.parts(in: entries).compactMap { parts -> (String, String)? in
                let field = parts.joined(separator: "\t")
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
    /// The plan, or why there is none: in words when the reason is the spares' own (no place, a property a spare
    /// can't keep), and nil when the layout's own reason says it (a type that changed otherwise than by growing).
    enum Fit {
        case plan(Plan)
        case refused(String?)
    }

    static func fitting(_ project: LampProject, before: [String], after: [String], declarations: SwiftSource.Declarations,
                        constants: [String] = []) -> Fit {
        let old = LiveReload.byType(before), new = LiveReload.byType(after)
        var map = whole(project)
        var cases: [String: Set<String>] = [:]
        for entry in after {
            let parts = entry.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, parts[1].hasPrefix("case "), let colon = parts[1].range(of: ": ") else { continue }
            // By the key and by the bare name, which a field's type uses.
            for key in Set([String(parts[0]), LiveReload.bare(String(parts[0]))]) {
                cases[key, default: []].insert(String(parts[1][parts[1].index(parts[1].startIndex, offsetBy: 5)..<colon.lowerBound]))
            }
        }
        var planned: [(type: String, name: String, slot: Slot, published: Bool, isNew: Bool)] = []
        var moved = Set<String>()
        for (type, members) in old.sorted(by: { $0.key < $1.key }) where !LiveReload.isGroup(type) {
            guard let current = new[type] else { continue }
            guard current != members, !casesAdded(type, members, current) else { continue }
            // Only additions, with what was there still there, in order.
            let extras = current.filter { !members.contains($0) }
            guard current.filter({ members.contains($0) }) == members, !extras.isEmpty else { return .refused(nil) }
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
                return .refused("\(type) has no spare place of Lamp's (a model, a Sendable class, an Equatable view, a wrapper or a struct in a file that lays memory out by hand gets none)")
            }
            // Every index in use, the retired ones' included: their values are still in them.
            var taken = Set((map[type] ?? [:]).values.map(\.index))
            for extra in extras {
                let field = extra.dropFirst(type.count + 1)
                guard !field.hasPrefix("case "), let colon = field.range(of: ": ") else { return .refused(nil) }
                var name = String(field[..<colon.lowerBound]), kind = String(field[colon.upperBound...])
                // A lazy property's storage (`$__lazy_storage_$_name`): what a spare can't keep, said as such.
                if name.hasPrefix("$__lazy_storage_$_") { return .refused("\(type).\(name.dropFirst(18)) is lazy, which a property kept in a spare can't be") }
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
                    guard !name.hasPrefix("_") else { return .refused("\(type).\(name.dropFirst()) is kept by a property wrapper, which needs storage of its own") }
                case .view:
                    guard unwrap("State") || unwrap("LazyState", underscores: 2) else { return .refused("\(type).\(name) isn't @State, and a view's spare keeps state") }
                }
                // A property an explicit CodingKeys names has to be stored for Codable to be made: it stays a field.
                if cases[type + ".CodingKeys"]?.contains(name) == true { return .refused("\(type).\(name) is named in its CodingKeys, so Codable needs it stored") }
                // What a computed property kept in a spare can't do: observers, `lazy`, a weak or unowned reference,
                // or being set in an initializer the type writes, before the stored properties are all set.
                guard let variable = declarations.variables[type + "\t" + name] else { return .refused(nil) }
                if variable.special { return .refused("\(type).\(name) has observers, is lazy, or is a weak or unowned reference, which a property kept in a spare can't be") }
                if declarations.assigned.contains(type + "\t" + name) { return .refused("\(type).\(name) is set in \(type)'s own initializer, where a property kept in a spare can't be set") }
                // A spare is observed: a property marked ignored changes while views draw, and observed would redraw them again.
                if variable.attributes.contains(where: { $0.name == "ObservationIgnored" }) { return .refused("\(type).\(name) is @ObservationIgnored, and a property kept in a spare is observed") }
                // A @Published property's `$name` publisher has no spare to come from.
                if holder == .object, variable.attributes.contains(where: { $0.name == "Published" }),
                   SwiftSource.Text(path: variable.position.file).map({ SwiftText.mentions(identifier: "$" + name, in: String(decoding: $0.bytes, as: UTF8.self)) }) == true {
                    return .refused("\(type).\(name)'s publisher ($\(name)) is used, and a property kept in a spare has none")
                }
                let optional = kind.hasSuffix("?") || kind.hasPrefix("Optional<")
                let initial = initialText(of: variable, in: declarations) ?? (optional ? "nil" : nil)
                guard let initial else { return .refused("\(type).\(name) has no starting value, which a property kept in a spare needs") }
                if holder == .view, declarations.lets.contains(type + "\t" + name) { return .refused("\(type).\(name) is a let, and a view's spare keeps state") }
                if holder == .value, !isSteady(initial, type: kind, cases: cases) {
                    return .refused("\(type).\(name) starts as \(initial), which may differ from one value to the next; a struct's property kept in a spare starts from a literal, an empty collection or one of the app's enum's cases")
                }
                moved.insert(extra)
                var generation: Int?
                if let kept = map[type]?[name] {
                    if kept.retired != true {
                        // Already in a spare: the same place, as long as it's still the same property.
                        guard kept.type == kind, (kept.holder ?? .object) == holder else { return .refused("\(type).\(name) was put in a spare as a \(kept.type), and is a \(kind) now") }
                        // A struct's spare compares a value never set by the starting value it was taken in with.
                        if let taken = kept.initial, let variable = declarations.variables[type + "\t" + name],
                           case let now = initialText(of: variable, in: declarations) ?? "nil", now != taken {
                            return .refused("\(type).\(name) starts as \(now) now, where it was put in its spare starting as \(taken), which the values the open app holds compare by")
                        }
                        planned.append((type, name, kept, published, false))
                        continue
                    }
                    // Brought back after being taken out: the old place keeps the old value, so this is a new one, kept
                    // apart by number; a class's old place stays taken under a record of its own.
                    generation = (kept.generation ?? 0) + 1
                    if holder == .object { map[type]?[retiredKey + name + " \(kept.index)"] = kept }
                }
                var index = 0
                if holder == .object {
                    guard let free = (0..<count).first(where: { !taken.contains($0) }) else { return .refused("\(type)'s \(count) spare places are all taken") }
                    taken.insert(free)
                    index = free
                }
                let known = holder == .value ? cases[enumName(kind)].map { $0.sorted() } : nil
                planned.append((type, name, Slot(index: index, type: kind, holder: holder, cases: known, generation: generation), published, true))
            }
        }
        // Every type the open app doesn't have is the library's to lay out; one it has that changed must be fitted.
        guard !planned.isEmpty || !constants.isEmpty else { return .refused(nil) }

        // Each declaration rewritten in its file, the last first so the earlier places stay where they are.
        var byFile: [String: [(binding: Int, items: [(type: String, name: String, slot: Slot, published: Bool, isNew: Bool)], constant: String?)]] = [:]
        for item in planned {
            guard let variable = declarations.variables[item.type + "\t" + item.name] else { return .refused(nil) }
            let file = variable.position.file
            var list = byFile[file] ?? []
            if let at = list.firstIndex(where: { $0.binding == variable.binding }) { list[at].items.append(item) } else { list.append((variable.binding, [item], nil)) }
            byFile[file] = list
        }
        // A constant whose value is made from a changed one is made again too (`half = size / 2`), and so on.
        let constants = withDependents(constants, in: declarations)
        // By bare names, as a constant's text names the enums its value is made from.
        let bareLayout = LiveReload.byType(LiveReload.bared(after))
        for key in constants {
            guard let variable = declarations.constants[key] else { return .refused(nil) }
            byFile[variable.position.file, default: []].append((variable.binding, [], key))
        }
        let initializers = memberwiseInitializers(for: planned.filter { $0.slot.holder == .value }.map { ($0.type, $0.name) },
                                                  declarations: declarations)
        var written: [(path: String, text: String)] = []
        for (file, edits) in byFile {
            guard let original = SwiftSource.Text(path: file) else { return .refused(nil) }
            var bytes = original.bytes
            // Each view's moved state, with the view: its `$name` was its state's binding and is now the box's, within
            // the view's own declaration, since another view in the file may have state of the same name.
            var views: [(type: String, name: String)] = []
            // Each rewrite's place in the original and how much longer it made the text, to find a view's declaration
            // in the text as rewritten.
            var shifts: [(at: Int, by: Int)] = []
            let ordered = edits.sorted { declarations.bindings[$0.binding].start.line > declarations.bindings[$1.binding].start.line
                || (declarations.bindings[$0.binding].start.line == declarations.bindings[$1.binding].start.line
                    && declarations.bindings[$0.binding].start.column > declarations.bindings[$1.binding].start.column) }
            for edit in ordered {
                let made = edit.constant.map { rewriteConstant($0, in: original, declarations: declarations, rewritten: Set(constants), layout: bareLayout) }
                    ?? rewrite(declarations.bindings[edit.binding], items: edit.items, in: original, declarations: declarations, cases: cases)
                guard let (range, text) = made else { return .refused(nil) }
                bytes.replaceSubrange(range, with: Array(text.utf8))
                shifts.append((range.lowerBound, text.utf8.count - range.count))
                for item in edit.items where item.slot.holder == .view { views.append((item.type, item.name)) }
            }
            for (type, name) in views {
                guard let declared = declarations.types[type], let from = original.offset(declared.start), let to = original.offset(declared.last) else { return .refused(nil) }
                func shifted(_ offset: Int) -> Int { offset + shifts.filter { $0.at < offset }.map(\.by).reduce(0, +) }
                let (first, last) = (shifted(from), min(shifted(to + 1), bytes.count))
                let inside = SwiftText.replacing(identifier: "$" + name, with: "__lampBinding_" + name, in: String(decoding: bytes[first..<last], as: UTF8.self))
                bytes.replaceSubrange(first..<last, with: Array(inside.utf8))
                shifts.append((from, inside.utf8.count - (last - first)))
            }
            var text = String(decoding: bytes, as: UTF8.self)
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
        return .plan(Plan(added: planned.filter(\.isNew).map { $0.type + "." + $0.name },
                          layout: after.filter { !moved.contains($0) },
                          files: written.map { URL(fileURLWithPath: $0.path).standardizedFileURL.path }.map { $0.hasPrefix(base) ? String($0.dropFirst(base.count)) : $0 },
                          constants: constants.filter { !earlier.contains($0) }.map(displayName), slots: map, allConstants: constants))
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
                    out[file, default: ""] += "\n\nextension \(LiveReload.bare(type)) {\n    init(\(params.joined(separator: ", "))) {\n"
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
        // And the cases of every enum those texts name (`Mood.allCases.count`): the value is made again each time
        // the enum grows, not only the first.
        for (type, entries) in layout {
            let cases = entries.filter { $0.contains("\tcase ") }
            guard !cases.isEmpty, case let short = String(type.split(separator: ".").last ?? ""),
                  sources.values.contains(where: { SwiftText.mentions(short, in: $0) }) else { continue }
            sources["\u{0}" + type] = cases.sorted().joined(separator: "\n")
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
    static let plainValues: Set<String> = [
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
        let key = spareKey(type: type, name: name, generation: item.slot.generation)
        let isLet = keyword == "let"
        let optional = declared.hasSuffix("?") || declared.hasPrefix("Optional<")
        guard let initial = initialText(of: variable, in: declarations) ?? (optional ? "nil" : nil) else { return nil }
        // A value set is read back as set, nil included: an optional's nil is told from "never set" by the place
        // holding a value at all, and read as `nil` when its box doesn't cast (a nil boxed as Any doesn't).
        let read: (String) -> String = { value in optional ? "return (\(value) as? \(declared)) ?? nil" : "if let v = \(value) as? \(declared) { return v }" }
        switch item.slot.holder ?? .object {
        case .object:
            let place = place(item.slot.index, in: type)
            let first = !isLiteral(initial) ? "let v: \(declared) = \(initial); \(place) = LampSpare(v); return v" : "return \(initial)"
            let getter = "get { if let p = \(place) { \(read("p.value")) }; \(first) }"
            let setter = isLet ? "" : " set { \(place) = LampSpare(newValue) }"
            return ["var \(name): \(declared) { \(getter)\(setter) }"]
        case .value:
            guard isSteady(initial, type: declared, cases: item.isNew ? cases : [enumName(item.slot.type): Set(item.slot.cases ?? [])]) else { return nil }
            if let taken = item.slot.initial, taken != initial { return nil }
            let place = place(in: type, holder: .value)
            let getter = "get { if \(place).has(\"\(key)\") { \(read("\(place).field(\"\(key)\")")) }; return \(initial) }"
            // Set back to its starting value, it's as if never set, so two values alike compare alike.
            let setter = isLet ? "" : " set { \(place) = LampSpare.setting(\"\(key)\", to: newValue, initial: { () -> \(declared) in \(initial) }(), in: \(place)) }"
            return ["var \(name): \(declared) { \(getter)\(setter) }"]
        case .view:
            guard !isLet else { return nil }
            let box = place(in: type, holder: .view)
            let read = "\(box).get(\"\(key)\") { () -> \(declared) in \(initial) }"
            return ["var \(name): \(declared) { get { \(read) } nonmutating set { \(box).set(\"\(key)\", newValue) } }",
                    "var __lampBinding_\(name): Binding<\(declared)> { Binding(get: { \(read) }, set: { \(box).set(\"\(key)\", $0) }) }"]
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

    private static func simpleName(_ type: String) -> String { LiveReload.bare(type).split(separator: ".").last.map(String.init) ?? type }

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
        if isLiteral(value) || value.range(of: #"^(?:\[[\w.<>, :?]+\]|(?:Set|Dictionary|Array|String)(?:<[\w.<>, :?\[\]]+>)?)\(\)$"#, options: .regularExpression) != nil { return true }
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
                // The escaped character is the string's, whatever it is: a raw string's `\#"` is no closing quote.
                end = after + 1
                continue
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

    /// Whether `identifier` is used in the code (not in a string or comment, nor as part of a longer name).
    static func mentions(identifier: String, in text: String) -> Bool {
        replacing(identifier: identifier, with: identifier + "\u{1}", in: text) != text
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
