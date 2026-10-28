import Foundation

/// A request to make a game more fun ("Make it a lot more fun", one of New York's first changes, or the person's own few
/// words for it). Asked that plainly, a model reliably makes a game better; the request carries a note naming what it
/// asks for, and what makes a game fun is said once, in the game skill's "Fun".
enum GameFun {
    /// Whether an app is a game, however it's made.
    static func isGame(_ project: LampProject) -> Bool {
        DeviceApps.isGame(project) || Skills.gameUse(project) != nil
    }

    /// Whether a request asks for it: a few words that ask for more fun. A long request that mentions fun along the way
    /// is its own.
    static func asked(_ request: String) -> Bool {
        let words = request.split(whereSeparator: \.isWhitespace)
        return words.count <= 12 && request.range(of: #"(?i)\bmore fun\b"#, options: .regularExpression) != nil
    }

    /// The note at the end of such a request, for every engine alike.
    static func note(for project: LampProject, request: String) -> String {
        guard isGame(project), asked(request) else { return "" }
        return """
        \n\n---
        What this request asks for (from Lamp): make the game a lot more fun, as the game skill's "Fun" says (open it if \
        you haven't). Play it first and find what's flat. Then give it a better core loop and difficulty curve; juice \
        (quick feedback, sound, particles, and a little screen shake on the big moments); and surprises and small \
        delights, often. Playtest it in the preview before you finish, and fix what still isn't fun.
        """
    }
}
