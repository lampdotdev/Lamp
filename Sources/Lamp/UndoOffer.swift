import Foundation

/// The Undo Last Change under the latest change in the chat: which change it is offered for, if any. It is the
/// toolbar's Undo (`Store.undo`), shown where the change happened, so it's offered only where that Undo would
/// take back just this change: the latest request made the current version, nothing came after it, and nothing
/// is left unsaved. And only when the app's saved data stays readable after it: Undo puts the code back, never
/// the data, so code that can't read what the change saved would find it missing.
enum UndoOffer {
    /// The version the latest request made, when Undo Last Change can be offered under it.
    static func version(for project: LampProject, chat: [LogLine]) async -> String? {
        guard let made = chat.last(where: { $0.kind == .user })?.version else { return nil }
        let versions = await Versions.list(project)
        guard versions.first?.id == made, let (undoing, target) = Versions.undoTarget(in: versions), undoing.id == made,
              // Not the first build: going back to the empty app isn't taking back a change.
              target.message != "Scaffold",
              await !Versions.hasUnsavedChanges(project),
              await keepsSavedDataReadable(project, from: target.id, to: made) else { return nil }
        return made
    }

    /// Known answers, by the two versions: they don't change, and finding one compiles the app's code twice.
    @MainActor private static var known: [String: Bool] = [:]

    /// Whether the code of `older` can still read whatever the code of `newer` saves. Worked out from what the
    /// compiler says each saved type holds (`LiveReload.layout`), not from the code's text. Not known (the code
    /// doesn't compile here) counts as no: the offer is left to the toolbar's Undo, which asks nothing.
    @MainActor static func keepsSavedDataReadable(_ project: LampProject, from older: String, to newer: String) async -> Bool {
        let key = older + ">" + newer
        if let answer = known[key] { return answer }
        let answer = await findOut(project, from: older, to: newer)
        known[key] = answer
        return answer
    }

    private static func findOut(_ project: LampProject, from older: String, to newer: String) async -> Bool {
        let env = ["LAMP_OLDER": older, "LAMP_NEWER": newer]
        var changed = ""
        guard await Versions.git("git diff --name-only \"$LAMP_OLDER\" \"$LAMP_NEWER\" -- '*.swift'", cwd: project.dir, env: env,
                                 onLine: { changed += $0 }) == 0 else { return false }
        // A change to pictures, settings or anything but code leaves what the app saves as it was.
        if changed.trimmed.isEmpty { return true }
        // The older code, beside the app's own and laid out as it is, so the compiler reads it the same way.
        let folder = project.dir.appendingPathComponent(".lamp/runtime/undo-check")
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let widget = Template.widgetFolder + "/" + Template.sharedWidgetFolder
        let extract = """
            git archive "$LAMP_OLDER" Sources | tar -x -C .lamp/runtime/undo-check && \
            { ! git cat-file -e "$LAMP_OLDER:\(widget)" 2>/dev/null || git archive "$LAMP_OLDER" '\(widget)' | tar -x -C .lamp/runtime/undo-check; }
            """
        guard await Versions.git(extract, cwd: project.dir, env: env) == 0 else { return false }
        let ios = project.platform == .iphone
        async let before = LiveReload.layout(of: folder.appendingPathComponent("Sources"), files: nil, module: project.exe, ios: ios)
        async let after = LiveReload.layout(of: project.dir.appendingPathComponent("Sources"), files: nil, module: project.exe, ios: ios)
        guard let before = await before, let after = await after else { return false }
        return readable(before: before, after: after)
    }

    /// Whether code with the `before` layout reads every value saved by code with the `after` one. A saved
    /// type is one the compiler gave coding keys (`Codable`, saved by `LampStore` and `LampSync` as JSON by
    /// those keys). The older code reads it when each key it needs is still saved and holds the same type
    /// (an optional one it can do without), and when no enum it reads has a case it doesn't know.
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
        func cases(_ list: [String]) -> Set<String> {
            Set(list.filter { $0.hasPrefix("case ") }.map { String($0.dropFirst(5).prefix { $0 != ":" }) })
        }
        func optional(_ type: String) -> Bool { type.hasSuffix("?") || type.hasPrefix("Optional<") }
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
            // An enum: a case added is one the older code can't read.
            if !cases(held).isEmpty, !cases(new[type] ?? []).isSubset(of: cases(held)) { return false }
            if let keys = old[type + ".CodingKeys"] {
                let oldMembers = members(held), newMembers = members(new[type] ?? [])
                let newKeys = cases(new[type + ".CodingKeys"] ?? [])
                for key in cases(keys) {
                    guard let wanted = oldMembers[key] else { continue }
                    waiting += named(in: wanted)
                    if optional(wanted) { continue }
                    guard newKeys.contains(key), newMembers[key] == wanted else { return false }
                }
            }
        }
        return true
    }
}
