import Foundation

extension Platform {
    /// A game: a page on Lamp's game runtime, Phaser for 2D or three.js for 3D (or, made before those, C++ on Lamp's game kit), one code wherever it's played
    /// (`GameKit`). Its home is the Mac; every other place a page goes (`Places.pagePlaces`) is one it's given as well
    /// (`LampProject.places`), never another kind.
    static let game = Platform(kind: "game")
}

extension Target {
    static let game = Target(
        // A page: wherever one of Lamp's web hosts is.
        platform: .game, places: Places.pagePlaces,
        identity: Identity(name: "the game", phrase: "a game played on the Mac, an iPhone or iPad, Android, a TV or an Xbox", analytics: "game",
                           made: { _, _ in "a game" },
                           devices: Words(words: [("game", "\"game\" for a game (where it's played beside the Mac, any place a page goes, goes in `places`)",
                                                   "\"game\" for a game played in real time")],
                                          hint: "[\"game\"] for a game played in real time (3D, racing, a platformer, a shooter, an arcade or sports game, "
                                              + "anything played with a controller or on their Xbox), whatever device it names, with where else it's played in \"places\": "
                                              + "\"iphone\" for an iPhone or iPad, \"android\" for an Android phone, \"android-tv\" for a Google TV, Android TV or Fire TV, "
                                              + "\"tv\" for a Samsung or LG TV, \"xbox-one\" for their Xbox. "
                                              + "A game played by clicking or tapping through turns (a quiz, a puzzle, a board, card or word game) is an app, "
                                              + "and so is one they want only on their Mac or iPhone with what only Apple's apps have (Game Center, a widget, inside an app of theirs)",
                                          claims: GameKit.claims, owns: { $0 == GameKit.xboxKind || $0 == "xbox" }, alone: true),
                           tryOnHelp: { _ in "Where it plays: this Mac, an iPhone or iPad, an Android phone, tablet or TV, a Samsung or LG TV, or your Xbox" },
                           place: { _ in .window }),
        guidance: Guidance(prompt: Agent.gamePrompt(for:), changeRules: Agent.Rules.gameChange,
                           skills: { [] },
                           // A C++ game from before three.js games has none of Lamp's building blocks; a three.js game has LampAI.
                           noAI: { GameKit.engine($0) == .native ? "- None: a game in C++ has none of Lamp's AI building blocks." : nil },
                           elsewhere: { _ in nil }),
        recipe: Recipe(language: .game, fill: GameKit.fill, ownedFiles: GameKit.write(for:), support: GameKit.write(for:),
                       isMade: GameKit.isMade, scaffolded: { dir, _ in GameKit.isMade(dir) },
                       // Sources/ too: the Swift that answers the page's calls of the device is the agent's (Native.swift); and
                       // Phone/, the page phones join the game from; and src/, a TypeScript game's source.
                       sources: { _ in ["Game", "Assets", GameKit.webFolder, GameKit.sourceFolder, TVTemplate.phoneFolder, "Sources", "icon.json", "capabilities.json"] },
                       // The kit is part of what's built: a new Lamp with a new kit builds the game again. So is what the
                       // page is told of the device it's built for: a change to that row builds it again too.
                       inputs: { GameKit.stamp + GameAndroid.stamp + GamePage.buildInput(for: $0) + GameKit.playerInput(for: $0) },
                       builtURL: { project in
                           project.onTV ? TVs.stagingFolder(for: project).appendingPathComponent("web/index.html")
                               : project.onDevice ? DeviceApps.packageURL(for: project) : project.onAndroid ? GameAndroid.apk(project)
                               : project.dir.appendingPathComponent(project.onIOS ? "build/iOS/\(project.exe).app" : "build/\(project.exe).app")
                       },
                       marker: GameKit.marker,
                       // A game from before games were a kind of their own carries the device app's marker.
                       refines: .device,
                       // A three.js game is shared as its page (`GameFiles`); one in C++ is refused in `Sharing.export`.
                       shareRefusal: nil),
        part: Part(folder: "Game", family: "game", word: "game", menu: ("Game", "gamecontroller"), rules: { Agent.gamePrompt(part: $0, alone: $1) },
                   // How its places are given beside the wish's other apps, and how it reaches them.
                   wishRule: Agent.Rules.gameAmongApps) { dir, wish in
            AppFile.read(dir.appendingPathComponent(GameKit.marker), inFolder: wish, last: 1) != nil
        },
        // Nothing up front: the Mac builds it with Xcode's tools and one small download, fetched as it's first built;
        // what each further place needs is asked for when it's given (`GameKit.notReady`).
        setup: .none,
        startsAt: [.mac], hostedByLamp: true, showsPage: { GameKit.engine($0) == .web }, changesAreWeb: { GameKit.engine($0) == .web }, installFolder: "Games", takesPhones: true)
}

extension Language {
    static let game = Language(name: "game", code: "the game's page in Web/", leftover: "the game's files in Web/") {
        "Write the app again as a game in Web/ against Lamp's game runtime (the scaffold is there), drawn as the game skill and the 2d-game or 3d-game skill say (read them first), reading \($0) for what it does, then delete \($1) with delete_file. "
    }
}
