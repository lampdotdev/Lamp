import Foundation
import UniformTypeIdentifiers

/// What an app is, in a sentence, for someone it's shared with: `about.json` at the app's root, which the
/// agent writes (`Agent.Rules.about`) the way it writes icon.json. Lamp reads it as data and takes nothing
/// from it that isn't one plain line of text: a file that's missing, isn't JSON or holds anything else is
/// an app with no description.
///
/// The same file says what a Mac app opens when Finder hands it something (`opens`, `Agent.Rules.finder`):
/// a list of plain names, checked the same way whoever wrote them, the agent here or the sender of a shared
/// file, and declared in the app's Info.plist after each build.
enum AppDescription {
    static let file = "about.json"

    static func description(of project: LampProject) -> String? {
        description(at: project.dir.appendingPathComponent(file))
    }

    static func description(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let words = object["description"] as? String else { return nil }
        return valid(words)
    }

    /// The words when they're one line with something on it, without the white space around them. The same
    /// test for what the agent wrote here and for what a shared file says of itself.
    static func valid(_ words: String) -> String? {
        let line = words.trimmed
        return line.isEmpty || line.contains(where: \.isNewline) ? nil : line
    }

    /// Gives an app the description and the list of what it opens that a shared file came with, or none
    /// when the file had none. Only what passed the checks is written, never the sender's file.
    static func write(_ description: String?, opens: [String] = [], for project: LampProject) throws {
        let url = project.dir.appendingPathComponent(file)
        var object: [String: Any] = [:]
        if let description { object["description"] = description }
        let checked = valid(opens: opens)
        if !checked.isEmpty { object["opens"] = checked }
        guard !object.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url)
    }

    // MARK: - What the app opens

    /// What the app says it opens, checked: "folder", "file" for any file, a file extension ("png"), or a
    /// type identifier ("public.image").
    static func opens(of project: LampProject) -> [String] {
        opens(at: project.dir.appendingPathComponent(file))
    }

    static func opens(at url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let entries = object["opens"] as? [Any] else { return [] }
        return valid(opens: entries.compactMap { $0 as? String })
    }

    /// The entries that are plain names, in lower case, each once: letters, digits, dots and dashes only,
    /// so nothing else can reach the app's Info.plist. The same test for what the agent wrote and for what
    /// a shared file says of itself; at most 40 of them.
    static func valid(opens entries: [String]) -> [String] {
        var kept: [String] = []
        for entry in entries {
            var name = entry.trimmingCharacters(in: .whitespaces).lowercased()
            if name.hasPrefix("."), name.count > 1 { name.removeFirst() }
            let plain = name.range(of: #"^[a-z0-9]{1,16}$"#, options: .regularExpression) != nil
            let identifier = name.contains(".") && name.range(of: #"^[a-z0-9][a-z0-9.-]{2,80}$"#, options: .regularExpression) != nil
            if plain || identifier, !kept.contains(name), kept.count < 40 { kept.append(name) }
        }
        return kept
    }

    /// What a checked list comes to in a Mac app's Info.plist, or nothing. Until an app declares a kind of
    /// file, macOS hands it none: Finder won't take a drop on its icon or list it in Open With, and a
    /// confined program (the agent's shell, Sandbox) asking to open a file with it is refused with error
    /// -10820. The app is only ever an alternative for them, so declaring folders or pictures never makes it
    /// what opens them on a double-click.
    static func documentTypes(for opens: [String]) -> [[String: Any]] {
        var types: [String] = [], extensions: [String] = []
        for name in valid(opens: opens) {
            if name == "folder" { types.append("public.folder") }
            else if name == "file" { types.append("public.data") }
            else if name.contains(".") { types.append(name) }
            // An extension macOS knows becomes its type; one it doesn't is declared as the extension.
            else if let known = UTType(filenameExtension: name), !known.isDynamic { types.append(known.identifier) }
            else { extensions.append(name) }
        }
        guard !types.isEmpty || !extensions.isEmpty else { return [] }
        var type: [String: Any] = ["CFBundleTypeName": "Document", "CFBundleTypeRole": "Viewer", "LSHandlerRank": "Alternate"]
        if !types.isEmpty { type["LSItemContentTypes"] = types.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } } }
        if !extensions.isEmpty { type["CFBundleTypeExtensions"] = extensions }
        return [type]
    }

    /// Puts what the app opens into a freshly built Mac app's Info.plist, before it's signed, the way its
    /// stamp is (BuildStamp.write): written by Lamp from checked values, never by the build script.
    static func writeDocumentTypes(of project: LampProject, to app: URL) {
        let url = app.appendingPathComponent("Contents/Info.plist")
        guard let info = NSMutableDictionary(contentsOf: url) else { return }
        let types = documentTypes(for: opens(of: project))
        if types.isEmpty { info.removeObject(forKey: "CFBundleDocumentTypes") } else { info["CFBundleDocumentTypes"] = types }
        info.write(to: url, atomically: true)
    }
}
