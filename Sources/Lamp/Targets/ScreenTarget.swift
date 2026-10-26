import Foundation

extension Platform {
    /// A screen: a page shown full screen and glanced at from across a room (`ScreenKit`). Its home is the Mac; every
    /// other place a page goes (`Places.pagePlaces`: an iPhone or iPad, an Android tablet, photo frame or TV, a Samsung
    /// or LG TV, an Xbox) is one it's given as well (`LampProject.places`), never another kind.
    static let screen = Platform(kind: "screen")
}

extension Target {
    static let screen = Target(
        // A page: wherever one of Lamp's web hosts is.
        platform: .screen, places: Places.pagePlaces,
        identity: Identity(name: "the screen", phrase: "a screen shown on the Mac, an iPad, an Android tablet, a TV or an Xbox", analytics: "screen",
                           made: { _, _ in "a screen" },
                           devices: Words(words: [("screen", "\"screen\" for a screen (where it's shown beside the Mac, any place a page goes, goes in `places`)",
                                                   "\"screen\" for something shown full screen and glanced at")],
                                          hint: "[\"screen\"] for something shown full screen and glanced at from across a room rather than used up close: "
                                              + "a family calendar or chore board, a photo frame or album slideshow, a dashboard, a scoreboard, a clock, "
                                              + "the day's weather, with where else it's shown in \"places\": \"tv\" for their Samsung or LG TV, "
                                              + "\"android-tv\" for a Google TV, Android TV or Fire TV, \"ipad\" for an iPad on a stand, "
                                              + "\"android\" for an Android tablet or a photo frame that runs Android, "
                                              + "\"xbox-one\" for their Xbox. An app the person works in or plays is no screen",
                                          claims: { $0 == ["screen"] },
                                          alone: true),
                           tryOnHelp: { _ in "Where it's shown: this Mac, an iPhone or iPad, an Android tablet, photo frame or TV, a Samsung or LG TV, or your Xbox" },
                           place: { _ in .window }),
        guidance: Guidance(prompt: Agent.screenPrompt(for:),
                           changeRules: { _ in Agent.Rules.screenEdit + Agent.Rules.tvFrameworks + Agent.Rules.tvDesign + Agent.Rules.tvKeys + Agent.Rules.tvData + Agent.Rules.tvTry },
                           skills: { [] },
                           elsewhere: { _ in "- On the person's TV, iPad, Android tablet or Xbox: the same, while it's on this Mac's Wi‑Fi with Lamp open; away from it, no AI" }),
        recipe: Recipe(language: .web, fill: ScreenKit.fill, ownedFiles: ScreenKit.write(for:), support: ScreenKit.write(for:),
                       isMade: ScreenKit.isMade, scaffolded: { dir, _ in ScreenKit.isMade(dir) },
                       // Sources/ too: the Swift that answers the page's calls of the device is the agent's (Native.swift).
                       sources: { _ in [TVTemplate.webFolder, "Sources", "icon.json"] },
                       inputs: { _ in ScreenKit.stamp },
                       builtURL: { project in
                           project.onTV ? TVs.stagingFolder(for: project).appendingPathComponent("web/index.html")
                               : project.onDevice ? DeviceApps.packageURL(for: project)
                               : project.onAndroid ? GameAndroid.apk(project)
                               : project.dir.appendingPathComponent(project.onIOS ? "build/iOS/\(project.exe).app" : "build/\(project.exe).app")
                       },
                       marker: ScreenKit.marker,
                       // Its folder holds a TV app's page and script: it's asked whether it's a screen first.
                       refines: .tv,
                       shareRefusal: "Lamp doesn't share screens yet."),
        part: Part(folder: "Screen", family: "screen", word: "screen", menu: ("Screen", "tv.inset.filled"), rules: { Agent.screenPrompt(part: $0, alone: $1) },
                   // How its places are given beside the wish's other apps, and how it reaches them.
                   wishRule: Agent.Rules.screenAmongApps) { dir, wish in
            AppFile.read(dir.appendingPathComponent(ScreenKit.marker), inFolder: wish, last: 1) != nil
        },
        setup: .none,
        startsAt: [.mac], hostedByLamp: true, showsPage: { _ in true }, installFolder: "Screens")
}
