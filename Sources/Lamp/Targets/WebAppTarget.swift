import Foundation

extension Platform {
    /// A web app: an app made with web (`make_app_for`'s `kind` "app", `made` "web"), a page in `Web/` in Lamp's common
    /// app around a page (`ScreenKit`, `ScreenKit.webAppPage`), at home on the Mac and shown wherever else a page goes.
    /// It's what a new web app is; a screen made before stays a screen (`Platform.screen`).
    static let webApp = Platform(kind: "web-app")
}

extension Target {
    static let webApp = Target(
        // A page: wherever one of Lamp's web hosts is.
        platform: .webApp, places: Places.pagePlaces,
        identity: Identity(name: "the web app", phrase: "a web app shown on the Mac, an iPhone or iPad, an Android device, a TV or an Xbox", analytics: "web-app",
                           made: { _, _ in "a web app" },
                           // No word of its own: it's what `make_app_for` makes of an app made with web, never what a list of
                           // devices names.
                           devices: Words(words: [], hint: nil, claims: { _ in false }, alone: true),
                           tryOnHelp: { _ in "Where it's shown: this Mac, an iPhone or iPad, an Android device, a Samsung or LG TV, or your Xbox" },
                           place: { _ in .window }),
        guidance: Guidance(prompt: Agent.screenPrompt(for:),
                           // The web app's own design rule, not a TV's 1920x1080, with the shapes read off the request's device line: an app is
                           // given its kind before `make_app_for` sets its places, so its places here may not be the ones asked for.
                           changeRules: { _ in Agent.Rules.screenEdit + Agent.Rules.tvFrameworks + Agent.Rules.screenDesign(nil) + Agent.Rules.tvKeys + Agent.Rules.tvData + Agent.Rules.tvTry },
                           skills: { [] },
                           elsewhere: { _ in "- On the person's TV, iPad, Android device or Xbox: the same, while it's on this Mac's Wi‑Fi with Lamp open; away from it, no AI" }),
        recipe: Recipe(language: .web, fill: ScreenKit.fill, ownedFiles: ScreenKit.write(for:), support: ScreenKit.write(for:),
                       isMade: ScreenKit.isWebAppMade, scaffolded: { dir, _ in ScreenKit.isWebAppMade(dir) },
                       // Sources/ too: the Swift that answers the page's calls of the device is the agent's (Native.swift).
                       sources: { _ in [TVTemplate.webFolder, "Sources", "icon.json"] },
                       inputs: { ScreenKit.stamp + GameKit.playerInput(for: $0) },
                       builtURL: { project in
                           project.onTV ? TVs.stagingFolder(for: project).appendingPathComponent("web/index.html")
                               : project.onDevice ? DeviceApps.packageURL(for: project)
                               : project.onAndroid ? GameAndroid.apk(project)
                               : project.dir.appendingPathComponent(project.onIOS ? "build/iOS/\(project.exe).app" : "build/\(project.exe).app")
                       },
                       marker: ScreenKit.webAppPage.marker,
                       // Its folder holds a TV app's page and script: it's asked whether it's a web app first.
                       refines: .tv,
                       // Its page and the Swift beside it travel in a shared file (`ScreenFiles`).
                       shareRefusal: nil),
        part: Part(folder: "WebApp", family: "web-app", word: "web-app", menu: ("Web App", "globe"), rules: { Agent.screenPrompt(part: $0, alone: $1) },
                   // How its places are given beside the wish's other apps, and how it reaches them.
                   wishRule: Agent.Rules.screenAmongApps) { dir, wish in
            AppFile.read(dir.appendingPathComponent(ScreenKit.webAppPage.marker), inFolder: wish, last: 1) != nil
        },
        setup: .none,
        startsAt: [.mac], hostedByLamp: true, showsPage: { _ in true }, installFolder: "Web Apps", looksInTVPreview: true)
}
