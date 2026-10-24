import Foundation

/// The Undo Last Change under the latest change in the chat: which change it is offered for, if any. It is the
/// toolbar's Undo (`Store.undo`), shown where the change happened, so it's offered only where that Undo would
/// take back just this change: the latest request made the current version, nothing came after it, and nothing
/// is left unsaved. And only when the app's saved data stays readable after it: Undo puts the code back, never
/// the data, so code that can't read what the change saved would find it missing.
enum UndoOffer {
    /// The version the latest request made, when Undo Last Change can be offered under it. `parts` are the wish's
    /// other apps, whose code the version holds too.
    static func version(for project: LampProject, chat: [LogLine], parts: [LampProject] = []) async -> String? {
        guard let made = chat.last(where: { $0.kind == .user })?.version else { return nil }
        let versions = await Versions.list(project)
        guard versions.first?.id == made, let (undoing, target) = Versions.undoTarget(in: versions), undoing.id == made,
              // Not the first build: going back to the empty app isn't taking back a change.
              target.message != "Scaffold",
              await !Versions.hasUnsavedChanges(project),
              await keepsSavedDataReadable(project, parts: parts, from: target.id, to: made) else { return nil }
        return made
    }

    /// Known answers, by the two versions: they don't change, and finding one compiles the app's code twice. A
    /// look still going is shared by whoever asks meanwhile (a turn's end, the chat shown, the sidebar), rather
    /// than started again beside it.
    @MainActor private static var known: [String: Bool] = [:]
    @MainActor private static var looking: [String: Task<Bool?, Never>] = [:]

    /// Whether the code of `older` can still read whatever the code of `newer` saves. Worked out from what the
    /// compiler says each saved type holds (`LiveReload.layout`), not from the code's text. Not known (the code
    /// doesn't compile here) counts as no: the offer is left to the toolbar's Undo, which asks nothing. Only a
    /// known answer is kept, so a look that failed is made again next time. Undo takes the whole wish back, so
    /// every Swift app of it (the one at its root and each of `parts`) has to keep reading what it saved.
    @MainActor static func keepsSavedDataReadable(_ project: LampProject, parts: [LampProject] = [], from older: String, to newer: String) async -> Bool {
        let key = project.dir.path + "\n" + older + ">" + newer
        if let answer = known[key] { return answer }
        let look = looking[key] ?? Task { await findOut(project, parts: parts, from: older, to: newer) }
        looking[key] = look
        let answer = await look.value
        looking[key] = nil
        if let answer { known[key] = answer }
        return answer ?? false
    }

    private static func findOut(_ project: LampProject, parts: [LampProject], from older: String, to newer: String) async -> Bool? {
        let env = ["LAMP_OLDER": older, "LAMP_NEWER": newer]
        var changed = ""
        guard await Versions.git("git diff --name-only \"$LAMP_OLDER\" \"$LAMP_NEWER\" -- '*.swift'", cwd: project.dir, env: env,
                                 onLine: { changed += $0 + "\n" }) == 0 else { return nil }
        let files = changed.components(separatedBy: .newlines).map(\.trimmed).filter { !$0.isEmpty }
        // Each app's own files: a part's under its folder, the root's everywhere else.
        let folders = parts.map { $0.dir.lastPathComponent + "/" }
        for app in [project] + parts where app.platform.target.recipe.language == .swift {
            let prefix = app.isPart ? app.dir.lastPathComponent + "/" : ""
            let own = files.filter { prefix.isEmpty ? !folders.contains(where: $0.hasPrefix) : $0.hasPrefix(prefix) }
            // A change to pictures, settings or anything but code leaves what the app saves as it was.
            if own.isEmpty { continue }
            guard let readable = await readable(app, in: project, prefix: prefix, env: env) else { return nil }
            if !readable { return false }
        }
        return true
    }

    /// Whether one app of the wish, in `prefix` of its folder, reads with its older code what its newer code saves.
    /// An app one side doesn't have (added or taken away by the change) has nothing saved by the other to read.
    private static func readable(_ app: LampProject, in project: LampProject, prefix: String, env: [String: String]) async -> Bool? {
        for version in ["$LAMP_OLDER", "$LAMP_NEWER"] {
            if await Versions.git("git cat-file -e \"\(version):\(prefix)Sources\"", cwd: project.dir, env: env) != 0 { return true }
        }
        // Both versions' code as saved, each in a folder of its own and laid out as the app's is, so the compiler
        // reads them the same way. Not the app's own Sources: a turn may be writing there by now. Inside the app's
        // own folder, the only one its compile's sandbox opens.
        let place = ".lamp/runtime/undo-check-" + UUID().uuidString
        let folder = app.dir.appendingPathComponent(place)
        defer { try? FileManager.default.removeItem(at: folder) }
        let widget = Template.widgetFolder + "/" + Template.sharedWidgetFolder
        let extract = ["older", "newer"].map { side in
            let version = side == "older" ? "$LAMP_OLDER" : "$LAMP_NEWER"
            let tree = prefix.isEmpty ? "\"\(version)\"" : "\"\(version):\(prefix.dropLast())\""
            return """
                mkdir -p '\(prefix)\(place)/\(side)' && git archive \(tree) Sources | tar -x -C '\(prefix)\(place)/\(side)' && \
                { ! git cat-file -e "\(version):\(prefix)\(widget)" 2>/dev/null || git archive \(tree) '\(widget)' | tar -x -C '\(prefix)\(place)/\(side)'; }
                """
        }.joined(separator: " && ")
        guard await Versions.git(extract, cwd: project.dir, env: env) == 0 else { return nil }
        let ios = app.platform == .iphone
        async let before = LiveReload.layout(of: folder.appendingPathComponent("older/Sources"), in: app, files: nil, module: app.exe, macOS: Template.macMinimum(app),
                                             ios: ios, rawValues: true)
        async let after = LiveReload.layout(of: folder.appendingPathComponent("newer/Sources"), in: app, files: nil, module: app.exe, macOS: Template.macMinimum(app),
                                            ios: ios, rawValues: true)
        guard let before = await before, let after = await after else { return nil }
        return readable(before: before, after: after)
    }

