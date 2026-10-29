import Foundation

extension Platform {
    /// A screen, as Lamp once made them (`ScreenKit`): a web app, kept for the screens already made, which load, build,
    /// restore and keep their saved data as they did. Nothing chooses it for a new app: it has no device words, and
    /// `make_app_for` only ever keeps a wish's own screen (`AppKinds.target`).
    static let screen = Platform(kind: "screen")
}

extension Target {
    static let screen = Target(
        // A page: wherever one of Lamp's web hosts is.
        platform: .screen, places: Places.pagePlaces,
        identity: Identity(name: "the screen", phrase: "a web app shown full screen on the Mac, an iPad, an Android tablet, a TV or an Xbox", analytics: "screen",
                           made: { _, _ in "a screen" },
                           // No word of its own: a new app is never made a screen.
                           devices: Words(words: [], hint: nil, claims: { _ in false }, alone: true),
                           tryOnHelp: { _ in "Where it's shown: this Mac, an iPhone or iPad, an Android tablet, photo frame or TV, a Samsung or LG TV, or your Xbox" },
                           place: { _ in .window }),
        guidance: Guidance(prompt: Agent.screenPrompt(for:),
                           // The web app's own design rule, not a TV's 1920x1080, with the shapes read off the request's device line: an app is
                           // given its kind before `make_app_for` sets its places, so its places here may not be the ones asked for.
                           changeRules: { _ in Agent.Rules.screenEdit + Agent.Rules.tvFrameworks + Agent.Rules.screenDesign(nil) + Agent.Rules.tvKeys + Agent.Rules.tvData + Agent.Rules.screenTry },
                           skills: { [] },
                           elsewhere: { _ in "- On the person's TV, iPad, Android tablet, photo frame or Google TV, or Xbox: the same, while it's on this Mac's Wi‑Fi with Lamp open; away from it, no AI" }),
        recipe: Recipe(language: .web, fill: ScreenKit.fill, ownedFiles: ScreenKit.write(for:), support: ScreenKit.write(for:),
                       isMade: ScreenKit.isMade, scaffolded: { dir, _ in ScreenKit.isMade(dir) },
                       // Sources/ too: the Swift that answers the page's calls of the device is the agent's (Native.swift).
                       sources: { _ in [TVTemplate.webFolder, "Sources", "icon.json"] },
                       inputs: { ScreenKit.stamp + GameKit.playerInput(for: $0) },
                       builtURL: { project in
                           project.onTV ? TVs.stagingFolder(for: project).appendingPathComponent("web/index.html")
                               : project.onDevice ? DeviceApps.packageURL(for: project)
                               : project.onAndroid ? GameAndroid.apk(project)
                               : project.dir.appendingPathComponent(project.onIOS ? "build/iOS/\(project.exe).app" : "build/\(project.exe).app")
                       },
                       marker: ScreenKit.marker,
                       // Its folder holds a TV app's page and script: it's asked whether it's a screen first.
                       refines: .tv,
                       // Its page and the Swift beside it travel in a shared file (`ScreenFiles`); the copy is a screen too.
                       shareRefusal: nil),
        part: Part(folder: "Screen", family: "screen", word: "screen", menu: ("Screen", "tv.inset.filled"), rules: { Agent.screenPrompt(part: $0, alone: $1) },
                   // How its places are given beside the wish's other apps, and how it reaches them.
                   wishRule: Agent.Rules.screenAmongApps) { dir, wish in
            AppFile.read(dir.appendingPathComponent(ScreenKit.marker), inFolder: wish, last: 1) != nil
        },
        setup: .none,
        startsAt: [.mac], hostedByLamp: true, showsPage: { _ in true }, installFolder: "Screens", looksInTVPreview: true)
}
