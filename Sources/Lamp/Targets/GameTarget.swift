import Foundation

extension Platform {
    /// A game: C++ on Lamp's game kit, one code wherever it's played (`GameKit`). Its home is the Mac; an iPhone or iPad
    /// and an Xbox are places it's given as well (`LampProject.places`), never another kind.
    static let game = Platform(kind: "game")
}

extension Target {
    static let game = Target(
        platform: .game, places: [.mac, .ios, .android, .device],
        identity: Identity(name: "the game", phrase: "a game played on the Mac, an iPhone or iPad, Android or an Xbox", analytics: "game",
                           made: { _, _ in "a game" },
                           devices: Words(words: [("game", "\"game\" for a game (with \"mac\", \"iphone\", \"android\" and \"xbox-one\" for the places it's played on)",
                                                   "\"game\" for a game played in real time")],
                                          hint: "[\"game\"] for a game played in real time (3D, racing, a platformer, a shooter, an arcade or sports game, "
                                              + "anything played with a controller or on their Xbox), whatever device it names; with \"iphone\" when it's to "
                                              + "be played on an iPhone or iPad too, \"android\" on an Android phone, with \"xbox-one\" when it's for their Xbox. "
                                              + "A game played by clicking or tapping through turns (a quiz, a puzzle, a board, card or word game) is an app",
                                          claims: GameKit.claims, owns: { $0 == GameKit.xboxKind || $0 == "xbox" }, alone: true),
                           tryOnHelp: { _ in "Where it plays: this Mac, an iPhone or iPad, an Android phone or tablet, or your Xbox" },
                           place: { _ in .window }),
        guidance: Guidance(prompt: Agent.gamePrompt(for:), changeRules: Agent.Rules.gameChange,
                           skills: { [] },
                           // A C++ game from before three.js games has none of Lamp's building blocks; a three.js game has LampAI.
                           noAI: { GameKit.engine($0) == .native ? "- None: a game in C++ has none of Lamp's AI building blocks." : nil },
                           elsewhere: { _ in nil }),
        recipe: Recipe(language: .game, fill: GameKit.fill, ownedFiles: GameKit.write(for:), support: GameKit.write(for:),
                       isMade: GameKit.isMade, scaffolded: { dir, _ in GameKit.isMade(dir) },
                       // Sources/ too: the Swift that answers the page's calls of the device is the agent's (Native.swift).
                       sources: { _ in ["Game", "Assets", GameKit.webFolder, "Sources", "icon.json", "capabilities.json"] },
                       // The kit is part of what's built: a new Lamp with a new kit builds the game again.
                       inputs: { _ in GameKit.stamp },
                       builtURL: { project in
                           project.onDevice ? DeviceApps.packageURL(for: project) : project.onAndroid ? GameAndroid.apk(project)
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
        startsAt: [.mac], hostedByLamp: true, showsPage: { GameKit.engine($0) == .web })
}

extension Language {
    static let game = Language(name: "game", code: "the game's page in Web/", leftover: "the game's files in Web/") {
        "Write the app again as a game drawn with three.js in Web/ against Lamp's game runtime (the scaffold is there), reading \($0) for what it does, then delete \($1) with delete_file. "
    }
}