    /// Whether code with the `before` layout reads every value saved by code with the `after` one. A saved
    /// type is one the compiler gave coding keys (`Codable`, saved by `LampStore` and `LampSync` as JSON by
    /// those keys, which are their raw values when they have them). The older code reads it when each key it needs
    /// is still written and holds the same type (an optional one it can do without, but not read as another
    /// type), and when no enum it reads writes a value it doesn't know.
    static func readable(before: [String], after: [String]) -> Bool {
        func byType(_ entries: [String]) -> [String: [String]] {
            var types: [String: [String]] = [:]
            for entry in entries {
                let parts = entry.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                guard parts.count == 2 else { continue }
                types[parts[0], default: []] += parts[1].isEmpty ? [] : [parts[1]]
            }
            return types
        }
        let old = byType(before), new = byType(after)
        // "name: Type" and "case name: Type" as name and type.
        func members(_ list: [String]) -> [String: String] {
            Dictionary(list.filter { !$0.hasPrefix("case ") }.compactMap { member in
                member.range(of: ": ").map { (String(member[..<$0.lowerBound]), String(member[$0.upperBound...])) }
            }, uniquingKeysWith: { first, _ in first })
        }
        // "case name: Type = \"raw\"" as its name and what it writes: its raw value, else its name.
        func cases(_ list: [String]) -> [String: String] {
            Dictionary(list.filter { $0.hasPrefix("case ") }.map { entry in
                let name = String(entry.dropFirst(5).prefix { $0 != ":" })
                guard let raw = entry.range(of: " = ", options: .backwards) else { return (name, name) }
                var written = String(entry[raw.upperBound...])
                if written.count >= 2, written.hasPrefix("\""), written.hasSuffix("\"") { written = String(written.dropFirst().dropLast()) }
                return (name, written)
            }, uniquingKeysWith: { first, _ in first })
        }
        func optional(_ type: String) -> Bool { type.hasSuffix("?") || type.hasPrefix("Optional<") }
        func unwrapped(_ type: String) -> String {
            if type.hasSuffix("?") { return String(type.dropLast()) }
            if type.hasPrefix("Optional<"), type.hasSuffix(">") { return String(type.dropFirst(9).dropLast()) }
            return type
        }
        // The app's own types a member's type names: "[Entry]", "Entry?", "[String: Plant.Kind]".
        let names = try! NSRegularExpression(pattern: #"[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*"#)
        func named(in type: String) -> [String] {
            names.matches(in: type, range: NSRange(type.startIndex..., in: type)).compactMap { match in
                Range(match.range, in: type).map { String(type[$0]) }
            }.filter { old[$0] != nil }
        }

        var waiting = old.keys.filter { $0.hasSuffix(".CodingKeys") }.map { String($0.dropLast(".CodingKeys".count)) }
        var seen = Set<String>()
        while let type = waiting.popLast() {
            guard seen.insert(type).inserted, let held = old[type] else { continue }
            // An enum: a value it writes that the older code doesn't know (a case added, a raw value changed).
            let oldValues = Set(cases(held).values)
            if !oldValues.isEmpty, !Set(cases(new[type] ?? []).values).isSubset(of: oldValues) { return false }
            if let keys = old[type + ".CodingKeys"] {
                let oldMembers = members(held), newMembers = members(new[type] ?? [])
                // Which property the newer code writes under each key.
                let newProperties = Dictionary(cases(new[type + ".CodingKeys"] ?? []).map { ($0.value, $0.key) },
                                               uniquingKeysWith: { first, _ in first })
                for (property, key) in cases(keys) {
                    guard let wanted = oldMembers[property] else { continue }
                    waiting += named(in: wanted)
                    // A key no longer written is fine only for what the older code can do without.
                    guard let written = newProperties[key].flatMap({ newMembers[$0] }) else {
                        if optional(wanted) { continue }
                        return false
                    }
                    // One still written must hold what the older code reads there. An optional the newer code
                    // writes leaves the key out when empty, which a required one can't be read without.
                    if optional(wanted) ? unwrapped(written) != unwrapped(wanted) : written != wanted { return false }
                }
            }
        }
        return true
    }
}
