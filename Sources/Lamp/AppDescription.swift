import Foundation

/// What an app is, in a sentence, for someone it's shared with: `about.json` at the app's root, which the
/// agent writes (`Agent.Rules.about`) the way it writes icon.json. Lamp reads it as data and takes nothing
/// from it that isn't one plain line of text: a file that's missing, isn't JSON or holds anything else is
/// an app with no description.
enum AppDescription {
    static let file = "about.json"
    /// The most a line holds and still fits the four lines the desk gives it beside the app's picture, in its
    /// one size (`WishDesk.stage`). The agent is told it (`Agent.Rules.about`) and asked to shorten a longer line.
    static let limit = 90

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

    /// Gives an app the description a shared file came with, or none when the file had none.
    static func write(_ description: String?, for project: LampProject) throws {
        let url = project.dir.appendingPathComponent(file)
        guard let description else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try JSONSerialization.data(withJSONObject: ["description": description], options: [.prettyPrinted]).write(to: url)
    }
}
