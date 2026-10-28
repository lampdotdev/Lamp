import Foundation
import LampSidebarKit

/// "Make it a lot more fun": the change Lamp offers for every game wherever it offers changes (a starter's card, the
/// next request it suggests, the ideas in the remix panel). Asked that plainly, a model reliably makes a game better,
/// so it's always one of the choices. The words are the person's request; what they mean is said once, in the game
/// skill's "Fun", and the request carries a note naming the four things it asks for.
enum GameFun {
    static let title = "Make it a lot more fun"
    static let symbol = "party.popper"

    /// Whether Lamp offers it for an app: any game, however it's made.
    static func offered(for project: LampProject) -> Bool {
        DeviceApps.isGame(project) || Skills.gameUse(project) != nil
    }

    /// Whether a request asks for it: the change chosen on a card or taken from the message box, or the person's own
    /// few words for it ("make it more fun"). A long request that mentions fun along the way is its own.
    static func asked(_ request: String) -> Bool {
        let words = request.split(whereSeparator: \.isWhitespace)
        return words.count <= 12 && request.range(of: #"(?i)\bmore fun\b"#, options: .regularExpression) != nil
    }

    /// The note at the end of such a request, for every engine alike.
    static func note(for project: LampProject, request: String) -> String {
        guard offered(for: project), asked(request) else { return "" }
        return """
        \n\n---
        What this request asks for (from Lamp): make the game a lot more fun, as the game skill's "Fun" says (open it if \
        you haven't). Play it first and find what's flat. Then give it a better core loop and difficulty curve; juice \
        (quick feedback, sound, particles, and a little screen shake on the big moments); and surprises and small \
        delights, often. Playtest it in the preview before you finish, and fix what still isn't fun.
        """
    }

    /// The same change as one of the remix panel's ideas.
    static var idea: RemixIdea { RemixIdea(text: title, symbol: symbol) }
}
