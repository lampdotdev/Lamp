import Foundation

/// A request to make a game more fun ("Make it a lot more fun", one of New York's first changes, or the person's own
/// words for it). Asked that plainly, a model reliably makes a game better; the request carries a note naming what it
/// asks for, and what makes a game fun is said once, in the game skill's "Fun".
enum GameFun {
    /// Whether a wish has a game among its apps, however it's made: its own, or one in a folder of its own (`Game/`),
    /// whose chat is the wish's.
    static func hasGame(_ apps: [LampProject]) -> Bool {
        apps.contains { DeviceApps.isGame($0) || Skills.gameUse($0) != nil }
    }

    /// Whether a request is that request: the whole of it, or the answer that ends a card's message ("Make New York
    /// yours? Make it a lot more fun."), asking for more fun from the game as a whole. A request that scopes it ("make
    /// the menu more fun"), turns it down ("don't make it more fun") or goes on to other things is its own.
    static func asked(_ request: String, name: String = "") -> Bool {
        let whole = ["it", "this", "this game", "the game", "the whole game", name.lowercased()].filter { !$0.isEmpty }
            .map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let pattern = #"(?i)(?:^|[?\n])\s*(?:please\s+|can you\s+|now\s+)?make\s+(?:"# + whole
            + #")\s+(?:(?:a lot|a whole lot|so much|much|way|even|a bit|a little)\s+)?more\s+fun(?:\s+please)?[.!]*\s*$"#
        return request.range(of: pattern, options: .regularExpression) != nil
    }

    /// The note at the end of such a request, for every engine alike, whether it starts a turn or is handed to one
    /// already running.
    static func note(for wish: LampProject, apps: [LampProject], request: String) -> String {
        guard hasGame(apps), asked(request, name: wish.name) else { return "" }
        return """
        \n\n---
        What this request asks for (from Lamp): make the game a lot more fun, as the game skill's "Fun" says (open it if \
        you haven't). Play it first and find what's flat. Then give it a better core loop and difficulty curve; juice \
        (quick feedback, sound, particles, and a little screen shake on the big moments); and surprises and small \
        delights, often. Playtest it in the preview before you finish, and fix what still isn't fun.
        """
    }
}
