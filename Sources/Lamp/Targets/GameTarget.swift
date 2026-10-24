import Foundation

extension Platform {
    /// A game: C++ on Lamp's game kit, one code wherever it's played (`GameKit`). Its home is the Mac; an iPhone or iPad
    /// and an Xbox are places it's given as well (`LampProject.places`), never another kind.
    static let game = Platform(kind: "game")
}

extension Target {
    static let game = Target(
        platform: .game, places: [.mac, .ios, .device],
        identity: Identity(name: "the game", phrase: "a game played on the Mac, an iPhone or iPad, or an Xbox", analytics: "game",
                           made: { _, _ in "a game" },
                           devices: Words(words: [("game", "\"game\" for a game (with \"mac\", \"iphone\" and \"xbox-one\" for the places it's played on)",
                                                   "\"game\" for a 3D game or one played with a controller")],
                                          hint: "[\"game\"] for a 3D game, or a game played with a controller or on their Xbox, whatever device it names; "
                                              + "with \"iphone\" when it's to be played on a phone or iPad too, and with \"xbox-one\" when it's for their Xbox. "
                                              + "A 2D game played with the mouse or by tapping (a puzzle, a board, card or word game, a simple arcade game) "
                                              + "is an app for this Mac or the iPhone",
                                          claims: GameKit.claims, owns: { $0 == GameKit.xboxKind || $0 == "xbox" }, alone: true),
                           tryOnHelp: { _ in "Where it plays: this Mac, an iPhone or iPad, or your Xbox" },
                           place: { _ in .window }),
        guidance: Guidance(prompt: Agent.gamePrompt(for:), changeRules: { _ in Agent.Rules.gameChange },
                           skills: { [] },
                           noAI: { _ in "- None: a game has none of Lamp's AI building blocks." },
                           elsewhere: { _ in nil }),
        recipe: Recipe(language: .cpp, fill: GameKit.fill, ownedFiles: GameKit.write(for:), support: GameKit.write(for:),
                       isMade: GameKit.isMade, scaffolded: { dir, _ in GameKit.isMade(dir) },
                       sources: { _ in ["Game", "Assets", "icon.json", "capabilities.json"] },
                       // The kit is part of what's built: a new Lamp with a new kit builds the game again.
                       inputs: { _ in GameKit.stamp },
                       builtURL: { project in
                           project.onDevice ? DeviceApps.packageURL(for: project)
                               : project.dir.appendingPathComponent(project.onIOS ? "build/iOS/\(project.exe).app" : "build/\(project.exe).app")
                       },
                       marker: GameKit.marker,
                       // A game from before games were a kind of their own carries the device app's marker.
                       refines: .device,
                       shareRefusal: "Lamp doesn't share games yet."),
        part: nil,
        // Nothing up front: the Mac builds it with Xcode's tools and one small download, fetched as it's first built;
        // what each further place needs is asked for when it's given (`GameKit.notReady`).
        setup: .none,
        startsAt: [.mac])
}

extension Language {
    static let cpp = Language(name: "c++", code: "the game's C++ in Game/", leftover: "the files in Game/") {
        "Write the app again as a game in C++ in Game/ against Lamp's game kit (the scaffold is there), reading \($0) for what it does, then delete \($1) with delete_file. "
    }
}
