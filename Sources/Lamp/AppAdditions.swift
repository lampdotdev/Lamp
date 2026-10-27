import Foundation

/// Whether the person chose to add one more app to a wish that has one (`make_app_for` with `another`). The agent can
/// only ask: Lamp puts its own card up ("Add another app" or "Change this app"), only the person can answer it, and
/// Lamp keeps what was chosen, in Lamp's own folder by the wish's instance, never in the wish's folder, which the agent
/// can write. A choice to add is for one app, of the code the card was for, and is used once: the app it made is
/// remembered until the person next writes, so a call repeated after its answer was lost gets that same app back
/// rather than a third. Anything the person types instead of choosing adds nothing.
enum AppAdditions {
    struct Kept: Codable, Equatable {
        /// The card that's up, and the code of the app it asks about (`key`).
        var asking: Pending?
        /// "Add another app" was chosen for an app of this code, and no app has been added for it yet.
        var granted: String?
        /// The app the last choice added: its code and folder.
        var made: Pending?
    }

    struct Pending: Codable, Equatable {
        var key: String
        var card: UUID?
        var folder: String?
    }

    static let add = "Add another app"
    static let change = "Change this app"
    static let changeOne = "Change one of its apps"

    private static var folder: URL { Edition.supportFolder.appendingPathComponent("AppAdditions") }

    private static func file(_ wish: LampProject) -> URL {
        folder.appendingPathComponent((wish.instance.isEmpty ? wish.id : wish.instance) + ".json")
    }

    static func kept(_ wish: LampProject) -> Kept {
        (try? Data(contentsOf: file(wish))).flatMap { try? JSONDecoder().decode(Kept.self, from: $0) } ?? Kept()
    }

    private static func save(_ kept: Kept, for wish: LampProject) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if kept == Kept() { try? FileManager.default.removeItem(at: file(wish)); return }
        try? JSONEncoder().encode(kept).write(to: file(wish), options: .atomic)
    }

    /// What a choice to add is for: the app's code (`AppKinds.code`), so one chosen for a Mac app adds no Android app.
    static func key(_ target: AppTarget) -> String { target.code }

    /// The card: one question, two answers, only the person's to give. `new` is the app asked for ("the Mac app"),
    /// `existing` the wish's apps as the agent is told of them.
    static func card(new: String, existing: [String]) -> Talk.Ask {
        let one = existing.count == 1
        return Talk.Ask(layout: .steps, questions: [
            Talk.Question(question: "Add another app to this wish?",
                          options: [Talk.Option(title: add, detail: "Make \(new) as well. " + (one ? "The one it has stays." : "The ones it has stay."),
                                                symbol: "plus.square.on.square"),
                                    Talk.Option(title: one ? change : changeOne, detail: "No new app: " + (one ? "change the one it has." : "change one it has."),
                                                symbol: "arrow.triangle.2.circlepath")],
                          personOnly: true),
        ], addition: true)
    }

    /// The card is up: what it asks about is noted, to be allowed when the person chooses to add.
    static func asking(card: UUID, key: String, for wish: LampProject) {
        var kept = kept(wish)
        kept.asking = Pending(key: key, card: card)
        save(kept, for: wish)
    }

    /// The person's answer to the card, as the option they chose, kept once it's delivered to the agent. Only an answer
    /// to the card that's up counts.
    static func answer(_ choice: String, card: UUID, for wish: LampProject) {
        var kept = kept(wish)
        guard let asking = kept.asking, asking.card == card else { return }
        kept.asking = nil
        kept.granted = choice == add ? asking.key : nil
        save(kept, for: wish)
    }

    /// A message reached the agent: when it's the answer chosen on Lamp's card about adding an app (`card`, the card it
    /// answers), what was chosen there is kept. A message typed instead, an answer to any other card (the agent's own,
    /// whatever its words), or one taken back before it was delivered keeps nothing.
    static func delivered(card: UUID?, in lines: [LogLine], for wish: LampProject) {
        guard let card, let ask = lines.first(where: { $0.id == card })?.ask, ask.addition == true, ask.typed != true,
              let choice = ask.answers?.first else { return }
        answer(choice, card: card, for: wish)
    }

    /// Uses the person's choice to add an app of this code: true once, then never again for that choice.
    static func take(_ key: String, for wish: LampProject) -> Bool {
        var kept = kept(wish)
        guard kept.granted == key else { return false }
        kept.granted = nil
        save(kept, for: wish)
        return true
    }

    /// The folder the person's last choice added an app of this code in, while it's remembered.
    static func added(_ key: String, for wish: LampProject) -> String? {
        let made = kept(wish).made
        return made?.key == key ? made?.folder : nil
    }

    /// The folder kept for the app a choice adds, noted before anything is made, so a repeated call finds it.
    static func adding(_ key: String, in folder: String, for wish: LampProject) {
        var kept = kept(wish)
        kept.made = Pending(key: key, folder: folder)
        save(kept, for: wish)
    }

    /// The person wrote to the chat (not by choosing on a card): a card still up, a choice not used and the memory of the
    /// last app added are all spent.
    static func endExchange(for wish: LampProject) {
        guard kept(wish) != Kept() else { return }
        save(Kept(), for: wish)
    }

    /// Forgotten with the wish.
    static func forget(_ wish: LampProject) { try? FileManager.default.removeItem(at: file(wish)) }
}
